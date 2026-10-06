// Measures the demo's tables on Postgres, as the prototype was measured on
// an in-memory data layer (spec section 12; the prototype's numbers are in
// issue 11), and writes results.json. `node report.mjs` turns that into
// RESULTS.md. Run `./setup.sh` first.
//
//   npm run measure          both, with 15 repetitions of everything
//   PERF_REPS=3 node measure.mjs   a quick look
//   PERF_REPS=1 PERF_RESULTS=/tmp/smoke.json node measure.mjs
//                            whether it still runs, the committed results left alone

import { execFileSync } from "node:child_process"
import { writeFileSync } from "node:fs"
import os from "node:os"
import path from "node:path"
import { chromium } from "@playwright/test"
import { BASE, liveViews, serverCommand, sleep, startServer, versions } from "./lib/server.mjs"
import { logIn, open } from "./lib/table.mjs"

const REPS = Number(process.env.PERF_REPS ?? 15)
if (REPS < 1) throw new Error("PERF_REPS must be at least 1")

// The table of /tasks, as the admin (all 14 columns), at its two page sizes.
// The second exists in the perf environment only (perf/server/task.ex).
const TABLES = [
  { name: "tasks, 25 rows", path: "/tasks", id: "task", text: "title" },
  { name: "tasks, 100 rows", path: "/perf/tasks100", id: "task", text: "title" },
]

// The widest table of the demo (47 columns), for the cost of a row with many
// columns. It has 36 records in either seed.
const SPECIMENS = {
  name: "specimens, 20 rows",
  path: "/specimens",
  id: "specimen",
  text: "a_string",
  sorts: ["an_integer"],
}

const DATABASES = [
  { name: "large", database: "demo_perf", sessions: [1, 10, 50] },
  { name: "standard", database: "demo_perf_standard", sessions: [] },
]

const log = (...words) => console.log(new Date().toISOString().slice(11, 19), ...words)

async function repeat(times, run) {
  const repetitions = []
  for (let i = 0; i < times; i++) repetitions.push(await run(i))
  return repetitions
}

/** Everything that is measured on one table of one database. */
async function measureTable(context, table) {
  const result = { ...table }

  log(table.name, "initial load")
  await (await open(context, table.path, table.id)).close()
  result.load = await repeat(REPS, async () => {
    const opened = await open(context, table.path, table.id)
    await opened.close()
    return opened.load
  })

  const page = await open(context, table.path, table.id)
  result.rows = page.load.rows
  result.columns = page.load.columns
  const [first] = await page.rowKeys()

  // Each thing is done once before it is measured: the server loads its
  // code as it is first used, and that is not what is measured here.

  // a text cell, through the table's `update` action; put back afterwards
  log(table.name, "cell edit")
  const text = await page.cell(first, table.text).textContent()
  await page.edit(first, table.text, "Measured edit, warming up")
  result.edit = await repeat(REPS, (i) => page.edit(first, table.text, `Measured edit ${i}`))
  await page.edit(first, table.text, text)

  // each click moves the sort on: ascending, descending, none
  for (const column of table.sorts ?? ["progress", "title", "comment_count"]) {
    log(table.name, "sort by", column)
    for (let i = 0; i < 3; i++) await page.sort(column)
    result[`sort_${column}`] = await repeat(REPS, async (i) => ({
      to: ["ascending", "descending", "none"][i % 3],
      ...(await page.sort(column)),
    }))
    // back to no sort for what follows
    for (let i = REPS; i % 3 !== 0; i++) await page.sort(column)
  }

  if (table.id === "task") {
    log(table.name, "filter")
    await page.filter("title", "invoice")
    await page.clearFilters()
    result.filter = await repeat(REPS, async () => {
      const applied = await page.filter("title", "invoice")
      await page.clearFilters()
      return applied
    })

    log(table.name, "page change")
    await page.nextPage()
    await page.toPage(1)
    result.next_page = await repeat(REPS, async () => {
      // on the last page there is no next one: start again
      if (await page.page.locator("#task-next").isDisabled()) await page.toPage(1)
      return page.nextPage()
    })
    await page.toPage(1)
    // the last page: the deepest offset there is
    const last = await page.page.locator(`#task-pagination button[id^="task-page-"]`).last().textContent()
    result.last_page = await repeat(Math.min(REPS, 5), async () => {
      const there = await page.toPage(Number(last))
      await page.toPage(1)
      return there
    })
    result.last_page_number = Number(last)
  }

  log(table.name, "arrow keys")
  result.arrow_keys = await page.arrowKeys(first, table.text)

  await page.close()
  return result
}

/**
 * The memory of the table's LiveView process with `count` pages open on the
 * table, as the server reports it for each process.
 */
async function measureMemory(context, table, count) {
  log(table.name, "memory with", count, "open")
  const pages = []
  for (let i = 0; i < count; i++) pages.push(await open(context, table.path, table.id))
  await sleep(500)

  const { live_views, vm } = await liveViews()
  const tables = live_views.filter((view) => view.url && new URL(view.url).pathname === table.path)
  if (tables.length !== count) {
    throw new Error(`${count} pages are open on ${table.path}, the server has ${tables.length}`)
  }

  for (const page of pages) await page.close()
  // the processes end when their sockets close
  for (let i = 0; i < 100; i++) {
    if ((await liveViews()).live_views.length === 0) break
    await sleep(100)
  }

  return { sessions: count, processes: tables, vm_total_bytes: vm.total, vm_processes_bytes: vm.processes }
}

function machine() {
  const run = (command, args) => {
    try {
      return execFileSync(command, args, { encoding: "utf8" }).trim()
    } catch {
      return null
    }
  }
  return {
    cpu: os.cpus()[0].model,
    cores: os.cpus().length,
    memory_gb: Math.round(os.totalmem() / 2 ** 30),
    os: `${os.type()} ${os.release()} ${os.arch()}`,
    node: process.version,
    load_average: os.loadavg().map((load) => Number(load.toFixed(2))),
    commit: run("git", ["rev-parse", "--short", "HEAD"]),
  }
}

const results = {
  date: new Date().toISOString(),
  repetitions: REPS,
  machine: machine(),
  base: BASE,
  databases: [],
}

const browser = await chromium.launch()
results.browser = `Chromium ${browser.version()} (headless), Playwright`

for (const { name, database, sessions } of DATABASES) {
  log("starting the server on", database)
  const stop = await startServer(database)
  try {
    const context = await browser.newContext({ viewport: { width: 1600, height: 900 } })
    await logIn(context)

    const entry = { name, database, command: serverCommand(database), versions: await versions(), tables: [], memory: [] }
    for (const table of TABLES) entry.tables.push(await measureTable(context, table))
    entry.tables.push(await measureTable(context, SPECIMENS))

    for (const table of TABLES) {
      for (const count of sessions) entry.memory.push({ table: table.name, ...(await measureMemory(context, table, count)) })
    }

    results.databases.push(entry)
    await context.close()
  } finally {
    await stop()
    log("stopped the server")
  }
}

await browser.close()
results.machine.load_average_after = os.loadavg().map((load) => Number(load.toFixed(2)))

// PERF_RESULTS names another file, for a run that is not to replace the
// committed results (report.mjs reads results.json).
const file = path.resolve(process.env.PERF_RESULTS ?? path.join(import.meta.dirname, "results.json"))
writeFileSync(file, JSON.stringify(results, null, 1) + "\n")
log("wrote", file)
