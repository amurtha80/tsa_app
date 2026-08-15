suppressPackageStartupMessages({ library(duckdb); library(DBI); library(glue) })

check <- function(host, disable_ssl) {
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
    ok <- tryCatch({ dbGetQuery(con, glue("SELECT COUNT(*) FROM {tbl}")); "STILL EXISTS" },
                    error = function(e) "gone (table not found)")
    cat(glue("{tbl}: {ok}"), "\n")
  }
  dbDisconnect(con, shutdown = TRUE)
}

check("localhost", FALSE)
check("192.168.1.207", TRUE)
