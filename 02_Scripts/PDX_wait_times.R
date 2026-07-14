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

scrape_tsa_data_pdx <- function() {

  print(glue("kickoff PDX scrape ", format(Sys.time(), "%a %b %d %X %Y")))

  # API endpoint ----
  cache_buster <- as.character(round(as.numeric(Sys.time()) * 1000))
  api_url <- "https://www.flypdx.com/TSAWaitTimesRefresh"

  req <- request(api_url) |>
    req_method("GET") |>
    req_url_query(`_` = cache_buster) |>
    req_headers(
      `Referer`          = "https://www.flypdx.com/",
      `X-Requested-With` = "XMLHttpRequest"
    )

  response <- req_perform(req)
  status <- resp_status(response)

  # Parse checkpoints ----

  parsed_data <- resp_body_json(response)

  # CounterName arrives as "<North|South><General|Precheck>". North = "Security
  # checkpoint for gates DE", South = "Security checkpoint for gates BC" --
  # mapping confirmed against PDX_in_progress.R's own comment and matched
  # against the DB's existing checkpoint naming convention. No CLEAR lane
  # exists in this payload.
  checkpoint_map <- c(North = "Security checkpoint for gates DE",
                       South = "Security checkpoint for gates BC")

  raw_tbl <- purrr::map_dfr(parsed_data$WaitTimes, function(cp) {
    side      <- stringr::str_extract(cp$CounterName, "^(North|South)")
    lane_type <- stringr::str_remove(cp$CounterName, "^(North|South)")

    tibble::tibble(
      checkpoint = checkpoint_map[[side]],
      lane_type = lane_type,
      wait_min = readr::parse_number(cp$DisplayText %||% NA_character_)
    )
  })

  data_tbl <- raw_tbl |>
    tidyr::pivot_wider(names_from = lane_type, values_from = wait_min)

  # Primary gate: the API's own live per-checkpoint Closed flags.
  if (isTRUE(parsed_data$NorthCheckpointClosed)) {
    data_tbl$General[data_tbl$checkpoint == "Security checkpoint for gates DE"] <- NA_real_
    data_tbl$Precheck[data_tbl$checkpoint == "Security checkpoint for gates DE"] <- NA_real_
  }
  if (isTRUE(parsed_data$SouthCheckpointClosed)) {
    data_tbl$General[data_tbl$checkpoint == "Security checkpoint for gates BC"] <- NA_real_
    data_tbl$Precheck[data_tbl$checkpoint == "Security checkpoint for gates BC"] <- NA_real_
  }

  # Backstop gate: airport_checkpoint_hours, in addition to the live Closed
  # flags above -- same "don't remove a known-necessary gate just because the
  # API also exposes its own flag" reasoning as the DCA/IAH migrations, since
  # the live Closed flag's reliability over time is unproven.
  pdx_hours <- dbGetQuery(con_write, "
    SELECT checkpoint, open_time_gen, close_time_gen
    FROM airport_checkpoint_hours
    WHERE airport = 'PDX'
  ")
  now_pt <- lubridate::now(tzone = "America/Los_Angeles")
  now_minutes_of_day <- lubridate::hour(now_pt) * 60 + lubridate::minute(now_pt)
  tod_minutes <- function(ts) lubridate::hour(ts) * 60 + lubridate::minute(ts)

  is_checkpoint_open <- function(cp) {
    hrs <- pdx_hours[pdx_hours$checkpoint == cp, ]
    if (nrow(hrs) == 0 || is.na(hrs$open_time_gen[1]) || is.na(hrs$close_time_gen[1])) {
      return(TRUE)
    }
    now_minutes_of_day >= tod_minutes(hrs$open_time_gen[1]) &&
      now_minutes_of_day <= tod_minutes(hrs$close_time_gen[1])
  }

  open_now <- purrr::map_lgl(data_tbl$checkpoint, is_checkpoint_open)
  data_tbl$General[!open_now] <- NA_real_

  # Create tibble for data insertion ----
  if (!exists("PDX_data", envir = .GlobalEnv)) {
    PDX_data <- tibble::tibble(airport = character(),
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
    PDX_data <- get("PDX_data", envir = .GlobalEnv)
  }

  PDX_data <- dplyr::rows_append(PDX_data, tibble::tibble(
    airport = "PDX",
    checkpoint = data_tbl$checkpoint,
    datetime = lubridate::now(tzone = 'America/Los_Angeles'),
    date = lubridate::today(tzone = 'America/Los_Angeles'),
    time = Sys.time() |>
      lubridate::with_tz(tzone = "America/Los_Angeles") |>
      lubridate::floor_date(unit = "minute"),
    timezone = "America/Los_Angeles",
    wait_time = data_tbl$General,
    wait_time_priority = NA_real_,
    wait_time_pre_check = data_tbl$Precheck,
    wait_time_clear = NA_real_
  ))

  assign("PDX_data", PDX_data, envir = .GlobalEnv)

  # Write to database ----
  dbAppendTable(con_write, name = "tsa_wait_times", value = PDX_data)

  print(glue("{nrow(PDX_data)} appended to tsa_wait_times at ", format(Sys.time(), "%a %b %d %X %Y")))

  # Cleanup ----
  rm(cache_buster)
  rm(api_url)
  rm(status)
  rm(req)
  rm(response)
  rm(parsed_data)
  rm(checkpoint_map)
  rm(raw_tbl)
  rm(data_tbl)
  rm(pdx_hours, now_pt, now_minutes_of_day, tod_minutes, is_checkpoint_open, open_now)
  rm(PDX_data, envir = .GlobalEnv)

}

# Testing ----

# scrape_tsa_data_pdx()


# Test Loop ----
# i <- 1
#
# for (i in 1:5) {
#   p1 <- lubridate::ceiling_date(Sys.time(), unit = "minute")
#   print(glue(i, "  ", format(Sys.time())))
#   scrape_tsa_data_pdx()
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
# rm(scrape_tsa_data_pdx)
