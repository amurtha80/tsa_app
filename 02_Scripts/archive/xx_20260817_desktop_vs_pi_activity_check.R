suppressPackageStartupMessages({ library(duckdb); library(DBI); library(glue) })

connect <- function(host, disable_ssl) {
  con <- dbConnect(duckdb::duckdb())
  dbExecute(con, "INSTALL quack; LOAD quack;")
  attach_sql <- if (disable_ssl) {
    glue("ATTACH 'quack:{host}' AS remote_db (TYPE quack, TOKEN '{Sys.getenv('DUCKDB_QUACK_TOKEN')}', DISABLE_SSL true)")
  } else {
    glue("ATTACH 'quack:{host}' AS remote_db (TYPE quack, TOKEN '{Sys.getenv('DUCKDB_QUACK_TOKEN')}')")
  }
  dbExecute(con, attach_sql)
  dbExecute(con, "USE remote_db;")
  con
}

summarize_host <- function(host, disable_ssl, label, since) {
  con <- connect(host, disable_ssl)
  cat(glue("\n==== {label} ({host}) ===="), "\n")

  overall <- dbGetQuery(con, glue("
    SELECT COUNT(*) AS n_rows,
           MIN(datetime) AS min_dt,
           MAX(datetime) AS max_dt,
           COUNT(DISTINCT airport) AS n_airports
    FROM tsa_wait_times
    WHERE datetime >= TIMESTAMP '{since}'
  "))
  print(overall)

  cat("\nPer-airport row counts and last-seen timestamp:\n")
  per_airport <- dbGetQuery(con, glue("
    SELECT airport, COUNT(*) AS n_rows, MAX(datetime) AS last_seen
    FROM tsa_wait_times
    WHERE datetime >= TIMESTAMP '{since}'
    GROUP BY airport
    ORDER BY airport
  "))
  print(per_airport, row.names = FALSE)

  cat("\nHourly cycle coverage (rows per hour, whole window):\n")
  hourly <- dbGetQuery(con, glue("
    SELECT date_trunc('hour', datetime) AS hr, COUNT(*) AS n_rows
    FROM tsa_wait_times
    WHERE datetime >= TIMESTAMP '{since}'
    GROUP BY hr
    ORDER BY hr
  "))
  cat(glue("  {nrow(hourly)} distinct hours have data; min/hr={min(hourly$n_rows)}, max/hr={max(hourly$n_rows)}, median/hr={median(hourly$n_rows)}"), "\n")

  # find gaps > 30 min in the overall stream (any airport writing = alive)
  cat("\nGaps > 30 min in overall scrape activity (any row, any airport):\n")
  gaps <- dbGetQuery(con, glue("
    WITH ordered AS (
      SELECT DISTINCT datetime FROM tsa_wait_times
      WHERE datetime >= TIMESTAMP '{since}'
      ORDER BY datetime
    ),
    lagged AS (
      SELECT datetime, LAG(datetime) OVER (ORDER BY datetime) AS prev_dt
      FROM ordered
    )
    SELECT prev_dt, datetime AS next_dt,
           date_diff('minute', prev_dt, datetime) AS gap_minutes
    FROM lagged
    WHERE date_diff('minute', prev_dt, datetime) > 30
    ORDER BY prev_dt
  "))
  if (nrow(gaps) == 0) {
    cat("  none\n")
  } else {
    print(gaps, row.names = FALSE)
  }

  dbDisconnect(con, shutdown = TRUE)
  invisible(list(overall = overall, per_airport = per_airport, hourly = hourly, gaps = gaps))
}

since <- "2026-08-15 00:00:00"

desktop <- summarize_host("localhost", FALSE, "DESKTOP", since)
pi      <- summarize_host("192.168.1.207", TRUE, "PI", since)

cat("\n\n==== COMPARISON: airports present on one host but not the other ====\n")
d_airports <- desktop$per_airport$airport
p_airports <- pi$per_airport$airport
cat("On desktop, missing from Pi: ", paste(setdiff(d_airports, p_airports), collapse = ", "), "\n")
cat("On Pi, missing from desktop: ", paste(setdiff(p_airports, d_airports), collapse = ", "), "\n")

cat("\n==== COMPARISON: per-airport row-count deltas (desktop - pi) ====\n")
merged <- merge(desktop$per_airport, pi$per_airport, by = "airport", all = TRUE,
                 suffixes = c("_desktop", "_pi"))
merged$n_rows_desktop[is.na(merged$n_rows_desktop)] <- 0
merged$n_rows_pi[is.na(merged$n_rows_pi)] <- 0
merged$delta <- merged$n_rows_desktop - merged$n_rows_pi
print(merged[order(-abs(merged$delta)), ], row.names = FALSE)
