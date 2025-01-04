# install.packages(c("DBI", "polite", "rvest", "RSelenium",  "tidyverse", 
# "duckdb", "glue", "here"))

# library(DBI, verbose = FALSE, warn.conflicts = FALSE)
# library(polite, verbose = FALSE, warn.conflicts = FALSE)
# library(rvest, verbose = FALSE, warn.conflicts = FALSE)
# library(RSelenium, verbose = FALSE, warn.conflicts = FALSE)
# library(duckdb, verbose = FALSE, warn.conflicts = FALSE)
# library(glue, verbose = FALSE, warn.conflicts = FALSE)
# library(tidyverse, verbose = FALSE, warn.conflicts = FALSE)
# library(here, verbose = FALSE, warn.conflicts = FALSE)

# here::here()

# Database Connection ----

# con <- dbConnect(duckdb::duckdb(), dbdir = "01_Data/tsa_app.duckdb", read_only = FALSE)


# Function to scrape and store TSA checkpoint wait times
scrape_tsa_data_den <- function() {
  
  print(glue("kickoff DEN scrape ", format(Sys.time(), "%a %b %d %X %Y")))
  
  # Define URL and initiate polite session
  url <- "https://www.flydenver.com/security/"  # Update with the actual URL

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
    html_elements('.name') |> 
    html_text2() |> 
    magrittr::extract(c(1,3,5)) 

  
  # chkpnt_type <- h |> 
  #   html_elements('.wait-type') |>
  #   html_text2() |> 
  #   {\(.) case_when(. == "Minimal Screening Lanes Available" ~ "Standard", TRUE ~ .)}()
  
  
  wait_time <- h |> 
    html_elements('.wait-num') |> 
    html_text2() |> 
    gsub(pattern = ' ', replacement = 'NA') |> 
    as.numeric() |> 
    suppressWarnings() |> 
    magrittr::extract(c(1,2,4))
  
  
  wait_time_pre_check <- h |> 
    html_elements('.wait-num') |> 
    html_text2() |> 
    gsub(pattern = ' ', replacement = 'NA') |> 
    as.numeric() |> 
    suppressWarnings() |> 
    magrittr::extract(c(3,5)) |> 
    {\(.) append(NA, .)}()
  
  
  # Check to make Sure that TSA CheckPoint and Time have the same length
  if(length(wait_time) != length(gates)){
    stop("The length of tsa_time and tsa_terminal_checkpoint do not match.")
  }  
  if(length(wait_time_pre_check) != length(gates)){
    stop("The length of tsa_time_pre_check and gates do not match.")
  }
  
  # Create tibble for data insertion
  if(!exists("DEN_data", envir = .GlobalEnv)) {
    DEN_data <- tibble(airport = character(),
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
    DEN_data <- get("DEN_data", envir = .GlobalEnv)
  }
  
  
  # Insert data into tibble
  # Prepare data with airport code, date, time, timezone, and wait times
  DEN_data <- rows_append(DEN_data, tibble(
    airport = "DEN",
    checkpoint = gates,
    datetime = lubridate::now(tzone = 'MST'),
    date = lubridate::today(),
    time = Sys.time() |> 
      with_tz(tzone = "America/Denver") |> 
      floor_date(unit = "minute"),
    # time = lubridate::now(tzone = 'EST') |>
    # floor_date(unit = "minute") |>
    # with_tz('EST'),
    # format("%H:%M:%S"),
    # hms::new_hms(),
    timezone = "America/Denver",
    wait_time = wait_time,  # Assume this is a list of wait times for each checkpoint
    wait_time_priority = NA,
    wait_time_pre_check = wait_time_pre_check,
    wait_time_clear = NA
  ))
  
  assign("DEN_data", DEN_data, envir = .GlobalEnv)  
  
  dbAppendTable(con_write, name = "tsa_wait_times", value = DEN_data)
  
  # print(glue("session has run successfully ", format(Sys.time(), "%a %b %d %X %Y")))
  print(glue("{nrow(DEN_data)} row(s) of data have been added to tsa_wait_times"))
  
  
  rm(gates)
  rm(wait_time)
  rm(wait_time_pre_check)
  rm(url)
  rm(h)
  rm(DEN_data, envir = .GlobalEnv)
  
  brow$close()
  rm(brow)
  
  remote_driver$server$stop()
  rm(remote_driver)
  # gc()
}


# Test Loop ----
# i <- 1
# 
# for (i in 1:5) {
#   p1 <- lubridate::ceiling_date(Sys.time(), unit = "minute")
#   print(glue(i, "  ", format(Sys.time())))
#   scrape_tsa_data_den()
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
# rm(scrape_tsa_data_den)


## TODO ----
## Research error when killing Chrome processes in Windows Task Manager

# kickoff DEN scrape Fri Dec 06 4:30:11 PM 2024
# [2024-12-06 16:30:45] [error] handle_read_frame error: asio.system:10054 (An existing connection was forcibly closed by the remote host.)
# 3 row(s) of data have been added to tsa_wait_times
# kickoff EWR scrape Fri Dec 06 4:30:47 PM 2024