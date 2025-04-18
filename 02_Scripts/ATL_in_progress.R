# install.packages(c("DBI", "polite", "rvest", "RSelenium", "tidyverse", "duckdb", 
#  "glue", "here"))

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
# library(netstat, verbose = FALSE, warn.conflicts = FALSE)

# here::here()

# Database Connection ----

# con_write <- dbConnect(duckdb::duckdb(), dbdir = "01_Data/tsa_app.duckdb", read_only = FALSE)


# Script Function ----

# Function to scrape and store TSA checkpoint wait times
scrape_tsa_data_atl <- function() {
  
  print(glue("kickoff ATL scrape ", format(Sys.time(), "%a %b %d %X %Y")))
  
  # Define URL and initiate polite session
  url <- "https://www.atl.com/times/"  # Update with the actual URL


# firefox
remote_driver <- RSelenium::rsDriver(browser = "chrome",
                          chromever = "113.0.5672.63",
                          verbose = F,
                          port = netstat::free_port(random = TRUE) #,
                          # extraCapabilities = list("moz:firefoxOptions" = list(args = list('--headless')))
                          )


# Access Page
brow <- remote_driver[["client"]]
# brow$open()
brow$navigate(url)
Sys.sleep(1.5)
h <- brow$getPageSource()
h <- rvest::read_html(h[[1]])

webElem <- brow$findElement(using = 'css',
                            value = "input")

webElem$clickElement()



# Scrape Page
page <- brow$getPageSource()
page <- read_html(h[[1]])


tsa_terminal <- page |> 
  rvest::html_elements("div h1") |> 
  rvest::html_text() |> 
  str_trim() |>  
  magrittr::extract(3:4)

tsa_checkpoint <- page |> 
  rvest::html_elements("div h2") |> 
  rvest::html_text() |> 
  str_trim()

tsa_terminal_checkpoint <- c(paste0(tsa_terminal[1]," ",tsa_checkpoint[1]), paste0(
  tsa_terminal[1]," ",tsa_checkpoint[2]), paste0(tsa_terminal[1]," ",tsa_checkpoint[3]),
  paste0(tsa_terminal[1]," ",tsa_checkpoint[4]), paste0(tsa_terminal[2]," ",tsa_checkpoint[5])
)

rm(tsa_terminal, tsa_checkpoint)

tsa_time <- page %>%
  rvest::html_elements("button span") %>%  # Replace with the actual CSS selector
  rvest::html_text() %>% 
  str_trim() %>%
  as.numeric()

# Check to make Sure that TSA CheckPoint and Time have the same length
if(length(tsa_time) != length(tsa_terminal_checkpoint)){
  stop("The length of tsa_time and tsa_terminal_checkpoint do not match.")
}

if(!exists("ATL_data", envir = .GlobalEnv)) {
  ATL_data <- tibble(airport = character(),
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
  ATL_data <- get("ATL_data", envir = .GlobalEnv)
}

# time = lubridate::now(tzone = 'EST') |> floor_date(unit = "minute")
# time

# time2 = Sys.time() |> with_tz(tzone = "America/New_York") |> floor_date(unit = "minute")
# time2

# Prepare data with airport code, date, time, timezone, and wait times
ATL_data <- rows_append(ATL_data, tibble(
  airport = "ATL",
  checkpoint = tsa_terminal_checkpoint,
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
  wait_time = tsa_time,  # Assume this is a list of wait times for each checkpoint
  wait_time_priority = NA,
  wait_time_pre_check = NA,
  wait_time_clear = NA
))

assign("ATL_data", ATL_data, envir = .GlobalEnv)  


dbAppendTable(con_write, name = "tsa_wait_times", value = ATL_data)

# print(glue("session has run successfully ", format(Sys.time(), "%a %b %d %X %Y")))
print(glue("{nrow(ATL_data)} appended to tsa_wait_times at ", format(Sys.time(), "%a %b %d %X %Y")))
rm(tsa_time)
rm(url)
rm(tsa_terminal_checkpoint)
rm(page)
rm(session)
rm(ATL_data, envir = .GlobalEnv)
}


# Loop Funtion For Test ----

# i <- 1
#   
# for (i in 1:5) {
#   p1 <- lubridate::ceiling_date(Sys.time(), unit = "minute")
#   print(glue(i, "  ", format(Sys.time())))
#   scrape_tsa_data_atl()
#   theDelay <- as.numeric(difftime(p1,Sys.time(),unit="secs"))
#   Sys.sleep(max(0, theDelay))
#   
#   i <- i + 1
# }

# Disconnect DB ----

# rm(i)
# rm(p1)
# rm(theDelay)
# dbDisconnect(con)
# rm(con)
# rm(scrape_tsa_data_atl)