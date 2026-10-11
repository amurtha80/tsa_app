sink(here::here("runlog_appdata_xfer.txt"), append = TRUE, type = "output")

# xx_build_summary_db.R ----
# Overnight extraction script: reads tsa_app.duckdb, aggregates wait time data
# into 15-minute buckets by airport / checkpoint / weekday, writes the
# summary table to tsa_app_summ.duckdb, exports a parquet copy, and pushes
# the parquet to S3 for EC2 to pull on restart.
#
# Schedule: Windows Task Scheduler, nightly at 2:00 AM
# Runtime: seconds (single aggregation query over ~365 days of rows)
# Inputs:  01_Data/tsa_app.duckdb        (read-only)
# Outputs: 01_Data/tsa_app_summ.duckdb   (write — created on first run)
#          01_Data/tsa_app_summ.parquet   (write — overwritten each run)
#          S3: see S3 Push section below  (requires paws + AWS credentials)


# Package Management ----

foo <- function(x) {
  for (i in x) {
    suppressWarnings(suppressPackageStartupMessages(
      if (!require(i, character.only = TRUE, warn.conflicts = FALSE, quietly = TRUE)) {
        install.packages(i, dependencies = TRUE, verbose = FALSE, quiet = TRUE,
                         repos = "https://cloud.r-project.org/")
        require(i, character.only = TRUE, warn.conflicts = FALSE, quietly = TRUE)
      }
    ))
  }
}

foo(c("duckdb", "DBI", "here", "dplyr", "hms", "lubridate", "glue",
      "nanoparquet", "purrr"))

rm(foo)
print(glue("packages loaded at ", format(Sys.time(), "%a %b %d %X %Y")))


# Paths ----

path_summ    <- here::here("01_Data", "tsa_app_summ.duckdb")
path_parquet <- here::here("01_Data", "tsa_app_summ.parquet")


# Connect ----

# tsa_app.duckdb is read via Quack -- zz_database.R must already be running
# as the Quack server. tsa_app_summ.duckdb is a separate file nothing else
# writes concurrently, so it keeps a direct connection.
con_source <- dbConnect(duckdb::duckdb())
dbExecute(con_source, "INSTALL quack; LOAD quack;")
dbExecute(con_source, glue(
  "ATTACH 'quack:localhost' AS remote_db (TYPE quack, TOKEN '{Sys.getenv('DUCKDB_QUACK_TOKEN')}')"
))
dbExecute(con_source, "USE remote_db;")
dbExecute(con_source, "INSTALL icu; LOAD icu;")   # needed for timezone(); not bundled in the R duckdb build

con_summ   <- dbConnect(duckdb::duckdb(), dbdir = path_summ,   read_only = FALSE)

print(glue("******-- Start summary build ", format(Sys.time(), "%a %b %d %X %Y"), " --******"))


# Extract and Aggregate ----

# Operating hours lookup: airport_checkpoint_hours' TIMESTAMP_S date part is
# just an entry-date anchor, not meaningful for comparison -- reduce each
# open/close pair to a time-of-day plus a "wraps past midnight" flag (true
# when close's date is one day after open's, e.g. DEN West 3:30 AM - 1:00 AM).
# NULL open/close means "no known restriction" -- never filters that lane.
#
# Table is append-only: a correction writes an entire new *batch* of rows
# (one row per open/close window, sharing one new entry_timestamp) rather
# than updating in place -- a checkpoint needs 1..N window rows to represent
# a plain single-window day, a same-day split shift (window_seq 1, 2, ...),
# or a day-of-week-varying schedule (day_of_week set per row). Keep every
# row in the latest batch per (airport, checkpoint), not just one.
hours_lookup <- tbl(con_source, "airport_checkpoint_hours") |>
  collect() |>
  mutate(checkpoint = toupper(checkpoint)) |>
  group_by(airport, checkpoint) |>
  # plain `== max(entry_timestamp)` silently drops the whole group once any
  # correction row is added to a checkpoint that previously had no hours data
  # (NA vs. real timestamp both compare to NA and get filtered out) -- na.rm
  # picks the real latest row, with the all(is.na(...)) branch preserving
  # single-row NA-only groups (checkpoints with no hours restriction at all).
  filter(entry_timestamp == max(entry_timestamp, na.rm = TRUE) | all(is.na(entry_timestamp))) |>
  ungroup() |>
  mutate(
    open_gen_tod      = hms::as_hms(open_time_gen),
    close_gen_tod      = hms::as_hms(close_time_gen),
    wraps_gen          = as.Date(close_time_gen) > as.Date(open_time_gen),
    open_prechk_tod   = hms::as_hms(open_time_prechk),
    close_prechk_tod   = hms::as_hms(close_time_prechk),
    wraps_prechk       = as.Date(close_time_prechk) > as.Date(open_time_prechk),
    open_clear_tod    = hms::as_hms(open_time_clear),
    close_clear_tod    = hms::as_hms(close_time_clear),
    wraps_clear        = as.Date(close_time_clear) > as.Date(open_time_clear)
  )

