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
scrape_tsa_data_lax <- function() {

  print(glue("kickoff LAX scrape ", format(Sys.time(), "%a %b %d %X %Y")))

  # Page URL ----
  page_url <- "https://www.flylax.com/wait-times"

  # Static, server-rendered HTML -- no chromote needed (confirmed a raw
  # fetch of this URL already contains the populated table; no API call
  # backs it).
  wait_page <- rvest::read_html(page_url)

  # Parse checkpoints ----

  # Parsed directly from <tbody> rows rather than html_table(): the table's
  # <thead> has a merged "Security Wait Times" title row above the real
  # column-header row, which throws off html_table()'s header detection.
  table_rows <- wait_page |>
    rvest::html_element("table.wait-time-table") |>
    rvest::html_elements("tbody tr")

  # Guard: LAX only publishes TBIT on this page today, but the parser
  # below doesn't assume that -- it reshapes whatever rows are present.
  mine <- purrr::map_dfr(table_rows, function(r) {
    cells <- r |> rvest::html_elements("td") |> rvest::html_text2()
    tibble::tibble(checkpoint = cells[1], boarding_type = cells[2], wait_text = cells[3])
  }) |>
    dplyr::mutate(
      lane_type = dplyr::case_when(
        boarding_type == "General Boarding" ~ "wait_time",
        boarding_type == "TSA PreCheck"      ~ "wait_time_pre_check",
        TRUE ~ NA_character_
      ),
      wait_minutes = readr::parse_number(wait_text)
    )

  # Guard: a row with a boarding type we don't recognize means LAX changed
  # or added a new boarding-type label -- stop and surface it rather than
  # let pivot_wider silently create an NA column.
  if (anyNA(mine$lane_type)) {
    bad_rows <- mine |> dplyr::filter(is.na(lane_type))
    stop(glue("LAX scrape: {nrow(bad_rows)} row(s) have no recognized lane_type ",
              "(boarding type neither 'General Boarding' nor 'TSA PreCheck'). ",
              "Checkpoint(s): {paste(unique(bad_rows$checkpoint), collapse = ', ')}. ",
              "LAX page markup may have changed -- investigate before re-running."))
  }

  mine <- mine |>
    dplyr::select(checkpoint, lane_type, wait_minutes) |>
    tidyr::pivot_wider(names_from = lane_type, values_from = wait_minutes)

  # Create tibble for data insertion ----
  if (!exists("LAX_data", envir = .GlobalEnv)) {
    LAX_data <- tibble::tibble(airport = character(),
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
    LAX_data <- get("LAX_data", envir = .GlobalEnv)
  }

  LAX_data <- mine |>
    dplyr::mutate(
      airport = "LAX",
      datetime = lubridate::now(tzone = 'America/Los_Angeles'),
      date = lubridate::today(tzone = 'America/Los_Angeles'),
      time = Sys.time() |>
        lubridate::with_tz(tzone = "America/Los_Angeles") |>
        lubridate::floor_date(unit = "minute"),
      timezone = "America/Los_Angeles",
      wait_time = round(wait_time),
      wait_time_priority = NA_real_,
      wait_time_pre_check = round(wait_time_pre_check),
      wait_time_clear = NA_real_
    ) |>
    dplyr::select(airport, checkpoint, datetime, date, time, timezone,
                  wait_time, wait_time_priority, wait_time_pre_check, wait_time_clear) |>
    dplyr::rows_append(x = LAX_data, y = _)

  assign("LAX_data", LAX_data, envir = .GlobalEnv)

  # Write to database ----

  dbAppendTable(con_write, name = "tsa_wait_times", value = LAX_data)

  print(glue("{nrow(LAX_data)} appended to tsa_wait_times at ", format(Sys.time(), "%a %b %d %X %Y")))


  # Cleanup ----
  rm(page_url)
  rm(wait_page)
  rm(table_rows)
  rm(mine)
  rm(LAX_data, envir = .GlobalEnv)

}

# Testing ----

# scrape_tsa_data_lax()


# Test Loop ----
# i <- 1
#
# for (i in 1:5) {
#   p1 <- lubridate::ceiling_date(Sys.time(), unit = "minute")
#   print(glue(i, "  ", format(Sys.time())))
#   scrape_tsa_data_lax()
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
# rm(scrape_tsa_data_lax)
