# Install Packages ----

# install.packages(c("RSQLite", "nanoparquet", "duckdb", "duckplyr", "DBI"))

## Access Libraries to Project ----
# library(RSQLite, verbose = F)
# library(duckdb, verbose = F)
# library(duckplyr, verbose = F)
# library(DBI, verbose = F)
# library(here, verbose = F)
# library(nanoparquet, verbose = F)

# here::here()

# TSA Database ----

## Create Database ----

# Create TSA Database DuckDB - write connection
# con_write <- dbConnect(duckdb(), dbdir = "01_Data/tsa_app.duckdb", read_only = FALSE)


# Create TSA Database DuckDB - read connection
# con_read <- dbConnect(duckdb(), dbdir = "01_Data/tsa_app.duckdb", read_only = TRUE)


# Create TSA Database SQLite
# sqlite_db <- dbConnect(RSQLite::SQLite(), "01_Data/tsa_app.db")


## SQLite Database Settings ----
# Update SQLite Database read/write settings to have concurrency
# dbSendQuery(sqlite_db, "PRAGMA journal_mode=WAL;")
# Update SQLite Database read/write settings to remove concurrency
# dbSendQuery(sqlite_db, "PRAGMA journal_mode=delete;")


## Create Tables ----


# Create Airports Table
dbExecute(sqlite_db, "CREATE TABLE airports(
  Airport_ID INTEGER,
  Airport_Name  VARCHAR,
  Airport_City  VARCHAR,
  Airport_Country VARCHAR,
  IATA_Code VARCHAR,
  ICAO_code VARCHAR,
  Latitude  DOUBLE,
  Longitude DOUBLE,
  Altitude INTEGER,
  Timezone DOUBLE,
  DST VARCHAR,
  TZ_db_Timezone VARCHAR,
  Type VARCHAR,
  Source VARCHAR
);")


# Insert Parquet file into Airports Table - DuckDB
# dbExecute(sqlite_db, 
#           "INSERT INTO airports SELECT * FROM read_parquet('01_Data/airports.parquet');")

# Insert Parquet file into Airports Table - SQLite
# temp_airports <- nanoparquet::read_parquet(here::here('01_Data', 'airports.parquet'))

# dbWriteTable(conn = sqlite_db, name = "airports", value = temp_airports, 
#              overwrite = TRUE)
# 
# rm(temp_airports)

# Create TSA Wait Times Table
# FOREIGN KEY (airport) REFERENCES airports (IATA_Code)7
dbExecute(sqlite_db, "CREATE TABLE tsa_wait_times(
          airport VARCHAR,
          checkpoint VARCHAR,
          datetime DATETIME,
          date DATE,
          time TIMESTAMP_S,
          timezone VARCHAR,
          holiday_travel BOOLEAN,
          wait_time INTEGER,
          wait_time_priority INTEGER,
          wait_time_pre_check INTEGER,
          wait_time_clear INTEGER
);")


# Create Airport Website Table
dbExecute(sqlite_db, "CREATE TABLE airport_sites(
          airport VARCHAR,
          website VARCHAR
);")


# Create Airport CheckPoint Hours of Operation
dbExecute(sqlite_db, "CREATE TABLE airport_checkpoint_hours(
          airport VARCHAR,
          timezone VARCHAR,
          checkpoint VARCHAR,
          open_time_gen TIMESTAMP_S,
          close_time_gen TIMESTAMP_S,
          open_time_prechk TIMESTAMP_S,
          close_time_prechk TIMESTAMP_S
);")


## View tables ----
dbGetQuery(sqlite_db, "SHOW TABLES;")
dbListTables(sqlite_db)


## Testing Queries ----
# Query for observation count by airport
# dbGetQuery(sqlite_db, "SELECT airport, count(airport) as obs_count FROM tsa_wait_times GROUP BY airport;") 


# Query for most recent observations from most recent run
# SQLite expresses date calculation as DATE('now', '-1 day'
# dbGetQuery(sqlite_db,
# "SELECT a.airport, a.datetime, count(*) as obs from tsa_wait_times a INNER JOIN
# (SELECT airport, datetime FROM tsa_wait_times WHERE datetime >= CURRENT_DATE - INTERVAL 1 DAY
# GROUP BY airport) b
# ON a.airport = b.airport AND a.datetime = b.datetime GROUP BY a.airport, a.datetime
# ORDER BY a.airport;")

# DuckDb Implementation of Same Query
# dbGetQuery(con_read,
#            "SELECT airport, date, count (*) as obs FROM tsa_wait_times
#             WHERE date >= ((SELECT MAX(date) FROM tsa_wait_times)-1)
#             GROUP BY airport, date ORDER BY airport;")


# Query for looking at a specific airport, specific terminal, specific day, average time
# DuckDB Implementation
# The end range for the hour requested is BETWEEN 9 AND 9 because EXTRACT HOUR only
# gives whole hour values, not minutes or seconds, so XX:59:59 is still the same hour
# as XX:00:00
# dbGetQuery(con_read,
#           "SELECT airport, checkpoint, date, EXTRACT(HOUR FROM time) as hour,
#            FLOOR(EXTRACT(MINUTE FROM time) / 15) *15 as minute_interval, 
#            CEIL(AVG(wait_time)) as avg_wait_time
#            FROM tsa_wait_times WHERE airport = 'ATL' AND checkpoint = 'INT''L MAIN'
#            AND EXTRACT(DOW FROM date) = 6 AND (EXTRACT(HOUR FROM time) BETWEEN 10 AND 10)
#            GROUP BY airport, checkpoint, date, hour, minute_interval
#            ORDER BY airport, checkpoint, date, minute_interval;")


# Query for looking at a specific airport, specific terminal, specific day, max time
# DuckDB Implementation
# dbGetQuery(con_read,
#            "SELECT airport, checkpoint, date, EXTRACT(HOUR FROM time) as hour,
#            FLOOR(EXTRACT(MINUTE FROM time) / 15) *15 as minute_interval, 
#            CEIL(MAX(wait_time)) as max_wait_time
#            FROM tsa_wait_times WHERE airport = 'ATL' AND checkpoint = 'INT''L MAIN'
#            AND EXTRACT(DOW FROM date) = 6 AND (EXTRACT(HOUR FROM time) BETWEEN 10 AND 10)
#            GROUP BY airport, checkpoint, date, hour, minute_interval
#            ORDER BY airport, checkpoint, date, minute_interval;")

## Edit Queries ----
# dbSendQuery(sqlite_db, "INSERT INTO airport_sites (airport, website) VALUES 
#             ('ATL', 'https://www.atl.com/times/'),
#             ('CLT', 'https://api.cltairport.mobi/checkpoint-queues/current'),
#             ('DCA', 'https://www.flyreagan.com/travel-information/security-information'),
#             ('DEN', 'https://www.flydenver.com/security/'),
#             ('IAH', 'https://www.fly2houston.com/iah/security'),
#             ('JFK', 'https://www.jfkairport.com'),
#             ('LGA', 'https://www.laguardiaairport.com'),
#             ('MCO', 'https://flymco.com/security/'),
#             ('MIA', 'https://www.miami-airport.com/tsa-waittimes.asp'),
#             ('MSP', 'https://www.mspairport.com/airport/security-screening/security-wait-times');")
# dbSendQuery(sqlite_db, "DELETE FROM tsa_wait_times WHERE airport = 'LGA';")


## Disconnect from Database ----
DBI::dbDisconnect(sqlite_db, shutdown = TRUE)
rm(conn_write)
rm(conn_read)
rm(sqlite_db)
