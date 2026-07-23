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
scrape_tsa_data_sfo <- function() {

  print(glue("kickoff SFO scrape ", format(Sys.time(), "%a %b %d %X %Y")))

  # Page URL ----
  page_url <- "https://www.flysfo.com/passengers/flight-info/security-wait-times"

  # Static, server-rendered HTML -- no chromote needed (confirmed via a raw
  # fetch of this URL that the table is already populated server-side; no
  # API call backs it).
  wait_page <- rvest::read_html(page_url)

  # Parse checkpoints ----

  # Table has real <thead>/<th> headers (Checkpoint / General / TSA PreCheck)
  # unlike LAX, so General and PreCheck are already separate <td>s per row --
  # no long-to-wide pivot needed, just map columns directly.
  table_rows <- wait_page |>
    rvest::html_element("table.flysfo-checkpoints-table") |>
    rvest::html_elements("tbody tr")

  mine <- purrr::map_dfr(table_rows, function(r) {
    cells <- r |> rvest::html_elements("td") |> rvest::html_text2()
    tibble::tibble(
      checkpoint = stringr::str_squish(cells[1]),
      wait_time = readr::parse_number(cells[2], na = c("", "N/A", "Not Available", "Closed")),
      wait_time_pre_check = readr::parse_number(cells[3], na = c("", "N/A", "Not Available", "Closed"))
    )
  })

  # Guard: SFO currently publishes 6 checkpoints (A, B, B - Mezzanine Level,
  # D, F, G). If the table structure changes shape (missing checkpoint column
  # or no rows at all), stop rather than write malformed data.
  if (nrow(mine) == 0 || anyNA(mine$checkpoint)) {
    stop(glue("SFO scrape: no valid checkpoint rows parsed from ",
              "table.flysfo-checkpoints-table -- page markup may have changed."))
  }

  # Create tibble for data insertion ----
  if (!exists("SFO_data", envir = .GlobalEnv)) {
    SFO_data <- tibble::tibble(airport = character(),
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
    SFO_data <- get("SFO_data", envir = .GlobalEnv)
  }

  SFO_data <- mine |>
    dplyr::mutate(
      airport = "SFO",
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
    dplyr::rows_append(x = SFO_data, y = _)

  assign("SFO_data", SFO_data, envir = .GlobalEnv)

  # Write to database ----

  dbAppendTable(con_write, name = "tsa_wait_times", value = SFO_data)

  print(glue("{nrow(SFO_data)} appended to tsa_wait_times at ", format(Sys.time(), "%a %b %d %X %Y")))


  # Cleanup ----
  rm(page_url)
  rm(wait_page)
  rm(table_rows)
  rm(mine)
  rm(SFO_data, envir = .GlobalEnv)

}

# Testing ----

# scrape_tsa_data_sfo()


# Test Loop ----
# i <- 1
#
# for (i in 1:5) {
#   p1 <- lubridate::ceiling_date(Sys.time(), unit = "minute")
#   print(glue(i, "  ", format(Sys.time())))
#   scrape_tsa_data_sfo()
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
# rm(scrape_tsa_data_sfo)
