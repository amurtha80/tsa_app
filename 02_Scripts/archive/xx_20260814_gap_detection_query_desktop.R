library(duckdb); library(DBI)
con <- dbConnect(duckdb::duckdb())
dbExecute(con, "LOAD quack;")
token <- Sys.getenv("DUCKDB_QUACK_TOKEN")
dbExecute(con, sprintf("ATTACH 'quack:localhost' AS remote_db (TYPE quack, TOKEN '%s', DISABLE_SSL true)", token))
dbExecute(con, "USE remote_db")

gaps <- dbGetQuery(con, "
  WITH cycles AS (
    SELECT DISTINCT airport, datetime
    FROM tsa_wait_times
    WHERE datetime >= CAST(now() AS TIMESTAMP) - INTERVAL 24 HOUR
  ),
  ordered AS (
    SELECT airport, datetime,
           LAG(datetime) OVER (PARTITION BY airport ORDER BY datetime) AS prev_dt
    FROM cycles
  ),
  flagged AS (
    SELECT airport, prev_dt AS gap_start, datetime AS gap_end,
           date_diff('minute', prev_dt, datetime) AS gap_minutes
    FROM ordered
    WHERE date_diff('minute', prev_dt, datetime) > 15
  )
  SELECT airport, COUNT(*) AS n_gaps, SUM(gap_minutes) AS total_gap_minutes,
         MAX(gap_minutes) AS worst_gap_minutes
  FROM flagged
  GROUP BY airport
  ORDER BY total_gap_minutes DESC
")
cat('=== Desktop: gap summary by airport, last 24h ===\n')
print(gaps)

detail <- dbGetQuery(con, "
  WITH cycles AS (
    SELECT DISTINCT airport, datetime
    FROM tsa_wait_times
    WHERE datetime >= CAST(now() AS TIMESTAMP) - INTERVAL 24 HOUR
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
cat('=== Desktop: gap detail, last 24h ===\n')
print(detail)

summ <- dbGetQuery(con, "
  SELECT airport, MIN(datetime) AS earliest, MAX(datetime) AS latest, COUNT(DISTINCT datetime) AS n_cycles
  FROM tsa_wait_times
  WHERE datetime >= CAST(now() AS TIMESTAMP) - INTERVAL 24 HOUR
  GROUP BY airport ORDER BY airport
")
cat('=== Desktop: per-airport summary, last 24h ===\n')
print(summ)

dbDisconnect(con, shutdown=TRUE)
