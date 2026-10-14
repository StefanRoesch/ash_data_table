# Performance of the demo's tables on Postgres

Spec section 12 and test layer 4: the prototype's measurements (issue 11),
repeated on the real demo. This file is written by `npm run measure` in
`demo/perf`; the section "Findings" comes from `NOTES.md` beside it, which is
written by hand for the run that is committed. The numbers of every
repetition are in `results.json`.

Everything here is **localhost**: browser, server and database on one
machine, no network, no TLS, no compression of the WebSocket.

## The run

- **Date:** 2026-10-06 14:45 UTC, at commit `c115179` plus the working tree of the run
- **Machine:** 12th Gen Intel(R) Core(TM) i7-1255U, 12 logical cores, 39 GB; Linux 7.0.0-38-generic x64
- **Load average** (1, 5, 15 min) when the run began: 2.09, 1.81, 2.96; when it ended: 1.7, 1.82, 2.83
- **Server:** Elixir 1.19.4, Erlang/OTP 28 (erts 16.2), 12 schedulers, `MIX_ENV=perf`
- **Packages:** phoenix_live_view 1.2.12, ash_data_table 0.1.0, ash_phoenix 2.3.25, ash_postgres 2.14.2, ash 3.34.4, phoenix 1.8.15, ecto_sql 3.14.0, postgrex 0.22.4, bandit 1.12.5
- **Database:** PostgreSQL 18.6 in Docker (the `postgres` service of `docker-compose.yml`), on the same machine
- **Browser:** Chromium 153.0.8010.12 (headless), Playwright, Node 24.13.1; viewport 1600 × 900
- **Repetitions:** 15 of each thing (5 of the jump to the last page), after one that is not counted. A cell shows the median, with the least and the greatest in brackets.

```sh
docker compose up -d postgres     # in the repository root
cd demo && mix deps.get
cd perf && npm ci
npm run setup                     # creates, migrates, seeds: demo_perf (large), demo_perf_standard
PERF_REPS=15 npm run measure   # starts the server itself, measures, writes this file
```

`npm run measure` started the server twice, with

```sh
MIX_ENV=perf PERF_DB=demo_perf PORT=4479 mix phx.server
MIX_ENV=perf PERF_DB=demo_perf_standard PORT=4479 mix phx.server
```

## How it was measured

- **The server** runs in the Mix environment `perf` (`config/perf.exs`):
  no code reloading, no debug annotations in the markup, no expensive runtime
  checks, protocols consolidated, logging at `warning`. It differs from
  `prod` in that it is started with `mix phx.server` and not as a release
  (code is loaded when first used, which is why each thing is done once
  before it is measured), serves plain HTTP on loopback, and its assets are
  neither minified nor digested.
- **The tables** are `/tasks` as the admin, who has all 14 columns: at 25
  rows a page, which is what the demo serves, and at 100, the read action's
  `max_page_size`. A table's page size is its read action's
  `default_limit` and the table has no control for it, so the second is a
  route of the perf environment only, `/perf/tasks100`: the same resource,
  compiled from the same source with `default_limit: 100`
  (`perf/server/task.ex`). `/specimens` (20 rows of 47 columns, 36
  records in either seed) is there for a wide row.
- **Round trips** are timed in the page with `performance.now()`: from the
  key or click to the moment a `MutationObserver` sees the DOM patched with
  the answer (`aria-busy` gone from the cell or the grid). Painting is not
  included. For a cell edit the clock starts at the Enter that saves.
- **"Interactive"** is the moment the table's hook has run, counted from
  the start of the navigation: the HTML has arrived, the LiveView has joined
  over the WebSocket and the grid has its tab stop. Assets come from the
  browser's cache.
- **Sizes** are those of the text frames the server sent, uncompressed, and
  of the HTML document, as it is and as it went over the wire (Bandit
  compresses HTTP answers).
- **Server times** come from telemetry events that LiveView, Ash and Ecto
  emit anyway, collected by `Demo.Perf.Probe` (perf environment only): the
  table's `save` callback, the Ash read that fetches the record again, the
  update action (which also loads the row's calculations and aggregates for
  the answer), and Ecto's time for each query, waiting for a connection
  included.
