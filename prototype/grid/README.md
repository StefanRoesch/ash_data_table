# Grid prototype (THROWAWAY, ticket #11)

This is a throwaway prototype. It answers ticket #11 and is never promoted to production: no tests, no polish, in-memory data.

## Run it

```sh
cd prototype/grid/host && mix setup && mix phx.server
```

Then open <http://localhost:4477/prototype/grid>.

| URL param | Values | Meaning |
| --- | --- | --- |
| `variant` | `keyed` (A), `streams` (B), `components` (C) | rendering strategy |
| `rows` | `25`, `100`, `500` | page size |
| `cols` | `10`, `30` | number of columns |
| `layout` | `auto`, `fixed` | browser table layout (an extra experiment) |

Example: <http://localhost:4477/prototype/grid?variant=streams&rows=100&cols=30>

The floating bar at the bottom switches variant, rows, columns and layout, and has "open first 10 / 50 nested" buttons. The strip above it shows variant, rows, columns, focused cell, editing cell, last event, server handle time, size of the last frame received, LiveView process memory and how often the hook had to act.

Things to try: a title shorter than 3 characters fails; status `done` fails unless progress is 100 (an error about another field); a price above 100000 fails with an error that has no field; price uses its own action (`:reprice`), status uses `:set_status`, everything else uses `:update`; `External ref` and `Id` are read-only.

## What is where

- `ash_table_proto/` the grid library as a path dependency: three variants (`keyed.ex`, `streams.ex`, `components.ex`), the shared markup (`parts.ex`), the one JS hook (`hook.ex`), columns from `Ash.Resource.Info` (`model.ex`), read and save (`data.ex`).
- `host/` Phoenix 1.8.15, LiveView 1.2.12, ash 3.34.4, ash_phoenix 2.3.25. Demo domain in `lib/host/work.ex`, seeded in ETS at boot (600 tasks, 25 comments on each of the first 60 tasks, 3 on the others).
- `measure/` Playwright scripts and their output in `measure/results/`.

## Decision and recommendation

**Streams (variant B).** The driving dev decided this during the prototype run, because server memory per open table across many users matters most. The numbers support that choice on memory and show what it costs elsewhere.

| At 500 rows x 30 columns | keyed (A) | streams (B) | components (C) |
| --- | --- | --- | --- |
| LiveView process memory after GC | 9.4 MB | **0.14 MB** | 11.2 MB |
| Live data on the heap after GC | 6.4 MB | **0.04 MB** | 6.6 MB |
| Diff for one saved cell | 235 B | **3.4 KB** | 174 B |
| Cell edit, key press to patched DOM | 151 ms | 147 ms | 130 ms |
| Sort click diff | 233 KB | **1220 KB** | 244 KB |
| Sort click, click to patched DOM | 364 ms | 573 ms | 421 ms |

| At 100 rows x 10 columns | keyed (A) | streams (B) | components (C) |
| --- | --- | --- | --- |
| LiveView process memory after GC | 1.5 MB | **0.03 MB** | 1.5 MB |
| Diff for one saved cell | 235 B | **1.9 KB** | 174 B |
| Cell edit, key press to patched DOM | 24 ms | 24 ms | 19 ms |
| Sort click diff | 82 KB | 97 KB | 89 KB |
| With 50 nested tables open: memory after GC | 11.2 MB | **0.6 MB** | 16.2 MB |

What streams buys: memory per open table that does not grow with page size (about 150 to 300 times less than the other two at 500 rows).

What streams costs, measured:

- **A bigger diff per cell edit**: the whole row plus the row's static template parts, 1.9 KB at 10 columns and 3.4 KB at 30, against about 0.2 KB. It does not grow with page size.
- **One extra read per edit**: the record is fetched by primary key before the update. On ETS that is 8 to 10 ms per edit; almost all of it is the ETS data layer scanning the table (see "Re-fetch" below), so the real cost depends on the data layer.
- **Sort re-sends the whole page** even when most rows stay (1.2 MB against 0.23 MB at 500 x 30). At 25 and 100 rows the difference is small. A page change costs the same in all three variants.
- **No change tracking inside a row**, so anything a row's markup reads is sent again on every insert.

What did not differ: the keyboard and editing contract (57 checks pass in all three), focus (never lost after a patch in any variant), arrow-key navigation (zero frames), initial render size (within 6 %), and edit latency up to 100 rows.

If memory were not the priority, C (a LiveComponent per row) has the smallest diff and the cheapest browser patch, and A is the simplest code. Both hold the whole page of records per open table.

## Does a pure LiveView grid with one hook feel good enough?

