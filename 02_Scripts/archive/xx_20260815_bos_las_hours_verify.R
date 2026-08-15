suppressPackageStartupMessages({ library(duckdb); library(DBI); library(glue) })

verify <- function(host, disable_ssl) {
  con <- dbConnect(duckdb::duckdb())
  dbExecute(con, "INSTALL quack; LOAD quack;")
  attach_sql <- if (disable_ssl) {
    glue("ATTACH 'quack:{host}' AS remote_db (TYPE quack, TOKEN '{Sys.getenv('DUCKDB_QUACK_TOKEN')}', DISABLE_SSL true)")
  } else {
    glue("ATTACH 'quack:{host}' AS remote_db (TYPE quack, TOKEN '{Sys.getenv('DUCKDB_QUACK_TOKEN')}')")
  }
  dbExecute(con, attach_sql)
  dbExecute(con, "USE remote_db;")
  cat(glue("\n---- {host} ----"), "\n")
  print(dbGetQuery(con, "
    SELECT airport, checkpoint, open_time_gen, close_time_gen, open_time_prechk, close_time_prechk
    FROM airport_checkpoint_hours WHERE airport IN ('BOS','LAS') ORDER BY airport, checkpoint
  "))
  dbDisconnect(con, shutdown = TRUE)
}

verify("localhost", FALSE)
verify("192.168.1.207", TRUE)
