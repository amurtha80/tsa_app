# 02_Scripts/pi_baketest/00_scratch_db_setup.R
#
# Creates the scratch tables used by the Phase 0 bake-off, if they don't
# already exist. This is sourced by xx_baketest_orchestrator.R, which opens
# `con_write` against a scratch DuckDB file BEFORE sourcing this script --
# it is not meant to be run standalone.
#
# NEVER point the orchestrator's DB_PATH at production 01_Data/tsa_app.duckdb.
# This file only touches whatever con_write is already connected to.

# Mirrors the production tsa_wait_times schema (see zz_database.R) so the
# real scraper functions can dbAppendTable() into it unmodified.
dbExecute(con_write, "
  CREATE TABLE IF NOT EXISTS tsa_wait_times (
    airport             VARCHAR,
    checkpoint           VARCHAR,
    datetime             DATETIME,
    date                 DATE,
    time                 TIMESTAMP_S,
    timezone             VARCHAR,
    holiday_travel       BOOLEAN,
    wait_time            INTEGER,
    wait_time_priority   INTEGER,
    wait_time_pre_check  INTEGER,
    wait_time_clear      INTEGER
  );
")

# One row per (host, scraper, cycle) attempt -- the actual bake-off comparison data.
dbExecute(con_write, "
  CREATE TABLE IF NOT EXISTS bakeoff_runs (
    host_label            VARCHAR,
    scraper                VARCHAR,
    cycle_num              INTEGER,
    run_start               TIMESTAMP,
    run_end                 TIMESTAMP,
    duration_sec            DOUBLE,
    status                  VARCHAR,
    rows_inserted           INTEGER,
    error_message           VARCHAR,
    chromote_chrome_path    VARCHAR,
    r_version                VARCHAR,
    os_arch                  VARCHAR,
    recorded_at              TIMESTAMP
  );
")

print(dbGetQuery(con_write, "SHOW TABLES;"))
