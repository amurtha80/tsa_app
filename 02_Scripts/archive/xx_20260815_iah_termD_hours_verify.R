suppressPackageStartupMessages({library(duckdb); library(DBI); library(glue)})

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
  cat(glue("\n==== {host} ===="), "\n")
  print(dbGetQuery(con, "
    SELECT window_seq, day_of_week, open_time_gen, close_time_gen, entry_timestamp
    FROM airport_checkpoint_hours
    WHERE airport = 'IAH' AND checkpoint = 'IAH Terminal D'
    ORDER BY entry_timestamp, window_seq
  "))
  dbDisconnect(con, shutdown = TRUE)
}

verify("localhost", disable_ssl = FALSE)
verify("192.168.1.207", disable_ssl = TRUE)
