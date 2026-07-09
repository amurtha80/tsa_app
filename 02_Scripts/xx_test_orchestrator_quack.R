sink(here::here("runlog_quack_test.txt"), append = TRUE, type = "output")

# xx_test_orchestrator_quack.R ----
# Quack concurrency test orchestrator. Connects as a Quack CLIENT (not a
# server) against the server started by zz_test_duckdb_quack.R, which must
# already be running against 01_Data/tsa_app_quack_test.duckdb before this
# script is sourced.
#
# Usage:
#   Dry run (confirm the 3 test scrapers work at all): source this script
#   on its own, with no reader queries running alongside it.
#   Concurrency test: source this script, and while it's running, run
#   xx_test_quack_reader_queries.R (looped) from a separate R session.
#
# Writes only to runlog_quack_test.txt -- does not touch runlog.txt.

# Package Management ----

foo <- function(x) {
  for(i in x) {
    suppressWarnings(suppressPackageStartupMessages(
      if(! require(i, character.only = TRUE, warn.conflicts = FALSE, quietly = TRUE)) {
        install.packages(i, dependencies = TRUE, verbose = FALSE, quiet = TRUE,
                          repos = "https://cloud.r-project.org/")
        require(i, character.only = TRUE, verbose = FALSE, warn.conflicts = FALSE, quietly = TRUE)
      }
    ))
  }
}

foo(c('rvest', 'httr', 'httr2', 'jsonlite', 'duckdb', 'glue', 'DBI',
      'here', 'polite', 'tidyverse'))

rm(foo)
print("packages loaded")

# Source Test Scripts ----

test_files <- c(
  "xx_DEN_quack_test.R",
  "xx_MSP_quack_test.R",
  "xx_CLT_quack_test.R"
)

funcs <- tryCatch({
  as.vector(purrr::map(here::here("02_Scripts", test_files), source))
}, error = function(e) {
  print(glue("ERROR sourcing test funcs: {conditionMessage(e)} at ", format(Sys.time())))
  stop(e)
})
print("test funcs sourced")

rm(funcs)
rm(test_files)

functions <- as.vector(lsf.str())

# Connect to Database via Quack ----

quack_token <- Sys.getenv("DUCKDB_QUACK_TOKEN", "flyasap_quack_test_token")

con_write <- dbConnect(duckdb::duckdb())
dbExecute(con_write, "INSTALL quack; LOAD quack;")
dbExecute(con_write, glue(
  "ATTACH 'quack:localhost' AS remote_db (TYPE quack, TOKEN '{quack_token}')"
))
print(glue("connected to remote_db via quack at ", format(Sys.time())))

# Run Scripts with Dead Time ----

## 20s between each of the 3 airports = 40s idle time (2 gaps), well past the
## 30s+ needed to run read queries concurrently, landing total runtime near
## the ~1min original test target once scrape time is added.
dead_time_seconds <- 20

run_all_functions <- function() {

  print(glue("******-- Start Run ", format(Sys.time()), " --******"))

  functions <- sample(functions)

  ## Track any functions that error out during the main pass
  failed_functions <- character(0)

  for (f in functions) {
    tryCatch(
      do.call(f, list()),
      error = function(e) {
        print(glue("ERROR in {f}: {conditionMessage(e)} at ",
                   format(Sys.time(), "%a %b %d %X %Y")))
        # <<- assigns upward into the enclosing scope so the retry pass can see it
        failed_functions <<- c(failed_functions, f)
      }
    )
    print(glue("dead time: sleeping ", dead_time_seconds, "s at ", format(Sys.time())))
    Sys.sleep(dead_time_seconds)
  }

  ## Retry pass -- attempt each failed function one more time
  if (length(failed_functions) > 0) {

    print(glue("******-- Retry Pass Starting ({length(failed_functions)} failed) ",
               format(Sys.time()), " --******"))

    lapply(failed_functions, function(f) {
      tryCatch(
        do.call(f, list()),
        error = function(e) {
          print(glue("RETRY FAILED for {f}: {conditionMessage(e)} at ",
                     format(Sys.time(), "%a %b %d %X %Y")))
        }
      )
    })

    print(glue("******-- Retry Pass Completed ", format(Sys.time()), " --******"))
  }

  print(glue("******-- Completed Run ", format(Sys.time()), " --******"))
}

run_all_functions()

# Shutdown ----
dbDisconnect(con_write, shutdown = TRUE)
rm(con_write)
rm(quack_token)
rm(functions)
rm(run_all_functions)
rm(dead_time_seconds)
rm(list = ls())

sink()
gc()
