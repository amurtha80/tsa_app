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
  
  # Scrape and parse data
  # page <- polite::scrape(session)
  page <- read_html_live(url)
  
  
  times <- page |> 
    rvest::html_elements(".resp-table-row") |> 
    rvest::html_text2() |> 
    str_remove_all(pattern = "Directions") |> 
    str_split("\n") |> 
    stringi::stri_list2matrix(byrow = T)
  
  
  # Create column names for tibble
  colnames(times) <-  c("Checkpoint", "General", "TSA_Pre", "Blank")
  
  
  # Create wait times tibble from scraped data
  wait_times <- as_tibble(times) |> 
    magrittr::extract(1:3) |> 
    mutate(General = case_when(General == "" ~ "NA",
                               (stringr::str_sub(General, 1, 1) == "<" ~ word(General, 2, 2)),
                               TRUE ~ word(General, 2, 2, sep = '-') |> word(1, 1)) |> 
             as.numeric() |> 
             suppressWarnings(),
           TSA_Pre = case_when(TSA_Pre == "" ~ "NA",
                               (stringr::str_sub(TSA_Pre, 1, 1) == "<" ~ word(TSA_Pre, 2, 2)),
                               TRUE~ word(TSA_Pre, 2, 2, sep = '-') |> word(1, 1)) |> 
             as.numeric() |> 
             suppressWarnings()
    )
  
  
  # Create tibble for data insertion
  if(!exists("DCA_data", envir = .GlobalEnv)) {
    DCA_data <- tibble(airport = character(),
                       checkpoint = character(),
                       datetime = lubridate::ymd_hms(tz = 'EST'),
                       date = lubridate::ymd(),
                       time = lubridate::POSIXct(tz = 'EST'),
                       timezone = character(),
                       wait_time = numeric(),
                       wait_time_priority = numeric(),
                       wait_time_pre_check = numeric(),
                       wait_time_clear = numeric()
    )
  } else {
    DCA_data <- get("DCA_data", envir = .GlobalEnv)
  }
  
  
  # Insert data into tibble
  # Prepare data with airport code, date, time, timezone, and wait times
  DCA_data <- rows_append(DCA_data, tibble(
    airport = "DCA",
    checkpoint = wait_times$Checkpoint,
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
    wait_time = wait_times$General,  # Assume this is a list of wait times for each checkpoint
    wait_time_priority = NA,
    wait_time_pre_check = wait_times$TSA_Pre,
    wait_time_clear = NA
  ))
  
  
  assign("DCA_data", DCA_data, envir = .GlobalEnv)  
  
  dbAppendTable(con_write, name = "tsa_wait_times", value = DCA_data)
  
  # print(glue("session has run successfully ", format(Sys.time(), "%a %b %d %X %Y")))
  print(glue("{nrow(DCA_data)} appended to tsa_wait_times at ", format(Sys.time(), "%a %b %d %X %Y")))
  
  
  # rm(gates)
  rm(times)
  rm(wait_times)
  rm(DCA_data, envir = .GlobalEnv)
  
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
#   
#   print(glue(i, "  ", format(Sys.time())))
#   
#   scrape_tsa_data_dca()
#   
#   theDelay <- as.numeric(difftime(p1,Sys.time(),unit="secs"))
#   
#   i <- i + 1
#   
#   if(i == 6) {
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