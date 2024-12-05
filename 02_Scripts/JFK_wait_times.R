# Install Packages ----

# install.packages(c("rvest", "RSelenium", "netstat", "wdman", "tidyverse", "duckdb",
#                     "glue", "here", "polite"))

# library(rvest)
# library(RSelenium)
# library(netstat)
# library(wdman)
# library(duckdb)
# library(tidyverse)
# library(glue)
# library(here)

# here::here()

# Database Connection ----

# con <- dbConnect(duckdb::duckdb(), dbdir = "01_Data/tsa_app.duckdb", read_only = FALSE)

# Function to scrape and store TSA checkpoint wait times
scrape_tsa_data_jfk <- function() {
  
  print(glue("kickoff JFK scrape ", format(Sys.time(), "%a %b %d %X %Y")))
  
  # firefox
  remote_driver <- rsDriver(browser = "firefox",
                            chromever = NULL,
                            verbose = F,
                            port = free_port(),
                            extraCapabilities = list("moz:firefoxOptions" = list(args = list('--headless'))))
  
  
  # Access Page
  brow <- remote_driver[["client"]]
  # brow$open()
  brow$navigate("https://www.jfkairport.com")
  
  
  # Scrape Page
  h <- brow$getPageSource()
  h <- read_html(h[[1]])
  results <- h |> 
    html_elements('.av-responsive-table') |> 
    html_table(fill = TRUE) |> 
    dplyr::bind_rows()
  
  # Tranform Data
  JFK_data <- results |> 
    mutate(airport = 'JFK',
           # General Wait Time
           wait_time = results$`General Line` |> 
             str_remove_all("                                ") |> 
             str_remove("                             ") |> 
             str_remove_all('\n') |> str_sub(13) |> 
             str_remove("min") |> 
             as.numeric() |> 
             suppressWarnings(),
           # TSA Pre check Wait Time
           wait_time_pre_check = results$`TSA Pre✓ Line` |> 
             str_remove_all("          ") |> 
             str_remove("         ") |> 
             str_remove_all("  ") |> 
             str_remove_all('\n') |> 
             str_sub(14) |> 
             str_remove('min') |> 
             as.numeric() |> 
             suppressWarnings(),
           # DateTime
           datetime = lubridate::now(tzone = 'EST'),
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
  assign("JFK_data", JFK_data, envir = .GlobalEnv) 
  
  
  # Insert observations into tsa_wait_times table
  dbAppendTable(con, name = "tsa_wait_times", value = JFK_data)
  
  
  # Cleanup to rerun
  # print(glue("session has run successfully ", format(Sys.time(), "%a %b %d %X %Y")))
  print(glue("{nrow(JFK_data)} row(s) of data have been added to tsa_wait_times"))
  
  
  rm(results)
  rm(JFK_data, envir = .GlobalEnv)
  rm(h)
  
  brow$close()
  rm(brow)
  
  remote_driver$server$stop()
  rm(remote_driver)
  # gc()
}


# i <- 1
# 
# for (i in 1:5) {
#   p1 <- lubridate::ceiling_date(Sys.time(), unit = "minute")
#     print(glue(i, "  ", format(Sys.time())))
#     scrape_tsa_data_jfk()
#   theDelay <- as.numeric(difftime(p1,Sys.time(),unit="secs"))
#   Sys.sleep(max(0, theDelay))
#   
#   i <- i + 1
# }

# Close the server
# rm(seleniumCommand)
# rm(i)
# rm(p1)
# rm(theDelay)
# dbDisconnect(con)
# rm(con)
# rm(scrape_tsa_data_jfk)
