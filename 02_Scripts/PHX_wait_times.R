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

scrape_tsa_data_phx <- function() {

  print(glue("kickoff PHX scrape ", format(Sys.time(), "%a %b %d %X %Y")))

  # API endpoint ----
  api_url <- "https://api.phx.aero/avn-wait-times/raw?Key=4f85fe2ef5a240d59809b63de94ef536"

  req <- request(api_url) |>
    req_headers(
      `accept`     = "*/*",
      `origin`     = "https://www.skyharbor.com",
      `referer`    = "https://www.skyharbor.com/",
      `user-agent` = "Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Mobile Safari/537.36"
    )

  response <- req_perform(req)
  status <- resp_status(response)

  # Parse checkpoints ----

  parsed_data <- resp_body_json(response)

  # api.phx.aero returns "success": false in the envelope even when "current"
  # holds valid live readings (confirmed via a live fetch) -- gate on the
  # array being present/non-empty, not on the success flag.
  if (length(parsed_data$current) == 0) {
    stop(glue("PHX scrape: no checkpoint readings in 'current' array -- ",
              "API payload shape may have changed."))
  }

  # No live open/closed flag and no distinct PreCheck field anywhere in the
  # payload -- per SLC/DTW "mirror the only number" convention, the single
  # projectedWaitTime reading is duplicated into wait_time_pre_check.
  # projectedWaitTime is in SECONDS (confirmed: 360/60=6=avg(4,8) min/max;
  # 420/60=7=avg(5,9) min/max), so divide by 60 rather than average the two
  # minute fields. Queue names all end in " General" with no distinct
  # PreCheck queue, so that suffix is stripped as redundant.
  data_tbl <- purrr::map_dfr(parsed_data$current, function(cp) {
    tibble::tibble(
      checkpoint = stringr::str_remove(cp$queueName, " General$") |> stringr::str_squish(),
      wait_time = as.numeric(cp$projectedWaitTime) / 60
    )
  })

  # Create tibble for data insertion ----
  if (!exists("PHX_data", envir = .GlobalEnv)) {
    PHX_data <- tibble::tibble(airport = character(),
                                checkpoint = character(),
                                datetime = lubridate::ymd_hms(tz = 'America/Phoenix'),
                                date = lubridate::ymd(),
                                time = lubridate::POSIXct(tz = 'America/Phoenix'),
                                timezone = character(),
                                wait_time = numeric(),
                                wait_time_priority = numeric(),
                                wait_time_pre_check = numeric(),
                                wait_time_clear = numeric())
  } else {
    PHX_data <- get("PHX_data", envir = .GlobalEnv)
  }

  PHX_data <- dplyr::rows_append(PHX_data, tibble::tibble(
    airport = "PHX",
    checkpoint = data_tbl$checkpoint,
    datetime = lubridate::now(tzone = 'America/Phoenix'),
    date = lubridate::today(tzone = 'America/Phoenix'),
    time = Sys.time() |>
      lubridate::with_tz(tzone = "America/Phoenix") |>
      lubridate::floor_date(unit = "minute"),
    timezone = "America/Phoenix",
    wait_time = data_tbl$wait_time,
    wait_time_priority = NA_real_,
    wait_time_pre_check = data_tbl$wait_time,
    wait_time_clear = NA_real_
  ))

  assign("PHX_data", PHX_data, envir = .GlobalEnv)

  # Write to database ----
  dbAppendTable(con_write, name = "tsa_wait_times", value = PHX_data)

  print(glue("{nrow(PHX_data)} appended to tsa_wait_times at ", format(Sys.time(), "%a %b %d %X %Y")))

  # Cleanup ----
  rm(api_url)
  rm(status)
  rm(req)
  rm(response)
  rm(parsed_data)
  rm(data_tbl)
  rm(PHX_data, envir = .GlobalEnv)

}

# Testing ----

# scrape_tsa_data_phx()
