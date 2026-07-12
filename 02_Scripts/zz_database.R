# Install Packages ----

# install.packages(c("RSQLite", "nanoparquet", "duckdb", "duckplyr", "DBI", "here", "glue"))

## Access Libraries to Project ----
library(duckdb, verbose = F)
library(DBI, verbose = F)
library(here, verbose = F)
library(glue, verbose = F)

here::here()

# TSA Database ----

## Quack Server ----
# This script is the persistent Quack server (Task Scheduler job
# tsa_app_quack_server, trigger "At log on"). It becomes the sole holder of
# 01_Data/tsa_app.duckdb and serves every other connection (scraper
# orchestrator, nightly build/validate scripts) over quack:localhost. Every
# other connection MUST go through Quack -- if any script keeps a direct file
# connection alongside this, Quack's server just becomes another connection
# fighting for the same exclusive lock, and nothing is gained.
#
# Token: DUCKDB_QUACK_TOKEN in .Renviron. Falls back to a fixed default so
# this script still runs standalone if that var isn't set.

# Create TSA Database DuckDB - write connection (server holds this open)
con_write <- dbConnect(duckdb::duckdb(),
                        dbdir = here::here("01_Data", "tsa_app.duckdb"),
                        read_only = FALSE)

## DuckDB Database Settings ----

# Confirm engine version supports Quack (requires DuckDB engine 1.5.3+)
engine_version <- dbGetQuery(con_write, "PRAGMA version;")
print(engine_version)

# FORCE INSTALL (not plain INSTALL) -- a plain INSTALL can silently reuse a
# stale/cached extension and leave quack_serve unregistered even though
# INSTALL/LOAD report no error.
dbExecute(con_write, "FORCE INSTALL quack; LOAD quack;")

quack_status <- dbGetQuery(con_write,
  "SELECT extension_name, loaded, installed FROM duckdb_extensions() WHERE extension_name = 'quack';")
print(quack_status)
if (nrow(quack_status) == 0 || !isTRUE(quack_status$loaded)) {
  stop("quack extension did not load -- check engine_version above is >= 1.5.3")
}

quack_token <- Sys.getenv("DUCKDB_QUACK_TOKEN", "flyasap_quack_test_token")

# Start Quack background listener (non-blocking -- returns immediately)
dbExecute(con_write, glue::glue(
  "CALL quack_serve('quack:localhost', token := '{quack_token}')"
))

print(glue::glue("quack server started on tsa_app.duckdb at ",
                  format(Sys.time(), "%a %b %d %X %Y")))


## Create Tables ----
## One-time schema setup -- already run against the production database.
## Left here as documentation only; do not uncomment against tsa_app.duckdb.

# Create Airports Table
# dbExecute(con_write, "CREATE TABLE airports(
#   Airport_ID INTEGER,
#   Airport_Name  VARCHAR,
#   Airport_City  VARCHAR,
#   Airport_Country VARCHAR,
#   IATA_Code VARCHAR,
#   ICAO_code VARCHAR,
#   Latitude  DOUBLE,
#   Longitude DOUBLE,
#   Altitude INTEGER,
#   Timezone DOUBLE,
#   DST VARCHAR,
#   TZ_db_Timezone VARCHAR,
#   Type VARCHAR,
#   Source VARCHAR
# );")


# Insert Parquet file into Airports Table - DuckDB
# dbExecute(con_write, 
#           "INSERT INTO airports SELECT * FROM read_parquet('01_Data/airports.parquet');")

# Insert Parquet file into Airports Table - SQLite
# temp_airports <- nanoparquet::read_parquet(here::here('01_Data', 'airports.parquet'))

# dbWriteTable(conn = con_write, name = "airports", value = temp_airports, 
#              overwrite = TRUE)
# 
# rm(temp_airports)

# Create TSA Wait Times Table
# FOREIGN KEY (airport) REFERENCES airports (IATA_Code)7
# dbExecute(con_write, "CREATE TABLE tsa_wait_times(
#           airport VARCHAR,
#           checkpoint VARCHAR,
#           datetime DATETIME,
#           date DATE,
#           time TIMESTAMP_S,
#           timezone VARCHAR,
#           holiday_travel BOOLEAN,
#           wait_time INTEGER,
#           wait_time_priority INTEGER,
#           wait_time_pre_check INTEGER,
#           wait_time_clear INTEGER
# );")


