# Install Packages ----

# install.packages(c("rvest", "RSelenium", "netstat", "wdman", "tibble", "dplyr",
#                     "lubridate", "stringr", "tidyr", "duckdb", "here", "glue"))

library(rvest, verbose = F, warn.conflicts = F)
library(RSelenium, verbose = F, warn.conflicts = F)
library(netstat, verbose = F, warn.conflicts = F)
library(wdman, verbose = F, warn.conflicts = F)
library(tibble, verbose = F, warn.conflicts = F)
library(dplyr, verbose = F, warn.conflicts = F)
library(lubridate, verbose = F, warn.conflicts = F)
library(stringr, warn.conflicts = F)
library(tidyr, verbose = F, warn.conflicts = F)
library(duckdb, verbose = F, warn.conflicts = F)
library(here, verbose = F, warn.conflicts = F)
library(glue, verbose = F, warn.conflicts = F)


# setup
# wdman::selenium()
# seleniumCommand <- selenium(retcommand = T, check = F)
# seleniumCommand
# binman::list_versions("chromedriver")

# Database Connection ----

con <- dbConnect(duckdb::duckdb(), dbdir = "02_Data/tsa_app.duckdb", read_only = FALSE)

# Function to scrape and store TSA checkpoint wait times
scrape_tsa_data_lga <- function() {
  
  # firefox
  remote_driver <- rsDriver(browser = "firefox",
                            chromever = NULL,
                            verbose = F,
                            port = free_port(),
                            extraCapabilities = list("moz:firefoxOptions" = list(args = list('--headless'))))
  
  
  # Access Page
  brow <- remote_driver[["client"]]
  # brow$open()
  brow$navigate("https://www.laguardiaairport.com")
  
  
  # Scrape Page
  h <- brow$getPageSource()
  h <- read_html(h[[1]])
  results <- h |> 
    html_elements('.av-responsive-table') |> 
    html_table(fill = TRUE) |> 
    dplyr::bind_rows()
  
  # Tranform Data
  LGA_data <- results |> 
    mutate(airport = 'LGA',
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
           timezone = "America/New_York") |>
    # Rename CheckPoint column
    rename(checkpoint = `Terminal...1`) |>
    # Remove unnecessary columns
    select(-(2:5)) |> 
    # Reorder remaining columns
    select(airport, checkpoint, datetime, date, time, timezone, wait_time,
           wait_time_pre_check)
  
  
  # Assign to Global Environment
  assign("LGA_data", LGA_data, envir = .GlobalEnv) 
  
  
  # Insert observations into tsa_wait_times table
  dbAppendTable(con, name = "tsa_wait_times", value = LGA_data)
  
  
  # Cleanup to rerun
  print(glue("session has run successfully ", format(Sys.time(), "%a %b %d %X %Y")))
  rm(results)
  rm(LGA_data, envir = .GlobalEnv)
  rm(h)
  
  brow$close()
  rm(brow)
  
  remote_driver$server$stop()
  rm(remote_driver)
  gc()
  
}

# purrr::slowly(scrape_tsa_data, rate = rate_delay(pause = 60), quiet = FALSE)

i <- 1

for (i in 1:5) {
  p1 <- lubridate::ceiling_date(Sys.time(), unit = "minute")
    print(glue(i, "  ", format(Sys.time()))
    scrape_tsa_data_lga()
  theDelay <- as.numeric(difftime(p1,Sys.time(),unit="secs"))
  Sys.sleep(max(0, theDelay))
  
  i <- i + 1
}

# Disconnect DB, Cleanup Script ----
          
# Close the server
# rm(seleniumCommand)
# remote_driver$server$stop()
# rm(remote_driver)
DBI::dbDisconnect(con, shutdown = TRUE)
rm(i)
rm(p1)
rm(theDelay)
dbDisconnect(con)          
rm(con)
rm(scrape_tsa_data_lga)