- **Memory** is `:erlang.process_info(pid, :memory)` of each table's
  LiveView process, read on the server by `Demo.Perf.Probe` over a route of
  the perf environment, with 1, 10 and 50 pages open in one browser. "As
  found" is before, "after a GC" after a forced garbage collection of that
  process. "Binaries referred to" are outside the process heap and may be
  shared.

## Results with the large seed: 50,000 tasks

### Initial load

| Table | Rows × columns | Interactive, ms | HTML answered, ms | HTML, KB | HTML on the wire, KB | Join frame, KB |
| --- | --- | --- | --- | --- | --- | --- |
| tasks, 25 rows | 25 × 14 | 132 (115–155) | 13 (11–26) | 85.8 | 9.74 | 83.1 |
| tasks, 100 rows | 100 × 14 | 202 (192–260) | 18 (14–23) | 260.4 | 19.7 | 260.4 |
| specimens, 20 rows | 20 × 47 | 177 (163–250) | 16 (13–22) | 216.9 | 20.5 | 209.0 |

### A cell edit saved

A text cell (`title`; `a_string` on `/specimens`), through the table's
`update` action.

| Table | Rows × columns | Round trip, ms | Frame back, KB | Server: `save` callback, ms | of it: re-fetch, ms | of it: update action, ms | of it: in the database, ms | Round trip less database, ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| tasks, 25 rows | 25 × 14 | 24 (17–38) | 2.55 | 19 (13–24) | 3.3 (2.5–5.0) | 13 (9.4–19) | 10.0 (5.3–14), 3 queries | 14 (11–25) |
| tasks, 100 rows | 100 × 14 | 23 (21–28) | 2.55 | 17 (12–18) | 3.3 (2.6–3.8) | 12 (8.4–13) | 8.2 (6.7–9.6), 3 queries | 15 (14–20) |
| specimens, 20 rows | 20 × 47 | 21 (15–27) | 8.48 | 9.0 (7.6–13) | 2.9 (2.3–5.9) | 4.7 (3.6–5.6) | 5.7 (4.7–9.9), 2 queries | 13 (10–19) |

### Sort, filter, page change

Each makes the table read again: a query for the rows, and a query for the
count where the action counts.

| Table | What | Round trip, ms | Frames back, KB | Largest frame, KB | Server: the read, ms | of it: rows query, ms | of it: count query, ms |
| --- | --- | --- | --- | --- | --- | --- | --- |
| tasks, 25 rows | Sort by `progress` (a number, no index) | 45 (19–65) | 64.2 in 3 | 59.6 | 30 (5.6–51) | 26 (1.4–46) | 4.5 (3.0–8.3) |
| tasks, 25 rows | Sort by `title` (text, no index) | 46 (23–54) | 63.9 in 3 | 59.4 | 32 (7.6–39) | 26 (1.6–34) | 4.6 (2.5–7.2) |
| tasks, 25 rows | Sort by `comment_count` (an aggregate) | 115 (22–204) | 63.8 in 3 | 59.2 | 99 (6.6–179) | 94 (2.2–172) | 4.3 (2.8–8.9) |
| tasks, 25 rows | Filter: `title` contains "invoice" | 31 (26–40) | 66.4 in 4 | 60.2 | 18 (13–21) | 2.7 (2.1–4.4) | 14 (10–18) |
| tasks, 25 rows | Next page | 27 (17–40) | 63.9 in 3 | 59.4 | 10 (5.7–20) | 4.0 (2.3–9.6) | 4.5 (3.5–12) |
| tasks, 25 rows | Last page (the deepest offset): page 1800 | 45 (38–50) | 64.0 in 3 | 59.7 | 29 (26–36) | 25 (22–30) | 4.2 (3.4–5.7) |
| tasks, 100 rows | Sort by `progress` (a number, no index) | 71 (44–97) | 241.6 in 3 | 237.1 | 34 (7.2–60) | 28 (2.2–55) | 4.4 (3.7–36) |
| tasks, 100 rows | Sort by `title` (text, no index) | 66 (45–77) | 241.6 in 3 | 237.1 | 31 (7.9–40) | 26 (2.2–34) | 4.0 (3.3–5.6) |
| tasks, 100 rows | Sort by `comment_count` (an aggregate) | 133 (40–184) | 241.6 in 3 | 237.1 | 98 (5.9–139) | 93 (1.6–133) | 3.7 (2.4–4.3) |
| tasks, 100 rows | Filter: `title` contains "invoice" | 52 (43–59) | 244.3 in 4 | 238.0 | 16 (13–19) | 4.4 (3.0–6.7) | 12 (9.9–16) |
| tasks, 100 rows | Next page | 46 (41–76) | 241.9 in 3 | 237.4 | 8.7 (6.9–15) | 3.5 (2.7–7.1) | 3.7 (3.2–7.0) |
| tasks, 100 rows | Last page (the deepest offset): page 450 | 69 (63–72) | 241.5 in 3 | 237.2 | 31 (27–37) | 24 (22–30) | 4.1 (3.7–4.9) |
| specimens, 20 rows | Sort by `an_integer` | 41 (35–61) | 171.1 in 3 | 165.1 | 8.0 (5.6–13) | 4.5 (3.6–6.9) | 1.9 (1.2–3.5) |

