# install.packages(c("DBI", "polite", "RSelenium", "netstat", "rvest", "tidyverse", "duckdb", 
#  "lubridate", "magrittr", glue", "here"))

library(polite, verbose = FALSE, warn.conflicts = FALSE)
library(rvest, verbose = FALSE, warn.conflicts = FALSE)
library(RSelenium, verbose = FALSE, warn.conflicts = FALSE)
library(netstat, verbose = FALSE, warn.conflicts = FALSE)
library(duckdb, verbose = FALSE, warn.conflicts = FALSE)
library(glue, verbose = FALSE, warn.conflicts = FALSE)
library(DBI, verbose = FALSE, warn.conflicts = FALSE)
library(tidyverse, verbose = FALSE, warn.conflicts = FALSE)
library(here, verbose = FALSE, warn.conflicts = FALSE)

here::here()


# Database Connection ----

con <- dbConnect(duckdb::duckdb(), dbdir = "02_Data/tsa_app.duckdb", read_only = FALSE)


# Script Function ----


scrape_tsa_data_clt <- function() {
  # Define URL and initiate polite session
  url <- "https://www.miami-airport.com/tsa-waittimes.asp"  # Update with the actual URL
  
  # firefox
  remote_driver <- rsDriver(browser = "firefox",
                            chromever = NULL,
                            verbose = F,
                            port = free_port(),
                            extraCapabilities = list("moz:firefoxOptions" = list(args = list('--headless'))))
  
  
  # Access Page
  brow <- remote_driver[["client"]]
  # brow$open()
  brow$navigate(url)
  
  
  # Scrape Page
  h <- brow$getPageSource()
  h <- read_html(h[[1]])
  

  #Scrape Table Headers  
  headers <- h |> 
    html_elements(".ag-header-cell-text") |> 
    html_text2()
  
  temp <- headers[[5]]
  headers <- c(temp, headers) |> 
    head(-1)
  
  rm(temp)
  
  
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
  
  MIA_data <- mia_tbl |> 
    mutate(row = rep(1:(nrow(mia_tbl) / 5), each = 5)) |> 
    pivot_wider(names_from = headers, values_from = checkpoint_data) |>  
    select(-row) |> 
    mutate(General = case_when(str_detect(General, pattern = " / ") ~ str_remove_all(str_split_i(General, pattern = "/", 2), "\\D"), 
                                (General == "Closed" ~ "N/A"),
                                TRUE ~ General), 
           Priority = case_when(str_detect(Priority, pattern = " / ") ~ str_remove_all(str_split_i(Priority, pattern = "/", 2), "\\D"),
                                (Priority == "Closed" ~ "N/A"),
                                TRUE ~ Priority),
           `TSA-Pre` = case_when(str_detect(`TSA-Pre`, pattern = " / ") ~ str_remove_all(str_split_i(`TSA-Pre`, pattern = "/", 2), "\\D"), 
                                (`TSA-Pre` == "Closed" ~ "N/A"),
                                TRUE ~ `TSA-Pre`),
           Clear = case_when(str_detect(Clear, pattern = " / ") ~ str_remove_all(str_split_i(Clear, pattern = "/", 2), "\\D"),
                                (Clear == "Closed" ~ "N/A"),
                                TRUE ~ Clear)
           )
  
  
}  