Yes for 25 and 100 rows: an edit is patched 16 to 34 ms after the key press on a local server, navigation never touches the server (0.1 to 0.4 ms per key), a page change takes 30 to 100 ms. At 500 x 30 (15,000 cells) everything is slow in every variant: 1.1 to 1.3 s to an interactive grid, 130 to 150 ms per edit, 230 to 570 ms for sort and page. Most of the edit time there is the browser (style, layout, paint of a huge table), not LiveView and not the strategy. 500 rows should not be an offered page size without virtual scrolling.

All timings are from one machine with client and server on localhost, so they contain no network latency. This was run by a script, not by a person: nobody has yet sat in front of it and judged the feel.

## Results

Measured with `measure/measure.mjs`: headless Chromium (Playwright), WebSocket frames captured, medians of 10 edits, 6 sort clicks and 6 page changes, 3 page loads. Server started with `PROTO_MEASURE=1` (no code reloader, no live reload); JavaScript unminified, no compression on HTTP or WebSocket. "Round trip" is from the input event to the last DOM mutation of the patch; "to next frame" adds the wait for the browser's next frame. "browser script / layout / style" are Chrome's own counters for the same interval. Raw data: `measure/results/measure-auto.json`.

### Initial render

| rows x cols | variant | HTML KB | join frame KB | join gzip KB | interactive ms | settled ms |
| --- | --- | --- | --- | --- | --- | --- |
| 25 x 10 | keyed | 78.1 | 32.9 | 5.2 | 132.4 | 134.9 |
| 25 x 10 | streams | 78.1 | 33.5 | 5.3 | 128.3 | 134.3 |
| 25 x 10 | components | 78.1 | 34.8 | 5.3 | 117.6 | 120 |
| 25 x 30 | keyed | 203.6 | 75.3 | 9.7 | 147.5 | 151 |
| 25 x 30 | streams | 203.6 | 75.9 | 9.8 | 152.8 | 165.7 |
| 25 x 30 | components | 203.6 | 77.3 | 9.7 | 154.1 | 158 |
| 100 x 10 | keyed | 279.1 | 101.8 | 11.2 | 172.3 | 177.7 |
| 100 x 10 | streams | 279.1 | 104 | 11.5 | 187.2 | 203.5 |
| 100 x 10 | components | 279.1 | 109.9 | 11.9 | 186.2 | 190.6 |
| 100 x 30 | keyed | 752.5 | 254 | 24.4 | 296.5 | 304.4 |
| 100 x 30 | streams | 752.5 | 256.2 | 24.8 | 300.7 | 343.8 |
| 100 x 30 | components | 752.5 | 262.1 | 25.2 | 291.4 | 302 |
| 500 x 10 | keyed | 1358 | 476.4 | 43.5 | 421.8 | 431.2 |
| 500 x 10 | streams | 1358.1 | 487.6 | 45 | 502.7 | 589.2 |
| 500 x 10 | components | 1358.1 | 541.8 | 49.4 | 434.2 | 445.1 |
| 500 x 30 | keyed | 3695.2 | 1222.4 | 107.5 | 1088.4 | 1125.4 |
| 500 x 30 | streams | 3695.2 | 1233.6 | 108.9 | 1301.5 | 1535 |
| 500 x 30 | components | 3695.2 | 1287.8 | 117.3 | 1127.4 | 1165.7 |

### One cell edit saved

| rows x cols | variant | diff bytes | round trip ms | to next frame ms | server handle_event ms | of which re-fetch ms | of which Ash update ms | browser script ms | browser layout ms | browser style ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 25 x 10 | keyed | 233 | 17.4 | 29.2 | 10.1 | 0 | 9.9 | 4.7 | 2 | 1.7 |
| 25 x 10 | streams | 1884 | 21.2 | 25.8 | 16.1 | 9.3 | 6.5 | 3.9 | 2 | 1.7 |
| 25 x 10 | components | 174 | 16.4 | 30.4 | 10 | 0 | 9.7 | 3.5 | 2 | 1.8 |
| 25 x 30 | keyed | 234 | 20.3 | 29.6 | 8.8 | 0 | 8.6 | 8 | 2.3 | 2.2 |
| 25 x 30 | streams | 3361.5 | 22.9 | 29.3 | 16.1 | 8.2 | 6.5 | 6 | 1.6 | 2.1 |
| 25 x 30 | components | 174 | 18.6 | 26.2 | 10.4 | 0 | 10.2 | 4 | 2.1 | 2.3 |
| 100 x 10 | keyed | 235 | 24 | 29.5 | 9.6 | 0 | 9.4 | 7.8 | 6.2 | 2.3 |
| 100 x 10 | streams | 1884 | 24.4 | 30.2 | 14.3 | 7.9 | 6 | 6.5 | 5.7 | 2.6 |
| 100 x 10 | components | 174 | 19.3 | 31.2 | 10.7 | 0 | 10.4 | 3.5 | 4.8 | 2.5 |
| 100 x 30 | keyed | 235 | 34.4 | 45.3 | 11.3 | 0 | 11 | 12.2 | 3.1 | 3.9 |
| 100 x 30 | streams | 3361.5 | 33.7 | 45.7 | 21.3 | 9.2 | 10.6 | 10.7 | 3.8 | 4.8 |
| 100 x 30 | components | 174 | 26.3 | 38.3 | 10.7 | 0 | 10.4 | 4.3 | 3.4 | 4 |
| 500 x 10 | keyed | 235 | 62.7 | 74.3 | 11.9 | 0 | 11.6 | 18.7 | 19.3 | 11.1 |
| 500 x 10 | streams | 1884 | 58.2 | 69.9 | 18.6 | 9.1 | 9.5 | 13.8 | 20.7 | 12.6 |
| 500 x 10 | components | 174 | 49 | 61.7 | 11.2 | 0 | 10.9 | 5.4 | 19.7 | 12.8 |
| 500 x 30 | keyed | 235 | 151.4 | 245.3 | 11 | 0 | 10.7 | 42.2 | 12.7 | 22.5 |
| 500 x 30 | streams | 3368 | 146.7 | 241.5 | 19.5 | 10.2 | 8.8 | 31.8 | 13.3 | 26.2 |
| 500 x 30 | components | 174 | 129.5 | 223.4 | 11.9 | 0 | 11.7 | 10.9 | 13.9 | 26.1 |

