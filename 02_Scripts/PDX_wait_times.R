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
scrape_tsa_data_pdx <- function() {
  
  print(glue("kickoff PDX scrape ", format(Sys.time(), "%a %b %d %X %Y")))
  
  
  # Define URL and initiate polite session
  url <- "https://www.flypdx.com"  # Update with the actual URL
  
  
  session <- polite::bow(url)
  options(chromote.headless = "new")
  
  # Scrape and parse data
  # page <- polite::scrape(session)
  page <- safe_read_html_live(url)
  
  
  ####  --------------------------------------------------------------------- ####
  
  gates <- page |> 
    html_elements('.checkpoint-name') |> 
    html_text2()
  
  
  wait_time <- page |> 
    html_elements('.general-boarding .wait-time') |> 
    html_text2() |> 
    gsub(pattern = ' ', replacement = 'NA') |> 
    as.numeric() |> 
    suppressWarnings() 
  
  
  wait_time_pre_check <- page |> 
    html_elements('.tsa-precheck .wait-time') |> 
    html_text2() |> 
    gsub(pattern = ' ', replacement = 'NA') |> 
    as.numeric() |> 
    suppressWarnings()
  
  
  ####  --------------------------------------------------------------------- ####  
  
  
  # Check to make Sure that TSA CheckPoint and Time have the same length
  if(length(wait_time) != length(gates)){
    stop("The length of tsa_time and tsa_terminal_checkpoint do not match.")
  }  
  if(length(wait_time_pre_check) != length(gates)){
    stop("The length of tsa_time_pre_check and gates do not match.")
  }
  
  # Create tibble for data insertion
  if(!exists("PDX_data", envir = .GlobalEnv)) {
    PDX_data <- tibble(airport = character(),
                       checkpoint = character(),
                       datetime = lubridate::ymd_hms(tz = 'America/Los_Angeles'),
                       date = lubridate::ymd(),
                       time = lubridate::POSIXct(tz = 'America/Los_Angeles'),
                       timezone = character(),
                       wait_time = numeric(),
                       wait_time_priority = numeric(),
                       wait_time_pre_check = numeric(),
                       wait_time_clear = numeric())
  } else {
    PDX_data <- get("PDX_data", envir = .GlobalEnv)
  }
  
  
  # Insert data into tibble
  # Prepare data with airport code, date, time, timezone, and wait times
  PDX_data <- rows_append(PDX_data, tibble(
    airport = "PDX",
    checkpoint = gates,
    datetime = lubridate::now(tzone = 'America/Los_Angeles'),
    date = lubridate::today(),
    time = Sys.time() |> 
      with_tz(tzone = "America/Los_Angeles") |> 
      floor_date(unit = "minute"),
    # time = lubridate::now(tzone = 'EST') |>
    # floor_date(unit = "minute") |>
    # with_tz('EST'),
    # format("%H:%M:%S"),
    # hms::new_hms(),
    timezone = "America/Los_Angeles",
    wait_time = wait_time,  # Assume this is a list of wait times for each checkpoint
    wait_time_priority = NA,
    wait_time_pre_check = wait_time_pre_check,
    wait_time_clear = NA
  ))
  
  
  assign("PDX_data", PDX_data, envir = .GlobalEnv)  
  
  
  dbAppendTable(con_write, name = "tsa_wait_times", value = PDX_data)
  
  
  # print(glue("session has run successfully ", format(Sys.time(), "%a %b %d %X %Y")))
  print(glue("{nrow(PDX_data)} appended to tsa_wait_times at ", format(Sys.time(), "%a %b %d %X %Y")))
  
  
  rm(gates)
  rm(wait_time)
  rm(wait_time_pre_check)
  rm(PDX_data, envir = .GlobalEnv)
  
  page$session$close()
  rm(page)
  
  rm(session)
  rm(url)
  # gc()
  
}


# Test Loop ----
# i <- 1
# 
# for (i in 1:5) {
#   p1 <- lubridate::ceiling_date(Sys.time(), unit = "minute")
#   print(glue(i, "  ", format(Sys.time())))
#   scrape_tsa_data_pdx()
#   theDelay <- as.numeric(difftime(p1,Sys.time(),unit="secs"))
#   Sys.sleep(max(0, theDelay))
#   
#   i <- i + 1
# }

# Cleanup ----
# rm(i)
# rm(p1)
# rm(theDelay)
# dbDisconnect(con)
# rm(con)
# rm(scrape_tsa_data_pdx)