A click on a header moves its sort on, so the sorts above are a third each
of these:

| Table | What | To ascending, ms | To descending, ms | Back to no sort, ms |
| --- | --- | --- | --- | --- |
| tasks, 25 rows | Sort by `progress` (a number, no index) | 47 | 46 | 24 |
| tasks, 25 rows | Sort by `title` (text, no index) | 46 | 50 | 26 |
| tasks, 25 rows | Sort by `comment_count` (an aggregate) | 124 | 129 | 29 |
| tasks, 100 rows | Sort by `progress` (a number, no index) | 75 | 76 | 49 |
| tasks, 100 rows | Sort by `title` (text, no index) | 69 | 74 | 46 |
| tasks, 100 rows | Sort by `comment_count` (an aggregate) | 136 | 134 | 51 |
| specimens, 20 rows | Sort by `an_integer` | 42 | 38 | 41 |

### Arrow keys

Real key presses, to count what goes to the server; then the time of the
hook's handler per key, taken over 2,000 keys dispatched in the page.

| Table | Keys pressed | Frames sent | The hook's work per key, ms |
| --- | --- | --- | --- |
| tasks, 25 rows | 80 | 0 | 0.040 |
| tasks, 100 rows | 80 | 0 | 0.045 |
| specimens, 20 rows | 80 | 0 | 0.047 |

### Memory of the LiveView process of an open table

| Table | Open pages | Per process, after a GC, KiB | Per process, as found, KiB | Binaries referred to, per process, KiB | All of them, after a GC, MiB |
| --- | --- | --- | --- | --- | --- |
| tasks, 25 rows | 1 | 86.8 (86.8–86.8) | 417.1 (417.1–417.1) | 0.1 (0.1–0.1) | 0.08 |
| tasks, 25 rows | 10 | 86.8 (86.8–86.8) | 417.1 (417.1–417.1) | 0.1 (0.1–0.1) | 0.85 |
| tasks, 25 rows | 50 | 86.8 (86.8–86.8) | 417.1 (417.1–417.1) | 0.1 (0.1–0.1) | 4.24 |
| tasks, 100 rows | 1 | 86.8 (86.8–86.8) | 1762.0 (1762.0–1762.0) | 0.1 (0.1–0.1) | 0.08 |
| tasks, 100 rows | 10 | 86.8 (86.8–86.8) | 1762.0 (1761.6–1762.0) | 0.1 (0.1–0.1) | 0.85 |
| tasks, 100 rows | 50 | 86.8 (86.8–86.8) | 1762.0 (1761.6–1762.0) | 0.1 (0.1–0.1) | 4.24 |

## What the data volume costs: 400 tasks against 50,000

The same things on the standard seed (400 tasks, of which the admin
sees 320), medians of round trips.

