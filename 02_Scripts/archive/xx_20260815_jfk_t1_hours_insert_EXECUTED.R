suppressPackageStartupMessages({
  library(duckdb); library(DBI); library(glue); library(dplyr)
})

# JFK Terminal 1 PreCheck 24hr assumption (set 2026-07-12) corrected after a
# full month of tsa_wait_times data (2026-07-15 through 2026-08-15) showed a
# consistent, day-of-week-independent double-closure pattern -- see CHANGELOG
# 2026-08-15 for the full analysis (UTC/local timezone bug found+fixed along
# the way, calibrated against JFK Terminal 8's confirmed 4am-8pm hours).
# Boundaries pinned via 15-min-bucket median wait_time_pre_check:
#   Window 1 (sustained open): 08:00 - 01:00 (wraps)
#   Window 2 (partial morning reopen): 03:30 - 06:00
# Both windows apply every day (weekday vs weekend checked separately, same
# shape in both -- 30-31/31 days hit min=0 in each trough hour). General
# lane hours (04:00-23:00) unchanged, only restated on window_seq=1 -- the
# window_seq=2 row leaves general NA, which means "this window doesn't add a
# second general-lane restriction," not "unrestricted" (window_seq=1 already
# defines general for this checkpoint). No CLEAR lane at this checkpoint,
# same as before.

base_date <- as.Date(Sys.Date())  # 2026-08-15, placeholder date matching entry-date convention
mk <- function(date_offset, time) as.POSIXct(paste(base_date + date_offset, time), tz = "UTC")

entry_ts <- as.POSIXct(paste(Sys.Date(), format(Sys.time(), "%H:%M:%S")), tz = "UTC")

rows <- tribble(
  ~airport, ~timezone,              ~checkpoint,   ~window_seq, ~day_of_week, ~open_time_gen,     ~close_time_gen,    ~open_time_prechk,  ~close_time_prechk,

  "JFK",    "America/New_York",    "Terminal 1",   1L,          NA_character_, mk(0, "04:00:00"), mk(0, "23:00:00"), mk(0, "08:00:00"), mk(1, "01:00:00"),
  "JFK",    "America/New_York",    "Terminal 1",   2L,          NA_character_, NA,                 NA,                 mk(0, "03:30:00"), mk(0, "06:00:00"),
) |>
  mutate(
    open_time_clear  = as.POSIXct(NA),
    close_time_clear = as.POSIXct(NA),
    entry_timestamp  = entry_ts,
    is_active        = TRUE
  )

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

  before <- dbGetQuery(con, "SELECT COUNT(*) n FROM airport_checkpoint_hours WHERE airport='JFK' AND checkpoint='Terminal 1'")$n
  dbAppendTable(con, "airport_checkpoint_hours", as.data.frame(rows))
  after <- dbGetQuery(con, "SELECT COUNT(*) n FROM airport_checkpoint_hours WHERE airport='JFK' AND checkpoint='Terminal 1'")$n
  cat(glue("{host}: {before} -> {after} JFK Terminal 1 rows"), "\n")

  dbDisconnect(con, shutdown = TRUE)
}

cat("\n---- Writing to desktop (localhost) ----\n")
write_to("localhost", disable_ssl = FALSE)

cat("\n---- Writing to Pi (192.168.1.207) ----\n")
write_to("192.168.1.207", disable_ssl = TRUE)
