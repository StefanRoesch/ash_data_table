# Nested tables on Postgres: one run

A short measurement of nested tables, beside `RESULTS.md` (which
`npm run measure` writes, and which this run did not touch). Written by hand
from `nested-results.json`, the output of `node nested.mjs`.

- **Date:** 2026-10-17 22:05 UTC, on `main` at `1329ea4`: each portal drawn from values of its own, one table model per kind for the page
- **Machine:** 12th Gen Intel Core i7-1255U, 12 logical cores; load average 3.1, 7.6, 6.5 when the run began (the machine was busy), so read the times as orders of magnitude
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
| `/tasks` → Comments (has-many, keyset, counted) | 0 to 5 | 2 | 4.4 ms | 37.4 ms (26.8 to 58.0) |
| `/tasks` → Labels (many-to-many, not paginated) | 0 to 3 | 2 | 4.7 ms | 38.0 ms (28.5 to 60.4) |
| `/tasks` → Project (belongs-to) | 1 | 2 | 3.3 ms | 36.4 ms (28.1 to 55.1) |
| `/tasks` → Newest comment (has-one of many) | 0 or 1 | 2 | 3.6 ms | 34.8 ms (25.9 to 63.2) |
| `/projects` → Tasks (has-many, offset page of 25, counted; a calculation, an aggregate and three reference cells among the columns) | 25 | 9 | 21.1 ms | 77.4 ms (66.6 to 106.1) |

A nested table is read in two statements: the row it belongs to, read again
as the person, with the count, and the page. The page of tasks under a
project takes nine, with what its calculation, aggregate and three
reference columns read.

Opening a line sends one event. Expanding a row sends one event and reads
nothing.

## What the server holds with many open

One page of `/tasks` (25 rows), with the comments of its rows opened one
after the other and then the project of each. Measured in the page's
LiveView process after a garbage collection: **live**, the part of its heap
in use (`garbage_collection_info`), which is what it holds; and the
**heap block**, `:erlang.process_info(pid, :memory)`, which is a step of
the VM's sequence of heap sizes, often twice what is in use, so a count of
it per table jumps. Compare per table on the live bytes.

| Nested tables open | Live | Heap block | Heap block as found |
| --- | --- | --- | --- |
| 0 | 126.9 KiB | 364.0 KiB | 1,765.8 KiB |
| 1 | 162.8 KiB | 364.1 KiB | 1,179.9 KiB |
| 10 | 306.0 KiB | 951.5 KiB | 1,176.9 KiB |
| 50 | 1,141.4 KiB | 2,488.9 KiB | 7,473.2 KiB |

Every nested table is an entry of the one table value in the page's
LiveView process, with its state and the keys of its page; the rows are in
its stream, in the browser. Its table model is made for the person from
the one the page keeps for every table of its kind (`models` of the
table): about 20 KiB live for each one more open, of which about 10 KiB is
LiveView's own change tracking of the nested grid. LiveView keeps the rows
a nested table was last sent with in its change tracking until the next
render; the table itself stores no rows.

Before this, at `85798e7` on the same machine an hour earlier, every nested
table built its own models and every event drew every portal again: 45 KiB
live each (2,387.2 KiB with 50 open, a heap block of 4,025.2 KiB).

Opening one more still gets slower as they add up, much less than before:
the first five lines took 33 to 45 ms each from click to rows, the last
five of the fifty 87 to 94 ms (at `85798e7`: 177 to 371 ms;
`open_ms_by_number_open` in the results of a run). An event of one nested
table sends and patches that table's portal only; what still grows is the
page around them. Measured once more with 1 and with 48 open, opening one
more sends the same frames (29,072 and about 6,900 bytes), and the server
spends about the same in its callbacks (a toggle 3 to 6 ms, each render 1
to 2 ms; the library's own functions about 12 ms under a tracer either
way). The growth is in the browser, in LiveView's patch: it morphs the
whole LiveView's markup for every patch, and the nested tables are inside
it, so indexing it (`indexTree` 6 → 19 ms of CPU, with `isPhxDestroyed`,
`getNodeKey` and `querySelectorAll` from nothing to 6 to 9 ms each) and
the layout the hooks measure (`getBoundingClientRect` 6 → 12 ms) grow with
the page. Before the refactor each nested table was a component, which
LiveView patches on its own. Rendering, scrolling and layout with fifty grids in one
page were not measured.
