suppressPackageStartupMessages({
  library(duckdb); library(DBI); library(glue)
})

con <- dbConnect(duckdb::duckdb())
dbExecute(con, "INSTALL quack; LOAD quack;")
dbExecute(con, glue(
  "ATTACH 'quack:localhost' AS remote_db (TYPE quack, TOKEN '{Sys.getenv('DUCKDB_QUACK_TOKEN')}')"
))
dbExecute(con, "USE remote_db;")

cat("---- schema ----\n")
print(dbGetQuery(con, "DESCRIBE airport_checkpoint_hours"))

cat("\n---- existing BOS/LAS rows ----\n")
print(dbGetQuery(con, "SELECT * FROM airport_checkpoint_hours WHERE airport IN ('BOS','LAS') ORDER BY airport, checkpoint"))

cat("\n---- a fully-populated example row (non-BOS/LAS) for reference ----\n")
print(dbGetQuery(con, "SELECT * FROM airport_checkpoint_hours WHERE airport = 'JFK' LIMIT 3"))

dbDisconnect(con, shutdown = TRUE)
