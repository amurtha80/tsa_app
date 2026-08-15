# install.packages(c("DBI", "polite", "rvest", "tidyverse", "duckdb", 
#  "lubridate", "magrittr", glue", "here", "chromote"))

# library(polite, verbose = FALSE, warn.conflicts = FALSE)
# library(rvest, verbose = FALSE, warn.conflicts = FALSE)
# library(duckdb, verbose = FALSE, warn.conflicts = FALSE)
# library(lubridate, verbose = FALSE, warn.conflicts = FALSE)
# library(magrittr, verbose = FALSE, warn.conflicts = FALSE)
# library(glue, verbose = FALSE, warn.conflicts = FALSE)
# library(DBI, verbose = FALSE, warn.conflicts = FALSE)
# library(tidyverse, verbose = FALSE, warn.conflicts = FALSE)
# library(here, verbose = FALSE, warn.conflicts = FALSE)
# library(chromote, verbose = FALSE, warn.conflicts = FALSE)

# here::here()

# Database Connection ----

# con_write <- dbConnect(duckdb::duckdb(), dbdir = "01_Data/tsa_app.duckdb", read_only = FALSE)


####  --------------------------------------------------------------------- ####


# Function to scrape and store TSA checkpoint wait times
scrape_tsa_data_lga <- function() {
  
  print(glue("kickoff LGA scrape ", format(Sys.time(), "%a %b %d %X %Y")))

  # Always tear down the default chromote object on exit, success or failure.
  # See JFK_wait_times.R for why this must not only run at the bottom of the
  # function -- safe_read_html_live()'s stop() skips that entirely, leaking a
  # broken session into the next chromote airport script in this cycle.
  on.exit({
    tryCatch({
      if (exists("page", inherits = FALSE) && !is.null(page)) {
        try(page$session$close(), silent = TRUE)
        try(page$session$parent$close(wait = 2), silent = TRUE)
      }
      if (chromote::has_default_chromote_object()) {
        chromote::set_default_chromote_object(NULL)
      }
    }, error = function(e) {
      message(Sys.time(), " | LGA teardown warning (non-fatal): ", e$message)
    })
  }, add = TRUE)

  # Define URL and initiate polite session
  url <- "https://www.laguardiaairport.com" # Update with the actual URL
  
  session <- polite::bow(url)
  Sys.sleep(0.3)
  options(chromote.headless = "new")
  
  # Chrome binary: let chromote auto-detect an installed browser (matches
  # ATL_wait_times.R's existing pattern). Do NOT pin via
  # chromote::local_chrome_version(binary = "chrome-headless-shell") -- Google
  # does not publish Chrome-for-Testing builds for linux-arm64 (Pi), so that
  # call fails there. See project_pi_chromote_arm64_binary_fix memory.

  # page <- read_html_live(url)
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
        str_trim(results[["TSA Pre\u2713"]]) == "No Wait" ~ 0,
        !is.na(readr::parse_number(results[["TSA Pre\u2713"]], na = c("-", ""))) ~
          readr::parse_number(results[["TSA Pre\u2713"]], na = c("-", "")),
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
  
  
  # Insert observations into tsa_wait_times table
  dbAppendTable(con_write, name = "tsa_wait_times", value = LGA_data)
  
  # Cleanup to rerun
  # print(glue("session has run successfully ", format(Sys.time(), "%a %b %d %X %Y")))
  print(glue("{nrow(LGA_data)} row(s) appended to tsa_wait_times at ", format(Sys.time(), "%a %b %d %X %Y")))
  
  
  rm(results)
  rm(LGA_data, envir = .GlobalEnv)

  # Chromote teardown now handled by the on.exit() registered at the top of
  # this function, so it runs on both success and failure paths.

  # gc()

}

####  --------------------------------------------------------------------- ####

# Test Run one time
# scrape_tsa_data_lga()


# Test Run in loop
# i <- 1
# 
# for (i in 1:5) {
#   p1 <- lubridate::ceiling_date(Sys.time(), unit = "minute")
#     print(glue(i, "  ", format(Sys.time())))
#     scrape_tsa_data_lga()
#   theDelay <- as.numeric(difftime(p1,Sys.time(),unit="secs"))
#   Sys.sleep(max(0, theDelay))
#   
#   i <- i + 1
# }

# Close the server
# rm(i)
# rm(p1)
# rm(theDelay)
# dbDisconnect(con_write)
# rm(con_write)
# rm(scrape_tsa_data_lga)