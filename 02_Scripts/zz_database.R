# Install Packages ----

# install.packages(c("RSQLite", "nanoparquet", "duckdb", "duckplyr", "DBI"))

## Access Libraries to Project ----
library(RSQLite, verbose = F)
# library(duckdb, verbose = F)
# library(duckplyr, verbose = F)
library(DBI, verbose = F)
library(here, verbose = F)
library(nanoparquet, verbose = F)

here::here()

# TSA Database ----

## Create Database ----

# Create TSA Database DuckDB
# con <- dbConnect(duckdb(), dbdir = "01_Data/tsa_app.duckdb", read_only = FALSE)

# Create TSA Database SQLite
sqlite_db <- dbConnect(RSQLite::SQLite(), "01_Data/tsa_app.db")


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
temp_airports <- nanoparquet::read_parquet(here::here('01_Data', 'airports.parquet'))

dbWriteTable(conn = sqlite_db, name = "airports", value = temp_airports, 
             overwrite = TRUE)

rm(temp_airports)

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


# View tables
# dbGetQuery(sqlite_db, "SHOW TABLES;")
# dbListTables(sqlite_db)


# Testing Queries
# dbGetQuery(sqlite_db, "SELECT airport, count(airport) as obs_count FROM tsa_wait_times GROUP BY airport;")


# Edit Queries
# dbSendQuery(sqlite_db, "INSERT INTO airport_sites (airport, website) airport_sites VALUES (
#             'JFK', 'https://www.jfkairport.com',
#             'LGA', 'https://www.laguardiaairport.com');")
# dbSendQuery(sqlite_db, "DELETE FROM tsa_wait_times WHERE airport = 'LGA';")


# Disconnect from Database ----
DBI::dbDisconnect(sqlite_db, shutdown = TRUE)
rm(sqlite_db)