# Create TSA Wait Time Summary Table
# Lives in 01_Data/tsa_app_summ.duckdb (separate DB from tsa_app.duckdb)
# Written nightly by xx_build_summary_db.R via dbWriteTable(..., overwrite = TRUE)
# One row per airport / checkpoint / weekday / bucket_time (15-min intervals)
# Read-only source for the Shiny app (app.R)
# NOTE: this block is documentation only — do not run against tsa_app.duckdb
# dbExecute(con_summ, "CREATE TABLE tsa_wait_time_summ(
#           airport VARCHAR,
#           checkpoint VARCHAR,
#           weekday VARCHAR,
#           bucket_time TIME,
#           avg_time_std DOUBLE,
#           max_time_std DOUBLE,
#           avg_time_tsa_precheck DOUBLE,
#           max_time_tsa_precheck DOUBLE,
#           avg_time_clear DOUBLE,
#           max_time_clear DOUBLE
# );")


# Create Airport Website Table
# dbExecute(con_write, "CREATE TABLE airport_sites(
#           airport VARCHAR,
#           website VARCHAR
# );")


# Create Airport CheckPoint Hours of Operation
# dbExecute(con_write, "CREATE TABLE airport_checkpoint_hours(
#           airport VARCHAR,
#           timezone VARCHAR,
#           checkpoint VARCHAR,
#           open_time_gen TIMESTAMP_S,
#           close_time_gen TIMESTAMP_S,
#           open_time_prechk TIMESTAMP_S,
#           close_time_prechk TIMESTAMP_S
# );")

# Updating to add new open/close times for clear checkpoints ----
# library(duckdb)
# library(DBI)
# library(here)
# 
# # Direct (non-Quack) connection -- only safe while tsa_app_quack_server is stopped
# con_write <- dbConnect(duckdb::duckdb(), dbdir = "01_Data/tsa_app.duckdb", read_only = FALSE)
# 
# # Confirm current schema before changing it
# print(dbGetQuery(con_write, "DESCRIBE airport_checkpoint_hours;"))
# 
# dbExecute(con_write, "ALTER TABLE airport_checkpoint_hours ADD COLUMN open_time_clear TIMESTAMP_S;")
# dbExecute(con_write, "ALTER TABLE airport_checkpoint_hours ADD COLUMN close_time_clear TIMESTAMP_S;")
# 
# # Confirm the change landed
# print(dbGetQuery(con_write, "DESCRIBE airport_checkpoint_hours;"))
# 
# DBI::dbDisconnect(con_write, shutdown = TRUE)
# rm(con_write)


# Populate PHL checkpoint hours ----
# Open/close times sourced from phl.org's wait-api.js (tHours/tPre objects),
# cross-checked against the displayed hours text on the checkpoint-hours page.
# Date part of each TIMESTAMP_S is the entry date, not a dummy anchor -- if
# PHL's hours change later, insert a new dated row rather than updating in
# place, so this table keeps a history. Downstream consumers should take the
# most recent row per (airport, checkpoint).
# dbExecute(con_write, "
#   INSERT INTO airport_checkpoint_hours
#     (airport, timezone, checkpoint, open_time_gen, close_time_gen, open_time_prechk, close_time_prechk)
#   VALUES
#     ('PHL', 'America/New_York', 'Terminal A-West 1', NULL, NULL, '2026-07-10 15:00:00', '2026-07-10 17:30:00'),
#     ('PHL', 'America/New_York', 'Terminal A-West 2', '2026-07-10 05:00:00', '2026-07-10 22:15:00', NULL, NULL),
#     ('PHL', 'America/New_York', 'Terminal A-East',   '2026-07-10 04:15:00', '2026-07-10 20:15:00', '2026-07-10 04:15:00', '2026-07-10 18:30:00'),
#     ('PHL', 'America/New_York', 'Terminal B',         '2026-07-10 03:30:00', '2026-07-10 21:15:00', NULL, NULL),
#     ('PHL', 'America/New_York', 'Terminal C',         NULL, NULL, '2026-07-10 04:15:00', '2026-07-10 20:00:00'),
#     ('PHL', 'America/New_York', 'Terminal D/E',       '2026-07-10 03:00:00', '2026-07-10 23:25:00', '2026-07-10 03:45:00', '2026-07-10 20:00:00'),
#     ('PHL', 'America/New_York', 'Terminal F',          '2026-07-10 04:30:00', '2026-07-10 21:15:00', NULL, NULL);
# ")


