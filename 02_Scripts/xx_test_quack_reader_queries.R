# xx_test_quack_reader_queries.R ----
# Run this from a SEPARATE R session while xx_test_orchestrator_quack.R is
# running -- that's the whole point of the test. Requires the Quack server
# (zz_test_duckdb_quack.R) to already be running.
#
# Query 3 is the real concurrency proof -- loop it every 5-10s during the
# orchestrator's run and watch for new rows with no lock error.

library(duckdb, warn.conflicts = FALSE)
library(DBI, warn.conflicts = FALSE)
library(glue, warn.conflicts = FALSE)

quack_token <- Sys.getenv("DUCKDB_QUACK_TOKEN", "flyasap_quack_test_token")

con_read <- dbConnect(duckdb::duckdb())
dbExecute(con_read, "INSTALL quack; LOAD quack;")
dbExecute(con_read, glue(
  "ATTACH 'quack:localhost' AS remote_db (TYPE quack, TOKEN '{quack_token}')"
))

# Query 1: row count by airport - proves you can read at all
print(dbGetQuery(con_read, "
SELECT airport, COUNT(*) AS obs_count
FROM remote_db.tsa_wait_times
GROUP BY airport
ORDER BY airport;
"))

# Query 2: most recent timestamp per airport - proves writes are landing live
print(dbGetQuery(con_read, "
SELECT airport, MAX(datetime) AS latest_datetime
FROM remote_db.tsa_wait_times
GROUP BY airport
ORDER BY airport;
"))

# Query 3: rows written in just the last 2 minutes - the real concurrency proof
print(dbGetQuery(con_read, "
SELECT airport, checkpoint, datetime, wait_time
FROM remote_db.tsa_wait_times
WHERE datetime >= CAST(CURRENT_TIMESTAMP AS TIMESTAMP) - INTERVAL 2 MINUTE
ORDER BY datetime DESC;
"))

dbDisconnect(con_read, shutdown = TRUE)
rm(con_read)
rm(quack_token)
