# install.packages(c("DBI", "httr2", "tidyverse", "duckdb",
#  "lubridate", "glue", "here"))

# library(httr2, verbose = FALSE, warn.conflicts = FALSE)
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

scrape_tsa_data_dtw <- function() {

  print(glue("kickoff DTW scrape ", format(Sys.time(), "%a %b %d %X %Y")))

  # API endpoint ----
  api_url <- "https://proxy.metroairport.com/SkyFiiTSAProxy.ashx"

  req <- request(api_url) |>
    req_headers(
      `accept`          = "application/json, text/plain, */*",
      `accept-language` = "en-US,en;q=0.9",
      `origin`          = "https://metroairport.com",
      `referer`         = "https://metroairport.com/",
      `user-agent`      = "Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Mobile Safari/537.36"
    )

  response <- req_perform(req)
  status <- resp_status(response)

  # Parse checkpoints ----

  parsed_data <- resp_body_json(response)

  # metroairport.com's SkyFii proxy exposes one wait-time reading per
  # terminal/checkpoint (Evans, McNamara), with no live open/closed flag and
  # no separate PreCheck figure anywhere in the payload. Per user decision
  # (2026-07-22), mirror the single reading into wait_time_pre_check as a
  # conservative estimate -- same "duplicate the only number that exists"
  # convention SLC uses for its airport-wide reading. wait_time_clear stays
  # NA (no CLEAR signal at DTW).
  data_tbl <- purrr::map_dfr(parsed_data, function(cp) {
    tibble::tibble(
      checkpoint = cp$Name,
      wait_time = as.numeric(cp$WaitTime)
    )
  })

  # Create tibble for data insertion ----
  if (!exists("DTW_data", envir = .GlobalEnv)) {
    DTW_data <- tibble::tibble(airport = character(),
                                checkpoint = character(),
                                datetime = lubridate::ymd_hms(tz = 'America/Detroit'),
                                date = lubridate::ymd(),
                                time = lubridate::POSIXct(tz = 'America/Detroit'),
                                timezone = character(),
                                wait_time = numeric(),
                                wait_time_priority = numeric(),
                                wait_time_pre_check = numeric(),
                                wait_time_clear = numeric())
  } else {
    DTW_data <- get("DTW_data", envir = .GlobalEnv)
  }

  DTW_data <- dplyr::rows_append(DTW_data, tibble::tibble(
    airport = "DTW",
    checkpoint = data_tbl$checkpoint,
    datetime = lubridate::now(tzone = 'America/Detroit'),
    date = lubridate::today(tzone = 'America/Detroit'),
    time = Sys.time() |>
      lubridate::with_tz(tzone = "America/Detroit") |>
      lubridate::floor_date(unit = "minute"),
    timezone = "America/Detroit",
    wait_time = data_tbl$wait_time,
    wait_time_priority = NA_real_,
    wait_time_pre_check = data_tbl$wait_time,
    wait_time_clear = NA_real_
  ))

  assign("DTW_data", DTW_data, envir = .GlobalEnv)

  # Write to database ----
  dbAppendTable(con_write, name = "tsa_wait_times", value = DTW_data)

  print(glue("{nrow(DTW_data)} appended to tsa_wait_times at ", format(Sys.time(), "%a %b %d %X %Y")))

  # Cleanup ----
  rm(api_url)
  rm(status)
  rm(req)
  rm(response)
  rm(parsed_data)
  rm(data_tbl)
  rm(DTW_data, envir = .GlobalEnv)

}

# Testing ----

# scrape_tsa_data_dtw()
