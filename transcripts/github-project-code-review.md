# GitHub project code review

### User

There is the GitHub project link for your initial review in the word doc I loaded in.

I have a lot more content to provide you before we actually get to work, but feel free to review the code I have published thus far.

No need for action items or recommendations as I have not loaded the rest of what is needed to the knowledge folder.

---

### Assistant

It looks like the repo at `github.com/amurtha80/tsa_app` isn't publicly indexed by search engines, which means it's likely set to private. I wasn't able to pull its contents directly.

A couple of options to get me up to speed on the code:

1. **Make the repo public** (if that's appropriate for this project) — then I can fetch it directly.
2. **Paste the code** or key files directly into the chat.
3. **Export/download files** from the repo and upload them here.

Also, just so I'm oriented — what does "TSA" stand for in the context of your project? That'll help me make sense of what I'm looking at once you share the rest of the materials.

---

### User

Transportation Security Administration

---

### Assistant

 Got it, thanks for the context. That's a pretty interesting domain for a data project — lots of potential angles with checkpoint throughput, wait times, staffing, screening data, etc.

Since the repo appears to be private, just paste or upload the code files whenever you're ready, along with the rest of the supporting materials. I'll hold off on any assumptions until I can see the full picture you're building toward.

---

### User

The repo is public 

Here is a link to the page...

https://github.com/amurtha80/tsa_app

---

### Assistant

 

Good, I can see the repo structure now. Let me dig into the actual code files.

Got a good look at what's there. Here's what I can see so far:

**Repo structure:**
- `scrape_test.R` — the main scraping script (174 lines)
- `02_Scripts/` — likely houses additional scripts
- `03_App/tsa_wait_time_app/` — the RShiny app itself
- `tsa_app.Rproj` — RStudio project file

**What `scrape_test.R` is doing:**
It's a Chromote-based web scraper targeting the Houston IAH airport security wait time page (`fly2houston.com`). It uses `rvest` + `read_html_live` to handle the JavaScript-rendered content, pulls both standard lane and TSA PreCheck wait times by checkpoint, and structures everything into a tibble with fields for airport, checkpoint name, datetime, date, time, timezone, standard wait, priority wait, PreCheck wait, and CLEAR wait. There's also a DuckDB connection and `dbAppendTable` call commented out, suggesting the data persistence layer is stubbed in but not yet active.

A few things I noticed that are worth keeping in mind for when we get to work — but as you said, you'll share more context first. I'm ready whenever you are.

---

### User

Folder 02_Scripts/ is the script folder and scrape_data_automate.R is the primary script for the scraping portion of the project

---

### Assistant

The search didn't surface the file directly. Let me try fetching it via the blob URL since I now have the repo page already fetched.

GitHub's robots rules are blocking me from fetching subdirectory blob pages directly without a prior search result linking to them. The easiest workaround would be to either:

1. **Paste the contents of `scrape_data_automate.R`** directly into the chat
2. **Share the raw GitHub URL** for that file (it would look like `https://raw.githubusercontent.com/amurtha80/tsa_app/main/02_Scripts/scrape_data_automate.R`) — though I may hit the same restriction

The same will likely apply to whatever's in the `03_App/tsa_wait_time_app/` folder. Pasting the code directly will be the most reliable path forward as you load up the rest of the materials.

---

### User

Scrape data automate raw file

<details>
<summary>Attachment: attachment</summary>

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
foo(c('rvest', 'httr', 'RSelenium', 'jsonlite', 'duckdb', 'glue', 'DBI', 'netstat',
      'fs', 'chromote', 'here', 'polite', 'tidyverse'))

# Sys.time()
# require('polite')
# require('tidyverse')

Sys.sleep(0.25)


rm(foo)
print("packages loaded")

# Source Scripts ----

## Loading Airport Scraping functions
 


files <- list.files(path = "C:/Users/james/Documents/R/tsa_app/02_Scripts") |>
  stringr::str_subset("_wait_times.R")
print("files object works")


Sys.sleep(0.25)
funcs <- tryCatch({
  as.vector(purrr::map(here::here("C:/Users/james/Documents/R/tsa_app/02_Scripts", files), source))
}, error = function(e) {
  writeLines(paste("ERROR in funcs creation:", conditionMessage(e)), log_file, append = TRUE)
  writeLines(paste("Error occurred at:", Sys.time()), log_file, append = TRUE)
  stop(e)  # Re-throw the error to stop execution
})

# funcs <- as.vector(map(file.path("C:/Users/james/Documents/R/tsa_app/02_Scripts", files), source))
# funcs <- as.vector(purrr::map(here::here("C:/Users/james/Documents/R/tsa_app/02_Scripts", files), source))
# funcs <- as.vector(map(.x = glue("02_Scripts/{files}"), .f = source))
# funcs <- as.vector(source(here::here("02_Scripts/", "ATL_wait_times.R")))
print("funcs object works")


Sys.sleep(0.3)
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

</details>

---

### Assistant

 Good, I can see the full orchestration script now. Here's what I'm taking in:

**What this script does:**
- Opens a sink log to `runlog.txt` for output capture
- Has a smart package loader (`foo`) that installs missing packages before loading
- Dynamically sources all `*_wait_times.R` files from `02_Scripts/` — so each airport has its own dedicated scraping function file
- Has a `safe_read_html_live()` helper with retry logic and graceful exit on failure
- Connects to a DuckDB database, runs all airport functions in a **randomized order** (anti-bot detection strategy), then disconnects and cleans up

**Notable design decisions I see:**
- The randomized `sample(functions)` on each run is a nice touch for mimicking human browsing patterns
- The loop (288 iterations × 5 min = 24 hours) is commented out, suggesting you're currently running single-pass via Windows Task Scheduler rather than a self-looping script
- `safe_read_html_live()` is a good defensive wrapper, though both attempts share the same URL without any fallback variation

**I can also infer the broader architecture:**
- `*_wait_times.R` files are the individual airport scrapers (IAH being the one we saw in `scrape_test.R`)
- DuckDB is the persistence layer (`tsa_app.duckdb`)
- The Shiny app in `03_App/` presumably reads from that same database

Ready for whatever you load next.

---

