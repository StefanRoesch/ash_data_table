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
