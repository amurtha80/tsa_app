suppressPackageStartupMessages({ library(duckdb); library(DBI); library(glue) })

teardown <- function(host, disable_ssl) {
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
  for (tbl in c("bos_hours_monitor", "las_hours_monitor")) {
    n <- tryCatch(dbGetQuery(con, glue("SELECT COUNT(*) n FROM {tbl}"))$n, error = function(e) NA)
    cat(glue("{tbl}: {n} rows before drop"), "\n")
  }

  dbExecute(con, "DROP TABLE IF EXISTS bos_hours_monitor")
  dbExecute(con, "DROP TABLE IF EXISTS las_hours_monitor")
  cat("Dropped both monitor tables (IF EXISTS).\n")

  dbDisconnect(con, shutdown = TRUE)
}

teardown("localhost", FALSE)
teardown("192.168.1.207", TRUE)
