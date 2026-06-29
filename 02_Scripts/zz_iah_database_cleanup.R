# zz_iah_database_cleanup.R
# One-time database cleanup script — IAH checkpoint name normalization
# Run: June 2026
#
# Problem: IAH checkpoint names accumulated across three eras:
#   Era 1 (Dec 2024 – Mar 2026): old scraper wrote names without "IAH" prefix
#   Era 2 (Mar 2026 – present):  current scraper correctly writes "IAH Terminal X" names
#   Era 3 (Mar 2026 blip):       strip-and-pivot logic temporarily failed; lane suffix
#                                 left in checkpoint name instead of routed to lane column
#
# Actions:
#   - Rename Era 1 names to canonical "IAH Terminal X" format (5 checkpoints)
#   - Rename Era 3 blip Pre-check/PreCheck names to canonical (3 checkpoints)
#   - Delete unrecoverable rows: Loading, concatenation glitch, Terminal E blip (all-null)
#   - Terminal B retained as-is (historical record, outside 12-month window)
#   - Terminal E Pre-check deleted (ambiguous column assignment, 4 days, redundant)
# See CHANGELOG 2026-06-28 for full investigation notes.


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
View(dbGetQuery(con_write, "SELECT
checkpoint,
COUNT(*)        AS obs_count,
MIN(date)       AS first_seen,
MAX(date)       AS last_seen
FROM tsa_wait_times
WHERE airport = 'IAH'
GROUP BY checkpoint
ORDER BY first_seen;"))

#Results
# Era 3 blip names — all map cleanly to canonical, the PreCheck wait time is sitting in 
# the wrong column (checkpoint name instead of wait_time_pre_check). We need one more 
# query to confirm before deciding whether to fix or delete.

# 1                                                                                  Terminal B
# 2                                                                            Terminal A South
# 3                                                                                     Loading
# 4                                                                            Terminal C North
# 5                                                                            Terminal A North
# 6                                                                                  Terminal D
# 7                                                                            Terminal C South
# 8  cTerminal A North Terminal A South Terminal B Terminal C North Terminal C South Terminal D
# 9                                                                              IAH Terminal D
# 10                                                                       IAH Terminal A South
# 11                                                                       IAH Terminal C North
# 12                                                                       IAH Terminal C South
# 13                                                                       IAH Terminal A North
# 14                                                                             IAH Terminal E
# 15                                                                       Terminal E Pre-check
# 16                                                                 Terminal A North Pre-check
# 17                                                             IAH Terminal C North Pre-check
# 18                                                                   IAH Terminal E Pre-check
# 19                                                                    IAH Terminal E PreCheck
# 20                                                             IAH Terminal A North Pre-check
# 21                                                              IAH Terminal A North PreCheck
# 22                                                              IAH Terminal C North PreCheck
# obs_count first_seen  last_seen
# 1      11418 2024-12-05 2025-01-21
# 2      25293 2024-12-05 2025-03-26
# 3        999 2024-12-05 2025-03-25
# 4      25293 2024-12-05 2025-03-26
# 5      25293 2024-12-05 2025-03-26
# 6      25293 2024-12-05 2025-03-26
# 7      25293 2024-12-05 2025-03-26
# 8          6 2024-12-05 2024-12-05
# 9      70615 2025-03-26 2026-06-28
# 10     70674 2025-03-26 2026-06-28
# 11     70259 2025-03-26 2026-06-28
# 12     70615 2025-03-26 2026-06-28
# 13     70616 2025-03-26 2026-06-28
# 14     36816 2025-10-28 2026-06-28
# 15      1294 2026-03-09 2026-03-19
# 16      1294 2026-03-09 2026-03-19
# 17        19 2026-03-19 2026-03-19
# 18        11 2026-03-19 2026-03-19
# 19       373 2026-03-19 2026-03-23
# 20        11 2026-03-19 2026-03-19
# 21       373 2026-03-19 2026-03-23
# 22       373 2026-03-19 2026-03-23

# second query so I can see the blip rows' column structure before recommending fix-vs-delete:
dbGetQuery(con_write, "SELECT
    checkpoint,
    COUNT(*)                        AS obs_count,
    COUNT(wait_time)                AS non_null_standard,
    COUNT(wait_time_pre_check)      AS non_null_precheck,
    COUNT(wait_time_priority)       AS non_null_priority
FROM tsa_wait_times
WHERE airport = 'IAH'
    AND checkpoint IN (
        'Terminal A North Pre-check',
        'Terminal E Pre-check',
        'IAH Terminal E Pre-check',
        'IAH Terminal A North Pre-check',
        'IAH Terminal C North Pre-check',
        'IAH Terminal E PreCheck',
        'IAH Terminal A North PreCheck',
        'IAH Terminal C North PreCheck'
    )
GROUP BY checkpoint
ORDER BY checkpoint;")

#Results
# The blip rows have both wait_time (standard) and wait_time_pre_check populated. 
# That means the pivot still ran correctly — the lane times are in the right columns. 
# The only problem is the checkpoint name wasn't stripped properly. So these rows 
# are structurally sound, just misnamed. We rename them, not delete them.

# checkpoint obs_count non_null_standard non_null_precheck non_null_priority
# 1 IAH Terminal A North Pre-check        11                11                11                 0
# 2  IAH Terminal A North PreCheck       373               337               337                 0
# 3 IAH Terminal C North Pre-check        19                 4                 4                 0
# 4  IAH Terminal C North PreCheck       373               343               343                 0
# 5       IAH Terminal E Pre-check        11                 0                 0                 0
# 6        IAH Terminal E PreCheck       373                 0                 0                 0
# 7     Terminal A North Pre-check      1294              1294              1294                 0
# 8           Terminal E Pre-check      1294              1198              1198                 0


# Check for group #14 from original query IAH Terminal E to see the count of 
# how many standard and pre-check times there are
dbGetQuery(con_write, "SELECT
    COUNT(*)                    AS obs_count,
    COUNT(wait_time)            AS non_null_standard,
    COUNT(wait_time_pre_check)  AS non_null_precheck
FROM tsa_wait_times
WHERE airport = 'IAH'
    AND checkpoint = 'IAH Terminal E';")

#Results
# It appears there are valid non-null values for IAH Terminal E for standard and pre-check
# We have data retained to use for analysis.
#   obs_count non_null_standard non_null_precheck
# 1     36819             36811             36754

# Fix ----
# Full cleanup plan
# ActionRows
# Rename Terminal A North → IAH Terminal A North 25,293
# Rename Terminal A South → IAH Terminal A South 25,293
# Rename Terminal C North → IAH Terminal C North 25,293
# Rename Terminal C South → IAH Terminal C South 25,293
# Rename Terminal D → IAH Terminal D25,293
# Rename Terminal A North Pre-check → IAH Terminal A North 1,294
# Rename IAH Terminal A North Pre-check → IAH Terminal A North11Rename IAH Terminal A North PreCheck → IAH Terminal A North373Rename IAH Terminal C North Pre-check → IAH Terminal C North19Rename IAH Terminal C North PreCheck → IAH Terminal C North 373
# Delete IAH Terminal E PreCheck (all nulls) 373
# Delete IAH Terminal E Pre-check (all nulls) 11
# Delete Terminal E Pre-check — see note below 1,294
# Delete Loading 999
# Delete concatenation glitch6Terminal B — your call 11,418
# 
# Terminal E Pre-check — 1,294 rows, 1,198 non-null standard values, but Terminal 
# E didn't appear in the data until Oct 2025 under IAH Terminal E. These rows are 
# from Mar 2026 during the blip, and Terminal E only has a Standard and PreCheck 
# lane. Since the name has "Pre-check" in it but the wait time landed in wait_time
# (standard column), the data is ambiguous — we don't know if these are standard 
# or precheck times. I'd recommend delete rather than guess. Agree?


# Era 1 Renames — add IAH prefix ----

dbExecute(con_write, "
UPDATE tsa_wait_times
SET checkpoint = 'IAH Terminal A North'
WHERE airport = 'IAH'
    AND checkpoint = 'Terminal A North'
")
# Expected: 25293

dbExecute(con_write, "
UPDATE tsa_wait_times
SET checkpoint = 'IAH Terminal A South'
WHERE airport = 'IAH'
    AND checkpoint = 'Terminal A South'
")
# Expected: 25293

dbExecute(con_write, "
UPDATE tsa_wait_times
SET checkpoint = 'IAH Terminal C North'
WHERE airport = 'IAH'
    AND checkpoint = 'Terminal C North'
")
# Expected: 25293

dbExecute(con_write, "
UPDATE tsa_wait_times
SET checkpoint = 'IAH Terminal C South'
WHERE airport = 'IAH'
    AND checkpoint = 'Terminal C South'
")
# Expected: 25293

dbExecute(con_write, "
UPDATE tsa_wait_times
SET checkpoint = 'IAH Terminal D'
WHERE airport = 'IAH'
    AND checkpoint = 'Terminal D'
")
# Expected: 25293


# Era 3 Renames — strip lane suffix from checkpoint name ----

dbExecute(con_write, "
UPDATE tsa_wait_times
SET checkpoint = 'IAH Terminal A North'
WHERE airport = 'IAH'
    AND checkpoint = 'Terminal A North Pre-check'
")
# Expected: 1294

dbExecute(con_write, "
UPDATE tsa_wait_times
SET checkpoint = 'IAH Terminal A North'
WHERE airport = 'IAH'
    AND checkpoint = 'IAH Terminal A North Pre-check'
")
# Expected: 11

dbExecute(con_write, "
UPDATE tsa_wait_times
SET checkpoint = 'IAH Terminal A North'
WHERE airport = 'IAH'
    AND checkpoint = 'IAH Terminal A North PreCheck'
")
# Expected: 373

dbExecute(con_write, "
UPDATE tsa_wait_times
SET checkpoint = 'IAH Terminal C North'
WHERE airport = 'IAH'
    AND checkpoint = 'IAH Terminal C North Pre-check'
")
# Expected: 19

dbExecute(con_write, "
UPDATE tsa_wait_times
SET checkpoint = 'IAH Terminal C North'
WHERE airport = 'IAH'
    AND checkpoint = 'IAH Terminal C North PreCheck'
")
# Expected: 373


# Deletes ----

# Loading — page not fully rendered at scrape time
dbExecute(con_write, "
DELETE FROM tsa_wait_times
WHERE airport = 'IAH'
    AND checkpoint = 'Loading'
")
# Expected: 999

# Concatenation glitch — one-time selector failure
dbExecute(con_write, "
DELETE FROM tsa_wait_times
WHERE airport = 'IAH'
    AND checkpoint = 'cTerminal A North Terminal A South Terminal B Terminal C North Terminal C South Terminal D'
")
# Expected: 6

# Terminal E blip — all-null wait times, unrecoverable
dbExecute(con_write, "
DELETE FROM tsa_wait_times
WHERE airport = 'IAH'
    AND checkpoint IN ('IAH Terminal E PreCheck', 'IAH Terminal E Pre-check')
")
# Expected: 384

# Terminal E Pre-check — ambiguous column assignment, 4 days, redundant
dbExecute(con_write, "
DELETE FROM tsa_wait_times
WHERE airport = 'IAH'
    AND checkpoint = 'Terminal E Pre-check'
")
# Expected: 1294


# Verify final state ----

dbGetQuery(con_write, "
SELECT
    checkpoint,
    COUNT(*)    AS obs_count,
    MIN(date)   AS first_seen,
    MAX(date)   AS last_seen
FROM tsa_wait_times
WHERE airport = 'IAH'
GROUP BY checkpoint
ORDER BY first_seen
")

#Results
#             checkpoint obs_count first_seen  last_seen
# 1 IAH Terminal A North     97592 2024-12-05 2026-06-28
# 2 IAH Terminal A South     95972 2024-12-05 2026-06-28
# 3           Terminal B     11418 2024-12-05 2025-01-21
# 4       IAH Terminal D     95913 2024-12-05 2026-06-28
# 5 IAH Terminal C North     95949 2024-12-05 2026-06-28
# 6 IAH Terminal C South     95913 2024-12-05 2026-06-28
# 7       IAH Terminal E     36821 2025-10-28 2026-06-28


# Cleanup ----

dbDisconnect(con_write, shutdown = TRUE)
rm(con_write)
