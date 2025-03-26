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

scrape_tsa_data_jfk <- function() {
  
  print(glue("kickoff JFK scrape ", format(Sys.time(), "%a %b %d %X %Y")))
  
  url <- "https://www.jfkairport.com"
  
  session <- session(url)
  Sys.sleep(2)
  options(chromote.headless = "new")

  page <- read_html_live(url)
  Sys.sleep(0.3)
  
  results <- page |> 
    html_elements('.av-responsive-table') |> 
    html_table(fill = TRUE) |> 
    dplyr::bind_rows() |> 
    suppressMessages()
  
  
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
  dbAppendTable(con_write, name = "tsa_wait_times", value = JFK_data)
  
  
  # Cleanup to rerun
  # print(glue("session has run successfully ", format(Sys.time(), "%a %b %d %X %Y")))
  print(glue("{nrow(JFK_data)} row(s) appended to tsa_wait_times at ", format(Sys.time(), "%a %b %d %X %Y")))
  
 
  # rm(checkpoints)
  # rm(notes)
  # rm(data)
  
  rm(results)
  page$session$close()
  rm(page)
  rm(session)
  rm(url)
  rm(JFK_data, envir = .GlobalEnv)
  # gc()
  
}

# Test Run one time
# scrape_tsa_data_jfk()


# Test Run in loop
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
# rm(i)
# rm(p1)
# rm(theDelay)
# dbDisconnect(con_write)
# rm(con_write)
# rm(scrape_tsa_data_jfk)
