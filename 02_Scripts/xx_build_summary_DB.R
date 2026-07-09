sink(here::here("C:/Users/james/Documents/R/tsa_app/runlog_appdata_xfer.txt"), append = TRUE, type = "output")

# xx_build_summary_db.R ----
# Overnight extraction script: reads tsa_app.duckdb, aggregates wait time data
# into 15-minute buckets by airport / checkpoint / weekday, writes the
# summary table to tsa_app_summ.duckdb, exports a parquet copy, and pushes
# the parquet to S3 for EC2 to pull on restart.
#
# Schedule: Windows Task Scheduler, nightly at 2:00 AM
# Runtime: seconds (single aggregation query over ~365 days of rows)
# Inputs:  01_Data/tsa_app.duckdb        (read-only)
# Outputs: 01_Data/tsa_app_summ.duckdb   (write — created on first run)
#          01_Data/tsa_app_summ.parquet   (write — overwritten each run)
#          S3: see S3 Push section below  (requires paws + AWS credentials)


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

foo(c("duckdb", "DBI", "here", "dplyr", "hms", "lubridate", "glue",
      "nanoparquet"))

rm(foo)
print(glue("packages loaded at ", format(Sys.time(), "%a %b %d %X %Y")))


# Paths ----

path_summ    <- here::here("C:/Users/james/Documents/R/tsa_app/01_Data/tsa_app_summ.duckdb")
path_parquet <- here::here("C:/Users/james/Documents/R/tsa_app/01_Data/tsa_app_summ.parquet")


# Connect ----

# tsa_app.duckdb is read via Quack -- zz_database.R must already be running
# as the Quack server. tsa_app_summ.duckdb is a separate file nothing else
# writes concurrently, so it keeps a direct connection.
con_source <- dbConnect(duckdb::duckdb())
dbExecute(con_source, "INSTALL quack; LOAD quack;")
dbExecute(con_source, glue(
  "ATTACH 'quack:localhost' AS remote_db (TYPE quack, TOKEN '{Sys.getenv('DUCKDB_QUACK_TOKEN')}')"
))
dbExecute(con_source, "USE remote_db;")

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
  )) |>
  # Store bucket_time as "HH:MM:SS" character — hms writes as raw seconds in
  # DuckDB which breaks comparisons on read. Parsed back to hms in app.R.
  mutate(bucket_time = as.character(bucket_time))

print(glue("{nrow(tsa_wait_time_summ)} rows aggregated"))


# Write Summary Table ----
# overwrite = TRUE so each nightly run refreshes the full table

dbWriteTable(con_summ, "tsa_wait_time_summ", tsa_wait_time_summ, overwrite = TRUE)

print(glue("{nrow(tsa_wait_time_summ)} rows written to tsa_wait_time_summ"))
print(glue("******-- Summary build complete ", format(Sys.time(), "%a %b %d %X %Y"), " --******"))


# Write Parquet ----
# Parquet is the file format read by the Shiny app on EC2.
# bucket_time stays as "HH:MM:SS" character — filter key, not display value.
# Display format (12-hour) is applied at render time in app_sidebar.R.

nanoparquet::write_parquet(tsa_wait_time_summ, path_parquet)

print(glue("{nrow(tsa_wait_time_summ)} rows written to tsa_app_summ.parquet at ",
           format(Sys.time(), "%a %b %d %X %Y")))


# S3 Push ----
# TODO: replace bucket name and key path before deploying.
# AWS credentials must be configured on this machine (IAM role, env vars,
# or ~/.aws/credentials). paws picks them up automatically.
# paws is installed here rather than via foo() above to avoid a known
# conflict with glue 1.8.0 when loaded via require() at script startup.

if (!requireNamespace("paws", quietly = TRUE)) {
  install.packages("paws", repos = "https://cloud.r-project.org/")
}

tryCatch({
  s3 <- paws::s3()
  s3$put_object(
    Bucket = "flyasap-app-data",
    Key    = "tsa_app_summ.parquet",
    Body   = path_parquet
  )
  print(glue("parquet pushed to S3 at ", format(Sys.time(), "%a %b %d %X %Y")))
}, error = function(e) {
  print(glue("ERROR: S3 push failed at ", format(Sys.time(), "%a %b %d %X %Y"),
             " — ", conditionMessage(e)))
})


# Cleanup ----

rm(tsa_wait_time_summ)
rm(path_summ)
rm(path_parquet)
rm(s3)

dbDisconnect(con_source, shutdown = TRUE)
dbDisconnect(con_summ,   shutdown = TRUE)

rm(con_source)
rm(con_summ)

sink()
gc()
