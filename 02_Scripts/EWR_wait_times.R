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

# con <- dbConnect(duckdb::duckdb(), dbdir = "01_Data/tsa_app.duckdb", read_only = FALSE)


# Function to scrape and store TSA checkpoint wait times
scrape_tsa_data_ewr <- function() {
  
  print(glue("kickoff EWR scrape ", format(Sys.time(), "%a %b %d %X %Y")))
  
  # Define URL and initiate polite session
  url <- "https://www.newarkairport.com/"  # Update with the actual URL
  session <- polite::bow(url)
 
  
  # Access Page
  page <- read_html_live(url)
  
  # Scrape Page
  results <- page |> 
    html_elements('.av-responsive-table') |> 
    html_table(fill = TRUE) |> 
    dplyr::bind_rows() 
  
  # Transform Data
  EWR_data <- results |> 
    mutate(airport = 'EWR',
           # General Wait Time
           wait_time = results$`General Line` |> 
             str_remove_all(' ') |> 
             str_remove_all('\n') |> 
             str_remove_all('min') |>
             str_remove_all('GeneralLine')) |> 
    mutate(wait_time = case_when(wait_time == "NoWait" ~ "0", TRUE ~ wait_time) |>
             as.numeric()) |> 
    # TSA Pre check Wait Time
    mutate(wait_time_pre_check = results$`TSA Pre✓ Line` |> 
             str_remove_all(' ') |> 
             str_remove_all('\n') |> 
             str_remove_all('min') |> 
             str_remove_all('TSAPre✓Line')) |> 
    mutate(wait_time_pre_check = case_when(wait_time_pre_check == "NoWait" ~ "0",
                                           TRUE ~ wait_time_pre_check) |> 
             as.numeric()) |> 
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
  assign("EWR_data", EWR_data, envir = .GlobalEnv) 
  
  
  # Insert observations into tsa_wait_times table
  dbAppendTable(con_write, name = "tsa_wait_times", value = EWR_data)
  
  
  # Cleanup to rerun
  # print(glue("session has run successfully ", format(Sys.time(), "%a %b %d %X %Y")))
  print(glue("{nrow(EWR_data)} row(s) of data have been added to tsa_wait_times"))
  
  rm(results)
  rm(EWR_data, envir = .GlobalEnv)
  page$session$close()
  rm(page)
  rm(session)
  rm(url)
  
  # gc()
  
}


# scrape_tsa_data_ewr()

# Loop Funtion For Test ----

# i <- 1
#   
# for (i in 1:5) {
#   p1 <- lubridate::ceiling_date(Sys.time(), unit = "minute")
#   print(glue(i, "  ", format(Sys.time())))
#   scrape_tsa_data_ewr()
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
# rm(scrape_tsa_data_ewr)
