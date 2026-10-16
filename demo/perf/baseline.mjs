// The baseline of the refactor (docs/architecture/baseline.md): what five
// things a person does on /tasks cost, before the table is split up, so that
// every stage can be measured the same way and compared. On the standard
// seed (400 tasks), as the admin. Writes baseline-results.json.
//
//   node baseline.mjs
//   PERF_PORT=4490 PERF_REPS=15 node baseline.mjs
//   PERF_PAGE=/support/modes/embedded/tasks node baseline.mjs
//   PERF_NOTIFIED=1 node baseline.mjs   also a save on /perf/notified (stage 6)
//   PERF_WIRE=1 node baseline.mjs       also the bytes on the wire
//   PERF_WIRE=1 PERF_WIRE_DEFLATE=0 node baseline.mjs   the same, uncompressed
//
// `PERF_PAGE` is the page measured, /tasks unless it is given: the same
// table placed by the tag in a LiveView of the host's is
// /support/modes/embedded/tasks (stage 4).
//
// For each thing: the time in the page from the key or click to the patch
// that shows the answer, the bytes of the WebSocket frames the server sent
// for it (uncompressed), and what the server recorded meanwhile: the
// callbacks of the LiveView and the table (`handle_event`, a component's
// `update`), Ash's reads and the database's statements. Run `./setup.sh`
// first.
//
// The frames' bytes are those Playwright shows, inflated. With `PERF_WIRE=1`
// the browser talks to the server through a proxy (lib/wire.mjs) that also
// counts what the server sent on the wire: deflated when the browser and the
// server agreed on permessage-deflate (`compress: true` on the endpoint's
// socket), with the frames' headers. `PERF_WIRE_DEFLATE=0` keeps the browser
// from offering it, so the same server answers uncompressed. Deflate keeps
// its context from message to message, so a later message compresses
// better than the first: compare runs in this script's order only.

import { writeFileSync } from "node:fs"
import os from "node:os"
import path from "node:path"
import { chromium } from "@playwright/test"
import { BASE, sleep, startServer, versions, wireDeflate } from "./lib/server.mjs"
import { logIn, open, Table } from "./lib/table.mjs"

const REPS = Number(process.env.PERF_REPS ?? 15)
const PAGE = process.env.PERF_PAGE ?? "/tasks"
const log = (...words) => console.log(new Date().toISOString().slice(11, 19), ...words)

const sum = (entries) => entries.reduce((total, entry) => total + entry.us, 0)
const named = (events, ...names) => events.filter((event) => names.includes(event.name))

/** What the server recorded for one thing, by kind. */
function onServer(events) {
  const callbacks = named(
    events,
    "live_view.handle_event",
    "live_view.handle_params",
    "live_component.handle_event",
    "live_component.update",
  )
  const queries = named(events, "query")
  return {
    callbacks: callbacks.map((event) => `${event.name}${event.event ? ":" + event.event : ""}`),
    callbacks_us: sum(callbacks),
    ash_reads: named(events, "ash.read").length,
    ash_reads_us: sum(named(events, "ash.read")),
    queries: queries.length,
    database_us: sum(queries),
  }
}

/**
 * Times what `act` does (a function body evaluated in the page, right after
 * the clock starts) to the moment `done` (an expression evaluated in the
 * page) is true after a change of the DOM.
 */
function until(table, done, act) {
  return table.measure(
    ({ done, act }) => {
      const check = new Function(`return (${done})`)
      window.__measured = new Promise((resolve) => {
        let started = null
        const observer = new MutationObserver(() => {
          if (started !== null && check()) {
            observer.disconnect()
            resolve(performance.now() - started)
          }
        })
        observer.observe(document.body, { subtree: true, childList: true, attributes: true })
        window.__act = () => {
          started = performance.now()
          new Function(act)()
        }
      })
    },
    { done, act },
    () => table.page.evaluate(() => window.__act()),
  )
}

