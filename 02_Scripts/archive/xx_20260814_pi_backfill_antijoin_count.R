library(duckdb); library(DBI)
con <- dbConnect(duckdb::duckdb())
dbExecute(con, "LOAD quack;")
token <- Sys.getenv("DUCKDB_QUACK_TOKEN")

# Local (desktop) DB -- source of truth for the backfill window
dbExecute(con, sprintf("ATTACH 'quack:localhost' AS desktop_db (TYPE quack, TOKEN '%s', DISABLE_SSL true)", token))

# Remote (Pi) DB -- the one missing rows
dbExecute(con, sprintf("ATTACH 'quack:192.168.1.207' AS pi_db (TYPE quack, TOKEN '%s', DISABLE_SSL true)", token))

window_start <- "2026-08-13 00:00:00"  # raw stored value, cutover day
window_end   <- "2026-08-14 21:00:00"  # raw stored value, safely past the 16:56 EDT fix

# Count of desktop rows in-window missing from the Pi, per airport
missing <- dbGetQuery(con, sprintf("
  SELECT d.airport, COUNT(*) AS missing_rows
  FROM desktop_db.tsa_wait_times d
  WHERE d.datetime BETWEEN TIMESTAMP '%s' AND TIMESTAMP '%s'
    AND NOT EXISTS (
      SELECT 1 FROM pi_db.tsa_wait_times p
      WHERE p.airport = d.airport
        AND p.checkpoint = d.checkpoint
        AND p.datetime = d.datetime
    )
  GROUP BY d.airport
  ORDER BY missing_rows DESC
", window_start, window_end))

cat('=== Rows present on desktop but missing from Pi, by airport (', window_start, 'to', window_end, ') ===\n')
print(missing)
cat('\nTotal missing rows:', sum(missing$missing_rows), '\n')

dbDisconnect(con, shutdown = TRUE)
