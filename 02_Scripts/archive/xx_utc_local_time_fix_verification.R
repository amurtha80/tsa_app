# xx_utc_local_time_fix_verification.R ----
# Debugging/verification queries run 2026-07-12 while diagnosing and fixing
# the "datetime/time stored as UTC, not airport-local" data quality bug (see
# CHANGELOG.md 2026-07-12 entry, fix landed in xx_build_summary_DB.R).
# Archived as a record of how the fix was verified, not meant to be re-run
# as part of any pipeline. Requires the Quack server (zz_database.R) running.


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

foo(c("duckdb", "DBI", "dplyr", "hms", "lubridate", "glue"))

rm(foo)


# Connect ----
# Read-only Quack connection -- this script only ever SELECTs.

con <- dbConnect(duckdb::duckdb())
dbExecute(con, "INSTALL quack; LOAD quack;")
dbExecute(con, glue(
  "ATTACH 'quack:localhost' AS remote_db (TYPE quack, TOKEN '{Sys.getenv('DUCKDB_QUACK_TOKEN')}')"
))
dbExecute(con, "USE remote_db;")


# Check 1: confirm `time` round-trips as a genuine UTC instant ----
# Expect attr(result$time, "tzone") == "UTC", and the raw clock values here
# should NOT match true airport-local wall-clock time at query time.

