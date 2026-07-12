# install.packages(c("DBI", "httr2", "jsonlite", "rvest", "tidyverse", "duckdb",
#  "lubridate", "glue", "here"))

# library(httr2, verbose = FALSE, warn.conflicts = FALSE)
# library(jsonlite, verbose = FALSE, warn.conflicts = FALSE)
# library(rvest, verbose = FALSE, warn.conflicts = FALSE)
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
scrape_tsa_data_phl <- function() {

  print(glue("kickoff PHL scrape ", format(Sys.time(), "%a %b %d %X %Y")))

  # Zone ID -> checkpoint/lane_type map ----
  # Sourced from phl.org's wait-api.js, which reads these same IDs out of
  # the /phllivereach/metrics feed and writes them into the checkpoint-hours
  # page. The feed carries ~14 additional zone IDs unrelated to these
  # checkpoints (other PHL LiveReach metrics) -- only these 8 are relevant.
  zone_map <- tibble::tribble(
    ~zone_id, ~checkpoint,         ~lane_type,
    3971,     "Terminal D/E",      "wait_time",
    4126,     "Terminal D/E",      "wait_time_pre_check",
    4368,     "Terminal A-East",   "wait_time",
    4386,     "Terminal A-East",   "wait_time_pre_check",
    4377,     "Terminal A-West 2", "wait_time",
    5047,     "Terminal B",        "wait_time",
    5052,     "Terminal C",        "wait_time_pre_check",
    5068,     "Terminal F",        "wait_time"
  )

  # API endpoint ----
  api_url <- "https://www.phl.org/phllivereach/metrics"

  req <- request(api_url) |>
    req_headers(
      `Accept`     = "application/json, text/plain, */*",
      `Referer`    = "https://www.phl.org/flights/security-information/checkpoint-hours",
      `User-Agent` = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36"
    )

  response <- req_perform(req)
  status <- resp_status(response)
  # print(paste("HTTP Status Code:", status))

  parsed_data <- resp_body_json(response)
  rows <- parsed_data$content$rows

  metrics <- purrr::map_dfr(rows, function(x) {
    tibble::tibble(zone_id = x[[1]], wait_minutes = x[[2]])
  })

  # Guard: all 8 expected zone IDs must be present -- if PHL retires/renames
  # a zone this stops loudly rather than silently dropping a checkpoint.
  # (The feed carries other, unmapped zone IDs too -- that's expected, not
  # an error condition here.)
  missing_ids <- setdiff(zone_map$zone_id, metrics$zone_id)
  if (length(missing_ids) > 0) {
    stop(glue("PHL scrape: expected zone ID(s) {paste(missing_ids, collapse = ', ')} ",
              "missing from /phllivereach/metrics response. PHL may have changed ",
              "zone IDs or retired a checkpoint -- investigate before re-running."))
  }

  api_checkpoints <- zone_map |>
    dplyr::inner_join(metrics, by = "zone_id") |>
    dplyr::select(checkpoint, lane_type, wait_minutes) |>
    tidyr::pivot_wider(names_from = lane_type, values_from = wait_minutes)

  # Guard: Terminal A-East and Terminal F don't clear their wait time overnight
  # -- the feed leaves a stale ~3 min reading in place for the entire closed
  # window instead of dropping the zone or returning a null. Scoped to just
  # these two checkpoints (the other live-feed checkpoints -- D/E, A-West 2, B,
  # C -- weren't flagged by the overnight audit and are left alone). Same
  # pattern as the A-West 1 gate below, and as DCA/IAH/MIA/MSP.
  stale_gate_hours <- dbGetQuery(con_write, "
    SELECT checkpoint, open_time_gen, close_time_gen, open_time_prechk, close_time_prechk
    FROM airport_checkpoint_hours
    WHERE airport = 'PHL' AND checkpoint IN ('Terminal A-East', 'Terminal F')
  ")
  now_et_gate <- lubridate::now(tzone = "America/New_York")
  now_min_gate <- lubridate::hour(now_et_gate) * 60 + lubridate::minute(now_et_gate)
  tod_minutes_gate <- function(ts) lubridate::hour(ts) * 60 + lubridate::minute(ts)
  is_open_gate <- function(cp, open_col, close_col) {
    hrs <- stale_gate_hours[stale_gate_hours$checkpoint == cp, ]
    open_val  <- hrs[[open_col]][1]
    close_val <- hrs[[close_col]][1]
    if (nrow(hrs) == 0 || is.na(open_val) || is.na(close_val)) return(TRUE)
    open_min  <- tod_minutes_gate(open_val)
    close_min <- tod_minutes_gate(close_val)
    if (close_min < open_min) {
      now_min_gate >= open_min || now_min_gate <= close_min
    } else {
      now_min_gate >= open_min && now_min_gate <= close_min
    }
  }
  if (!is_open_gate("Terminal A-East", "open_time_gen", "close_time_gen")) {
    api_checkpoints$wait_time[api_checkpoints$checkpoint == "Terminal A-East"] <- NA_real_
  }
  if (!is_open_gate("Terminal A-East", "open_time_prechk", "close_time_prechk")) {
    api_checkpoints$wait_time_pre_check[api_checkpoints$checkpoint == "Terminal A-East"] <- NA_real_
  }
  if (!is_open_gate("Terminal F", "open_time_gen", "close_time_gen")) {
    api_checkpoints$wait_time[api_checkpoints$checkpoint == "Terminal F"] <- NA_real_
  }

  # Terminal A-West 1 ----
  # Not part of the metrics feed at all (wait-api.js never targets #aw1Gen) --
  # its wait time is a static value manually maintained in the checkpoint-hours
  # page's HTML itself. Scrape the static page (no chromote needed) and treat
  # it as PreCheck-only, per the page's own note that A-West 1 is a PreCheck lane.
  hours_url <- "https://www.phl.org/flights/security-information/checkpoint-hours"
  hours_page <- rvest::read_html(hours_url)

  aw1_card <- hours_page |>
    rvest::html_elements("a.term") |>
    purrr::keep(~ stringr::str_detect(rvest::html_text2(rvest::html_element(.x, "h2")), "A-West 1"))

  # A-West 1's wait value is static markup, not a live feed -- wait-api.js only
  # uses its published hours to toggle the open/closed status badge, never to
  # gate this value, so it reads "< 10" around the clock even when closed.
  # Gate on airport_checkpoint_hours (PreCheck window) rather than write a
  # meaningless number for the hours this checkpoint isn't open -- replaces
  # the old hardcoded 3:00pm-5:30pm check now that the hours table is populated.
  aw1_hours <- dbGetQuery(con_write, "
    SELECT open_time_prechk, close_time_prechk FROM airport_checkpoint_hours
    WHERE airport = 'PHL' AND checkpoint = 'Terminal A-West 1'
  ")
  now_et <- lubridate::now(tzone = "America/New_York")
  now_minutes_of_day <- lubridate::hour(now_et) * 60 + lubridate::minute(now_et)
  tod_minutes <- function(ts) lubridate::hour(ts) * 60 + lubridate::minute(ts)
  aw1_open <- if (nrow(aw1_hours) == 0 || is.na(aw1_hours$open_time_prechk[1])) {
    FALSE
  } else {
    now_minutes_of_day >= tod_minutes(aw1_hours$open_time_prechk[1]) &&
      now_minutes_of_day <= tod_minutes(aw1_hours$close_time_prechk[1])
  }

  aw1_wait <- if (length(aw1_card) == 0 || !aw1_open) {
    # Card absent entirely (PHL swapped in the commented-out "CLOSED" variant)
    # or outside its 3:00pm-5:30pm operating window
    NA_real_
  } else {
    span_text <- aw1_card[[1]] |>
      rvest::html_element("#aw1Gen") |>
      rvest::html_text2()
    if (is.na(span_text)) NA_real_ else readr::parse_number(span_text)
  }

  aw1_checkpoint <- tibble::tibble(
    checkpoint = "Terminal A-West 1",
    wait_time = NA_real_,
    wait_time_pre_check = aw1_wait
  )

  mine <- dplyr::bind_rows(api_checkpoints, aw1_checkpoint)

  # Create tibble for data insertion ----
  if (!exists("PHL_data", envir = .GlobalEnv)) {
    PHL_data <- tibble::tibble(airport = character(),
                               checkpoint = character(),
                               datetime = lubridate::ymd_hms(tz = 'America/New_York'),
                               date = lubridate::ymd(),
                               time = lubridate::POSIXct(tz = 'America/New_York'),
                               timezone = character(),
                               wait_time = numeric(),
                               wait_time_priority = numeric(),
                               wait_time_pre_check = numeric(),
                               wait_time_clear = numeric())
  } else {
    PHL_data <- get("PHL_data", envir = .GlobalEnv)
  }

  PHL_data <- mine |>
    dplyr::mutate(
      airport = "PHL",
      datetime = lubridate::now(tzone = 'America/New_York'),
      date = lubridate::today(),
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
    dplyr::arrange(checkpoint) |>
    dplyr::rows_append(x = PHL_data, y = _)

  assign("PHL_data", PHL_data, envir = .GlobalEnv)

  # Write to database ----

  dbAppendTable(con_write, name = "tsa_wait_times", value = PHL_data)

  print(glue("{nrow(PHL_data)} appended to tsa_wait_times at ", format(Sys.time(), "%a %b %d %X %Y")))


  # Cleanup ----
  rm(zone_map)
  rm(api_url)
  rm(status)
  rm(req)
  rm(response)
  rm(parsed_data)
  rm(rows)
  rm(metrics)
  rm(missing_ids)
  rm(stale_gate_hours, now_et_gate, now_min_gate, tod_minutes_gate, is_open_gate)
  rm(api_checkpoints)
  rm(hours_url)
  rm(hours_page)
  rm(aw1_card)
  rm(aw1_hours)
  rm(now_et)
  rm(now_minutes_of_day)
  rm(tod_minutes)
  rm(aw1_open)
  rm(aw1_wait)
  rm(aw1_checkpoint)
  rm(mine)
  rm(PHL_data, envir = .GlobalEnv)

}

# Testing ----

# scrape_tsa_data_phl()


# Test Loop ----
# i <- 1
#
# for (i in 1:5) {
#   p1 <- lubridate::ceiling_date(Sys.time(), unit = "minute")
#   print(glue(i, "  ", format(Sys.time())))
#   scrape_tsa_data_phl()
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
# rm(scrape_tsa_data_phl)
