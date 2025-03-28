# Package Management ----
options(tidyverse.quiet = TRUE)

## Create Function: Load Packages if they exist, otherwise install then load them
foo <- function(x) {
  for(i in x) {
    # require returns TRUE invisibly if it was able to load package
    if(! require(i, character.only = TRUE, quietly = TRUE)) {
      # if package was not able to be loaded then re-install
      install.packages(i, dependencies = TRUE, verbose = FALSE, quiet = TRUE)
      # load package after installing
      require(i, character.only = TRUE, verbose = FALSE, quietly = TRUE)
    }
  }
}

## Then install/load packages...
foo(c('polite', 'rvest', 'httr', 'RSelenium', 'jsonlite', 'duckdb', 'glue', 'DBI', 'tidyverse', 
      'netstat', 'here', 'fs', 'chromote'))

# pak::pak('rstudio/chromote')

Sys.sleep(1)
here::here()


rm(foo)

# Source Scripts ----

## Loading Airport Scraping functions
 


files <- list.files(path = here::here("02_Scripts")) |>
  stringr::str_subset("_wait_times.R")
print("files object works")

Sys.sleep(1)
funcs <- as.vector(map(here::here("02_Scripts", files), source))
# funcs <- as.vector(map(.x = glue("02_Scripts/{files}"), .f = source))
# funcs <- as.vector(source(here::here("02_Scripts/", "ATL_wait_times.R")))
print("funcs object works")

Sys.sleep(1)
rm(files)
rm(funcs)


functions <- as.vector(lsf.str())
# Tried the following to get to work with Windows Task Scheduler, Failed
# global_env <- ls(envir = .GlobalEnv)
# print("global_env object works")

# Filter to only functions
# functions <- global_env[sapply(global_env,
#                         function(x) is.function(get(x, envir = .GlobalEnv)))]
# functions <- ls(pattern = "^function \\(.+$") 


# rm(global_env)


# Test Run Scripts ----

## Run all scripts on a 5 minute loop ----

## Connect to Database
con_write <- dbConnect(duckdb::duckdb(), dbdir = here::here("01_Data", "tsa_app.duckdb"), read_only = FALSE)

## Run Scripts ----

## Create Function to run all scripts
run_all_functions <- function() {
  
  ## Randomly assign list of functions so for mixing up timing when scraping
  ## Strategy so that the random timing makes scraping appear human
  functions <- sample(functions)
  # print(glue("There are ", length(functions), " airports to scrape"))
  
  ## Run each function
  lapply(functions, function(f) do.call(f, list()))
}


# run_all_functions()


 i <- 1

# 288 iterations = 1 Day
for (i in 1:288) {
  p1 <- lubridate::ceiling_date(Sys.time(), unit = "5 minutes")

  print(glue("******-- Run ", i, " ", format(Sys.time()), " --******"))
  
  tryCatch(
    expr = {
      run_all_functions()
    },
    error = function(e) NULL
  )

  gc()

  theDelay <- as.numeric(difftime(p1,Sys.time(),unit="secs"))

  i <- i + 1

  # 288 iterations + 1 to terminate loop = 1 Day
  if(i == 289) {
    break()
  } else {
    Sys.sleep(max(0, theDelay))
  }

}

rm(i)
rm(p1)
rm(theDelay)
rm(functions)
dbDisconnect(con_write, shutdown = TRUE)
rm(list = ls())
gc()
