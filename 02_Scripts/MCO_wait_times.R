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

scrape_tsa_data_mco <- function() {

  print(glue("kickoff MCO scrape ", format(Sys.time(), "%a %b %d %X %Y")))

  # API endpoint ----
  api_url <- "https://api.goaa.aero/wait-times/checkpoint/MCO"

  req <- request(api_url) |>
    req_method("GET") |>
    req_headers(
      `api-key`     = "8eaac7209c824616a8fe58d22268cd59",
      `api-version` = "140",
      `Origin`      = "https://flymco.com",
      `Referer`     = "https://flymco.com/"
    )

  response <- req_perform(req)
  status <- resp_status(response)

  # Parse checkpoints ----

  parsed_data <- resp_body_json(response)
  res_list <- parsed_data$data$wait_times

  # Conservative range parse: prefer maxWaitSeconds over waitSeconds when both
  # are present, same "never understate the wait" convention established for
  # DCA's string-range parsing and reused verbatim from IAH_wait_times.R.
  parse_minutes <- function(cp) {
    secs <- c(cp$waitSeconds, cp$maxWaitSeconds)
    secs <- secs[!vapply(secs, is.null, logical(1))]
    if (length(secs) == 0) return(NA_real_)
    max(as.numeric(secs)) / 60
  }

  # name arrives as "<Side> <Standard|PreCheck>" (e.g. "South Standard"). The
  # physical checkpoint is derived from each lane's own attributes.minGate/
  # maxGate (not the Side label) as "Gates {min} - {max}" -- confirmed to
  # reproduce the DB's existing checkpoint convention exactly (West->"Gates 1 -
  # 59", East->"Gates 70 - 129", South->"Gates C230 - C254"). No CLEAR lane
  # exists in this payload.
  raw_tbl <- purrr::map_dfr(res_list, function(cp) {
    lane_type <- stringr::word(cp$name, -1)
    if (!lane_type %in% c("Standard", "PreCheck")) return(NULL)

    checkpoint <- paste0("Gates ", cp$attributes$minGate, " - ", cp$attributes$maxGate)

    # Honor the API's own live open/displayable flags -- primary gate.
    wait_min <- parse_minutes(cp)
    if (!isTRUE(cp$isOpen) || !isTRUE(cp$isDisplayable)) wait_min <- NA_real_

    tibble::tibble(checkpoint = checkpoint, lane_type = lane_type, wait_min = wait_min)
  })

  # Pivot wide: one row per physical checkpoint, separate columns per lane type
  data_tbl <- raw_tbl |>
    dplyr::select(checkpoint, lane_type, wait_min) |>
    tidyr::pivot_wider(names_from = lane_type, values_from = wait_min)

  if (!"Standard" %in% names(data_tbl)) data_tbl$Standard <- NA_real_
  if (!"PreCheck" %in% names(data_tbl)) data_tbl$PreCheck <- NA_real_

  # Backstop gate: airport_checkpoint_hours -- this API never populates
  # openTime/closeTime (both null on every lane observed), so unlike IAH/PDX
  # there is no live per-checkpoint hours signal in the payload itself; the
  # isOpen/isDisplayable flags above are the primary gate, this is the sole
  # backstop, same "don't remove a known-necessary gate" reasoning as the
  # DCA/IAH/PDX migrations.
  mco_hours <- dbGetQuery(con_write, "
    SELECT checkpoint, open_time_gen, close_time_gen, open_time_prechk, close_time_prechk
    FROM airport_checkpoint_hours
    WHERE airport = 'MCO'
  ")
  now_et <- lubridate::now(tzone = "America/New_York")
  now_minutes_of_day <- lubridate::hour(now_et) * 60 + lubridate::minute(now_et)
  tod_minutes <- function(ts) lubridate::hour(ts) * 60 + lubridate::minute(ts)

  is_open <- function(cp, open_col, close_col) {
    hrs <- mco_hours[mco_hours$checkpoint == cp, ]
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
  data_tbl$Standard[!gen_open]  <- NA_real_
  data_tbl$PreCheck[!prek_open] <- NA_real_

  # Create tibble for data insertion ----
  if (!exists("MCO_data", envir = .GlobalEnv)) {
    MCO_data <- tibble::tibble(airport = character(),
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
    MCO_data <- get("MCO_data", envir = .GlobalEnv)
  }

  MCO_data <- dplyr::rows_append(MCO_data, tibble::tibble(
    airport = "MCO",
    checkpoint = data_tbl$checkpoint,
    datetime = lubridate::now(tzone = 'America/New_York'),
    date = lubridate::today(tzone = 'America/New_York'),
    time = Sys.time() |>
      lubridate::with_tz(tzone = "America/New_York") |>
      lubridate::floor_date(unit = "minute"),
    timezone = "America/New_York",
    wait_time = data_tbl$Standard,
    wait_time_priority = NA_real_,
    wait_time_pre_check = data_tbl$PreCheck,
    wait_time_clear = NA_real_
  ))

  assign("MCO_data", MCO_data, envir = .GlobalEnv)

  # Write to database ----
  dbAppendTable(con_write, name = "tsa_wait_times", value = MCO_data)

  print(glue("{nrow(MCO_data)} appended to tsa_wait_times at ", format(Sys.time(), "%a %b %d %X %Y")))

  # Cleanup ----
  rm(api_url)
  rm(status)
  rm(req)
  rm(response)
  rm(parsed_data)
  rm(res_list)
  rm(raw_tbl)
  rm(data_tbl)
  rm(mco_hours, now_et, now_minutes_of_day, tod_minutes, is_open, gen_open, prek_open)
  rm(MCO_data, envir = .GlobalEnv)

}

# Testing ----

# scrape_tsa_data_mco()
