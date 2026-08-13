sink("C:/Users/james/Documents/R/tsa_app/runlog_backup_pull.txt", append = TRUE, type = "output")
cat(paste0("******-- xx_backup_pull_from_pi.R started at ", format(Sys.time(), "%a %b %d %X %Y"), " --******"), "\n")

# xx_backup_pull_from_pi.R ----
# Passive backup of the Pi's live tsa_app.duckdb onto the desktop, added ahead
# of the Phase 1 Pi migration (see project_pi_nas_migration memory) once the
# Pi's SSD becomes the sole host of the live production DB. Avoids AWS
# storage/egress costs entirely by reusing the same Quack protocol/token
# already used everywhere else in this project (see zz_database.R) -- just
# ATTACHing to a remote host instead of localhost.
#
# Desktop is intentionally powered off most nights, so this is NOT scheduled
# for a fixed nightly time (it would just get skipped). Task Scheduler is set
# up with an "At log on" trigger, so a pull runs shortly after every boot,
# whether the last pull was 12 hours or several days ago -- the WHERE >
# watermark logic below always catches up to exactly whatever's missing,
# nothing more.
#
# Backup file: 01_Data/tsa_app_backup.duckdb -- a SEPARATE file from
# production, direct (non-Quack) connection, since this desktop file has
# exactly one writer (this script) and no concurrent readers to arbitrate.
#
# Schedule: Windows Task Scheduler, trigger "At log on"
# Runtime: seconds to low minutes, depending on catch-up size
# Inputs:  remote Pi Quack server (read-only queries), local backup DB
# Outputs: 01_Data/tsa_app_backup.duckdb (append-only), runlog_backup_pull.txt


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

foo(c("duckdb", "DBI", "glue"))

rm(foo)
cat(glue("packages loaded at ", format(Sys.time(), "%a %b %d %X %Y")), "\n")


# Config ----

backup_db_path <- "C:/Users/james/Documents/R/tsa_app/01_Data/tsa_app_backup.duckdb"

# Pi's local LAN IP (DHCP-assigned, confirmed 2026-08-13: 192.168.1.207 on
# eth0). Deliberately NOT the "unbuntuserverpi" hostname -- that resolves via
# Tailscale MagicDNS on this desktop, and Quack traffic is meant to stay on
# the local LAN, not depend on Tailscale being up. Overridable via
# PI_QUACK_HOST in .Renviron if the IP ever changes (a DHCP reservation on
# the router would prevent that, not yet set up).
pi_quack_host <- Sys.getenv("PI_QUACK_HOST", "192.168.1.207")
quack_token   <- Sys.getenv("DUCKDB_QUACK_TOKEN")

# Tables to sync. tsa_wait_times: datetime is a reliable per-row watermark --
# every row has one, rows are append-only/immutable. airport_checkpoint_hours:
# NOT append-only-safe -- entry_timestamp was added after some rows already
# existed, so 17 of 113 rows have entry_timestamp IS NULL (confirmed
# 2026-08-13). `WHERE entry_timestamp > watermark` silently and permanently
# excludes NULL rows on every future run (NULL > anything is NULL, not TRUE),
# so this small table uses a full-replace snapshot instead of a watermark --
# cheap at 113 rows, and correctness matters more than incremental efficiency
# here.
sync_tables <- list(
  list(table = "tsa_wait_times",          mode = "watermark", watermark_col = "datetime"),
  list(table = "airport_checkpoint_hours", mode = "full_replace")
)


tryCatch({

  if (quack_token == "") {
    stop("DUCKDB_QUACK_TOKEN missing from .Renviron -- cannot authenticate to the Pi's Quack server")
  }

  ## Connect to local backup file (direct, not Quack -- single writer) ----
  con_backup <- dbConnect(duckdb::duckdb(), dbdir = backup_db_path, read_only = FALSE)

  ## Attach remote Pi Quack server (read-only use) ----
  ## DISABLE_SSL: Quack's HTTPS client expects a cert matching the exact
  ## hostname it connects to; connecting by raw LAN IP fails TLS verification
  ## outright ("SSL connect error"), confirmed 2026-08-13. Traffic stays on
  ## the private home LAN, not the public internet, so plaintext (token still
  ## required) is an accepted tradeoff here -- see zz_database.R's matching
  ## comment on the server side.
  dbExecute(con_backup, "INSTALL quack; LOAD quack;")
  dbExecute(con_backup, glue(
    "ATTACH 'quack:{pi_quack_host}' AS remote_pi (TYPE quack, TOKEN '{quack_token}', DISABLE_SSL true)"
  ))
  cat(glue("Connected to remote Pi Quack server at {pi_quack_host}"), "\n")

  for (tbl in sync_tables) {

    table_name <- tbl$table

    if (tbl$mode == "full_replace") {
      ## Small, not append-only-safe tables: just re-copy the whole thing.
      ## CREATE OR REPLACE avoids any watermark/NULL edge cases entirely.
      dbExecute(con_backup, glue(
        "CREATE OR REPLACE TABLE {table_name} AS SELECT * FROM remote_pi.{table_name}"
      ))
      n <- dbGetQuery(con_backup, glue("SELECT COUNT(*) AS n FROM {table_name}"))$n
      cat(glue("{table_name}: full-replace snapshot, {n} row(s) at ", format(Sys.time(), "%a %b %d %X %Y")), "\n")
      next
    }

    wm_col <- tbl$watermark_col

    ## Create the local backup table on first run (schema only, no rows) ----
    dbExecute(con_backup, glue(
      "CREATE TABLE IF NOT EXISTS {table_name} AS SELECT * FROM remote_pi.{table_name} WHERE 1 = 0"
    ))

    ## Watermark = latest row already in the backup. COALESCE handles a
    ## still-empty table on first run so nothing is skipped.
    local_max <- dbGetQuery(con_backup, glue(
      "SELECT COALESCE(MAX({wm_col}), TIMESTAMP '1900-01-01') AS wm FROM {table_name}"
    ))$wm

    new_row_count <- dbGetQuery(con_backup, glue(
      "SELECT COUNT(*) AS n FROM remote_pi.{table_name} WHERE {wm_col} > TIMESTAMP '{local_max}'"
    ))$n

    cat(glue("{table_name}: local watermark {local_max}, {new_row_count} new row(s) on the Pi"), "\n")

    if (new_row_count > 0) {
      dbExecute(con_backup, glue(
        "INSERT INTO {table_name}
         SELECT * FROM remote_pi.{table_name}
         WHERE {wm_col} > TIMESTAMP '{local_max}'"
      ))
      cat(glue("{table_name}: pulled {new_row_count} new row(s) at ", format(Sys.time(), "%a %b %d %X %Y")), "\n")
    } else {
      cat(glue("{table_name}: already up to date"), "\n")
    }
  }

}, error = function(e) {
  cat(glue("ERROR at ", format(Sys.time(), "%a %b %d %X %Y"), " — ", conditionMessage(e)), "\n")
}, finally = {

  cat(glue("******-- Backup pull complete ", format(Sys.time(), "%a %b %d %X %Y"), " --******"), "\n")

  suppressWarnings(
    if (exists("con_backup")) {
      tryCatch(dbExecute(con_backup, "DETACH remote_pi"), error = function(e) NULL)
      dbDisconnect(con_backup, shutdown = TRUE)
    }
  )

  suppressWarnings(
    rm(list = intersect(
      ls(),
      c("backup_db_path", "pi_quack_host", "quack_token", "sync_tables", "tbl",
        "table_name", "wm_col", "local_max", "new_row_count", "con_backup")
    ))
  )

  sink()
  gc()

})
