library(duckdb); library(DBI)
con <- dbConnect(duckdb::duckdb())
dbExecute(con, "LOAD quack;")
token <- Sys.getenv("DUCKDB_QUACK_TOKEN")
dbExecute(con, sprintf("ATTACH 'quack:localhost' AS desktop_db (TYPE quack, TOKEN '%s', DISABLE_SSL true)", token))
dbExecute(con, sprintf("ATTACH 'quack:192.168.1.207' AS pi_db (TYPE quack, TOKEN '%s', DISABLE_SSL true)", token))

window_start <- "2026-08-13 00:00:00"
window_end   <- "2026-08-14 21:00:00"

sample_rows <- dbGetQuery(con, sprintf("
  SELECT d.*
  FROM desktop_db.tsa_wait_times d
  WHERE d.datetime BETWEEN TIMESTAMP '%s' AND TIMESTAMP '%s'
    AND d.airport IN ('DFW','JFK','LGA','DCA')
    AND NOT EXISTS (
      SELECT 1 FROM pi_db.tsa_wait_times p
      WHERE p.airport = d.airport AND p.checkpoint = d.checkpoint AND p.datetime = d.datetime
    )
  ORDER BY d.airport, d.datetime
  LIMIT 12
", window_start, window_end))
cat('=== Sample missing rows (would be inserted) ===\n')
print(sample_rows)

# Sanity check 1: are any of these accidentally already-duplicated on desktop itself?
dup_check <- dbGetQuery(con, sprintf("
  SELECT airport, checkpoint, datetime, COUNT(*) n
  FROM desktop_db.tsa_wait_times
  WHERE datetime BETWEEN TIMESTAMP '%s' AND TIMESTAMP '%s'
  GROUP BY airport, checkpoint, datetime
  HAVING COUNT(*) > 1
  LIMIT 10
", window_start, window_end))
cat('\n=== Desktop-side duplicate (airport,checkpoint,datetime) combos in window (should ideally be empty or small) ===\n')
print(dup_check)
cat('Total dup groups on desktop in window:', nrow(dbGetQuery(con, sprintf("
  SELECT airport, checkpoint, datetime
  FROM desktop_db.tsa_wait_times
  WHERE datetime BETWEEN TIMESTAMP '%s' AND TIMESTAMP '%s'
  GROUP BY airport, checkpoint, datetime
  HAVING COUNT(*) > 1
", window_start, window_end))), '\n')

# Sanity check 2: schema match between desktop and pi tables
cat('\n=== Column check ===\n')
d_cols <- dbGetQuery(con, "DESCRIBE desktop_db.tsa_wait_times")$column_name
p_cols <- dbGetQuery(con, "DESCRIBE pi_db.tsa_wait_times")$column_name
cat('Desktop cols:', paste(d_cols, collapse=', '), '\n')
cat('Pi cols:     ', paste(p_cols, collapse=', '), '\n')
cat('Identical:', identical(d_cols, p_cols), '\n')

dbDisconnect(con, shutdown = TRUE)
