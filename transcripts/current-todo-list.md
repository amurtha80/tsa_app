# Current todo list

### User

can you show me the current todo list?

---

### Assistant

Here's where things stand:

Active Bug Fixes (Airport Scripts)

- WebSocket warning — Suppress "got non-close frame while closing" during `tryCatch` teardown in chromote scripts after switching to `chrome-headless-shell`. Cosmetic/non-fatal but needs cleanup.

- DEN — `DEN_wait_times.R` returning NA for `wait_time` and `wait_time_pre_check`. CSS selectors or parsing logic on flydenver.com likely need updating.

- JFK — `JFK_wait_times.R` returning correct checkpoint titles but NA for all wait time values. Page may have changed.

- LGA / JFK / EWR (Port Authority airports) — LGA returning no results (table appears to have moved). Since all three share infrastructure, the fix for one will likely carry over. Should tackle together.

- CLT — Checkpoint names from API no longer match page display names; wait time values don't align either (page shows ranges, API shows point values). Need to decide on correct data source.

Upcoming Development

- IAH — Error investigation (dedicated chat planned)

- DFW — JSON parsing fix (dedicated chat planned)

- Shiny app — Connect to DuckDB, port chart logic from `xx_chart_times.R`, wire reactive inputs

- shinyapps.io deployment — Resolve hardcoded local DB path, configure `rsconnect`

- DuckDB Quack protocol — Keep an eye on for future concurrent read/write refactor (expected maturity v2.0, fall 2026)

- `holiday_travel` column — Currently unpopulated, needs to be filled

- README — Update and format for the GitHub repo

- Housekeeping — Archive unused scripts, standardize function naming

Which of these do you want to dig into?

---

### Assistant

TSA Wait Time Shiny App

---

