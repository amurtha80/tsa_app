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

scrape_tsa_data_bos <- function() {

  print(glue("kickoff BOS scrape ", format(Sys.time(), "%a %b %d %X %Y")))

  # Checkpoint -> journey ID mapping ----
  # Source: Zensors waitTimeExplorer.init response (authoritative, confirmed
  # live 2026-07-20 -- see 02_Scripts/BOS_scraper_PLAN.md). Checkpoints 6 and 7
  # are the only pair that collide on name ("All E Gates" with no other
  # distinguishing text anywhere on massport's site) -- only those two keep
  # the "Checkpoint N: " prefix; the other 5 already have unique names.
  bos_journeys <- tibble::tribble(
    ~checkpoint,                    ~journey,
    "A Gates",                      "t6CQ1P0Y3",
    "A Gates PreCheck Only",        "tKK3PDVP9",
    "Gates B1 - B22",               "tXT4B8KMX",
    "Gates B23 - 40",               "tF1JP9828",
    "Terminal C",                   "tSGV88H0D",
    "Checkpoint 6: All E Gates",    "tWEBCSW2Q",
    "Checkpoint 7: All E Gates",    "tCLRGFHM9"
  )

  zensors_slug <- "tSTQVPRW1"
  zensors_domain_slug <- "BOS"
  zensors_token <- "9uBjlxUu2dTQydGHYGtoDYxH5TE0vHOl"

  # Fetch one checkpoint ----
  # No CLEAR lane exists for BOS (confirmed both in the API response and in
  # massport's own copy: CLEAR wait times are "currently unavailable"). Each
  # of `precheck`/`standard` is an optional key -- Checkpoint 2 is
  # PreCheck-only and Checkpoint 6 is Standard-only, so parse defensively
  # rather than assuming both lanes exist. `open` gates the wait_time to NA
  # when the checkpoint/lane isn't currently open, same convention as
  # SEA/PDX/MIA's IsOpen/isOpen flags.
  get_checkpoint_data <- function(checkpoint, journey) {
    input <- list(`0` = list(journey = journey, slug = zensors_slug,
                              domainSlug = zensors_domain_slug, token = zensors_token))
    input_json <- jsonlite::toJSON(input, auto_unbox = TRUE)

    req <- request("https://embed.zensors.live/api/embeddable-widget/trpc/waitTimeExplorer.update") |>
      req_url_query(batch = 1, input = as.character(input_json))

    resp <- req_perform(req) |> resp_body_json()
    paths <- resp[[1]]$result$data$paths

    lane_wait <- function(lane) {
      if (is.null(paths[[lane]])) return(NA_real_)
      if (!isTRUE(paths[[lane]]$open)) return(NA_real_)
      as.numeric(paths[[lane]]$waitTime$value)
    }

    tibble::tibble(
      checkpoint = checkpoint,
      wait_time = lane_wait("standard"),
      wait_time_pre_check = lane_wait("precheck")
    )
  }

  # Parse checkpoints ----

  mine <- purrr::map2_dfr(bos_journeys$checkpoint, bos_journeys$journey, get_checkpoint_data)

  # Create tibble for data insertion ----
  if (!exists("BOS_data", envir = .GlobalEnv)) {
    BOS_data <- tibble::tibble(airport = character(),
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
    BOS_data <- get("BOS_data", envir = .GlobalEnv)
  }

  BOS_data <- mine |>
    dplyr::mutate(
      airport = "BOS",
      datetime = lubridate::now(tzone = 'America/New_York'),
      date = lubridate::today(tzone = 'America/New_York'),
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
    dplyr::rows_append(x = BOS_data, y = _)

  assign("BOS_data", BOS_data, envir = .GlobalEnv)

  # Write to database ----

  dbAppendTable(con_write, name = "tsa_wait_times", value = BOS_data)

  print(glue("{nrow(BOS_data)} appended to tsa_wait_times at ", format(Sys.time(), "%a %b %d %X %Y")))


  # Cleanup ----
  rm(bos_journeys)
  rm(zensors_slug)
  rm(zensors_domain_slug)
  rm(zensors_token)
  rm(get_checkpoint_data)
  rm(mine)
  rm(BOS_data, envir = .GlobalEnv)

}

# Testing ----

# scrape_tsa_data_bos()


# Test Loop ----
# i <- 1
#
# for (i in 1:5) {
#   p1 <- lubridate::ceiling_date(Sys.time(), unit = "minute")
#   print(glue(i, "  ", format(Sys.time())))
#   scrape_tsa_data_bos()
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
# rm(scrape_tsa_data_bos)
