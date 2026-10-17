# Nested tables on Postgres: one run

A short measurement of nested tables, beside `RESULTS.md` (which
`npm run measure` writes, and which this run did not touch). Written by hand
from `nested-results.json`, the output of `node nested.mjs`.

- **Date:** 2026-10-17 19:09 UTC, on `main` after the docs pass of the architecture refactor
- **Machine:** 12th Gen Intel Core i7-1255U, 12 logical cores; load average 1.8, 1.4, 1.5 when the run began, so read the times as orders of magnitude
- **Server:** `MIX_ENV=perf PERF_DB=demo_perf_standard`, started by the script on port 4490; ash 3.36.1, ash_postgres 2.14.5, phoenix_live_view 1.2.12, Elixir 1.19.4, OTP 28
- **Data:** the standard seed (400 tasks), as the admin
- **Browser:** Chromium (headless), Playwright; localhost, no network
- **Repetitions:** 15 of each line, after one that is not counted; median, with the least and the greatest in brackets

```sh
cd demo/perf && npm run setup      # once: demo_perf_standard
PERF_PORT=4490 node nested.mjs
```

## Opening one nested table

From the click on a line to the patch that brings the nested table's rows,
measured in the page; the statements and the database time are what the
server recorded for it (`[:demo, :repo, :query]`).

| Line | Rows | Statements | Database | Click to rows |
| --- | --- | --- | --- | --- |
| `/tasks` → Comments (has-many, keyset, counted) | 0 to 5 | 2 | 4.0 ms | 38.0 ms (27.6 to 58.0) |
| `/tasks` → Labels (many-to-many, not paginated) | 0 to 3 | 2 | 4.1 ms | 37.7 ms (27.7 to 57.9) |
| `/tasks` → Project (belongs-to) | 1 | 2 | 3.6 ms | 37.7 ms (27.8 to 42.4) |
| `/tasks` → Newest comment (has-one of many) | 0 or 1 | 2 | 3.5 ms | 38.1 ms (25.1 to 54.0) |
| `/projects` → Tasks (has-many, offset page of 25, counted; a calculation, an aggregate and three reference cells among the columns) | 25 | 9 | 24.5 ms | 92.6 ms (73.3 to 123.2) |

A nested table is read in two statements: the row it belongs to, read again
as the person, with the count, and the page. The page of tasks under a
project takes nine, with what its calculation, aggregate and three
reference columns read.

Opening a line sends one event. Expanding a row sends one event and reads
nothing.

## What the server holds with many open

One page of `/tasks` (25 rows), with the comments of its rows opened one
after the other and then the project of each: `:erlang.process_info(pid,
:memory)` of the page's LiveView process after a garbage collection, and as
it was found before it.

| Nested tables open | After a collection | As found |
| --- | --- | --- |
| 0 | 364.0 KiB | 1,765.8 KiB |
| 1 | 588.2 KiB | 1,104.0 KiB |
| 10 | 1,538.3 KiB | 1,781.5 KiB |
| 50 | 4,025.2 KiB | 9,385.4 KiB |

Every nested table is an entry of the one table value in the page's
LiveView process, with its state, its table model and the keys of its page;
the rows are in its stream, in the browser. From 10 to 50 open, each one
more holds about 62 KiB after a collection.

Opening one more gets slower as they add up: the first five lines took 37 to
80 ms each from click to rows, and the last five of the fifty 177 to 214 ms
(`open_ms_by_number_open` in the results of a run). Rendering, scrolling and
layout with fifty grids in one page were not measured.
