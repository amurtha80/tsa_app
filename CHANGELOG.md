# Changelog
FlyASAP — Airport Security Advance Planning

---

## 2026-07-14 (5)

### Refactor — MCO Scraper Migrated from RSelenium/Chromote to JSON API
- Replaced `MCO_wait_times.R`'s RSelenium/Firefox headless-browser scrape of the
  flymco.com rendered page with a plain `httr2` GET against
  `api.goaa.aero/wait-times/checkpoint/MCO` (`api-key`/`api-version`/`Origin`/
  `Referer` headers) — endpoint confirmed via the user-supplied
  `MCO_in_progress.R` stub and a live curl fetch. Old RSelenium version archived
  to `02_Scripts/archive/MCO_scrape_v1.R` (first archive for MCO).
- The API returns one per-lane object per `South|West|East` × `Standard|
  PreCheck` lane, with live `isOpen`/`isDisplayable` flags, `waitSeconds`/
  `minWaitSeconds`/`maxWaitSeconds`, and `attributes.minGate`/`maxGate`.
  Checkpoint naming is derived from each lane's own gate range as `"Gates
  {min} - {max}"` rather than the `Side` label — reproduces the DB's existing
  3-checkpoint convention exactly (`Gates 1 - 59`, `Gates 70 - 129`, `Gates
  C230 - C254`). No CLEAR lane in the payload, `wait_time_clear` stays NA as
  before.
- Conservative wait parsing reused verbatim from `IAH_wait_times.R`: prefer
  `max(waitSeconds, maxWaitSeconds)` over the bare `waitSeconds` value.
- Primary gate is the API's own live per-lane `isOpen`/`isDisplayable` flags.
  Unlike IAH/PDX, this API never populates `openTime`/`closeTime` (null on
  every lane observed), so the pre-existing `airport_checkpoint_hours`
  time-of-day gate (already correct from the 2026-07-12 MCO hours fix, no
  changes needed this time) serves as the sole backstop — no live Quack-server
  restart was required for this migration.
- Verified end-to-end: scratchpad dry-run (write disabled, full tibble
  printed) matched a same-moment raw JSON fetch exactly (6/5, 13/3, 13/4
  minutes across South/West/East General/PreCheck) before promoting the file
  between live orchestrator cycles.

## 2026-07-14 (4)

### Refactor — PDX Scraper Migrated from Chromote to JSON API
- Replaced `PDX_wait_times.R`'s chromote/rvest scrape of the flypdx.com rendered
  page with a plain `httr2` GET against `flypdx.com/TSAWaitTimesRefresh`
  (cache-busting `_` query param, `Referer`/`X-Requested-With` headers) — endpoint
  confirmed via the user-supplied `PDX_in_progress.R` stub. Old chromote version
  archived to `02_Scripts/archive/PDX_scrape_v1.R` (first archive for PDX).
- The API returns one `WaitTimes` entry per `North|South` × `General|Precheck`
  counter plus live per-checkpoint `NorthCheckpointClosed`/`SouthCheckpointClosed`
  booleans and open/close timestamps. `North` maps to `"Security checkpoint for
  gates DE"`, `South` to `"Security checkpoint for gates BC"` — matches the DB's
  existing checkpoint-naming convention exactly. No CLEAR field, `wait_time_clear`
  stays NA as before.
- Primary gate is the API's own live `Closed` booleans per checkpoint; the
  existing `airport_checkpoint_hours` time-of-day backstop gate was kept
  alongside it (unproven reliability of the new flag over time), same reasoning
  as the DCA/IAH migrations.
- Cross-referencing the JSON's live open/close times against `airport_checkpoint_hours`
  found `Security checkpoint for gates BC`'s `close_time_gen` stale (22:00 -> 21:00)
  and `Security checkpoint for gates DE`'s general hours entirely unpopulated
  (added: 03:00 -> 21:30). Corrected via a direct (non-Quack) connection, anchored
  off `open_time_gen`/`open_time_prechk`'s date per the IAH lesson. Required
  stopping/restarting `tsa_app_quack_server`.
- Verified end-to-end: scratchpad dry-run (write disabled) matched the live API
  response exactly for both checkpoints' General/PreCheck values; confirmed live
  in the 1:55 PM orchestrator cycle with correct rows landing for both checkpoints.
- Note: the Quack server restart took longer than the usual single scrape gap
  (a `Start-ScheduledTask` restart attempt silently failed, and a manual Git-Bash
  launch picked up the wrong token per the known `.Renviron`-under-Git-Bash gotcha)
  — caused ~6 missed 5-minute scrape cycles (~1:20-1:50 PM) across all 16 airports
  before the server came back up correctly. No lasting effect once fixed.

