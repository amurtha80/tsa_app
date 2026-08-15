suppressPackageStartupMessages({ library(duckdb); library(DBI); library(glue) })
con <- dbConnect(duckdb::duckdb())
dbExecute(con, "INSTALL quack; LOAD quack;")
dbExecute(con, glue(
  "ATTACH 'quack:localhost' AS remote_db (TYPE quack, TOKEN '{Sys.getenv('DUCKDB_QUACK_TOKEN')}')"
))
dbExecute(con, "USE remote_db;")
print(dbGetQuery(con, "
  SELECT airport, checkpoint, open_time_gen, close_time_gen, open_time_prechk, close_time_prechk, timezone
  FROM airport_checkpoint_hours
  WHERE close_time_gen - open_time_gen >= INTERVAL 23 HOUR
     OR close_time_prechk - open_time_prechk >= INTERVAL 23 HOUR
  LIMIT 10
"))
dbDisconnect(con, shutdown = TRUE)
