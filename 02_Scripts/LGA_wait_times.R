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


####  --------------------------------------------------------------------- ####


# Function to scrape and store TSA checkpoint wait times
scrape_tsa_data_lga <- function() {
  
  print(glue("kickoff LGA scrape ", format(Sys.time(), "%a %b %d %X %Y")))
  
  # Define URL and initiate polite session
  url <- "https://www.laguardiaairport.com" # Update with the actual URL
  session <- session(url)
  Sys.sleep(2)
  options(chromote.headless = "new")
  
  
  
  
  # page <- read_html_live(url)
  page <- safe_read_html_live(url)
  Sys.sleep(0.3)
  
  # Read TSA Checkpoint Wait Time Data from Website Table
  results <- page |> 
    html_elements('.av-responsive-table') |> 
    html_table(fill = TRUE) |> 
    dplyr::bind_rows() |> 
    suppressMessages()
  
  
  # Tranform Data
  LGA_data <- results |> 
    mutate(airport = 'LGA',
           # General Wait Time
           wait_time = results$`General Line` |> 
             str_remove_all(' ') |> 
             str_remove_all('\n') |> 
             str_remove_all('min') |>
             str_remove_all('GeneralLine')) |> 
    mutate(wait_time = case_when(wait_time == "NoWait" ~ "0", 
                                 wait_time == "" ~ NA,
                                 TRUE ~ wait_time),
           wait_time = as.numeric(wait_time)) |> 
    suppressWarnings() |> 
    # TSA Pre check Wait Time
    mutate(wait_time_pre_check = results$`TSA Pre✓ Line` |> 
             str_remove_all(' ') |> 
             str_remove_all('\n') |> 
             str_remove_all('min') |> 
             str_remove_all('TSAPre✓Line')) |> 
    mutate(wait_time_pre_check = case_when(wait_time_pre_check == "NoWait" ~ "0",
                                           wait_time_pre_check == "" ~ NA,
                                           TRUE ~ wait_time_pre_check), 
           wait_time_pre_check = as.numeric(wait_time_pre_check)) |> 
    suppressWarnings() |> 
    # DateTime
    mutate(datetime = lubridate::now(tzone = 'EST'),
           # Date
           date = lubridate::today(),
           # Time Rounded to Minute
           time = Sys.time() |> 
             with_tz(tzone = "America/New_York") |> 
             floor_date(unit = "minute"),
           timezone = "America/New_York",
           wait_time_priority = NA,
           wait_time_clear = NA) |>
    # Rename CheckPoint column
    rename(checkpoint = `Terminal...1`) |>
    # Remove unnecessary columns
    select(-(2:5)) |> 
    # Reorder remaining columns
    select(airport, checkpoint, datetime, date, time, timezone, wait_time,
           wait_time_priority, wait_time_pre_check, wait_time_clear)
  
  
  # Assign to Global Environment
  assign("LGA_data", LGA_data, envir = .GlobalEnv) 
  
  
  # Insert observations into tsa_wait_times table
  dbAppendTable(con_write, name = "tsa_wait_times", value = LGA_data)
  
  # Cleanup to rerun
  # print(glue("session has run successfully ", format(Sys.time(), "%a %b %d %X %Y")))
  print(glue("{nrow(LGA_data)} row(s) appended to tsa_wait_times at ", format(Sys.time(), "%a %b %d %X %Y")))
  
  
  rm(results)
  page$session$close()
  rm(page)
  rm(session)
  rm(url)
  rm(LGA_data, envir = .GlobalEnv)
  rm(safe_read_html_live)
  # gc()
  
}


# Test Run one time
# scrape_tsa_data_lga()


# Test Run in loop
# i <- 1
# 
# for (i in 1:5) {
#   p1 <- lubridate::ceiling_date(Sys.time(), unit = "minute")
#     print(glue(i, "  ", format(Sys.time())))
#     scrape_tsa_data_lga()
#   theDelay <- as.numeric(difftime(p1,Sys.time(),unit="secs"))
#   Sys.sleep(max(0, theDelay))
#   
#   i <- i + 1
# }

# Close the server
# rm(i)
# rm(p1)
# rm(theDelay)
# dbDisconnect(con_write)
# rm(con_write)
# rm(scrape_tsa_data_lga)