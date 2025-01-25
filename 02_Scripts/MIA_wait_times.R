# install.packages(c("DBI", "polite", "RSelenium", "netstat", "rvest", "tidyverse", "duckdb", 
#  "lubridate", "magrittr", glue", "here"))
# 
# library(polite, verbose = FALSE, warn.conflicts = FALSE)
# library(rvest, verbose = FALSE, warn.conflicts = FALSE)
# library(RSelenium, verbose = FALSE, warn.conflicts = FALSE)
# library(netstat, verbose = FALSE, warn.conflicts = FALSE)
# library(duckdb, verbose = FALSE, warn.conflicts = FALSE)
# library(glue, verbose = FALSE, warn.conflicts = FALSE)
# library(DBI, verbose = FALSE, warn.conflicts = FALSE)
# library(tidyverse, verbose = FALSE, warn.conflicts = FALSE)
# library(here, verbose = FALSE, warn.conflicts = FALSE)
# 
# here::here()


# Database Connection ----

# con_write <- dbConnect(duckdb::duckdb(), dbdir = "01_Data/tsa_app.duckdb", read_only = FALSE)


# Script Function ----


scrape_tsa_data_mia <- function() {
  
  print(glue("kickoff MIA scrape ", format(Sys.time(), "%a %b %d %X %Y")))
  
  # Define URL and initiate polite session
  url <- "https://www.miami-airport.com/tsa-waittimes.asp"  # Update with the actual URL
  
  # firefox
  remote_driver <- rsDriver(browser = "firefox",
                            chromever = NULL,
                            verbose = F,
                            port = netstat::free_port(random = TRUE)
                            ,extraCapabilities = list("moz:firefoxOptions" = list(args = list('--headless'))))
  
  
  # Access Page
  brow <- remote_driver[["client"]]
  # brow$open()
  brow$navigate(url)
  
  # Allow time for page to load
  Sys.sleep(1.5)
  
  # Scrape Page
  h <- brow$getPageSource()
  h <- read_html(h[[1]])
  

  #Scrape Table Headers  
  headers <- h |> 
    html_elements("span.ag-header-cell-text") |> 
    html_text2()
  
  temp <- last(headers)
  headers <- c(temp, headers) |> 
    head(-1)
  
  
  #Scrape Checkpoint Data
  checkpoint_data <- h |> 
    html_elements(".ag-center-cols-container") |> 
    html_text2() |>
    tibble() |> 
    separate_longer_delim(cols = `html_text2(html_elements(h, ".ag-center-cols-container"))`,
                          delim = '\n') |> 
    rename('data' = `html_text2(html_elements(h, ".ag-center-cols-container"))`) |> 
    deframe()

  headers <- rep(headers, len = length(checkpoint_data))
  mia_tbl <- tibble(headers, checkpoint_data)
  row <- rep(1:(nrow(mia_tbl) / 5), each = 5)
  
  MIA_transform <- mia_tbl |> 
    cbind(row) |> 
    pivot_wider(names_from = headers, values_from = checkpoint_data) |>  
    select(-row) |> 
    mutate(General = case_when(str_detect(General, pattern = " / ") ~ str_remove_all(str_split_i(General, pattern = "/", 2), "\\D"), 
                                (General == "Closed" ~ "NA"),
                                (General == "N/A" ~ "NA"),
                                TRUE ~ General), 
           Priority = case_when(str_detect(Priority, pattern = " / ") ~ str_remove_all(str_split_i(Priority, pattern = "/", 2), "\\D"),
                                (Priority == "Closed" ~ "NA"),
                                (Priority == "N/A" ~ "NA"),
                                TRUE ~ Priority),
           `TSA-Pre` = case_when(str_detect(`TSA-Pre`, pattern = " / ") ~ str_remove_all(str_split_i(`TSA-Pre`, pattern = "/", 2), "\\D"), 
                                (`TSA-Pre` == "Closed" ~ "NA"),
                                (`TSA-Pre` == "N/A" ~ "NA"),
                                TRUE ~ `TSA-Pre`),
           Clear = case_when(str_detect(Clear, pattern = " / ") ~ str_remove_all(str_split_i(Clear, pattern = "/", 2), "\\D"),
                                (Clear == "Closed" ~ "NA"),
                                (Clear == "N/A" ~ "NA"),
                                TRUE ~ Clear)
           ) |> 
    mutate(across(c(General:Clear), as.numeric)) |> suppressWarnings()
  
  
  # Create tibble for data insertion
  if(!exists("MIA_data", envir = .GlobalEnv)) {
    MIA_data <- tibble(airport = character(),
                       checkpoint = character(),
                       datetime = lubridate::ymd_hms(tz = 'EST'),
                       date = lubridate::ymd(),
                       time = lubridate::POSIXct(tz = 'EST'),
                       timezone = character(),
                       wait_time = numeric(),
                       wait_time_priority = numeric(),
                       wait_time_pre_check = numeric(),
                       wait_time_clear = numeric()
                       )
  } else {
    MIA_data <- get("MIA_data", envir = .GlobalEnv)
  }
  
  
  # Insert data into tibble
  # Prepare data with airport code, date, time, timezone, and wait times
  MIA_data <- rows_append(MIA_data, tibble(
    airport = "MIA",
    checkpoint = MIA_transform$Checkpoint,
    datetime = lubridate::now(tzone = 'EST'),
    date = lubridate::today(),
    time = Sys.time() |> 
      with_tz(tzone = "America/New_York") |> 
      floor_date(unit = "minute"),
    # time = lubridate::now(tzone = 'EST') |>
    # floor_date(unit = "minute") |>
    # with_tz('EST'),
    # format("%H:%M:%S"),
    # hms::new_hms(),
    timezone = "America/New_York",
    wait_time = MIA_transform$General,  # Assume this is a list of wait times for each checkpoint
    wait_time_priority = MIA_transform$Priority,
    wait_time_pre_check = MIA_transform$`TSA-Pre`,
    wait_time_clear = MIA_transform$Clear
  ))

  
  assign("MIA_data", MIA_data, envir = .GlobalEnv)  
  
  dbAppendTable(con_write, name = "tsa_wait_times", value = MIA_data)
  
  # print(glue("session has run successfully ", format(Sys.time(), "%a %b %d %X %Y")))
  print(glue("{nrow(MIA_data)} row(s) of data have been added to tsa_wait_times"))
  
  rm(url)
  rm(h)
  rm(headers)
  rm(temp)
  rm(row)
  rm(checkpoint_data)
  rm(mia_tbl)
  rm(MIA_transform)
  rm(MIA_data, envir = .GlobalEnv)
  
  brow$close()
  rm(brow)
  
  remote_driver$server$stop()
  rm(remote_driver)
  # gc() 
}  


# Test Loop ----
# i <- 1
# 
# for (i in 1:10) {
#   p1 <- lubridate::ceiling_date(Sys.time(), unit = "minute")
# 
#   print(glue(i, "  ", format(Sys.time())))
# 
#   scrape_tsa_data_mia()
# 
#   theDelay <- as.numeric(difftime(p1,Sys.time(),unit="secs"))
# 
#   i <- i + 1
# 
#   if(i == 6) {
#     break()
#   } else {
#     Sys.sleep(max(0, theDelay))
#   }
# 
# }


# Cleanup ----
# rm(i)
# rm(p1)
# rm(theDelay)
# dbDisconnect(con)
# rm(con)
# rm(scrape_tsa_data_mia)
  
