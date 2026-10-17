// Measures nested tables on the standard seed: what the server holds with
// 1, 10 and 50 of them open under one page of /tasks, and what opening one
// costs in statements and time. Writes nested-results.json; the numbers of
// the run that is committed are in NESTED.md beside it. Run `./setup.sh`
// first.
//
//   node nested.mjs
//   PERF_PORT=4478 PERF_REPS=5 node nested.mjs

import { writeFileSync } from "node:fs"
import os from "node:os"
import path from "node:path"
import { chromium } from "@playwright/test"
import { BASE, drainEvents, liveViews, sleep, startServer, versions } from "./lib/server.mjs"
import { logIn, open } from "./lib/table.mjs"

const REPS = Number(process.env.PERF_REPS ?? 15)
const log = (...words) => console.log(new Date().toISOString().slice(11, 19), ...words)

const nestedId = (id, key, relationship) => `${id}-row-${key}-t-${relationship}`

/** Expands a row, if it is not, and waits for its lines. */
async function expand(page, id, key) {
  const expander = page.locator(`[id="${id}-row-${key}-e"] > button`)
  if ((await expander.getAttribute("aria-expanded")) === "true") return
  await expander.click()
  await page.locator(`[id="${id}-row-${key}-x"] td[data-line]`).first().waitFor()
}

/**
 * Opens a line and returns the milliseconds from the click to the patch that
 * brings the nested table's rows (or its "No records"), with what the server
 * recorded meanwhile.
 */
async function openLine(page, id, key, relationship) {
  await drainEvents()
  const ms = await page.evaluate(
    ({ button, nested }) =>
      new Promise((resolve) => {
        const started = performance.now()
        const done = () => {
          const grid = document.getElementById(`${nested}-table`)
          if (!grid || grid.getAttribute("aria-busy") === "true") return false
          if (document.getElementById(`${nested}-loading`)) return false
          resolve(performance.now() - started)
          return true
        }
        const observer = new MutationObserver(() => done() && observer.disconnect())
        observer.observe(document.body, { subtree: true, childList: true, attributes: true })
        document.getElementById(button).click()
      }),
    { button: `${id}-row-${key}-l-${relationship}-b`, nested: nestedId(id, key, relationship) },
  )
  await sleep(30)
  const events = await drainEvents()
  const queries = events.filter((event) => event.name === "query")
  const reads = events.filter((event) => event.name === "ash.read")
  return {
    ms,
    rows: await page.locator(`[id="${nestedId(id, key, relationship)}-table"] > tbody:not([data-detail])`).count(),
    statements: queries.length,
    database_ms: queries.reduce((sum, query) => sum + query.us, 0) / 1000,
    ash_reads: reads.length,
  }
}

async function closeLine(page, id, key, relationship) {
  await page.locator(`[id="${id}-row-${key}-l-${relationship}-b"]`).click()
  await page.locator(`[id="${nestedId(id, key, relationship)}"]`).waitFor({ state: "detached" })
}

/** What the page's LiveView process holds, as the server reports it after a garbage collection. */
async function memory(pathname) {
  await sleep(500)
  const { live_views } = await liveViews()
  // the router's page keeps its URL to itself: with no `url` assign, the
  // one page of the table's LiveView is the page (the script opens one at a time)
  const [view, ...others] = live_views.filter((view) =>
    view.url ? new URL(view.url).pathname === pathname : view.view === "AshDataTable.Live.Page",
  )
  if (!view || others.length > 0) throw new Error(`expected one page on ${pathname}`)
  return { memory_bytes: view.memory, memory_before_gc_bytes: view.memory_before_gc, binaries_bytes: view.binaries }
}

const median = (numbers) => [...numbers].sort((a, b) => a - b)[Math.floor(numbers.length / 2)]
const summary = (runs) => ({
  median_ms: Number(median(runs.map((run) => run.ms)).toFixed(1)),
  min_ms: Number(Math.min(...runs.map((run) => run.ms)).toFixed(1)),
  max_ms: Number(Math.max(...runs.map((run) => run.ms)).toFixed(1)),
  median_database_ms: Number(median(runs.map((run) => run.database_ms)).toFixed(1)),
  statements: [...new Set(runs.map((run) => run.statements))],
  ash_reads: [...new Set(runs.map((run) => run.ash_reads))],
  rows: [...new Set(runs.map((run) => run.rows))],
})

