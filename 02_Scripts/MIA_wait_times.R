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

scrape_tsa_data_mia <- function() {

  print(glue("kickoff MIA scrape ", format(Sys.time(), "%a %b %d %X %Y")))

  # API endpoint ----
  api_url <- "https://waittime.api.aero/waittime/v2/current/MIA"

  req <- request(api_url) |>
    req_method("GET") |>
    req_headers(
      `x-apikey` = "5d0cacea6e41416fdcde0c5c5a19d867",
      `Origin`   = "https://www.miami-airport.com",
      `Referer`  = "https://www.miami-airport.com/tsa-waittimes.asp"
    )

  response <- req_perform(req)
  status <- resp_status(response)

  # Parse checkpoints ----

  parsed_data <- resp_body_json(response)
  res_list <- parsed_data$current

  # Conservative range parse: prefer the max of the projected-range minutes
  # over the live projectedWaitTime (seconds) when they disagree, same
  # "never understate the wait" convention reused from
  # DCA/IAH/MCO_wait_times.R.
  parse_minutes <- function(cp) {
    mins <- c(cp$projectedWaitTime / 60, cp$projectedMaxWaitMinutes)
    mins <- mins[!vapply(mins, is.null, logical(1))]
    if (length(mins) == 0) return(NA_real_)
    max(as.numeric(mins))
  }

  # queueName arrives as "<checkpoint> <lane>" (e.g. "8 TSA-Pre", "FIS
  # General") -- checkpoint token is always the first word (bare numeric
  # "1".."10" or "FIS"), lane is everything after. Verified this reproduces
  # the DB's existing 11-checkpoint convention exactly (every checkpoint/lane
  # combination present in the API matches which columns are historically
  # populated vs. NA for that checkpoint in tsa_wait_times).
  raw_tbl <- purrr::map_dfr(res_list, function(cp) {
    checkpoint <- stringr::word(cp$queueName, 1)
    lane_type  <- stringr::word(cp$queueName, 2, -1)
    if (!lane_type %in% c("General", "Priority", "TSA-Pre", "Clear")) return(NULL)

    # Honor the API's own live status flag -- primary gate.
    wait_min <- parse_minutes(cp)
    if (!identical(cp$status, "Open")) wait_min <- NA_real_

    tibble::tibble(checkpoint = checkpoint, lane_type = lane_type, wait_min = wait_min)
  })

  # Pivot wide: one row per physical checkpoint, separate columns per lane type
  data_tbl <- raw_tbl |>
    dplyr::select(checkpoint, lane_type, wait_min) |>
    tidyr::pivot_wider(names_from = lane_type, values_from = wait_min)

  for (lane in c("General", "Priority", "TSA-Pre", "Clear")) {
    if (!lane %in% names(data_tbl)) data_tbl[[lane]] <- NA_real_
  }

  # Backstop gate: airport_checkpoint_hours -- kept alongside the live status
  # flag above per the now-standard "don't remove a known-necessary gate"
  # reasoning from DCA/IAH/PDX/MCO. This replaces the old RSelenium-era
  # one-off patch (checkpoints 4/10 not clearing General immediately at
  # close) -- the live per-lane status flag is now the real protection
  # against that, same reasoning IAH used to retire its Terminal D patch.
  #
  # This table can carry same-day correction duplicates for one checkpoint
  # (e.g. checkpoint "2" has two rows from a 2026-07-12 hours correction) --
  # dedup to the most recent row per checkpoint via entry_timestamp, same
  # convention as xx_build_summary_DB.R's hours_lookup, before using it here.
  mia_hours <- dbGetQuery(con_write, "
    SELECT checkpoint, open_time_gen, close_time_gen, open_time_prechk, close_time_prechk, entry_timestamp
    FROM airport_checkpoint_hours
    WHERE airport = 'MIA'
  ") |>
    dplyr::group_by(checkpoint) |>
    dplyr::slice_max(entry_timestamp, n = 1, with_ties = FALSE) |>
    dplyr::ungroup()

  now_et <- lubridate::now(tzone = "America/New_York")
  now_minutes_of_day <- lubridate::hour(now_et) * 60 + lubridate::minute(now_et)
  tod_minutes <- function(ts) lubridate::hour(ts) * 60 + lubridate::minute(ts)

  is_open <- function(cp, open_col, close_col) {
    hrs <- mia_hours[mia_hours$checkpoint == cp, ]
    if (nrow(hrs) == 0 || is.na(hrs[[open_col]][1]) || is.na(hrs[[close_col]][1])) {
      return(TRUE)
    }
    open_min  <- tod_minutes(hrs[[open_col]][1])
    close_min <- tod_minutes(hrs[[close_col]][1])
    if (close_min < open_min) {
      now_minutes_of_day >= open_min || now_minutes_of_day <= close_min
    } else {
      now_minutes_of_day >= open_min && now_minutes_of_day <= close_min
    }
  }

  gen_open  <- purrr::map_lgl(data_tbl$checkpoint, is_open, open_col = "open_time_gen", close_col = "close_time_gen")
  prek_open <- purrr::map_lgl(data_tbl$checkpoint, is_open, open_col = "open_time_prechk", close_col = "close_time_prechk")
  data_tbl$General[!gen_open]    <- NA_real_
  data_tbl$`TSA-Pre`[!prek_open] <- NA_real_

  # Create tibble for data insertion ----
  if (!exists("MIA_data", envir = .GlobalEnv)) {
    MIA_data <- tibble::tibble(airport = character(),
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
    MIA_data <- get("MIA_data", envir = .GlobalEnv)
  }

  MIA_data <- dplyr::rows_append(MIA_data, tibble::tibble(
    airport = "MIA",
    checkpoint = data_tbl$checkpoint,
    datetime = lubridate::now(tzone = 'America/New_York'),
    date = lubridate::today(tzone = 'America/New_York'),
    time = Sys.time() |>
      lubridate::with_tz(tzone = "America/New_York") |>
      lubridate::floor_date(unit = "minute"),
    timezone = "America/New_York",
    wait_time = data_tbl$General,
    wait_time_priority = data_tbl$Priority,
    wait_time_pre_check = data_tbl$`TSA-Pre`,
    wait_time_clear = data_tbl$Clear
  ))

  assign("MIA_data", MIA_data, envir = .GlobalEnv)

  # Write to database ----
  dbAppendTable(con_write, name = "tsa_wait_times", value = MIA_data)

  print(glue("{nrow(MIA_data)} appended to tsa_wait_times at ", format(Sys.time(), "%a %b %d %X %Y")))

  # Cleanup ----
  rm(api_url)
  rm(status)
  rm(req)
  rm(response)
  rm(parsed_data)
  rm(res_list)
  rm(raw_tbl)
  rm(data_tbl)
  rm(mia_hours, now_et, now_minutes_of_day, tod_minutes, is_open, gen_open, prek_open)
  rm(MIA_data, envir = .GlobalEnv)

}

# Testing ----

# scrape_tsa_data_mia()
