# Install Packages ----
# install.packages(c("duckdb", "RSQLite", "DBI", "here", "dplyr", "ggplot2",
                    # "lubridate", "rstudioapi"))


## Access Libraries to Project ----
library(duckdb, verbose = F, quietly = T, warn.conflicts = F)
# library(RSQLite, verbose = F, quietly = T, warn.conflicts = F)
library(DBI, verbose = F, quietly = T, warn.conflicts = F)
library(here, verbose = F, quietly = T, warn.conflicts = F)
library(dplyr, verbose = F, quietly = T, warn.conflicts = F)
library(ggplot2, verbose = F, quietly = T, warn.conflicts = F)
library(lubridate, verbose = F, quietly = T, warn.conflicts = F)
library(rstudioapi, verbose = F, quietly = T, warn.conflicts = F)


## Access working directory ----
here::here()

# TODO ----
# 1. Potentially use `tibbletime` package function collapse_by to get into 
#     15 minute groupings. Also lubridate's ceiling_date function might work
#     well (https://forum.posit.co/t/how-to-aggregate-15-min-data-to-30-45-and-so-on/136554)
# 2. Take 15 minute time intervals and also group by airport and checkpoint to get 
#     15 minute intervals by airport
# 3. Plot bar chart of 15 minute intervals with a 60 minute buffer on each side,
#     totaling 9 bars in the bar chart. This is an average time for all time
#     slots for that day/time combination
# 4. Plot horizontal line in 15 minute intervals as the maximum time with a 60 
#     minute buffer on each side
# 5. Update database.R script to include new table for analysis of timeseries data

## Query data from tsa_wait_times table, group by airport and day of week, and 
## then aggregate by 15 minute time frame


  # Create TSA Database DuckDB - read connection
  con_read_test <- dbConnect(duckdb(), dbdir = "01_Data/tsa_app_test.duckdb", read_only = TRUE)

  # Grab Table from database
  temp <- tbl(con_read_test, "tsa_wait_times") |>
    collect() |> 
    # Filter to last 365 days from most recent date
    filter(date >= max(date)-365) |> 
    # Create bucket time and weekday fields
    mutate(bucket_time = hms::as_hms(lubridate::ceiling_date(time, "15 mins")),
           weekday = lubridate::wday(time, label = TRUE, abbr = TRUE)) |>
    # Group by airport, checkpoint, weekday, and bucket time
    group_by(airport, checkpoint, weekday, bucket_time) |>
    # Create Summary variables, avereage and maximum
    summarize(avg_time_std = ceiling(mean(wait_time)),
              max_time_std = max(wait_time),
              avg_time_tsa_precheck = ceiling(mean(wait_time_pre_check)),
              max_time_tsa_precheck = max(wait_time_pre_check),
              avg_time_clear = ceiling(mean(wait_time_clear)),
              max_time_clear = max(wait_time_clear))


  # Push temp dataframe to database table
  dbWriteTable(con_read_test, "tsa_wait_time_summ", temp, overwrite = TRUE)

#
## to pretend Shiny for now... RStudio api inputs
  location <- rstudioapi::showPrompt(title = "Airport Selection", message = "Please enter the 3 letter airport code of your desired airport (e.g. Atlanta Airport = ATL)") |> 
    base::toupper()
  checkpnt <- rstudioapi::showPrompt(title = "Checkpoint Selection", message = "Please enter the name of the checkpoint you are wanting to use") |> 
    base::toupper()
  dayOfWeek <- rstudioapi::showPrompt(title = "Day of Week", message = "Please Select Day of Week, Abbreviated (e.g. Sun, Mon)")
  timeOfDay <- rstudioapi::showPrompt(title = "Time of Day", message = "Please select time of Day in 15 Minute Intervals (hh:mm:00)") |> 
    hms::as_hms()

  start_time <- timeOfDay - hours(1)
  end_time <- timeOfDay + hours(1)
  
  # TODO - Solve bucket_time == between(lubridate::as.period(timeOfDay), start_time, end_time)
  temp_selection <- temp |> filter(airport == location, checkpoint == checkpnt, weekday == dayOfWeek, bucket_time >= (timeOfDay - hours(1)) & bucket_time <= (timeOfDay + hours(1)))
  
##
## plot bar chart
## chart <- ggplot(temp_selection, aes(x = bucket_time, y = avg_time_std)) + ## how do I combo plot with max
##            geom_col(<attributes for average time>) +
##            geom_point(<attributes for max time>) +
##            ## TODO how to center selected value on bar chart
##            scale_x_continuous(min 60 min before selected, max 60 min after selected) + 
##            coordinates +
##            theme +
##            misc

# Script Cleanup
  # Remove temp table
  rm(temp)

  # Disconnect from database
  dbDisconnect(tsa_app_test, shutdown = TRUE)
  # Remove database object
  rm(con_read_test)
  # Garbage Collection
  gc()