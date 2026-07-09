# Install Packages ----

# install.packages(c("duckdb", "DBI", "here", "glue"))

## Access Libraries to Project ----
library(duckdb, verbose = F)
library(DBI, verbose = F)
library(here, verbose = F)
library(glue, verbose = F)

here::here()

# Quack Server -- TSA Test Database ----
# Run this script interactively and leave the session open. It becomes the
# sole holder of 01_Data/tsa_app_quack_test.duckdb (a copy of the production
# DB) and serves reads/writes to every other Quack client (the test
# orchestrator and reader-query scripts) over quack:localhost.
#
# Token: DUCKDB_QUACK_TOKEN in .Renviron. Falls back to a fixed default so
# this script still runs standalone if that var isn't set.

## Connect to Test Database ----

# Create TSA Test Database DuckDB - write connection (server holds this open)
con_write <- dbConnect(duckdb::duckdb(),
                        dbdir = here::here("01_Data", "tsa_app_quack_test.duckdb"),
                        read_only = FALSE)

## DuckDB Database Settings ----

# Confirm engine version supports Quack (requires DuckDB engine 1.5.3+,
# shipped via the core extension repository) before attempting install --
# this is packageVersion("duckdb")'s bundled engine, not the R package
# version, which is always >= the engine it ships with.
engine_version <- dbGetQuery(con_write, "PRAGMA version;")
print(engine_version)

# Setup Quack Extension
# FORCE INSTALL (not plain INSTALL) -- per DuckDB's Quack troubleshooting
# docs, a plain INSTALL can silently reuse a stale/cached extension and
# leave quack_serve unregistered even though INSTALL/LOAD report no error.
dbExecute(con_write, "FORCE INSTALL quack; LOAD quack;")

# Confirm quack actually registered as loaded before calling quack_serve
quack_status <- dbGetQuery(con_write,
  "SELECT extension_name, loaded, installed FROM duckdb_extensions() WHERE extension_name = 'quack';")
print(quack_status)
if (nrow(quack_status) == 0 || !isTRUE(quack_status$loaded)) {
  stop("quack extension did not load -- check engine_version above is >= 1.5.3 and see 02_Scripts troubleshooting notes.")
}

# Start Quack background listener (non-blocking -- returns immediately)
quack_token <- Sys.getenv("DUCKDB_QUACK_TOKEN", "flyasap_quack_test_token")

dbExecute(con_write, glue::glue(
  "CALL quack_serve('quack:localhost', token := '{quack_token}')"
))

print(glue::glue("quack server started on tsa_app_quack_test.duckdb at ",
                  format(Sys.time(), "%a %b %d %X %Y")))

## Confirm tables are visible ----
dbGetQuery(con_write, "SHOW TABLES;")


## Disconnect from Database ----
## Only run this when you are done testing -- shutting down con_write stops
## the Quack server and disconnects every client attached to it.
# DBI::dbDisconnect(con_write, shutdown = TRUE)
# rm(con_write)
# rm(quack_token)