### Sort click

| rows x cols | variant | diff KB | round trip ms | to next frame ms | browser script ms | browser layout ms |
| --- | --- | --- | --- | --- | --- | --- |
| 25 x 10 | keyed | 24 | 41.3 | 48 | 11.5 | 2.1 |
| 25 x 10 | streams | 25.1 | 28.7 | 33.1 | 8.6 | 1.8 |
| 25 x 10 | components | 25.7 | 31.5 | 36.3 | 9.8 | 2.1 |
| 25 x 30 | keyed | 61.2 | 40 | 48.5 | 15.7 | 3.5 |
| 25 x 30 | streams | 62.5 | 36.5 | 44.9 | 12.5 | 3.3 |
| 25 x 30 | components | 62.8 | 45.4 | 55.3 | 15.9 | 3.8 |
| 100 x 10 | keyed | 81.8 | 49.5 | 59.4 | 21.5 | 4.5 |
| 100 x 10 | streams | 96.7 | 44.5 | 54.9 | 18.5 | 4.5 |
| 100 x 10 | components | 88.8 | 55.2 | 70 | 23.9 | 4.9 |
| 100 x 30 | keyed | 209.5 | 88.4 | 120.5 | 41.9 | 12.3 |
| 100 x 30 | streams | 244.6 | 86.2 | 118.6 | 40.3 | 12 |
| 100 x 30 | components | 216.6 | 105.6 | 145.9 | 55.1 | 13.1 |
| 500 x 10 | keyed | 105.7 | 155.6 | 197.3 | 87.4 | 20.5 |
| 500 x 10 | streams | 479.3 | 216 | 261 | 148.8 | 19.9 |
| 500 x 10 | components | 116.6 | 167.1 | 218.4 | 98.7 | 21 |
| 500 x 30 | keyed | 233.2 | 363.6 | 553.4 | 219.5 | 59.9 |
| 500 x 30 | streams | 1220 | 573.3 | 741.7 | 395.3 | 58.1 |
| 500 x 30 | components | 244.1 | 421.3 | 636.8 | 276.1 | 59 |

### Page change

| rows x cols | variant | diff KB | round trip ms | to next frame ms | browser script ms | browser layout ms |
| --- | --- | --- | --- | --- | --- | --- |
| 25 x 10 | keyed | 23.8 | 35 | 43.9 | 8.4 | 1.6 |
| 25 x 10 | streams | 24.4 | 26.9 | 32 | 8.5 | 1.6 |
| 25 x 10 | components | 25.4 | 28.3 | 34.8 | 7.3 | 1.7 |
| 25 x 30 | keyed | 60.2 | 31.8 | 44.4 | 13.1 | 3.3 |
| 25 x 30 | streams | 60.8 | 34 | 47 | 13.6 | 3.2 |
| 25 x 30 | components | 61.9 | 35.8 | 49.3 | 15 | 3.3 |
| 100 x 10 | keyed | 93.5 | 44.5 | 60 | 18.4 | 4.5 |
| 100 x 10 | streams | 95.8 | 39.2 | 56.4 | 19.1 | 4.4 |
| 100 x 10 | components | 102.1 | 49.8 | 69.5 | 23.6 | 4.7 |
| 100 x 30 | keyed | 240.8 | 70.3 | 111.4 | 38.5 | 11.5 |
| 100 x 30 | streams | 243.1 | 77.6 | 117 | 37.8 | 11 |
| 100 x 30 | components | 249.4 | 98.8 | 142.7 | 54.1 | 13.3 |
| 500 x 10 | keyed | 280.8 | 86.6 | 125.7 | 46 | 11.8 |
| 500 x 10 | streams | 287.9 | 95 | 135.7 | 63.9 | 12.1 |
| 500 x 10 | components | 308.2 | 96.4 | 140.1 | 59.1 | 11.9 |
| 500 x 30 | keyed | 725 | 234.3 | 374.6 | 136.6 | 35.9 |
| 500 x 30 | streams | 732.1 | 257.5 | 402.2 | 176.1 | 36.2 |
| 500 x 30 | components | 752.4 | 328 | 525 | 186.3 | 36.9 |

