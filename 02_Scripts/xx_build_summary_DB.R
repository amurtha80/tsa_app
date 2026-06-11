sink(here::here("C:/Users/james/Documents/R/tsa_app/runlog_appdata_xfer.txt"), append = TRUE, type = "output")

# xx_build_summary_db.R ----
# Overnight extraction script: reads tsa_app.duckdb, aggregates wait time data
# into 15-minute buckets by airport / checkpoint / weekday, and writes the
# summary table to tsa_app_summ.duckdb for use by the Shiny app.
#
# Schedule: Windows Task Scheduler, nightly at 2:00 AM
# Runtime: seconds (single aggregation query over ~365 days of rows)
# Inputs:  01_Data/tsa_app.duckdb      (read-only)
# Outputs: 01_Data/tsa_app_summ.duckdb (write — created on first run)


# Package Management ----

foo <- function(x) {
  for (i in x) {
    suppressWarnings(suppressPackageStartupMessages(
      if (!require(i, character.only = TRUE, warn.conflicts = FALSE, quietly = TRUE)) {
        install.packages(i, dependencies = TRUE, verbose = FALSE, quiet = TRUE,
                         repos = "https://cloud.r-project.org/")
        require(i, character.only = TRUE, verbose = FALSE, warn.conflicts = FALSE, quietly = TRUE)
      }
    ))
  }
}

foo(c("duckdb", "DBI", "here", "dplyr", "hms", "lubridate", "glue"))

rm(foo)
print(glue("packages loaded at ", format(Sys.time(), "%a %b %d %X %Y")))


# Paths ----

path_source <- here::here("C:/Users/james/Documents/R/tsa_app/01_Data/tsa_app.duckdb")
path_summ   <- here::here("C:/Users/james/Documents/R/tsa_app/01_Data/tsa_app_summ.duckdb")


# Connect ----

con_source <- dbConnect(duckdb::duckdb(), dbdir = path_source, read_only = TRUE)
con_summ   <- dbConnect(duckdb::duckdb(), dbdir = path_summ,   read_only = FALSE)

print(glue("******-- Start summary build ", format(Sys.time(), "%a %b %d %X %Y"), " --******"))


# Extract and Aggregate ----

tsa_wait_time_summ <- tbl(con_source, "tsa_wait_times") |>
  collect() |>
  # Keep rolling 365-day window from most recent scraped date
  filter(date >= max(date, na.rm = TRUE) - 365) |>
  mutate(
    checkpoint  = toupper(checkpoint),
    bucket_time = hms::as_hms(lubridate::ceiling_date(time, "15 mins")),
    weekday     = lubridate::wday(time, label = TRUE, abbr = TRUE)
  ) |>
  group_by(airport, checkpoint, weekday, bucket_time) |>
  summarize(
    avg_time_std          = ceiling(mean(wait_time,          na.rm = TRUE)),
    max_time_std          = max(wait_time,                   na.rm = TRUE),
    avg_time_tsa_precheck = ceiling(mean(wait_time_pre_check, na.rm = TRUE)),
    max_time_tsa_precheck = max(wait_time_pre_check,         na.rm = TRUE),
    avg_time_clear        = ceiling(mean(wait_time_clear,    na.rm = TRUE)),
    max_time_clear        = max(wait_time_clear,             na.rm = TRUE),
    .groups = "drop"
  ) |>
  # Inf/-Inf from max/mean over all-NA groups → replace with NA
  mutate(across(
    c(avg_time_std, max_time_std,
      avg_time_tsa_precheck, max_time_tsa_precheck,
      avg_time_clear, max_time_clear),
    \(x) if_else(is.infinite(x) | is.nan(x), NA_real_, as.double(x))
  ))

print(glue("{nrow(tsa_wait_time_summ)} rows aggregated"))


# Write Summary Table ----
# overwrite = TRUE so each nightly run refreshes the full table

dbWriteTable(con_summ, "tsa_wait_time_summ", tsa_wait_time_summ, overwrite = TRUE)

print(glue("{nrow(tsa_wait_time_summ)} rows written to tsa_wait_time_summ"))
print(glue("******-- Summary build complete ", format(Sys.time(), "%a %b %d %X %Y"), " --******"))


# Cleanup ----

rm(tsa_wait_time_summ)
rm(path_source)
rm(path_summ)

dbDisconnect(con_source, shutdown = TRUE)
dbDisconnect(con_summ,   shutdown = TRUE)

rm(con_source)
rm(con_summ)

sink()
gc()