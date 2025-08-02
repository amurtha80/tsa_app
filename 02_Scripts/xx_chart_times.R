# Install Packages ----
# install.packages(c("duckdb", "DBI", "here", "dplyr", "ggplot2", "svglite"
#                     "lubridate", "hms",  "rstudioapi", "glue", "ggrounded"))
# install.packages("RSQLite")

## Access Libraries to Project ----
library(duckdb, verbose = F, quietly = T, warn.conflicts = F)
# library(RSQLite, verbose = F, quietly = T, warn.conflicts = F)
library(DBI, verbose = F, quietly = T, warn.conflicts = F)
library(here, verbose = F, quietly = T, warn.conflicts = F) |> 
  suppressMessages()
library(dplyr, verbose = F, quietly = T, warn.conflicts = F)
library(ggplot2, verbose = F, quietly = T, warn.conflicts = F)
library(svglite, verbose = F, quietly = T, warn.conflicts = F)
library(ggrounded, verbose = F, quietly = T, warn.conflicts = F)
library(lubridate, verbose = F, quietly = T, warn.conflicts = F)
library(hms, verbose = F, quietly = T, warn.conflicts = F)
library(rstudioapi, verbose = F, quietly = T, warn.conflicts = F)
library(glue, verbose = F, quietly = T, warn.conflicts = F)


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
  tsa_app_test <- dbConnect(duckdb(), dbdir = "01_Data/tsa_app_test.duckdb", read_only = FALSE)

  # Grab Table from database
  temp <- tbl(tsa_app_test, "tsa_wait_times") |>
    collect() |> 
    # Filter to last 365 days from most recent date
    filter(date >= max(date)-365) |> 
    # Create bucket time and weekday fields
    # mutate(bucket_time = as.POSIXct(lubridate::ceiling_date(time, "15 mins")),
    mutate(checkpoint = toupper(checkpoint),
           bucket_time = hms::as_hms(lubridate::ceiling_date(time, "15 mins")),
           weekday = lubridate::wday(time, label = TRUE, abbr = TRUE)) |>
    # Group by airport, checkpoint, weekday, and bucket time
    group_by(airport, checkpoint, weekday, bucket_time) |>
    # Create Summary variables, avereage and maximum
    summarize(avg_time_std = ceiling(mean(wait_time)),
              max_time_std = max(wait_time),
              avg_time_tsa_precheck = ceiling(mean(wait_time_pre_check)),
              max_time_tsa_precheck = max(wait_time_pre_check),
              avg_time_clear = ceiling(mean(wait_time_clear)),
              max_time_clear = max(wait_time_clear)) |> 
    suppressMessages()


  # Push temp dataframe to database table
  dbWriteTable(tsa_app_test, "tsa_wait_time_summ", temp, overwrite = TRUE)

#
## to pretend Shiny for now... RStudio api inputs
  location <- rstudioapi::showPrompt(title = "Airport Selection", message = "Please enter the 3 letter airport code of your desired airport (e.g. Atlanta Airport = ATL)") |> 
    base::toupper()
  checkpnt <- rstudioapi::showPrompt(title = "Checkpoint Selection", message = "Please enter the name of the checkpoint you are wanting to use") |> 
    base::toupper()
  dayOfWeek <- rstudioapi::showPrompt(title = "Day of Week", message = "Please Select Day of Week, Abbreviated (e.g. Sun, Mon)")
  timeOfDay <- rstudioapi::showPrompt(title = "Time of Day", message = "Please select time of Day in 15 Minute Intervals (hh:mm:00)") |> 
    hms::as_hms()

  start_time <- hms::as_hms(as.POSIXct(timeOfDay, tz = "EST") - hours(1))
  end_time <- hms::as_hms(as.POSIXct(timeOfDay, tz = "EST") + hours(1))
  
  # TODO - Solve bucket_time == between(lubridate::as.period(timeOfDay), start_time, end_time)
  temp_selection <- temp |> filter(airport == location, 
                                   checkpoint == checkpnt, 
                                   weekday == dayOfWeek, 
                                   bucket_time >= start_time & bucket_time <= end_time) |> 
    mutate(highlight = ifelse(bucket_time == bucket_time[5], "Central", "Other"),
           # bucket_time = factor(bucket_time, levels = bucket_time),
           bucket_time = format(as.POSIXlt(bucket_time), "%H:%M") |> factor(),
           labelColor = ifelse(highlight == "Central", "white", "black"))
  
plotTitle <- glue("Average Minutes for {checkpnt} Checkpoint \nat {location} on {dayOfWeek} at {timeOfDay}")
  
# plot bar chart
  ## TODO how do I combo plot with max
chart <- ggplot(temp_selection, aes(x = bucket_time, y = avg_time_std, fill = highlight)) + 
            ## TODO how to center selected value on bar chart
            geom_col_rounded(width = 0.9, position = position_dodge(), show.legend = FALSE,
              aes(fill = highlight)) +  #Rounded corners (ggplot2 v3.4.0+)
            geom_text(aes(label = round(avg_time_std, 1), color = labelColor), 
                      vjust = 1.3,  # Push text just below the top inside the bar
                      size = 3.5,
                      fontface = "bold") +
            geom_point(aes(y = max_time_std), shape = 21, size = 3, fill = "skyblue3", color = "skyblue3") +
            geom_text(aes(y = max_time_std, label = round(max_time_std, 1), color = "black"),
                      vjust = -1,
                      size = 3.5,
                      fontface = "bold") +
            scale_color_identity() +
            scale_fill_manual(values = c("Central" = "skyblue3", "Other" = "darkgray")) +
            labs(title = plotTitle,
                 x = NULL,  # Remove x-axis title for minimal look
                 y = "Average Minutes", 
                 fontface = "bold") +
            theme_minimal() +
            theme(plot.title = element_text(hjust = 0.5),
                axis.text.x = element_text(angle = 0, hjust = 0.5, vjust = 10, face = "bold"),  # Rotate x-axis labels
                panel.grid.major.x = element_blank(),  # Remove vertical grid lines
                panel.grid.minor = element_blank()) +
            annotate("text", 
                     x = 1,  # Adjust as needed
                     y = max(temp_selection$max_time_std) + 2, 
                     label = "🔵 = Max Wait Time", 
                     color = "skyblue3", 
                     size = 4,
                     hjust = 0)

chart
ggsave("tsa_wait_time_JFK_req.svg", plot = chart, path = here::here(),
       width = 4, height = 5, units = "in", dpi = 300)

# Script Cleanup
  # Remove temp table
  rm(temp)

  # Disconnect from database
  dbDisconnect(tsa_app_test, shutdown = TRUE)
  # Remove database object
  rm(tsa_app_test)
  # Garbage Collection
  gc()
  