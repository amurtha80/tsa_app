sink("C:/Users/james/Documents/R/tsa_app/runlog_validate.txt", append = TRUE, type = "output")
cat(paste0("******-- xx_validate_scrape.R started at ", format(Sys.time(), "%a %b %d %X %Y"), " --******"), "\n")

# xx_validate_scrape.R ----
# Nightly data quality validation script: queries tsa_app.duckdb for yesterday's
# raw scrape rows and runs five checks to detect scraping failures or bad data.
# Logs a summary every run (pass or fail). Sends a blastula email alert if any
# check fails.
#
# Schedule: Windows Task Scheduler, nightly — run ~15 min after xx_build_summary_DB.R
# Runtime: seconds (lightweight queries only)
# Inputs:  01_Data/tsa_app.duckdb  (read-only)
# Outputs: runlog_validate.txt     (always written)
#          Email alert              (only on failure)
#
# SMTP setup: add the following to C:/Users/james/Documents/.Renviron then
# restart R or re-run the Task Scheduler job:
#   SMTP_USER=your_gmail_address@gmail.com
#   SMTP_PASSWORD=your_app_password   # Gmail App Password, not account password
#   ALERT_EMAIL_TO=your_alert_destination@email.com


# Package Management ----

foo <- function(x) {
  for (i in x) {
    suppressWarnings(suppressPackageStartupMessages(
      if (!require(i, character.only = TRUE, warn.conflicts = FALSE, quietly = TRUE)) {
        cat(paste0("WARNING: package '", i, "' not found — attempting install at ",
                   format(Sys.time(), "%a %b %d %X %Y")), "\n")
        install.packages(i, dependencies = TRUE, verbose = FALSE, quiet = TRUE,
                         repos = "https://cloud.r-project.org/")
        require(i, character.only = TRUE, warn.conflicts = FALSE, quietly = TRUE)
      }
    ))
  }
}

foo(c("duckdb", "DBI", "here", "dplyr", "glue", "lubridate", "blastula"))

rm(foo)
cat(glue("packages loaded at ", format(Sys.time(), "%a %b %d %X %Y")), "\n")


# Config ----

yesterday  <- lubridate::today() - 1

# Threshold: a checkpoint must appear on at least this many of the prior 7 days
# to be considered "expected" — absence yesterday will then trigger an alert
checkpoint_presence_threshold <- 5L

# Wait time ceiling — values above this (in minutes) are treated as parse errors
wait_time_ceiling <- 120L

# Row count drop threshold — alert if yesterday's count is below this fraction
# of the airport's 7-day rolling average
row_count_drop_pct <- 0.50


# Connect ----
# tsa_app.duckdb is read via Quack -- zz_database.R must already be running
# as the Quack server.

con <- tryCatch(
  {
    con <- dbConnect(duckdb::duckdb())
    dbExecute(con, "INSTALL quack; LOAD quack;")
    dbExecute(con, glue(
      "ATTACH 'quack:localhost' AS remote_db (TYPE quack, TOKEN '{Sys.getenv('DUCKDB_QUACK_TOKEN')}')"
    ))
    dbExecute(con, "USE remote_db;")
    con
  },
  error = function(e) {
    cat(glue("FATAL: could not connect to database via Quack — ",
             conditionMessage(e)), "\n")
    NULL
  }
)

if (is.null(con)) {
  cat("Script aborted: no database connection.\n")
  sink()
  stop("Database connection failed — see runlog_validate.txt")
}

cat(glue("******-- Start validation run {yesterday} ",
         format(Sys.time(), "%a %b %d %X %Y"), " --******"), "\n")