| Table | What | 400 tasks, ms | 50,000 tasks, ms | Factor |
| --- | --- | --- | --- | --- |
| tasks, 25 rows | Cell edit | 23 | 24 | 1.1 × |
| tasks, 25 rows | Sort by `progress` (a number, no index) | 25 | 45 | 1.8 × |
| tasks, 25 rows | Sort by `title` (text, no index) | 25 | 46 | 1.9 × |
| tasks, 25 rows | Sort by `comment_count` (an aggregate) | 25 | 115 | 4.5 × |
| tasks, 25 rows | Filter | 22 | 31 | 1.4 × |
| tasks, 25 rows | Next page | 23 | 27 | 1.2 × |
| tasks, 25 rows | Last page (the deepest offset) | 23 | 45 | 1.9 × |
| tasks, 25 rows | Initial load, to interactive | 135 | 132 | 1.0 × |
| tasks, 100 rows | Cell edit | 24 | 23 | 1.0 × |
| tasks, 100 rows | Sort by `progress` (a number, no index) | 54 | 71 | 1.3 × |
| tasks, 100 rows | Sort by `title` (text, no index) | 53 | 66 | 1.3 × |
| tasks, 100 rows | Sort by `comment_count` (an aggregate) | 53 | 133 | 2.5 × |
| tasks, 100 rows | Filter | 34 | 52 | 1.5 × |
| tasks, 100 rows | Next page | 50 | 46 | 0.9 × |
| tasks, 100 rows | Last page (the deepest offset) | 24 | 69 | 2.9 × |
| tasks, 100 rows | Initial load, to interactive | 203 | 202 | 1.0 × |

<details>
<summary>The standard seed in full</summary>

| Table | Rows × columns | Interactive, ms | HTML answered, ms | HTML, KB | HTML on the wire, KB | Join frame, KB |
| --- | --- | --- | --- | --- | --- | --- |
| tasks, 25 rows | 25 × 14 | 135 (124–186) | 13 (10–24) | 85.8 | 9.77 | 83.1 |
| tasks, 100 rows | 100 × 14 | 203 (191–288) | 18 (14–20) | 261.2 | 20.2 | 261.2 |
| specimens, 20 rows | 20 × 47 | 179 (168–201) | 15 (13–22) | 216.9 | 20.6 | 209.0 |

| Table | Rows × columns | Round trip, ms | Frame back, KB | Server: `save` callback, ms | of it: re-fetch, ms | of it: update action, ms | of it: in the database, ms | Round trip less database, ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| tasks, 25 rows | 25 × 14 | 23 (17–34) | 2.64 | 17 (12–26) | 3.1 (2.2–5.2) | 12 (8.7–19) | 9.1 (5.4–17), 3 queries | 14 (11–19) |
| tasks, 100 rows | 100 × 14 | 24 (21–30) | 2.64 | 16 (13–21) | 3.3 (2.7–3.8) | 13 (9.1–16) | 8.8 (6.1–11), 3 queries | 15 (12–20) |
| specimens, 20 rows | 20 × 47 | 20 (16–31) | 8.38 | 8.9 (7.2–14) | 2.8 (2.3–4.7) | 4.7 (3.6–8.1) | 5.8 (4.7–9.1), 2 queries | 14 (11–22) |

