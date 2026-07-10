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
con_write <- dbConnect(duckdb::duckdb(), dbdir = here::here("01_Data/tsa_app.duckdb"), read_only = FALSE)

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

# checking on distinct wait time values to see whether the API is broken since apr 2025
dbGetQuery(con_write, "
  SELECT datetime, checkpoint, wait_time, wait_time_pre_check
  FROM tsa_wait_times
  WHERE airport = 'CLT'
  ORDER BY datetime DESC
  LIMIT 20
")

#Results
#               datetime   checkpoint wait_time wait_time_pre_check
# 1  2026-06-30 12:56:10 Checkpoint 1         5                  NA
# 2  2026-06-30 12:56:10 Checkpoint 3         0                  NA
# 3  2026-06-30 12:56:10 Checkpoint A        NA                  NA
# 4  2026-06-30 12:50:36 Checkpoint 1         5                  NA
# 5  2026-06-30 12:50:36 Checkpoint 3         0                  NA
# 6  2026-06-30 12:50:36 Checkpoint A        NA                  NA
# 7  2026-06-30 12:45:12 Checkpoint 1         5                  NA
# 8  2026-06-30 12:45:12 Checkpoint 3         0                  NA
# 9  2026-06-30 12:45:12 Checkpoint A        NA                  NA
# 10 2026-06-30 12:40:37 Checkpoint 1         5                  NA
# 11 2026-06-30 12:40:37 Checkpoint 3         0                  NA
# 12 2026-06-30 12:40:37 Checkpoint A        NA                  NA
# 13 2026-06-30 12:35:19 Checkpoint 1         5                  NA
# 14 2026-06-30 12:35:19 Checkpoint 3         0                  NA
# 15 2026-06-30 12:35:19 Checkpoint A        NA                  NA
# 16 2026-06-30 12:30:33 Checkpoint 1         5                  NA
# 17 2026-06-30 12:30:33 Checkpoint 3         0                  NA
# 18 2026-06-30 12:30:33 Checkpoint A        NA                  NA
# 19 2026-06-30 12:25:49 Checkpoint 3         0                  NA
# 20 2026-06-30 12:25:49 Checkpoint A        NA                  NA


dbGetQuery(con_write, "
  SELECT date, COUNT(DISTINCT wait_time) AS distinct_wait_values
  FROM tsa_wait_times
  WHERE airport = 'CLT' AND date >= DATE '2026-06-23'
  GROUP BY date
  ORDER BY date
")

#Results
#         date distinct_wait_values
# 1 2026-06-23                    2
# 2 2026-06-24                    2
# 3 2026-06-25                    2
# 4 2026-06-26                    2
# 5 2026-06-27                    2
# 6 2026-06-28                    2
# 7 2026-06-29                    2
# 8 2026-06-30                    2

# Diagnostic Query for exact freeze based on API updated
dbGetQuery(con_write, "
  SELECT date,
         checkpoint,
         COUNT(DISTINCT wait_time) AS distinct_values,
         MIN(wait_time) AS min_wt,
         MAX(wait_time) AS max_wt
  FROM tsa_wait_times
  WHERE airport = 'CLT'
    AND date BETWEEN DATE '2025-04-10' AND DATE '2025-04-25'
  GROUP BY date, checkpoint
  ORDER BY date, checkpoint
")

#         date   checkpoint distinct_values min_wt max_wt
# 1  2025-04-10 Checkpoint 1              34      0     40
# 2  2025-04-10 Checkpoint 3              25      0     28
# 3  2025-04-10 Checkpoint A               0     NA     NA
# 4  2025-04-11 Checkpoint 1              27      0     31
# 5  2025-04-11 Checkpoint 3              32      0     33
# 6  2025-04-11 Checkpoint A               0     NA     NA
# 7  2025-04-12 Checkpoint 1              28      0     30
# 8  2025-04-12 Checkpoint 3              27      0     29
# 9  2025-04-12 Checkpoint A               0     NA     NA
# 10 2025-04-13 Checkpoint 1              23      0     24
# 11 2025-04-13 Checkpoint 3              24      0     28
# 12 2025-04-13 Checkpoint A               0     NA     NA
# 13 2025-04-14 Checkpoint 1              25      0     35
# 14 2025-04-14 Checkpoint 3              28      0     29
# 15 2025-04-14 Checkpoint A               0     NA     NA
# 16 2025-04-15 Checkpoint 1              25      0     31
# 17 2025-04-15 Checkpoint 3              24      0     25
# 18 2025-04-15 Checkpoint A               0     NA     NA
# 19 2025-04-16 Checkpoint 1              19      0     21
# 20 2025-04-16 Checkpoint 3              27      0     31
# 21 2025-04-16 Checkpoint A               0     NA     NA
# 22 2025-04-17 Checkpoint 1              25      0     28
# 23 2025-04-17 Checkpoint 3              26      0     28
# 24 2025-04-17 Checkpoint A               0     NA     NA
# 25 2025-04-18 Checkpoint 1              24      0     31
# 26 2025-04-18 Checkpoint 3              21      0     23
# 27 2025-04-18 Checkpoint A               0     NA     NA
# 28 2025-04-19 Checkpoint 1               1      5      5
# 29 2025-04-19 Checkpoint 3               1      0      0
# 30 2025-04-19 Checkpoint A               0     NA     NA
# 31 2025-04-20 Checkpoint 1               1      5      5
# 32 2025-04-20 Checkpoint 3               1      0      0
# 33 2025-04-20 Checkpoint A               0     NA     NA
# 34 2025-04-21 Checkpoint 1               1      5      5
# 35 2025-04-21 Checkpoint 3               1      0      0
# 36 2025-04-21 Checkpoint A               0     NA     NA
# 37 2025-04-22 Checkpoint 1               1      5      5
# 38 2025-04-22 Checkpoint 3               1      0      0
# 39 2025-04-22 Checkpoint A               0     NA     NA
# 40 2025-04-23 Checkpoint 1               1      5      5
# 41 2025-04-23 Checkpoint 3               1      0      0
# 42 2025-04-23 Checkpoint A               0     NA     NA
# 43 2025-04-24 Checkpoint 1               1      5      5
# 44 2025-04-24 Checkpoint 3               1      0      0
# 45 2025-04-24 Checkpoint A               0     NA     NA
# 46 2025-04-25 Checkpoint 1               1      5      5
# 47 2025-04-25 Checkpoint 3               1      0      0
# 48 2025-04-25 Checkpoint A               0     NA     NA

# File backup of the database prior to removing all 228k+ records for CLT cleanup
file.copy(
  from = here::here("01_Data/tsa_app.duckdb"),
  to   = here::here("01_Data/tsa_app_backup_pre_clt_cleanup_20260702.duckdb")
)

# Delete frozen rows (April 19, 2025 onward) ----
dbExecute(con_write, "
  DELETE FROM tsa_wait_times
  WHERE airport = 'CLT'
    AND date >= DATE '2025-04-19'
")

# Results
# 234888

# Delete all Checkpoint A rows (always NA, never real data) ----
dbExecute(con_write, "
  DELETE FROM tsa_wait_times
  WHERE airport = 'CLT'
    AND checkpoint = 'Checkpoint A'
")

# Results
# 36245

# Check to make sure that everything is cleaned up
dbGetQuery(con_write, "
  SELECT checkpoint,
         MIN(date) AS first_date,
         MAX(date) AS last_date,
         COUNT(*)  AS row_count
  FROM tsa_wait_times
  WHERE airport = 'CLT'
  GROUP BY checkpoint
  ORDER BY checkpoint
")

# Results
#   checkpoint first_date  last_date row_count
# 1 Checkpoint 1 2024-11-27 2025-04-18     36245
# 2 Checkpoint 3 2024-11-27 2025-04-18     36245

# Check to see whether the new data showed up in the database since new scrape started yesterday
dbGetQuery(con_write, "
  SELECT checkpoint,
         MIN(date)  AS first_date,
         MAX(date)  AS last_date,
         COUNT(*)   AS row_count
  FROM tsa_wait_times
  WHERE airport = 'CLT'
  GROUP BY checkpoint
  ORDER BY checkpoint
")

# Results - appears to be working, log shows success, and counts for all checkpoints are increasing
#     checkpoint first_date  last_date row_count
# 1 Checkpoint 1 2024-11-27 2026-07-03     36256
# 2 Checkpoint 2 2026-07-03 2026-07-03        11
# 3 Checkpoint 3 2024-11-27 2026-07-03     36256

dbDisconnect(con_write, shutdown = TRUE)
rm(con_write)
