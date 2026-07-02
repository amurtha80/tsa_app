# install.packages(c("DBI", "httr", "jsonlite", "tidyverse", "duckdb",
#  "lubridate", "glue", "here"))

# library(httr2, verbose = FALSE, warn.conflicts = FALSE)
# library(jsonlite, verbose = FALSE, warn.conflicts = FALSE)
# library(duckdb, verbose = FALSE, warn.conflicts = FALSE)
# library(lubridate, verbose = FALSE, warn.conflicts = FALSE)
# library(glue, verbose = FALSE, warn.conflicts = FALSE)
# library(DBI, verbose = FALSE, warn.conflicts = FALSE)
# library(tidyverse, verbose = FALSE, warn.conflicts = FALSE)
# library(here, verbose = FALSE, warn.conflicts = FALSE)

# here::here()

# Database Connection ----

# con_write <- dbConnect(duckdb::duckdb(), dbdir = "01_Data/tsa_app.duckdb", read_only = FALSE)


# Script Function ----

# Function to scrape and store TSA checkpoint wait times
scrape_tsa_data_clt <- function() {
  
  print(glue("kickoff CLT scrape ", format(Sys.time(), "%a %b %d %X %Y")))
  
  # API endpoint ----
  api_url <- "https://api.cltairport.mobi/wait-times/checkpoint/CLT"
  
  # 1. Initialize the request
  req <- request(api_url)
  
  # 2. Build the exact browser mimic layer
  req <- req %>% 
    req_headers(
      `accept` = "application/json, text/plain, */*",
      `accept-language` = "en-US,en;q=0.9",
      `api-key` = "5ccb418715f9428ca6cb4df1635d4815",
      `api-version` = "130",
      `origin` = "https://cltairport.com",
      `referer` = "https://cltairport.com/",
      `user-agent` = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36"
    ) %>%
    # Force HTTP/2 protocol to match Chrome's network profile
    req_options(http_version = 2)
  
  # 3. Perform the request safely
  response <- req_perform(req)
  
  # 4. Check results
  status <- resp_status(response)
  print(paste("HTTP Status Code:", status))
  
  # Parse checkpoints ----
  
  raw_content <- resp_body_string(response)
  parsed_data <- jsonlite::fromJSON(raw_content, flatten = TRUE)
  parsed_data <- parsed_data$data$wait_times
  # print(parsed_data)
  
  # Drop dead/orphaned rows (legacy lane records CLT never purged) ----
  live_data <- parsed_data |>
    dplyr::filter(isDisplayable == TRUE)
  
  # Collapse general + preCheck rows into one row per checkpoint ----
  mine <- live_data |>
    dplyr::mutate(
      lane_type = dplyr::case_when(
        attributes.preCheck == TRUE ~ "wait_time_pre_check",
        attributes.general  == TRUE ~ "wait_time",
        TRUE ~ NA_character_
      ),
      wait_minutes = dplyr::if_else(isOpen == TRUE, waitSeconds / 60, NA_real_)
    ) |>
    dplyr::select(checkpoint = name, lane_type, wait_minutes)
  
  # Guard: a live, displayable row with no recognized lane type means CLT
  # added a new attribute flag (or changed the schema) — stop and surface it
  # rather than let pivot_wider silently create an NA column.
  if (anyNA(mine$lane_type)) {
    bad_rows <- mine |> dplyr::filter(is.na(lane_type))
    stop(glue("CLT scrape: {nrow(bad_rows)} displayable row(s) have no recognized ",
              "lane_type (neither preCheck nor general set). Checkpoint(s): ",
              "{paste(unique(bad_rows$checkpoint), collapse = ', ')}. ",
              "CLT API schema may have changed — investigate before re-running."))
  }
  
  mine <- mine |>
    tidyr::pivot_wider(names_from = lane_type, values_from = wait_minutes)
  
  # Create tibble for data insertion ----
  if (!exists("CLT_data", envir = .GlobalEnv)) {
    CLT_data <- tibble::tibble(airport = character(),
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
    dplyr::mutate(
      airport = "CLT",
      datetime = lubridate::now(tzone = 'EST'),
      date = lubridate::today(tzone = 'EST'),
      time = Sys.time() |>
        lubridate::with_tz(tzone = "America/New_York") |>
        lubridate::floor_date(unit = "minute"),
      timezone = "America/New_York",
      wait_time = round(wait_time),
      wait_time_priority = NA_real_,
      wait_time_pre_check = round(wait_time_pre_check),
      wait_time_clear = NA_real_
    ) |>
    dplyr::select(airport, checkpoint, datetime, date, time, timezone,
                  wait_time, wait_time_priority, wait_time_pre_check, wait_time_clear) |>
    dplyr::rows_append(x = CLT_data, y = _)
  
  assign("CLT_data", CLT_data, envir = .GlobalEnv)
  
  # Write to database ----
  
  dbAppendTable(con_write, name = "tsa_wait_times", value = CLT_data)
  
  print(glue("{nrow(CLT_data)} appended to tsa_wait_times at ", format(Sys.time(), "%a %b %d %X %Y")))
  
  
  # Cleanup ----
  rm(api_url)
  rm(raw_content)
  rm(status)
  rm(req)
  rm(response)
  rm(parsed_data)
  rm(live_data)
  rm(mine)
  rm(CLT_data, envir = .GlobalEnv)
  
# gc()
  
}

# Testing ----

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
# dbDisconnect(con_write)
# rm(con_write)
# rm(scrape_tsa_data_clt)
  