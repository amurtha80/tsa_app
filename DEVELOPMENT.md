# FlyASAP Development & Infrastructure Guide

## Directory Conventions
- `00_Readme/`: Contains `todo_list.txt` file, a file where Claude and I place TODO items that should be worked on in the future. When items are completed the get added to the `CHANGELOG.md` file, which sits in the top level folder of the project.
- `01_Data/` : Local databases and data tracking (never commit).
- `02_Scripts/` : Scripts. WIP scripts prefixed with airport code; sandbox/utilities with `xx_`; archived/one-time with `zz_`.
- `03_App/` : Shiny application files (ui, server, global).

## Tech Stack & Environment
- **Local Dev:** Windows Desktop (R 4.5.1). *Note: path.expand("~") resolves to Documents; `.Renviron` lives at `C:/Users/james/Documents/.Renviron`.*
- **Production EC2:** Ubuntu 24.04, Shiny Server, nginx reverse proxy, Let's Encrypt SSL.
- **Data Pipeline:** Windows desktop builds summary parquet (`tsa_app_summ.parquet`) at 2 AM -> S3 bucket (`flyasap-app-data`) -> EC2 cron pulls at 3 AM via `CRON_TZ=America/New_York` and restarts Shiny Server.

## Database & Concurrency (DuckDB Quack Protocol)
- DuckDB takes an exclusive OS file lock, blocking concurrent reads/writes.
- **Solution (In Progress):** Utilizing the DuckDB **Quack** protocol (released May 2026, beta in v1.5.2+).
- **Architecture:** One persistent DuckDB server process holds the file block. Scrapers and interactive sessions connect as clients via:
  `ATTACH 'quack:localhost' AS remote_db (TYPE quack, TOKEN '...');`
- Token is securely loaded from `QUACK_TOKEN` in `.Renviron`.
- Always call `dbDisconnect(con_write, shutdown = TRUE)` at the end of scripts.

## Active State & Blocks
1. **DFW Scraper:** Blocked pending raw JSON response capture to confirm field names. Uses chromote network capture via `DFW_in_progress.R`. Needs timezone set to `America/Chicago`.
2. **CLT Alignment:** Page shows ranges, API shows point values. Needs source verification.
3. **Airport Checkpoint Hours Table:** `airport_checkpoint_hours` exists in `zz_database.R`. INSERT statement is blocked pending `SELECT DISTINCT checkpoint FROM tsa_wait_times` per airport to prevent join mismatches.