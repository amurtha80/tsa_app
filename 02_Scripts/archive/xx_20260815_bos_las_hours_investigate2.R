suppressPackageStartupMessages({
  library(duckdb); library(DBI); library(glue); library(dplyr)
})

con <- dbConnect(duckdb::duckdb())
dbExecute(con, "INSTALL quack; LOAD quack;")
dbExecute(con, glue(
  "ATTACH 'quack:localhost' AS remote_db (TYPE quack, TOKEN '{Sys.getenv('DUCKDB_QUACK_TOKEN')}')"
))
dbExecute(con, "USE remote_db;")

targets <- list(
  list(cp = "Checkpoint 1: A Gates", lane = "precheck"),
  list(cp = "Checkpoint 6: All E Gates", lane = "standard"),
  list(cp = "Checkpoint 7: All E Gates", lane = "standard")
)

for (t in targets) {
  cat("\n----", t$cp, "/", t$lane, "----\n")
  df <- dbGetQuery(con, glue("
    SELECT EXTRACT(hour FROM poll_time) AS hr,
           COUNT(*) AS n_polls,
           SUM(CASE WHEN is_open THEN 1 ELSE 0 END) AS n_open,
           ROUND(100.0 * SUM(CASE WHEN is_open THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_open
    FROM bos_hours_monitor
    WHERE checkpoint = '{t$cp}' AND lane = '{t$lane}'
    GROUP BY hr ORDER BY hr
  "))
  print(df, row.names = FALSE)

  cat("--- by day-of-week ---\n")
  dow <- dbGetQuery(con, glue("
    SELECT dayname(poll_time) AS dow, EXTRACT(hour FROM poll_time) AS hr,
           ROUND(100.0 * SUM(CASE WHEN is_open THEN 1 ELSE 0 END) / COUNT(*), 0) AS pct_open
    FROM bos_hours_monitor
    WHERE checkpoint = '{t$cp}' AND lane = '{t$lane}'
    GROUP BY dow, hr ORDER BY dow, hr
  "))
  wide <- tidyr::pivot_wider(dow, names_from = hr, values_from = pct_open)
  print(as.data.frame(wide), row.names = FALSE)
}

dbDisconnect(con, shutdown = TRUE)
