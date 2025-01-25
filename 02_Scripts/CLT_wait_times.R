# install.packages(c("DBI", "polite", "RSelenium", "netstat", "rvest", "tidyverse", "duckdb",
#  "lubridate", "magrittr", "glue", "here", "duckdb", "netstat"))

# suppressWarnings(library(rvest, verbose = F, warn.conflicts = F))
# suppressWarnings(library(httr, verbose = F, warn.conflicts = F))
# suppressWarnings(library(stringr, verbose = F, warn.conflicts = F))
# suppressWarnings(library(polite, verbose = F, warn.conflicts = F))
# suppressWarnings(library(RSelenium, verbose = F, warn.conflicts = F))
# suppressWarnings(library(jsonlite, verbose = F, warn.conflicts = F))
# suppressWarnings(library(tidyr, verbose = F, warn.conflicts = F))
# suppressWarnings(library(dplyr, verbose = F, warn.conflicts = F))
# suppressWarnings(library(glue, verbose = F, warn.conflicts = F))
# suppressWarnings(library(lubridate, verbose = F, warn.conflicts = F))
# suppressWarnings(library(DBI, verbose = F, warn.conflicts = F))
# suppressWarnings(library(duckdb, verbose = F, warn.conflicts = F))
# suppressWarnings(library(netstat, verbose = F, warn.conflicts = F))


# here::here()

# con_write <- dbConnect(duckdb::duckdb(), dbdir = "01_Data/tsa_app.duckdb", read_only = FALSE)

scrape_tsa_data_clt <- function() {

  print(glue("kickoff CLT scrape ", format(Sys.time(), "%a %b %d %X %Y")))

  # url <- "https://www.cltairport.com/airport-info/security/"  
  apiurl <- 'https://api.cltairport.mobi/checkpoint-queues/current' # Update with the actual URL
  UA <- "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 email me at james.a.murtha@gmail.com"

  # my_session <- session("https://www.cltairport.com/airport-info/security/")

  response <- GET(apiurl, user_agent(UA))

  response$status_code

  stuff <- fromJSON(apiurl)

  gates <- stuff$data$items$fullName |> 
    stringr::word(1, 2, sep = ' ')
  
  gatetype <- stuff$data$items$accessTypes |> 
    unlist(use.names = F)
  
  wait_time <- stuff$data$items$metrics$queueWaitTime$upperBoundSeconds / 60
  
  isClosed <- stuff$data$items$metrics$queueStatus$reportedClosed 
  
  mine <- tibble::tibble(
    airport = rep('CLT', 4),
    checkpoint = gates,
    Type = gatetype,
    wait_time = wait_time,
    wait_time_priority = rep(NA, 4),
    wait_time_pre_check = rep(0, 4),
    wait_time_clear = rep(NA, 4),
    Status = isClosed)
  
  # Create tibble for data insertion
  if(!exists("CLT_data", envir = .GlobalEnv)) {
    CLT_data <- tibble(airport = character(),
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
    CLT_data <- get("CLT_data", envir = .GlobalEnv)
  }
  
  CLT_data <- mine |> 
    mutate(datetime = lubridate::now(tzone = 'EST'),
           date = lubridate::today(tzone = 'EST'),
           time = Sys.time() |> 
             with_tz(tzone = "America/New_York") |> 
             floor_date(unit = "minute"),
           timezone = "America/New_York",
           wait_time_pre_check = case_when((Status == "TRUE" ~ NA),
                                           Type == "PreCheck" ~ wait_time,
                                           TRUE ~ NA),
           wait_time = case_when(Type == "General" ~ wait_time,
                                 (Status == "TRUE" ~ NA),
                                 TRUE ~ NA)
    ) |> 
    select(-Type, -Status) |> 
    group_by(airport, checkpoint, datetime, date, time, timezone) |>
    summarize(
      wait_time = if (all(is.na(wait_time))) NA_real_ else max(wait_time, na.rm = TRUE),
      wait_time_priority = if (all(is.na(wait_time_priority))) NA_real_ else max(wait_time_priority, na.rm = TRUE),
      wait_time_pre_check = if (all(is.na(wait_time_pre_check))) NA_real_ else max(wait_time_pre_check, na.rm = TRUE),
      wait_time_clear = if (all(is.na(wait_time_clear))) NA_real_ else max(wait_time_clear, na.rm = TRUE),
      .groups = "drop" # Ensure ungrouped result
      )


  assign("CLT_data", CLT_data, envir = .GlobalEnv)  
  
  dbAppendTable(con_write, name = "tsa_wait_times", value = CLT_data)
  
  # print(glue("session has run successfully ", format(Sys.time(), "%a %b %d %X %Y")))
  print(glue("{nrow(CLT_data)} row(s) of data have been added to tsa_wait_times"))
  

  # rm(url)
  rm(apiurl)
  rm(UA)
  rm(response)
  rm(gates)
  rm(gatetype)
  rm(wait_time)
  rm(isClosed)
  rm(stuff)
  rm(mine)
  rm(CLT_data, envir = .GlobalEnv)
  
}

  # scrape_tsa_data_clt()

# Test Loop ----
# i <- 1
# 
# for (i in 1:5) {
#   p1 <- lubridate::ceiling_date(Sys.time(), unit = "minute")
#   print(glue(i, "  ", format(Sys.time())))
#   scrape_tsa_data_clt()
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
# rm(scrape_tsa_data_clt)
