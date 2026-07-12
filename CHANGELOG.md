# Changelog
FlyASAP — Airport Security Advance Planning

---

## 2026-07-12

### Data Quality Fix — Charts Now Show Airport-Local Time, Not UTC
- Root-caused the open todo item flagging that `tsa_wait_times.time` (`TIMESTAMP_S`,
  a naive/non-timezone-aware DuckDB column type) silently stores a UTC instant on
  write, not the airport-local wall clock each scraper builds it as — the DuckDB R
  driver drops the `tzone` attribute from a tz-aware `POSIXct` when writing into a
  naive timestamp column via `dbAppendTable`, with no explicit conversion code
  anywhere doing this
- Neither `xx_build_summary_DB.R` (nightly parquet build) nor `app.R` (`filtered_data()`)
  did any timezone conversion before this fix — both treated the raw `time` value as
  if it were already airport-local, so every airport's chart was shifted by that
  airport's UTC offset (varying with DST); e.g. ATL's Sunday `DOMESTIC LOWER NORTH`
  peak wait time appeared at noon-2pm instead of the true 7:30-9:00am rush
- No backfill/UPDATE of historical `tsa_wait_times` data was needed: R's `POSIXct`
  always stores seconds-since-epoch-UTC internally regardless of the `tzone` label
  used to construct it, and `floor_date(unit = "minute")` is timezone-invariant, so
  every scraper's `time` column has always held a genuinely correct UTC instant —
  confirmed via live-DB query (`attr(result$time, "tzone")` returns `"UTC"`) and via
  a value-level before/after comparison showing the peak wait-time bucket shift into
  a plausible daytime window
- Fix is a single change in `xx_build_summary_DB.R`: force-tag `time` as UTC, then
  `group_by(timezone) |> with_tz(time, tzone = first(timezone))` to convert each
  row to its true airport-local wall clock (grouped by timezone since a single
  `POSIXct` vector can only carry one `tzone` attribute at a time) before deriving
  `bucket_time`/`weekday` for the parquet — `app.R` needed no changes, since it
  already just compares `bucket_time` at face value
- Verified DST-correctness (not just a fixed-offset shift) across the 2025-03-09
  spring-forward transition for both an Eastern-time airport (ATL: -5 → -4) and a
  Pacific-time airport (PDX: -8 → -7) — `with_tz()` against an Olson/IANA zone name
  (e.g. `"America/New_York"`) automatically applies the correct historical DST rule
  for any date, so this fix is retroactively correct back to whenever each airport's
  scraping began, with no DST-boundary-specific code required
- CLT/JFK's separate, pre-existing bug where `datetime`/`date` are built from a
  fixed-offset `'EST'` literal (no DST) was confirmed to never touch `time`/`timezone`
  (both correctly use `America/New_York`), so it did not taint this fix; still an
  open cleanup item for a future pass
- Debugging/verification queries archived at `02_Scripts/archive/xx_utc_local_time_fix_verification.R`

