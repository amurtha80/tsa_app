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
  filter(entry_timestamp == max(entry_timestamp)) |>
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

tsa_wait_time_summ <- tbl(con_source, "tsa_wait_times") |>
  collect() |>
  # `time` is a genuine UTC instant (DuckDB's TIMESTAMP_S column is naive;
  # the R driver drops tz on write). Force-tag UTC explicitly, then convert
  # to each row's true airport-local wall clock via the `timezone` column
  # before bucketing, so charts reflect airport-local time of day.
  mutate(time = lubridate::force_tz(time, tzone = "UTC")) |>
  # Keep rolling 365-day window from most recent scraped date
  filter(date >= max(date, na.rm = TRUE) - 365) |>
  group_by(timezone) |>
  mutate(time_local = lubridate::with_tz(time, tzone = dplyr::first(timezone))) |>
  ungroup() |>
  mutate(checkpoint = toupper(checkpoint)) |>
  left_join(hours_checkpoint, by = c("airport", "checkpoint")) |>
  mutate(
    time_of_day = hms::as_hms(time_local),
    weekday     = lubridate::wday(time_local, label = TRUE, abbr = TRUE),
    weekday_chr = as.character(weekday),
    # is_active FALSE means the checkpoint itself is out of service for an
    # indefinite/unknown duration (e.g. an airline shutdown vacating a
    # terminal), not just closed for the day -- overrides the hours-of-day
    # check entirely rather than participating in is_open_lane().
    wait_time           = if_else(coalesce(is_active, TRUE) &
                                     purrr::pmap_lgl(list(time_of_day, weekday_chr, windows_gen), is_open_lane),
                                   wait_time, NA_real_),
    wait_time_pre_check = if_else(coalesce(is_active, TRUE) &
                                     purrr::pmap_lgl(list(time_of_day, weekday_chr, windows_prechk), is_open_lane),
                                   wait_time_pre_check, NA_real_),
    wait_time_clear     = if_else(coalesce(is_active, TRUE) &
                                     purrr::pmap_lgl(list(time_of_day, weekday_chr, windows_clear), is_open_lane),
                                   wait_time_clear, NA_real_)
  ) |>
  mutate(
    bucket_time = hms::as_hms(lubridate::ceiling_date(time_local, "15 mins"))
  ) |>
  group_by(airport, checkpoint, weekday, bucket_time) |>
  summarize(
    avg_time_std          = ceiling(mean(wait_time,          na.rm = TRUE)),
    max_time_std          = max(wait_time,                   na.rm = TRUE),
    avg_time_tsa_precheck = ceiling(mean(wait_time_pre_check, na.rm = TRUE)),
    max_time_tsa_precheck = max(wait_time_pre_check,         na.rm = TRUE),
    avg_time_clear        = ceiling(mean(wait_time_clear,    na.rm = TRUE)),
    max_time_clear        = max(wait_time_clear,             na.rm = TRUE),
    # Constant per (airport, checkpoint) via the left_join above -- carried
    # through so app.R can distinguish "closed right now" from "checkpoint
    # out of service indefinitely" without a second lookup.
    is_active              = dplyr::first(coalesce(is_active, TRUE)),
    .groups = "drop"
  ) |>
  # Inf/-Inf from max/mean over all-NA groups → replace with NA
  mutate(across(
    c(avg_time_std, max_time_std,
      avg_time_tsa_precheck, max_time_tsa_precheck,
      avg_time_clear, max_time_clear),
    \(x) if_else(is.infinite(x) | is.nan(x), NA_real_, as.double(x))
  )) |>
  # Store bucket_time as "HH:MM:SS" character — hms writes as raw seconds in
  # DuckDB which breaks comparisons on read. Parsed back to hms in app.R.
  mutate(bucket_time = as.character(bucket_time))

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