### Arrow keys (20 presses)

| rows x cols | variant | frames sent | frames received | median ms | max ms |
| --- | --- | --- | --- | --- | --- |
| 25 x 10 | keyed | 0 | 0 | 0.2 | 0.7 |
| 25 x 10 | streams | 0 | 0 | 0.2 | 0.3 |
| 25 x 10 | components | 0 | 0 | 0.4 | 0.7 |
| 25 x 30 | keyed | 0 | 0 | 0.1 | 0.3 |
| 25 x 30 | streams | 0 | 0 | 0.1 | 0.2 |
| 25 x 30 | components | 0 | 0 | 0.1 | 0.4 |
| 100 x 10 | keyed | 0 | 0 | 0.1 | 0.3 |
| 100 x 10 | streams | 0 | 0 | 0.1 | 0.3 |
| 100 x 10 | components | 0 | 0 | 0.1 | 0.4 |
| 100 x 30 | keyed | 0 | 0 | 0.1 | 0.4 |
| 100 x 30 | streams | 0 | 0 | 0.1 | 0.3 |
| 100 x 30 | components | 0 | 0 | 0.1 | 0.2 |
| 500 x 10 | keyed | 0 | 0 | 0.2 | 0.4 |
| 500 x 10 | streams | 0 | 0 | 0.2 | 0.3 |
| 500 x 10 | components | 0 | 0 | 0.2 | 0.4 |
| 500 x 30 | keyed | 0 | 0 | 0.25 | 0.7 |
| 500 x 30 | streams | 0 | 0 | 0.3 | 0.5 |
| 500 x 30 | components | 0 | 0 | 0.3 | 0.5 |

### LiveView process memory

| rows x cols | variant | process memory after load KB | same after GC KB | live data after GC KB | process memory after edits, sorts, pages KB | same after GC KB | live data after GC KB |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 25 x 10 | keyed | 4611 | 364 | 167 | 8052 | 364 | 168 |
| 25 x 10 | streams | 4611 | 34 | 12 | 4673 | 34 | 13 |
| 25 x 10 | components | 4610 | 364 | 176 | 7473 | 364 | 177 |
| 25 x 30 | keyed | 4610 | 951 | 336 | 8096 | 951 | 337 |
| 25 x 30 | streams | 4610 | 54 | 21 | 5046 | 54 | 22 |
| 25 x 30 | components | 4610 | 951 | 345 | 8126 | 951 | 346 |
| 100 x 10 | keyed | 2487 | 1537 | 637 | 8198 | 1538 | 638 |
| 100 x 10 | streams | 4611 | 34 | 16 | 8198 | 54 | 17 |
| 100 x 10 | components | 2487 | 1537 | 674 | 9018 | 1538 | 675 |
| 100 x 30 | keyed | 7459 | 2487 | 1286 | 15555 | 4023 | 1287 |
| 100 x 30 | streams | 7459 | 54 | 25 | 10636 | 54 | 26 |
| 100 x 30 | components | 7460 | 4023 | 1323 | 15545 | 4023 | 1324 |
| 500 x 10 | keyed | 10909 | 6509 | 3149 | 20463 | 11247 | 3150 |
| 500 x 10 | streams | 9347 | 87 | 34 | 14782 | 87 | 35 |
| 500 x 10 | components | 7459 | 6509 | 3335 | 16547 | 7811 | 3334 |
| 500 x 30 | keyed | 12783 | 9373 | 6367 | 44835 | 23321 | 6368 |
| 500 x 30 | streams | 7459 | 140 | 43 | 29666 | 140 | 44 |
| 500 x 30 | components | 10910 | 11247 | 6553 | 44996 | 23321 | 6552 |

### Nested tables open (100 parent rows x 10 cols, 25 comments x 6 cols each)

