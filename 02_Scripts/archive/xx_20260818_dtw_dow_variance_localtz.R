suppressPackageStartupMessages({
  library(duckdb); library(DBI); library(glue); library(dplyr); library(lubridate)
})

con <- dbConnect(duckdb::duckdb())
dbExecute(con, "INSTALL quack; LOAD quack;")
dbExecute(con, glue(
  "ATTACH 'quack:localhost' AS remote_db (TYPE quack, TOKEN '{Sys.getenv('DUCKDB_QUACK_TOKEN')}')"
))
dbExecute(con, "USE remote_db;")

raw <- dbGetQuery(con, "
  SELECT time, checkpoint, wait_time
  FROM tsa_wait_times
  WHERE airport = 'DTW' AND checkpoint IN ('Evans', 'McNamara')
") |>
  as_tibble() |>
  mutate(time = force_tz(time, tzone = "UTC"),
         time_local = with_tz(time, tzone = "America/Detroit"))

cat("---- Local-time range covered ----\n")
print(range(raw$time_local))
cat("\n---- Row counts per checkpoint ----\n")
print(count(raw, checkpoint))

profile <- raw |>
  mutate(dow = wday(time_local, label = TRUE, abbr = TRUE, week_start = 7),
         hr  = hour(time_local)) |>
  group_by(checkpoint, dow, hr) |>
  summarise(
    n = n(),
    n_distinct_vals = n_distinct(wait_time),
    mean_wait = round(mean(wait_time, na.rm = TRUE), 1),
    min_wait = min(wait_time, na.rm = TRUE),
    max_wait = max(wait_time, na.rm = TRUE),
    n_na = sum(is.na(wait_time)),
    .groups = "drop"
  ) |>
  arrange(checkpoint, dow, hr)

print(as.data.frame(profile), row.names = FALSE)

dbDisconnect(con, shutdown = TRUE)
