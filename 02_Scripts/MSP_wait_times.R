# install.packages(c("DBI", "polite", "rvest", "tidyverse", "duckdb", 
#  "lubridate", "magrittr", glue", "here"))

# library(polite, verbose = FALSE, warn.conflicts = FALSE)
# library(rvest, verbose = FALSE, warn.conflicts = FALSE)
# library(duckdb, verbose = FALSE, warn.conflicts = FALSE)
# library(lubridate, verbose = FALSE, warn.conflicts = FALSE)
# library(magrittr, verbose = FALSE, warn.conflicts = FALSE)
# library(glue, verbose = FALSE, warn.conflicts = FALSE)
# library(DBI, verbose = FALSE, warn.conflicts = FALSE)
# library(tidyverse, verbose = FALSE, warn.conflicts = FALSE)
# library(here, verbose = FALSE, warn.conflicts = FALSE)

# here::here()

# Database Connection ----

# con_write <- dbConnect(duckdb::duckdb(), dbdir = "01_Data/tsa_app.duckdb", read_only = FALSE)


# Function to scrape and store TSA checkpoint wait times
scrape_tsa_data_msp <- function() {
  
  print(glue("kickoff MSP scrape ", format(Sys.time(), "%a %b %d %X %Y")))
  
  
  # Define URL and initiate polite session
  url <- "https://www.mspairport.com/airport/security-screening/security-wait-times"  # Update with the actual URL
  session <- polite::bow(url)
  
  
  # Scrape and parse data
  # page <- polite::scrape(session)
  page <- read_html(url)

  
  checkpoints <- page |>
    rvest::html_elements("div.security-wait-time__checkpoint-name") |>
    rvest::html_text() |>
    stringr::str_squish()

  
  chkpnt_type <- page |> 
    rvest::html_elements("div.security-wait-time__message") |> 
    rvest::html_text() |> 
    stringr::str_trim()

  
  wait_time <- page |> 
    rvest::html_elements("div.security-wait-time__time") |> 
    rvest::html_text() |> 
    stringr::str_extract(pattern = "(\\d)+") |> 
    as.numeric()


  mine <- tibble::tibble(
    checkpoints = checkpoints,
    chkpnt_type = chkpnt_type,
    wait_time = wait_time
  )


  # Check to make Sure that TSA CheckPoint and Time have the same length
  if((length(checkpoints) != length(wait_time)) | (length(checkpoints) != length(chkpnt_type))){
    stop("The length of tsa_time and tsa_terminal_checkpoint do not match.")
  }

  # Guard: T2 Checkpoint 1 and T2 Checkpoint 2 don't clear their wait time
  # before opening at 4:00am -- the prior day's last reading is left on the
  # page (settling around 5 min, the site's minimum display tier) until the
  # checkpoint actually opens. Scoped to just these two checkpoints, matching
  # the pattern already used at DCA/IAH/MIA/PHL.
  stale_gate_hours <- dbGetQuery(con_write, "
    SELECT checkpoint, open_time_gen, close_time_gen
    FROM airport_checkpoint_hours
    WHERE airport = 'MSP' AND checkpoint IN ('T2 Checkpoint 1', 'T2 Checkpoint 2')
  ")
  now_ct <- lubridate::now(tzone = "America/Chicago")
  now_minutes_of_day <- lubridate::hour(now_ct) * 60 + lubridate::minute(now_ct)
  tod_minutes <- function(ts) lubridate::hour(ts) * 60 + lubridate::minute(ts)
  is_checkpoint_open <- function(cp) {
    hrs <- stale_gate_hours[stale_gate_hours$checkpoint == cp, ]
    if (nrow(hrs) == 0 || is.na(hrs$open_time_gen[1]) || is.na(hrs$close_time_gen[1])) {
      return(TRUE)
    }
    open_min  <- tod_minutes(hrs$open_time_gen[1])
    close_min <- tod_minutes(hrs$close_time_gen[1])
    if (close_min < open_min) {
      now_minutes_of_day >= open_min || now_minutes_of_day <= close_min
    } else {
      now_minutes_of_day >= open_min && now_minutes_of_day <= close_min
    }
  }
  for (cp in c("T2 Checkpoint 1", "T2 Checkpoint 2")) {
    if (!is_checkpoint_open(cp)) {
      mine$wait_time[mine$checkpoints == cp] <- NA_real_
    }
  }


if(!exists("MSP_data", envir = .GlobalEnv)) {
  MSP_data <- tibble(airport = character(),
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
  MSP_data <- get("MSP_data", envir = .GlobalEnv)
}


  # Prepare data with airport code, date, time, timezone, and wait times
  MSP_data <- rows_append(MSP_data, tibble(
    airport = "MSP",
    checkpoint = mine$checkpoints,
    datetime = lubridate::now(tzone = 'America/Chicago'),
    date = lubridate::today(),
    time = Sys.time() |> 
      with_tz(tzone = "America/Chicago") |> 
      floor_date(unit = "minute"),
    timezone = "America/Chicago",
    wait_time = case_when(mine$chkpnt_type == "all passengers" ~ mine$wait_time,
                          TRUE ~ NA_integer_),  # Assume this is a list of wait times for each checkpoint
    wait_time_priority = NA,
    wait_time_pre_check = case_when(mine$chkpnt_type == "PreCheck OPEN Only" ~ mine$wait_time,
                                    (mine$checkpoints == "T2 Checkpoint 1" & mine$chkpnt_type == "all passengers") ~ NA_integer_,
                                     mine$chkpnt_type == "all passengers" ~ mine$wait_time,
                                    TRUE ~ NA_integer_),
    wait_time_clear = NA
    )
  )


  assign("MSP_data", MSP_data, envir = .GlobalEnv)  
  

  dbAppendTable(con_write, name = "tsa_wait_times", value = MSP_data)
  

  # print(glue("session has run successfully ", format(Sys.time(), "%a %b %d %X %Y")))
  print(glue("{nrow(MSP_data)} appended to tsa_wait_times at ", format(Sys.time(), "%a %b %d %X %Y")))
  
  rm(url)
  rm(checkpoints)
  rm(chkpnt_type)
  rm(wait_time)
  rm(mine)
  rm(page)
  rm(session)
  rm(stale_gate_hours, now_ct, now_minutes_of_day, tod_minutes, is_checkpoint_open, cp)
  rm(MSP_data, envir = .GlobalEnv)

  
}


# Loop Funtion For Test ----

# i <- 1
#   
# for (i in 1:5) {
#   p1 <- lubridate::ceiling_date(Sys.time(), unit = "minute")
#   print(glue(i, "  ", format(Sys.time())))
#   scrape_tsa_data_msp()
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
# rm(scrape_tsa_data_msp)