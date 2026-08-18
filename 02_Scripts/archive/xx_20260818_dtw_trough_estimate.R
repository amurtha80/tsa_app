suppressPackageStartupMessages({
  library(duckdb); library(DBI); library(glue); library(dplyr); library(lubridate); library(purrr)
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
         time_local = with_tz(time, tzone = "America/Detroit"),
         dow = wday(time_local, label = TRUE, abbr = TRUE, week_start = 7),
         hr  = hour(time_local))

hourly <- raw |>
  group_by(checkpoint, dow, hr) |>
  summarise(mean_wait = round(mean(wait_time, na.rm = TRUE), 2), .groups = "drop")

thresholds <- hourly |>
  group_by(checkpoint) |>
  summarise(q25 = quantile(mean_wait, 0.25), .groups = "drop")

# find longest contiguous run of hours (0-23, wrapping) below q25, per checkpoint x dow
find_quiet_run <- function(hrs_ordered, is_quiet_vec) {
  n <- length(is_quiet_vec)
  doubled <- c(is_quiet_vec, is_quiet_vec)
  best_len <- 0; best_start <- NA
  cur_len <- 0; cur_start <- NA
  for (i in seq_along(doubled)) {
    if (doubled[i]) {
      if (cur_len == 0) cur_start <- i
      cur_len <- cur_len + 1
      if (cur_len > best_len && cur_len <= n) { best_len <- cur_len; best_start <- cur_start }
    } else {
      cur_len <- 0
    }
  }
  if (best_len == 0) return(c(NA, NA))
  start_hr <- hrs_ordered[((best_start - 1) %% n) + 1]
  end_idx <- best_start + best_len - 1
  end_hr <- hrs_ordered[((end_idx - 1) %% n) + 1]
  c(start_hr, (end_hr + 1) %% 24)  # end = hour AFTER last quiet hour
}

summary_tbl <- hourly |>
  left_join(thresholds, by = "checkpoint") |>
  mutate(is_quiet = mean_wait <= q25) |>
  group_by(checkpoint, dow) |>
  arrange(hr, .by_group = TRUE) |>
  summarise(
    run = list(find_quiet_run(hr, is_quiet)),
    .groups = "drop"
  ) |>
  mutate(quiet_start = map_dbl(run, 1), quiet_end = map_dbl(run, 2)) |>
  select(-run)

print(as.data.frame(summary_tbl), row.names = FALSE)

dbDisconnect(con, shutdown = TRUE)
