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


# Script Function ----

# Function to scrape and store TSA checkpoint wait times
scrape_tsa_data_dca <- function() {
  
  print(glue("kickoff DCA scrape ", format(Sys.time(), "%a %b %d %X %Y")))
  
  
  url <- 'https://www.flyreagan.com/travel-information/security-information' # Update with the actual URL
  
  session <- polite::bow(url)
  options(chromote.headless = "new")
  
  # Initialize a new Chrome session with the latest stable version of Chrome 
  # and specify the binary for chrome-headless-shell
  chromote::local_chrome_version(version = "latest-stable", binary = "chrome-headless-shell")
  
  # Scrape and parse data
  # page <- polite::scrape(session)
  page <- safe_read_html_live(url)
  Sys.sleep(2.0) # Polite delay to ensure page is fully loaded
  
  # Scrape ----
  # Pull every row div, then within each row grab the 4 table-body-cell divs
  # by position: [1] checkpoint name, [2] General time, [3] TSA Pre time, [4] Directions (ignored)
  rows <- page |>
  rvest::html_elements(".resp-table-row")
  
  if (length(rows) == 0) {
    stop("DCA: no .resp-table-row elements found — page may not have loaded fully")
  }
  
  parse_cell <- function(row, position) {
    row |>
      rvest::html_elements(".table-body-cell") |>
      magrittr::extract(position) |>
      rvest::html_text2() |>
      stringr::str_trim()
  }
  
  checkpoints <- purrr::map_chr(rows, \(r) parse_cell(r, 1))
  
  raw_general <- purrr::map_chr(rows, \(r) {
    cells <- r |> rvest::html_elements(".table-body-cell")
    if (length(cells) < 2) return(NA_character_)
    cells[[2]] |> rvest::html_text2() |> stringr::str_trim()
  })
  
  raw_pre <- purrr::map_chr(rows, \(r) {
    cells <- r |> rvest::html_elements(".table-body-cell")
    if (length(cells) < 3) return(NA_character_)
    cells[[3]] |> rvest::html_text2() |> stringr::str_trim()
  })
  
  # Parse time values ----
  # Values arrive as "< 5 mins", "12 mins", or empty string (no service at that checkpoint)
  # Extract the numeric portion; "< 5" becomes 5 (ceiling of the stated bound)
  parse_time <- function(x) {
    dplyr::case_when(
      is.na(x) | x == ""          ~ NA_real_,
      stringr::str_detect(x, "^<") ~ readr::parse_number(x, na = c("", "N/A")),
      TRUE                          ~ readr::parse_number(x, na = c("", "N/A"))
    )
  }
  
  wait_time           <- parse_time(raw_general)
  wait_time_pre_check <- parse_time(raw_pre)

  # Guard: an occasional row on this page renders with a blank checkpoint name
  # (a divider/empty row, not a real checkpoint) -- drop it rather than write a
  # row that can never join against airport_checkpoint_hours
  keep <- !is.na(checkpoints) & stringr::str_trim(checkpoints) != ""
  checkpoints         <- checkpoints[keep]
  wait_time           <- wait_time[keep]
  wait_time_pre_check <- wait_time_pre_check[keep]


  # Build output tibble ----
  if (!exists("DCA_data", envir = .GlobalEnv)) {
    DCA_data <- tibble(
      airport             = character(),
      checkpoint          = character(),
      datetime            = lubridate::ymd_hms(tz = "America/New_York"),
      date                = lubridate::ymd(character()),
      time                = lubridate::POSIXct(tz = "America/New_York"),
      timezone            = character(),
      wait_time           = numeric(),
      wait_time_priority  = numeric(),
      wait_time_pre_check = numeric(),
      wait_time_clear     = numeric()
    )
  } else {
    DCA_data <- get("DCA_data", envir = .GlobalEnv)
  }
  
  DCA_data <- rows_append(DCA_data, tibble(
    airport             = "DCA",
    checkpoint          = checkpoints,
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
  
  
  assign("DCA_data", DCA_data, envir = .GlobalEnv)  
  
  dbAppendTable(con_write, name = "tsa_wait_times", value = DCA_data)
  
  # print(glue("session has run successfully ", format(Sys.time(), "%a %b %d %X %Y")))
  print(glue("{nrow(DCA_data)} appended to tsa_wait_times at ", format(Sys.time(), "%a %b %d %X %Y")))
  
  
  # Cleanup ----
  rm(rows, checkpoints, raw_general, raw_pre, wait_time, wait_time_pre_check, parse_cell, parse_time)
  rm(DCA_data, envir = .GlobalEnv)
  
  
  tryCatch({
    page$session$close()
    page$session$parent$close(wait = 2)
    if (chromote::has_default_chromote_object()) {
      chromote::set_default_chromote_object(NULL)
    }
  }, error = function(e) {
    message(Sys.time(), " | DCA teardown warning (non-fatal): ", e$message)
  }, finally = {
    rm(page)
    rm(session)
    rm(url)
  })
  
  # gc()
}


# Test Loop ----
# i <- 1
# 
# for (i in 1:24) {
#   p1 <- lubridate::ceiling_date(Sys.time(), unit = "minute")
# 
#   print(glue(i, "  ", format(Sys.time())))
# 
#   scrape_tsa_data_dca()
# 
#   theDelay <- as.numeric(difftime(p1,Sys.time(),unit="secs"))
# 
#   i <- i + 1
# 
#   if(i == 25) {
#     break()
#   } else {
#     Sys.sleep(max(0, theDelay))
#   }
# 
# }


# Cleanup ----
# rm(i)
# rm(p1)
# rm(theDelay)
# dbDisconnect(con)
# rm(con)
# rm(scrape_tsa_data_dca)