### Infra Fix — EC2 S3 Pull Cron Replaced with Timezone-Aware systemd Timer
- Root-caused why DFW/PHL/LAX (and by extension every airport, every night)
  consistently appeared in the app a full day later than the overnight build
  actually produced fresh data: the EC2 crontab entry (`CRON_TZ=America/New_York`
  + `0 3 * * * aws s3 cp ... && systemctl restart shiny-server`) was silently
  ignoring `CRON_TZ` and firing at 03:00 UTC (server's system time) instead of
  03:00 America/New_York (07:00/08:00 UTC depending on DST) — i.e. ~4 hours
  *before* the Windows-side 2:03 AM ET nightly build had even run, so the pull
  always grabbed the previous night's parquet from S3
- Confirmed via `aws s3api head-object` (S3 object `LastModified` matched the
  correct/current nightly build time) vs. the downloaded file's mtime on EC2
  (matched the *prior* night's build) — proved the push (`paws::s3()` in
  `xx_build_summary_DB.R`) was working correctly and the bug was entirely in
  the EC2-side pull scheduling, not the Windows-side build/push
- Replaced the crontab entry with `tsa-parquet-pull.service` +
  `tsa-parquet-pull.timer` (systemd), using `OnCalendar=*-*-* 03:00:00
  America/New_York` — note the timezone is a *trailing* field per
  `systemd.time(7)`, not a prefix; systemd 255 on this box supports
  timezone-qualified `OnCalendar=` natively (added in systemd v239), so DST
  transitions are now handled automatically with no manual re-tuning twice a
  year
- Old `crontab -e` entry removed entirely; verified via
  `systemctl list-timers` that `NEXT` correctly resolved to 07:00 UTC (3 AM
  EDT) for the current DST period
- Gotcha for future debugging: `aws s3 cp` on this box stamps the downloaded
  file's local mtime to match the **S3 object's own `LastModified`**, not the
  wall-clock download time — don't use local mtime alone to judge whether a
  manual pull test actually ran; compare file size/`ETag` against
  `head-object` instead

### Housekeeping
- Fixed `zz_delete_temp_files.R`: `n_success`/`n_fail` reporting was broken
  because `unlink()` returns a single 0/1 result for the whole call, not a
  per-file vector like `file.remove()` does — `sum(results == 0)` was
  checking one scalar, not counting actual deletions, so `n_success` always
  printed 0
- Fix: capture the total file count before deleting, then after `unlink()`
  check `file.exists()` on the original list to count real failures
  (still-locked files), and derive `n_success` by subtraction
- Verified against the live temp folder: 500 items deleted, 3 failed
  (locked by an active Chrome/scraper process)

## 2026-07-11

### New Airport — LAX Live and Verified
- New `LAX_wait_times.R` (function `scrape_tsa_data_lax`), auto-discovered by
  `scrape_data_automate.R`'s `_wait_times.R` glob — no orchestrator changes
  needed
- Confirmed via claude-in-chrome that `flylax.com/wait-times` is genuinely
  static, server-rendered HTML (a raw `fetch()` with no JS execution already
  returns the populated table; no API/XHR call backs it) — `rvest::read_html()`
  is sufficient, no chromote required, as originally scoped in `todo_list.txt`
- Parses `table.wait-time-table`'s `<tbody>` rows directly rather than via
  `rvest::html_table()` — the table's `<thead>` has a merged "Security Wait
  Times" title row above the real column-header row, which breaks
  `html_table()`'s header detection and also picks up the `<tfoot>` "Data
  Last Updated" row as a phantom data row
- Only 2 rows currently published, both `TBIT` (General Boarding, TSA
  PreCheck) — despite LAX physically having its own security checkpoint at
  nearly every terminal (1–8, T8 sharing T7's), flylax.com's own site does not
  surface live wait data for those terminals on this page. Parser doesn't
  hardcode "TBIT" as the only possible checkpoint — it reshapes whatever rows
  are present, so it won't need changes if LAX adds more terminals to the
  page later
- Guard added: errors if any row's Boarding Type text doesn't map to
  `wait_time`/`wait_time_pre_check`, matching the schema-change guard pattern
  used in CLT/DFW/PHL
- Investigated an apparent ~3 hour discrepancy between flylax.com's wait time
  and news.delta.com/airport-wait-times' displayed LAX wait time — not a data
  quality issue: Delta's page shows a single site-wide "Last updated"
  timestamp (Eastern time, Delta/Atlanta) rather than a per-airport one, and
  the gap lines up exactly with the ET/PT offset. Both sources reflect
  essentially the same moment, just labeled in different timezones
- Live production write confirmed: `scrape_tsa_data_lax()` validated
  end-to-end against `01_Data/tsa_app_test.duckdb` (production `tsa_app.duckdb`
  was unavailable for direct testing — held open by the live Quack server
  process, as expected); 1 row inserted for `airport = 'LAX'`, checkpoint
  `TBIT`, matching schema/types of existing CLT/DFW/PHL rows; test rows
  deleted from the test DB afterward
- Follow-ups filed in `todo_list.txt`: an app-UI note that LAX only publishes
  TBIT wait times (not "LAX has one checkpoint total"), and a lower-priority
  research item to scope the TSA's own Android/mobile wait-times app as a
  potential backup data source for airports with partial official-site
  coverage

## 2026-07-10

### New Airport — DFW Live and Verified
- Replaced the drafted-but-blocked `DFW_in_progress.R` with a working
  `DFW_wait_times.R` (function `scrape_tsa_data_dfw`), auto-discovered by
  `scrape_data_automate.R`'s `_wait_times.R` glob — no orchestrator changes
  needed
- New endpoint: `marketplace.locuslabs.com/venueId/dfw/dynamic-poi`
  (`Origin`/`Referer`/`x-account-id` headers), replacing the old draft's
  non-working `rest.locuslabs.com/.../get-all-dynamic-pois/` URL and its
  incorrect `upperBoundSeconds / 60` field assumption — the real feed
  already reports wait time in minutes
- Filters checkpoint POIs dynamically by `category == "security.checkpoint"`
  instead of a hardcoded POI ID list; the old draft's 24-ID list was already
  stale (missing 4 newer TSA PreCheck POIs added since it was written)
- Maps LocusLabs' `queue.queueSubtype` (`general`/`tsapre`/`priority`) onto
  `wait_time`/`wait_time_pre_check`/`wait_time_priority` — DFW is the first
  airport in the app to populate `wait_time_priority` with real data
  (DFW's "Priority" lane, distinct from TSA PreCheck)
  and nulls out wait time for any POI with `isClosed`/`isTemporarilyClosed`
  true
- Verified against the live `dfwairport.com/security/` page via
  claude-in-chrome: confirmed the JSON endpoint is the same underlying
  LocusLabs data source the site renders, not a mismatched field — apparent
  drift on busy checkpoints is ordinary 5-minute-poll sampling noise
  (consistent with every other airport in this app), not a scraper bug
- Live production write confirmed: 15 checkpoint rows inserted for `airport
  = 'DFW'` via `dbAppendTable` through the Quack client connection

### Data Quality — LGA Mislabeled as JFK (FIXED)
- Root cause found for the "LGA stale timestamp" issue flagged during the
  2026-07-09 Quack cutover verification: not a scraper failure, but a
  copy-paste bug. Two distinct phases:
  - **2026-05-04 → 2026-05-13**: LGA's website changed its checkpoint table
    markup; `LGA_wait_times.R`'s old CSS selector degraded (Terminal A
    stopped 05-04, Terminal B/C stopped 05-13) — a genuine data gap, nothing
    to backfill
  - **2026-06-10 → 2026-07-10**: commit `a4657e8` fixed the scraper for the
    new 2026 website by copy-pasting `JFK_wait_times.R`'s transform block,
    including the literal `airport = 'JFK'`; a same-day follow-up
    (`6779fb2`) renamed the local variable `JFK_data` → `LGA_data` but
    missed the `airport` literal. Every LGA scrape since then ran
    successfully but wrote its rows to `tsa_wait_times` under `airport =
    'JFK'` instead of `'LGA'` — also meant the JFK checkpoint chart in the
    live app was showing 7 checkpoints instead of 5, 2 of which were
    actually LGA data
- Fixed the one-line bug in `LGA_wait_times.R` (`airport = 'JFK'` →
  `airport = 'LGA'`)
- Backfilled 16,388 mislabeled rows in production
  (`UPDATE tsa_wait_times SET airport = 'LGA' WHERE airport = 'JFK' AND
  checkpoint IN ('Terminal B', 'Terminal C') AND datetime >= TIMESTAMP
  '2026-06-10 22:01:15'`), run directly against `con_write` inside the
  Quack server process (Quack clients can't run `UPDATE`) — required a
  brief stop/restart of the `tsa_app_quack_server` task
- Re-ran `xx_build_summary_DB.R` to rebuild `tsa_app_summ.duckdb` /
  `tsa_app_summ.parquet` from the corrected data and pushed to S3

### New Airport — PHL Live and Verified
- New `PHL_wait_times.R` (function `scrape_tsa_data_phl`), auto-discovered by
  `scrape_data_automate.R`'s `_wait_times.R` glob — no orchestrator changes
  needed
- Combines two sources per scrape: a plain JSON GET against
  `phl.org/phllivereach/metrics` (no auth/headers required, unlike CLT/DFW)
  for 6 of 7 checkpoints, plus a static `rvest::read_html()` scrape of the
  `checkpoint-hours` page for Terminal A-West 1, whose wait value is
  manually-maintained static markup with no live feed at all
- Zone ID → checkpoint/lane-type mapping (`3971`/`4126` → Terminal D/E,
  `4368`/`4386` → Terminal A-East, `4377` → Terminal A-West 2, `5047` →
  Terminal B, `5052` → Terminal C, `5068` → Terminal F) sourced directly from
  `wait-api.js`'s own hardcoded `if/else` chain and its accompanying
  `//DE-Precheck: 4126` etc. comment block — verified live against the
  current file at `phl.org/modules/custom/phl_wait_api/js/wait-api.js`, not
  inferred; the feed carries ~14 additional unrelated zone IDs, ignored by
  design. Terminal C's span is misleadingly named `cGen` in the JS but maps
  to `wait_time_pre_check` (Terminal C is PreCheck-only, per the page's own
  text) based on its actual HTML label, not the variable name
- Guard added: errors if any of the 8 expected zone IDs go missing from the
  metrics response (PHL retiring/renaming a zone), rather than erroring on
  the ~14 unmapped extras, which are expected noise
- Terminal A-West 1 gated on a hardcoded 3:00pm–5:30pm clock check (its own
  operating hours) since `wait-api.js` never nulls that value itself outside
  those hours — flagged in `todo_list.txt` to replace with a lookup against
  `airport_checkpoint_hours` once the coordinated hours-of-operation fix
  lands, so no scraper needs a hardcoded window
- Checkpoints written in alphabetical order (`dplyr::arrange(checkpoint)`),
  matching the sort convention used across the project's other scraper
  scripts
- Populated `airport_checkpoint_hours` for PHL's 7 checkpoints from
  `wait-api.js`'s `tHours`/`tAepre`/`tDEpre` objects (cross-checked against
  the page's displayed hours text). First-ever population of this
  previously-empty table — established the convention that the `TIMESTAMP_S`
  date part is the entry date, not a dummy anchor, so future hours changes
  get a new dated row instead of an in-place update, preserving history
- Live production write confirmed: 7 checkpoint rows inserted for `airport =
  'PHL'` via `dbAppendTable`, and 7 rows inserted into
  `airport_checkpoint_hours`, both through the Quack client connection

## 2026-07-09

### Infrastructure — Quack Concurrent DB Access Test (PASSED)
- Goal: eliminate the 4-minute dev windows caused by DuckDB's exclusive
  read-write file lock, which blocks even read-only connections from other
  processes while the scrape orchestrator holds `con_write` open
- Built a standalone test against a throwaway copy of the DB
  (`01_Data/tsa_app_quack_test.duckdb`): `zz_test_duckdb_quack.R` runs the
  Quack server, `xx_test_orchestrator_quack.R` runs 3 lightweight airport
  scrapers (DEN, MSP, CLT — chosen to avoid chromote/RSelenium browser
  overhead) as Quack clients, `xx_test_quack_reader_queries.R` runs
  concurrent reads from a separate session
- Root cause found and fixed along the way: local `duckdb` R package was
  serving DuckDB engine v1.4.3; Quack requires 1.5.3+ (shipped via the core
  extension repository). Updated to current CRAN release (1.5.4.2, engine
  v1.5.4) via `remove.packages("duckdb"); install.packages("duckdb")`
- Result: dry run (write-only) and full concurrency run both completed
  clean — reads returned live rows via `ATTACH 'quack:localhost' AS
  remote_db` while the orchestrator was actively writing, no lock errors
- Not yet rolled out to production `tsa_app.duckdb` or the 12 real airport
  scripts — see `00_Readme/todo_list.txt` for the scoped follow-up work

### Infrastructure — Quack Rolled Out to Production (COMPLETE)
- Confirmed `USE remote_db;` after `ATTACH` makes unqualified table names
  resolve automatically — only `zz_database.R`, `scrape_data_automate.R`,
  `xx_build_summary_DB.R`, and `xx_validate_scrape.R` needed connection-block
  changes; all 12 airport scraper scripts and the build-summary/validate
  query lines were untouched
- `zz_database.R` converted into the persistent Quack server: holds
  `01_Data/tsa_app.duckdb` open, calls `quack_serve()`, and ends in a
  `repeat { Sys.sleep(30) }` keep-alive instead of disconnecting; one-time
  `CREATE TABLE` statements commented out as historical documentation
- Switched all three Task Scheduler jobs (`tsa_app_scraper`,
  `tsa_app_nightly_summary_build`, `tsa_app_scraper_validate`) to run under
  R-4.5.1 instead of R-4.4.3, since R-4.4.3's `duckdb` package (v1.3.2) was
  below Quack's 1.5.3 engine floor; confirmed R-4.5.1 already had every
  package the scraper needs (including RSelenium/chromote) before switching
- Created a new `tsa_app_quack_server` Task Scheduler job for `zz_database.R`
  (Password logon type — "run whether user is logged on or not" — restart
  3x/5min, `ExecutionTimeLimit` unlimited, `DisallowHardTerminate` set)
- Cutover: paused `tsa_app_scraper`, started the Quack server against the
  real database, manually verified a clean write cycle (all 12 airports)
  and a concurrent read against live data, then re-enabled the scraper —
  confirmed working on its regular 5-minute schedule afterward
- Gotchas hit during rollout (see also `DEVELOPMENT.md` if updated):
  Task Scheduler actions need an explicit `WorkingDirectory` or `here::here()`
  resolves against the wrong folder; `Set-ScheduledTask` with only `-Action`
  silently drops other settings objects — always re-supply the full settings
  set; a task registered with "Interactive" logon type gets killed ~30s after
  a manual `Start-ScheduledTask` — needs "Password" logon type to run stably
  the same way the other three jobs do; Git Bash's overridden `HOME` means
  any script run from a Bash shell won't find `.Renviron` in
  `Documents/` and silently falls back to a default token — use PowerShell
  (or native Windows launch) for anything that needs the real
  `DUCKDB_QUACK_TOKEN`
- One live incident during the session: a draft edit was briefly applied to
  the live `scrape_data_automate.R` before the pause window, causing a
  ~20-minute scrape gap (no data loss, no bad rows) — caught via the runlog
  going silent and reverted immediately
- Found in passing, not yet fixed: `LGA` writes report success each cycle but
  `MAX(datetime)` for LGA has been stuck at 2026-05-13 — added to
  `00_Readme/todo_list.txt` for investigation

---

## 2026-07-04

### Infrastructure — EC2 Cron Timezone Bug (CLT Missing from App)
- Investigated: CLT absent from airport dropdown in live app despite confirmed
  fresh scraper data (Checkpoint 1/2/3) in `tsa_wait_times` for Jul 3–4
- Ruled out via diagnostics, in order: source table (data present), nightly
  aggregation in `xx_build_summary_DB.R` (CLT rows present and correct in
  `tsa_wait_time_summ`), S3 push (confirmed via `runlog_appdata_xfer.txt`,
  no errors on Jul 2/3/4 builds)
- Root cause: EC2 root crontab entry (`0 3 * * * aws s3 cp ... && systemctl
  restart shiny-server`) has no `CRON_TZ` set; `timedatectl` confirmed instance
  runs `Etc/UTC`, so the job fired at 3:00 AM UTC (11:00 PM ET the prior night) —
  three hours *before* that night's 2:03 AM ET build even wrote to S3
- Effect: EC2 was permanently serving a parquet one full build-cycle stale,
  every day, since deployment — not specific to CLT, affects all airports'
  freshness by one day, but only became visible once CLT had a full day
  of live data to compare against
- Fix: added `CRON_TZ=America/New_York` above the cron entry so the schedule
  tracks Eastern time (and DST) automatically instead of a fixed UTC offset
- Verified: manual `sudo aws s3 cp` + `sudo systemctl restart shiny-server`
  confirmed CLT displays correctly in app once a fresh parquet is loaded
- No changes required to any R script — `xx_build_summary_DB.R`, `app.R`, and
  `CLT_wait_times.R` all behaved correctly throughout
  
---

## 2026-07-03

### Scraper — CLT Complete Rebuild
- Investigated active bug: CLT checkpoint names and wait times not aligning
  between API response and page display
- Discovered root cause: original `checkpoint-queues/current` endpoint had been
  returning a frozen payload since `2025-04-19T01:20:02Z` — over 14 months of
  stale data written to DB on every scrape cycle; `generatedAt` field confirmed freeze
- Identified new endpoint: `api.cltairport.mobi/wait-times/checkpoint/CLT` —
  no-auth, 200 response, live data confirmed across multiple independent pulls
- New endpoint returns 6 rows; 2 are orphaned legacy records (`isDisplayable = FALSE`,
  stale `lastUpdatedTimestamp`); 4 are live lanes across Checkpoint 1, 2, and 3
- `CLT_wait_times.R` fully rebuilt against new endpoint using `httr2`:
  - Filters on `isDisplayable == TRUE` to drop orphaned legacy rows
  - Maps `attributes.general` / `attributes.preCheck` flags to `wait_time` /
    `wait_time_pre_check` columns via `case_when()` + `pivot_wider()`
  - Sets `wait_time = NA` when `isOpen == FALSE` regardless of `waitSeconds` value,
    preventing stale closed-checkpoint values from being recorded as real waits
  - `round()` applied to both wait time columns before DB write
  - Explicit `stop()` guard before `pivot_wider()`: fires if any `isDisplayable = TRUE`
    row has neither `attributes.general` nor `attributes.preCheck` set — surfaces
    future CLT API schema changes loudly rather than silently writing a malformed column
  - `print(paste("HTTP Status Code:", status))` removed from production function
- `httr2` added to `foo()` package loader in `scrape_data_automate.R` — CLT is
  the only airport currently using `httr2`; `httr` remains for other airports

### Data — CLT Database Cleanup
- Backed up DB as `tsa_app_backup_pre_clt_cleanup_20260702.duckdb` before any writes
- Deleted 234,888 frozen rows: `airport = 'CLT' AND date >= DATE '2025-04-19'`
- Deleted 36,245 all-NA rows: `airport = 'CLT' AND checkpoint = 'Checkpoint A'` —
  this orphaned row was returned by the old API on every cycle but never contained
  real data for its entire recorded history (Nov 2024 – Apr 2025)
- Remaining CLT data: `Checkpoint 1` and `Checkpoint 3`, Nov 27 2024 – Apr 18 2025,
  36,245 rows each — represents the only period of real, non-frozen CLT data
- Note: historical `"Checkpoint 1"` rows physically represent Checkpoint 2 due to
  a CLT backend naming discrepancy introduced when the new checkpoint opened Nov 2023;
  rename deferred until fresh data accumulates — tracked in TODO

---

## 2026-06-28

### Data — IAH Checkpoint Name Normalization
- Investigated IAH checkpoint name variants accumulated across three scraper eras
- Era 1 (Dec 2024 – Mar 2026): old scraper wrote names without "IAH" prefix (`Terminal A North` etc.)
- Era 2 (Mar 2026 – present): current scraper correctly writes `IAH Terminal X` canonical names
- Era 3 (Mar 2026 blip): strip-and-pivot logic temporarily failed; lane suffix left in checkpoint name
- Renamed 5 Era 1 checkpoints to canonical `IAH Terminal X` format (~25K rows each)
- Renamed 5 Era 3 blip checkpoints to canonical format (1–1,294 rows each)
- Deleted 2,684 unrecoverable rows: `Loading`, concatenation glitch, all-null Terminal E blip, ambiguous `Terminal E Pre-check`
- Terminal B retained as-is (historical record, outside 365-day aggregation window)
- Final state: 7 clean checkpoints — `Terminal B` plus 6 canonical `IAH Terminal X` names
- Rebuilt `tsa_app_summ.parquet` and pushed to S3
- Cleanup documented in `zz_iah_database_cleanup.R`

### Data — DCA Junk Checkpoint Cleanup
- Investigated `"Opens 4am"` junk value appearing in DCA checkpoint dropdown
- Root cause: earlier version of flyreagan.com security page rendered the
  hours-of-operation notice inside the same `.resp-table-row` CSS class as
  the wait times table; scraper captured it as a checkpoint name
- Page has since been updated — hours text now lives in `<li>` elements and
  is no longer captured by the scraper; no scraper changes required
- Deleted 68 rows where `airport = 'DCA' AND checkpoint = 'Opens 4am'`
- Rebuilt `tsa_app_summ.parquet` and pushed to S3; DCA dropdown confirmed clean
- Cleanup documented in `zz_dca_database_cleanup.R`

### Data Pipeline — Nightly Validation Script
- Created `xx_validate_scrape.R`: nightly data quality check that runs ~15 min
  after `xx_build_summary_DB.R` and queries yesterday's raw rows from `tsa_app.duckdb`
- Runs five independent checks each night:
  1. Airport total absence — zero rows for any known airport
  2. Row count drop — yesterday's count below 50% of 7-day rolling average
  3. Checkpoint drop-off — checkpoint absent yesterday but present 5+ of prior 7 days
  4. Implausible wait time values — any value outside 0–120 min range
  5. All-NA standard lane — scraper ran but returned no usable wait time data
- Logs result to `runlog_validate.txt` on every run (pass or fail)
- Sends HTML email alert via blastula when any check fails; skips silently if
  credentials missing
- Email credentials: `SMTP_USER` and `ALERT_EMAIL_TO` in `.Renviron`;
  sending credential stored in Windows keystore via `blastula::create_smtp_creds_key()`
- Scheduled in Windows Task Scheduler; task imported from existing working task
  XML to inherit correct user account context

---

## 2026-06-27

### Data — DEN Checkpoint Cleanup
- Investigated two DEN TODO items: Pre✓ missing early morning data and 
  South checkpoint weekday sparsity
- Root cause: Great Hall Project renamed North/South → East/West checkpoints;
  CSS scraper wrote corrupt/null checkpoint names Dec 2024 – Jun 2026 during
  transition; API scraper (live since Jul 2025) captures East/West correctly
- Deleted 158,465 rows where `checkpoint IS NULL` (only 1,122 had non-null
  wait times, all Dec 2024 – Feb 2025, too sparse to salvage)
- Renamed checkpoint variants to canonical API names via three UPDATE statements:
  `West` → `East Security` (35,922 rows)
  `South Security` → `West Security` (35,922 rows)
  `South` → `West Security` (1,803 rows)
- `Bridge Security` (2,021 rows, last seen 2024-12-05) left as-is — outside
  rolling 365-day window, never surfaces in app
- Parquet rebuilt manually and pushed to S3; EC2 pulled and Shiny Server restarted
- Added `rm(s3)` to cleanup block in `xx_build_summary_DB.R`
- Saved investigation script as `zz_den_database_cleanup.R` in `02_Scripts/`

---

## 2026-06-26

### App — UI/UX
- `build_chart()` refactored to accept `lane_label` parameter (`"standard"`, `"precheck"`, `"clear"`); all-NA empty state now renders a lane-specific message instead of the generic fallback — Pre✓ chart displays "No TSA Pre✓ lane at this checkpoint." and CLEAR chart case is pre-wired for when that chart is added
- Both `renderPlot()` call sites updated to pass explicit `lane_label` argument

### AWS Infrastructure
- `flyasap-windows` IAM user scoped to `flyasap-app-data` bucket only via inline policy `flyasap-windows-s3-scoped`; policy grants `s3:PutObject` on `arn:aws:s3:::flyasap-app-data/*` and `s3:ListBucket` on `arn:aws:s3:::flyasap-app-data`; any previously attached broad S3 managed policies removed
- AWS Budget alert configured (`flyasap-monthly-budget`): monthly cost budget with email notification at 85% forecasted and 100% actual spend
- CloudWatch billing alarm configured (`flyasap-billing-alarm`): fires on `EstimatedCharges` exceeding threshold; SNS topic `flyasap-billing-alarm` delivers email notification; billing alerts opt-in enabled at account level (requires root); alarm scoped to us-east-1 (required region for billing metrics)

---

## 2026-06-25

### App — UI/UX
- Replaced invalid `shield-check` icon (FA Pro only) in TSA Pre✓ card header with `plane-circle-check` (FA6 Free); was generating warnings in Shiny Server logs on every session
- Chart x-axis AM/PM label overflow identified — fix pending (labels spilling into adjacent time slots on mobile)

---

## 2026-06-24

### App — Performance
- `bindCache()` added to both `renderPlot()` calls in `app.R` using default `cache = "app"` — app-scoped in-memory cache shared across sessions; nightly Shiny Server restart clears stale cache automatically
- Note: earlier attempt used `cache = cache_mem()` without `cachem::` namespace, which crashed the app on startup; correct call is `cachem::cache_mem()` but unnecessary here since `bindCache()` default behavior is equivalent

### Infrastructure
- AWS EC2 t3.medium (`flyasap-app`) provisioned on Ubuntu 24.04 in us-east-2
- Shiny Server + nginx configured; Let's Encrypt SSL live for `flyasap.app` (.app TLD mandates HTTPS)
- Cloudflare DNS A record pointing to Elastic IP `3.21.184.42`
- IAM users `flyasap-admin` and `flyasap-windows` created; IAM role `flyasap-ec2-s3-read` attached to EC2
- S3 bucket `flyasap-app-data` created in us-east-2
- AWS credentials stored in `.Renviron` on Windows desktop (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION`)
- EC2 nightly cron job configured (3 AM) — pulls parquet from S3, restarts Shiny Server
- **App is live at https://flyasap.app**

### Data Pipeline
- Windows Task Scheduler nightly job configured (2 AM) to run `xx_build_summary_DB.R`
- Parquet export added to `xx_build_summary_DB.R` via `nanoparquet::write_parquet()`
- S3 push added to `xx_build_summary_DB.R` via `paws` (called inline to avoid `glue` 1.8.0 conflict); wrapped in `tryCatch`; bucket `flyasap-app-data`
- `app.R` updated to read `tsa_app_summ.parquet` via `nanoparquet::read_parquet()` at startup, replacing DuckDB/DBI read
- `app_sidebar.R` renamed to `app.R` for Shiny Server compatibility

---

## 2026-06-23

### App — Performance
- `bucket_label` display format changed from 24-hour to 12-hour (`%I:%M %p`) at render time; underlying `bucket_time` filter key preserved as `"HH:MM:SS"` character

---

## 2026-06-19

### Branding
- Domain `flyasap.app` purchased through Cloudflare (`.app` TLD)
- Social handles `@flyasapapp` secured across X, Instagram, TikTok, and Threads
- App name confirmed as ASAP; brand descriptor "Know before you go."
- Confirmed that descriptive use of "TSA" in copy/metadata is legally safe; TSA logo and government affiliation claims are not

---

## 2026-06-17

### Housekeeping
- `xx_cleanup_temp_files.R` written using `unlink(recursive = TRUE, force = TRUE)` to remove `HeadlessChrome*` and `Rtmp*` temp folders generated by headless Chrome on Windows; filed in `02_Scripts/`

---

## 2026-06-15

### App — UI/UX
- Settings offcanvas drawer (dark mode + color toggle) removed for MVP
- Fixed theme: Navy `#2C3E7F` primary, Teal `#18BC9C` accent
- Inter + DM Serif Display loaded via Google Fonts
- Hero band added below navbar with headline "Know before you go." and one-line descriptor
- Smart defaults: day and time selectors auto-set from `Sys.time()` on session start
- Day + time selectors displayed side-by-side on mobile via `layout_columns(col_widths = c(6, 6))`
- Donate prompt changed from pinned footer to 30-second delayed Bootstrap 5 toast
- `selectizeInput` replaced with `selectInput(..., selectize = FALSE)` across all four dropdowns to prevent mobile virtual keyboard from triggering on dropdown interaction
- Chart text and dot sizing increased for mobile readability
- `annotate("text", fontface = "bold")` replaced with `geom_text()` on `data[1, ]` — `annotate()` silently ignores `fontface` in ggplot2

---

## 2026-06-12

### App — Architecture
- `xx_build_summary_DB.R` written: nightly ETL reads `tsa_app.duckdb`, aggregates into 15-minute buckets by airport/checkpoint/weekday, writes `tsa_app_summ.duckdb` and exports `tsa_app_summ.parquet`
- `bucket_time` stored as `"HH:MM:SS"` character in DuckDB (not raw `hms` seconds) to prevent comparison failures on read; parsed back to `hms` in app
- Two-database architecture adopted: `tsa_app.duckdb` for scraping writes, `tsa_app_summ.duckdb` for app reads — avoids DuckDB concurrent read/write constraint without requiring beta Quack protocol
- `app.R` built on bslib/Bootstrap 5 with `page_fillable()`, `layout_columns()`, `breakpoints(sm = 12, lg = c(3, 9))`, and custom `tags$nav` navbar
- Checkpoint dropdown dynamically populated from selected airport via pre-computed lookup at startup; `updateSelectInput()` used at runtime
- `build_chart()` helper renders both standard and TSA Pre✓ lane charts with `ggrounded` rounded bars, avg bar labels, and max wait dot annotation
- Double newlines in `runlog.txt` fixed: replaced `print(glue(...))` with `cat(glue(...), "\n")` inside `sink()`

### Scraper Fixes
- All 12 active airport scrapers passing in orchestrator run (~1 min 39 sec per cycle)
- ATL: fixed terminal/checkpoint name building; handled closed checkpoints marked as `"X"`
- DCA: rewrote scraping to use `purrr::map_chr` pulling cells by position from `.resp-table-row` — eliminated `stri_list2matrix` ragged matrix failures
- JFK + LGA: updated to new Port Authority Chakra UI selector; `"No Wait"` → `0` conversion added
- EWR: updated selector; concatenated `Terminal + Gates` columns for granular checkpoint names; `"No Wait"` → `0` conversion added

---

## 2026-06-11

### Scraper Fixes
- DEN: pivoted from Cloudflare-blocked chromote scrape to backend API at `app.flyfruition.com/api/public/tsa`; `upper_bound()` helper parses range strings (e.g., `"9-13"`) conservatively
- JFK, LGA, EWR (Port Authority): updated CSS selectors from `.av-responsive-table` to `.chakra-table__root.Table_tableContainer__Hwsqp` following 2026 site redesign

---

## 2026-06-10

### Scraper Fixes
- IAH: rewrote `IAH_error.R` → `IAH_wait_times.R`; single-pass scrape replaces old two-pass tab-click; `pivot_wider()` splits Standard/PreCheck/Premier lane types into schema columns; June 2026 `tryCatch` teardown pattern applied
- `chrome-headless-shell` binary (`chromote::local_chrome_version(version = "latest-stable", binary = "chrome-headless-shell")`) added inside all chromote scrape functions — eliminates `HeadlessChrome*` temp file accumulation (was generating 100GB+ per day)
- Teardown pattern standardized across all chromote scripts: `page$session$close()` → `page$session$parent$close(wait = 3)` → `chromote::set_default_chromote_object(NULL)` guard, wrapped in `tryCatch`
- `reset_chromote()` helper added to `scrape_data_automate.R` — clears lingering default chromote object before each airport function call
- `safe_read_html_live()` rewritten to throw catchable errors instead of calling `quit()` — enables `tryCatch` isolation in orchestrator

---

## 2026-06-09

### New Airports (Research)
- BOS: Zensors tRPC API reverse-engineered; `BOS_wait_times.R` drafted using `purrr::pmap()` over checkpoint map; needs live test
- LAX: `flylax.com/wait-times` confirmed as static HTML; `LAX_wait_times.R` drafted using `read_html()` + `html_table()`; needs live test
- SEA, SLC, DTW: domain-blocked from static fetch; require live DevTools investigation before scripting

---

## 2026-06-06

### Scraper — Orchestrator
- `tryCatch` error isolation added to `lapply` in `run_all_functions()` — individual airport failures no longer kill the entire orchestrator run
- Single retry pass added for failed airports after primary run completes
- `bitops` package identified as missing RSelenium transitive dependency; resolved with `install.packages("bitops")`

---

## 2026-05-31

### Project Setup
- R project initialized: `01_Data/` / `02_Scripts/` / `03_App/` folder structure
- DuckDB schema created (`tsa_wait_times`, `airports`, `airport_sites`, `airport_checkpoint_hours` tables)
- Initial airport scrapers operational: ATL, CLT, DCA, DEN, EWR, IAH, JFK, LGA, MCO, MIA, MSP, PDX
- `scrape_data_automate.R` orchestrator written with `foo()` package management and `sink()` run logging
- `here::here()` adopted for path portability across RStudio and Positron
- GitHub repo created at `github.com/amurtha80/tsa_app`; `01_Data/` gitignored
- Custom coding style and conventions finalized (pipe usage, scraper function pattern, DuckDB style, Shiny preferences)