const results = {
  date: new Date().toISOString(),
  repetitions: REPS,
  machine: { cpu: os.cpus()[0].model, cores: os.cpus().length, load_average: os.loadavg() },
  base: BASE,
}

const browser = await chromium.launch()
log("starting the server on demo_perf_standard")
const stop = await startServer("demo_perf_standard")

try {
  results.versions = await versions()
  const context = await browser.newContext({ viewport: { width: 1600, height: 900 } })
  await logIn(context)

  // ---- opening one --------------------------------------------------------
  log("opening one nested table,", REPS, "times each")
  const tasks = await open(context, "/tasks", "task")
  const keys = await tasks.rowKeys()
  results.open = {}

  for (const relationship of ["comments", "labels", "project", "latest_comment"]) {
    // once before it is measured: the server loads its code as it is first used
    await expand(tasks.page, "task", keys[0])
    await openLine(tasks.page, "task", keys[0], relationship)
    await closeLine(tasks.page, "task", keys[0], relationship)

    const runs = []
    for (let i = 0; i < REPS; i++) {
      const key = keys[1 + (i % (keys.length - 1))]
      await expand(tasks.page, "task", key)
      runs.push(await openLine(tasks.page, "task", key, relationship))
      await closeLine(tasks.page, "task", key, relationship)
    }
    results.open[`task.${relationship}`] = summary(runs)
    log("task", relationship, JSON.stringify(results.open[`task.${relationship}`]))
  }
  await tasks.close()

  // a page of 25 of a table with a calculation and an aggregate among its columns
  const projects = await open(context, "/projects", "project")
  const projectKeys = await projects.rowKeys()
  await expand(projects.page, "project", projectKeys[0])
  await openLine(projects.page, "project", projectKeys[0], "tasks")
  await closeLine(projects.page, "project", projectKeys[0], "tasks")
  const runs = []
  for (let i = 0; i < REPS; i++) {
    const key = projectKeys[i % projectKeys.length]
    await expand(projects.page, "project", key)
    runs.push(await openLine(projects.page, "project", key, "tasks"))
    await closeLine(projects.page, "project", key, "tasks")
  }
  results.open["project.tasks"] = summary(runs)
  log("project tasks", JSON.stringify(results.open["project.tasks"]))
  await projects.close()

  // ---- memory with many open ------------------------------------------------
  // one page of /tasks: the comments of each of its 25 rows, then the project of each
  const page = await open(context, "/tasks", "task")
  const rows = await page.rowKeys()
  const lines = [...rows.map((key) => [key, "comments"]), ...rows.map((key) => [key, "project"])]
  results.memory = [{ open: 0, ...(await memory("/tasks")) }]
  let opened = 0
  // the time to open each one, with those before it open already
  const timings = []
  for (const count of [1, 10, 50]) {
    for (; opened < count; opened++) {
      const [key, relationship] = lines[opened]
      await expand(page.page, "task", key)
      timings.push((await openLine(page.page, "task", key, relationship)).ms)
    }
    const grids = await page.page.locator("#task-table [role=grid]").count()
    if (grids !== count) throw new Error(`${count} nested tables should be open, ${grids} are`)
    results.memory.push({ open: count, ...(await memory("/tasks")) })
    log("memory with", count, "open:", JSON.stringify(results.memory.at(-1)))
  }
  results.open_ms_by_number_open = timings.map((ms) => Number(ms.toFixed(1)))
  await page.close()
  await context.close()
} finally {
  await stop()
  await browser.close()
  log("stopped the server")
}

const file = path.resolve(process.env.PERF_RESULTS ?? path.join(import.meta.dirname, "nested-results.json"))
writeFileSync(file, JSON.stringify(results, null, 1) + "\n")
log("wrote", file)