tryCatch({
  
  # Pull Raw Data ----
  
  # Yesterday's rows
  yesterday_data <- tbl(con, "tsa_wait_times") |>
    filter(date == !!as.character(yesterday)) |>
    select(airport, checkpoint, date, wait_time, wait_time_pre_check, wait_time_clear) |>
    collect()
  
  # Prior 7 days rows (baseline window, excludes yesterday)
  baseline_data <- tbl(con, "tsa_wait_times") |>
    filter(date >= !!as.character(yesterday - 7),
           date <  !!as.character(yesterday)) |>
    select(airport, checkpoint, date, wait_time, wait_time_pre_check, wait_time_clear) |>
    collect()
  
  cat(glue("{nrow(yesterday_data)} rows found for {yesterday}"), "\n")
  cat(glue("{nrow(baseline_data)} rows found in 7-day baseline window"), "\n")
  
  
  # Checks ----
  # Each check produces a data frame of flagged issues (zero rows = clean).
  # Columns: check, airport, checkpoint, detail
  
  issues <- list()
  
  
  ## Check 1 — Total airport absence ----
  # Any airport with zero rows yesterday is an outright scrape failure.
  
  known_airports <- baseline_data |>
    distinct(airport) |>
    pull(airport)
  
  yesterday_airports <- yesterday_data |>
    distinct(airport) |>
    pull(airport)
  
  missing_airports <- setdiff(known_airports, yesterday_airports)
  
  issues$check1 <- if (length(missing_airports) > 0) {
    tibble(
      check      = "1 — Airport total absence",
      airport    = missing_airports,
      checkpoint = NA_character_,
      detail     = "Zero rows for this airport yesterday — scrape likely failed entirely"
    )
  } else {
    tibble(
      check      = character(),
      airport    = character(),
      checkpoint = character(),
      detail     = character()
    )
  }
  
  cat(glue("Check 1 (airport absence): {length(missing_airports)} airports flagged"), "\n")
  
  
  ## Check 2 — Row count drop vs. 7-day baseline ----
  # Flag any airport where yesterday's row count is below 50% of its rolling average.
  # Catches partial scrape failures that still produce some rows.
  # Guard: airports with zero baseline avg are excluded to avoid division by zero.
  
  baseline_avg <- baseline_data |>
    count(airport, date) |>
    group_by(airport) |>
    summarize(avg_daily_rows = mean(n, na.rm = TRUE), .groups = "drop") |>
    filter(avg_daily_rows > 0)
  
  yesterday_counts <- yesterday_data |>
    count(airport, name = "yesterday_rows")
  
  row_count_check <- baseline_avg |>
    left_join(yesterday_counts, by = "airport") |>
    mutate(yesterday_rows = coalesce(yesterday_rows, 0L)) |>
    filter(yesterday_rows < avg_daily_rows * row_count_drop_pct)
  
  issues$check2 <- if (nrow(row_count_check) > 0) {
    row_count_check |>
      transmute(
        check      = "2 — Row count drop",
        airport,
        checkpoint = NA_character_,
        detail     = glue(
          "Yesterday: {yesterday_rows} rows; 7-day avg: {round(avg_daily_rows, 1)} rows ",
          "({round(yesterday_rows / avg_daily_rows * 100, 0)}% of baseline)"
        )
      )
  } else {
    tibble(
      check      = character(),
      airport    = character(),
      checkpoint = character(),
      detail     = character()
    )
  }
  
  cat(glue("Check 2 (row count drop): {nrow(row_count_check)} airports flagged"), "\n")
  
  
  ## Check 3 — Checkpoint drop-off ----
  # For each airport, find checkpoints present on 5+ of the prior 7 days.
  # Flag any that are completely absent yesterday.
  # Threshold avoids alerting on naturally sporadic checkpoints.
  # Denominator in detail message uses actual days observed, not hardcoded 7.
  
  baseline_days_observed <- baseline_data |>
    distinct(date) |>
    nrow()
  
  baseline_checkpoint_presence <- baseline_data |>
    distinct(airport, checkpoint, date) |>
    count(airport, checkpoint, name = "days_present") |>
    filter(days_present >= checkpoint_presence_threshold)
  
  yesterday_checkpoints <- yesterday_data |>
    distinct(airport, checkpoint)
  
  missing_checkpoints <- baseline_checkpoint_presence |>
    anti_join(yesterday_checkpoints, by = c("airport", "checkpoint"))
  
  issues$check3 <- if (nrow(missing_checkpoints) > 0) {
    missing_checkpoints |>
      transmute(
        check      = "3 — Checkpoint drop-off",
        airport,
        checkpoint,
        detail     = glue(
          "Present on {days_present}/{baseline_days_observed} prior days; absent yesterday"
        )
      )
  } else {
    tibble(
      check      = character(),
      airport    = character(),
      checkpoint = character(),
      detail     = character()
    )
  }
  
  cat(glue("Check 3 (checkpoint drop-off): {nrow(missing_checkpoints)} checkpoints flagged"), "\n")
  
  
  ## Check 4 — Implausible wait time values ----
  # Flag any rows where any wait time column exceeds the ceiling or is negative.
  # Catches parse errors (e.g., departure time scraped as a wait time).
  
  implausible <- yesterday_data |>
    filter(
      (!is.na(wait_time)           & (wait_time           > wait_time_ceiling | wait_time           < 0)) |
        (!is.na(wait_time_pre_check) & (wait_time_pre_check > wait_time_ceiling | wait_time_pre_check < 0)) |
        (!is.na(wait_time_clear)     & (wait_time_clear     > wait_time_ceiling | wait_time_clear     < 0))
    ) |>
    distinct(airport, checkpoint) |>
    mutate(
      check  = "4 — Implausible wait time value",
      detail = glue("At least one row with wait time outside 0–{wait_time_ceiling} min range")
    ) |>
    select(check, airport, checkpoint, detail)
  
  issues$check4 <- implausible
  
  cat(glue("Check 4 (implausible values): {nrow(implausible)} airport/checkpoint combos flagged"), "\n")
  
  
  ## Check 5 — All-NA standard lane per airport ----
  # If every wait_time row for an airport yesterday is NA, the scraper ran but
  # returned no usable data. Different from Check 2 (rows exist, values are all junk).
  # Guard: only runs on airports that actually have rows yesterday (Check 1 handles
  # total absence — this check should not double-fire on those same airports).
  
  all_na_airports <- yesterday_data |>
    filter(airport %in% yesterday_airports) |>
    group_by(airport) |>
    summarize(all_na = all(is.na(wait_time)), .groups = "drop") |>
    filter(all_na) |>
    pull(airport)
  
  issues$check5 <- if (length(all_na_airports) > 0) {
    tibble(
      check      = "5 — All-NA standard lane",
      airport    = all_na_airports,
      checkpoint = NA_character_,
      detail     = "Every wait_time row for this airport is NA — scraper returned no usable data"
    )
  } else {
    tibble(
      check      = character(),
      airport    = character(),
      checkpoint = character(),
      detail     = character()
    )
  }
  
  cat(glue("Check 5 (all-NA standard lane): {length(all_na_airports)} airports flagged"), "\n")
  
  
  # Combine Issues ----
  
  all_issues <- bind_rows(issues)
  
  n_issues <- nrow(all_issues)
  
  
  # Log Summary ----
  
  if (n_issues == 0) {
    cat(glue("RESULT: CLEAN — all checks passed. 0 issues found for {yesterday}."), "\n")
  } else {
    cat(glue("RESULT: {n_issues} issue(s) found for {yesterday}:"), "\n")
    # Fix #8: print as plain data frame to avoid ANSI escape codes in log file
    print(as.data.frame(all_issues))
  }
  
  cat(glue("******-- Validation complete ", format(Sys.time(), "%a %b %d %X %Y"), " --******"), "\n")
  
  
  # Email Alert ----
  # Sends only when at least one check failed.
  # Prerequisites:
  #   1. Run once interactively to store sending credentials in system keystore:
  #        blastula::create_smtp_creds_key(
  #          id       = "gmail_creds",
  #          user     = "your_gmail@gmail.com",
  #          provider = "gmail"
  #        )
  #      R will prompt for the 16-character App Password.
  #   2. Ensure C:/Users/james/Documents/.Renviron contains:
  #        SMTP_USER=your_gmail@gmail.com
  #        ALERT_EMAIL_TO=your_alert_destination@email.com
  
  if (n_issues > 0) {
    
    smtp_user <- Sys.getenv("SMTP_USER")
    alert_to  <- Sys.getenv("ALERT_EMAIL_TO")
    
    if (smtp_user == "" || alert_to == "") {
      cat("WARNING: email alert skipped — SMTP_USER or ALERT_EMAIL_TO missing from .Renviron\n")
    } else {
      
      tryCatch({
        
        # Build HTML table of issues for email body
        issues_html <- all_issues |>
          mutate(checkpoint = coalesce(checkpoint, "—")) |>
          glue::glue_data(
            "<tr>",
            "<td style='padding:6px 12px;border-bottom:1px solid #eee;'>{check}</td>",
            "<td style='padding:6px 12px;border-bottom:1px solid #eee;'>{airport}</td>",
            "<td style='padding:6px 12px;border-bottom:1px solid #eee;'>{checkpoint}</td>",
            "<td style='padding:6px 12px;border-bottom:1px solid #eee;'>{detail}</td>",
            "</tr>"
          ) |>
          paste(collapse = "\n")
        
        email_body <- glue("
        <h2 style='color:#2C3E7F;font-family:Inter,sans-serif;'>
          FlyASAP — Scrape Validation Alert
        </h2>
        <p style='font-family:Inter,sans-serif;'>
          <strong>{n_issues} issue(s)</strong> detected in last night's scrape
          for <strong>{yesterday}</strong>.
        </p>
        <table style='border-collapse:collapse;font-family:Inter,sans-serif;font-size:14px;width:100%;'>
          <thead>
            <tr style='background:#2C3E7F;color:#fff;'>
              <th style='padding:8px 12px;text-align:left;'>Check</th>
              <th style='padding:8px 12px;text-align:left;'>Airport</th>
              <th style='padding:8px 12px;text-align:left;'>Checkpoint</th>
              <th style='padding:8px 12px;text-align:left;'>Detail</th>
            </tr>
          </thead>
          <tbody>
            {issues_html}
          </tbody>
        </table>
        <p style='font-family:Inter,sans-serif;color:#888;font-size:12px;margin-top:24px;'>
          Sent by xx_validate_scrape.R at {format(Sys.time(), '%a %b %d %X %Y')}
        </p>
      ")
        
        email <- blastula::compose_email(body = blastula::md(email_body))
        
        blastula::smtp_send(
          email,
          from        = smtp_user,
          to          = alert_to,
          subject     = glue("FlyASAP alert: {n_issues} scrape issue(s) on {yesterday}"),
          credentials = blastula::creds_key(id = "gmail_creds")
        )
        
        cat(glue("Alert email sent to {alert_to} at ", format(Sys.time(), "%a %b %d %X %Y")), "\n")
        
      }, error = function(e) {
        cat(glue("ERROR: email send failed at ", format(Sys.time(), "%a %b %d %X %Y"),
                 " — ", conditionMessage(e)), "\n")
      })
      
    }
    
  }
  
  
}, error = function(e) {
  # Catches any unhandled error in the checks/email block and logs it
  # before the finally block runs cleanup
  cat(glue("FATAL ERROR at ", format(Sys.time(), "%a %b %d %X %Y"),
           " — ", conditionMessage(e)), "\n")
  
}, finally = {
  
  # Cleanup — always runs regardless of success or error
  # suppressWarnings handles the case where an object was never created
  # due to an earlier error
  suppressWarnings(
    rm(list = intersect(
      ls(),
      c("yesterday_data", "baseline_data", "known_airports", "yesterday_airports",
        "missing_airports", "baseline_avg", "yesterday_counts", "row_count_check",
        "baseline_checkpoint_presence", "yesterday_checkpoints", "missing_checkpoints",
        "baseline_days_observed", "implausible", "all_na_airports", "issues",
        "all_issues", "n_issues", "smtp_user", "alert_to",
        "issues_html", "email_body", "email")
    ))
  )
  
  suppressWarnings(
    rm(list = intersect(
      ls(),
      c("yesterday", "checkpoint_presence_threshold",
        "wait_time_ceiling", "row_count_drop_pct")
    ))
  )
  
  if (exists("con") && !is.null(con)) {
    dbDisconnect(con, shutdown = TRUE)
    rm(con)
  }
  
  sink()
  gc()
  
})