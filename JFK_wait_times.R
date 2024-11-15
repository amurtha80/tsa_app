# Script in Process

## TODO: Make function out of code so it can be called in an automated script on AWS
## TODO: Ensure that insert code works in DuckDB database data process
## TODO (LOW): Refactor text clenaup, and research more efficient tag scraping off of page
## TODO (LOW): Fix chrome driver issues

# Install Packages ----

# install.packages(c("rvest", "RSelenium", "netstat", "wdman", "tibble", "dplyr",
#                     "lubridate", "stringr", "tidyr"))

library(rvest)
library(RSelenium)
library(netstat)
library(wdman)
library(tibble)
library(dplyr)
library(lubridate)
library(stringr)
library(tidyr)


# setup
wdman::selenium()
selenium_object <- selenium(retcommand = T, check = F)
# binman::list_versions("chromedriver")

# firefox
remote_driver <- rsDriver(browser = "firefox",
                          chromever = NULL,
                          verbose = T,
                          port = free_port())

# Access Page
brow <- remote_driver[["client"]]
brow$open()
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
        timezone = "America/New_York") |>
  # Rename CheckPoint column
  rename(checkpoint = `Terminal...1`) |>
  # Remove unnecessary columns
  select(-(2:5)) |> 
  # Reorder remaining columns
  select(airport, checkpoint, datetime, date, time, timezone, wait_time,
         wait_time_pre_check)
  

# Assign to Global Environment
assign("JFK_data", JFK_data, envir = .GlobalEnv) 


# Insert observations into tsa_wait_times table
dbAppendTable(con, name = "tsa_wait_times", value = JFK_data)


# Cleanup to rerun
print(glue("session has run successfully ", format(Sys.time(), "%a %b %d %X %Y")))
rm(h)
rm(results)
rm(JFK_data)
rm(brow)
rm(selenium_object)


# Close the server
remote_driver$server$stop()
rm(remote_driver)

