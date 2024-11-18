#Current Script working

# Install Packages ----

# install.packages(c("duckdb", "duckplyr", "DBI"))

## Access Libraries to Project ----
library(duckdb)
library(duckplyr)
library(DBI)


# TSA Database ----

## Create Database ----

# Create TSA Database
con <- dbConnect(duckdb(), dbdir = "02_Data/tsa_app.duckdb", read_only = FALSE)


## Create Tables ----


# Create Airports Table
dbExecute(con, "CREATE TABLE airports(
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


# Insert Parquet file into Airports Table
dbExecute(con, "INSERT INTO airports SELECT * FROM read_parquet('02_Data/airports.parquet');")


# Create TSA Wait Times Table
dbExecute(con, "CREATE TABLE tsa_wait_times(
          airport VARCHAR,
          checkpoint VARCHAR,
          datetime DATETIME,
          date DATE,
          time TIMESTAMP_S,
          timezone VARCHAR,
          wait_time INTEGER,
          wait_time_pre_check INTEGER
);")


# Create Airport Website Table
dbExecute(con, "CREATE TABLE airport_sites(
          airport VARCHAR,
          website VARCHAR
);")


# View tables
dbGetQuery(con, "SHOW TABLES;")


# Testing Queries
# dbGetQuery(con, "SELECT airport, count(airport) as obs_count FROM tsa_wait_times GROUP BY airport;")


# Edit Queries
# dbSendQuery(con, "INSERT INTO airport_sites (airport, website) airport_sites VALUES ('LGA', 'https://www.laguardiaairport.com');")
# dbSendQuery(con, "DELETE FROM tsa_wait_times WHERE airport = 'LGA';")


# Disconnect from Database ----
DBI::dbDisconnect(con, shutdown = TRUE)
rm(con)
