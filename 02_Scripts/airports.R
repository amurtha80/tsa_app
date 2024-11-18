## Packages ----

#### Install Packages
# install.packages(c("dplyr", "nanoparquet", "tibble"))

library(nanoparquet)
library(dplyr)
library(tibble) 

## Data Schema ----

# Grabbing the raw data from the following link and saving as a parquet file
# https://raw.githubusercontent.com/jpatokal/openflights/master/data/airports.dat

# Schema
#   Name              Type          Notes
#   Airport_ID        numeric()     Unique OpenFlights identifier for this airport.
#   Airport_Name      character()   Name of airport. May or may not contain the City name.
#   Airport_City      character()   Main city served by airport. May be spelled differently from Name.
#   Airport_Country   character()   Country or territory where airport is located. See Countries to cross-reference to ISO 3166-1 codes.
#   IATA_Code         character()   3-letter IATA code. Null if not assigned/unknown.
#   ICAO_Code         character()   4-letter ICAO code. Null if not assigned.
#   Latitude          numeric()     Decimal degrees, usually to six significant digits. Negative is South, positive is North.
#   Longitude         numeric()     Decimal degrees, usually to six significant digits. Negative is West, positive is East.
#   Altitude          numeric()     In feet.
#   Timezone          numeric()     Hours offset from UTC. Fractional hours are expressed as decimals, eg. India is 5.5.
#   DST               character()   Daylight savings time. One of E (Europe), A (US/Canada), S (South America), O (Australia), Z (New Zealand), N (None) or U (Unknown). See also: Help: Time
#   TZ_db_Timezone    character()   Timezone in "tz" (Olson) format, eg. "America/Los_Angeles".
#   Type              character()   Type of the airport. Value "airport" for air terminals, "station" for train stations, "port" for ferry terminals and "unknown" if not known. In airports.csv, only type=airport is included.
#   Source            character()   Source of this data. "OurAirports" for data sourced from OurAirports, "Legacy" for old data not matched to OurAirports (mostly DAFIF), "User" for unverified user contributions. In airports.csv, only source=OurAirports is included.

# airports <- tibble(
#   Airport_ID      = numeric(),
#   Airport_Name    = character(),
#   Airport_City    = character(),
#   Airport_Country = character(),
#   IATA_Code       = character(),
#   ICAO_code       = character(),
#   Latitude        = numeric(),
#   Longitude       = numeric(),
#   Altitude        = numeric(),
#   Timezone        = numeric(),
#   DST             = character(),
#   TZ_db_Timezone  = character(),
#   Type            = character(),
#   Source          = character()
# )

names <- c("Airport_ID", "Airport_Name", "Airport_City", "Airport_Country", 
           "IATA_Code", "ICAO_Code", "Latitude", "Longitude", "Altitude", "Timezone",
           "DST", "TZ_db_Timezone", "Type", "Source")

## Import Data ----

# URL: https://raw.githubusercontent.com/jpatokal/openflights/master/data/airports.dat
url <- "https://raw.githubusercontent.com/jpatokal/openflights/master/data/airports.dat"

temp <- tibble(read.csv(url, header = FALSE))
airports <- temp
airports <- airports |> setNames(names)


## Cleanup ----

# Remove '\N' data in various columns and replace with ""
airports <- airports |> 
  mutate(IATA_Code = case_when(IATA_Code == "\\N" ~ "", TRUE ~ IATA_Code),
         ICAO_Code = case_when(ICAO_Code == '\\N' ~ "", TRUE ~ ICAO_Code),
         TZ_db_Timezone = case_when(TZ_db_Timezone == "\\N" ~ "", TRUE ~ TZ_db_Timezone),
         Timezone = case_when(Timezone == '\\N' ~ NA, TRUE ~ Timezone),
         DST = case_when(DST == '\\N' ~ "", TRUE ~ DST))

## Write Data Out ----

# Write to Parquet
nanoparquet::write_parquet(airports, "02_data/airports.parquet")

## Cleanup ----

# Remove Objects
rm(url)
rm(temp)
rm(airports)
rm(names)
