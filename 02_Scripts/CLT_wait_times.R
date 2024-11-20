# install.packages(c("DBI", "polite", "RSelenium", "netstat", "rvest", "tidyverse", "duckdb", 
#  "lubridate", "magrittr", glue", "here"))

library(polite, verbose = FALSE, warn.conflicts = FALSE)
library(rvest, verbose = FALSE, warn.conflicts = FALSE)
library(RSelenium, verbose = FALSE, warn.conflicts = FALSE)
library(netstat, verbose = FALSE, warn.conflicts = FALSE)
library(duckdb, verbose = FALSE, warn.conflicts = FALSE)
library(glue, verbose = FALSE, warn.conflicts = FALSE)
library(DBI, verbose = FALSE, warn.conflicts = FALSE)
library(tidyverse, verbose = FALSE, warn.conflicts = FALSE)
library(here, verbose = FALSE, warn.conflicts = FALSE)

here::here()


# Database Connection ----

con <- dbConnect(duckdb::duckdb(), dbdir = "02_Data/tsa_app.duckdb", read_only = FALSE)


# Script Function ----


scrape_tsa_data_clt <- function() {
  # Define URL and initiate polite session
  url <- "https://www.cltairport.com/airport-info/security/"  # Update with the actual URL

  
  # firefox
  remote_driver <- rsDriver(browser = "firefox",
                            chromever = NULL,
                            verbose = F,
                            port = free_port(),
                            extraCapabilities = list("moz:firefoxOptions" = list(args = list('--headless'))))
  
  
  # Access Page
  brow <- remote_driver[["client"]]
  # brow$open()
  brow$navigate(url)
  
  
  # Scrape Page
  h <- brow$getPageSource()
  h <- read_html(h[[1]])
  
  
  gates <- h |> 
    html_elements("h2") |> 
    html_text2() |>
    magrittr::extract(c(2:3,5:6))
  
  
  availability <- h |> 
    html_elements('div.css-gtvyll.ehd75gq0 p') |> 
    html_text2()
  
  
  wait_time <- ifelse(availability == "Now Closed", "Closed", 
    h |> 
      html_elements('h3') |> 
      html_text2() |> 
      str_sub(-2)) |> 
    magrittr::extract(c(1:2)) |> 
    as.numeric() |> 
    suppressWarnings()
  
  wait_time_pre_check <- ifelse(availability == "Now Closed", "Closed",
    h |> 
      html_elements('h3') |> 
      html_text2() |> 
      str_sub(-2)) |>
    magrittr::extract(c(3:4)) |>
    gsub(pattern = 'Closed', replacement = 'NA') |> 
    as.numeric() |> 
    suppressWarnings()
  
  # Fill in blanks for transformation to tibble
  wait_time <- c(wait_time, NA, NA)
  wait_time_pre_check <- c(NA, NA, wait_time_pre_check)
  
  
  # Check to make Sure that TSA CheckPoint and Time have the same length
  if(length(wait_time) != length(gates)){
    stop("The length of wait_time and gates do not match.")
  }
  if(length(wait_time_pre_check) != length(gates)){
    stop("The length of wait_time_pre_check and gates to not match.")
  }
  
  
  # Create tibble for data insertion
  if(!exists("CLT_data", envir = .GlobalEnv)) {
    CLT_data <- tibble(airport = character(),
                       checkpoint = character(),
                       datetime = lubridate::ymd_hms(tz = 'EST'),
                       date = lubridate::ymd(),
                       time = lubridate::POSIXct(tz = 'EST'),
                       timezone = character(),
                       wait_time = numeric(),
                       wait_time_pre_check = numeric())
  } else {
    CLT_data <- get("CLT_data", envir = .GlobalEnv)
  }
  
  
  # Insert data into tibble
  # Prepare data with airport code, date, time, timezone, and wait times
  CLT_data <- rows_append(CLT_data, tibble(
    airport = "CLT",
    checkpoint = gates,
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
    wait_time = wait_time,  # Assume this is a list of wait times for each checkpoint
    wait_time_pre_check = wait_time_pre_check
  ))
  
  
  assign("CLT_data", CLT_data, envir = .GlobalEnv)  
  
  dbAppendTable(con, name = "tsa_wait_times", value = CLT_data)
  
  print(glue("session has run successfully ", format(Sys.time(), "%a %b %d %X %Y")))
  rm(wait_time_pre_check)
  rm(url)
  rm(h)
  rm(gates)
  rm(availability)
  rm(wait_time)
  rm(CLT_data, envir = .GlobalEnv)
  
  brow$close()
  rm(brow)
  
  remote_driver$server$stop()
  rm(remote_driver)
  gc() 
  
}


# Test Loop ----
i <- 1

for (i in 1:5) {
  p1 <- lubridate::ceiling_date(Sys.time(), unit = "minute")
  print(glue(i, "  ", format(Sys.time())))
  scrape_tsa_data_clt()
  theDelay <- as.numeric(difftime(p1,Sys.time(),unit="secs"))
  Sys.sleep(max(0, theDelay))
  
  i <- i + 1
}


# Cleanup ----
rm(i)
rm(p1)
rm(theDelay)
dbDisconnect(con)
rm(con)
rm(scrape_tsa_data_clt)
