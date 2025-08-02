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
  # session <- polite::bow(url)
  options(chromote.headless = "new")
  
  # Scrape and parse data
  # page <- polite::scrape(session)
  page <- read_html_live(url)
  Sys.sleep(0.3)
  
  # page$click(".css-19957wq-TagButton-StyledTagButton.e2v3h8e0")
  # Sys.sleep(0.5)
  
  
  checkpoints_std <- page |> 
    rvest::html_elements(".css-b1azl9-InfoCard-styles-InfoCardTitle.e1x13lbf4") |> 
    rvest::html_text()
    # rvest::html_table()
  
  times_std <- page |> 
    rvest::html_elements(".css-hegrzh-InfoCard-styles-InfoCardRemark.e1x13lbf8") |> 
    rvest::html_text() |> 
    word(1) |> 
    as.numeric()
  
  std_tbl <- tibble(checkpoints_std, times_std)
  
  page$click(".css-171js4o-TagButton-StyledTagButton.e2v3h8e0")
  Sys.sleep(0.3)
  
  checkpoints_pre <- page |> 
    rvest::html_elements(".css-b1azl9-InfoCard-styles-InfoCardTitle.e1x13lbf4") |> 
    rvest::html_text()
  
  times_pre <- page |> 
    rvest::html_elements(".css-hegrzh-InfoCard-styles-InfoCardRemark.e1x13lbf8") |> 
    rvest::html_text() |> 
    word(1) |> 
    as.numeric()

  pre_tbl <- tibble(checkpoints_pre, times_pre)
  
  last_updtd <- page |> 
    rvest::html_element(".css-kv0fdb-RefreshData-RefreshDataWrap.eabli8d0 div") |> 
    rvest::html_text()
  
  data_tbl <- std_tbl |> 
    left_join(pre_tbl, by = join_by(checkpoints_std == checkpoints_pre))
  

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

  
  # Prepare data with airport code, date, time, timezone, and wait times
  IAH_data <- rows_append(IAH_data, tibble(
    airport = "IAH",
    checkpoint = data_tbl$checkpoints_std,
    datetime = lubridate::now(tzone = 'America/Chicago'),
    date = lubridate::today(),
    time = Sys.time() |> 
      with_tz(tzone = "America/Chicago") |> 
      floor_date(unit = "minute"),
    timezone = "America/Chicago",
    wait_time = data_tbl$times_std,
    wait_time_priority = NA,
    wait_time_pre_check = data_tbl$times_pre,
    wait_time_clear = NA
    )
  ) 
  

  assign("IAH_data", IAH_data, envir = .GlobalEnv)  
  
  
  dbAppendTable(con_write, name = "tsa_wait_times", value = IAH_data)
  
  
  # print(glue("session has run successfully ", format(Sys.time(), "%a %b %d %X %Y")))
  print(glue("{nrow(IAH_data)} appended to tsa_wait_times at ", format(Sys.time(), "%a %b %d %X %Y")))
  rm(url)
  rm(checkpoints_std)
  rm(checkpoints_pre)
  rm(times_std)
  rm(times_pre)
  rm(last_updtd)
  rm(std_tbl)
  rm(pre_tbl)
  rm(data_tbl)
  page$session$close()
  rm(page)
  rm(session)
  rm(IAH_data, envir = .GlobalEnv)
  
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