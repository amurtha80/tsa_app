# 02_Scripts/pi_baketest/LGA_wait_times_pi.R
#
# Phase 0 bake-off variant of ../LGA_wait_times.R. Scrape/transform logic is
# unchanged from the production script -- the only difference is the Chrome
# launch step. On Linux/aarch64 (Pi) and any host without a Chrome for
# Testing build, chromote::local_chrome_version() itself errors out (Google
# publishes no Linux arm64 Chrome for Testing build at all). The orchestrator
# already sets options(chromote.chrome = <path to system chromium-browser>)
# before sourcing this file, which is sufficient for chromote to launch a
# session -- so that discovery call is just dropped here instead.
#
# Keep in sync with ../LGA_wait_times.R if the scrape/transform logic there
# changes.

scrape_tsa_data_lga <- function() {

  print(glue("kickoff LGA scrape ", format(Sys.time(), "%a %b %d %X %Y")))

  # Define URL and initiate polite session
  url <- "https://www.laguardiaairport.com"

  session <- polite::bow(url)
  Sys.sleep(0.3)
  options(chromote.headless = "new")

  # (No chromote::local_chrome_version() call here -- see header note.
  # options(chromote.chrome = ...) set by the orchestrator handles binary
  # discovery on this host.)

  page <- safe_read_html_live(url)
  Sys.sleep(1.5)

  # Read TSA Checkpoint Wait Time Data from Website Table
  results <- page |>
    html_elements('table') |>
    html_table(fill = TRUE) |>
    dplyr::bind_rows() |>
    head(-1) |>
    suppressMessages()


  # Transform Data ----
  LGA_data <- results |>
    mutate(
      airport = 'LGA',
      # General wait time — "No Wait" → 0, numeric string → value, else NA
      wait_time = case_when(
        stringr::str_trim(.data[["General"]]) == "No Wait" ~ 0,
        TRUE ~ readr::parse_number(.data[["General"]], na = c("-", "", "N/A", "No Wait"))
      ),
      # TSA PreCheck wait time — same logic
      wait_time_pre_check = case_when(
        str_trim(results[["TSA Pre✓"]]) == "No Wait" ~ 0,
        !is.na(readr::parse_number(results[["TSA Pre✓"]], na = c("-", ""))) ~
          readr::parse_number(results[["TSA Pre✓"]], na = c("-", "")),
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
    ) |>
    rename(checkpoint = Terminal) |>
    mutate(checkpoint = stringr::str_squish(checkpoint)) |>
    select(airport, checkpoint, datetime, date, time, timezone,
           wait_time, wait_time_priority, wait_time_pre_check, wait_time_clear)


  # Assign to Global Environment
  assign("LGA_data", LGA_data, envir = .GlobalEnv)


  # Insert observations into tsa_wait_times table (scratch DB, not production)
  dbAppendTable(con_write, name = "tsa_wait_times", value = LGA_data)

  print(glue("{nrow(LGA_data)} row(s) appended to tsa_wait_times at ", format(Sys.time(), "%a %b %d %X %Y")))


  rm(results)
  rm(LGA_data, envir = .GlobalEnv)

  tryCatch({
    page$session$close()
    page$session$parent$close(wait = 2)
    if (chromote::has_default_chromote_object()) {
      chromote::set_default_chromote_object(NULL)
    }
  }, error = function(e) {
    message(Sys.time(), " | LGA teardown warning (non-fatal): ", e$message)
  }, finally = {
    rm(page)
    rm(session)
    rm(url)
  })

}
