# Package Management ----

## Create Function: Load Packages if they exist, otherwise install then load them
foo <- function(x) {
  for(i in x) {
    suppressWarnings(suppressPackageStartupMessages(
      # require returns TRUE invisibly if it was able to load package
      if(! require(i, character.only = TRUE, warn.conflicts = FALSE, quietly = TRUE)) {
        # if package was not able to be loaded then re-install
        install.packages(i, dependencies = TRUE, verbose = FALSE, quiet = TRUE)
        # load package after installing
        require(i, character.only = TRUE, verbose = FALSE, warn.conflicts = FALSE, quietly = TRUE)
      }
    ))  
  }
}

## Then install/load packages...
foo(c('polite', 'rvest', 'httr', 'RSelenium', 'jsonlite', 'duckdb', 'glue', 'DBI', 'tidyverse', 
      'netstat', 'here', 'fs', 'chromote'))


Sys.sleep(0.2)
# getwd()


rm(foo)

# Source Scripts ----

## Loading Airport Scraping functions


files <- list.files(path = "C:/Users/james/Documents/R/tsa_app/02_Scripts") |>
  stringr::str_subset("_wait_times.R")
# print(files)
print("files object works")

Sys.sleep(0.2)
funcs <- as.vector(map(here::here("C:/Users/james/Documents/R/tsa_app/02_Scripts", files), source))
# funcs <- as.vector(map(.x = glue("02_Scripts/{files}"), .f = source))
# funcs <- as.vector(source(here::here("02_Scripts/", "ATL_wait_times.R")))
print("funcs object works")

Sys.sleep(0.2)
rm(files)
rm(funcs)


functions <- as.vector(lsf.str())
# print(functions)
# Tried the following to get to work with Windows Task Scheduler, Failed
# global_env <- ls(envir = .GlobalEnv)
# if(exists(global_env, envir = .GlobalEnv)){
#   print("global_env object works")
# } else {
#   print("global_env does not exist, please debug")
# }

# Filter to only functions
# functions <- global_env[sapply(global_env,
#                         function(x) is.function(get(x, envir = .GlobalEnv)))]
# functions <- ls(pattern = "^function \\(.+$") 


# rm(global_env)


# Test Run Scripts ----

## Run all scripts on a 5 minute loop ----

## Connect to Database
# print(here::here("C:/Users/james/Documents/R/tsa_app/01_Data", "tsa_app.duckdb"))
con_write <- dbConnect(duckdb::duckdb(), dbdir = here::here("C:/Users/james/Documents/R/tsa_app/01_Data", "tsa_app.duckdb"), read_only = FALSE)
# print(con_write)
# dbListTables(con_write)


## Create Function to run all scripts
run_all_functions <- function() {
  
  print(glue("******-- Start Run ", format(Sys.time()), " --******"))
  
  
  ## Randomly assign list of functions so for mixing up timing when scraping
  ## Strategy so that the random timing makes scraping appear human
  functions <- sample(functions)
  
  
  ## Run each function
  lapply(functions, function(f) do.call(f, list()))
  
  
  print(glue("******-- Completed Run ", format(Sys.time()), " --******"))
  
}

## Run Script
run_all_functions()

# Cleanup ----

rm(functions)
rm(run_all_functions)

## Shutdown Database
dbDisconnect(con_write, shutdown = TRUE)
rm(con_write)

gc()