## 2026-07-14 (3)

### Refactor — IAH Scraper Migrated from Chromote to JSON API
- Replaced `IAH_wait_times.R`'s chromote/rvest scrape of `fly2houston.com/iah/security/`
  with a plain `httr2` GET against `api.houstonairports.mobi/wait-times/checkpoint/iah`
  (`api-key`/`api-version`/`Origin`/`Referer` headers) — endpoint discovered via browser
  network inspection. Old chromote version archived to `02_Scripts/archive/IAH_scrape_v2.R`
  (v1 was already archived from an earlier iteration).
- The API returns one object per checkpoint-lane with `name` ("IAH Terminal A North
  Standard"), `openTime`/`closeTime`, `isOpen`, `isDisplayable`, `waitSeconds`, and
  `min`/`maxWaitSeconds`. Physical checkpoint = `name` with the trailing
  `Standard`/`PreCheck`/`Premier` token stripped, same 6-checkpoint convention already in
  the DB. `wait_time_clear` remains NA — no CLEAR-specific field exists in the payload.
- The payload also includes an `"Int'l Arrivals Customs Checkpoint"` (FIS/CBP) entry.
  Confirmed via the live rendered page that it was never part of what this scraper
  collects (only the 9 TSA lane-cards render there) — excluded per explicit instruction
  to change *how* the data is fetched, not *what* is fetched.
- Primary gate is now the API's own live per-lane `isOpen`/`isDisplayable` flags; the
  existing `airport_checkpoint_hours` time-of-day backstop gate (scoped to `IAH Terminal
  A South`'s Standard lane, for the known overnight stale-reading issue) was kept
  alongside it, not removed.
- Cross-referencing the JSON's live `openTime`/`closeTime` against both the existing
  `airport_checkpoint_hours` table and the live page's own "Hours:" text found 3 stale
  rows and corrected them via a direct (non-Quack) connection: `IAH Terminal A South`
  `close_time_gen` 00:00 -> 23:00, `IAH Terminal D` `close_time_gen` 20:00 -> 22:30 (was
  incorrectly nulling real evening wait data), `IAH Terminal E` `close_time_prechk` 20:00
  -> 19:30. Required stopping/restarting `tsa_app_quack_server` since Quack clients can't
  run `UPDATE`. A first-pass UPDATE for A South anchored the new close time off the old
  (already midnight-rolled) date instead of `open_time_gen`'s date, producing a one-day-off
  timestamp; caught before restarting the server and corrected with a second UPDATE.
- Terminal D's published hours actually run a split shift 4 of 7 days (see
  `todo_list.txt`) — the single open/close pair can't represent that gap, so the live
  `isOpen`/`isDisplayable` flags (not the hours table) are what protect against it now.
- Verified end-to-end: scratchpad dry-run (write disabled) matched the live page exactly
  across all 9 lane readings; promoted between orchestrator cycles; multiple consecutive
  live cycles (12:25 PM - 12:45 PM) confirmed via Quack with all 6 expected checkpoint
  names and plausible values; `airport_checkpoint_hours` corrections confirmed via
  before/after `SELECT`s and a final Quack read-only check post-restart.

## 2026-07-14 (2)

### Refactor — DCA Scraper Migrated from Chromote to JSON API
- Replaced `DCA_wait_times.R`'s chromote/rvest HTML scrape with a plain `httr2` GET
  against `flyreagan.com/security-wait-times` — discovered via browser network
  inspection of the rendered security-information page (the old file's approach was
  chromote-based; no JSON endpoint had been identified before this session). Old
  chromote version archived to `02_Scripts/archive/DCA_scrape_v2.R` (v1 was already
  archived from an earlier iteration).
- The API returns one flat object per checkpoint (keyed `A`/`B`/`D`, not stable
  airport-side identifiers) with `location`, `gates`, `waittime` (General), `pre`
  (TSA PreCheck), `isDisabled`, and `pre_disabled` — no CLEAR data, and no per-lane
  or per-checkpoint timestamp field (the "Last updated" shown on the rendered page is
  a page-render artifact, not part of the API payload). Checkpoint name is built as
  `str_squish(paste(location, gates))`, which reproduces the existing DB convention
  exactly (`"Terminal 1 ( A Gates)"`, etc.) with no transformation needed.
- Occasionally the API returns a wait-time range (e.g. `"4-7 mins"`) instead of a
  single value. Parsing now extracts every number present and takes the max —
  a conservative choice so a range never understates the wait. Validated live: the
  page showed `"4-7 mins"` for Terminal 2 North during testing and the scraper
  correctly recorded 7.
- Kept the pre-existing `airport_checkpoint_hours` time-of-day gate (forces NA
  outside published hours) in addition to honoring `isDisabled`/`pre_disabled` from
  the API — the original file's gate exists because flyreagan.com doesn't reliably
  clear a stale reading after a checkpoint closes for the night, and that risk isn't
  known to be fully covered by the new API's own disabled flags yet.
- Verified end-to-end: scratchpad dry-run against the live API (write disabled,
  full tibble printed and cross-checked against the rendered page) before promoting
  the file, then confirmed the very next live orchestrator cycle (10:25 AM) picked up
  the renamed file automatically and appended clean rows for all 3 checkpoints with
  no errors, confirmed via a Quack read-only query.

## 2026-07-14

### Fix — Checkpoint Whitespace Normalization (Validator False-Positive + Scraper Hardening)
- Root-caused a scrape validation alert for PDX (2 checkpoints flagged as dropped on
  2026-07-13): a prior formatting fix had changed the stored checkpoint string from an
  embedded literal newline to a plain space. Data collection never actually stopped —
  the validator's day-over-day exact string match just saw it as one checkpoint
  vanishing and a new one appearing.
- Hardened `xx_validate_scrape.R`: checkpoint names are now whitespace-normalized once
  at read time, so a pure scraper formatting change no longer trips a false drop-off
  alert.
- Audited all `*_wait_times.R` scrapers for the same class of risk and added
  whitespace normalization to the 13 that were missing it (all except PDX, which
  already had it, and DFW/PHL, which are immune by construction). Each was verified
  with a live scratchpad dry-run against the real site/API before being applied to
  the production file, then confirmed clean in a full live orchestrator cycle and a
  follow-up DB query (zero rows with embedded/irregular whitespace).

## 2026-07-13 (3)

### New Airport — SEA (Seattle-Tacoma) Scraper Live
- Added `SEA_wait_times.R`. Turned out not to need chromote (contrary to the original
  todo note) — `portseattle.org/api/cwt/wait-times` is a plain JSON API, no auth
  required. General/PreCheck/CLEAR all share one `WaitTimeMinutes` value per
  checkpoint; a lane only gets that value when the API's live `Options` list marks it
  `"Available"`, otherwise NA (matches the rendered page's lane badges 1:1, verified
  in-browser against all 6 checkpoints).
- Populated `airport_checkpoint_hours` for SEA's 6 checkpoints (hours + lane
  capability from Port of Seattle's published checkpoint info); Checkpoint 4 (open 24
  hours) uses the existing midnight-to-midnight convention already used for JFK
  Terminal 1 PreCheck.