const click = (selector) => `document.querySelector(${JSON.stringify(selector)}).click()`
const enter = `document.activeElement.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true }))`

/** A save, as `Table.edit` measures it, with what the server recorded as it was. */
async function save(table, key, column, text) {
  const cell = table.cell(key, column)
  await cell.focus()
  await table.page.keyboard.press("Enter")
  await table.page.keyboard.press("ControlOrMeta+A")
  await table.page.keyboard.type(text)
  // saved once the cell has been busy and is no longer
  const id = JSON.stringify(await cell.getAttribute("id"))
  const saved =
    `(() => { if (document.getElementById(${id}).hasAttribute("aria-busy")) { window.__wasBusy = true; return false }` +
    ` return !!window.__wasBusy })()`
  await table.page.evaluate(() => (window.__wasBusy = false))
  const run = await until(table, saved, enter)
  if ((await cell.getAttribute("aria-invalid")) === "true") throw new Error(`the save of ${column} failed`)
  return run
}

const median = (numbers) => [...numbers].sort((a, b) => a - b)[Math.floor(numbers.length / 2)]
const round = (number) => Number(number.toFixed(1))

function summary(runs) {
  const of = (pick) => runs.map(pick)
  return {
    runs: runs.length,
    median_ms: round(median(of((run) => run.ms))),
    min_ms: round(Math.min(...of((run) => run.ms))),
    max_ms: round(Math.max(...of((run) => run.ms))),
    median_bytes_received: median(of((run) => run.bytes_received)),
    bytes_received: [...new Set(of((run) => run.bytes_received))].sort((a, b) => a - b),
    frames_received: [...new Set(of((run) => run.frames_received))],
    ...(runs[0].wire_bytes_received === null
      ? {}
      : {
          median_wire_bytes_received: median(of((run) => run.wire_bytes_received)),
          wire_bytes_received: [...new Set(of((run) => run.wire_bytes_received))].sort((a, b) => a - b),
        }),
    median_callbacks_ms: round(median(of((run) => run.server.callbacks_us)) / 1000),
    median_ash_reads_ms: round(median(of((run) => run.server.ash_reads_us)) / 1000),
    median_database_ms: round(median(of((run) => run.server.database_us)) / 1000),
    ash_reads: [...new Set(of((run) => run.server.ash_reads))],
    queries: [...new Set(of((run) => run.server.queries))],
    callbacks: [...new Set(of((run) => run.server.callbacks.join(", ")))],
  }
}

async function measured(name, times, run) {
  // once before it is measured: the server loads its code as it is first used
  await run(-1)
  const runs = []
  for (let i = 0; i < times; i++) {
    const result = await run(i)
    runs.push({ ...result, server: onServer(result.server) })
  }
  const result = summary(runs)
  log(name, JSON.stringify(result))
  return result
}

const results = {
  date: new Date().toISOString(),
  repetitions: REPS,
  machine: {
    cpu: os.cpus()[0].model,
    cores: os.cpus().length,
    memory_gb: Math.round(os.totalmem() / 2 ** 30),
    load_average_at_start: os.loadavg(),
  },
  base: BASE,
  page: PAGE,
}

const browser = await chromium.launch()
log("starting the server on demo_perf_standard")
const stop = await startServer("demo_perf_standard")

