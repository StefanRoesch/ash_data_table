// Writes RESULTS.md from results.json (written by measure.mjs) and NOTES.md
// (written by hand: what the numbers of the committed run say).

import { existsSync, readFileSync, writeFileSync } from "node:fs"
import path from "node:path"
import { median, summary } from "./lib/stats.mjs"

const here = (file) => path.join(import.meta.dirname, file)
const results = JSON.parse(readFileSync(here("results.json"), "utf8"))
const notes = existsSync(here("NOTES.md")) ? readFileSync(here("NOTES.md"), "utf8").trim() : null

// ---- formatting -------------------------------------------------------------

const ms = (value) => (value === null ? "–" : value < 10 ? value.toFixed(1) : String(Math.round(value)))
const fromUs = (value) => (value === null ? null : value / 1000)
const kb = (bytes) => (bytes === null ? "–" : (bytes / 1000).toFixed(bytes < 10_000 ? 2 : 1))

/** "34 (29–41)": the median with the least and the greatest, in milliseconds. */
function spread(repetitions, field, convert = (value) => value) {
  const { median, min, max, n } = summary(repetitions, field)
  if (n === 0) return "–"
  return `${ms(convert(median))} (${ms(convert(min))}–${ms(convert(max))})`
}

const mid = (repetitions, field) => summary(repetitions, field).median
const server = (repetitions) => repetitions.map((repetition) => repetition.server ?? {})

function table(headers, rows) {
  const line = (cells) => `| ${cells.join(" | ")} |`
  return [line(headers), line(headers.map(() => "---")), ...rows.map(line)].join("\n")
}

const size = (measured) => `${measured.rows} × ${measured.columns}`

// ---- the sections -----------------------------------------------------------

function loads(tables) {
  return table(
    ["Table", "Rows × columns", "Interactive, ms", "HTML answered, ms", "HTML, KB", "HTML on the wire, KB", "Join frame, KB"],
    tables.map((measured) => [
      measured.name,
      size(measured),
      spread(measured.load, "interactive_ms"),
      spread(measured.load, "response_end_ms"),
      kb(mid(measured.load, "html_bytes")),
      kb(mid(measured.load, "html_transferred_bytes")),
      kb(mid(measured.load, "join_frame_bytes")),
    ]),
  )
}

function edits(tables) {
  return table(
    [
      "Table",
      "Rows × columns",
      "Round trip, ms",
      "Frame back, KB",
      "Server: `save` callback, ms",
      "of it: re-fetch, ms",
      "of it: update action, ms",
      "of it: in the database, ms",
      "Round trip less database, ms",
    ],
    tables.map((measured) => {
      const onServer = server(measured.edit)
      const lessDatabase = measured.edit.map((repetition) => ({
        ms: repetition.ms - (repetition.server?.database_us ?? 0) / 1000,
      }))
      return [
        measured.name,
        size(measured),
        spread(measured.edit, "ms"),
        kb(mid(measured.edit, "bytes_received")),
        spread(onServer, "handle_event_us", fromUs),
        spread(onServer, "refetch_us", fromUs),
        spread(onServer, "update_us", fromUs),
        `${spread(onServer, "database_us", fromUs)}, ${mid(onServer, "queries")} queries`,
        spread(lessDatabase, "ms"),
      ]
    }),
  )
}

const READS = [
  ["sort_progress", "Sort by `progress` (a number, no index)"],
  ["sort_title", "Sort by `title` (text, no index)"],
  ["sort_comment_count", "Sort by `comment_count` (an aggregate)"],
  ["sort_an_integer", "Sort by `an_integer`"],
  ["filter", "Filter: `title` contains \"invoice\""],
  ["next_page", "Next page"],
  ["last_page", "Last page (the deepest offset)"],
]

function reads(tables) {
  const rows = []
  for (const measured of tables) {
    for (const [key, label] of READS) {
      const repetitions = measured[key]
      if (!repetitions) continue
      const onServer = server(repetitions)
      rows.push([
        measured.name,
        key === "last_page" ? `${label}: page ${measured.last_page_number}` : label,
        spread(repetitions, "ms"),
        `${kb(mid(repetitions, "bytes_received"))} in ${mid(repetitions, "frames_received")}`,
        kb(mid(repetitions, "largest_frame_bytes")),
        spread(onServer, "read_us", fromUs),
        spread(onServer, "rows_us", fromUs),
        spread(onServer, "count_us", fromUs),
      ])
    }
  }
  return table(
    [
      "Table",
      "What",
      "Round trip, ms",
      "Frames back, KB",
      "Largest frame, KB",
      "Server: the read, ms",
      "of it: rows query, ms",
      "of it: count query, ms",
    ],
    rows,
  )
}