| open | variant | open-all diff KB | open-all ms | edit parent (open row) bytes | ms | server ms | script ms | layout ms | edit parent (closed row) bytes | ms | edit nested cell bytes | ms | process memory before, GC KB | live before KB | process memory open KB | same after GC KB | live open KB |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 10 | keyed | 214 | 238.4 | 240 | 30.2 | 10.6 | 12.2 | 5.1 | 236 | 26.3 | 236 | 22.8 | 1537 | 637 | 12144 | 4023 | 1500 |
| 10 | streams | 230.3 | 229.9 | 2210 | 34 | 17.8 | 12.5 | 5.3 | 1901 | 27.3 | 1386.5 | 26.8 | 34 | 16 | 10573 | 140 | 68 |
| 10 | components | 235.2 | 241.7 | 181 | 27.5 | 11.3 | 9.1 | 5 | 175 | 20 | 175 | 21.5 | 1537 | 674 | 9400 | 4023 | 1634 |
| 50 | keyed | 1088.6 | 1141 | 240 | 63.3 | 11.8 | 26.5 | 5.6 | 236 | 57.5 | 236 | 46.3 | 1537 | 637 | 26245 | 11247 | 4965 |
| 50 | streams | 1169.3 | 1078.3 | 2210 | 63.9 | 16.9 | 24.6 | 5.8 | 1901 | 54.9 | 1386.5 | 46.7 | 34 | 16 | 17025 | 588 | 276 |
| 50 | components | 1196.9 | 1192.4 | 181 | 53.9 | 13.3 | 13.7 | 5.7 | 175 | 42.1 | 175 | 44.3 | 1537 | 674 | 21992 | 16195 | 5490 |

Notes on the tables:

- "process memory" is `:erlang.process_info(pid, :memory)`. It moves in large steps because heap blocks do, which is why 100 x 30 and 500 x 10 sometimes show the same figure after different work. "live data" is the words in use on the heap right after a forced full GC plus referenced off-heap binaries; it is the better figure for comparing strategies.
- "process memory after load" before GC is mostly garbage from rendering and says little.
- The first join frame carries the same rows in all variants; gzip brings 1.2 MB down to 0.11 MB, so enabling compression on the socket matters more for first render than the choice of strategy.
- Server handle time is `handle_event` only. It is dominated by Ash on ETS (see below).
- `layout=fixed` (declared column widths, `table-layout: fixed`) was tried at 500 x 30 to cut browser time: no measurable gain (edit 145 / 145 / 123 ms against 151 / 147 / 130). Data in `measure/results/layout-fixed-500x30.json`.

## Streams: the points that were checked specifically

**(a) Does `stream_insert` of a row lose focus or an open editor's value?** No, in every case tried (all in `measure/contract.mjs`, all pass):

- a row is re-inserted while one of its cells has focus: focus and `tabindex=0` stay;
- a row is re-inserted by the server while an editor is open in another row, and in the same row: the editor, its typed value and focus stay, and the edit then saves;
- with 400 ms simulated latency: a save in one cell returns while the person is already typing in another cell of the same row: the second editor keeps value and focus, the first cell shows the saved value; the second edit then saves;
- the same with a failing first save: the first cell turns invalid with the error, the second editor is untouched, and the first cell's error survives the row refresh caused by the second save.

This works because the hook marks the cell being edited with `phx-update="ignore"` in the DOM for the duration of the edit, so the re-inserted row is merged around it. See "Risks".

**(b) The re-fetch by primary key.** 8 to 10 ms per edit in the prototype (column "of which re-fetch"), roughly doubling server time per edit (16 to 21 ms against 9 to 12 ms). In isolation (`measure/ash_checks.exs`): `Ash.get!` of one task takes 5.9 ms and reading all 600 tasks takes 5.5 ms, so the cost is the ETS data layer scanning the table, not the re-fetch as such. What it costs on Postgres was not measured. The re-fetch is `Ash.get!/3`, which runs the primary read action: with an actor, a record of another owner comes back as `NotFound` and a field behind a field policy as `%Ash.ForbiddenField{}` (both run in `ash_checks.exs`). The prototype itself passes no actor; the real implementation must pass actor and tenant to this call.