checkpoint_meta <- hours_lookup |>
  group_by(airport, checkpoint) |>
  summarise(is_active = dplyr::first(coalesce(is_active, TRUE)), .groups = "drop")

# Nest each lane's window rows (dropping rows where that lane has no
# open/close defined) into one list-column per checkpoint. An empty/NULL
# list means "no known restriction" for that lane -- same meaning as the old
# NULL-pair case, just resolved at the batch level instead of per-row, since
# a checkpoint's other window rows may legitimately leave one lane NA (e.g.
# a second PreCheck-only window doesn't also restate the general-lane pair).
windows_gen <- hours_lookup |>
  filter(!is.na(open_gen_tod), !is.na(close_gen_tod)) |>
  select(airport, checkpoint, day_of_week,
         open_tod = open_gen_tod, close_tod = close_gen_tod, wraps = wraps_gen) |>
  group_by(airport, checkpoint) |>
  summarise(windows_gen = list(pick(day_of_week, open_tod, close_tod, wraps)), .groups = "drop")

windows_prechk <- hours_lookup |>
  filter(!is.na(open_prechk_tod), !is.na(close_prechk_tod)) |>
  select(airport, checkpoint, day_of_week,
         open_tod = open_prechk_tod, close_tod = close_prechk_tod, wraps = wraps_prechk) |>
  group_by(airport, checkpoint) |>
  summarise(windows_prechk = list(pick(day_of_week, open_tod, close_tod, wraps)), .groups = "drop")

windows_clear <- hours_lookup |>
  filter(!is.na(open_clear_tod), !is.na(close_clear_tod)) |>
  select(airport, checkpoint, day_of_week,
         open_tod = open_clear_tod, close_tod = close_clear_tod, wraps = wraps_clear) |>
  group_by(airport, checkpoint) |>
  summarise(windows_clear = list(pick(day_of_week, open_tod, close_tod, wraps)), .groups = "drop")

hours_checkpoint <- checkpoint_meta |>
  left_join(windows_gen,    by = c("airport", "checkpoint")) |>
  left_join(windows_prechk, by = c("airport", "checkpoint")) |>
  left_join(windows_clear,  by = c("airport", "checkpoint"))

# Multi-window, day-of-week-aware hours gate. `windows` is a tibble of
# (day_of_week, open_tod, close_tod, wraps) rows for one (airport,
# checkpoint, lane) batch, or NULL when that lane has no defined
# restriction. TRUE if `windows` is NULL/empty, or any window whose
# day_of_week is NA (applies every day) or matches `wd` contains `tod`.
is_open_lane <- function(tod, wd, windows) {
  if (is.null(windows) || nrow(windows) == 0) return(TRUE)
  any(
    (is.na(windows$day_of_week) | windows$day_of_week == wd) &
      dplyr::if_else(
        windows$wraps,
        tod >= windows$open_tod | tod <= windows$close_tod,
        tod >= windows$open_tod & tod <= windows$close_tod
      )
  )
}

# Extract, convert to each airport's OWN local time, filter to 365 days, bucket -- all in DuckDB.
# timezone(<per-row tz>, ...) is evaluated per row, so every airport gets its own local clock
# (the previous group_by(timezone)/with_tz/ungroup left one tzone attr = America/Chicago for all rows).
# Quack rejects multiple streaming scans in one statement, so max(date) is fetched separately.
max_date <- as.character(dbGetQuery(con_source, "SELECT max(date) FROM tsa_wait_times")[[1]])

