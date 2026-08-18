suppressPackageStartupMessages({
  library(duckdb); library(DBI); library(glue); library(dplyr)
})

# DTW McNamara Terminal hours, derived from 27 days of tsa_wait_times
# (America/Detroit -- DTW is Eastern Time, not Central).
# Posted site text claims "at least one checkpoint open 24/7" at McNamara, but
# live data shows a clean, repeatable 80-100% exact-zero-reading window every
# single night (>=75% zero-rate threshold), stronger/more consistent than
# Evans's signal -- contradicts posted text, trusted data per
# [[project_slc_hours_completion]] precedent.
# Evans intentionally left with NO rows (=24/7 unrestricted default) --
# its zero-readings were sparse/inconsistent, consistent with genuine
# low-traffic quiet periods rather than a real closure (user judgment call).
# Windows: Sun/Mon/Tue/Thu/Fri closed 22:00-04:00, Wed/Sat closed 21:00-04:00,
# floor/ceil 30-min buffer applied per SLC convention -> open 03:30, close
# 22:30 (or 21:30 Wed/Sat). Mirrored into PreCheck since DTW's scraper
# duplicates one shared reading into wait_time/wait_time_pre_check
# (see [[project_dtw_scraper_completion]]). No CLEAR lane.

base_date <- as.Date(Sys.Date())
mk <- function(time) as.POSIXct(paste(base_date, time), tz = "UTC")
entry_ts <- as.POSIXct(paste(Sys.Date(), format(Sys.time(), "%H:%M:%S")), tz = "UTC")

rows <- tribble(
  ~window_seq, ~day_of_week, ~open_time_gen,   ~close_time_gen,

  1L,          "Sun",        mk("03:30:00"),   mk("22:30:00"),
  2L,          "Mon",        mk("03:30:00"),   mk("22:30:00"),
  3L,          "Tue",        mk("03:30:00"),   mk("22:30:00"),
  4L,          "Wed",        mk("03:30:00"),   mk("21:30:00"),
  5L,          "Thu",        mk("03:30:00"),   mk("22:30:00"),
  6L,          "Fri",        mk("03:30:00"),   mk("22:30:00"),
  7L,          "Sat",        mk("03:30:00"),   mk("21:30:00"),
) |>
  mutate(
    airport             = "DTW",
    timezone            = "America/Detroit",
    checkpoint           = "McNamara",
    open_time_prechk    = open_time_gen,
    close_time_prechk   = close_time_gen,
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

  before <- dbGetQuery(con, "SELECT COUNT(*) n FROM airport_checkpoint_hours WHERE airport='DTW' AND checkpoint='McNamara'")$n
  dbAppendTable(con, "airport_checkpoint_hours", as.data.frame(rows))
  after <- dbGetQuery(con, "SELECT COUNT(*) n FROM airport_checkpoint_hours WHERE airport='DTW' AND checkpoint='McNamara'")$n
  cat(glue("{host}: {before} -> {after} DTW McNamara rows"), "\n")

  dbDisconnect(con, shutdown = TRUE)
}

cat("\n---- Writing to desktop (localhost) ----\n")
write_to("localhost", disable_ssl = FALSE)

cat("\n---- Writing to Pi (192.168.1.207) ----\n")
write_to("192.168.1.207", disable_ssl = TRUE)