# Add entry_timestamp + correct MIA/DEN hours (2026-07-12 checkpoint-hours re-verification) ----
# The append-only-history design above has a real gap: the TIMESTAMP_S date
# part is just an entry-date anchor with no time-of-day meaning, so a
# same-day correction ties with the row it's meant to supersede and
# xx_build_summary_DB.R's "take the most recent row" join can't tell them
# apart (verified this would silently pick the OLD row before this fix).
# Added a dedicated entry_timestamp column (real write-time) so ranking is
# unambiguous even for same-day corrections. Existing rows are backfilled
# using their own anchor date at midnight, which always sorts before a
# correction's CURRENT_TIMESTAMP (written later the same day).
#
# Direct (non-Quack) connection -- only safe while tsa_app_quack_server is
# stopped (same requirement as the CLEAR-columns block above). Executed
# 2026-07-12, ~2 min after a scraper run to minimize the write-failure window.
# library(duckdb)
# library(DBI)
#
# con_write <- dbConnect(duckdb::duckdb(), dbdir = "01_Data/tsa_app.duckdb", read_only = FALSE)
#
# dbExecute(con_write, "ALTER TABLE airport_checkpoint_hours ADD COLUMN entry_timestamp TIMESTAMP;")
#
# dbExecute(con_write, "
#   UPDATE airport_checkpoint_hours
#   SET entry_timestamp = CAST(COALESCE(open_time_gen, open_time_prechk, open_time_clear,
#                                        close_time_gen, close_time_prechk, close_time_clear)::DATE AS TIMESTAMP)
#   WHERE entry_timestamp IS NULL;
# ")
#
# # MIA checkpoint 2: DB had close 11:45 pm, official miami-airport.com/airport-security.asp
# # says 10:45 pm -- 1 hour conflict, corrected.
# dbExecute(con_write, "
#   INSERT INTO airport_checkpoint_hours
#     (airport, timezone, checkpoint, open_time_gen, close_time_gen, entry_timestamp)
#   VALUES
#     ('MIA', 'America/New_York', '2', '2026-07-12 03:30:00', '2026-07-12 22:45:00', CURRENT_TIMESTAMP);
# ")
#
# # DEN East/West: DB had asymmetric hours (East 3:00a-8:00p, West 3:30a-1:00a);
# # flydenver.com/security states both checkpoints share identical hours,
# # 3:00a-1:00a standard, 4:00a-8:45p PreCheck -- corrected both to match.
# dbExecute(con_write, "
#   INSERT INTO airport_checkpoint_hours
#     (airport, timezone, checkpoint, open_time_gen, close_time_gen, open_time_prechk, close_time_prechk, entry_timestamp)
#   VALUES
#     ('DEN', 'America/Denver', 'East Security', '2026-07-12 03:00:00', '2026-07-13 01:00:00', '2026-07-12 04:00:00', '2026-07-12 20:45:00', CURRENT_TIMESTAMP),
#     ('DEN', 'America/Denver', 'West Security', '2026-07-12 03:00:00', '2026-07-13 01:00:00', '2026-07-12 04:00:00', '2026-07-12 20:45:00', CURRENT_TIMESTAMP);
# ")
#
# DBI::dbDisconnect(con_write, shutdown = TRUE)
# rm(con_write)


## View tables ----
dbGetQuery(con_write, "SHOW TABLES;")
dbListTables(con_write)


## Testing Queries ----
# Query for observation count by airport
# dbGetQuery(con_write, "SELECT airport, count(airport) as obs_count FROM tsa_wait_times GROUP BY airport;") 


