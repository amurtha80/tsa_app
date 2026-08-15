library(duckdb); library(DBI)
con <- dbConnect(duckdb::duckdb())
dbExecute(con, "LOAD quack;")
token <- Sys.getenv("DUCKDB_QUACK_TOKEN")
dbExecute(con, sprintf("ATTACH 'quack:localhost' AS desktop_db (TYPE quack, TOKEN '%s', DISABLE_SSL true)", token))
dbExecute(con, sprintf("ATTACH 'quack:192.168.1.207' AS pi_db (TYPE quack, TOKEN '%s', DISABLE_SSL true)", token))

window_start <- "2026-08-13 00:00:00"
window_end   <- "2026-08-14 21:00:00"

antijoin_sql <- sprintf("
  SELECT d.*
  FROM desktop_db.tsa_wait_times d
  WHERE d.datetime BETWEEN TIMESTAMP '%s' AND TIMESTAMP '%s'
    AND NOT EXISTS (
      SELECT 1 FROM pi_db.tsa_wait_times p
      WHERE p.airport = d.airport
        AND p.checkpoint = d.checkpoint
        AND p.datetime = d.datetime
    )
", window_start, window_end)

# Final pre-write recount, run fresh in this same execution -- per the
# Verified-Facts Gate, this must be the count actually used to decide whether
# to proceed, not a number carried over from an earlier turn.
final_count <- dbGetQuery(con, sprintf("SELECT airport, COUNT(*) n FROM (%s) GROUP BY airport ORDER BY n DESC", antijoin_sql))
cat('=== Final pre-write recount ===\n')
print(final_count)
cat('Total rows to insert:', sum(final_count$n), '\n\n')

# --- INSERT (live write) ---
# Quack can't stream a cross-remote INSERT...SELECT between two attached quack
# dbs in one statement ("Multiple streaming scans... not currently supported").
# Materialize the anti-join result locally first, then append it.
rows_to_insert <- dbGetQuery(con, antijoin_sql)
cat('Materialized', nrow(rows_to_insert), 'rows locally.\n')

dbExecute(con, "USE pi_db")
dbAppendTable(con, "tsa_wait_times", value = rows_to_insert)
cat('Rows inserted into Pi:', nrow(rows_to_insert), '\n')

# Post-write verification from this same connection is not sufficient on its
# own (see feedback_verify_from_independent_connection) -- a true independent
# recheck is run separately after this script exits.

dbDisconnect(con, shutdown = TRUE)
