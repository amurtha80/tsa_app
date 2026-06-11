  # install.packages(c("DBI", "polite", "rvest", "tidyverse", "duckdb", 
  #  "lubridate", "magrittr", glue", "here"))
  
  # library(polite, verbose = FALSE, warn.conflicts = FALSE)
  # library(rvest, verbose = FALSE, warn.conflicts = FALSE)
  # library(duckdb, verbose = FALSE, warn.conflicts = FALSE)
  # library(lubridate, verbose = FALSE, warn.conflicts = FALSE)
  # library(magrittr, verbose = FALSE, warn.conflicts = FALSE)
  # library(glue, verbose = FALSE, warn.conflicts = FALSE)
  # library(DBI, verbose = FALSE, warn.conflicts = FALSE)
  # library(tidyverse, verbose = FALSE, warn.conflicts = FALSE)
  # library(here, verbose = FALSE, warn.conflicts = FALSE)

  # here::here()
  
  # Database Connection ----
  
  # con_write <- dbConnect(duckdb::duckdb(), dbdir = "01_Data/tsa_app.duckdb", read_only = FALSE)
  
  # Script Function ----
  
  # Function to scrape and store TSA checkpoint wait times
scrape_tsa_data_atl <- function() {
    
  print(glue("kickoff ATL scrape ", format(Sys.time(), "%a %b %d %X %Y")))
  
  # Define URL and initiate polite session
  url <- "https://www.atl.com/times/"  # Update with the actual URL
  session <- polite::bow(url, user_agent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/100.0.4896.75 Safari/537.36")

  # Scrape and parse data
  page <- safe_read_html_live(url)
  Sys.sleep(2)  # Polite delay to avoid overwhelming the server
  
  
  # Scrape terminal headers (h1) and checkpoint names (h2) ----
  # Page layout: two h1 sections (DOMESTIC, INT'L), each with h2 checkpoint names below.
  # We scrape them separately and pair to build "DOMESTIC MAIN", "INT'L MAIN", etc.
  tsa_terminal <- page |>
    rvest::html_elements("div h1") |>
    rvest::html_text() |>
    stringr::str_trim() |>
    # h1 elements include page-level headings before the checkpoint sections;
    # the two terminal headers are the last two h1 elements on the page
    tail(2)
  
  
  tsa_checkpoint <- page |>
    rvest::html_elements("div h2") |>
    rvest::html_text() |>
    stringr::str_trim()
  
  
  # Page structure: DOMESTIC has 4 checkpoints (MAIN, NORTH, LOWER NORTH, SOUTH),
  # INT'L has 1 (MAIN). Build names dynamically from what was actually scraped.
  n_domestic <- length(tsa_checkpoint) - 1  # everything except the last = domestic
  n_intl     <- 1
  
  tsa_terminal_checkpoint <- c(
    paste0(tsa_terminal[1], " ", tsa_checkpoint[seq_len(n_domestic)]),
    paste0(tsa_terminal[2], " ", tsa_checkpoint[length(tsa_checkpoint)])
  )
  
  
  # Scrape wait time numbers ----
  # Numbers appear in styled span elements inside button elements.
  # Extract all, filter to numeric-only values to avoid picking up button labels.
  tsa_time_raw <- page |>
    rvest::html_elements("button span") |>
    rvest::html_text() |>
    stringr::str_trim()
  
  
  # Keep only values that parse as numeric (the actual minute counts)
  tsa_time <- readr::parse_number(tsa_time_raw, na = c("", "N/A", "Closed")) |>
    (\(x) x[!is.na(x)])()
  
  
  # Guard: if counts don't align, log and abort rather than write bad data
  if (length(tsa_time) != length(tsa_terminal_checkpoint)) {
    stop(glue(
      "ATL length mismatch: {length(tsa_terminal_checkpoint)} checkpoints, ",
      "{length(tsa_time)} times. Raw button spans: ",
      paste(tsa_time_raw, collapse = " | ")
    ))
  }
  
  
  # Identify PreCheck-only checkpoints by their h3 label in the HTML ----
  # The page marks these with "PRECHECK ONLY CHECKPOINT" in the h3 element.
  # Scrape all h3 texts and flag any checkpoint whose h3 contains that string.
  # This is more robust than matching on checkpoint name (e.g. "SOUTH").
  checkpoint_h3 <- page |>
    rvest::html_elements("div h3") |>
    rvest::html_text() |>
    stringr::str_trim() |>
    tail(length(tsa_terminal_checkpoint))  # keep only the checkpoint h3s
  
  # h3 count matches checkpoint count (one h3 per checkpoint block)
  is_precheck_only <- grepl("PRECHECK ONLY", checkpoint_h3, ignore.case = TRUE)
  
  wait_time <- dplyr::if_else(is_precheck_only, NA_real_, as.numeric(tsa_time))
  wait_time_pre_check <- dplyr::if_else(is_precheck_only, as.numeric(tsa_time), NA_real_)
  
  
  # Create empty tibble to append data to, or get existing tibble if it already 
  # exists in the global environment
  if(!exists("ATL_data", envir = .GlobalEnv)) {
    ATL_data <- tibble(airport = character(),
           checkpoint = character(),
           datetime = lubridate::ymd_hms(tz = 'EST'),
           date = lubridate::ymd(),
           time = lubridate::POSIXct(tz = 'EST'),
           timezone = character(),
           wait_time = numeric(),
           wait_time_priority = numeric(),
           wait_time_pre_check = numeric(),
           wait_time_clear = numeric())
  } else {
    ATL_data <- get("ATL_data", envir = .GlobalEnv)
  }
  

    # Prepare data with airport code, date, time, timezone, and wait times
  ATL_data <- rows_append(ATL_data, tibble(
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
  ))
    
  
  assign("ATL_data", ATL_data, envir = .GlobalEnv)  
  

  dbAppendTable(con_write, name = "tsa_wait_times", value = ATL_data)
  
  
  # print(glue("session has run successfully ", format(Sys.time(), "%a %b %d %X %Y")))
  print(glue("{nrow(ATL_data)} appended to tsa_wait_times at ", format(Sys.time(), "%a %b %d %X %Y")))
  
  
  # Cleanup ----
  rm(tsa_terminal, tsa_checkpoint, tsa_terminal_checkpoint)
  rm(tsa_time_raw, tsa_time, checkpoint_h3, is_precheck_only, n_domestic, n_intl)
  rm(wait_time, wait_time_pre_check)
  rm(page, session, url)
  rm(ATL_data, envir = .GlobalEnv)
  
  #gc()
}
  
####  --------------------------------------------------------------------- ####
  
  # Loop Funtion For Test ----
  
# i <- 1
#   
# for (i in 1:5) {
#   p1 <- lubridate::ceiling_date(Sys.time(), unit = "minute")
#   print(glue(i, "  ", format(Sys.time())))
#   scrape_tsa_data_atl()
#   theDelay <- as.numeric(difftime(p1,Sys.time(),unit="secs"))
#   Sys.sleep(max(0, theDelay))
#   
#   i <- i + 1
# }
  
  # Disconnect DB ----
  
# rm(i)
# rm(p1)
# rm(theDelay)
# dbDisconnect(con)
# rm(con)
# rm(scrape_tsa_data_atl)
