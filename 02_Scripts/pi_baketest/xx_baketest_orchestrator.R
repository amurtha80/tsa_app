# 02_Scripts/pi_baketest/xx_baketest_orchestrator.R
#
# Phase 0 bake-off harness (runbook steps C1-C3, 04_Assets/phase0_pi_nas_baketest.html).
# Runs all four remaining chromote-based scrapers (LGA, EWR, JFK, ATL)
# N_CYCLES times each against a scratch DuckDB file, recording per-cycle
# timing/outcome metadata so results can be compared across hosts (Pi native
# vs. NAS Docker container). LGA/EWR already have Pi + NAS results recorded
# in the runbook's C4 section as of 2026-07-25/27; this run adds JFK/ATL to
# complete the full-pipeline estimate.
#
# RSelenium is out of scope -- MCO/MIA were migrated to JSON APIs, so chromote
# is the only browser-automation risk left to bake off (see
# project_pi_nas_migration.md, A7 finding).
#
# Run with: Rscript 02_Scripts/pi_baketest/xx_baketest_orchestrator.R
# from the repo root, on each host being compared. Config is via env vars so
# this file runs unmodified on every host -- set them before invoking, e.g.:
#
#   BAKETEST_HOST_LABEL=pi-native \
#   BAKETEST_DB_PATH=/mnt/ssd/scratch/tsa_app_scratch.duckdb \
#   CHROMOTE_CHROME_PATH=/usr/bin/chromium-browser \
#   Rscript 02_Scripts/pi_baketest/xx_baketest_orchestrator.R
#
#   BAKETEST_HOST_LABEL=nas-docker \
#   BAKETEST_DB_PATH=/scratch/tsa_app_scratch.duckdb \
#   CHROMOTE_CHROME_PATH=/usr/bin/chromium \
#   Rscript 02_Scripts/pi_baketest/xx_baketest_orchestrator.R
#
# Both hosts should point BAKETEST_DB_PATH at the SAME scratch file (e.g. a
# NAS-mounted path both can reach) if you want one combined bakeoff_runs
# table to compare against directly; otherwise merge the two scratch DBs
# afterward. Never point BAKETEST_DB_PATH at production 01_Data/tsa_app.duckdb.

## Config ----
HOST_LABEL      <- Sys.getenv("BAKETEST_HOST_LABEL", unset = "unknown-host")
DB_PATH         <- Sys.getenv("BAKETEST_DB_PATH", unset = here::here("01_Data", "scratch", "tsa_app_scratch.duckdb"))
CHROME_PATH     <- Sys.getenv("CHROMOTE_CHROME_PATH", unset = "/usr/bin/chromium-browser")
N_CYCLES        <- as.integer(Sys.getenv("BAKETEST_N_CYCLES", unset = "5"))
CYCLE_PAUSE_SEC <- as.integer(Sys.getenv("BAKETEST_CYCLE_PAUSE_SEC", unset = "10"))

## Packages ----
suppressPackageStartupMessages({
  library(duckdb)
  library(DBI)
  library(here)
  library(glue)
  library(rvest)
  library(chromote)
  library(dplyr)
  library(stringr)
  library(lubridate)
  library(readr)
  library(polite)
})

print(glue("=== Bake-off starting: host={HOST_LABEL} db={DB_PATH} chrome={CHROME_PATH} cycles={N_CYCLES} ==="))

## Point chromote at the system Chromium build -- Chrome for Testing (chromote's
## own downloader) has no Linux/aarch64 build at all, see A7 finding in
## project_pi_nas_migration.md. Harmless to set even on a host where the
## default discovery would have worked anyway.
if (file.exists(CHROME_PATH)) {
  options(chromote.chrome = CHROME_PATH)
} else {
  message(glue("WARNING: {CHROME_PATH} not found -- letting chromote fall back to its own discovery"))
}

## Helper the scraper functions depend on (normally sourced from scrape_data_automate.R) ----
safe_read_html_live <- function(url, wait = 2) {
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
  if (is.null(page)) stop("Unable to read page after two attempts.")
  page
}

