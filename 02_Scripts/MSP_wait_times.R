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


# Function to scrape and store TSA checkpoint wait times
scrape_tsa_data_msp <- function() {
  
  print(glue("kickoff MSP scrape ", format(Sys.time(), "%a %b %d %X %Y")))
  
  
  # Define URL and initiate polite session
  url <- "https://www.mspairport.com/airport/security-screening/security-wait-times"  # Update with the actual URL
  session <- polite::bow(url)
  
  
  # Scrape and parse data
  # page <- polite::scrape(session)
  page <- read_html(url)

  
  checkpoints <- page |> 
    rvest::html_elements("div.security-wait-time__checkpoint-name") |> 
    rvest::html_text() |> 
    stringr::str_trim()

  
  chkpnt_type <- page |> 
    rvest::html_elements("div.security-wait-time__message") |> 
    rvest::html_text() |> 
    stringr::str_trim()

  
  wait_time <- page |> 
    rvest::html_elements("div.security-wait-time__time") |> 
    rvest::html_text() |> 
    stringr::str_extract(pattern = "(\\d)+") |> 
    as.numeric()


  mine <- tibble::tibble(
    checkpoints = checkpoints,
    chkpnt_type = chkpnt_type,
    wait_time = wait_time
  )


  # Check to make Sure that TSA CheckPoint and Time have the same length
  if((length(checkpoints) != length(wait_time)) | (length(checkpoints) != length(chkpnt_type))){
    stop("The length of tsa_time and tsa_terminal_checkpoint do not match.")
  }


if(!exists("MSP_data", envir = .GlobalEnv)) {
  MSP_data <- tibble(airport = character(),
                     checkpoint = character(),
                     datetime = lubridate::ymd_hms(tz = 'America/Chicago'),
                     date = lubridate::ymd(),
                     time = lubridate::POSIXct(tz = 'America/Chicago'),
                     timezone = character(),
                     wait_time = numeric(),
                     wait_time_priority = numeric(),
                     wait_time_pre_check = numeric(),
                     wait_time_clear = numeric())
} else {
  MSP_data <- get("MSP_data", envir = .GlobalEnv)
}


  # Prepare data with airport code, date, time, timezone, and wait times
  MSP_data <- rows_append(MSP_data, tibble(
    airport = "MSP",
    checkpoint = mine$checkpoints,
    datetime = lubridate::now(tzone = 'America/Chicago'),
    date = lubridate::today(),
    time = Sys.time() |> 
      with_tz(tzone = "America/Chicago") |> 
      floor_date(unit = "minute"),
    timezone = "America/Chicago",
    wait_time = case_when(mine$chkpnt_type == "all passengers" ~ mine$wait_time,
                          TRUE ~ NA_integer_),  # Assume this is a list of wait times for each checkpoint
    wait_time_priority = NA,
    wait_time_pre_check = case_when(mine$chkpnt_type == "PreCheck OPEN Only" ~ mine$wait_time,
                                    (mine$checkpoints == "T2 Checkpoint 1" & mine$chkpnt_type == "all passengers") ~ NA_integer_,
                                     mine$chkpnt_type == "all passengers" ~ mine$wait_time,
                                    TRUE ~ NA_integer_),
    wait_time_clear = NA
    )
  )


  assign("MSP_data", MSP_data, envir = .GlobalEnv)  
  

  dbAppendTable(con_write, name = "tsa_wait_times", value = MSP_data)
  

  # print(glue("session has run successfully ", format(Sys.time(), "%a %b %d %X %Y")))
  print(glue("{nrow(MSP_data)} row(s) of data have been added to tsa_wait_times"))
  rm(url)
  rm(checkpoints)
  rm(chkpnt_type)
  rm(wait_time)
  rm(mine)
  rm(page)
  rm(session)
  rm(MSP_data, envir = .GlobalEnv)

  
}


# Loop Funtion For Test ----

# i <- 1
#   
# for (i in 1:5) {
#   p1 <- lubridate::ceiling_date(Sys.time(), unit = "minute")
#   print(glue(i, "  ", format(Sys.time())))
#   scrape_tsa_data_msp()
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
# rm(scrape_tsa_data_msp)