| Table | What | Round trip, ms | Frames back, KB | Largest frame, KB | Server: the read, ms | of it: rows query, ms | of it: count query, ms |
| --- | --- | --- | --- | --- | --- | --- | --- |
| tasks, 25 rows | Sort by `progress` (a number, no index) | 25 (21–31) | 64.3 in 3 | 59.8 | 8.0 (5.7–11) | 4.1 (2.7–6.0) | 2.0 (1.7–2.9) |
| tasks, 25 rows | Sort by `title` (text, no index) | 25 (19–40) | 64.3 in 3 | 59.8 | 7.8 (5.5–13) | 2.8 (1.5–7.2) | 1.4 (1.1–2.9) |
| tasks, 25 rows | Sort by `comment_count` (an aggregate) | 25 (18–46) | 64.2 in 3 | 59.6 | 7.9 (5.2–23) | 3.6 (1.6–11) | 2.2 (1.1–3.8) |
| tasks, 25 rows | Filter: `title` contains "invoice" | 22 (19–28) | 66.3 in 4 | 60.0 | 7.4 (5.9–13) | 2.8 (2.3–6.0) | 2.1 (1.5–4.4) |
| tasks, 25 rows | Next page | 23 (20–43) | 63.9 in 3 | 59.5 | 6.5 (5.0–13) | 2.8 (1.2–4.7) | 1.5 (1.0–2.2) |
| tasks, 25 rows | Last page (the deepest offset): page 13 | 23 (21–28) | 51.7 in 3 | 47.5 | 7.6 (5.3–9.2) | 2.8 (1.9–3.4) | 1.5 (1.1–1.6) |
| tasks, 100 rows | Sort by `progress` (a number, no index) | 54 (48–69) | 242.4 in 3 | 237.9 | 9.4 (8.0–12) | 3.6 (2.2–6.7) | 1.4 (1.2–4.0) |
| tasks, 100 rows | Sort by `title` (text, no index) | 53 (45–66) | 241.8 in 3 | 237.2 | 8.8 (6.8–13) | 3.7 (1.7–5.5) | 1.5 (1.0–2.2) |
| tasks, 100 rows | Sort by `comment_count` (an aggregate) | 53 (47–62) | 242.4 in 3 | 237.8 | 9.6 (6.6–13) | 3.9 (2.4–5.4) | 1.6 (1.3–2.4) |
| tasks, 100 rows | Filter: `title` contains "invoice" | 34 (22–61) | 66.3 in 4 | 60.0 | 6.8 (5.1–11) | 2.3 (1.8–5.7) | 2.0 (1.2–7.2) |
| tasks, 100 rows | Next page | 50 (20–59) | 241.4 in 3 | 237.4 | 8.0 (5.0–10) | 2.7 (1.8–4.6) | 1.3 (1.0–2.4) |
| tasks, 100 rows | Last page (the deepest offset): page 4 | 24 (18–25) | 51.5 in 3 | 47.5 | 5.7 (4.9–5.8) | 2.2 (2.1–2.8) | 1.3 (1.2–1.5) |
| specimens, 20 rows | Sort by `an_integer` | 42 (37–55) | 171.0 in 3 | 165.1 | 7.7 (7.0–13) | 5.2 (3.6–8.0) | 1.9 (1.2–4.1) |

</details>

## Against the prototype

The prototype (issue 11) measured its own page on an in-memory ETS data
layer with resources without policies, in dev, on localhost. The numbers
it gave for the variant that was chosen, streams:

| | Prototype, streams |
| --- | --- |
| Cell edit round trip, 25 × 10 | 21 ms |
| Cell edit round trip, 100 × 30 | 34 ms |
| Diff for one saved cell, 10 / 30 columns | 1.9 / 3.4 KB |
| Page change round trip, 100 × 30 | 78 ms |
| Process memory, 100 × 10 | 0.03 MB |
| Process memory, 500 × 30 | 0.14 MB |
| Arrow keys | no frames sent, under 0.5 ms |

**Comparable:** the method (round trip in the page from the key to the
patched DOM, frame sizes off the socket, process memory from the VM), the
rendering strategy (rows in a stream, one hook), localhost, headless
Chromium. The frame size of a saved cell, the arrow keys and the memory of
the process compare directly, allowing for the number of columns.

**Not comparable:**

- The data layer. The prototype's round trips had no database in them; the
  demo's have Postgres in Docker, with policies, field policies, a tenant, a
  calculation and an aggregate in every read. The column "round trip less
  database" takes Ecto's query time out, which is the nearest thing to the
  spec's "excluding database and network time"; what Ash does around the
  queries stays in.
- The size of the table. The demo has no table of 30 columns with 100 rows:
  `/tasks` has 14 columns, `/specimens` 47 with 20 rows. The prototype's
  100 × 30 lies between the two.
- The machine and the versions, which were not recorded for the prototype in
  a way that could be repeated.

## Findings

Written for the run of 2026-10-06. One run, on a laptop that was not idle
(another build was working in the same session; see the load average), so a
difference of a few milliseconds between two cells means nothing.

**Against the spec's section 12**

- **Arrow keys send nothing to the server:** confirmed, 0 frames for 80 keys
  on each table. The hook needs about 0.04 ms per key (prototype: under
  0.5 ms).
- **A cell edit in the order of the prototype's 34 ms, database and network
  excluded:** met. With 50,000 tasks an edit takes 23 to 24 ms from the Enter
  to the patched cell, the database included, at 25 rows and at 100; about
  15 ms without the database's part. The page size makes no difference to an
  edit, as only the row comes back. The prototype's 34 ms was at 100 rows of
  30 columns without a database; the demo's nearest is 100 rows of 14
  columns.
