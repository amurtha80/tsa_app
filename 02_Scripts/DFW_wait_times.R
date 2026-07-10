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

scrape_tsa_data_dfw <- function() {

  print(glue("kickoff DFW scrape ", format(Sys.time(), "%a %b %d %X %Y")))

  # API endpoint ----
  api_url <- "https://marketplace.locuslabs.com/venueId/dfw/dynamic-poi"

  # 1. Initialize the request
  req <- request(api_url)

  # 2. Build the exact browser mimic layer
  req <- req |>
    req_headers(
      `Accept`       = "*/*",
      `Origin`       = "https://www.dfwairport.com",
      `Referer`      = "https://www.dfwairport.com/",
      `x-account-id` = "A1GKNNFXZEQW1J",
      `User-Agent`   = "Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Mobile Safari/537.36"
    )

  # 3. Perform the request safely
  response <- req_perform(req)

  # 4. Check results
  status <- resp_status(response)
  # print(paste("HTTP Status Code:", status))

  # Parse checkpoints ----

  parsed_data <- resp_body_json(response)
  pois <- parsed_data$data

  # Keep only TSA security checkpoint POIs (dynamic filter -- POI IDs drift
  # over time as DFW adds/retires lanes, so do not hardcode a checkpoint ID list)
  security_pois <- purrr::keep(pois, ~ identical(.x$category, "security.checkpoint"))

  mine <- purrr::map_dfr(security_pois, function(x) {
    tibble::tibble(
      checkpoint = stringr::word(x$name, 1),
      lane_subtype = x$queue$queueSubtype %||% NA_character_,
      is_closed = isTRUE(x$isClosed) || isTRUE(x$isTemporarilyClosed),
      wait_minutes = x$time %||% NA_integer_
    )
  })

  mine <- mine |>
    dplyr::mutate(
      lane_type = dplyr::case_when(
        lane_subtype == "general"  ~ "wait_time",
        lane_subtype == "tsapre"   ~ "wait_time_pre_check",
        lane_subtype == "priority" ~ "wait_time_priority",
        TRUE ~ NA_character_
      ),
      wait_minutes = dplyr::if_else(is_closed, NA_real_, as.numeric(wait_minutes))
    )

  # Guard: a security checkpoint POI with no recognized lane subtype means
  # DFW's LocusLabs feed added a new queueSubtype -- stop and surface it
  # rather than let pivot_wider silently create an NA column.
  if (anyNA(mine$lane_type)) {
    bad_rows <- mine |> dplyr::filter(is.na(lane_type))
    stop(glue("DFW scrape: {nrow(bad_rows)} security checkpoint row(s) have no recognized ",
              "lane_type (queueSubtype not general/tsapre/priority). Checkpoint(s): ",
              "{paste(unique(bad_rows$checkpoint), collapse = ', ')}. ",
              "DFW/LocusLabs API schema may have changed -- investigate before re-running."))
  }

  mine <- mine |>
    dplyr::select(checkpoint, lane_type, wait_minutes) |>
    tidyr::pivot_wider(names_from = lane_type, values_from = wait_minutes)

  # Create tibble for data insertion ----
  if (!exists("DFW_data", envir = .GlobalEnv)) {
    DFW_data <- tibble::tibble(airport = character(),
                               checkpoint = character(),
                               datetime = lubridate::ymd_hms(tz = 'America/Chicago'),
                               date = lubridate::ymd(),
                               time = lubridate::POSIXct(tz = 'America/Chicago'),
                               timezone = character(),
                               wait_time = numeric(),
                               wait_time_priority = numeric(),
                               wait_time_pre_check = numeric(),
                               wait_time_clear = numeric())
  } else {
    DFW_data <- get("DFW_data", envir = .GlobalEnv)
  }

  DFW_data <- mine |>
    dplyr::mutate(
      airport = "DFW",
      datetime = lubridate::now(tzone = 'America/Chicago'),
      date = lubridate::today(),
      time = Sys.time() |>
        lubridate::with_tz(tzone = "America/Chicago") |>
        lubridate::floor_date(unit = "minute"),
      timezone = "America/Chicago",
      wait_time = round(wait_time),
      wait_time_priority = round(wait_time_priority),
      wait_time_pre_check = round(wait_time_pre_check),
      wait_time_clear = NA_real_
    ) |>
    dplyr::select(airport, checkpoint, datetime, date, time, timezone,
                  wait_time, wait_time_priority, wait_time_pre_check, wait_time_clear) |>
    dplyr::rows_append(x = DFW_data, y = _)

  assign("DFW_data", DFW_data, envir = .GlobalEnv)

  # Write to database ----

  dbAppendTable(con_write, name = "tsa_wait_times", value = DFW_data)

  print(glue("{nrow(DFW_data)} appended to tsa_wait_times at ", format(Sys.time(), "%a %b %d %X %Y")))


  # Cleanup ----
  rm(api_url)
  rm(status)
  rm(req)
  rm(response)
  rm(parsed_data)
  rm(pois)
  rm(security_pois)
  rm(mine)
  rm(DFW_data, envir = .GlobalEnv)

}

# Testing ----

# scrape_tsa_data_dfw()


# Test Loop ----
# i <- 1
#
# for (i in 1:5) {
#   p1 <- lubridate::ceiling_date(Sys.time(), unit = "minute")
#   print(glue(i, "  ", format(Sys.time())))
#   scrape_tsa_data_dfw()
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
# rm(scrape_tsa_data_dfw)