# Query for most recent observations from most recent run
# SQLite expresses date calculation as DATE('now', '-1 day'
# dbGetQuery(sqlite_db,
# "SELECT a.airport, a.datetime, count(*) as obs from tsa_wait_times a INNER JOIN
# (SELECT airport, datetime FROM tsa_wait_times WHERE datetime >= CURRENT_DATE - INTERVAL 1 DAY
# GROUP BY airport) b
# ON a.airport = b.airport AND a.datetime = b.datetime GROUP BY a.airport, a.datetime
# ORDER BY a.airport;")

# DuckDb Implementation of Same Query
# dbGetQuery(con_write,
#            "SELECT airport, date, count (*) as obs FROM tsa_wait_times
#             WHERE date >= ((SELECT MAX(date) FROM tsa_wait_times)-1)
#             GROUP BY airport, date ORDER BY airport;")


# Query for looking at a specific airport, specific terminal, specific day, average time
# DuckDB Implementation
# The end range for the hour requested is BETWEEN 9 AND 9 because EXTRACT HOUR only
# gives whole hour values, not minutes or seconds, so XX:59:59 is still the same hour
# as XX:00:00
# dbGetQuery(con_write,
#           "SELECT airport, checkpoint, date, EXTRACT(HOUR FROM time) as hour,
#            FLOOR(EXTRACT(MINUTE FROM time) / 15) *15 as minute_interval, 
#            CEIL(AVG(wait_time)) as avg_wait_time
#            FROM tsa_wait_times WHERE airport = 'ATL' AND checkpoint = 'INT''L MAIN'
#            AND EXTRACT(DOW FROM date) = 6 AND (EXTRACT(HOUR FROM time) BETWEEN 10 AND 10)
#            GROUP BY airport, checkpoint, date, hour, minute_interval
#            ORDER BY airport, checkpoint, date, minute_interval;")


# Query for looking at a specific airport, specific terminal, specific day, max time
# DuckDB Implementation
# dbGetQuery(con_write,
#            "SELECT airport, checkpoint, date, EXTRACT(HOUR FROM time) as hour,
#            FLOOR(EXTRACT(MINUTE FROM time) / 15) *15 as minute_interval, 
#            CEIL(MAX(wait_time)) as max_wait_time
#            FROM tsa_wait_times WHERE airport = 'ATL' AND checkpoint = 'INT''L MAIN'
#            AND EXTRACT(DOW FROM date) = 6 AND (EXTRACT(HOUR FROM time) BETWEEN 10 AND 10)
#            GROUP BY airport, checkpoint, date, hour, minute_interval
#            ORDER BY airport, checkpoint, date, minute_interval;")

## Edit Queries ----
# dbSendQuery(con_write, "INSERT INTO airport_sites (airport, website) VALUES 
#             ('ATL', 'https://www.atl.com/times/'),
#             ('CLT', 'https://api.cltairport.mobi/checkpoint-queues/current'),
#             ('DCA', 'https://www.flyreagan.com/travel-information/security-information'),
#             ('DEN', 'https://www.flydenver.com/security/'),
#             ('IAH', 'https://www.fly2houston.com/iah/security'),
#             ('JFK', 'https://www.jfkairport.com'),
#             ('LGA', 'https://www.laguardiaairport.com'),
#             ('MCO', 'https://flymco.com/security/'),
#             ('MIA', 'https://www.miami-airport.com/tsa-waittimes.asp'),
#             ('MSP', 'https://www.mspairport.com/airport/security-screening/security-wait-times'),
#             ('PDX', 'https://https://www.flypdx.com');")
# dbSendQuery(con_write, "DELETE FROM tsa_wait_times WHERE airport = 'LGA';")


## Keep Server Alive ----
## Do NOT dbDisconnect here -- this script IS the Quack server. Disconnecting
## con_write drops the file lock and kills quack_serve for every attached
## client. Launched non-interactively (Task Scheduler, trigger "At log on"),
## so it needs its own keep-alive loop to stay resident.
repeat {
  Sys.sleep(30)
}
