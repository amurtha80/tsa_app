# Standalone manual test harness for chromote_batch_wait_times.R.
# Run via: Rscript 02_Scripts/archive/xx_20260817_test_chromote_batch.R
# (batch/non-interactive on purpose -- interactive console sessions behave
# differently for chromote/websocket teardown, see
# project_chromote_websocket_teardown_warning memory)
#
# Mirrors scrape_data_automate.R's setup (package load, Quack connect,
# safe_read_html_live() definition) without running the other 20 scrapers,
# then calls scrape_tsa_data_chromote_batch() N times in a row so results
# are directly comparable to the ~0.4% legacy baseline. Writes real rows to
# tsa_wait_times (same as any manual test call to an individual airport
# script) and to chromote_batch_scrape_log.

suppressPackageStartupMessages({
  library(rvest); library(chromote); library(duckdb); library(DBI)
  library(glue); library(dplyr); library(stringr); library(lubridate)
  library(readr); library(tibble)
})

N_RUNS <- as.integer(Sys.getenv("N_RUNS", "5"))

safe_read_html_live <- function(url, wait = 2, exit_on_fail = TRUE) {
  page <- tryCatch(
    read_html_live(url),
    error = function(e) { message("First attempt failed: ", e$message); NULL }
  )
  if (is.null(page)) {
    message("Retrying once more after ", wait, " seconds...")
    Sys.sleep(wait)
    page <- tryCatch(
      read_html_live(url),
      error = function(e) { message("Second attempt failed: ", e$message); NULL }
    )
  }
  if (is.null(page)) {
    message("Unable to read page after two attempts.")
    if (exit_on_fail) stop("Unable to read page after two attempts. Exiting function safely.")
  }
  page
}

con_write <- dbConnect(duckdb::duckdb())
dbExecute(con_write, "INSTALL quack; LOAD quack;")
dbExecute(con_write, glue(
  "ATTACH 'quack:localhost' AS remote_db (TYPE quack, TOKEN '{Sys.getenv('DUCKDB_QUACK_TOKEN')}')"
))
dbExecute(con_write, "USE remote_db;")

# Plain relative path (not here::here()) -- avoids the here()-root-sentinel
# gotcha (project_here_i_am_renv_lock_gotcha memory); this script is invoked
# with the repo root as the working directory.
source("02_Scripts/chromote_batch_wait_times.R")

cat(glue("\n==== Starting {N_RUNS} manual test runs of scrape_tsa_data_chromote_batch() ===="), "\n\n")

run_results <- vector("list", N_RUNS)

for (i in seq_len(N_RUNS)) {
  cat(glue("\n---- Run {i}/{N_RUNS} ----"), "\n")
  t0 <- Sys.time()
  run_results[[i]] <- tryCatch({
    scrape_tsa_data_chromote_batch()
    list(run = i, error = NA_character_)
  }, error = function(e) {
    cat(glue("Run {i} threw an uncaught error: {conditionMessage(e)}"), "\n")
    list(run = i, error = conditionMessage(e))
  })
  cat(glue("Run {i} wall time: {round(as.numeric(difftime(Sys.time(), t0, units='secs')), 1)}s"), "\n")
  if (i < N_RUNS) Sys.sleep(10)  # brief gap between runs, mimics real cycle spacing
}

cat("\n==== Uncaught errors across runs (should be empty if on.exit/tryCatch held) ====\n")
errs <- Filter(function(x) !is.na(x$error), run_results)
if (length(errs) == 0) cat("  none\n") else print(errs)

cat("\n==== chromote_batch_scrape_log rows from this test session ====\n")
print(dbGetQuery(con_write, glue("
  SELECT airport, attempt, success, error_message, round(duration_seconds, 1) AS duration_seconds
  FROM chromote_batch_scrape_log
  WHERE cycle_time >= (SELECT MIN(cycle_time) FROM chromote_batch_scrape_log WHERE cycle_time >= NOW() - INTERVAL 30 MINUTE)
  ORDER BY cycle_time, airport, attempt
")))

cat("\n==== Per-airport final success rate (this test session) ====\n")
print(dbGetQuery(con_write, glue("
  WITH final_per_cycle AS (
    SELECT cycle_time, airport, MAX(success::INT) AS ever_succeeded
    FROM chromote_batch_scrape_log
    WHERE cycle_time >= NOW() - INTERVAL 30 MINUTE
    GROUP BY cycle_time, airport
  )
  SELECT airport, COUNT(*) AS cycles, SUM(ever_succeeded) AS succeeded,
         ROUND(100.0 * SUM(ever_succeeded) / COUNT(*), 1) AS pct_success
  FROM final_per_cycle
  GROUP BY airport ORDER BY airport
")))

dbDisconnect(con_write, shutdown = TRUE)
cat("\nDone.\n")
