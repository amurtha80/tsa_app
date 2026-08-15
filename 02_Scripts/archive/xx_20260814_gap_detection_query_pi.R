library(duckdb); library(DBI)
con <- dbConnect(duckdb::duckdb())
dbExecute(con, "LOAD quack;")
token <- Sys.getenv("DUCKDB_QUACK_TOKEN")
dbExecute(con, sprintf("ATTACH 'quack:localhost' AS remote_db (TYPE quack, TOKEN '%s', DISABLE_SSL true)", token))
dbExecute(con, "USE remote_db")

airports <- dbGetQuery(con, "SELECT DISTINCT airport FROM tsa_wait_times ORDER BY airport")
print(airports)

# Gap detection: distinct cycle timestamps per airport, look for gaps > 15 min
gaps <- dbGetQuery(con, "
  WITH cycles AS (
    SELECT DISTINCT airport, datetime
    FROM tsa_wait_times
    WHERE datetime >= TIMESTAMP '2026-08-13 00:00:00'
      AND airport != 'LAX'
  ),
  ordered AS (
    SELECT airport, datetime,
           LAG(datetime) OVER (PARTITION BY airport ORDER BY datetime) AS prev_dt
    FROM cycles
  )
  SELECT airport, prev_dt AS gap_start, datetime AS gap_end,
         date_diff('minute', prev_dt, datetime) AS gap_minutes
  FROM ordered
  WHERE date_diff('minute', prev_dt, datetime) > 15
  ORDER BY airport, gap_start
")
cat('=== GAPS > 15 min (excluding LAX) ===\n')
print(gaps)

summ <- dbGetQuery(con, "
  SELECT airport, MIN(datetime) AS earliest, MAX(datetime) AS latest, COUNT(DISTINCT datetime) AS n_cycles
  FROM tsa_wait_times
  WHERE datetime >= TIMESTAMP '2026-08-13 00:00:00' AND airport != 'LAX'
  GROUP BY airport ORDER BY airport
")
cat('=== per-airport summary since cutover ===\n')
print(summ)

dbDisconnect(con, shutdown=TRUE)
