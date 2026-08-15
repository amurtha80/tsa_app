library(duckdb); library(DBI)
con <- dbConnect(duckdb::duckdb())
dbExecute(con, "LOAD quack;")
token <- Sys.getenv("DUCKDB_QUACK_TOKEN")
dbExecute(con, sprintf("ATTACH 'quack:localhost' AS pi_db (TYPE quack, TOKEN '%s', DISABLE_SSL true)", token))
dbExecute(con, "USE pi_db")
r <- dbGetQuery(con, "
  SELECT airport, COUNT(*) n
  FROM tsa_wait_times
  WHERE datetime BETWEEN TIMESTAMP '2026-08-13 00:00:00' AND TIMESTAMP '2026-08-14 21:00:00'
  GROUP BY airport ORDER BY n DESC
")
print(r)
cat('Total rows in window now:', sum(r$n), '\n')

# re-check for any duplicate (airport,checkpoint,datetime) introduced by the insert
dup <- dbGetQuery(con, "
  SELECT COUNT(*) n_dup_groups FROM (
    SELECT airport, checkpoint, datetime
    FROM tsa_wait_times
    WHERE datetime BETWEEN TIMESTAMP '2026-08-13 00:00:00' AND TIMESTAMP '2026-08-14 21:00:00'
    GROUP BY airport, checkpoint, datetime
    HAVING COUNT(*) > 1
  )
")
print(dup)
dbDisconnect(con, shutdown=TRUE)
