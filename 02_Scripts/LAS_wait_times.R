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

scrape_tsa_data_las <- function() {

  print(glue("kickoff LAS scrape ", format(Sys.time(), "%a %b %d %X %Y")))

  # Checkpoint -> journey ID mapping ----
  # Source: Zensors waitTimeExplorer.init response (authoritative, confirmed
  # live 2026-07-22 via direct httr2 call -- see 02_Scripts/LAS_scraper_PLAN.md).
  # All 4 names are already unique -- no naming-collision prefix needed
  # (unlike BOS's two "All E Gates" checkpoints).
  las_journeys <- tibble::tribble(
    ~checkpoint,           ~journey,
    "T1 - A/B Gates",      "t2K25H6KA",
    "T1 - C Gates",        "tN8G8AV9D",
    "T1 - C/D Gates",      "tGMD2ET8Y",
    "T3 - D/E Gates",      "t0CSXP4SK"
  )

  zensors_slug <- "t1LQGTAPA"
  zensors_domain_slug <- "LAS"
  zensors_token <- "3Ll9yq2riLZctX1CZ94FRgLcScJimgXx"

  # Fetch one checkpoint ----
  # No CLEAR lane exists for LAS (confirmed via the API response -- no `clear`
  # key anywhere, same as BOS). All 4 checkpoints have both `standard` and
  # `precheck` paths, but parse defensively anyway (check key existence)
  # rather than assuming, matching the BOS/SEA/PDX/MIA convention. `open`
  # gates the wait_time to NA when the checkpoint/lane isn't currently open.
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

  mine <- purrr::map2_dfr(las_journeys$checkpoint, las_journeys$journey, get_checkpoint_data)

  # Create tibble for data insertion ----
  if (!exists("LAS_data", envir = .GlobalEnv)) {
    LAS_data <- tibble::tibble(airport = character(),
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
    LAS_data <- get("LAS_data", envir = .GlobalEnv)
  }

  LAS_data <- mine |>
    dplyr::mutate(
      airport = "LAS",
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
    dplyr::rows_append(x = LAS_data, y = _)

  assign("LAS_data", LAS_data, envir = .GlobalEnv)

  # Write to database ----

  dbAppendTable(con_write, name = "tsa_wait_times", value = LAS_data)

  print(glue("{nrow(LAS_data)} appended to tsa_wait_times at ", format(Sys.time(), "%a %b %d %X %Y")))


  # Cleanup ----
  rm(las_journeys)
  rm(zensors_slug)
  rm(zensors_domain_slug)
  rm(zensors_token)
  rm(get_checkpoint_data)
  rm(mine)
  rm(LAS_data, envir = .GlobalEnv)

}

# Testing ----

# scrape_tsa_data_las()


# Test Loop ----
# i <- 1
#
# for (i in 1:5) {
#   p1 <- lubridate::ceiling_date(Sys.time(), unit = "minute")
#   print(glue(i, "  ", format(Sys.time())))
#   scrape_tsa_data_las()
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
# rm(scrape_tsa_data_las)