result <- dbGetQuery(con, "
  SELECT airport, timezone, time, date
  FROM tsa_wait_times
  WHERE airport IN ('DFW','LAX','ATL')
  ORDER BY time DESC
  LIMIT 15
")
print(result)
str(result$time)
attr(result$time, "tzone")


# Check 2: confirm CLT/JFK's fixed-offset 'EST'-literal bug (datetime/date
# columns only) never touched `timezone` (or by extension `time`) ----
# Expect only 'America/New_York', never 'EST'.

dbGetQuery(con, "SELECT DISTINCT timezone FROM tsa_wait_times WHERE airport IN ('CLT','JFK')")

# Confirms: (1) time is a true UTC instant, not mislabeled local time, and (2) the CLT/JFK EST-literal bug never touched time/timezone. If either check fails, stop and re-diagnose before proceeding — do not fix piecemeal per the todo item's own instruction.
# 
#  Implementation
# 
#  Single file change, once historical-data assumption is confirmed: 02_Scripts/xx_build_summary_DB.R, lines 63-71.
# 
#  Current:
tsa_wait_time_summ <- tbl(con, "tsa_wait_times") |>
  collect() |>
  filter(date >= max(date, na.rm = TRUE) - 365) |>
  mutate(
    checkpoint  = toupper(checkpoint),
    bucket_time = hms::as_hms(lubridate::ceiling_date(time, "15 mins")),
    weekday     = lubridate::wday(time, label = TRUE, abbr = TRUE)
  ) |>
  group_by(airport, checkpoint, weekday, bucket_time) |>
  summarize() |>
  head(n=30)

# Change to convert time (UTC) to each row's true local wall clock via the existing timezone column, before deriving bucket_time/weekday:
tsa_wait_time_summ_new <- tbl(con, "tsa_wait_times") |>
  collect() |>
  # `time` is a genuine UTC instant (DuckDB's TIMESTAMP_S column is naive;
  # the R driver drops tz on write). Force-tag UTC explicitly, then convert
  # to each row's true airport-local wall clock via the `timezone` column.
  mutate(time = lubridate::force_tz(time, tzone = "UTC")) |>
  filter(date >= max(date, na.rm = TRUE) - 365) |>
  group_by(timezone) |>
  mutate(time_local = lubridate::with_tz(time, tzone = dplyr::first(timezone))) |>
  ungroup() |>
  mutate(
    checkpoint  = toupper(checkpoint),
    bucket_time = hms::as_hms(lubridate::ceiling_date(time_local, "15 mins")),
    weekday     = lubridate::wday(time_local, label = TRUE, abbr = TRUE)
  ) |>
  group_by(airport, checkpoint, weekday, bucket_time) |>
  summarize() |>
  head(n=30) # unchanged


# Check 3: value-level before/after comparison for one airport/checkpoint ----
# Confirms the fix actually moves wait-time values into plausible daytime
# buckets, not just relabeling identical bucket keys. ATL DOMESTIC LOWER
# NORTH / Sunday: old (buggy) peak landed at noon-2pm (implausible for a
# security line); new (fixed) peak lands at 7:30-9:00am (plausible rush).

old <- tbl(con, "tsa_wait_times") |>
  collect() |>
  filter(airport == "ATL", checkpoint == "DOMESTIC LOWER NORTH") |>
  mutate(
    bucket_time = hms::as_hms(lubridate::ceiling_date(time, "15 mins")),
    weekday     = lubridate::wday(time, label = TRUE, abbr = TRUE)
  ) |>
  filter(weekday == "Sun") |>
  group_by(bucket_time) |>
  summarize(avg_wait = ceiling(mean(wait_time, na.rm = TRUE)), .groups = "drop") |>
  arrange(desc(avg_wait))

new <- tbl(con, "tsa_wait_times") |>
  collect() |>
  filter(airport == "ATL", checkpoint == "DOMESTIC LOWER NORTH") |>
  mutate(time = lubridate::force_tz(time, tzone = "UTC")) |>
  mutate(time_local = lubridate::with_tz(time, tzone = "America/New_York")) |>
  mutate(
    bucket_time = hms::as_hms(lubridate::ceiling_date(time_local, "15 mins")),
    weekday     = lubridate::wday(time_local, label = TRUE, abbr = TRUE)
  ) |>
  filter(weekday == "Sun") |>
  group_by(bucket_time) |>
  summarize(avg_wait = ceiling(mean(wait_time, na.rm = TRUE)), .groups = "drop") |>
  arrange(desc(avg_wait))

print(old, n = 24)
print(new, n = 24)


# Check 4: DST-transition correctness, Eastern time (ATL) ----
# Confirms with_tz() applies the correct historical DST rule per date, not
# a fixed offset. applied_off should read -5 (EST) before 2025-03-09,
# flip to -4 (EDT) on/after 2025-03-09 (the actual spring-forward date).

dst_check_atl <- tbl(con, "tsa_wait_times") |>
  collect() |>
  filter(airport == "ATL") |>
  mutate(time = lubridate::force_tz(time, tzone = "UTC")) |>
  filter(
    (date >= as.Date("2024-11-01") & date <= as.Date("2024-11-05")) |
    (date >= as.Date("2025-03-07") & date <= as.Date("2025-03-11"))
  ) |>
  distinct(date, .keep_all = TRUE) |>
  mutate(
    time_local  = lubridate::with_tz(time, tzone = "America/New_York"),
    applied_off = as.numeric(
      difftime(
        as.POSIXct(format(time_local), tz = "UTC"),
        time,
        units = "hours"
      )
    )
  ) |>
  select(date, time, time_local, applied_off) |>
  arrange(date)

print(dst_check_atl)


# Check 5: DST-transition correctness, Pacific time (PDX) ----
# Same check as Check 4, different airport/zone -- confirms the fix isn't
# Eastern-time-specific. applied_off should read -8 (PST) before
# 2025-03-09, flip to -7 (PDT) on/after 2025-03-09.

dst_check_pdx <- tbl(con, "tsa_wait_times") |>
  collect() |>
  filter(airport == "PDX") |>
  mutate(time = lubridate::force_tz(time, tzone = "UTC")) |>
  filter(
    (date >= as.Date("2024-11-01") & date <= as.Date("2024-11-05")) |
    (date >= as.Date("2025-03-07") & date <= as.Date("2025-03-11"))
  ) |>
  distinct(date, .keep_all = TRUE) |>
  mutate(
    time_local  = lubridate::with_tz(time, tzone = "America/Los_Angeles"),
    applied_off = as.numeric(
      difftime(
        as.POSIXct(format(time_local), tz = "UTC"),
        time,
        units = "hours"
      )
    )
  ) |>
  select(date, time, time_local, applied_off) |>
  arrange(date)

print(dst_check_pdx)


# Cleanup ----

rm(result, old, new, dst_check_atl, dst_check_pdx)
dbDisconnect(con, shutdown = TRUE)
rm(con)