dbExecute(con_source, glue("
  CREATE OR REPLACE TEMP TABLE wt AS
  WITH base AS (
    SELECT airport, upper(checkpoint) AS checkpoint, date,
           wait_time, wait_time_pre_check, wait_time_clear,
           timezone(timezone, \"time\"::TIMESTAMP AT TIME ZONE 'UTC') AS tl,
           \"time\"::TIMESTAMP AS u, timezone AS tzname
    FROM tsa_wait_times
    WHERE date >= DATE '{max_date}' - 365
  )
  SELECT airport, checkpoint,
         strftime(tl, '%a') AS weekday,
         (hour(tl) * 3600 + minute(tl) * 60 + second(tl))::INTEGER AS tod_s,
         -- ceil to 15 min on the UTC instant, then convert to local: matches lubridate::ceiling_date on a
         -- tz-aware POSIXct across DST gaps (01:55 EST on spring-forward day rolls to 03:00 EDT, not 02:00)
         strftime(timezone(tzname, (CASE WHEN u = time_bucket(INTERVAL 15 MINUTE, u)
                                         THEN u ELSE time_bucket(INTERVAL 15 MINUTE, u) + INTERVAL 15 MINUTE END) AT TIME ZONE 'UTC'),
                  '%H:%M:%S') AS bucket_time,
         wait_time, wait_time_pre_check, wait_time_clear
  FROM base
"))

# Hours-gate inputs: small tables derived from hours_lookup above.
dbWriteTable(con_source, "meta",
  checkpoint_meta |> transmute(airport, checkpoint, is_active = coalesce(is_active, TRUE)),
  temporary = TRUE, overwrite = TRUE)
win <- bind_rows(
  hours_lookup |> filter(!is.na(open_gen_tod),    !is.na(close_gen_tod))    |>
    transmute(lane = "gen", airport, checkpoint, day_of_week, open_s = as.numeric(open_gen_tod),    close_s = as.numeric(close_gen_tod),    wraps = wraps_gen),
  hours_lookup |> filter(!is.na(open_prechk_tod), !is.na(close_prechk_tod)) |>
    transmute(lane = "pre", airport, checkpoint, day_of_week, open_s = as.numeric(open_prechk_tod), close_s = as.numeric(close_prechk_tod), wraps = wraps_prechk),
  hours_lookup |> filter(!is.na(open_clear_tod),  !is.na(close_clear_tod))  |>
    transmute(lane = "clr", airport, checkpoint, day_of_week, open_s = as.numeric(open_clear_tod),  close_s = as.numeric(close_clear_tod),  wraps = wraps_clear)
)
dbWriteTable(con_source, "win", win, temporary = TRUE, overwrite = TRUE)

# Hours gate, evaluated once per distinct (airport, checkpoint, weekday, time-of-day).
# Same semantics as the old is_open_lane(): no windows for the lane => open; else open if any window
# (day_of_week NA = every day, or equal to weekday) contains the time of day (wrap-past-midnight aware).
# is_active FALSE closes the lane outright.
lane_sql <- function(L, out) glue("
  (coalesce(m.is_active, TRUE) AND
   CASE WHEN NOT EXISTS (SELECT 1 FROM win w WHERE w.lane = '{L}' AND w.airport = c.airport AND w.checkpoint = c.checkpoint)
        THEN TRUE
        ELSE EXISTS (SELECT 1 FROM win w
                     WHERE w.lane = '{L}' AND w.airport = c.airport AND w.checkpoint = c.checkpoint
                       AND (w.day_of_week IS NULL OR w.day_of_week = c.weekday)
                       AND CASE WHEN w.wraps THEN (c.tod_s >= w.open_s OR c.tod_s <= w.close_s)
                                ELSE (c.tod_s >= w.open_s AND c.tod_s <= w.close_s) END)
   END) AS {out}")
dbExecute(con_source, glue("
  CREATE OR REPLACE TEMP TABLE gate AS
  SELECT c.airport, c.checkpoint, c.weekday, c.tod_s,
         {lane_sql('gen', 'g_gen')}, {lane_sql('pre', 'g_pre')}, {lane_sql('clr', 'g_clr')}
  FROM (SELECT DISTINCT airport, checkpoint, weekday, tod_s FROM wt) c
  LEFT JOIN meta m USING (airport, checkpoint)
"))

# All-NA group => NULL (was Inf/-Inf/NaN -> NA); ceiling(mean) and max as double.
tsa_wait_time_summ <- dbGetQuery(con_source, "
  SELECT w.airport, w.checkpoint, w.weekday, w.bucket_time,
         ceil(avg(CASE WHEN g.g_gen THEN w.wait_time END))::DOUBLE            AS avg_time_std,
         max(CASE WHEN g.g_gen THEN w.wait_time END)::DOUBLE                  AS max_time_std,
         ceil(avg(CASE WHEN g.g_pre THEN w.wait_time_pre_check END))::DOUBLE  AS avg_time_tsa_precheck,
         max(CASE WHEN g.g_pre THEN w.wait_time_pre_check END)::DOUBLE        AS max_time_tsa_precheck,
         ceil(avg(CASE WHEN g.g_clr THEN w.wait_time_clear END))::DOUBLE      AS avg_time_clear,
         max(CASE WHEN g.g_clr THEN w.wait_time_clear END)::DOUBLE            AS max_time_clear,
         any_value(coalesce(m.is_active, TRUE))                               AS is_active
  FROM wt w
  JOIN gate g USING (airport, checkpoint, weekday, tod_s)
  LEFT JOIN meta m USING (airport, checkpoint)
  GROUP BY w.airport, w.checkpoint, w.weekday, w.bucket_time")
# weekday stays an ordered factor (Sun < ... < Sat), as before
tsa_wait_time_summ$weekday <- factor(tsa_wait_time_summ$weekday,
  levels = c("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"), ordered = TRUE)

print(glue("{nrow(tsa_wait_time_summ)} rows aggregated"))


# Write Summary Table ----
# overwrite = TRUE so each nightly run refreshes the full table

dbWriteTable(con_summ, "tsa_wait_time_summ", tsa_wait_time_summ, overwrite = TRUE)

print(glue("{nrow(tsa_wait_time_summ)} rows written to tsa_wait_time_summ"))
print(glue("******-- Summary build complete ", format(Sys.time(), "%a %b %d %X %Y"), " --******"))


# Write Parquet ----
# Parquet is the file format read by the Shiny app on EC2.
# bucket_time stays as "HH:MM:SS" character — filter key, not display value.
# Display format (12-hour) is applied at render time in app_sidebar.R.

nanoparquet::write_parquet(tsa_wait_time_summ, path_parquet)

print(glue("{nrow(tsa_wait_time_summ)} rows written to tsa_app_summ.parquet at ",
           format(Sys.time(), "%a %b %d %X %Y")))


# S3 Push ----
# AWS credentials must be configured on this machine (IAM role, env vars,
# or ~/.aws/credentials). paws picks them up automatically.
# paws.storage is installed here rather than via foo() above to avoid a known
# conflict with glue 1.8.0 when loaded via require() at script startup.
#
# Use paws.storage::s3() directly rather than the bare paws meta-package --
# paws re-exports every AWS service's constructor, so calling paws::s3()
# forces R to resolve paws's full Imports: (all ~14 service sub-packages)
# just to load the namespace, even though only S3 is ever used. This was
# silently triggering multi-hour from-source builds of the unused service
# packages on the Pi (see feedback_pi_prefer_prebuilt_packages / the paws
# meta-package trap). paws.storage exports s3() itself and only depends on
# paws.common.

if (!requireNamespace("paws.storage", quietly = TRUE)) {
  install.packages("paws.storage", repos = "https://cloud.r-project.org/")
}

tryCatch({
  s3 <- paws.storage::s3()
  s3$put_object(
    Bucket = "flyasap-app-data",
    Key    = "tsa_app_summ.parquet",
    Body   = path_parquet
  )
  print(glue("parquet pushed to S3 at ", format(Sys.time(), "%a %b %d %X %Y")))
}, error = function(e) {
  print(glue("ERROR: S3 push failed at ", format(Sys.time(), "%a %b %d %X %Y"),
             " — ", conditionMessage(e)))
})


# Cleanup ----

rm(tsa_wait_time_summ)
rm(path_summ)
rm(path_parquet)
rm(s3)

dbDisconnect(con_source, shutdown = TRUE)
dbDisconnect(con_summ,   shutdown = TRUE)

rm(con_source)
rm(con_summ)

sink()
gc()
