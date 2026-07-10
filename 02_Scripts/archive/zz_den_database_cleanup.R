# zz_den_database_cleanup.R
# One-time database cleanup script — DEN checkpoint data
# Run: June 2026
#
# Problem: DEN scraper wrote 158,465 rows with NULL checkpoint names
# between 2024-12-05 and 2026-06-11 during the Great Hall Project
# construction transition (North/South → East/West rename).
# Only 1,122 rows had non-null wait_time values, all concentrated
# Dec 2024 – Feb 2025 and too sparse to salvage.
#
# Action: Deleted all DEN rows where checkpoint IS NULL.
# See CHANGELOG 2026-06-27 for full investigation notes.

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
con_read <- dbConnect(duckdb(), dbdir = "01_Data/tsa_app.duckdb", read_only = TRUE)

# Create TSA Database DuckDB - write connection
con_write <- dbConnect(duckdb(), dbdir = "01_Data/tsa_app.duckdb", read_only = FALSE)

# Initial query to check out the start time and end time of the different checkpoint categories
dbGetQuery(con_write, "SELECT checkpoint, MIN(date) AS first_seen, MAX(date) AS last_seen,
COUNT(*)   AS obs_count FROM tsa_wait_times WHERE airport = 'DEN' GROUP BY checkpoint
ORDER BY first_seen;")

#Results
#        checkpoint first_seen  last_seen obs_count
# 1 Bridge Security 2024-11-27 2024-12-05      2021
# 2            West 2024-11-27 2025-04-21     35922
# 3  South Security 2024-11-27 2025-04-21     35922
# 4            <NA> 2024-12-05 2026-06-11    158465
# 5           South 2025-04-21 2025-08-04      1803
# 6   East Security 2025-07-29 2026-06-27     12357
# 7   West Security 2025-08-05 2026-06-27      4611

# Second query to check out the null checkpoint values to see whether we can salvage them
dbGetQuery(con_read, "SELECT MIN(date) AS first_seen, MAX(date) AS last_seen,
MIN(time) AS earliest_time, MAX(time) AS latest_time, COUNT(*) AS obs_count,
COUNT(wait_time) AS non_null_wait_times FROM tsa_wait_times
WHERE airport = 'DEN' AND checkpoint IS NULL;")

#Results
#   first_seen  last_seen       earliest_time         latest_time obs_count non_null_wait_times
# 1 2024-12-05 2026-06-11 2024-12-05 19:25:00 2026-06-12 00:40:00    158465                1122

# Third query to check if the non-null wait times are worth rescuing
dbGetQuery(con_read, "SELECT date, COUNT(wait_time) AS non_null_wait_times
FROM tsa_wait_times WHERE airport = 'DEN' AND checkpoint IS NULL
AND wait_time IS NOT NULL GROUP BY date ORDER BY date;")

#Results
#          date non_null_wait_times
# 1  2024-12-05                  12
# 2  2024-12-06                  14
# 3  2024-12-07                  19
# 4  2024-12-08                  10
# 5  2024-12-09                  22
# 6  2024-12-10                  16
# 7  2024-12-11                  15
# 8  2024-12-12                  15
# 9  2024-12-13                  18
# 10 2024-12-14                  17
# 11 2024-12-15                  10
# 12 2024-12-16                  18
# 13 2024-12-17                  19
# 14 2024-12-18                  16
# 15 2024-12-19                  21
# 16 2024-12-20                  17
# 17 2024-12-21                  23
# 18 2024-12-22                  27
# 19 2024-12-23                  24
# 20 2024-12-24                  16
# 21 2024-12-25                  15
# 22 2024-12-26                  18
# 23 2024-12-27                  16
# 24 2024-12-28                  17
# 25 2024-12-29                   9
# 26 2024-12-30                  17
# 27 2024-12-31                  15
# 28 2025-01-01                  17
# 29 2025-01-02                  15
# 30 2025-01-03                  18
# 31 2025-01-04                  16
# 32 2025-01-05                  20
# 33 2025-01-06                  15
# 34 2025-01-07                   9
# 35 2025-01-08                   4
# 36 2025-01-09                  10
# 37 2025-01-10                  19
# 38 2025-01-11                  21
# 39 2025-01-12                  15
# 40 2025-01-13                  13
# 41 2025-01-14                  14
# 42 2025-01-15                  14
# 43 2025-01-16                  15
# 44 2025-01-17                  11
# 45 2025-01-18                  15
# 46 2025-01-19                  15
# 47 2025-01-20                  12
# 48 2025-01-21                  15
# 49 2025-01-22                   9
# 50 2025-01-23                  12
# 51 2025-01-24                   9
# 52 2025-01-25                  16
# 53 2025-01-26                  14
# 54 2025-01-27                  13
# 55 2025-01-28                  21
# 56 2025-01-29                  14
# 57 2025-01-30                  10
# 58 2025-01-31                  17
# 59 2025-02-01                   8
# 60 2025-02-02                  16
# 61 2025-02-03                  13
# 62 2025-02-04                  16
# 63 2025-02-05                  17
# 64 2025-02-06                  16
# 65 2025-02-07                  15
# 66 2025-02-08                  12
# 67 2025-02-09                   7
# 68 2025-02-10                   7
# 69 2025-02-11                  15
# 70 2025-02-12                   2
# 71 2025-02-13                   3
# 72 2025-02-14                   9
# 73 2025-02-15                  11
# 74 2025-02-16                  10
# 75 2025-02-17                  13
# 76 2025-02-18                  11
# 77 2025-02-19                  18
# 78 2025-02-20                   5
# 79 2025-04-21                   2
# 80 2025-12-04                   1
# 81 2025-12-05                   1

# Solution ----

#Delete the null value checkpoint records from the database, and then review whether
#to combine the other old checkpoint names into the new names (West, South Security, South
# into the new West)
dbExecute(con_write, "DELETE FROM tsa_wait_times WHERE airport = 'DEN'
AND checkpoint IS NULL;")

#Results
# [1] 158465

#Run the original query again to see what is left is clean:
dbGetQuery(con_read, "SELECT checkpoint, MIN(date) AS first_seen, MAX(date) AS last_seen,
COUNT(*)   AS obs_count FROM tsa_wait_times WHERE airport = 'DEN' GROUP BY checkpoint
ORDER BY first_seen;")

#Results
#        checkpoint first_seen  last_seen obs_count
# 1            West 2024-11-27 2025-04-21     35922
# 2 Bridge Security 2024-11-27 2024-12-05      2021
# 3  South Security 2024-11-27 2025-04-21     35922
# 4           South 2025-04-21 2025-08-04      1803
# 5   East Security 2025-07-29 2026-06-27     12370
# 6   West Security 2025-08-05 2026-06-27      4624


# Potential Mapping Fix
# South Security + South → West Security (South was the 24/7 standard checkpoint, physically on the west side)
# West → West Security (same checkpoint, early CSS scraper variant)
# East Security → stays as East Security (already correct)
# Bridge Security → leave alone (different checkpoint, no longer exists, not worth folding in)

# Checking Old `West` and `South Security` observations to make sure they aren't
# duplicate records
dbGetQuery(con_read, "SELECT date, time, COUNT(*) AS row_count FROM tsa_wait_times
WHERE airport = 'DEN' AND checkpoint IN ('West', 'South Security')
GROUP BY date, time HAVING COUNT(*) > 1 ORDER BY date, time LIMIT 20;")

#Results - Confirmed Duplicate observations
# date                time row_count
# 1  2024-11-27 2024-11-27 15:21:00         2
# 2  2024-11-27 2024-11-27 16:11:00         2
# 3  2024-11-27 2024-11-27 16:15:00         2
# 4  2024-11-27 2024-11-27 16:20:00         2
# 5  2024-11-27 2024-11-27 16:25:00         2
# 6  2024-11-27 2024-11-27 16:30:00         2
# 7  2024-11-27 2024-11-27 18:56:00         2
# 8  2024-11-27 2024-11-27 19:00:00         2
# 9  2024-11-27 2024-11-27 19:05:00         2
# 10 2024-11-27 2024-11-27 19:10:00         2
# 11 2024-11-27 2024-11-27 19:15:00         2
# 12 2024-11-27 2024-11-27 19:20:00         2
# 13 2024-11-27 2024-11-27 19:25:00         2
# 14 2024-11-27 2024-11-27 19:30:00         2
# 15 2024-11-27 2024-11-27 19:35:00         2
# 16 2024-11-27 2024-11-27 19:40:00         2
# 17 2024-11-27 2024-11-27 19:45:00         2
# 18 2024-11-27 2024-11-27 19:50:00         2
# 19 2024-11-27 2024-11-27 19:55:00         2
# 20 2024-11-27 2024-11-27 20:00:00         2

# Sanity check - do wait times from duplicate records actually differ
dbGetQuery(con_read, "SELECT 
  a.date,
  a.time,
  a.checkpoint        AS checkpoint_a,
  a.wait_time         AS wait_time_a,
  a.wait_time_pre_check AS pre_check_a,
  b.checkpoint        AS checkpoint_b,
  b.wait_time         AS wait_time_b,
  b.wait_time_pre_check AS pre_check_b
FROM tsa_wait_times a
JOIN tsa_wait_times b
  ON a.airport = b.airport
  AND a.date   = b.date
  AND a.time   = b.time
WHERE a.airport    = 'DEN'
  AND a.checkpoint = 'West'
  AND b.checkpoint = 'South Security'
LIMIT 20;")

#Results - These actually have different results in this sample, going to do one more check
# date                time checkpoint_a wait_time_a pre_check_a   checkpoint_b wait_time_b pre_check_b
# 1  2024-11-27 2024-11-27 15:21:00         West           2          NA South Security          NA          NA
# 2  2024-11-27 2024-11-27 16:11:00         West           2          NA South Security          NA          NA
# 3  2024-11-27 2024-11-27 16:15:00         West           2          NA South Security          NA          NA
# 4  2024-11-27 2024-11-27 16:20:00         West           2          NA South Security          NA          NA
# 5  2024-11-27 2024-11-27 16:25:00         West           2          NA South Security          NA          NA
# 6  2024-11-27 2024-11-27 16:30:00         West           2          NA South Security          NA          NA
# 7  2024-11-27 2024-11-27 18:56:00         West           2          NA South Security          NA          NA
# 8  2024-11-27 2024-11-27 19:00:00         West           2          NA South Security          NA          NA
# 9  2024-11-27 2024-11-27 19:05:00         West           2          NA South Security          NA          NA
# 10 2024-11-27 2024-11-27 19:10:00         West           2          NA South Security          NA          NA
# 11 2024-11-27 2024-11-27 19:15:00         West           2          NA South Security          NA          NA
# 12 2024-11-27 2024-11-27 19:20:00         West           2          NA South Security          NA          NA
# 13 2024-11-27 2024-11-27 19:25:00         West           2          NA South Security          NA          NA
# 14 2024-11-27 2024-11-27 19:30:00         West           3           5 South Security          12           6
# 15 2024-11-27 2024-11-27 19:35:00         West           2          NA South Security          NA          NA
# 16 2024-11-27 2024-11-27 19:40:00         West           2          NA South Security          NA          NA
# 17 2024-11-27 2024-11-27 19:45:00         West           2          NA South Security          NA          NA
# 18 2024-11-27 2024-11-27 19:50:00         West           2          NA South Security          NA          NA
# 19 2024-11-27 2024-11-27 19:55:00         West           2          NA South Security          NA          NA
# 20 2024-11-27 2024-11-27 20:00:00         West           2          NA South Security          NA          NA


# Second Sanity check with different checkpoint names to determine whether data is different
dbGetQuery(con_read, "SELECT 
  a.date,
  a.time,
  a.checkpoint          AS checkpoint_a,
  a.wait_time           AS wait_time_a,
  a.wait_time_pre_check AS pre_check_a,
  b.checkpoint          AS checkpoint_b,
  b.wait_time           AS wait_time_b,
  b.wait_time_pre_check AS pre_check_b
FROM tsa_wait_times a
JOIN tsa_wait_times b
  ON a.airport = b.airport
  AND a.date   = b.date
  AND a.time   = b.time
WHERE a.airport    = 'DEN'
  AND a.checkpoint = 'South'
  AND b.checkpoint = 'West Security'
LIMIT 20;")

#Results - Souuth and West Security never overlap, hence 0 rows, sequential not duplicates
# [1] date         time         checkpoint_a wait_time_a  pre_check_a  checkpoint_b wait_time_b  pre_check_b 
# <0 rows> (or 0-length row.names)


# Execution Plan for Checkpoint Cleanup ----
# West → East Security (was capturing North/East checkpoint)
# South Security → West Security (was capturing South/West checkpoint)
# South → West Security (sequential continuation of same checkpoint)
# Bridge Security → leave as-is
# East Security → leave as-is
# West Security → leave as-is


# West Update
dbExecute(con_write, "UPDATE tsa_wait_times
SET checkpoint = 'East Security'
WHERE airport = 'DEN'
AND checkpoint = 'West';")

#Results
# 35922

# South Security Update
dbExecute(con_write, "UPDATE tsa_wait_times
SET checkpoint = 'West Security'
WHERE airport = 'DEN'
AND checkpoint = 'South Security';")

#Results
# 35922

# South Update
dbExecute(con_write, "UPDATE tsa_wait_times
SET checkpoint = 'West Security'
WHERE airport = 'DEN'
AND checkpoint = 'South';")

#Results
# 1803


# Rerun original query to ensure cleanup is complete to check if we are down to two current checkpoints
dbGetQuery(con_read, "SELECT checkpoint, MIN(date) AS first_seen, MAX(date) AS last_seen,
COUNT(*)   AS obs_count FROM tsa_wait_times WHERE airport = 'DEN' GROUP BY checkpoint
ORDER BY first_seen;")

#Results
#       checkpoint first_seen  last_seen obs_count
# 1 Bridge Security 2024-11-27 2024-12-05      2021
# 2   East Security 2024-11-27 2026-06-27     48297
# 3   West Security 2024-11-27 2026-06-27     42354



# Cleanup Environment ----

DBI::dbDisconnect(con_read, shutdown = TRUE)
rm(con_read)

DBI::dbDisconnect(con_write, shutdown = TRUE)
rm(con_write)
