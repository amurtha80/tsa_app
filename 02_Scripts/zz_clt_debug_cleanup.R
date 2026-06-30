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


# 1. What does the live API currently return?
library(jsonlite)
stuff <- fromJSON("https://api.cltairport.mobi/checkpoint-queues/current")
str(stuff, max.level = 3)
stuff$data$items$fullName
names(stuff$data$items$metrics$queueWaitTime)


# Attempting to figure out the mapping from the website, trying to find out the 
# times listed vs. what is showing on site compared to API pull
stuff$data$items[, c("id", "parentId", "fullName")]
#Results
#     id parentId              fullName
# 1 CBPC       CB Checkpoint 1 PreCheck
# 2  CBG       CB Checkpoint 1 Standard
# 3  CEG      CE3          Checkpoint 3
# 4  CAG       CA Checkpoint A Standard

stuff$data$items$metrics$queueWaitTime
#Results
#   lowerBoundSeconds upperBoundSeconds          generatedAt
# 1                 0                 0 2025-04-19T01:20:02Z
# 2                60               300 2025-04-19T01:20:02Z
# 3                 0                 0 2025-04-19T01:20:02Z
# 4                 0                 0 2025-04-19T01:20:02Z

stuff$data$items$metrics$queueStatus
#Results
#   reportedClosed reportStatus          generatedAt
# 1           TRUE      Closure 2025-04-19T01:20:02Z
# 2          FALSE         Open 2025-04-19T01:20:02Z
# 3           TRUE      Closure 2025-04-19T01:20:02Z
# 4           TRUE      Closure 2025-04-19T01:20:02Z


# Before I write anything, I need one more thing: the DB diagnostic. The timing of
# when those CB rows started appearing in your data determines how far back the 
# mislabeling goes and what the cleanup scope is.
con_write <- dbConnect(duckdb::duckdb(), dbdir = here::here("01_Data/tsa_app.duckdb"), read_only = TRUE)

dbGetQuery(con_write, "
  SELECT checkpoint,
         MIN(datetime) AS first_seen,
         MAX(datetime) AS last_seen,
         COUNT(*)      AS row_count
  FROM tsa_wait_times
  WHERE airport = 'CLT'
  GROUP BY checkpoint
  ORDER BY first_seen
")

#Results
#     checkpoint          first_seen           last_seen row_count
# 1 Checkpoint 3 2024-11-27 15:14:51 2026-06-30 02:30:14    114366
# 2 Checkpoint 1 2024-11-27 15:14:51 2026-06-30 02:30:14    114366
# 3 Checkpoint A 2024-11-27 15:14:51 2026-06-30 02:30:14    114366


dbDisconnect(con_write, shutdown = TRUE)
rm(con_write)
