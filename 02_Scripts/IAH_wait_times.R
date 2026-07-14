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

scrape_tsa_data_iah <- function() {

  print(glue("kickoff IAH scrape ", format(Sys.time(), "%a %b %d %X %Y")))

  # API endpoint ----
  api_url <- "https://api.houstonairports.mobi/wait-times/checkpoint/iah"

  req <- request(api_url) |>
    req_method("GET") |>
    req_headers(
      `api-key`     = "9ACB3B733BE94B11A03B6E84CA87E895",
      `api-version` = "120",
      `Origin`      = "https://www.fly2houston.com",
      `Referer`     = "https://www.fly2houston.com/"
    )

  response <- req_perform(req)
  status <- resp_status(response)

  # Parse checkpoints ----

  parsed_data <- resp_body_json(response)
  res_list <- parsed_data$data$wait_times

  # Conservative range parse: prefer maxWaitSeconds over waitSeconds when both
  # are present, same "never understate the wait" convention established for
  # DCA's string-range parsing.
  parse_minutes <- function(cp) {
    secs <- c(cp$waitSeconds, cp$maxWaitSeconds)
    secs <- secs[!vapply(secs, is.null, logical(1))]
    if (length(secs) == 0) return(NA_real_)
    max(as.numeric(secs)) / 60
  }

  # name arrives as "<physical checkpoint> <lane type>" (e.g. "IAH Terminal A
  # North Standard"), except the FIS/customs entry which has no lane suffix
  # and is excluded below -- it never appears on the live wait-times page and
  # isn't part of what this scraper has ever collected.
  raw_tbl <- purrr::map_dfr(res_list, function(cp) {
    lane_type  <- stringr::word(cp$name, -1)
    if (!lane_type %in% c("Standard", "PreCheck", "Premier")) return(NULL)

    checkpoint <- stringr::str_squish(
      stringr::str_remove(cp$name, " (Standard|PreCheck|Premier)$")
    )

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
  if (!"Premier"  %in% names(data_tbl)) data_tbl$Premier  <- NA_real_

  # Guard: fly2houston.com does not clear the Standard-lane wait time for
  # Terminal A South when it closes overnight -- backstop kept in addition to
  # the API's own isOpen/isDisplayable flags, same pattern as the DCA/PHL
  # A-West 1 fixes (don't remove a known-necessary gate just because the API
  # also exposes its own flags).
  a_south_hours <- dbGetQuery(con_write, "
    SELECT open_time_gen, close_time_gen
    FROM airport_checkpoint_hours
    WHERE airport = 'IAH' AND checkpoint = 'IAH Terminal A South'
  ")
  now_ct <- lubridate::now(tzone = "America/Chicago")
  now_minutes_of_day <- lubridate::hour(now_ct) * 60 + lubridate::minute(now_ct)
  tod_minutes <- function(ts) lubridate::hour(ts) * 60 + lubridate::minute(ts)
  a_south_open <- if (nrow(a_south_hours) == 0 ||
                       is.na(a_south_hours$open_time_gen[1]) ||
                       is.na(a_south_hours$close_time_gen[1])) {
    TRUE
  } else {
    open_min  <- tod_minutes(a_south_hours$open_time_gen[1])
    close_min <- tod_minutes(a_south_hours$close_time_gen[1])
    if (close_min < open_min) {
      now_minutes_of_day >= open_min || now_minutes_of_day <= close_min
    } else {
      now_minutes_of_day >= open_min && now_minutes_of_day <= close_min
    }
  }
  if (!a_south_open) {
    data_tbl$Standard[data_tbl$checkpoint == "IAH Terminal A South"] <- NA_real_
  }

  # Create tibble for data insertion ----
  if (!exists("IAH_data", envir = .GlobalEnv)) {
    IAH_data <- tibble::tibble(airport = character(),
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
    IAH_data <- get("IAH_data", envir = .GlobalEnv)
  }

  IAH_data <- dplyr::rows_append(IAH_data, tibble::tibble(
    airport = "IAH",
    checkpoint = data_tbl$checkpoint,
    datetime = lubridate::now(tzone = 'America/Chicago'),
    date = lubridate::today(tzone = 'America/Chicago'),
    time = Sys.time() |>
      lubridate::with_tz(tzone = "America/Chicago") |>
      lubridate::floor_date(unit = "minute"),
    timezone = "America/Chicago",
    wait_time = data_tbl$Standard,
    wait_time_priority = data_tbl$Premier,
    wait_time_pre_check = data_tbl$PreCheck,
    wait_time_clear = NA_real_
  ))

  assign("IAH_data", IAH_data, envir = .GlobalEnv)

  # Write to database ----
  dbAppendTable(con_write, name = "tsa_wait_times", value = IAH_data)

  print(glue("{nrow(IAH_data)} appended to tsa_wait_times at ", format(Sys.time(), "%a %b %d %X %Y")))

  # Cleanup ----
  rm(api_url)
  rm(status)
  rm(req)
  rm(response)
  rm(parsed_data)
  rm(res_list)
  rm(raw_tbl)
  rm(data_tbl)
  rm(a_south_hours, now_ct, now_minutes_of_day, tod_minutes, a_south_open)
  rm(IAH_data, envir = .GlobalEnv)

}

# Testing ----

# scrape_tsa_data_iah()
