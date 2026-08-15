suppressPackageStartupMessages({
  library(duckdb); library(DBI); library(glue); library(dplyr)
})

con <- dbConnect(duckdb::duckdb())
dbExecute(con, "INSTALL quack; LOAD quack;")
dbExecute(con, glue(
  "ATTACH 'quack:localhost' AS remote_db (TYPE quack, TOKEN '{Sys.getenv('DUCKDB_QUACK_TOKEN')}')"
))
dbExecute(con, "USE remote_db;")

for (tbl in c("bos_hours_monitor", "las_hours_monitor")) {
  cat("\n====", tbl, "====\n")

  n <- dbGetQuery(con, glue("SELECT COUNT(*) n, MIN(poll_time) min_t, MAX(poll_time) max_t FROM {tbl}"))
  print(n)

  cps <- dbGetQuery(con, glue("SELECT DISTINCT checkpoint, lane FROM {tbl} ORDER BY 1,2"))
  print(cps)

  # hour-of-day open rate per checkpoint/lane
  hourly <- dbGetQuery(con, glue("
    SELECT checkpoint, lane, EXTRACT(hour FROM poll_time) AS hr,
           COUNT(*) AS n_polls,
           SUM(CASE WHEN is_open THEN 1 ELSE 0 END) AS n_open,
           ROUND(100.0 * SUM(CASE WHEN is_open THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_open
    FROM {tbl}
    GROUP BY checkpoint, lane, hr
    ORDER BY checkpoint, lane, hr
  "))

  # condensed summary: first/last hour with >=50% open rate, plus a flag for
  # any "stray" open hour outside that contiguous block (ambiguity check)
  summ <- hourly |>
    group_by(checkpoint, lane) |>
    summarise(
      open_hrs        = list(sort(hr[pct_open >= 50])),
      first_open_hr   = if (any(pct_open >= 50)) min(hr[pct_open >= 50]) else NA_real_,
      last_open_hr    = if (any(pct_open >= 50)) max(hr[pct_open >= 50]) else NA_real_,
      contiguous      = {
        h <- sort(hr[pct_open >= 50])
        length(h) == 0 || all(diff(h) == 1)
      },
      n_ambiguous_hrs = sum(pct_open > 5 & pct_open < 95),
      .groups = "drop"
    ) |>
    select(-open_hrs)

  print(as.data.frame(summ), row.names = FALSE)
}

dbDisconnect(con, shutdown = TRUE)
