# Install Packages ----

# install.packages(c("RSQLite", "nanoparquet", "duckdb", "duckplyr", "DBI", "here", "glue"))

## Access Libraries to Project ----
# library(RSQLite, verbose = F)
# library(duckdb, verbose = F)
# library(duckplyr, verbose = F)
# library(DBI, verbose = F)
# library(here, verbose = F)
# library(nanoparquet, verbose = F)
# library(glue, verbose = F)

# here::here()

# TSA Test Database ----

## Connect to Test Database ----

# Create TSA Database DuckDB - write connection
# con_write <- dbConnect(duckdb(), dbdir = "01_Data/tsa_app.duckdb", read_only = FALSE)

## DuckDB Database Settings ----
# Setup Quack Extension
# dbExecute(con_write, "INSTALL quack; LOAD quack;")
# Start Quack background listener
# dbExecute(con_write, glue("CALL quack_serve('quack:localhost', token := '{Sys.getenv('QUACK_TOKEN')}')"))



## Disconnect from Database ----
DBI::dbDisconnect(con_write, shutdown = TRUE)
rm(con_write)