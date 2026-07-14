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

scrape_tsa_data_dca <- function() {

  print(glue("kickoff DCA scrape ", format(Sys.time(), "%a %b %d %X %Y")))

  # API endpoint ----
  api_url <- "https://www.flyreagan.com/security-wait-times"

  # 1. Initialize the request
  req <- request(api_url)

  # 2. Build the exact browser mimic layer
  req <- req |>
    req_headers(
      `accept`           = "*/*",
      `accept-language`  = "en-US,en;q=0.9",
      `referer`          = "https://www.flyreagan.com/travel-information/security-information",
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
  res_list <- parsed_data$response$res

  # Values arrive as "< 5 mins", "12 mins", or occasionally a range like "6-9
  # mins". Extract every number present and take the largest -- conservative
  # choice so a range never understates the wait.
  parse_time <- function(x) {
    purrr::map_dbl(x, function(val) {
      if (is.na(val) || val == "") return(NA_real_)
      nums <- stringr::str_extract_all(val, "[0-9]+(\\.[0-9]+)?")[[1]]
      if (length(nums) == 0) return(NA_real_)
      max(as.numeric(nums))
    })
  }

  # Checkpoint naming must match the existing tsa_wait_times convention
  # ("Terminal 1 ( A Gates)", "Terminal 2 North ( B, C, D, E Gates)", etc.) --
  # verified 1:1 against the rendered security-information page and the DB's
  # existing DCA rows. isDisabled/pre_disabled flag a lane as unavailable
  # regardless of any stale waittime/pre string still present in the payload.
  mine <- purrr::map_dfr(res_list, function(cp) {
    checkpoint <- stringr::str_squish(paste(cp$location, cp$gates))

    gen_wait <- parse_time(cp$waittime %||% NA_character_)
    if (isTRUE(cp$isDisabled == 1)) gen_wait <- NA_real_

    pre_disabled <- isTRUE(cp$pre_disabled == 1) || is.null(cp$pre)
    pre_wait <- if (pre_disabled) NA_real_ else parse_time(cp$pre)

    tibble::tibble(
      checkpoint = checkpoint,
      wait_time = gen_wait,
      wait_time_pre_check = pre_wait,
      wait_time_clear = NA_real_
    )
  })

  # Guard: flyreagan.com does not always clear a checkpoint's displayed wait
  # time when it closes for the night -- gate against airport_checkpoint_hours
  # (time-of-day only, no DCA checkpoint's published window wraps midnight)
  # rather than relying solely on the API's isDisabled flag, same pattern as
  # the PHL Terminal A-West 1 fix.
  dca_hours <- dbGetQuery(con_write, "
    SELECT checkpoint, open_time_gen, close_time_gen
    FROM airport_checkpoint_hours
    WHERE airport = 'DCA'
  ")
  now_et <- lubridate::now(tzone = "America/New_York")
  now_minutes_of_day <- lubridate::hour(now_et) * 60 + lubridate::minute(now_et)
  tod_minutes <- function(ts) lubridate::hour(ts) * 60 + lubridate::minute(ts)

  is_checkpoint_open <- function(cp) {
    hrs <- dca_hours[dca_hours$checkpoint == cp, ]
    if (nrow(hrs) == 0 || is.na(hrs$open_time_gen[1]) || is.na(hrs$close_time_gen[1])) {
      return(TRUE)
    }
    now_minutes_of_day >= tod_minutes(hrs$open_time_gen[1]) &&
      now_minutes_of_day <= tod_minutes(hrs$close_time_gen[1])
  }

  open_now <- purrr::map_lgl(mine$checkpoint, is_checkpoint_open)
  mine$wait_time[!open_now]           <- NA_real_
  mine$wait_time_pre_check[!open_now] <- NA_real_

  # Create tibble for data insertion ----
  if (!exists("DCA_data", envir = .GlobalEnv)) {
    DCA_data <- tibble::tibble(airport = character(),
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
    DCA_data <- get("DCA_data", envir = .GlobalEnv)
  }

  # Insert airport data into tibble
  DCA_data <- mine |>
    dplyr::mutate(
      airport = "DCA",
      datetime = lubridate::now(tzone = 'America/New_York'),
      date = lubridate::today(tzone = 'America/New_York'),
      time = Sys.time() |>
        lubridate::with_tz(tzone = "America/New_York") |>
        lubridate::floor_date(unit = "minute"),
      timezone = "America/New_York",
      wait_time_priority = NA_real_
    ) |>
    dplyr::select(airport, checkpoint, datetime, date, time, timezone,
                  wait_time, wait_time_priority, wait_time_pre_check, wait_time_clear) |>
    dplyr::rows_append(x = DCA_data, y = _)

  assign("DCA_data", DCA_data, envir = .GlobalEnv)

  # Write to database ----
  dbAppendTable(con_write, name = "tsa_wait_times", value = DCA_data)

  print(glue("{nrow(DCA_data)} appended to tsa_wait_times at ", format(Sys.time(), "%a %b %d %X %Y")))


  # Cleanup ----
  rm(api_url)
  rm(status)
  rm(req)
  rm(response)
  rm(parsed_data)
  rm(res_list)
  rm(mine)
  rm(dca_hours, now_et, now_minutes_of_day, tod_minutes, is_checkpoint_open, open_now)
  rm(DCA_data, envir = .GlobalEnv)

}

# Testing ----

# scrape_tsa_data_dca()


# Test Loop ----
# i <- 1
#
# for (i in 1:5) {
#   p1 <- lubridate::ceiling_date(Sys.time(), unit = "minute")
#   print(glue(i, "  ", format(Sys.time())))
#   scrape_tsa_data_dca()
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
# rm(scrape_tsa_data_dca)
