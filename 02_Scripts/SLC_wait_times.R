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

scrape_tsa_data_slc <- function() {

  print(glue("kickoff SLC scrape ", format(Sys.time(), "%a %b %d %X %Y")))

  # API endpoint ----
  api_url <- "https://slcairport.com/ajaxtsa/waittimes"

  req <- request(api_url) |>
    req_headers(
      `accept`           = "*/*",
      `accept-language`  = "en-US,en;q=0.9",
      `referer`          = "https://slcairport.com/",
      `user-agent`       = "Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Mobile Safari/537.36",
      `x-requested-with` = "XMLHttpRequest"
    )

  response <- req_perform(req)
  status <- resp_status(response)

  # Parse checkpoints ----

  # Server sends "content-type: text/html" on a genuinely JSON body -- confirmed
  # via a live fetch, not a guess -- so the type check must be disabled or every
  # request errors regardless of payload validity.
  parsed_data <- resp_body_json(response, check_type = FALSE)

  # slcairport.com exposes a single airport-wide current wait ("rightnow", in
  # minutes) -- there is no per-checkpoint breakout anywhere in the payload.
  # "precheck_checkpoints" is the only live per-checkpoint signal (Open/Closed
  # per checkpoint, nested one level under terminal). "precheck" is an
  # airport-level boolean that PreCheck exists at all, not a distinct measured
  # PreCheck wait time. Per user decision: duplicate the single airport-wide
  # "rightnow" reading into both wait_time and wait_time_pre_check for each
  # checkpoint that's currently Open (gated independently per checkpoint),
  # since no other number exists to report. "estimated_hourly_times" is a
  # predicted/typical-pattern array (not a live reading) and "faa_alerts" is
  # unrelated to checkpoint wait times -- both ignored.
  rightnow <- as.numeric(parsed_data$rightnow)
  precheck_flag <- parsed_data$precheck

  raw_tbl <- purrr::imap_dfr(parsed_data$precheck_checkpoints, function(checkpoints, terminal) {
    purrr::imap_dfr(checkpoints, function(status, cp_name) {
      tibble::tibble(checkpoint = cp_name, status = status)
    })
  })

  # Only one terminal exists in the payload, so per the BOS/PHL "only
  # disambiguate on actual collision" convention, checkpoint names are stored
  # bare ("Checkpoint 1" / "Checkpoint 2") with no terminal prefix.
  data_tbl <- raw_tbl |>
    dplyr::mutate(
      is_open = status == "Open",
      wait_time = dplyr::if_else(is_open, rightnow, NA_real_),
      wait_time_pre_check = dplyr::if_else(is_open & (precheck_flag == 1), rightnow, NA_real_)
    )

  # Create tibble for data insertion ----
  if (!exists("SLC_data", envir = .GlobalEnv)) {
    SLC_data <- tibble::tibble(airport = character(),
                                checkpoint = character(),
                                datetime = lubridate::ymd_hms(tz = 'America/Denver'),
                                date = lubridate::ymd(),
                                time = lubridate::POSIXct(tz = 'America/Denver'),
                                timezone = character(),
                                wait_time = numeric(),
                                wait_time_priority = numeric(),
                                wait_time_pre_check = numeric(),
                                wait_time_clear = numeric())
  } else {
    SLC_data <- get("SLC_data", envir = .GlobalEnv)
  }

  SLC_data <- dplyr::rows_append(SLC_data, tibble::tibble(
    airport = "SLC",
    checkpoint = data_tbl$checkpoint,
    datetime = lubridate::now(tzone = 'America/Denver'),
    date = lubridate::today(tzone = 'America/Denver'),
    time = Sys.time() |>
      lubridate::with_tz(tzone = "America/Denver") |>
      lubridate::floor_date(unit = "minute"),
    timezone = "America/Denver",
    wait_time = data_tbl$wait_time,
    wait_time_priority = NA_real_,
    wait_time_pre_check = data_tbl$wait_time_pre_check,
    wait_time_clear = NA_real_
  ))

  assign("SLC_data", SLC_data, envir = .GlobalEnv)

  # Write to database ----
  dbAppendTable(con_write, name = "tsa_wait_times", value = SLC_data)

  print(glue("{nrow(SLC_data)} appended to tsa_wait_times at ", format(Sys.time(), "%a %b %d %X %Y")))

  # Cleanup ----
  rm(api_url)
  rm(status)
  rm(req)
  rm(response)
  rm(parsed_data)
  rm(rightnow, precheck_flag)
  rm(raw_tbl)
  rm(data_tbl)
  rm(SLC_data, envir = .GlobalEnv)

}

# Testing ----

# scrape_tsa_data_slc()
