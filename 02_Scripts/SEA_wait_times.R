# install.packages(c("DBI", "httr2", "jsonlite", "tidyverse", "duckdb",
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

scrape_tsa_data_sea <- function() {

  print(glue("kickoff SEA scrape ", format(Sys.time(), "%a %b %d %X %Y")))

  # API endpoint ----
  api_url <- "https://www.portseattle.org/api/cwt/wait-times"

  # 1. Initialize the request
  req <- request(api_url)

  # 2. Build the exact browser mimic layer
  req <- req |>
    req_headers(
      `accept`           = "application/json, text/javascript, */*; q=0.01",
      `accept-language`  = "en-US,en;q=0.9",
      `referer`          = "https://portseattle.org",
      `user-agent`       = "Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Mobile Safari/537.36",
      `x-requested-with` = "XMLHttpRequest"
    )

  # 3. Perform the request safely
  response <- req_perform(req)

  # 4. Check results
  status <- resp_status(response)
  # print(paste("HTTP Status Code:", status))

  # Parse checkpoints ----

  parsed_data <- resp_body_json(response)

  # Checkpoints 1-6 -- no lane-type difference between General/PreCheck/CLEAR
  # (same underlying WaitTimeMinutes), so a lane only gets a value when its
  # Options entry says "Available". IsOpen/IsDataAvailable false -> NA for
  # every lane on that checkpoint (unavailable on the live page -> NA).
  mine <- purrr::map_dfr(parsed_data, function(cp) {
    is_valid <- isTRUE(cp$IsOpen) && isTRUE(cp$IsDataAvailable)
    wait <- if (is_valid) as.numeric(cp$WaitTimeMinutes) else NA_real_

    lane_available <- function(lane_name) {
      opt <- purrr::keep(cp$Options, ~ identical(.x$Name, lane_name))
      length(opt) == 1 && identical(opt[[1]]$Availability, "Available")
    }

    tibble::tibble(
      checkpoint = stringr::str_squish(as.character(cp$Name)),
      wait_time = if (lane_available("General")) wait else NA_real_,
      wait_time_pre_check = if (lane_available("Pre")) wait else NA_real_,
      wait_time_clear = if (lane_available("Clear")) wait else NA_real_
    )
  })

  # Create tibble for data insertion ----
  if (!exists("SEA_data", envir = .GlobalEnv)) {
    SEA_data <- tibble::tibble(airport = character(),
                               checkpoint = character(),
                               datetime = lubridate::ymd_hms(tz = 'America/Los_Angeles'),
                               date = lubridate::ymd(),
                               time = lubridate::POSIXct(tz = 'America/Los_Angeles'),
                               timezone = character(),
                               wait_time = numeric(),
                               wait_time_priority = numeric(),
                               wait_time_pre_check = numeric(),
                               wait_time_clear = numeric())
  } else {
    SEA_data <- get("SEA_data", envir = .GlobalEnv)
  }

  SEA_data <- mine |>
    dplyr::mutate(
      airport = "SEA",
      datetime = lubridate::now(tzone = 'America/Los_Angeles'),
      date = lubridate::today(tzone = 'America/Los_Angeles'),
      time = Sys.time() |>
        lubridate::with_tz(tzone = "America/Los_Angeles") |>
        lubridate::floor_date(unit = "minute"),
      timezone = "America/Los_Angeles",
      wait_time = round(wait_time),
      wait_time_priority = NA_real_,
      wait_time_pre_check = round(wait_time_pre_check),
      wait_time_clear = round(wait_time_clear)
    ) |>
    dplyr::select(airport, checkpoint, datetime, date, time, timezone,
                  wait_time, wait_time_priority, wait_time_pre_check, wait_time_clear) |>
    dplyr::rows_append(x = SEA_data, y = _)

  assign("SEA_data", SEA_data, envir = .GlobalEnv)

  # Write to database ----

  dbAppendTable(con_write, name = "tsa_wait_times", value = SEA_data)

  print(glue("{nrow(SEA_data)} appended to tsa_wait_times at ", format(Sys.time(), "%a %b %d %X %Y")))


  # Cleanup ----
  rm(api_url)
  rm(status)
  rm(req)
  rm(response)
  rm(parsed_data)
  rm(mine)
  rm(SEA_data, envir = .GlobalEnv)

}

# Testing ----

# scrape_tsa_data_sea()


# Test Loop ----
# i <- 1
#
# for (i in 1:5) {
#   p1 <- lubridate::ceiling_date(Sys.time(), unit = "minute")
#   print(glue(i, "  ", format(Sys.time())))
#   scrape_tsa_data_sea()
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
# rm(scrape_tsa_data_sea)