/** Each direction of a sort is a query of its own; the table above takes them together. */
function sortDirections(tables) {
  const rows = []
  for (const measured of tables) {
    for (const [key, label] of READS.filter(([key]) => key.startsWith("sort_"))) {
      if (!measured[key]) continue
      const to = (direction) => measured[key].filter((repetition) => repetition.to === direction)
      rows.push([
        measured.name,
        label,
        ...["ascending", "descending", "none"].map((direction) => ms(mid(to(direction), "ms"))),
      ])
    }
  }
  return table(["Table", "What", "To ascending, ms", "To descending, ms", "Back to no sort, ms"], rows)
}

function keys(tables) {
  return table(
    ["Table", "Keys pressed", "Frames sent", "The hook's work per key, ms"],
    tables.map((measured) => [
      measured.name,
      measured.arrow_keys.keys_pressed,
      measured.arrow_keys.frames_sent,
      measured.arrow_keys.ms_per_key.toFixed(3),
    ]),
  )
}

function memory(entries) {
  const kib = (bytes) => (bytes / 1024).toFixed(1)
  return table(
    [
      "Table",
      "Open pages",
      "Per process, after a GC, KiB",
      "Per process, as found, KiB",
      "Binaries referred to, per process, KiB",
      "All of them, after a GC, MiB",
    ],
    entries.map((entry) => {
      const after = entry.processes.map((process) => process.memory)
      const found = entry.processes.map((process) => process.memory_before_gc)
      const binaries = entry.processes.map((process) => process.binaries)
      const range = (values) => `${kib(median(values))} (${kib(Math.min(...values))}–${kib(Math.max(...values))})`
      return [
        entry.table,
        entry.sessions,
        range(after),
        range(found),
        range(binaries),
        (after.reduce((sum, bytes) => sum + bytes, 0) / 2 ** 20).toFixed(2),
      ]
    }),
  )
}

function volume(large, standard) {
  const rows = []
  for (const measured of large.tables) {
    const other = standard.tables.find((candidate) => candidate.name === measured.name)
    if (!other || measured.id !== "task") continue
    for (const [key, label] of [["edit", "Cell edit"], ...READS, ["load", "Initial load, to interactive"]]) {
      if (!measured[key] || !other[key]) continue
      const field = key === "load" ? "interactive_ms" : "ms"
      const big = mid(measured[key], field)
      const small = mid(other[key], field)
      rows.push([measured.name, label.split(":")[0], ms(small), ms(big), `${(big / small).toFixed(1)} ×`])
    }
  }
  return table(["Table", "What", "400 tasks, ms", "50,000 tasks, ms", "Factor"], rows)
}

function environment() {
  const { machine } = results
  const [first] = results.databases
  const versions = first.versions
  const packages = Object.entries(versions.packages).map(([name, version]) => `${name} ${version}`)
  return [
    `- **Date:** ${results.date.slice(0, 16).replace("T", " ")} UTC, at commit \`${machine.commit}\` plus the working tree of the run`,
    `- **Machine:** ${machine.cpu}, ${machine.cores} logical cores, ${machine.memory_gb} GB; ${machine.os}`,
    `- **Load average** (1, 5, 15 min) when the run began: ${machine.load_average.join(", ")}; when it ended: ${machine.load_average_after.join(", ")}`,
    `- **Server:** Elixir ${versions.elixir}, Erlang/OTP ${versions.otp} (erts ${versions.erts}), ${versions.schedulers} schedulers, \`MIX_ENV=${versions.mix_env}\``,
    `- **Packages:** ${packages.join(", ")}`,
    `- **Database:** PostgreSQL ${versions.postgres} in Docker (the \`postgres\` service of \`docker-compose.yml\`), on the same machine`,
    `- **Browser:** ${results.browser}, ${machine.node.replace("v", "Node ")}; viewport 1600 × 900`,
    `- **Repetitions:** ${results.repetitions} of each thing (5 of the jump to the last page), after one that is not counted. A cell shows the median, with the least and the greatest in brackets.`,
  ].join("\n")
}

function commands() {
  return [
    "```sh",
    "docker compose up -d postgres     # in the repository root",
    "cd demo && mix deps.get",
    "cd perf && npm ci",
    "npm run setup                     # creates, migrates, seeds: demo_perf (large), demo_perf_standard",
    `PERF_REPS=${results.repetitions} npm run measure   # starts the server itself, measures, writes this file`,
    "```",
    "",
    "`npm run measure` started the server twice, with",
    "",
    "```sh",
    ...results.databases.map((entry) => entry.command),
    "```",
  ].join("\n")
}

