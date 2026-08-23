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
# DUPLICATION NOTICE: EWR/JFK/LGA's parsing logic below is COPIED from
# EWR_wait_times.R / JFK_wait_times.R / LGA_wait_times.R, not shared with
# them (deliberate choice -- see project_chromote_batch_scraper_design
# memory). Those 3 files are left fully untouched and independently
# runnable so a future hardware upgrade can pivot back to
# one-airport-per-script with zero rework. If any of those 3 sites' HTML
# layout changes and a parser needs fixing, the matching parser in THIS
# file needs the identical fix -- they will not stay in sync automatically.
# ATL_wait_times.R was renamed to ATL_wait_times_DISABLED.R on 2026-08-22
# (dropped out of the orchestrator's glob) once atl.com went behind
# Cloudflare -- there is no legacy ATL script left to stay in sync with.
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

  ####  ---------------------------------------------------------------- ####
  # ATL -- fully isolated path, NOT part of the shared-browser flow below.
  #
  # atl.com relaunched its wait-times page on 2026-08-22 behind a Cloudflare
  # managed challenge ("Just a moment..."). A plain httr2/curl request
  # cannot pass it under any header combination -- confirmed directly
  # (403 Forbidden even with a full realistic Chrome header set) -- because
  # the challenge requires executing JS to compute a proof-of-work token.
  # A real headless Chrome CAN pass it, but only if its User-Agent string
  # doesn't contain "HeadlessChrome" (chromote's raw default does; rvest's
  # read_html_live() already overrides it to a clean string internally, and
  # that alone is sufficient -- no manual UA/launch-arg override needed or
  # wanted, see below).
  #
  # Even past Cloudflare, ATL's new checkpoint cards render via a delayed
  # client-side AJAX call, not at Page.loadEventFired, and that render is
  # meaningfully less reliable than EWR/JFK/LGA (~60-70% success per
  # attempt in repeated scratchpad testing 2026-08-22, vs. those three's
  # near-100%). A hung/never-resolving attempt is a real risk here in a way
  # it isn't for the other three, so this MUST run in its own bounded
  # subprocess rather than inline in the shared browser used below:
  #   - callr::r(..., timeout=) guarantees a hard wall-clock cap and kills
  #     the whole subprocess tree if exceeded, so a stuck ATL attempt can
  #     never stall the rest of the batch (confirmed: a raw
  #     read_html_live() call can hang past chromote's own internal
  #     timeout with no error ever thrown).
  #   - Even on ordinary success/error returns (no timeout), chromote's own
  #     close()/on.exit patterns were observed leaving orphaned
  #     zygote/renderer/gpu child processes behind on the Pi in repeated
  #     testing -- graceful close(), processx kill_tree(), and
  #     ps::ps_kill_tree() (wrong API -- that function takes a marker
  #     string, not a handle) were all tried and all left zombies on some
  #     runs. The only approach that was 100% clean across ~20 repeated
  #     trials (successes, thrown errors, AND forced callr timeouts) is an
  #     outer-process PID diff: snapshot chrome-related PIDs before and
  #     after the callr call, hard-kill whatever is new. Safe here because
  #     scrape_one() below runs airports sequentially, never concurrently,
  #     so nothing else can spawn a matching process in that window.
  atl_chrome_pids <- function() {
    out <- tryCatch(
      system("ps aux | grep -i chrom | grep -v grep | awk '{print $2}'",
             intern = TRUE, ignore.stderr = TRUE),
      error = function(e) character(0)
    )
    out[grepl("^[0-9]+$", out)]  # keep only well-formed numeric PIDs
  }

  scrape_atl_isolated <- function() {
    atl_job <- function() {
      library(chromote); library(rvest); library(stringr)
      library(dplyr); library(glue); library(lubridate)

      options(chromote.headless = "new")

      parse_atl <- function(page) {
        # .atl-wt-card cards populate via client-side AJAX after the load
        # event -- html_elements() on a live page does NOT auto-wait for a
        # selector to appear, so poll for it (observed up to ~14s delay).
        deadline <- Sys.time() + 20
        cards <- rvest::html_elements(page, ".atl-wt-card")
        while (length(cards) == 0 && Sys.time() < deadline) {
          Sys.sleep(0.5)
          cards <- rvest::html_elements(page, ".atl-wt-card")
        }
        if (length(cards) == 0) {
          stop("ATL: no .atl-wt-card elements found after 20s wait (Cloudflare block or page structure change)")
        }

        # data-checkpoint (stable, ATL-assigned machine id) -> existing
        # tsa_wait_times checkpoint name, so history stays continuous
        # across the redesign.
        checkpoint_map <- c(
          main        = "DOMESTIC MAIN",
          north       = "DOMESTIC NORTH",
          lower_north = "DOMESTIC LOWER NORTH",
          south       = "DOMESTIC SOUTH",
          intl_main   = "INT'L MAIN"
        )

        rows <- purrr::map_dfr(cards, function(card) {
          cp_id <- rvest::html_elements(card, "[data-checkpoint]") |>
            rvest::html_attr("data-checkpoint")
          sr_text <- rvest::html_elements(card, ".atl-wt-sr-only") |>
            rvest::html_text() |>
            stringr::str_squish()

          if (length(cp_id) != 1 || length(sr_text) != 1) {
            stop(glue("ATL card parse failure: cp_id={paste(cp_id, collapse=',')} sr_text={paste(sr_text, collapse=',')}"))
          }
          if (!cp_id %in% names(checkpoint_map)) {
            stop(glue("ATL: unrecognized data-checkpoint id '{cp_id}' -- new checkpoint added on site?"))
          }

          # sr-only text is the single most reliable source, e.g. "North
          # checkpoint: 0 minute wait, Low, open." or "Main checkpoint:
          # Closed." -- no PreCheck-only distinction exists anywhere on
          # the new page (confirmed: zero "recheck" matches in the full
          # rendered HTML), unlike the old page's PRECHECK ONLY h3 label,
          # so wait_time_pre_check is always NA going forward.
          is_closed <- stringr::str_detect(sr_text, stringr::regex("closed", ignore_case = TRUE))
          wait_time <- if (is_closed) NA_real_ else readr::parse_number(sr_text)

          tibble::tibble(checkpoint = checkpoint_map[[cp_id]], wait_time = wait_time)
        })

        if (nrow(rows) != length(checkpoint_map)) {
          stop(glue(
            "ATL length mismatch: {nrow(rows)} checkpoint rows parsed, ",
            "{length(checkpoint_map)} expected."
          ))
        }

        tibble::tibble(
          airport             = "ATL",
          checkpoint          = rows$checkpoint,
          datetime            = lubridate::now(tzone = "America/New_York"),
          date                = lubridate::today(),
          time                = Sys.time() |>
            with_tz(tzone = "America/New_York") |>
            floor_date(unit = "minute"),
          timezone            = "America/New_York",
          wait_time           = rows$wait_time,
          wait_time_priority  = NA_real_,
          wait_time_pre_check = NA_real_,
          wait_time_clear     = NA_real_
        )
      }

      page <- tryCatch(read_html_live("https://www.atl.com/times/"), error = function(e) NULL)
      if (is.null(page)) {
        Sys.sleep(2)
        page <- read_html_live("https://www.atl.com/times/")
      }
      result <- parse_atl(page)
      try(page$session$close(), silent = TRUE)
      result
    }

    pids_before <- atl_chrome_pids()
    # on.exit (not code after the call) so cleanup runs whether callr::r()
    # returns normally OR throws (subprocess error or hard timeout) --
    # letting the error propagate is required so scrape_one()'s own
    # tryCatch below sees the failure and the batch's retry passes work.
    on.exit({
      pids_after <- atl_chrome_pids()
      leaked <- setdiff(pids_after, pids_before)
      if (length(leaked) > 0) {
        message(Sys.time(), " | ATL cleaning up ", length(leaked), " leaked chrome PID(s): ",
                paste(leaked, collapse = ", "))
        system(paste("kill -9", paste(leaked, collapse = " ")), ignore.stdout = TRUE, ignore.stderr = TRUE)
      }
    }, add = TRUE)

    callr::r(atl_job, timeout = 45)
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
    ATL = list(url = "https://www.atl.com/times/",          parse = NULL),  # routed through scrape_atl_isolated() in scrape_one() below, not this generic path
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

    result <- tryCatch({
      data <- if (code == "ATL") {
        scrape_atl_isolated()
      } else {
        page <- safe_read_html_live(airports[[code]]$url)
        d <- airports[[code]]$parse(page)
        try(page$session$close(), silent = TRUE)
        d
      }
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
