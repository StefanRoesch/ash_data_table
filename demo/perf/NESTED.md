# Nested tables on Postgres: one run

A short measurement of the nested tables slice, beside `RESULTS.md` (which
`npm run measure` writes, and which this run did not touch). Written by hand
from `nested-results.json`, the output of `node nested.mjs`.

- **Date:** 2026-10-07 09:46 UTC, on the working tree of the nested tables slice
- **Machine:** 12th Gen Intel Core i7-1255U, 12 logical cores; load average 3.9, 4.8, 7.9 when the run began: the machine was **not idle** (a browser suite had just run), so read the times as orders of magnitude
- **Server:** `MIX_ENV=perf PERF_DB=demo_perf_standard PORT=4478 mix phx.server`; ash 3.34.4, ash_postgres 2.14.2, phoenix_live_view 1.2.12
- **Data:** the standard seed (400 tasks, 480 comments), as the admin
- **Browser:** Chromium (headless), Playwright; localhost, no network
- **Repetitions:** 15 of each line, after one that is not counted; median, with the least and the greatest in brackets

```sh
cd demo/perf && npm run setup      # once: demo_perf_standard
PERF_PORT=4478 node nested.mjs
```

> **Since this run** the library reads in more steps, and the tasks have
> three reference columns. The times below are of this run and were not
> taken again; the statements are no longer all as counted here. Counted
> again on the test database (60 tasks, the admin): a page of `/tasks` is 6
> statements (the page, its count, the aggregate column, and one per
> reference column), where one statement for the page with its aggregate
> came to 5, at a median of 10.0 ms against 8.6 ms for the call alone. A
> page of 25 tasks under a project is 6 statements as well. The four nested
> tables of comments, labels and a project are 2 statements each, as below;
> the people under a task, whose table now has an aggregate column, are 3.

## Opening one nested table

From the click on a line to the patch that brings the nested table's rows,
measured in the page; the statements and the database time are what the
server recorded for it (`[:demo, :repo, :query]`).

| Line | Rows | Statements | Database | Click to rows |
| --- | --- | --- | --- | --- |
| `/tasks` → Comments (has-many, keyset, counted) | 0 to 5 | 2 | 4.0 ms | 16.6 ms (11.8 to 24.5) |
| `/tasks` → Labels (many-to-many, not paginated) | 0 to 3 | 2 | 3.9 ms | 15.9 ms (10.6 to 23.2) |
| `/tasks` → Project (belongs-to) | 1 | 2 | 2.9 ms | 13.9 ms (8.9 to 23.2) |
| `/tasks` → Newest comment (has-one of many) | 0 or 1 | 2 | 3.1 ms | 13.3 ms (8.3 to 17.3) |
| `/projects` → Tasks (has-many, offset page of 25, counted; a calculation and an aggregate among the columns) | 25 | 3 | 13.0 ms | 37.9 ms (25.9 to 47.5) |

Beside the spike (`docs/research/nested-tables-spike.md`, section 8, the
call alone without a browser): 2 statements and 3.9 ms for the comments of a
task, 3.0 ms for its labels, 2.5 ms for its project, 6.2 ms for a page of 25
tasks of a project. The statements and the database times agree, with one
difference: **a page of a table with calculation or aggregate columns takes
a third statement**, which the spike did not have. Its related query loaded
them in the page's own statement; that fails in the data layer for a reader
whose field policies look at the record (see `AshDataTable.Query.read_related/4`),
so the table loads them onto the page's records afterwards.

Opening a line sends one event. Expanding a row sends one event and reads
nothing.

## What the server holds with many open

One page of `/tasks` (25 rows), with the comments of its rows opened one
after the other and then the project of each: `:erlang.process_info(pid,
:memory)` of the page's LiveView process after a garbage collection, and as
it was found before it.

| Nested tables open | After a collection | As found |
| --- | --- | --- |
| 0 | 86.8 KiB | 416.7 KiB |
| 1 | 139.7 KiB | 285.6 KiB |
| 10 | 225.3 KiB | 678.4 KiB |
| 50 | 950.6 KiB | 1,783.5 KiB |

About 17 KiB for each open nested table, each a component with its own
stream that keeps the keys of its page, its state and its table model. The
prototype reported 0.59 MB with 50 open (in-memory data layer, 25 comments
in each, a model of six columns); this is 0.93 MB with 50 open on Postgres,
half of them a table of seven columns and half one of five, each with its
filter row's model.

Opening one more does not get much slower as they add up: in a second,
shorter run the first five lines took 14 to 20 ms each from click to rows,
and the last five of the fifty 20 to 30 ms (`open_ms_by_number_open` in the
results of a run). Rendering, scrolling and layout with fifty grids in one
page were not measured.