// ---- the file ---------------------------------------------------------------

const large = results.databases.find((entry) => entry.name === "large")
const standard = results.databases.find((entry) => entry.name === "standard")

const document = `# Performance of the demo's tables on Postgres

Spec section 12 and test layer 4: the prototype's measurements (issue 11),
repeated on the real demo. This file is written by \`npm run measure\` in
\`demo/perf\`; the section "Findings" comes from \`NOTES.md\` beside it, which is
written by hand for the run that is committed. The numbers of every
repetition are in \`results.json\`.

Everything here is **localhost**: browser, server and database on one
machine, no network, no TLS, no compression of the WebSocket.

## The run

${environment()}

${commands()}

## How it was measured

- **The server** runs in the Mix environment \`perf\` (\`config/perf.exs\`):
  no code reloading, no debug annotations in the markup, no expensive runtime
  checks, protocols consolidated, logging at \`warning\`. It differs from
  \`prod\` in that it is started with \`mix phx.server\` and not as a release
  (code is loaded when first used, which is why each thing is done once
  before it is measured), serves plain HTTP on loopback, and its assets are
  neither minified nor digested.
- **The tables** are \`/tasks\` as the admin, who has all 14 columns: at 25
  rows a page, which is what the demo serves, and at 100, the read action's
  \`max_page_size\`. A table's page size is its read action's
  \`default_limit\` and the table has no control for it, so the second is a
  route of the perf environment only, \`/perf/tasks100\`: the same resource,
  compiled from the same source with \`default_limit: 100\`
  (\`perf/server/task.ex\`). \`/specimens\` (20 rows of 47 columns, 36
  records in either seed) is there for a wide row.
- **Round trips** are timed in the page with \`performance.now()\`: from the
  key or click to the moment a \`MutationObserver\` sees the DOM patched with
  the answer (\`aria-busy\` gone from the cell or the grid). Painting is not
  included. For a cell edit the clock starts at the Enter that saves.
- **"Interactive"** is the moment the table's hook has run, counted from
  the start of the navigation: the HTML has arrived, the LiveView has joined
  over the WebSocket and the grid has its tab stop. Assets come from the
  browser's cache.
- **Sizes** are those of the text frames the server sent, uncompressed, and
  of the HTML document, as it is and as it went over the wire (Bandit
  compresses HTTP answers).
- **Server times** come from telemetry events that LiveView, Ash and Ecto
  emit anyway, collected by \`Demo.Perf.Probe\` (perf environment only): the
  table's \`save\` callback, the Ash read that fetches the record again, the
  update action (which also loads the row's calculations and aggregates for
  the answer), and Ecto's time for each query, waiting for a connection
  included.
- **Memory** is \`:erlang.process_info(pid, :memory)\` of each table's
  LiveView process, read on the server by \`Demo.Perf.Probe\` over a route of
  the perf environment, with 1, 10 and 50 pages open in one browser. "As
  found" is before, "after a GC" after a forced garbage collection of that
  process. "Binaries referred to" are outside the process heap and may be
  shared.

## Results with the large seed: ${large.versions.tasks.toLocaleString("en")} tasks

### Initial load

${loads(large.tables)}

### A cell edit saved

A text cell (\`title\`; \`a_string\` on \`/specimens\`), through the table's
\`update\` action.

${edits(large.tables)}

### Sort, filter, page change

Each makes the table read again: a query for the rows, and a query for the
count where the action counts.

${reads(large.tables)}

A click on a header moves its sort on, so the sorts above are a third each
of these:

${sortDirections(large.tables)}

### Arrow keys

Real key presses, to count what goes to the server; then the time of the
hook's handler per key, taken over 2,000 keys dispatched in the page.

${keys(large.tables)}

### Memory of the LiveView process of an open table

${memory(large.memory)}

## What the data volume costs: 400 tasks against 50,000

The same things on the standard seed (${standard.versions.tasks} tasks, of which the admin
sees 320), medians of round trips.

${volume(large, standard)}

<details>
<summary>The standard seed in full</summary>

${loads(standard.tables)}

${edits(standard.tables)}

${reads(standard.tables)}

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
  \`/tasks\` has 14 columns, \`/specimens\` 47 with 20 rows. The prototype's
  100 × 30 lies between the two.
- The machine and the versions, which were not recorded for the prototype in
  a way that could be repeated.

${notes ? `## Findings\n\n${notes}\n` : ""}`

writeFileSync(here("RESULTS.md"), document.trimEnd() + "\n")
console.log("wrote", here("RESULTS.md"))