- Verified end-to-end: ran the orchestrator manually, confirmed it auto-discovered
  the new `*_wait_times.R` file and wrote real rows to `tsa_wait_times` via Quack.

## 2026-07-13 (2)

### Feature — LGA Terminal A "Not Currently in Use" Status (Spirit Airlines Shutdown)
- Spirit Airlines ceased all operations at 3:00 AM ET on 2026-05-02, vacating LGA's
  Marine Air Terminal (Terminal A) entirely. LGA's live wait-time site stopped listing
  the checkpoint shortly after — the scraper's last real Terminal A row is
  2026-05-04 20:25 (a two-day-stale "1 min" ghost reading before the row disappeared
  from the site). There's no current plan to permanently close the terminal, so this
  needed to be a reversible status flag, not a deletion.
- Added `is_active` (BOOLEAN, default TRUE) to `airport_checkpoint_hours`. Inserted a
  new LGA Terminal A row with `is_active = FALSE`, carrying forward its existing
  general/PreCheck/CLEAR hours unchanged (append-only convention — no UPDATE).
- `xx_build_summary_DB.R`: when a checkpoint's latest `airport_checkpoint_hours` row
  has `is_active = FALSE`, all three wait-time columns are forced to NA for every
  bucket regardless of time-of-day (bypasses the hours-of-day check entirely — this
  is a different situation from a nightly closure). `is_active` is carried through
  into `tsa_wait_time_summ` (constant per airport/checkpoint) so the app can read it
  without a second lookup.
- `app.R`: `build_chart()` now takes a `checkpoint_active` flag and shows
  "This checkpoint is not currently in use." — checked *before* the existing
  `lane_exists_elsewhere` check, since an inactive checkpoint has no data anywhere
  (not just the selected window), which would otherwise trip the "no lane at this
  checkpoint" / "no wait time data" messages instead. Terminal A stays selectable in
  the dropdown rather than disappearing.
- Verified live: ran `xx_build_summary_DB.R` manually, confirmed all 672 LGA Terminal A
  buckets NA with `is_active = FALSE` in the parquet, then ran the app locally and
  confirmed both Standard and PreCheck panels show the new message for Terminal A
  while Terminal B/C render normally with real data (no regression).