- **A saved cell sends its row back:** 2.55 KB for a row of 14 columns and
  8.5 KB for one of 47 (prototype: 1.9 KB at 10 columns, 3.4 KB at 30). Per
  column that is as the prototype, or a little less.
- **Server memory per open table stays flat with page size:** yes, once the
  process has collected its garbage: 86.8 KiB at 25 rows and at 100, the
  same for each of 50 open pages, so 50 open tables hold 4.2 MiB between
  them. That is below the prototype's 0.14 MB at 500 × 30. **But see the
  first finding below** for the time before that collection.

**Findings**

1. **Until its first garbage collection, a table's process holds what the
   first render left behind, and that grows with the page:** 417 KiB at 25
   rows, 1,762 KiB at 100 ("as found" in the memory table), against 87 KiB
   afterwards. The records are not kept (they are in the stream), but the
   heap they were rendered on is not given back at once. LiveView hibernates
   a process after 15 seconds without a message, which collects it; a page
   that is used keeps collecting anyway. So the flat figure holds for tables
   that are open and quiet, and a burst of 50 people opening the 100-row
   table at once holds about 86 MB for a quarter of a minute, not 4 MB. The
   prototype reported one figure and did not say when it was taken. Not
   tuned here; a `hibernate_after` shorter than 15 s, or a
   `:erlang.garbage_collect/0` after the first render, would be the place.
2. **Sorting by the aggregate `comment_count` is the slowest thing a person
   can do: about 125 ms at 50,000 tasks against 25 ms at 400.** The rows
   query takes 90 to 170 ms: Postgres has to count the comments of all
   45,000 tasks of the organisation before it can order by the count and
   take 25. No index can help a sort by an aggregate; this is what an
   aggregate column costs on a large table, and it grows with the table.
3. **Sorting by a column without an index** (`progress`, `title`) costs about 28 ms
   in the database at 45,000 rows of one tenant, against 2 ms unsorted:
   a sequential scan and a top-N sort. Round trip 45 ms against 25 ms.
   Acceptable here, and linear in the table. The demo indexes only
   `inserted_at` and `due_on`.
4. **The count is cheap here, 4 ms for 45,000 rows, but it is paid on every
   read** of a countable action: every sort, filter and page change runs
   it again. With a filter it is the larger of the two queries:
   `title` contains "invoice" takes 3 ms for the rows and 12 to 14 ms for the
   count, because the count has to test every row with `LIKE`.
5. **A deep offset costs what it skips:** the last page (offset 44,975)
   takes 25 ms in the database against 4 ms for the second page. This is
   offset pagination, not the table; the keyset tables do not have it.
6. **Time to an interactive grid is browser time, not server time.** The
   HTML is answered in 13 to 18 ms; the grid is interactive after 132 ms at
   25 rows and 202 ms at 100. In between the browser parses the page, runs
   the scripts, joins over the WebSocket and gets the page a second time:
   the join frame is as large as the HTML (83 KB at 25 rows, 260 KB at 100),
   as LiveView renders the page once for the request and once for the
   socket. The data volume makes no difference to the load (132 against
   135 ms).
7. **A read sends the page again:** 59 KB at 25 rows, 237 KB at 100, for
   every sort, filter and page change (about 2.4 KB a row, as for an edit).
   Uncompressed and on localhost that is not felt; over a slow line the
   100-row page would be. The endpoint could compress the socket.
8. **The page size costs the browser more than the server.** At 100 rows a
   read that takes the server 9 ms (next page) takes 46 ms to the patched
   DOM, against 27 ms at 25 rows.

**What the volume costs** (the table above): nothing for an edit and for
the load; a factor of 1.2 to 2 for sorts by a plain column, filters and page
changes; 2.5 to 4.5 for the sort by the aggregate. In the standard seed the
last page of the 100-row table holds 20 rows, so its line compares a short
page with a full one.

**Not measured**

- Anything over a network, with TLS, or with compression.
- A release, and a server under load from many people at once: every number
  is one person on an otherwise quiet server.
- Firefox and Safari; time to paint.
- 500 rows a page and nested tables, which the prototype measured: the read
  action allows 100 at most, and nested tables are a later slice.
- A table of 30 columns with 100 rows.
