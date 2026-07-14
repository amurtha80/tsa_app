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


# Function to scrape and store TSA checkpoint wait times
scrape_tsa_data_ewr <- function() {
  
  print(glue("kickoff EWR scrape ", format(Sys.time(), "%a %b %d %X %Y")))
  
  # Define URL and initiate polite session
  url <- "https://www.newarkairport.com/"  # Update with the actual URL
  session <- polite::bow(url)
  options(chromote.headless = "new")
  
  # Initialize a new Chrome session with the latest stable version of Chrome 
  # and specify the binary for chrome-headless-shell
  chromote::local_chrome_version(version = "latest-stable", binary = "chrome-headless-shell")
  
  # Access Page
  page <- safe_read_html_live(url)
  Sys.sleep(1.2)
  
  
  # Scrape wait-times table ----
  # NOTE: The Port Authority redesigned their airport sites in 2026. The table CSS class
  # changed from '.av-responsive-table' to '.Table_tableContainer__Hwsqp'
  # (same Chakra UI component across all three PA airports).
  results <- page |>
    html_elements('table') |>
    html_table(fill = TRUE) |>
    dplyr::bind_rows() |>
    suppressMessages() |>
    head(-1)  # drops the footer row "Security wait times are calculated..."
  
  
  # Transform Data ----
  EWR_data <- results |>
    mutate(
      airport = 'EWR',
      # General wait time — "No Wait" → 0, numeric string → value, else NA
      wait_time = case_when(
        stringr::str_trim(.data[["General"]]) == "No Wait" ~ 0,
        TRUE ~ readr::parse_number(.data[["General"]], na = c("-", "", "N/A", "No Wait"))
      ),
      # TSA PreCheck wait time — same logic
      wait_time_pre_check = case_when(
        str_trim(results[["TSA Pre\u2713"]]) == "No Wait" ~ 0,
        !is.na(readr::parse_number(results[["TSA Pre\u2713"]], na = c("-", "", "No Wait"))) ~
          readr::parse_number(results[["TSA Pre\u2713"]], na = c("-", "", "No Wait")),
        TRUE ~ NA_real_
      ),
      # DateTime fields
      datetime           = lubridate::now(tzone = 'EST'),
      date               = lubridate::today(),
      time               = Sys.time() |>
        with_tz(tzone = "America/New_York") |>
        floor_date(unit = "minute"),
      timezone           = "America/New_York",
      wait_time_priority = NA_real_,
      wait_time_clear    = NA_real_
    ) |>
    mutate(
      checkpoint = stringr::str_squish(if_else(Gates == "All Gates", Terminal, paste(Terminal, Gates)))
    ) |>
    select(airport, checkpoint, datetime, date, time, timezone,
           wait_time, wait_time_priority, wait_time_pre_check, wait_time_clear) 
  
  
  # Assign to Global Environment
  assign("EWR_data", EWR_data, envir = .GlobalEnv) 
  
  
  # Insert observations into tsa_wait_times table
  dbAppendTable(con_write, name = "tsa_wait_times", value = EWR_data)
  
  
  # Cleanup to rerun
  # print(glue("session has run successfully ", format(Sys.time(), "%a %b %d %X %Y")))
  print(glue("{nrow(EWR_data)} appended to tsa_wait_times at ", format(Sys.time(), "%a %b %d %X %Y")))
  
  rm(results)
  rm(EWR_data, envir = .GlobalEnv)
  
  # June 2026 - New Tear-down Methodology to avoid Headless Chrome Temp files
  # in Windows environment. This is due to changes in chromote between 2025 and
  # 2026
  tryCatch({
    page$session$close()
    page$session$parent$close(wait = 2)
    if (chromote::has_default_chromote_object()) {
      chromote::set_default_chromote_object(NULL)
    }
  }, error = function(e) {
    message(Sys.time(), " | EWR teardown warning (non-fatal): ", e$message)
  }, finally = {
    rm(page)
    rm(session)
    rm(url)
  })
  
  # gc()
  
}


# scrape_tsa_data_ewr()

# Loop Funtion For Test ----

# i <- 1
#   
# for (i in 1:5) {
#   p1 <- lubridate::ceiling_date(Sys.time(), unit = "minute")
#   print(glue(i, "  ", format(Sys.time())))
#   scrape_tsa_data_ewr()
#   theDelay <- as.numeric(difftime(p1,Sys.time(),unit="secs"))
#   Sys.sleep(max(0, theDelay))
#   
#   i <- i + 1
# }

# Disconnect DB ----

# rm(i)
# rm(p1)
# rm(theDelay)
# dbDisconnect(con, shutdown = T)
# rm(con)
# rm(scrape_tsa_data_ewr)