## Source the bake-off scraper variants (same scrape/transform logic as
## production, minus the arm64-incompatible local_chrome_version() probe) ----
source(here::here("02_Scripts", "pi_baketest", "LGA_wait_times_pi.R"))
source(here::here("02_Scripts", "pi_baketest", "EWR_wait_times_pi.R"))
source(here::here("02_Scripts", "pi_baketest", "JFK_wait_times_pi.R"))
source(here::here("02_Scripts", "pi_baketest", "ATL_wait_times_pi.R"))

scrapers <- list(
  LGA = scrape_tsa_data_lga,
  EWR = scrape_tsa_data_ewr,
  JFK = scrape_tsa_data_jfk,
  ATL = scrape_tsa_data_atl
)

## Scratch DB connection -- direct file connection, NOT Quack. Throwaway
## comparison DB only. ----
dir.create(dirname(DB_PATH), recursive = TRUE, showWarnings = FALSE)
con_write <- dbConnect(duckdb::duckdb(), dbdir = DB_PATH, read_only = FALSE)

source(here::here("02_Scripts", "pi_baketest", "00_scratch_db_setup.R"))

## Metadata row writer ----
record_run <- function(scraper_name, cycle_num, run_start, run_end, status,
                        rows_inserted, error_message = NA_character_) {
  row <- data.frame(
    host_label           = HOST_LABEL,
    scraper               = scraper_name,
    cycle_num             = cycle_num,
    run_start             = run_start,
    run_end               = run_end,
    duration_sec          = as.numeric(difftime(run_end, run_start, units = "secs")),
    status                = status,
    rows_inserted         = as.integer(rows_inserted),
    error_message         = error_message,
    chromote_chrome_path  = CHROME_PATH,
    r_version             = R.version.string,
    os_arch               = R.version$arch,
    recorded_at           = Sys.time(),
    stringsAsFactors      = FALSE
  )
  dbAppendTable(con_write, "bakeoff_runs", row)
}

## Main loop ----
for (cycle in seq_len(N_CYCLES)) {
  for (scraper_name in names(scrapers)) {
    fn <- scrapers[[scraper_name]]
    print(glue("=== {HOST_LABEL} | {scraper_name} | cycle {cycle}/{N_CYCLES} ==="))

    rows_before <- dbGetQuery(con_write, glue(
      "SELECT COUNT(*) AS n FROM tsa_wait_times WHERE airport = '{scraper_name}'"
    ))$n

    run_start <- Sys.time()
    err_msg <- NA_character_
    status <- tryCatch({
      fn()
      "success"
    }, error = function(e) {
      msg <- conditionMessage(e)
      message(glue("{scraper_name} cycle {cycle} FAILED: {msg}"))
      err_msg <<- msg
      "error"
    })
    run_end <- Sys.time()

    rows_after <- dbGetQuery(con_write, glue(
      "SELECT COUNT(*) AS n FROM tsa_wait_times WHERE airport = '{scraper_name}'"
    ))$n

    record_run(scraper_name, cycle, run_start, run_end, status,
               rows_after - rows_before, err_msg)

    # Brutal chromote cleanup between cycles -- see xx_chromote_perm_cache_directory.R,
    # avoids each cycle leaking a fresh headless-Chrome profile dir.
    if (chromote::has_default_chromote_object()) {
      tryCatch(chromote::set_default_chromote_object(NULL), error = function(e) NULL)
    }
    gc()

    Sys.sleep(CYCLE_PAUSE_SEC)
  }
}

## Summary ----
summary_tbl <- dbGetQuery(con_write, "
  SELECT host_label, scraper,
         COUNT(*)                                        AS cycles_run,
         SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) AS successes,
         ROUND(AVG(duration_sec), 1)                      AS avg_duration_sec,
         ROUND(MIN(duration_sec), 1)                      AS min_duration_sec,
         ROUND(MAX(duration_sec), 1)                      AS max_duration_sec,
         SUM(rows_inserted)                                AS total_rows_inserted
  FROM bakeoff_runs
  GROUP BY host_label, scraper
  ORDER BY host_label, scraper;
")
print(summary_tbl)

dbDisconnect(con_write, shutdown = TRUE)
rm(con_write)

print(glue("=== Bake-off complete: host={HOST_LABEL} ==="))
