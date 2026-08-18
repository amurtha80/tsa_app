# install.packages(c("DBI", "rvest", "tidyverse", "duckdb",
#  "lubridate", "magrittr", glue", "here", "chromote"))

# library(rvest, verbose = FALSE, warn.conflicts = FALSE)
# library(duckdb, verbose = FALSE, warn.conflicts = FALSE)
# library(lubridate, verbose = FALSE, warn.conflicts = FALSE)
# library(magrittr, verbose = FALSE, warn.conflicts = FALSE)
# library(glue, verbose = FALSE, warn.conflicts = FALSE)
# library(DBI, verbose = FALSE, warn.conflicts = FALSE)
# library(tidyverse, verbose = FALSE, warn.conflicts = FALSE)
# library(here, verbose = FALSE, warn.conflicts = FALSE)
# library(chromote, verbose = FALSE, warn.conflicts = FALSE)

####  --------------------------------------------------------------------- ####
#
# NOT WIRED IN YET. This file is picked up automatically by
# scrape_data_automate.R's `_wait_times.R` glob, but SCRAPER_MODE=all
# (desktop's default/unset value) explicitly excludes it (see the
# BATCH_CHROMOTE_SCRAPER exclusion still to be added there) -- so sourcing
# this file alone does not change any current scraper's behavior. Wiring it
# into a live host requires:
#   1. Adding the BATCH_CHROMOTE_SCRAPER exclusion + SCRAPER_MODE=chromote_batch
#      branch to scrape_data_automate.R (see project_chromote_batch_scraper_design
#      memory for the exact design).
#   2. Setting SCRAPER_MODE=chromote_batch in the Pi's tsa_app_scraper.service
#      Environment= line (excludes the legacy 4, includes this file).
# Until both of those happen, ATL_wait_times.R / EWR_wait_times.R /
# JFK_wait_times.R / LGA_wait_times.R remain the only things actually running.
#
# WHY THIS EXISTS: on Pi hardware, each of the 4 legacy chromote scripts
# launches AND fully tears down its own Chrome browser process every single
# call. Investigation on 2026-08-17 found this contributing to a ~0.4%
# success rate for these 4 airports on the Pi (see
# project_chromote_batch_scraper_design memory for full diagnosis). This
# script instead launches ONE shared browser and scrapes all 4 airports as
# separate tabs on it, only tearing the browser down once at the very end
# (or once, mid-batch, if a fresh-browser retry is needed) -- verified
# directly on the Pi that back-to-back read_html_live() calls without an
# intervening teardown share one browser process (same
# --remote-debugging-port), so no low-level chromote API is needed here.
#
# DUPLICATION NOTICE: the parsing logic for each airport below is COPIED from
# ATL_wait_times.R / EWR_wait_times.R / JFK_wait_times.R / LGA_wait_times.R,
# not shared with them (deliberate choice -- see
# project_chromote_batch_scraper_design memory). Those 4 files are left fully
# untouched and independently runnable so a future hardware upgrade can pivot
# back to one-airport-per-script with zero rework. If any of those 4 sites'
# HTML layout changes and a parser needs fixing, the matching parser in THIS
# file needs the identical fix -- they will not stay in sync automatically.
#
####  --------------------------------------------------------------------- ####


# Database Connection ----

# con_write <- dbConnect(duckdb::duckdb(), dbdir = "01_Data/tsa_app.duckdb", read_only = FALSE)


