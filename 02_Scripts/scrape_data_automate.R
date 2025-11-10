sink("C:/Users/james/Documents/R/tsa_app/runlog.txt", append = TRUE, type = "output")

# Package Management ----

## Create Function: Load Packages if they exist, otherwise install then load them
foo <- function(x) {
  for(i in x) {
    suppressWarnings(suppressPackageStartupMessages(
    # require returns TRUE invisibly if it was able to load package
    if(! require(i, character.only = TRUE, warn.conflicts = FALSE, quietly = TRUE)) {
      # if package was not able to be loaded then re-install
      install.packages(i, dependencies = TRUE, verbose = FALSE, quiet = TRUE,
                       repos = "https://cloud.r-project.org/")
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


rm(foo)

# Source Scripts ----

## Loading Airport Scraping functions
 


files <- list.files(path = "C:/Users/james/Documents/R/tsa_app/02_Scripts") |>
  stringr::str_subset("_wait_times.R")
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


####  --------------------------------------------------------------------- ####


# Helper function to safely read html page
safe_read_html_live <- function(url, wait = 2, exit_on_fail = TRUE) {
  # Try first attempt
  page <- tryCatch(
    read_html_live(url),
    error = function(e) {
      message("First attempt failed: ", e$message)
      return(NULL)
    }
  )
  
  # Retry once if first failed
  if (is.null(page)) {
    message("Retrying once more after ", wait, " seconds...")
    Sys.sleep(wait)
    
    page <- tryCatch(
      read_html_live(url),
      error = function(e) {
        message("Second attempt failed: ", e$message)
        return(NULL)
      }
    )
  }
  
  # If both attempts failed, handle according to user preference
  if (is.null(page)) {
    message("Unable to read page after two attempts.")
    if (exit_on_fail) {
      message("Exiting script safely.")
      quit(save = "no", status = 0)
    }
  }
  
  return(page)
}


####  --------------------------------------------------------------------- ####


# Test Run Scripts ----


## Run all scripts on a 5 minute loop ----


## Connect to Database
con_write <- dbConnect(duckdb::duckdb(), dbdir = here::here("C:/Users/james/Documents/R/tsa_app/01_Data", "tsa_app.duckdb"), read_only = FALSE)


## Run Scripts ----


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


## Shutdown Database
dbDisconnect(con_write, shutdown = TRUE)
rm(con_write)


# Cleanup ----
rm(functions)
rm(run_all_functions)
rm(list = ls())


sink()
gc()


#  i <- 1
# 
# for (i in 1:288) {
#   p1 <- lubridate::ceiling_date(Sys.time(), unit = "5 minutes")
# 
#   print(glue(i, " ", format(Sys.time())))
#   
#   tryCatch(
#     expr = {
#       run_all_functions()
#     },
#     error = function(e) NULL
#   )
# 
#   gc()
# 
#   theDelay <- as.numeric(difftime(p1,Sys.time(),unit="secs"))
# 
#   i <- i + 1
# 
#   if(i == 289) {
#     break()
#   } else {
#     Sys.sleep(max(0, theDelay))
#   }
# 
# }

# rm(i)
# rm(p1)
# rm(theDelay)
# rm(functions)
# rm(run_all_functions)
# dbDisconnect(con_write, shutdown = TRUE)
# rm(list = ls())
# gc()
