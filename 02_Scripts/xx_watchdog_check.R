sink("C:/Users/james/Documents/R/tsa_app/runlog_watchdog.txt", append = TRUE, type = "output")
cat(paste0("******-- xx_watchdog_check.R started at ", format(Sys.time(), "%a %b %d %X %Y"), " --******"), "\n")

# xx_watchdog_check.R ----
# Fast-detection watchdog for the scraper pipeline. Added after the 2026-07-17
# outage, where tsa_app_scraper's Task Scheduler stored credential failed to
# authenticate (LogonUserExEx / ERROR_LOGON_FAILURE) for ~16 hours straight —
# the process never launched, so runlog.txt went silent with no error to catch
# until the nightly xx_validate_scrape.R alert fired ~20 hours later.
#
# This script checks two things and alerts immediately (not overnight) if either
# looks stalled:
#   1. runlog.txt has a recent "Start Run" — the scraper task is actually launching
#   2. the Quack server (zz_database.R) accepts a connection — it holds no log of
#      its own, so a silent crash there would otherwise be invisible
#
# Schedule: Windows Task Scheduler, every 30 minutes
# Runtime: seconds
# Inputs:  runlog.txt (read-only), Quack server connection
# Outputs: runlog_watchdog.txt (always written)
#          Email alert (only when a check fails)
#
# SMTP setup: reuses the same blastula "gmail_creds" keystore entry and
# .Renviron SMTP_USER / ALERT_EMAIL_TO already configured for xx_validate_scrape.R.


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

foo(c("duckdb", "DBI", "glue", "blastula"))

rm(foo)
cat(glue("packages loaded at ", format(Sys.time(), "%a %b %d %X %Y")), "\n")


# Config ----

runlog_path             <- "C:/Users/james/Documents/R/tsa_app/runlog.txt"
stale_threshold_minutes <- 20L   # 5-min cadence + retry pass; allow margin before flagging


# Send Alert Helper ----
# Shared by both checks below so a failure in one doesn't block the other from alerting.

send_alert <- function(subject_suffix, detail_html) {

  smtp_user <- Sys.getenv("SMTP_USER")
  alert_to  <- Sys.getenv("ALERT_EMAIL_TO")

  if (smtp_user == "" || alert_to == "") {
    cat("WARNING: email alert skipped — SMTP_USER or ALERT_EMAIL_TO missing from .Renviron\n")
    return(invisible(NULL))
  }

  tryCatch({

    email_body <- glue("
    <h2 style='color:#2C3E7F;font-family:Inter,sans-serif;'>
      FlyASAP — Watchdog Alert
    </h2>
    <p style='font-family:Inter,sans-serif;'>{detail_html}</p>
    <p style='font-family:Inter,sans-serif;color:#888;font-size:12px;margin-top:24px;'>
      Sent by xx_watchdog_check.R at {format(Sys.time(), '%a %b %d %X %Y')}
    </p>
  ")

    email <- blastula::compose_email(body = blastula::md(email_body))

    blastula::smtp_send(
      email,
      from        = smtp_user,
      to          = alert_to,
      subject     = glue("FlyASAP watchdog: {subject_suffix}"),
      credentials = blastula::creds_key(id = "gmail_creds")
    )

    cat(glue("Alert email sent to {alert_to} at ", format(Sys.time(), "%a %b %d %X %Y")), "\n")

  }, error = function(e) {
    cat(glue("ERROR: email send failed at ", format(Sys.time(), "%a %b %d %X %Y"),
             " — ", conditionMessage(e)), "\n")
  })

}


tryCatch({

  ## Check 1 — Scraper freshness ----
  # Read runlog.txt's last "Start Run" timestamp. If it's older than the
  # threshold, the scraper task itself isn't launching (as happened 2026-07-17).

  log_lines        <- readLines(runlog_path, warn = FALSE)
  start_run_lines  <- grep("^\\*+-- Start Run ", log_lines, value = TRUE)
  last_start_run   <- tail(start_run_lines, 1)

  if (length(last_start_run) == 0) {
    cat("WARNING: no 'Start Run' entries found in runlog.txt at all\n")
    minutes_since_last_run <- Inf
  } else {
    last_run_time <- as.POSIXct(
      sub(".*Start Run ([0-9-]+ [0-9:]+).*", "\\1", last_start_run),
      format = "%Y-%m-%d %H:%M:%S"
    )
    minutes_since_last_run <- as.numeric(difftime(Sys.time(), last_run_time, units = "mins"))
    cat(glue("Last scraper Start Run: {last_run_time} ({round(minutes_since_last_run, 1)} min ago)"), "\n")
  }

  if (minutes_since_last_run > stale_threshold_minutes) {
    cat(glue("ALERT: scraper stalled — last Start Run was {round(minutes_since_last_run, 1)} min ago (threshold {stale_threshold_minutes})"), "\n")
    send_alert(
      subject_suffix = "scraper stalled",
      detail_html = glue(
        "No new scraper run in <strong>{round(minutes_since_last_run, 1)} minutes</strong> ",
        "(threshold: {stale_threshold_minutes} min). tsa_app_scraper may have stopped launching — ",
        "check Task Scheduler history for logon/credential errors (Event 104/101) first, per the ",
        "2026-07-17 outage."
      )
    )
  } else {
    cat("Check 1 (scraper freshness): OK\n")
  }


  ## Check 2 — Quack server liveness ----
  # A dead zz_database.R server would fail every scraper cycle even with a
  # healthy Task Scheduler credential, and it keeps no log of its own.

  quack_ok <- tryCatch({
    con <- dbConnect(duckdb::duckdb())
    dbExecute(con, "INSTALL quack; LOAD quack;")
    dbExecute(con, glue(
      "ATTACH 'quack:localhost' AS remote_db (TYPE quack, TOKEN '{Sys.getenv('DUCKDB_QUACK_TOKEN')}')"
    ))
    dbExecute(con, "SELECT 1 FROM remote_db.tsa_wait_times LIMIT 1;")
    dbDisconnect(con, shutdown = TRUE)
    TRUE
  }, error = function(e) {
    cat(glue("Quack connection error: ", conditionMessage(e)), "\n")
    FALSE
  })

  if (!quack_ok) {
    cat("ALERT: Quack server unreachable\n")
    send_alert(
      subject_suffix = "Quack server unreachable",
      detail_html = "Could not connect to the Quack server (zz_database.R) via the standard TOKEN-based ATTACH. It may have crashed or is not running — check the tsa_app_quack_server Task Scheduler job status."
    )
  } else {
    cat("Check 2 (Quack server liveness): OK\n")
  }

}, error = function(e) {
  cat(glue("FATAL ERROR at ", format(Sys.time(), "%a %b %d %X %Y"),
           " — ", conditionMessage(e)), "\n")
}, finally = {

  cat(glue("******-- Watchdog check complete ", format(Sys.time(), "%a %b %d %X %Y"), " --******"), "\n")

  suppressWarnings(
    rm(list = intersect(
      ls(),
      c("runlog_path", "stale_threshold_minutes", "send_alert", "log_lines",
        "start_run_lines", "last_start_run", "last_run_time", "minutes_since_last_run",
        "quack_ok", "con")
    ))
  )

  sink()
  gc()

})
