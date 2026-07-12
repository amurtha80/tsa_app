# xx_summ_parquet_sanity_check.R ----
# Quick sanity check on a freshly rebuilt tsa_app_summ.parquet: confirms the
# airport-local-time fix (xx_build_summary_DB.R, 2026-07-12) produced
# plausible peak wait-time buckets before pushing the file to S3/EC2.
# Reads the local parquet directly -- no Quack connection needed.


# Package Management ----

foo <- function(x) {
  for (i in x) {
    suppressWarnings(suppressPackageStartupMessages(
      if (!require(i, character.only = TRUE, warn.conflicts = FALSE, quietly = TRUE)) {
        install.packages(i, dependencies = TRUE, verbose = FALSE, quiet = TRUE,
                         repos = "https://cloud.r-project.org/")
        require(i, character.only = TRUE, warn.conflicts = FALSE, quietly = TRUE)
      }
    ))
  }
}

foo(c("nanoparquet", "dplyr", "here"))

rm(foo)


# Read ----

path_parquet <- here::here("C:/Users/james/Documents/R/tsa_app/01_Data/tsa_app_summ.parquet")

summ <- nanoparquet::read_parquet(path_parquet)


# Check: peak avg_time_std bucket per airport, weekday-only, top 5 rows ----
# bucket_time is local wall-clock now -- peaks should cluster in plausible
# daytime/rush windows (roughly 5am-9pm local), not the middle of the night.

peak_check <- summ |>
  filter(weekday %in% c("Mon","Tue","Wed","Thu","Fri")) |>
  group_by(airport) |>
  slice_max(avg_time_std, n = 1, with_ties = FALSE) |>
  ungroup() |>
  select(airport, weekday, bucket_time, avg_time_std) |>
  arrange(airport)

print(peak_check, n = Inf)


# Cleanup ----

rm(summ, peak_check, path_parquet)