- **Reactivation**: when Terminal A returns to service, insert one new
  `airport_checkpoint_hours` row with `is_active = TRUE` — no code change needed.

## 2026-07-13 (1)

### Data Quality — EWR: Data-First Analysis, Terminal B Scraper Bug Found and Fixed, PreCheck Hours Set
- Changed methodology per explicit user direction: instead of the JFK/LGA approach of
  bouncing between site-listed hours, Google-search hours, and scraper data, did EWR
  data-first — pulled a 45-day hourly profile (`pct_na`, `pct_zero`, mean wait) per
  checkpoint/lane via Quack, then sanity-checked the method itself against JFK Terminal
  7 (confirmed open 05:00-23:00) before touching any online source. That calibration
  revealed the method has a real blind spot: JFK T7's PreCheck field is 100% NA at
  *every* hour despite the checkpoint being open (a scraper coverage gap, not a status
  signal), and its genuinely-closed overnight hours (0-4am) still read as 0% NA / 0%
  zero — indistinguishable from a real-but-quiet open period. So the NA/zero-cliff
  method can detect a checkpoint that goes fully silent (worked cleanly for EWR
  Terminal A) but can't distinguish "24hr with low overnight traffic" from "closed but
  still emitting a low baseline reading" for EWR Terminal B/C.
- User then redirected away from `tsa.gov/precheck/schedule` entirely (used for
  JFK/LGA) back to Google search + `04_Assets/tsa_checkpoint_hours.html`, citing it as
  a likely source of the JFK/LGA back-and-forth. Confirmed the html file's existing EWR
  general hours already match the current `airport_checkpoint_hours` DB values exactly
  (both ultimately sourced from the same prior research) — no PreCheck data existed in
  either.
- **Root cause found for a long-standing EWR data quality issue**: newarkairport.com's
  live wait-time table has 4 columns — `Terminal | Gates | General | TSA Pre✓` — with 5
  rows every scrape (Terminal A/All Gates, Terminal B/40-49, Terminal B/51-57, Terminal
  B/60-68, Terminal C/All Gates). `EWR_wait_times.R` was doing `rename(checkpoint =
  Terminal)`, which kept the Terminal column but silently dropped Gates, collapsing all
  3 Terminal B rows into identical `checkpoint = "Terminal B"` values on every single
  scrape since the scraper's inception. This explains both the 3x row-count ratio
  (313,458 EWR Terminal B rows vs 104,494 each for A/C) and the flat 66.7%-NA-at-every-
  hour PreCheck artifact found during the JFK-T7-calibrated sanity check (2 of every 3
  gate groups never carry PreCheck at all — confirmed against the live official page,
  where only 40-49 shows a `TSA Pre✓` value and 51-57/60-68 show `-`).
- Verified the fix was safe before applying: across the full history (104,485 distinct
  scrape timestamps), Terminal B rows came in groups of exactly 3 with zero exceptions,
  in a stable scan order confirmed by running the same query 3 times with identical
  results, and position 1 carried a non-NA PreCheck reading 99.5% of the time (position
  2/3: 0.01-0.02%) — strong confirmation that position 1=40-49, 2=51-57, 3=60-68.
