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
  Sys.sleep(1.5)
  options(chromote.headless = "new")
  
  # Initialize a new Chrome session with the latest stable version of Chrome 
  # and specify the binary for chrome-headless-shell
  chromote::local_chrome_version(version = "latest-stable", binary = "chrome-headless-shell")
  
  page <- safe_read_html_live(url)
  Sys.sleep(1.5)

####  --------------------------------------------------------------------- ####
  
  results <- page |> 
    html_elements('table') |>
    # html_elements('.chakra-table__body.css-0') |>
    # html_elements('.av-responsive-table') |> 
    html_table(fill = TRUE) |> 
    dplyr::bind_rows() |> 
    head(-1) |> 
    suppressMessages()
  
  
  # Transform Data ----
  JFK_data <- results |>
    mutate(
      airport = 'JFK',
      # General wait time — "No Wait" → 0, numeric string → value, else NA
      wait_time = case_when(
        str_trim(results$`General`) == "No Wait" ~ 0,
        !is.na(readr::parse_number(results$`General`, na = c("-", ""))) ~
          readr::parse_number(results$`General`, na = c("-", "")),
        TRUE ~ NA_real_
      ),
      # TSA PreCheck wait time — same logic
      wait_time_pre_check = case_when(
        str_trim(results[["TSA Pre\u2713"]]) == "No Wait" ~ 0,
        !is.na(readr::parse_number(results[["TSA Pre\u2713"]], na = c("-", ""))) ~
          readr::parse_number(results[["TSA Pre\u2713"]], na = c("-", "")),
        TRUE ~ NA_real_
      ),
      datetime           = lubridate::now(tzone = 'EST'),
      date               = lubridate::today(),
      time               = Sys.time() |>
        with_tz(tzone = "America/New_York") |>
        floor_date(unit = "minute"),
      timezone           = "America/New_York",
      wait_time_priority = NA_real_,
      wait_time_clear    = NA_real_
    ) |>
    rename(checkpoint = Terminal) |>
    select(airport, checkpoint, datetime, date, time, timezone,
           wait_time, wait_time_priority, wait_time_pre_check, wait_time_clear)
  
  
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
  rm(JFK_data, envir = .GlobalEnv)
  
  # page$session$close() - Quit using April 2026, only closes tab not entire session
  # page$parent$close()
  
  tryCatch({
    page$session$close()
    page$session$parent$close(wait = 2)
    if (chromote::has_default_chromote_object()) {
      chromote::set_default_chromote_object(NULL)
    }
  }, error = function(e) {
    message(Sys.time(), " | JFK teardown warning (non-fatal): ", e$message)
  }, finally = {
    rm(page)
    rm(session)
    rm(url)
  })

  # gc()
  
}

####  --------------------------------------------------------------------- ####

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
