suppressPackageStartupMessages({
  library(duckdb); library(DBI); library(glue); library(dplyr)
})

# Derived from ~24-26 days of live open/closed polling (bos_hours_monitor /
# las_hours_monitor tables) -- see CHANGELOG 2026-08-15 for the analysis.
# No posted schedule exists for either airport, so this monitor-derived data
# IS the source of truth here (unlike airports with a real posted schedule).
# Checkpoint 6: All E Gates (BOS) intentionally excluded -- no consistent
# daily pattern, can't be reduced to one open/close pair without risking
# hiding real data behind a wrong guess (same call as SLC/DTW precedent).

base_date <- as.Date(Sys.Date())  # 2026-08-15, placeholder date matching entry-date convention
mk <- function(date_offset, time) as.POSIXct(paste(base_date + date_offset, time), tz = "UTC")

rows <- tribble(
  ~airport, ~timezone,              ~checkpoint,                            ~open_time_gen,      ~close_time_gen,      ~open_time_prechk,   ~close_time_prechk,

  "LAS", "America/Los_Angeles", "T1 - A/B Gates",                          mk(0, "00:00:00"), mk(1, "00:00:00"), mk(0, "00:00:00"), mk(1, "00:00:00"),
  "LAS", "America/Los_Angeles", "T1 - C Gates",                            mk(0, "00:00:00"), mk(1, "00:00:00"), mk(0, "00:00:00"), mk(1, "00:00:00"),
  "LAS", "America/Los_Angeles", "T1 - C/D Gates",                          mk(0, "00:00:00"), mk(1, "00:00:00"), mk(0, "00:00:00"), mk(1, "00:00:00"),
  "LAS", "America/Los_Angeles", "T3 - D/E Gates",                          mk(0, "00:00:00"), mk(1, "00:00:00"), mk(0, "00:00:00"), mk(1, "00:00:00"),

  "BOS", "America/New_York",    "Checkpoint 1: A Gates",                   mk(0, "04:00:00"), mk(0, "22:00:00"), NA,                 NA,
  "BOS", "America/New_York",    "Checkpoint 2: A Gates PreCheck Only",     NA,                 NA,                 mk(0, "04:00:00"), mk(0, "20:00:00"),
  "BOS", "America/New_York",    "Checkpoint 3: Gates B1 - B22",            mk(0, "03:00:00"), mk(0, "22:00:00"), mk(0, "03:00:00"), mk(0, "20:00:00"),
  "BOS", "America/New_York",    "Checkpoint 4: Gates B23 - 40",            mk(0, "03:00:00"), mk(0, "22:00:00"), mk(0, "03:00:00"), mk(0, "21:00:00"),
  "BOS", "America/New_York",    "Checkpoint 5: Terminal C",                mk(0, "03:00:00"), mk(0, "23:00:00"), mk(0, "04:00:00"), mk(0, "21:00:00"),
  "BOS", "America/New_York",    "Checkpoint 7: All E Gates",               mk(0, "04:30:00"), mk(1, "01:30:00"), mk(0, "04:00:00"), mk(0, "22:00:00"),
) |>
  mutate(
    open_time_clear  = as.POSIXct(NA),
    close_time_clear = as.POSIXct(NA),
    entry_timestamp  = as.POSIXct(paste(Sys.Date(), format(Sys.time(), "%H:%M:%S")), tz = "UTC"),
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

  before <- dbGetQuery(con, "SELECT COUNT(*) n FROM airport_checkpoint_hours WHERE airport IN ('BOS','LAS')")$n
  dbAppendTable(con, "airport_checkpoint_hours", as.data.frame(rows))
  after <- dbGetQuery(con, "SELECT COUNT(*) n FROM airport_checkpoint_hours WHERE airport IN ('BOS','LAS')")$n
  cat(glue("{host}: {before} -> {after} BOS/LAS rows"), "\n")

  dbDisconnect(con, shutdown = TRUE)
}

cat("\n---- Writing to desktop (localhost) ----\n")
write_to("localhost", disable_ssl = FALSE)

cat("\n---- Writing to Pi (192.168.1.207) ----\n")
write_to("192.168.1.207", disable_ssl = TRUE)
