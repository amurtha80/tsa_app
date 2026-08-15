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

scrape_tsa_data_jfk <- function() {

  print(glue("kickoff JFK scrape ", format(Sys.time(), "%a %b %d %X %Y")))

  # Always tear down the default chromote object on exit, success or failure.
  # Previously this only happened at the bottom of the function, which
  # safe_read_html_live()'s stop() (on a failed page load) skips entirely --
  # leaving an orphaned/broken default chromote session that the NEXT
  # chromote airport script in this cycle (ATL/EWR/LGA) would try to reuse,
  # producing cascading "Chromote has been closed" / port errors that look
  # like site outages but are actually caused by this script's own failure.
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
      message(Sys.time(), " | JFK teardown warning (non-fatal): ", e$message)
    })
  }, add = TRUE)

  url <- "https://www.jfkairport.com"
  
  session <- polite::bow(url)
  Sys.sleep(0.3)
  options(chromote.headless = "new")
  
  # Chrome binary: let chromote auto-detect an installed browser (matches
  # ATL_wait_times.R's existing pattern). Do NOT pin via
  # chromote::local_chrome_version(binary = "chrome-headless-shell") -- Google
  # does not publish Chrome-for-Testing builds for linux-arm64 (Pi), so that
  # call fails there. See project_pi_chromote_arm64_binary_fix memory.

  page <- safe_read_html_live(url)
  Sys.sleep(1.5)

####  --------------------------------------------------------------------- ####
  
  results <- page |> 
    html_elements('table') |>
    # html_elements('.chakra-table__body.css-0') |>
    # html_elements('.av-responsive-table') |> 
    html_table(fill = TRUE) |> 
    dplyr::bind_rows() |> 
    head(-1) |> 
    suppressMessages()
  
  
  # Transform Data ----
  JFK_data <- results |>
    mutate(
      airport = 'JFK',
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
  assign("JFK_data", JFK_data, envir = .GlobalEnv) 
  
  
  # Insert observations into tsa_wait_times table
  dbAppendTable(con_write, name = "tsa_wait_times", value = JFK_data)
  
  
  # Cleanup to rerun
  # print(glue("session has run successfully ", format(Sys.time(), "%a %b %d %X %Y")))
  print(glue("{nrow(JFK_data)} row(s) appended to tsa_wait_times at ", format(Sys.time(), "%a %b %d %X %Y")))
  
  
  # rm(checkpoints)
  # rm(notes)
  # rm(data)
  
  rm(results)
  rm(JFK_data, envir = .GlobalEnv)

  # Chromote teardown now handled by the on.exit() registered at the top of
  # this function, so it runs on both success and failure paths.

  # gc()

}

####  --------------------------------------------------------------------- ####

# Test Run one time
# scrape_tsa_data_jfk()


# Test Run in loop
# i <- 1
# 
# for (i in 1:5) {
#   p1 <- lubridate::ceiling_date(Sys.time(), unit = "minute")
#     print(glue(i, "  ", format(Sys.time())))
#     scrape_tsa_data_jfk()
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
# rm(scrape_tsa_data_jfk)
