# install.packages(c("DBI", "polite", "rvest", "tidyverse", "duckdb", 
#  "lubridate", "magrittr", glue", "here", "chromote"))

# library(polite, verbose = FALSE, warn.conflicts = FALSE)
# library(rvest, verbose = FALSE, warn.conflicts = FALSE)
# library(duckdb, verbose = FALSE, warn.conflicts = FALSE)
# library(lubridate, verbose = FALSE, warn.conflicts = FALSE)
# library(magrittr, verbose = FALSE, warn.conflicts = FALSE)
# library(glue, verbose = FALSE, warn.conflicts = FALSE)
# library(DBI, verbose = FALSE, warn.conflicts = FALSE)
# library(tidyverse, verbose = FALSE, warn.conflicts = FALSE)
# library(here, verbose = FALSE, warn.conflicts = FALSE)
# library(chromote, verbose = FALSE, warn.conflicts = FALSE)

# here::here()

# Database Connection ----

# con_write <- dbConnect(duckdb::duckdb(), dbdir = "01_Data/tsa_app.duckdb", read_only = FALSE)


# Function to scrape and store TSA checkpoint wait times
scrape_tsa_data_iah <- function() {
  
  print(glue("kickoff IAH scrape ", format(Sys.time(), "%a %b %d %X %Y")))
  
  # Define URL and initiate polite session
  url <- "https://www.fly2houston.com/iah/security/"  # Update with the actual URL

  options(chromote.headless = "new")
  # Use headless shell binary to avoid persistent Chrome temp profile accumulation
  # (Chrome v132+ default headless mode writes HeadlessChrome* dirs to %TEMP%)
  chromote::local_chrome_version(version = "latest-stable", binary = "chrome-headless-shell")
  
  
  # Access JavaScript-rendered page
  # All 9 checkpoint cards (Standard, PreCheck, Premier) load simultaneously —
  # no tab-click navigation needed. The page renders one flat list.
  page <- safe_read_html_live(url)
  Sys.sleep(1.5)  # Ensure page fully loads before scraping

  
  # Scrape checkpoint names and wait times ----
  
  # Returns all 9 cards: names encode lane type
  # e.g. "IAH Terminal A North Standard", "IAH Terminal A North PreCheck",
  #      "IAH Terminal C North Premier"
  checkpoints_raw <- page |>
    rvest::html_elements(".css-b1azl9-InfoCard-styles-InfoCardTitle.e1x13lbf4") |>
    rvest::html_text()
  
  times_raw <- page |>
    rvest::html_elements(".css-hegrzh-InfoCard-styles-InfoCardRemark.e1x13lbf8") |>
    rvest::html_text() |>
    word(1) |>
    readr::parse_number(na = c("Closed", "N/A", "NA"))
  
  
  # Validate lengths match before proceeding
  if (length(checkpoints_raw) != length(times_raw)) {
    stop(glue(
      "IAH scrape length mismatch: {length(checkpoints_raw)} checkpoints vs ",
      "{length(times_raw)} times. Page may not have fully loaded."
    ))
  }


  # Transform: derive lane type from checkpoint name, pivot to one row per
  # physical checkpoint location with separate wait time columns ----
  
  # Lane type is the last word of the checkpoint name
  raw_tbl <- tibble(
    checkpoint_full = checkpoints_raw,
    time_raw        = times_raw
  ) |>
    mutate(
      lane_type  = word(checkpoint_full, -1),              # "Standard", "PreCheck", "Premier"
      checkpoint = str_remove(checkpoint_full, " (Standard|PreCheck|Premier)$")
    )
  
  # Pivot wide: one row per physical checkpoint, separate columns per lane type
  # Standard  -> wait_time           (general lane)
  # PreCheck  -> wait_time_pre_check (TSA PreCheck lane)
  # Premier   -> wait_time_priority  (United priority lane)
  data_tbl <- raw_tbl |>
    select(checkpoint, lane_type, time_raw) |>
    pivot_wider(
      names_from  = lane_type,
      values_from = time_raw
    )
  
  # Ensure all three lane columns exist even if a type is absent on a given run
  # (e.g. Premier lane closed and card not rendered on the page)
  if (!"Standard" %in% names(data_tbl)) data_tbl$Standard <- NA_real_
  if (!"PreCheck" %in% names(data_tbl)) data_tbl$PreCheck <- NA_real_
  if (!"Premier"  %in% names(data_tbl)) data_tbl$Premier  <- NA_real_

  # Guard: fly2houston.com does not clear the Standard-lane wait time for
  # Terminal A South when it closes overnight (midnight - 3:30am) -- the last
  # real reading (settling around 3 min) is left on the page indefinitely.
  # Scoped to A South only (not applied airport-wide): IAH's other checkpoints
  # are separately flagged as possibly having too-conservative researched hours,
  # so gating them here would risk suppressing real overnight data instead of
  # stale data. Same pattern as the DCA/PHL A-West 1 fixes.
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

  
  # Initialize or retrieve data tibble from global environment ----
    if(!exists("IAH_data", envir = .GlobalEnv)) {
    IAH_data <- tibble(airport = character(),
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

  
  # Append new rows to IAH_data tibble
  IAH_data <- rows_append(IAH_data, tibble(
    airport = "IAH",
    checkpoint = data_tbl$checkpoint,
    datetime = lubridate::now(tzone = 'America/Chicago'),
    date = lubridate::today(),
    time = Sys.time() |> 
      with_tz(tzone = "America/Chicago") |> 
      floor_date(unit = "minute"),
    timezone = "America/Chicago",
    wait_time = data_tbl$Standard,
    wait_time_priority = data_tbl$Premier,
    wait_time_pre_check = data_tbl$PreCheck,
    wait_time_clear = NA_real_
    )
  ) 
  
  # Write to database ----
  
  assign("IAH_data", IAH_data, envir = .GlobalEnv)  
  
  dbAppendTable(con_write, name = "tsa_wait_times", value = IAH_data)
  
  print(glue("{nrow(IAH_data)} appended to tsa_wait_times at ", format(Sys.time(), "%a %b %d %X %Y")))
  
  # Cleanup ----
  
  rm(checkpoints_raw)
  rm(times_raw)
  rm(raw_tbl)
  rm(data_tbl)
  rm(a_south_hours, now_ct, now_minutes_of_day, tod_minutes, a_south_open)
  rm(IAH_data, envir = .GlobalEnv)
  
  # June 2026 - New Tear-down Methodology to avoid Headless Chrome Temp files
  # in Windows environment. This is due to changes in chromote between 2025 and
  # 2026
  tryCatch({
    page$session$close()
    page$session$parent$close(wait = 3)
    if (chromote::has_default_chromote_object()) {
      chromote::set_default_chromote_object(NULL)
    }
  }, error = function(e) {
    message(Sys.time(), " | PDX teardown warning (non-fatal): ", e$message)
  }, finally = {
    rm(page)
    rm(url)
  })

  # gc()
  
}

# scrape_tsa_data_iah()

# Loop Funtion For Test ----

# i <- 1
#   
# for (i in 1:5) {
#   p1 <- lubridate::ceiling_date(Sys.time(), unit = "minute")
#   print(glue(i, "  ", format(Sys.time())))
#   scrape_tsa_data_iah()
#   theDelay <- as.numeric(difftime(p1,Sys.time(),unit="secs"))
#   Sys.sleep(max(0, theDelay))
#   
#   i <- i + 1
# }

# Disconnect DB ----

# rm(i)
# rm(p1)
# rm(theDelay)
# dbDisconnect(con, shutdown = T)
# rm(con)
# rm(scrape_tsa_data_iah)