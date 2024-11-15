# Code is working, and has been tested to run into duckdb database

# install.packages(c("DBI", "polite", "rvest", "tidyverse", "duckdb", 
#  "lubridate", "glue", "magrittr", "here"))

library(polite, verbose = FALSE)
library(rvest, verbose = FALSE)
library(duckdb, verbose = FALSE)
library(lubridate, verbose = FALSE)
library(magrittr, verbose = FALSE)
library(glue, verbose = FALSE)
library(DBI, verbose = FALSE)
library(tidyverse, verbose = FALSE)
library(here, verbose = FALSE)

here::here()

# Database Connection ----
con <- dbConnect(duckdb::duckdb(), dbdir = "02_Data/tsa_app.duckdb", read_only = FALSE)

# Script Function ----

# Function to scrape and store TSA checkpoint wait times
scrape_tsa_data <- function() {
  # Define URL and initiate polite session
  url <- "https://www.atl.com/times/"  # Update with the actual URL
  session <- polite::bow(url)
  
# Scrape and parse data
# page <- polite::scrape(session)
page <- read_html(url)
tsa_terminal <- page |> 
  rvest::html_elements("div h1") |> 
  rvest::html_text() |> 
  str_trim() |>  
  magrittr::extract(3:4)

tsa_checkpoint <- page |> 
  rvest::html_elements("div h2") |> 
  rvest::html_text() |> 
  str_trim()

tsa_terminal_checkpoint <- c(paste0(tsa_terminal[1]," ",tsa_checkpoint[1]), paste0(
  tsa_terminal[1]," ",tsa_checkpoint[2]), paste0(tsa_terminal[1]," ",tsa_checkpoint[3]),
  paste0(tsa_terminal[1]," ",tsa_checkpoint[4]), paste0(tsa_terminal[2]," ",tsa_checkpoint[5])
)

rm(tsa_terminal, tsa_checkpoint)

tsa_time <- page %>%
  rvest::html_elements("button span") %>%  # Replace with the actual CSS selector
  rvest::html_text() %>% 
  str_trim() %>%
  as.numeric()
  
# Check to make Sure that TSA CheckPoint and Time have the same length
if(length(tsa_time) != length(tsa_terminal_checkpoint)){
  stop("The length of tsa_time and tsa_terminal_checkpoint do not match.")
}

if(!exists("ATL_data", envir = .GlobalEnv)) {
  ATL_data <- tibble(airport = character(),
         checkpoint = character(),
         datetime = lubridate::ymd_hms(tz = 'EST'),
         date = lubridate::ymd(),
         time = lubridate::POSIXct(tz = 'EST'),
         timezone = character(),
         wait_time = numeric())
} else {
  ATL_data <- get("ATL_data", envir = .GlobalEnv)
}

# time = lubridate::now(tzone = 'EST') |> floor_date(unit = "minute")
# time

# time2 = Sys.time() |> with_tz(tzone = "America/New_York") |> floor_date(unit = "minute")
# time2
  
  # Prepare data with airport code, date, time, timezone, and wait times
  ATL_data <- rows_append(ATL_data, tibble(
    airport = "ATL",
    checkpoint = tsa_terminal_checkpoint,
    datetime = lubridate::now(tzone = 'EST'),
    date = lubridate::today(),
    time = Sys.time() |> 
      with_tz(tzone = "America/New_York") |> 
      floor_date(unit = "minute"),
    # time = lubridate::now(tzone = 'EST') |>
      # floor_date(unit = "minute") |>
      # with_tz('EST'),
      # format("%H:%M:%S"),
      # hms::new_hms(),
    timezone = "America/New_York",
    wait_time = tsa_time,  # Assume this is a list of wait times for each checkpoint
    wait_time_pre_check = NA
  ))
  
assign("ATL_data", ATL_data, envir = .GlobalEnv)  

dbAppendTable(con, name = "tsa_wait_times", value = ATL_data)

  print(glue("session has run successfully ", format(Sys.time(), "%a %b %d %X %Y")))
  rm(tsa_time)
  rm(url)
  rm(tsa_terminal)
  rm(tsa_terminal_checkpoint)
  rm(page)
  rm(session)
  rm(ATL_data)
}

# Loop Funtion For Test (SUCCESS) ----
# i <- 1
# while (i < 6) {
#  p1 <- Sys.time()
#  scrape_tsa_data()
#  theDelay <- 60-as.numeric(difftime(Sys.time(),p1,unit="secs"))
#  Sys.sleep(max(0, theDelay))

#  i <- i + 1
# }

# Disconnect DB ----

DBI::dbDisconnect(con, shutdown = TRUE)
rm(con)
