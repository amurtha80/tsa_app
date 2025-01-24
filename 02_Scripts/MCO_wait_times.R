# install.packages(c("DBI", "polite", "rvest", "RSelenium", "tidyverse", "duckdb", 
#  "lubridate", "magrittr", glue", "here"))

# library(polite, verbose = FALSE, warn.conflicts = FALSE)
# library(rvest, verbose = FALSE, warn.conflicts = FALSE)
# library(RSelenium, verbose = FALSE, warn.conflicts = FALSE)
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


# Script Function ----

# Function to scrape and store TSA checkpoint wait times
scrape_tsa_data_mco <- function() {
  
  print(glue("kickoff MCO scrape ", format(Sys.time(), "%a %b %d %X %Y")))
  
    # Define URL and initiate polite session
    url <- "https://flymco.com/security/"  # Update with the actual URL
    
    
    # firefox
    remote_driver <- rsDriver(browser = "firefox",
                              chromever = NULL,
                              verbose = F,
                              port = netstat::free_port(random = TRUE),
                              extraCapabilities = list("moz:firefoxOptions" = list(args = list('--headless')))
                              )
    
    
    # Access Page
    brow <- remote_driver[["client"]]
    # brow$open()
    brow$navigate(url)
    Sys.sleep(3.1)
    
    # Scrape Page
    h <- brow$getPageSource()
    h <- read_html(h[[1]])


    # # Click Accept All Cookie Button
    # if(length(brow$findElements(using = 'id', "CybotCookiebotDialogBodyLevelButtonLevelOptinAllowAll")) != 0) {
    #   button <- brow$findElement(using = 'id', "CybotCookiebotDialogBodyLevelButtonLevelOptinAllowAll")
    #   if(button$isElementDisplayed()[[1]]) {
    #     button$clickElement()
    #   }
    # } 
    
    # Click Accept All Cookie Button - revised
    doesCookieButton_Exist <- isTRUE(length(brow$findElements(using = 'id', "CybotCookiebotDialogBodyLevelButtonLevelOptinAllowAll")) != 0)
    if(doesCookieButton_Exist) {
      button <- brow$findElement(using = 'id', "CybotCookiebotDialogBodyLevelButtonLevelOptinAllowAll")
      if(button$isElementDisplayed()[[1]]) {
        button$clickElement()
      }
    }


    gates <- h |> 
      # h5.css-1osfado-headings-H5-WidgetContainer-WidgetTitle-SecurityWaitTimesCard-SWTCardTitle.e1v0x5ca2
      html_elements("h5.css-1osfado-headings-H5-WidgetContainer-WidgetTitle-SecurityWaitTimesCard-SWTCardTitle.e1v0x5ca2") |>
      html_text2() |> 
        magrittr::extract(c(1:3))


    wait_time <- h |> 
      html_elements('p.css-1jbuqz4-SecurityWaitTimeInfo-TimeRange.ebqyvgq1') |> 
      html_text2() |> 
      word(start = 3, end = 3) |> 
      as.numeric()


    wait_time_pre_check <- rep(NA, length(wait_time))

    # Comment Out Checks from Testing
    # print(glue("wait time length ", {length(wait_time)}))
    # print(glue("gates length ", {length(gates)}))

    # Comment Out Checks from Testing
    # Check to make Sure that TSA CheckPoint and Time have the same length
    # if(length(wait_time) != length(gates)){
    #   stop("The length of wait_time and gates do not match.")
    # }


    # Create tibble for data insertion
    if(!exists("MCO_data", envir = .GlobalEnv)) {
      MCO_data <- tibble(airport = character(),
                         checkpoint = character(),
                         datetime = lubridate::ymd_hms(tz = 'EST'),
                         date = lubridate::ymd(),
                         time = lubridate::POSIXct(tz = 'EST'),
                         timezone = character(),
                         wait_time = numeric(),
                         wait_time_priority = numeric(),
                         wait_time_pre_check = numeric(),
                         wait_time_clear = numeric())
    } else {
      MCO_data <- get("MCO_data", envir = .GlobalEnv)
    }


    # Insert data into tibble
    # Prepare data with airport code, date, time, timezone, and wait times
    MCO_data <- rows_append(MCO_data, tibble(
      airport = "MCO",
      checkpoint = gates,
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
      wait_time = wait_time,  # Assume this is a list of wait times for each checkpoint
      wait_time_priority = NA,
      wait_time_pre_check = wait_time_pre_check,
      wait_time_clear = NA
    ))
    
    assign("MCO_data", MCO_data, envir = .GlobalEnv)  
    
    dbAppendTable(con_write, name = "tsa_wait_times", value = MCO_data)
    
    # print(glue("session has run successfully ", format(Sys.time(), "%a %b %d %X %Y")))
    print(glue("{nrow(MCO_data)} row(s) of data have been added to tsa_wait_times"))
    
    rm(wait_time_pre_check)
    rm(url)
    rm(h)
    rm(gates)
    rm(wait_time)
    rm(MCO_data, envir = .GlobalEnv)
    rm(button)
    rm(doesCookieButton_Exist)
    
    brow$close()
    rm(brow)
    
    remote_driver$server$stop()
    rm(remote_driver)
}



# Test Loop ----
# i <- 1
# 
# for (i in 1:5) {
#   p1 <- lubridate::ceiling_date(Sys.time(), unit = "minute")
#   print(glue(i, "  ", format(Sys.time())))
#   scrape_tsa_data_mco()
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
# rm(scrape_tsa_data_mco)
