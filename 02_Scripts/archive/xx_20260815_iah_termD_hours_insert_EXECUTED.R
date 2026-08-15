suppressPackageStartupMessages({
  library(duckdb); library(DBI); library(glue); library(dplyr)
})

# IAH Terminal D split-shift hours, confirmed both by fly2houston.com/iah/security/
# (refetched 2026-08-15, unchanged since 2026-07-14 discovery) AND by a 42-day
# tsa_wait_times data-first check on the General lane: hours with LITERAL zero
# variance (n_distinct_vals=1, sd=0.00, always exactly the 5-min floor value)
# vs hours with real spread (many distinct values, sd>0) line up almost exactly
# with the posted windows once `time` is correctly converted UTC -> America/Chicago
# (the raw `datetime` column is UTC-naive, same convention as xx_build_summary_DB.R
# -- an initial pass using `datetime` directly was off by IAH's 5hr UTC offset and
# wrongly looked like continuous 24/7 coverage; recomputing off `time` with a
# proper force_tz("UTC") -> with_tz("America/Chicago") resolved it).
#   Sun/Mon/Wed/Fri: 07:00-11:30 and 16:30-20:00 (closing/opening transitions
#     inside hours 11 and 16 showed ~85-97% floor rate, matching a :30 boundary)
#   Tue/Thu/Sat: continuous 07:00-20:00 (no literal zero-variance block during
#     the day, just natural lower-traffic dips)
# No PreCheck lane exists at Terminal D (wait_time_pre_check 100% NA for the
# full window) -- left NA on every row, same "batch-wide NA = no restriction /
# lane doesn't apply" convention as JFK Terminal 1's window_seq=2 row.
# This replaces the single continuous 07:00-22:30 placeholder row set during
# the 2026-07-14 JSON migration (that row was only ever an "outer bound" fix
# for an evening data-loss bug, not a real reflection of the midday gap).

base_date <- as.Date(Sys.Date())
mk <- function(time) as.POSIXct(paste(base_date, time), tz = "UTC")
entry_ts <- as.POSIXct(paste(Sys.Date(), format(Sys.time(), "%H:%M:%S")), tz = "UTC")

rows <- tribble(
  ~window_seq, ~day_of_week, ~open_time_gen,  ~close_time_gen,

  1L,          "Sun",        mk("07:00:00"),  mk("11:30:00"),
  2L,          "Sun",        mk("16:30:00"),  mk("20:00:00"),
  3L,          "Mon",        mk("07:00:00"),  mk("11:30:00"),
  4L,          "Mon",        mk("16:30:00"),  mk("20:00:00"),
  5L,          "Wed",        mk("07:00:00"),  mk("11:30:00"),
  6L,          "Wed",        mk("16:30:00"),  mk("20:00:00"),
  7L,          "Fri",        mk("07:00:00"),  mk("11:30:00"),
  8L,          "Fri",        mk("16:30:00"),  mk("20:00:00"),
  9L,          "Tue",        mk("07:00:00"),  mk("20:00:00"),
  10L,         "Thu",        mk("07:00:00"),  mk("20:00:00"),
  11L,         "Sat",        mk("07:00:00"),  mk("20:00:00"),
) |>
  mutate(
    airport             = "IAH",
    timezone            = "America/Chicago",
    checkpoint          = "IAH Terminal D",
    open_time_prechk    = as.POSIXct(NA),
    close_time_prechk   = as.POSIXct(NA),
    open_time_clear     = as.POSIXct(NA),
    close_time_clear    = as.POSIXct(NA),
    entry_timestamp     = entry_ts,
    is_active           = TRUE
  ) |>
  select(airport, timezone, checkpoint, window_seq, day_of_week,
         open_time_gen, close_time_gen, open_time_prechk, close_time_prechk,
         open_time_clear, close_time_clear, entry_timestamp, is_active)

cat("---- Derived rows (dry run) ----\n")
print(as.data.frame(rows))

write_to <- function(host, disable_ssl) {
  con <- dbConnect(duckdb::duckdb())
  dbExecute(con, "INSTALL quack; LOAD quack;")
  attach_sql <- if (disable_ssl) {
    glue("ATTACH 'quack:{host}' AS remote_db (TYPE quack, TOKEN '{Sys.getenv('DUCKDB_QUACK_TOKEN')}', DISABLE_SSL true)")
  } else {
    glue("ATTACH 'quack:{host}' AS remote_db (TYPE quack, TOKEN '{Sys.getenv('DUCKDB_QUACK_TOKEN')}')")
  }
  dbExecute(con, attach_sql)
  dbExecute(con, "USE remote_db;")

  before <- dbGetQuery(con, "SELECT COUNT(*) n FROM airport_checkpoint_hours WHERE airport='IAH' AND checkpoint='IAH Terminal D'")$n
  dbAppendTable(con, "airport_checkpoint_hours", as.data.frame(rows))
  after <- dbGetQuery(con, "SELECT COUNT(*) n FROM airport_checkpoint_hours WHERE airport='IAH' AND checkpoint='IAH Terminal D'")$n
  cat(glue("{host}: {before} -> {after} IAH Terminal D rows"), "\n")

  dbDisconnect(con, shutdown = TRUE)
}

cat("\n---- Writing to desktop (localhost) ----\n")
write_to("localhost", disable_ssl = FALSE)

cat("\n---- Writing to Pi (192.168.1.207) ----\n")
write_to("192.168.1.207", disable_ssl = TRUE)
