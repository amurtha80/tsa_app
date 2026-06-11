# install.packages(c("DBI", "httr", "jsonlite", "tidyverse", "duckdb",
#  "lubridate", "glue", "here"))

# library(httr, verbose = FALSE, warn.conflicts = FALSE)
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

# Function to scrape and store TSA checkpoint wait times
scrape_tsa_data_den <- function() {
  
  print(glue("kickoff DEN scrape ", format(Sys.time(), "%a %b %d %X %Y")))
  
  # API endpoint ----
  api_url <- "https://app.flyfruition.com/api/public/tsa"
  ua      <- "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36"
  api_key <- "vqw8ruvwqpv02pqu938bh5p028"
  
  response <- GET(
    api_url,
    add_headers(
      `User-Agent`  = ua,
      `Referer`     = "https://www.flydenver.com/security/",
      `Origin`      = "https://www.flydenver.com",
      `x-api-key`   = api_key
    )
  )
  
  raw <- fromJSON(content(response, "text", encoding = "UTF-8"), flatten = FALSE)
  
  
  # Parse checkpoints ----
  
  # Helper: extract upper bound of range string (e.g. "9-13" -> 13)
  # Returns NA if lane is closed or value cannot be parsed
  upper_bound <- function(wait_str, closed) {
    dplyr::if_else(
      isTRUE(closed),
      NA_real_,
      readr::parse_number(
        purrr::map_chr(stringr::str_split(wait_str, "-"), dplyr::last),
        na = c("Closed", "N/A", "NA", "")
      )
    )
  }
  
  DEN_data_list <- purrr::map(seq_len(nrow(raw)), \(i) {
    
    checkpoint_name <- raw$title[[i]]
    
    # Keep only visible lanes (hide_lane == FALSE)
    lanes <- raw$lanes[[i]] |>
      dplyr::filter(!hide_lane)
    
    std_row   <- lanes |> dplyr::filter(title == "Standard")
    pre_row   <- lanes |> dplyr::filter(title == "PreCheck")
    clear_row <- lanes |> dplyr::filter(title == "CLEAR with PreCheck")
    
    tibble::tibble(
      airport              = "DEN",
      checkpoint           = checkpoint_name,
      datetime             = lubridate::now(tzone = "America/Denver"),
      date                 = lubridate::today(),
      time                 = Sys.time() |>
        with_tz(tzone = "America/Denver") |>
        floor_date(unit = "minute"),
      timezone             = "America/Denver",
      wait_time            = if (nrow(std_row)   == 0) NA_real_ else upper_bound(std_row$wait_time,   std_row$closed),
      wait_time_priority   = NA_real_,
      wait_time_pre_check  = if (nrow(pre_row)   == 0) NA_real_ else upper_bound(pre_row$wait_time,   pre_row$closed),
      wait_time_clear      = if (nrow(clear_row) == 0) NA_real_ else upper_bound(clear_row$wait_time, clear_row$closed)
    )
  })
  
  DEN_data <- dplyr::bind_rows(DEN_data_list)
  
  
  # Write to database ----
  
  assign("DEN_data", DEN_data, envir = .GlobalEnv)
  
  dbAppendTable(con_write, name = "tsa_wait_times", value = DEN_data)
  
  print(glue("{nrow(DEN_data)} appended to tsa_wait_times at ", format(Sys.time(), "%a %b %d %X %Y")))
  
  
  # Cleanup ----
  rm(api_url)
  rm(ua)
  rm(api_key)
  rm(response)
  rm(raw)
  rm(upper_bound)
  rm(DEN_data_list)
  rm(DEN_data, envir = .GlobalEnv)

  # gc()  
}


# Test Loop ----
# i <- 1
#
# for (i in 1:5) {
#   p1 <- lubridate::ceiling_date(Sys.time(), unit = "minute")
#   print(glue(i, "  ", format(Sys.time())))
#   scrape_tsa_data_den()
#   theDelay <- as.numeric(difftime(p1,Sys.time(),unit="secs"))
#   Sys.sleep(max(0, theDelay))
#
#   i <- i + 1
# }

# Cleanup ----
# rm(i)
# rm(p1)
# rm(theDelay)
# dbDisconnect(con)
# rm(con)
# rm(scrape_tsa_data_den)