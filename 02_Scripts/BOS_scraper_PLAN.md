# BOS Scraper — Research & Plan (drafted overnight, 2026-07-19)

## Verdict: JSON/API, not chromote

BOS's wait-time widget on massport.com is powered by a third-party vendor
("Zensors") loaded via an `<iframe>`. The iframe hits a clean tRPC JSON API
directly — same shape of win as the SEA/DCA/IAH/PDX/MCO/MIA JSON migrations.
**No headless browser needed.**

This also resolves the existing `todo_list.txt` note ("needs test run to
confirm Zensors API Origin allowlist check passes from R; fallback is
chromote if 403 persists") — tested tonight with a bare `curl`, **no
Origin/Referer header at all**, and the API still returned `200` with valid
data. There is no server-side origin allowlist enforced. httr2 can hit this
directly with no browser mimicry required.

## The API

```
GET https://embed.zensors.live/api/embeddable-widget/trpc/waitTimeExplorer.update?batch=1&input=<urlencoded JSON>
```

`input` JSON shape:
```json
{"0":{"journey":"<checkpoint-specific-id>","slug":"tSTQVPRW1","domainSlug":"BOS","token":"9uBjlxUu2dTQydGHYGtoDYxH5TE0vHOl"}}
```

- `slug` and `token` are constant across all 7 checkpoints and are hardcoded
  in massport.com's page HTML (`<iframe src="https://embed.zensors.live/BOS/tSTQVPRW1/waitTimeExplorer?token=...">`).
  Confirmed stable across two separate fresh page loads tonight — this reads
  as a static API key issued to Massport for the embed, not a rotating
  session token. Standard "verify it's still working" risk applies same as
  any other airport's hardcoded endpoint, nothing more.
- `journey` is the one thing that varies **per checkpoint** — see mapping below.
- One request per checkpoint (7 total per scrape cycle), same as any
  multi-checkpoint airport.

### Response shape
```json
{
  "result": {
    "data": {
      "paths": {
        "precheck": {"name": "TSA PreCheck®", "verified": true, "open": false, "waitTime": {"timestamp": 1784513160000, "value": 0}},
        "standard": {"name": "Standard", "verified": true, "open": false, "waitTime": {"timestamp": 1784513160000, "value": 1.5}}
      }
    }
  }
}
```
- Wrapped in a top-level array (`[{...}]`) — standard tRPC batch response, unwrap index 0.
- `paths.standard` and `paths.precheck` are each **optional keys** — Checkpoint 2
  (PreCheck-only) omits `standard` entirely rather than returning it null/closed.
  Parse defensively (check key existence), don't assume both are always present.
- `waitTime.value` is in **minutes, fractional** (observed 0, 0.75, 1.5) — round()
  same as every other scraper.
- `waitTime.timestamp` is epoch **milliseconds**.
- `open` is a live boolean — same role as SEA/PDX/MIA's `IsOpen`/`isOpen` flags,
  usable directly for hours-gating instead of (or in addition to)
  `airport_checkpoint_hours` static rows.
- **No CLEAR data** — confirmed by both the API response (no `clear` key anywhere)
  and the page's own copy: "CLEAR is available in Terminals A, B and E. Wait
  times for CLEAR are currently unavailable." Don't build a `wait_time_clear`
  column expectation for BOS.

### Checkpoint → journey ID mapping (authoritative — from `waitTimeExplorer.init`)

Superseded the earlier dropdown-only mapping once `waitTimeExplorer.init` was
found (2026-07-20) — this is a real, unauthenticated endpoint
(`GET .../trpc/waitTimeExplorer.init?batch=1&input=...`, same `slug`/`domainSlug`/`token`,
no `journey` needed) that returns the full `journeys` map server-side,
confirmed live via bare `curl`. It also corrected one assumption: **Checkpoint
6 has no PreCheck lane at all** (`availablePaths: ["standard"]` only) —
earlier UI screenshots were misleading because the widget still renders a
PreCheck card even when that lane doesn't exist for the checkpoint.

| # | journey ID | Zensors `name` | Stored `checkpoint` value | availablePaths |
|---|---|---|---|---|
| 1 | `t6CQ1P0Y3` | Checkpoint 1: A Gates | `A Gates` | precheck, standard |
| 2 | `tKK3PDVP9` | Checkpoint 2: A Gates PreCheck Only | `A Gates PreCheck Only` | precheck |
| 3 | `tXT4B8KMX` | Checkpoint 3: Gates B1 - B22 | `Gates B1 - B22` | precheck, standard |
| 4 | `tF1JP9828` | Checkpoint 4: Gates B23 - 40 | `Gates B23 - 40` | precheck, standard |
| 5 | `tSGV88H0D` | Checkpoint 5: Terminal C | `Terminal C` | precheck, standard |
| 6 | `tWEBCSW2Q` | Checkpoint 6: All E Gates | `Checkpoint 6: All E Gates` | **standard only** |
| 7 | `tCLRGFHM9` | Checkpoint 7: All E Gates | `Checkpoint 7: All E Gates` | precheck, standard |

**Naming decision (finalized):** Checkpoints 6 and 7 are the only pair that
collide (both genuinely "All E Gates" with zero other distinguishing text
anywhere on massport's site or in Zensors' own data) — same category of
problem as the EWR Terminal B 3-checkpoint collapse bug. Only those two keep
the `"Checkpoint N: "` prefix in the stored `checkpoint` string; the other 5
already have unique descriptive names and get the prefix stripped, matching
how every other airport in the DB is stored (no airport prefixes every
checkpoint with its dropdown number — see PHL's `"Terminal A-West 1"` /
`"Terminal A-West 2"` for the same "only disambiguate where it collides"
pattern).

There is no independently fetchable "list all checkpoints" endpoint beyond
`waitTimeExplorer.init` itself — confirmed via full network trace (hard
reload, cache disabled) and full-text search across all 15 of Zensors' JS
bundles for these literal strings, finding nothing. `waitTimeExplorer.init`
*is* that endpoint; no further reverse-engineering needed.

## Proposed script shape (following SEA/PHL boilerplate convention)

- httr2 GET loop over the 7 `journey` IDs (named vector/list, checkpoint label → journey)
- Parse `paths.standard`/`paths.precheck` defensively per checkpoint (key may be absent)
- `wait_time` from `standard.waitTime.value`, `wait_time_pre_check` from `precheck.waitTime.value`, `wait_time_clear` = NA always
- timezone: `America/New_York`
- Standard `BOS_data` tibble → `dbAppendTable` → cleanup block, matching SEA/DFW/PHL pattern
- Dry-run per [[feedback_dry_run_before_live_writes]]: comment out `dbAppendTable`, print table for spot-check first
- Orchestrator auto-discovers `BOS_wait_times.R` — no manual wiring needed

## Open decisions for the morning
1. Naming convention for checkpoints 6 & 7 (see above).
2. Whether to still populate `airport_checkpoint_hours` rows for BOS (project
   convention from PHL onward) even though the live `open` flag already
   gates hours — recommend yes for UI/chart consistency with other airports,
   but it's not load-bearing for correctness here since `open` is live per-poll.
3. No code has been written yet — this is research/planning only, per your ask.