**(c) Row refresh after a save without a second read of our own.** `AshPhoenix.Form.submit(form, params: ..., action_opts: [load: [...]])` returns the updated record with the calculation loaded, and field policies are applied to that returned record even when the record handed to the form was read without authorization (both run in `ash_checks.exs`; this also answers the "to verify" of ticket #10). Ash carries out that `load` as a read by primary key internally, so there is no second read in table code but there is one in Ash. The prototype passes `load` through but its demo resources have no calculations.

**(d) Memory with nested tables open** (each nested table is its own stream): 140 KB with 10 open and 588 KB with 50 open, after GC, against 4.0 MB and 11 to 16 MB for the other two.

**(e) Can the per-edit diff be made smaller?** The real frame was taken apart (`measure/diff_floor.mjs`, output in `measure/results/diff_floor.txt`):

| | 10 columns | 30 columns |
| --- | --- | --- |
| frame as measured | 1880 B | 3317 B |
| of which static template parts (sent again on every insert) | 756 B | 756 B |
| of which per-cell `id` + `aria-colindex` + `aria-readonly` | 375 B | 1138 B |
| of which the values themselves | 83 B | 246 B |
| the frame gzipped | 770 B | 1068 B |
| computed: without `aria-colindex` on cells | 1658 B | 2675 B |
| computed: also without cell ids | 1525 B | 2239 B |
| computed: also with short class names | 1319 B | 2033 B |

The last three rows are arithmetic on the captured frame, not runs. The floor is the row's values plus JSON keys plus the statics: roughly 1 KB at 10 columns and 1.3 KB at 30. Levers, in order of effect: enable WebSocket compression (about a third of the size, no markup change); drop `aria-colindex` from cells (ARIA only needs it when columns are missing from the DOM); address cells by row id and column index instead of a DOM id per cell; replace the long utility-class strings on `td` by one class. Already done in the prototype: a plain text cell is two dynamic slots (attributes, value).

**(f) Sort and page change with `stream(..., reset: true)`.** Both work; focus stays on the header after a keyboard sort; after a page change the hook moves the roving `tabindex` to the cell at the same position. Sort re-sends every row of the page; a keyed comprehension only sends rows that are new to the page plus moves, which matters only at large pages (see tables). Open nested tables and failed-edit markers are dropped on sort and page change (in all variants).

## Risks and workarounds the real streams implementation must carry

1. **The table element is the stream container**, with `<thead>` as a non-stream child that has an id, and one `<tbody>` per row as the stream items (a row plus the optional row holding its nested table). This worked, including updates to the header (`aria-sort`). A non-stream child without an id would not.
2. **The server still needs some state per open table**: the page's primary keys in order (for `aria-rowindex` and for "which row is the Nth"), the set of open rows, and the failed edits (`%{row => %{column => {typed, message}}}`). A failed edit has to be rendered by the server because every re-insert of the row would otherwise wipe it.
3. **The cell under edit is frozen on the client** by setting `phx-update="ignore"` on it from the hook. LiveView's client checks the attribute on the live element (`DOM.isIgnored(fromEl, ...)` in `dom_patch.ts`), which is why this works, but setting it from JavaScript is not a documented use. If it stopped working, the fallback is one editor per grid in a server-rendered `phx-update="ignore"` container positioned over the cell.
4. **A cell frozen during an edit misses updates.** If the row changes while a cell is open and the edit is then cancelled, the hook puts the pre-edit text back; if that cell's value was the one that changed, it stays stale until the row is inserted again. Reasoned from the code, not reproduced.
5. **Hook `updated()` is enough for streams and keyed**; all 57 checks pass with the MutationObserver switched off (`node contract.mjs --no-observer`). It is not enough for C: a patch of a row LiveComponent never calls `updated()` on the grid root, and the roving `tabindex` is lost (6 checks fail). The prototype keeps the observer on as a safety net; with streams it could be dropped.
6. **The server renders `tabindex="-1"` on every cell**, so every patch of a row resets the active cell; the hook restores it in `updated()`. Focus itself survives because row and cell DOM ids are stable. In the whole walk the hook never had to restore lost focus in any variant.
7. **Nothing a row reads is change tracked.** For example the grid's `aria-label` is re-sent with every diff in the prototype because of how it is computed; keep per-row markup free of anything that is not per-row.
8. **Single root per row component.** `Parts.row/1` renders one `<tbody>`; that matters for A (next section) and is harmless for streams.
9. **Each edit acts on a freshly read record.** That is a benefit (no update built on a stale copy), but "unchanged value calls nothing" is decided in the hook against the text shown, which can be older than the database.

## Tried on the side: making keyed cheaper in the browser

The first run showed A as the slowest variant on a cell edit at large pages (267 ms at 500 x 30, 156 ms of it script), because the LiveView client rebuilt and morphed the whole grid for a one-cell diff. Rendering each row through a function component with a single root element lets the client skip unchanged rows (`data-phx-skip`): script time fell from 156 ms to 42 ms and the edit from 267 ms to 150 ms. That change is in the prototype and in the tables above. It adds about 90 bytes to a streams row diff. Not pursued further after the decision for streams.

## The four verification points

**1. Does `AshPhoenix.Form` suit a single-cell edit?** Yes. The whole save (`ash_table_proto/lib/ash_table_proto/data.ex`):

```elixir
form = AshPhoenix.Form.for_update(record, col.action, as: "cell")

case AshPhoenix.Form.submit(form, params: %{to_string(col.name) => value}, action_opts: [load: load]) do
  {:ok, record} -> {:ok, record}
  {:error, form} -> {:error, error_message(form, col.name)}
end
```

- Params casting: strings from the editors were cast for every type tried, including `"true"`/`"false"`, `"2027-01-02"`, the `datetime-local` form `"2027-01-02T10:30"`, decimals and enum values. Constraint errors come back as the action's messages ("length must be greater than or equal to 3", "must be less than or equal to 100").
- Errors for the field: `AshPhoenix.Form.errors(form)` returns `[field: "message"]`, already interpolated.
- Errors about another field come back in the same list under that field's name; the prototype shows them on the edited cell as `progress: must be 100 before the task can be done`.
- Errors with no field are **not** in `errors/1`. They have to be taken from `AshPhoenix.Form.raw_errors(form)` and turned into text with `Exception.message/1`. This is the one place where the form does not do the whole job.
- Cost: about 0.1 to 0.4 ms over a bare `Ash.update!` (6.3 ms against 6.1 ms on ETS).
- Not tried: a forbidden action (the demo has no policies), nested forms, and whether `raw_errors/1` is the right source for every error class.

**2. Where does "which cell is being edited" live?** Entirely in the hook. The server only knows about saves and about failed edits. Reasons: opening a cell is instant and costs no frame; typing starts the editor inside the same key event, so no character is lost however slow the connection is; Escape and unchanged values never reach the server; and the server has no per-user edit state to keep, which fits streams. The editor markup still comes from the server: one inert `<template>` per editable column, cloned into the cell. The cost of this approach is point 3 and 4 under "Risks". Keeping it in a server assign instead would cost one round trip to open a cell, a buffer in the hook for keys typed before the input arrives, and a re-insert of the row on open and on close.

**3. axe-core** (`measure/axe.mjs`, output in `measure/results/axe.txt`), same in all three variants:

- plain grid, text editor open, select editor open, 10 nested tables open: 0 violations;
- failed save showing: 1 violation, `color-contrast` (serious) on the error text (daisyUI `text-error` on the tinted cell). A styling matter for the default look;
- whole page: `region` (moderate) on the prototype's own debug strip, not the grid.

axe marks colour contrast as "incomplete" (needs a human) in every state. axe checks markup rules only; no screen reader was used.

**4. Does a nested grid inside a row cause ARIA or focus problems?**

- axe finds nothing with nested grids open.
- Focus: none found. The whole tree has exactly one `tabindex="0"` at any time, at whatever depth, so the grid stays one tab stop; Tab from inside a nested grid leaves the whole grid and Shift+Tab returns to the nested cell. Arrow keys stay inside the grid that has focus.
- ARIA: it is not a treegrid in the strict sense. The prototype uses `role="grid"`, puts `aria-expanded` on the expander button, and places the nested table in an extra row with one cell that spans all columns and contains another `role="grid"`. A true treegrid has child rows of the same grid with `aria-level`; a nested table with other columns cannot be expressed that way. The extra row has no `aria-rowindex`. How a screen reader announces a grid inside a gridcell is not verified.
- Keyboard: the extra cell is a stop for arrow navigation; Enter on it moves into the nested grid, Escape in the nested grid moves back to it. That is the APG rule for a cell containing a widget, and needs a person to judge.

## The colocated hook shipped from a dependency

**It works as an extracted colocated hook; no fallback was needed.** The `runtime` variant and the prebuilt ES module were therefore not tried.

Library side:

- `mix.exs` needs `compilers: [:phoenix_live_view] ++ Mix.compilers()`. Verified as required: without it the hook's `.js` file is still extracted, but no `index.js` manifest is written, and the host bundle fails with `Could not resolve "phoenix-colocated/ash_table_proto"`.
- The hook is a `<script :type={Phoenix.LiveView.ColocatedHook} name=".Grid">` inside a function component that is never rendered (`AshTableProto.Hook.script/1`). Extraction happens at compile time.
- The `.Grid` shorthand only resolves inside the module that defines the script. Other modules of the library use the full name, `phx-hook="AshTableProto.Hook.Grid"`.

Host side:

- `app.js`: `import {hooks as ashTableHooks} from "phoenix-colocated/ash_table_proto"` and `...ashTableHooks` in the `hooks` option.
- No config change: the generated esbuild config already has `NODE_PATH` containing `Mix.Project.build_path()`, and the manifest is written to the host's `_build/dev/phoenix-colocated/ash_table_proto/`.
- `app.css`: one `@source` line so Tailwind sees the library's classes (`../../deps/ash_table/lib` for a Hex dependency; the prototype uses the path of the path dependency).
- Built with the `esbuild` and `tailwind` Hex packages only. No npm in the host.

Not verified: the same with a package fetched from Hex instead of a path dependency (the compile step is the same, but it was not run), a release build with minified assets, and umbrella projects. LiveView also creates a dangling `node_modules` symlink next to the manifest pointing at `<library>/assets/node_modules`; harmless here.

## Qualitative notes

- Focus lost after a patch: never, in any variant, in the whole walk (the hook's restore path ran 0 times).
- An open editor's typed value survived an unrelated patch in every variant, for a patch of another row and of the same row.
- Save in progress: the cell shows the typed value at once and carries `aria-busy="true"` (dimmed) until the patch arrives; the patch removes the attribute by itself. If the server accepts a value that renders the same as before, no patch arrives and the hook puts the old content back from the reply callback.
- A bug found on the way and fixed: restoring focus from a MutationObserver fired in the middle of a click that moved focus from an editor to another cell, and pulled focus back for an instant.
- Ash's ETS data layer scans the table for every read and update, which puts a floor of about 6 to 10 ms under every save and hides differences in server time between the variants.
- The Phoenix dev defaults `debug_heex_annotations` and `debug_attributes` are switched off in `host/config/dev.exs`; with them on, payloads are much larger and not comparable.

## Keyboard contract: what felt wrong or needs a person to judge

1. **Enter after editing keeps focus on the same cell.** Spreadsheets move down. APG allows both.
2. **Ctrl+Home goes to the first data row**, not the header row. The header is reached with Up Arrow from the first row (needed to sort by keyboard).
3. **Page Up / Page Down** move by the number of rows that fit the window minus two. On a 25-row page that is simply first and last row, and Page Up from the top lands on the header.
4. **Space does nothing at all**, also on a checkbox cell (Enter or F2 toggles it). Reserved for row selection as decided, but a checkbox that ignores Space is surprising.
5. **Typing on an enum cell** opens the select and drops the character (a select would treat it as type-ahead and save at once). On a date or datetime cell the character goes into the first segment of the native picker, which depends on locale.
6. **Number cells**: Up and Down Arrow change the value while editing (native input). Long text is edited in a single-line input.
7. **Tab leaves the grid but lands on the pager** ("Next"), which sits inside the grid's root element. A nested table with more than one page would put pager buttons, and so tab stops, inside the parent grid. Not exercised: nested tables here have exactly one page.
8. **Shift+Tab while an editor is open** was not tried.
9. **A failed cell grows**: the error text is shown inside the cell under the value and makes the row taller. Cells are truncated at a fixed maximum width with no way to see the full text except editing.
10. **Escape has three meanings** depending on where focus is: cancel an edit, clear a failed cell, leave a nested grid.
11. **Left Arrow on a closed expander does nothing**; in a treegrid it would move to the parent row.

## Not done or unverified

- No person has used it; all behaviour claims come from the Playwright walk in headless Chromium. Firefox and Safari were not run.
- No screen reader test.
- Only ETS. Cost of the re-fetch and of `load:` on Postgres is unknown.
- No actor, tenant or policies in the prototype's own resources; policies were only checked in the separate `ash_checks.exs` script. A forbidden action as a cell error was not tried.
- No real network: no latency except the 400 ms simulation in three checks, no compression, unminified JavaScript, dev build.
- Timings are single runs of medians on one machine; expect a few milliseconds of noise. The run was repeated once after fixing the measurement setup; the earlier run in normal dev mode was discarded because code reloading and live reload disturbed it.
- The "computed" rows of the diff table are arithmetic, not runs.
- Risk 4 (stale cell after a cancelled edit) is reasoned, not reproduced.
- `confirm` on a column, row actions, row selection, filters, URL state for page and sort, column resizing: not in the prototype.
- The colocated hook from a Hex package (as opposed to a path dependency), in a release, and under a Content Security Policy.
- Datetime cells show minutes only; a value with seconds would lose them when edited. Not tried.
- Concurrent edits by two users.
- The `runtime` colocated hook and the prebuilt ES module routes.

## Reproduce the measurements

```sh
cd prototype/grid/host && mix setup && PROTO_MEASURE=1 mix assets.build && PROTO_MEASURE=1 mix phx.server
# in a second shell (Node is only used here, never by the host app):
cd prototype/grid/measure && npm install
node contract.mjs                 # the keyboard and editing contract, 57 checks per variant
node contract.mjs --no-observer   # the same with the hook relying on updated() only
node measure.mjs                  # all tables above -> results/measure-auto.{json,md}
node axe.mjs                      # axe-core
node diff_floor.mjs               # what is in a streams edit diff
cd ../host && mix run ../measure/ash_checks.exs   # Ash-side checks (server need not run)
```

`PROTO_MEASURE=1` uses its own build directory (`_build_measure`), turns off the code reloader, live reload and the asset watchers. `GET /prototype/grid/reset` restores the seed data; the scripts call it.
