# Install Packages ----
# install.packages(c("RSQLite", "DBI", "here", "dplyr", "ggplot2"))


## Access Libraries to Project ----
library(RSQLite, verbose = F, quietly = T, warn.conflicts = F)
library(DBI, verbose = F, quietly = T, warn.conflicts = F)
library(here, verbose = F, quietly = T, warn.conflicts = F)
library(dplyr, verbose = F, quietly = T, warn.conflicts = F)
library(ggplot2, verbose = F, quietly = T, warn.conflicts = F)
library(lubridate, verbose = F, quietly = T, warn.conflicts = F)


## Access working directory ----
here::here()

# TODO ----
# 1. Potentially use `tibbletime` package function collapse_by to get into 
#     15 minute groupings. Also lubridate's ceiling_date function might work
#     well (https://forum.posit.co/t/how-to-aggregate-15-min-data-to-30-45-and-so-on/136554)
# 2. Take 15 minute time intervals and also group by airport to get 15 minute
#     intervals by airport
# 3. Plot bar chart of 15 minute intervals with a 60 minute buffer on each side,
#     totaling 9 bars in the bar chart. This is an average time for all time
#     slots for that day/time combination
# 4. Plot horizontal line in 15 minute intervals as the maximum time with a 60 
#     minute buffer on each side

## Query data from tsa_wait_times table, group by airport and day of week, and 
## then aggregate by 15 minute timeframe
##
##
## temp <- <dataframe and code> |> 
## mutate(bucket_time = ceiling_date(time, "15 mins")) |>
##  group_by(airport, weekday, bucket_time) |> 
##  summarize(avg_time_std = mean(wait_time),
##            max_time_std = max(wait_time),
##            avg_time_tsa_precheck = mean(wait_time_tsa_precheck),
##            max_time_tsa_precheck = max(wait_time_tsa_precheck),
##            avg_time_clear = mean(wait_time_clear),
##            max_time_clear = max(wait_time_clear))
##
##
## push temp dataframe to database table
##
##  library(RSQLite, verbose = F, quietly = T, warn.conflicts = F)
##
##
## to pretend Shiny for now... RStudio api inputs
##  dayOfWeek <- rstudioapi::show_prompt(title = "Day of Week", message = "Please Select Day of Week")
##  timeOfDay <- rstudioapi::show_prompt(title = "Time of Day", message = "Please select time of Day")
##
##
## plot barchart
## chart <- ggplot(aes(x = bucket_time, y = avg_time_std)) + ## how do I combo plot with max
##            geom_col(<attributes for average time>) +
##            geom_point(<attributes for max time>) +
##            ## TODO how to center selected value on barchart
##            scale_x_continuous(min 60 min before selected, max 60 min after selected) + 
##            coordinates +
##            theme