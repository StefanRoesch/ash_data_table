# Baseline before the refactor

What five things a person does on `/tasks` cost before stage 0, so that stage 5 (and every stage before it) can be measured the same way and compared. The markup is guarded separately by the markup snapshots (`demo/test/demo_web/markup_snapshot_test.exs`, `demo/test/snapshots/`).

## How it was measured

- **Commit:** `d1489d6` (the library as of the test preparation; the measured paths are the same as at `a606c42`: no library change since touches them).
- **Date:** 2026-10-14 09:26 UTC.
- **Machine:** 12th Gen Intel Core i7-1255U, 12 logical cores, 39 GB; Linux 7.0.0-38. Load average 5.8, 4.4, 5.1 when the run began: the machine was **not idle** (other sessions were working), so read differences of a few milliseconds as noise.
- **Server:** `MIX_ENV=perf PERF_DB=demo_perf_standard PORT=4490 mix phx.server`, started by the script. Elixir 1.19.4, OTP 28, Postgres 18.6 (docker), phoenix_live_view 1.2.12, ash 3.34.4, ash_postgres 2.14.2, ash_phoenix 2.3.25, bandit 1.12.5.
- **Data:** the standard seed (400 tasks, 480 comments, 14 users), seeded again before the run; as the admin, 25 rows of 14 columns.
- **Browser:** Chromium (headless), Playwright 1.63; localhost.
- **Repetitions:** 15 of each, after one that is not counted; median, with the least and the greatest.

```sh
cd demo/perf && ./setup.sh               # or only the standard database: see setup.sh
PERF_PORT=4490 node baseline.mjs         # writes baseline-results.json
```

The script is `demo/perf/baseline.mjs`; the raw numbers are `demo/perf/baseline-results.json`.

- **Browser time:** in the page, from the click or key (dispatched in the page, so Playwright's own waiting is not counted) to the DOM change that shows the answer, seen by a `MutationObserver`. Painting is not included.
- **Bytes:** the WebSocket text frames the server sent for it, uncompressed, summed.
- **Server:** what the probe (`demo/perf/server/probe.ex`) recorded from telemetry: the callbacks of the LiveView and the table (`handle_event`, a component's `update`), Ash's reads (the async read of a page runs beside the callbacks) and the database's statements.

## The numbers

| Action | Browser, median (min–max) | Bytes sent (median) | Frames | Callbacks | Ash reads | Statements | Database |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Cell save (Enter in the title's editor → cell patched) | 36.5 ms (32.4–55.3) | 7,218 | 2 | 23.8 ms (`handle_event:save`) | 4, 11.8 ms | 7 | 15.9 ms |
| Page change (Next / Previous → rows of the page) | 82.6 ms (71.9–120.3) | 152,695 | 4 | 5.1 ms (`handle_event:page`, `update`) | 4, 19.2 ms | 7 | 14.5 ms |
| Expanding a row (expander → its lines) | 10.4 ms (9.1–23.8) | 3,258 | 1 | 0.0 ms (`handle_event:expand`) | 0 | 0 | 0 |
| Opening a nested table (Comments line → its rows) | 36.5 ms (26.2–48.2) | 29,693 (26,461–40,480) | 2 | 4.8 ms (`handle_event:toggle`, `update`) | 2, 10.6 ms | 2 | 3.9 ms |
| Opening the picker (Enter on Assignee → its rows) | 42.7 ms (38.1–84.2) | 27,078 | 1 | 11.4 ms (`handle_event:pick`, `update`) | 2, 5.8 ms | 4 | 7.9 ms |

The bytes of a nested table vary with the comments of the row it is opened under (0 to 5).

## What to compare at stage 5

- The bytes are the sharpest number: they do not depend on the machine's load. Stage 5 should send about the same for each action; a nested table or a picker that goes through `<.portal>` may add the portal's wrapper, not more.
- The callbacks change their names in stages 4 and 5 (no `live_component.*` any more); compare their sum.
- Statements and Ash reads per action should not grow.
- Times: run the script again on the same machine, idle if possible, and compare medians; differences under about 20 % are within this run's noise.

## Also fixed for this run

The perf environment had fallen behind the library: `Demo.Perf.Task` (made from the source of `Demo.Tracker.Task` with pages of 100) opened with a page size its `page_sizes` did not offer, which the table refuses since that rule was added, and every nested table's link to the full view raised on it; and its domain named no `pub_sub`. `demo/perf/server/task.ex` now offers 100 and names `Demo.PubSub`.
