# Install Packages ----
# install.packages(c("RSQLite", "DBI", "here", "dplyr", "ggplot2"))


## Access Libraries to Project ----
library(RSQLite, verbose = F)
library(DBI, verbose = F)
library(here, verbose = F)
library(dplyr, verbose = F)
library(ggplot2, verbose = F)


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