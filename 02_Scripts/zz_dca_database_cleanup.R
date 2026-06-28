# zz_dca_database_cleanup.R

# One-time database cleanup script — DCA junk checkpoint rows
# Run: June 2026
#
# Problem: An earlier version of the flyreagan.com security page rendered
# the hours-of-operation notice ("Opens 4am") inside the same
# .resp-table-row CSS class used by the wait times table. The DCA
# scraper picked it up as a checkpoint name, producing 68 junk rows
# in tsa_wait_times with checkpoint = 'Opens 4am'.
# The page has since been updated — hours text now lives in <li>
# elements and is no longer captured by the scraper.
#
# Action: Deleted 68 rows where airport = 'DCA' AND checkpoint = 'Opens 4am'.
# No scraper changes required.
# See CHANGELOG 2026-06-28 for notes.

# Install Packages ----

# install.packages(c("RSQLite", "nanoparquet", "duckdb", "duckplyr", "DBI"))

## Access Libraries to Project ----
# library(RSQLite, verbose = F)
library(duckdb, verbose = F)
# library(duckplyr, verbose = F)
library(DBI, verbose = F)
library(here, verbose = F)
library(nanoparquet, verbose = F)

here::here()

# TSA Database ----

## Create Database ----

# Create TSA Database DuckDB - write connection
# con_write <- dbConnect(duckdb(), dbdir = "01_Data/tsa_app.duckdb", read_only = FALSE)


# Create TSA Database DuckDB - read connection
# con_read <- dbConnect(duckdb(), dbdir = "01_Data/tsa_app.duckdb", read_only = TRUE)

# Create TSA Database DuckDB - write connection
con_write <- dbConnect(duckdb(), dbdir = "01_Data/tsa_app.duckdb", read_only = FALSE)

# Initial query to check out the start time and end time of the different checkpoint categories
dbGetQuery(con_write, "SELECT DISTINCT checkpoint, COUNT(*) AS n
FROM tsa_wait_times
WHERE airport = 'DCA'
GROUP BY checkpoint
ORDER BY checkpoint;")

# Results
#                             checkpoint      n
# 1                            Opens 4am     68
# 2                Terminal 1 ( A Gates)  96937
# 3 Terminal 2 North ( B, C, D, E Gates) 112429
# 4 Terminal 2 South ( B, C, D, E Gates) 112456

# Fix the database and delete the "Opens 4am" Checkpoint data
dbExecute(con_write, "DELETE FROM tsa_wait_times
WHERE airport = 'DCA'
  AND checkpoint = 'Opens 4am';")

#Results
# [1] 68

# Verify the count is Zero and that group is now gone from the database
dbGetQuery(con_write, "SELECT COUNT(*) 
FROM tsa_wait_times
WHERE airport = 'DCA'
  AND checkpoint = 'Opens 4am';")

#Results
#   count_star()       
# 1            0


# Cleanup ----

# dbDisconnect(con_read, shutdown = TRUE)
# rm(con_read)

dbDisconnect(con_write, shutdown = TRUE)
rm(con_write)