- Stopped `tsa_app_quack_server` (explicit user authorization, "sacrifice a few
  scrapes") and ran a direct `UPDATE ... FROM` keyed on DuckDB's `rowid` plus
  `row_number() OVER (PARTITION BY datetime ORDER BY rowid)` to relabel all 313,458
  historical "Terminal B" rows into `Terminal B 40-49`/`Terminal B 51-57`/`Terminal B
  60-68`. Post-update counts: 104,494 rows each, exactly matching A and C. Fixed
  `EWR_wait_times.R` to capture the Gates column going forward (`checkpoint =
  if_else(Gates == "All Gates", Terminal, paste(Terminal, Gates))`).
- Also found (official newarkairport.com Terminal B page) that the html file's
  existing "Terminal B general hours" (4:30am-7:30pm Sun-Fri / 4:30am-6pm Sat) is
  actually **CLEAR hours for gates 40-49 specifically**, mislabeled as general hours by
  the prior research — left as-is per explicit user instruction not to adjust backend
  data on this task, but noting the mislabel for future reference. An official
  EWRairport X/Twitter post found via search: "TSA security checkpoint hours at
  Terminals A and C offer from 4 AM to 12 [AM], while Terminal B operates based on
  flight schedules" (i.e. no fixed hours for B) — consistent with the data-first
  finding that Terminal B's standard lane never goes to zero/NA at any hour.
- Per explicit user instruction (no further analysis/hedging): inserted new
  `airport_checkpoint_hours` rows for EWR Terminal A/B/C with `open_time_prechk` =
  04:00, `close_time_prechk` = 20:00, carrying forward each checkpoint's existing
  general hours unchanged, `clear` columns left NULL.
- **Known follow-up gap**: `xx_build_summary_DB.R`'s hours-based filtering joins
  `tsa_wait_times.checkpoint` to `airport_checkpoint_hours.checkpoint` by exact name.
  Since `airport_checkpoint_hours` still has only one "Terminal B" row, the 3 newly-
  split checkpoints won't match it — `is_open()` treats an unmatched (NA) lookup as
  unrestricted, so no hours-based filtering applies to any of the 3 EWR Terminal B
  checkpoints until matching rows are added. See `todo_list.txt`.

## 2026-07-12 (6)

### Data Quality — JFK and LGA PreCheck/CLEAR Hours Populated from TSA's Own Schedule Tool
- Discovered `tsa.gov/precheck/schedule` publishes per-checkpoint PreCheck hours for
  JFK and LGA even though neither airport's own site does — walked through every
  time window on a single representative day (Monday) for both airports via
  claude-in-chrome to build each checkpoint's open/close pattern.
- **JFK**: added `open_time_prechk`/`close_time_prechk` for all 5 checkpoints.
  Terminal 4's "Terminal 4 Main Checkpoint" and "Checkpoint 96/Terminal 4 Delta 1"
  are tracked as one `Terminal 4` row in `tsa_wait_times`, so their PreCheck hours
  were reconciled to the general-hours window (04:30-23:00) rather than either raw
  reading. Terminal 1 set to 24hr PreCheck as a judgment call after the schedule
  tool's claimed overnight closures conflicted with its own general hours — see the
  new `todo_list.txt` item for the planned 1-month recheck. `open_time_gen`/
  `close_time_gen` left as-is for all 5 checkpoints (matches
  `04_Assets/tsa_checkpoint_hours.html`, the verified general-hours source).
- **LGA**: added `open_time_prechk`/`close_time_prechk` and `open_time_clear`/
  `close_time_clear` (CLEAR mirrors PreCheck at LGA) for all 3 checkpoints, using a
  4am-8pm default with two exceptions found via the schedule tool: Terminal B opens
  at 3am (confirmed at the exact hour boundary), and Terminal A has no dedicated
  PreCheck listing in the tool at all despite having general hours — defaulted to
  4am-8pm anyway as a judgment call. Both exceptions flagged in `todo_list.txt` for a
  1-month recheck.
- **Real bug found and fixed**: an initial JFK insert used `as.POSIXct(..., tz =
  "America/New_York")`, which the DBI/duckdb write path silently converted to UTC on
  write (this table's `TIMESTAMP` columns are naive local time, not tz-aware) —
  shifted every value +4 hours. Caught before it reached the app, but the bad rows'
  `entry_timestamp` was also shifted forward, meaning `slice_max` would have picked
  the *wrong* row over the corrected fix. Deleted the 5 bad rows via direct
  connection (`epoch(entry_timestamp)::BIGINT` match — plain `epoch()` returns a
  fractional value, so an unqualified integer comparison silently matched nothing on
  the first attempt). Rewrote the write path to construct all datetimes with `tz =
  "UTC"` (a literal copy of the intended wall-clock value, since the column doesn't
  actually store UTC) instead of the airport's real timezone — avoids the driver's
  implicit conversion. LGA's write used this corrected pattern from the start with no
  issue.
- Stopping `tsa_app_quack_server` for the JFK DELETE briefly interrupted two 5-minute
  scraper cycles (9:40pm and 9:45pm) — both simply skipped writing that cycle, no
  data corruption; scraper resumed normally the next cycle. LGA's write needed no
  server restart (append-only INSERT works fine through a Quack client).
- Investigated whether ~21 days of scraped `tsa_wait_times` data could settle JFK
  Terminal 1's overnight-closure question independently of either published source.
  Inconclusive: `wait_time_pre_check` turned out to be non-NA at 100% of readings for
  4 of JFK's 5 checkpoints across every hour of the day regardless of the schedule
  tool's claimed closures, while the 5th checkpoint (Terminal 7) was 0% non-NA at
  every hour including its own confirmed-open hours — the field doesn't reliably
  track true open/closed status, so real usage data was not used to override the
  published schedule for this decision.
- Updated the stale `todo_list.txt` item claiming JFK/EWR/LGA have no official
  checkpoint-hours source — narrowed to EWR only, noting the schedule-tool approach
  to try there next (planned for 2026-07-13).

## 2026-07-12 (5)

### Data Quality — MCO Standard-Screening/CLEAR Hours Populated
- Closed the `todo_list.txt` item "MCO Standard-Screening/CLEAR Hours Unrecorded".
  flymco.com/security/ confirmed standard checkpoints and PreCheck lanes both operate
  4:00 AM – 8:30 PM, and CLEAR is available at the same hours as standard/PreCheck at
  all three checkpoints. Set `open_time_gen`/`close_time_gen` and
  `open_time_clear`/`close_time_clear` to match the existing `prechk` window
  (04:00:00–20:30:00) for all three MCO checkpoints (`Gates 1 - 59`, `Gates 70 - 129`,
  `Gates C230 - C254`) in `airport_checkpoint_hours`. MCO's separate "Reserve" slot
  program (5:00 AM–5:00 PM booking window for 6:30 AM–8:30 PM departures) is a
  reservation system, not a checkpoint operating window, so it was not applied here.
- Update required a direct (non-Quack) connection since Quack clients can't run
  `UPDATE`: stopped `tsa_app_quack_server` after confirming the 7:00 PM scraper run
  finished, ran the `UPDATE` directly, verified before/after via `SELECT`, then
  restarted the task and re-verified through a Quack client read.

## 2026-07-12 (4)

### Data Quality — Checkpoint Hours Re-Verified Against Official Sources
- Closed the `todo_list.txt` item "Data Quality — Checkpoint Hours Need Re-Verification".
  Researched official/authoritative sources for all flagged checkpoints: JFK (Terminal
  1/4/5/7/8), EWR (Terminal A/B/C), LGA (Terminal A/B/C), MIA (checkpoints 2 and 7), DEN
  (East/West Security), ATL (`INT'L MAIN`), IAH (Terminal C South and D), and LAX (TBIT).
  - **JFK, EWR, LGA**: no official airport or terminal-operator page publishes
    checkpoint-level operating hours at all (only live/average wait times) — remain
    unverifiable against a primary source; current DB values left as-is since nothing
    contradicts them and no better source exists.
  - **ATL `INT'L MAIN`, IAH Terminal C South/D, LAX TBIT**: matched the airport's own
    official source (ATL, IAH) or consistent secondary sources (LAX — flylax.com blocks
    non-browser fetches, so still medium-confidence but no longer contradicted). No
    changes needed.
  - **MIA checkpoint 2**: DB had close time 11:45 pm; official
    miami-airport.com/airport-security.asp states 10:45 pm. Corrected (1-hour conflict).
  - **DEN East/West Security**: DB had asymmetric hours (East 3:00a–8:00p, West
    3:30a–1:00a); flydenver.com/security states both checkpoints share identical hours,
    3:00a–1:00a standard / 4:00a–8:45p PreCheck. Corrected both to match.
- **Found and fixed a real bug** in the append-only-history design for
  `airport_checkpoint_hours` while preparing the MIA/DEN corrections: the table's
  `TIMESTAMP_S` columns' date part is only an entry-date anchor with no time-of-day
  meaning, so a same-day correction ties with the row it's meant to replace —
  `xx_build_summary_DB.R`'s "take the most recent row per checkpoint" join had no way
  to break that tie and, verified via a dry-run simulation, would have silently kept
  the *old* (wrong) row. Added a dedicated `entry_timestamp TIMESTAMP` column (real
  write-time, distinct from the schedule's own open/close columns); backfilled existing
  rows to midnight of their anchor date and set new correction rows to
  `CURRENT_TIMESTAMP`, so ranking is now unambiguous. Updated `hours_lookup` in
  `xx_build_summary_DB.R` to dedupe on `entry_timestamp` via `slice_max(..., n = 1,
  with_ties = FALSE)` per `(airport, checkpoint)` instead of the old derived-date
  approach. Verified `slice_max` correctly keeps single-row groups even when
  `entry_timestamp` is NULL (checkpoints with no hours data at all, e.g. all 15 DFW
  checkpoints — `is_open()` already treats NA open/close as "no restriction" either way).
- Schema change and corrective INSERTs required a direct (non-Quack) connection —
  `ALTER TABLE` isn't supported through the Quack remote connection. Stopped
  `tsa_app_quack_server` ~2 minutes after a scheduled scraper run, applied the changes,
  verified row counts (73 → 76) and the dedup logic against real data, then restarted
  the task and confirmed the next scraper run (5:35 PM) wrote successfully with
  `LastTaskResult = 0`.
- **MCO Gates 70-129** standard/CLEAR hours remain genuinely unresolved — flymco.com's
  security page has no gate-specific breakdown, only an airport-wide PreCheck window and
  a blanket CLEAR-availability note. Left open in `todo_list.txt` as it needs a phone
  call or another source, not further web research.
- No forced parquet rebuild needed — `xx_build_summary_DB.R` runs nightly and rebuilds
  from scratch each time, so the corrected hours automatically apply starting with
  tonight's run.

## 2026-07-12 (3)

### Data Quality — Stale Overnight Wait-Time Values Fixed (scraper-level)
- Closed the `todo_list.txt` item "Data Quality — Stale Overnight Wait-Time Values",
  fixing all 5 checkpoints/airports the 2026-07-12 systematic overnight audit flagged as
  showing the same single flat number during their published closed hours, confirmed via
  a fresh 7-day hour-by-hour query against each checkpoint before touching any scraper:
  - **DCA** — all 3 terminals flatlined around 4-5 min for the whole 9pm/11pm–4am closed
    window (confirmed real variation 3-11+ min during open hours). Added an
    `airport_checkpoint_hours` lookup gating `wait_time`/`wait_time_pre_check` per
    checkpoint (three different close times: 9pm/11pm/9pm), same pattern as PHL A-West 1
  - **IAH Terminal A South** — flatlined at 3 min from midnight to its 3:30am open.
    Gated *only* this checkpoint (not IAH-wide): IAH's C South and D terminals are
    separately flagged as possibly having too-conservative researched hours, so an
    airport-wide gate risked nulling real data there instead of stale data
  - **MIA checkpoints 4 and 10** — checkpoint 4 is a genuinely low-traffic checkpoint
    (~0 min nearly all day) with only a brief stale-carryover tail past its 8:15pm close;
    checkpoint 10 flatlined at 3 min for roughly an hour past its 7:15pm close before the
    site itself eventually nulled it. Gated only checkpoints 4 and 10 (not MIA-wide) for
    the same reason as IAH — checkpoints 2 and 7 are separately flagged as possibly
    under-researched hours
  - **MSP T2 Checkpoints 1 and 2** — both held a stale ~5 min reading (the site's own
    minimum display tier) in the hour before their shared 4am open. Gated both against
    their published 4am–10pm window
  - **PHL Terminal A-East and Terminal F** — both flatlined at ~3 min for the entirety of
    their closed hours (confirmed via the live `/phllivereach/metrics` feed's zone IDs),
    while still showing real variation mixed with occasional low (~3 min) readings during
    open hours. Gated only these two zones from the feed, not the other live-feed
    checkpoints (D/E, A-West 2, B, C), which weren't flagged
- Fix shape is uniform across all 5: a per-checkpoint (never airport-wide) lookup against
  `airport_checkpoint_hours`, reducing the stored `TIMESTAMP_S` open/close to
  time-of-day + an overnight-wrap check, nulling the affected wait-time column(s) when
  outside the published window — same pattern established by the PHL A-West 1 fix.
  Verified each gate's open/closed boundary against real data before editing, and
  re-verified the implemented logic against synthetic timestamps (midnight, boundary
  minutes, midday) after editing, before considering any checkpoint done
- Checked `Get-ScheduledTask` state for `tsa_app_scraper` (Ready, not mid-run) before
  editing any of the 4 live scraper scripts (`DCA_wait_times.R`, `IAH_wait_times.R`,
  `MIA_wait_times.R`, `MSP_wait_times.R`, `PHL_wait_times.R`)
- Deliberately did not touch the separate "Checkpoint Hours Need Re-Verification" item
  (JFK, EWR, LGA, MIA 2 & 7, DEN, ATL `INT'L MAIN`, IAH C South & D, LAX) — those need
  hours-table corrections, not scraper-level gates, and weren't part of this pass

## 2026-07-12 (2)

### Data Quality — Checkpoint Hours of Operation Populated + Hours-Based Chart Filtering
- Closed both `todo_list.txt` items "Data Quality — Checkpoint Hours of Operation" and
  "Overnight Wait Time Data — Validity Check" in a single coordinated pass, per the
  project's stated preference to treat checkpoint-hours as one fix across all airports
  rather than airport-by-airport
- `airport_checkpoint_hours` schema: added `open_time_clear`/`close_time_clear`
  (`ALTER TABLE`, run directly against the DB file with the `tsa_app_quack_server`
  scheduled task briefly stopped — Quack clients can't run DDL, confirmed live via
  `Alter not implemented yet` error)
- Populated `airport_checkpoint_hours` for all 14 active airports (66 new rows; PHL's
  7 rows already existed from its own onboarding) via a one-time checkpoint-name
  crosswalk mapping the `04_Assets/tsa_checkpoint_hours.html` research file's display
  names to the actual canonical `tsa_wait_times.checkpoint` strings (e.g. ATL's
  `Domestic — Main` → `DOMESTIC MAIN`, MIA's `Concourse D — Checkpoint 1` → `1`) — a
  one-time documentation exercise, not a pipeline step; new airports are expected to
  write canonical checkpoint names from the start, as PHL/DFW/LAX already do
- Added IAH (13th airport, previously missing entirely from the hours research) and
  researched hours for the three newly-live airports (DFW, PHL[already done], LAX) into
  the HTML asset and the DB table
- **DFW correction**: confirmed via a live fetch of the LocusLabs `dynamic-poi` endpoint
  that it has no hours/schedule fields at all (only live queue state + `isClosed` flags)
  — the HTML file's prior recommendation to "pull hours from the DFW API" was checked
  and isn't possible. DFW's 15 checkpoints are intentionally left NULL in
  `airport_checkpoint_hours`; its scraper already nulls `wait_time` in real time via
  `isClosed`/`isTemporarilyClosed`, so no static table is needed there
- Two pre-existing checkpoint-name data-hygiene bugs fixed so they don't silently break
  the new hours join: `DCA_wait_times.R` now drops rows with a blank checkpoint name
  (a rare divider-row artifact); `PDX_wait_times.R` now collapses the embedded `\n`
  that `html_text2()` was leaving in `.checkpoint-name` (from a `<br>` in the source
  markup) into a single space
- `xx_build_summary_DB.R`: added an hours-based filter before aggregation — each raw
  row's `wait_time`/`wait_time_pre_check`/`wait_time_clear` is nulled individually if
  local time-of-day falls outside that lane's `airport_checkpoint_hours` window
  (open/close reduced to time-of-day + an overnight-wrap flag, since the table's
  `TIMESTAMP_S` date part is just an entry-date anchor, not meaningful for comparison).
  **NULL open/close on a checkpoint/lane means "no known restriction" and is never
  filtered** — this is what makes DFW and MCO's missing-standard-hours rows behave
  correctly with no special-casing
- `app.R` `build_chart()`: bars for closed time slots are now `na.rm`-dropped (no bar,
  not a zero bar); when the entire selected ±1hr window is closed, the chart now shows
  "This checkpoint is not open during this time window" instead of the previous generic
  "no data" message — a `lane_exists_elsewhere` check (does this lane have data
  *anywhere* for this checkpoint, not just this window) keeps that message from being
  shown for checkpoints that simply have no PreCheck/CLEAR lane at all, which still get
  their prior "No TSA Pre✓/CLEAR lane" message. Verified live in-browser: ATL
  `DOMESTIC NORTH` (closed 9pm–4am) at 2:00 AM Sunday correctly renders the new message
- `PHL_wait_times.R`'s hardcoded 3:00pm–5:30pm clock gate for Terminal A-West 1 (added
  when the hours table didn't exist yet) replaced with a live lookup against
  `airport_checkpoint_hours` — verified the new logic reproduces the old hardcoded
  window exactly (open at 3:30pm/5:29pm, closed at 2pm/5:31pm/8pm) before deploying
- Ran the updated nightly build once live (ahead of its normal 2 AM schedule, with the
  user's confirmation) — 39,611 rows aggregated and pushed to S3 successfully

### Data Quality — Systematic Overnight Validity Audit
- Ran a 7-day audit joining every airport/checkpoint's raw scraped data against its new
  operating hours to check for non-null `wait_time` during known-closed windows —
  surfaced two genuinely distinct problems that had been bundled under one todo item:
  - **Real stale-cache bugs** (the exact same single number every time during closed
    hours, matching the pattern PHL's A-West 1 had before its own fix): DCA (all 3
    terminals, flat at 4 min), IAH Terminal A South (flat at 3), MIA checkpoints 4 and
    10 (flat at 0 and 3), MSP T2 Checkpoints 1 and 2 (flat at 5), PHL Terminal A-East
    and Terminal F (flat at 3) — these need scraper-level investigation, filed as a new
    todo item rather than fixed in this pass
  - **Hours data that's likely too conservative, not a scraper bug** — real, varying
    wait times (10–30+ minute swings, not a repeated number) during "closed" hours at
    JFK (all 5 terminals), EWR (all 3), LGA, MIA (checkpoints 2 and 7), DEN, ATL
    `INT'L MAIN`, IAH (C South and D), and LAX — mostly the airports the original
    research already flagged as medium-confidence/secondary-source estimates. This
    suggests those checkpoints are genuinely open later than researched, not that the
    scrapers are malfunctioning — filed as a separate todo item to re-verify hours
    rather than conflating it with the stale-cache bugs above
  - A hand-verified 3-checkpoint spot check earlier in this session (ATL `DOMESTIC
    NORTH`, DEN `East Security`, MIA checkpoint `9`) had already suggested the
    2026-07-12 UTC/local timezone fix (see below) resolved most of the "every airport
    shows overnight activity" symptom; this systematic audit confirms that theory for
    the majority of checkpoints while isolating the genuine remaining exceptions above

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