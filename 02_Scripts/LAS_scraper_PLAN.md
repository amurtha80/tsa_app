# LAS Scraper — Research & Plan (2026-07-22)

## Verdict: JSON/API, not chromote

LAS's wait-time widget on harryreidairport.com is powered by the same
third-party vendor as BOS ("Zensors"), loaded via an `<iframe>`. Confirmed via
a `chromote` network sniff of the live page (no dropdown interaction
required to see the request fire — the `waitTimeExplorer.init` call happens
on initial page load, not only after a dropdown selection as the todo item
speculated).

## The API

Same shape as BOS — see `02_Scripts/BOS_scraper_PLAN.md` for the full tRPC
request/response format.

```
GET https://embed.zensors.live/api/embeddable-widget/trpc/waitTimeExplorer.update?batch=1&input=<urlencoded JSON>
```

- `slug = "t1LQGTAPA"`, `domainSlug = "LAS"`, `token = "3Ll9yq2riLZctX1CZ94FRgLcScJimgXx"`
  — found directly in the iframe embed URL via network sniff, confirmed
  stable across the `.init` and `.update` calls tested this session.
- No server-side Origin allowlist — bare `httr2` requests work with no
  browser mimicry, same as BOS.

### Checkpoint → journey ID mapping (from `waitTimeExplorer.init`)

| journey ID | Zensors `name` | availablePaths |
|---|---|---|
| `t2K25H6KA` | T1 - A/B Gates (default journey) | precheck, standard |
| `tN8G8AV9D` | T1 - C Gates | precheck, standard |
| `tGMD2ET8Y` | T1 - C/D Gates | precheck, standard |
| `t0CSXP4SK` | T3 - D/E Gates | precheck, standard |

- No naming collisions — all 4 names are already unique, unlike BOS's two
  "All E Gates" checkpoints. No `"Checkpoint N: "` prefix needed anywhere.
- No CLEAR data — no `clear` key in any response, and the airport's own page
  says nothing about CLEAR either. `wait_time_clear` is always `NA`.
- All 4 checkpoints have both `standard` and `precheck` paths (unlike BOS's
  PreCheck-only/Standard-only edge cases) — parsing still stays defensive via
  the same `lane_wait()` helper pattern in case that ever changes.
- Timezone: `America/Los_Angeles`.

## Checkpoint hours

No source (harryreidairport.com, CLEAR, TSA schedule tool, general web
search) gives concrete per-checkpoint open/close times — same situation as
BOS. A temporary `tsa_app_las_hours_monitor` Task Scheduler job (every 15min,
offset :05/:20/:35/:50 to avoid clustering with BOS's :03/:18/:33/:48) polls
Zensors' live `open` flag into a temporary `las_hours_monitor` DuckDB table.
See `todo_list.txt` for the teardown plan once real hours are derived
(target ~2026-08-19).

## Status
Live in production 2026-07-22 as `02_Scripts/LAS_wait_times.R`, picked up
automatically by `scrape_data_automate.R`'s glob. Confirmed via a manual
single-cycle write test (4 rows landed in `tsa_wait_times`, sane per-checkpoint
values, correct `America/Los_Angeles` timezone tag).