try {
  results.versions = await versions()
  const context = await browser.newContext({ viewport: { width: 1600, height: 900 } })
  await logIn(context)
  const tasks = await open(context, PAGE, "task")
  const page = tasks.page
  const keys = await tasks.rowKeys()
  const key = (i) => keys[(i + keys.length) % keys.length]

  // ---- a cell save: Enter in the editor of a text cell to the patched cell
  const title = await tasks.cell(keys[0], "title").textContent()
  results.cell_save = await measured("cell save", REPS, (i) =>
    save(tasks, keys[0], "title", `Baseline edit ${i}`),
  )
  await tasks.edit(keys[0], "title", title)

  // ---- expanding a row: the click on its expander to its lines
  const expanded = (k) => `document.querySelector('[id="task-row-${k}-x"] td[data-line]') !== null`
  const expander = (k) => page.locator(`[id="task-row-${k}-e"] > button`)
  results.expand_row = await measured("expand a row", REPS, async (i) => {
    const run = await until(tasks, expanded(key(i)), click(`[id="task-row-${key(i)}-e"] > button`))
    // closed again, not measured
    await expander(key(i)).click()
    await page.locator(`[id="task-row-${key(i)}-x"] td[data-line]`).first().waitFor({ state: "detached" })
    return run
  })

  // ---- opening a nested table: the click on a line to the nested table's rows
  const nested = (k) => `task-row-${k}-t-comments`
  const read = (k) =>
    `(() => { const grid = document.getElementById("${nested(k)}-table");` +
    ` return !!grid && grid.getAttribute("aria-busy") !== "true" && !document.getElementById("${nested(k)}-loading") })()`
  results.open_nested = await measured("open a nested table", REPS, async (i) => {
    const k = key(i + 1)
    await expander(k).click()
    await page.locator(`[id="task-row-${k}-x"] td[data-line]`).first().waitFor()
    const run = await until(tasks, read(k), click(`[id="task-row-${k}-l-comments-b"]`))
    // closed again, with the row, not measured
    await page.locator(`[id="task-row-${k}-l-comments-b"]`).click()
    await page.locator(`[id="${nested(k)}"]`).waitFor({ state: "detached" })
    await expander(k).click()
    await page.locator(`[id="task-row-${k}-x"] td[data-line]`).first().waitFor({ state: "detached" })
    return run
  })

  // ---- opening the picker: Enter on a reference cell to the picker's rows
  const picker = "task-pick-assignee"
  const picked =
    `(() => { const grid = document.getElementById("${picker}-table");` +
    ` return !!grid && grid.getAttribute("aria-busy") !== "true" && grid.querySelector("tbody") !== null })()`
  results.open_picker = await measured("open the picker", REPS, async (i) => {
    const cell = tasks.cell(key(i), "assignee")
    await cell.focus()
    const run = await until(tasks, picked, enter)
    // closed again, not measured
    await page.keyboard.press("Escape")
    await page.locator('[id="task-picker"]').waitFor({ state: "detached" })
    return run
  })

  // ---- opening the panel: the click on a row's "Reassign" to the open
  // action panel with its fields (stage 7)
  const opened =
    `(() => { const panel = document.getElementById("task-panel");` +
    ` return !!panel && panel.open && panel.querySelector("form") !== null })()`
  results.open_panel = await measured("open the panel", REPS, async (i) => {
    const run = await until(tasks, opened, click(`[id="task-row-${key(i)}-a-reassign"]`))
    // closed again, not measured
    await page.keyboard.press("Escape")
    await page.locator('[id="task-panel"]').waitFor({ state: "detached" })
    return run
  })

  // ---- opening the panel in the page: the same on /perf/inline/tasks,
  // whose table opens its panel inline (stage 7b), in a page of its own
  if (PAGE === "/tasks") {
    const inlineTasks = await open(context, "/perf/inline/tasks", "task")
    const inline =
      `(() => { const panel = document.getElementById("task-panel");` +
      ` return !!panel && panel.dataset.presentation === "inline" && panel.querySelector("form") !== null })()`
    results.open_panel_inline = await measured("open the panel inline", REPS, async (i) => {
      const run = await until(inlineTasks, inline, click(`[id="task-row-${key(i)}-a-reassign"]`))
      // closed again, not measured
      await inlineTasks.page.locator('[id="task-panel-cancel"]').click()
      await inlineTasks.page.locator('[id="task-panel"]').waitFor({ state: "detached" })
      return run
    })
    await inlineTasks.page.close()
  }

  // ---- a cell save in a nested table, and one in the top table while a
  // nested table is open (stage 5: every table of a page is in one
  // component). The comments of the first task that has any.
  let withComments = null
  for (const k of keys) {
    await expander(k).click()
    await page.locator(`[id="task-row-${k}-x"] td[data-line]`).first().waitFor()
    await page.locator(`[id="task-row-${k}-l-comments-b"]`).click()
    await page.waitForFunction(new Function(`return ${read(k)}`))
    if ((await page.locator(`#${nested(k)}-table > tbody:not([data-detail])`).count()) > 0) {
      withComments = k
      break
    }
    await page.locator(`[id="task-row-${k}-l-comments-b"]`).click()
    await page.locator(`[id="${nested(k)}"]`).waitFor({ state: "detached" })
    await expander(k).click()
  }
  if (withComments === null) throw new Error("no task on the first page has comments")
  const comments = new Table(page, nested(withComments), tasks.received, tasks.sent)
  const comment = (await comments.rowKeys())[0]
  const body = await comments.cell(comment, "body").textContent()
  results.cell_save_nested = await measured("cell save in a nested table", REPS, (i) =>
    save(comments, comment, "body", `Baseline comment ${i}`),
  )
  await save(comments, comment, "body", body.trim())
  const other = keys.find((k) => k !== withComments)
  const otherTitle = await tasks.cell(other, "title").textContent()
  results.cell_save_nested_open = await measured(
    "cell save with a nested table open",
    REPS,
    (i) => save(tasks, other, "title", `Baseline edit ${i}`),
  )
  await save(tasks, other, "title", otherTitle.trim())
  await page.locator(`[id="task-row-${withComments}-l-comments-b"]`).click()
  await page.locator(`[id="${nested(withComments)}"]`).waitFor({ state: "detached" })
  await expander(withComments).click()

  // ---- selecting a row: the click on its box to the box checked, with
  // what the server sends meanwhile (stage 6: the hook tells it `select`)
  const box = (k) => `[id="task-row-${k}-s"] > input`
  results.select_row = await measured("select a row", REPS, async (i) => {
    const run = await until(tasks, `document.querySelector('${box(key(i))}').checked`, click(box(key(i))))
    // the server has answered before the box is taken out again
    await sleep(100)
    await page.locator(box(key(i))).click()
    await page.waitForFunction(new Function(`return !document.querySelector('${box(key(i))}').checked`))
    await sleep(100)
    return run
  })

  // ---- a page change: the click on "Next" to the rows of the next page
  // forth and back between the first two pages
  results.page_change = await measured("page change", REPS, async (i) => {
    const run = await until(
      tasks,
      `document.getElementById("task-table").getAttribute("aria-busy") !== "true" && document.getElementById("task-range").textContent.startsWith("${i % 2 !== 0 ? 26 : 1}")`,
      click(i % 2 !== 0 ? "#task-next" : "#task-previous"),
    )
    return run
  })

  if (wireDeflate() !== null) results.wire = { permessage_deflate: wireDeflate() }
  await tasks.close()

  // ---- a cell save on a page that is told every event, gives a context and
  // asks a veto (stage 6, /perf/notified): only where the page is there
  if (process.env.PERF_NOTIFIED === "1") {
    const notified = await open(context, "/perf/notified", "task")
    const [first] = await notified.rowKeys()
    const was = await notified.cell(first, "title").textContent()
    results.cell_save_notified = await measured("cell save, notified", REPS, (i) =>
      save(notified, first, "title", `Baseline edit ${i}`),
    )
    await save(notified, first, "title", was.trim())
    await notified.close()
  }

  await context.close()
} finally {
  await stop()
  await browser.close()
  log("stopped the server")
}

const file = path.resolve(
  process.env.PERF_RESULTS ?? path.join(import.meta.dirname, "baseline-results.json"),
)
writeFileSync(file, JSON.stringify(results, null, 1) + "\n")
log("wrote", file)