scrape_tsa_data_chromote_batch <- function() {

  print(glue("kickoff CHROMOTE BATCH scrape (ATL/EWR/JFK/LGA) ",
             format(Sys.time(), "%a %b %d %X %Y")))

  batch_start <- Sys.time()

  # Closes the shared browser itself (not just a tab). NOTE:
  # chromote::set_default_chromote_object(NULL) is NOT a valid way to do this
  # in the installed chromote version -- confirmed directly (2026-08-17) that
  # it unconditionally throws "x must be a Chromote object" regardless of
  # state. The legacy per-airport scripts never hit that error only because
  # they call page$session$parent$close(wait = 2) FIRST, which clears
  # has_default_chromote_object() to FALSE and so their guarded
  # set_default_chromote_object(NULL) call never actually runs. Closing the
  # default object directly (same effect as page$session$parent$close())
  # is the real teardown mechanism.
  close_shared_browser <- function() {
    tryCatch({
      if (chromote::has_default_chromote_object()) {
        chromote::default_chromote_object()$close(wait = 2)
      }
    }, error = function(e) {
      message(Sys.time(), " | CHROMOTE BATCH browser close warning (non-fatal): ", e$message)
    })
  }

  # Final teardown of the shared browser happens ONCE at the very end of the
  # whole batch (all airports, all passes) -- not per-airport like the legacy
  # scripts. This is the entire point: pay Chrome's launch cost once per
  # cycle instead of 4 times.
  on.exit(close_shared_browser(), add = TRUE)

  options(chromote.headless = "new")
  # Chrome binary: let chromote auto-detect an installed browser -- do NOT
  # pin via chromote::local_chrome_version(binary = "chrome-headless-shell").
  # See project_pi_chromote_arm64_binary_fix memory.


  ####  ---------------------------------------------------------------- ####
  # Per-airport parsers -- nested INSIDE this function deliberately, not
  # defined at top level. scrape_data_automate.R auto-discovers every
  # top-level function that exists after sourcing all *_wait_times.R files
  # (`functions <- as.vector(lsf.str())`) and blindly calls each one with no
  # arguments. A top-level parse_atl(page) etc. would get swept up and
  # "run" by the orchestrator every cycle and error out. Nesting them here
  # keeps them local to this function's scope only.
  ####  ---------------------------------------------------------------- ####

  parse_atl <- function(page) {
    tsa_terminal <- page |>
      rvest::html_elements("div h1") |>
      rvest::html_text() |>
      stringr::str_trim() |>
      tail(2)

    tsa_checkpoint <- page |>
      rvest::html_elements("div h2") |>
      rvest::html_text() |>
      stringr::str_trim()

    n_domestic <- length(tsa_checkpoint) - 1
    n_intl     <- 1

    tsa_terminal_checkpoint <- c(
      paste0(tsa_terminal[1], " ", tsa_checkpoint[seq_len(n_domestic)]),
      paste0(tsa_terminal[2], " ", tsa_checkpoint[length(tsa_checkpoint)])
    ) |>
      stringr::str_squish()

    tsa_time_raw <- page |>
      rvest::html_elements("button span") |>
      rvest::html_text() |>
      stringr::str_trim()

    tsa_time <- readr::parse_number(tsa_time_raw, na = c("", "N/A", "Closed", "X"))

    if (length(tsa_time) != length(tsa_terminal_checkpoint)) {
      stop(glue(
        "ATL length mismatch: {length(tsa_terminal_checkpoint)} checkpoints, ",
        "{length(tsa_time)} times. Raw button spans: ",
        paste(tsa_time_raw, collapse = " | ")
      ))
    }

    checkpoint_h3 <- page |>
      rvest::html_elements("div h3") |>
      rvest::html_text() |>
      stringr::str_trim() |>
      tail(length(tsa_terminal_checkpoint))

    is_precheck_only <- grepl("PRECHECK ONLY", checkpoint_h3, ignore.case = TRUE)

    wait_time <- dplyr::if_else(is_precheck_only, NA_real_, as.numeric(tsa_time))
    wait_time_pre_check <- dplyr::if_else(is_precheck_only, as.numeric(tsa_time), NA_real_)

    tibble::tibble(
      airport             = "ATL",
      checkpoint          = tsa_terminal_checkpoint,
      datetime            = lubridate::now(tzone = "America/New_York"),
      date                = lubridate::today(),
      time                = Sys.time() |>
        with_tz(tzone = "America/New_York") |>
        floor_date(unit = "minute"),
      timezone            = "America/New_York",
      wait_time           = wait_time,
      wait_time_priority  = NA_real_,
      wait_time_pre_check = wait_time_pre_check,
      wait_time_clear     = NA_real_
    )
  }

  parse_pa_table <- function(page, airport_code) {
    # Shared shape for EWR/JFK/LGA -- all three are Port Authority sites on
    # the same Chakra UI table component, only the checkpoint-naming step
    # differs (EWR pairs Terminal+Gates, JFK/LGA just rename Terminal).
    results <- page |>
      rvest::html_elements("table") |>
      rvest::html_table(fill = TRUE) |>
      dplyr::bind_rows() |>
      suppressMessages() |>
      head(-1)  # drops the footer row

    results |>
      mutate(
        airport = airport_code,
        wait_time = case_when(
          stringr::str_trim(.data[["General"]]) == "No Wait" ~ 0,
          TRUE ~ readr::parse_number(.data[["General"]], na = c("-", "", "N/A", "No Wait"))
        ),
        wait_time_pre_check = case_when(
          str_trim(results[["TSA Pre✓"]]) == "No Wait" ~ 0,
          !is.na(readr::parse_number(results[["TSA Pre✓"]], na = c("-", "", "No Wait"))) ~
            readr::parse_number(results[["TSA Pre✓"]], na = c("-", "", "No Wait")),
          TRUE ~ NA_real_
        ),
        datetime           = lubridate::now(tzone = 'EST'),
        date               = lubridate::today(),
        time               = Sys.time() |>
          with_tz(tzone = "America/New_York") |>
          floor_date(unit = "minute"),
        timezone           = "America/New_York",
        wait_time_priority = NA_real_,
        wait_time_clear    = NA_real_
      )
  }

  parse_ewr <- function(page) {
    parse_pa_table(page, "EWR") |>
      mutate(
        checkpoint = stringr::str_squish(if_else(Gates == "All Gates", Terminal, paste(Terminal, Gates)))
      ) |>
      select(airport, checkpoint, datetime, date, time, timezone,
             wait_time, wait_time_priority, wait_time_pre_check, wait_time_clear)
  }

  parse_jfk <- function(page) {
    parse_pa_table(page, "JFK") |>
      rename(checkpoint = Terminal) |>
      mutate(checkpoint = stringr::str_squish(checkpoint)) |>
      select(airport, checkpoint, datetime, date, time, timezone,
             wait_time, wait_time_priority, wait_time_pre_check, wait_time_clear)
  }

  parse_lga <- function(page) {
    parse_pa_table(page, "LGA") |>
      rename(checkpoint = Terminal) |>
      mutate(checkpoint = stringr::str_squish(checkpoint)) |>
      select(airport, checkpoint, datetime, date, time, timezone,
             wait_time, wait_time_priority, wait_time_pre_check, wait_time_clear)
  }

  airports <- list(
    ATL = list(url = "https://www.atl.com/times/",         parse = parse_atl),
    EWR = list(url = "https://www.newarkairport.com/",      parse = parse_ewr),
    JFK = list(url = "https://www.jfkairport.com",           parse = parse_jfk),
    LGA = list(url = "https://www.laguardiaairport.com",     parse = parse_lga)
  )


  ####  ---------------------------------------------------------------- ####
  # Tracker -- one row per airport per attempt, written to
  # chromote_batch_scrape_log so the before/after success rate is
  # measurable against the ~0.4% baseline this script exists to fix.
  ####  ---------------------------------------------------------------- ####

  tryCatch({
    dbExecute(con_write, "
      CREATE TABLE IF NOT EXISTS chromote_batch_scrape_log (
        cycle_time TIMESTAMP,
        airport VARCHAR,
        attempt INTEGER,
        success BOOLEAN,
        error_message VARCHAR,
        duration_seconds DOUBLE
      )
    ")
  }, error = function(e) {
    message(Sys.time(), " | chromote_batch_scrape_log CREATE TABLE warning (non-fatal): ", e$message)
  })

  tracker <- tibble::tibble(
    cycle_time = as.POSIXct(character()),
    airport = character(),
    attempt = integer(),
    success = logical(),
    error_message = character(),
    duration_seconds = double()
  )

  # Scrapes one airport: loads the page (reusing the shared browser if one
  # is already alive), parses it, writes to tsa_wait_times, closes just that
  # tab (NOT the whole browser -- see final on.exit above). Returns TRUE/FALSE.
  scrape_one <- function(code, attempt) {
    t0 <- Sys.time()
    url <- airports[[code]]$url
    parse_fn <- airports[[code]]$parse

    result <- tryCatch({
      page <- safe_read_html_live(url)
      data <- parse_fn(page)
      try(page$session$close(), silent = TRUE)
      dbAppendTable(con_write, name = "tsa_wait_times", value = data)
      list(success = TRUE, n = nrow(data), error_message = NA_character_)
    }, error = function(e) {
      list(success = FALSE, n = 0, error_message = conditionMessage(e))
    })

    duration <- as.numeric(difftime(Sys.time(), t0, units = "secs"))

    tracker <<- dplyr::bind_rows(tracker, tibble::tibble(
      cycle_time = batch_start,
      airport = code,
      attempt = attempt,
      success = result$success,
      error_message = result$error_message,
      duration_seconds = duration
    ))

    if (result$success) {
      print(glue("{code}: {result$n} appended to tsa_wait_times (attempt {attempt}) at ",
                 format(Sys.time(), "%a %b %d %X %Y")))
    } else {
      print(glue("{code}: FAILED (attempt {attempt}): {result$error_message} at ",
                 format(Sys.time(), "%a %b %d %X %Y")))
    }

    result$success
  }

  succeeded <- function() {
    if (nrow(tracker) == 0) return(character(0))
    tracker |>
      dplyr::filter(success) |>
      dplyr::pull(airport) |>
      unique()
  }

  pending_after <- function() setdiff(names(airports), succeeded())


  ####  ---------------------------------------------------------------- ####
  # Pass 1: main pass, one shared browser, randomized order (matches the
  # orchestrator's existing human-mimicking randomization philosophy).
  ####  ---------------------------------------------------------------- ####

  Sys.sleep(5)  # one-time browser warm-up, replaces each legacy script's own ~1-2s delay

  for (code in sample(names(airports))) scrape_one(code, attempt = 1)

  pending <- pending_after()

  ####  ---------------------------------------------------------------- ####
  # Pass 2: retry pass A -- same browser, fresh tab. Cheap; handles the
  # common case of one slow page load.
  ####  ---------------------------------------------------------------- ####

  if (length(pending) > 0) {
    print(glue("CHROMOTE BATCH retry pass A (same browser) for: {paste(pending, collapse = ', ')}"))
    for (code in pending) scrape_one(code, attempt = 2)
    pending <- pending_after()
  }

  ####  ---------------------------------------------------------------- ####
  # Pass 3: retry pass B -- fresh browser, only for airports still failing.
  # Handles the case where the browser itself is in a bad state, without
  # paying a relaunch cost for airports that already succeeded.
  ####  ---------------------------------------------------------------- ####

  if (length(pending) > 0) {
    print(glue("CHROMOTE BATCH retry pass B (fresh browser) for: {paste(pending, collapse = ', ')}"))
    close_shared_browser()
    Sys.sleep(5)  # warm-up for the fresh browser
    for (code in pending) scrape_one(code, attempt = 3)
    pending <- pending_after()
  }

  tryCatch({
    dbAppendTable(con_write, name = "chromote_batch_scrape_log", value = tracker)
  }, error = function(e) {
    message(Sys.time(), " | chromote_batch_scrape_log append warning (non-fatal): ", e$message)
  })

  n_ok <- length(succeeded())
  print(glue("CHROMOTE BATCH complete: {n_ok}/4 succeeded",
             if (length(pending) > 0) glue(" (still failed: {paste(pending, collapse = ', ')})") else "",
             " at ", format(Sys.time(), "%a %b %d %X %Y")))

  # Final browser teardown handled by the on.exit() registered at the top
  # of this function.
}

####  --------------------------------------------------------------------- ####

# Test Run one time
# scrape_tsa_data_chromote_batch()
