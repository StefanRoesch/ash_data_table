// THROWAWAY PROTOTYPE (#11). The numbers: payload sizes, round trips and
// server memory for every variant at rows x cols, and with nested tables open.
//
//   node measure.mjs            everything -> results/${NAME}.json + results/${NAME}.md
//   node measure.mjs matrix     only rows x cols
//   node measure.mjs nested     only the nested-table case
import fs from "node:fs"
import zlib from "node:zlib"
import {launch, open, goto, reset, act, settle, focusCell, stats, median, round, url, VARIANTS, LAYOUT} from "./lib.mjs"

const what = process.argv[2] || "all"
const ROWS = process.env.ROWS ? process.env.ROWS.split(",").map(Number) : [25, 100, 500]
const COLS = process.env.COLS ? process.env.COLS.split(",").map(Number) : [10, 30]
const EDITS = 10
const NAME = process.env.NAME || `measure-${LAYOUT}`
const browser = await launch()
const out = {matrix: [], nested: []}
fs.mkdirSync("results", {recursive: true})

const key = (page, k) => page.keyboard.press(k)
const med = (samples, field) => round(median(samples.map(s => s[field]).filter(x => x !== null)), 1)

// Edit the title of `count` different rows: Enter, replace the text, Enter.
// The clock starts at the committing Enter (the last keydown).
async function edits(page, frames, rowsFrom, count, col = "title", grid = "g") {
  const samples = []
  for (let i = 0; i < count; i++) {
    await focusCell(page, rowsFrom + i, col, grid)
    await key(page, "Enter")
    await page.keyboard.press("Control+a")
    await page.keyboard.type(`Edited ${i} ${Date.now() % 100000}`)
    const sample = await act(page, frames, () => key(page, "Enter"))
    const last = (await stats(page, false)).last
    samples.push({...sample, handle_us: last.handle_us, render_us: last.render_us, refetch_us: last.refetch_us ?? 0, save_us: last.save_us})
  }
  const bad = samples.filter(s => s.sent !== 1 || s.received !== 1)
  if (bad.length) console.log("  !! edit with unexpected frame count", bad.map(s => [s.sent, s.received]))
  return {bytes: med(samples, "recv_bytes"), patch_ms: med(samples, "patch_ms"), frame_ms: med(samples, "frame_ms"),
    script_ms: med(samples, "script_ms"), layout_ms: med(samples, "layout_ms"), style_ms: med(samples, "style_ms"),
    refetch_ms: round(median(samples.map(s => s.refetch_us)) / 1000, 1), save_ms: round(median(samples.map(s => s.save_us)) / 1000, 1),
    handle_ms: round(median(samples.map(s => s.handle_us)) / 1000, 1), render_ms: round(median(samples.map(s => s.render_us)) / 1000, 1), n: samples.length}
}

async function matrix(variant, rows, cols) {
  await reset()
  // initial render, three times: dead-render HTML, join payload, time until the hook is mounted
  const loads = []
  let page, frames, errors
  for (let i = 0; i < 3; i++) {
    if (page) await page.context().close()
    ;({page, frames, errors} = await open(browser))
    const response = await page.goto(url(variant, rows, cols))
    const html = (await response.body()).length
    await page.waitForFunction(() => window.__m && window.__m.mounted !== null)
    await settle(page)
    const m = await page.evaluate(() => ({mounted: window.__m.mounted, frame: window.__m.frame}))
    const join = frames.received[0]
    loads.push({html, join: join.size, join_gz: zlib.gzipSync(join.payload).length, mounted_ms: m.mounted, settled_ms: m.frame})
  }
  const memLoad = await stats(page, true)

  const edit = await edits(page, frames, 0, EDITS)

  // sort: click the Title header six times (asc, desc, none, twice)
  const sorts = []
  for (let i = 0; i < 6; i++) sorts.push(await act(page, frames, () => page.click('#g th[data-col="title"]')))

  // page change: next, previous, three times
  const pages = []
  for (let i = 0; i < 6; i++) pages.push(await act(page, frames, () => page.click(`#g [data-pager="${i % 2 ? "prev" : "next"}"]`)))

  // arrow keys: no frames at all, and the time from keydown to the focus change
  await focusCell(page, 0, "title")
  await page.evaluate(() => { window.__m.nav = [] })
  const nav = await act(page, frames, async () => {
    for (let i = 0; i < 20; i++) await key(page, i % 2 ? "ArrowRight" : "ArrowDown")
  })
  const navMs = await page.evaluate(() => window.__m.nav)

  const memEnd = await stats(page, true)
  const row = {
    variant, rows, cols,
    html_bytes: loads[0].html,
    join_bytes: loads[0].join,
    join_gz_bytes: loads[0].join_gz,
    interactive_ms: med(loads, "mounted_ms"),
    settled_ms: med(loads, "settled_ms"),
    edit_bytes: edit.bytes, edit_ms: edit.patch_ms, edit_frame_ms: edit.frame_ms,
    edit_handle_ms: edit.handle_ms, edit_refetch_ms: edit.refetch_ms, edit_save_ms: edit.save_ms,
    edit_script_ms: edit.script_ms, edit_layout_ms: edit.layout_ms, edit_style_ms: edit.style_ms,
    sort_bytes: med(sorts, "recv_bytes"), sort_ms: med(sorts, "patch_ms"), sort_frame_ms: med(sorts, "frame_ms"),
    sort_script_ms: med(sorts, "script_ms"), sort_layout_ms: med(sorts, "layout_ms"),
    page_script_ms: med(pages, "script_ms"), page_layout_ms: med(pages, "layout_ms"),
    page_bytes: med(pages, "recv_bytes"), page_ms: med(pages, "patch_ms"), page_frame_ms: med(pages, "frame_ms"),
    nav_frames_sent: nav.sent, nav_frames_received: nav.received, nav_ms: round(median(navMs), 2), nav_max_ms: round(Math.max(...navMs), 2),
    mem_load_kb: round(memLoad.memory / 1024, 0), mem_load_gc_kb: round(memLoad.after_gc.memory / 1024, 0),
    live_load_kb: round((memLoad.after_gc.live + memLoad.after_gc.binary) / 1024, 0),
    mem_end_kb: round(memEnd.memory / 1024, 0), mem_end_gc_kb: round(memEnd.after_gc.memory / 1024, 0),
    live_end_kb: round((memEnd.after_gc.live + memEnd.after_gc.binary) / 1024, 0),
    errors: errors.length
  }
  await page.context().close()
  if (errors.length) console.log("  !! page errors", errors)
  console.log(JSON.stringify(row))
  return row
}

// 100 parent rows x 10 columns; the first N rows open a nested table of 25 comments.
async function nested(variant, n) {
  await reset()
  const {page, frames, errors} = await open(browser)
  await goto(page, variant, 100, 10)
  const before = await stats(page, true)
  const opened = await act(page, frames, () => page.click(`#open-first-${n}`), 400)
  const grids = await page.evaluate(() => document.querySelectorAll("#g [data-grid]").length)
  const nestedRows = await page.evaluate(() => document.querySelectorAll("#g [data-grid] tr[data-pk]").length)
  const after = await stats(page, true)
  // edit a parent row that has an open nested table, a parent row without, and a nested cell
  const parentOpen = await edits(page, frames, 0, Math.min(EDITS, n))
  const parentClosed = await edits(page, frames, 60, EDITS)
  const inNested = await edits(page, frames, 0, EDITS, "body", "g-1-n")
  const end = await stats(page, true)
  const row = {
    variant, open: n, nested_grids: grids, nested_rows: nestedRows,
    open_bytes: opened.recv_bytes, open_frames: opened.received, open_ms: round(opened.patch_ms, 1), open_frame_ms: round(opened.frame_ms, 1),
    edit_parent_open_bytes: parentOpen.bytes, edit_parent_open_ms: parentOpen.patch_ms,
    edit_parent_open_server_ms: parentOpen.handle_ms,
    edit_parent_open_script_ms: parentOpen.script_ms, edit_parent_open_layout_ms: parentOpen.layout_ms,
    edit_parent_closed_bytes: parentClosed.bytes, edit_parent_closed_ms: parentClosed.patch_ms,
    edit_nested_bytes: inNested.bytes, edit_nested_ms: inNested.patch_ms,
    mem_before_gc_kb: round(before.after_gc.memory / 1024, 0),
    mem_open_kb: round(after.memory / 1024, 0), mem_open_gc_kb: round(after.after_gc.memory / 1024, 0),
    live_before_kb: round((before.after_gc.live + before.after_gc.binary) / 1024, 0),
    live_open_kb: round((after.after_gc.live + after.after_gc.binary) / 1024, 0),
    mem_end_gc_kb: round(end.after_gc.memory / 1024, 0),
    errors: errors.length
  }
  await page.context().close()
  if (errors.length) console.log("  !! page errors", errors)
  console.log(JSON.stringify(row))
  return row
}

if (what === "all" || what === "matrix")
  for (const rows of ROWS) for (const cols of COLS) for (const variant of VARIANTS) out.matrix.push(await matrix(variant, rows, cols))
if (what === "all" || what === "nested")
  for (const n of [10, 50]) for (const variant of VARIANTS) out.nested.push(await nested(variant, n))
await browser.close()

const previous = fs.existsSync(`results/${NAME}.json`) ? JSON.parse(fs.readFileSync(`results/${NAME}.json`)) : {}
const merged = {...previous, ...Object.fromEntries(Object.entries(out).filter(([, v]) => v.length))}
fs.writeFileSync(`results/${NAME}.json`, JSON.stringify(merged, null, 2))

// ---- markdown ---------------------------------------------------------------
const table = (rows, cols) =>
  [`| ${cols.map(c => c[0]).join(" | ")} |`, `| ${cols.map(() => "---").join(" | ")} |`,
    ...rows.map(r => `| ${cols.map(c => typeof c[1] === "function" ? c[1](r) : r[c[1]]).join(" | ")} |`)].join("\n")
const kb = b => round(b / 1024, 1)
const size = r => `${r.rows} x ${r.cols}`
let md = ""
if (merged.matrix) {
  const m = merged.matrix
  md += "### Initial render\n\n" + table(m, [["rows x cols", size], ["variant", "variant"], ["HTML KB", r => kb(r.html_bytes)], ["join frame KB", r => kb(r.join_bytes)], ["join gzip KB", r => kb(r.join_gz_bytes)], ["interactive ms", "interactive_ms"], ["settled ms", "settled_ms"]])
  md += "\n\n### One cell edit saved\n\n" + table(m, [["rows x cols", size], ["variant", "variant"], ["diff bytes", "edit_bytes"], ["round trip ms", "edit_ms"], ["to next frame ms", "edit_frame_ms"], ["server handle_event ms", "edit_handle_ms"], ["of which re-fetch ms", "edit_refetch_ms"], ["of which Ash update ms", "edit_save_ms"], ["browser script ms", "edit_script_ms"], ["browser layout ms", "edit_layout_ms"], ["browser style ms", "edit_style_ms"]])
  md += "\n\n### Sort click\n\n" + table(m, [["rows x cols", size], ["variant", "variant"], ["diff KB", r => kb(r.sort_bytes)], ["round trip ms", "sort_ms"], ["to next frame ms", "sort_frame_ms"], ["browser script ms", "sort_script_ms"], ["browser layout ms", "sort_layout_ms"]])
  md += "\n\n### Page change\n\n" + table(m, [["rows x cols", size], ["variant", "variant"], ["diff KB", r => kb(r.page_bytes)], ["round trip ms", "page_ms"], ["to next frame ms", "page_frame_ms"], ["browser script ms", "page_script_ms"], ["browser layout ms", "page_layout_ms"]])
  md += "\n\n### Arrow keys (20 presses)\n\n" + table(m, [["rows x cols", size], ["variant", "variant"], ["frames sent", "nav_frames_sent"], ["frames received", "nav_frames_received"], ["median ms", "nav_ms"], ["max ms", "nav_max_ms"]])
  md += "\n\n### LiveView process memory\n\n" + table(m, [["rows x cols", size], ["variant", "variant"], ["process memory after load KB", "mem_load_kb"], ["same after GC KB", "mem_load_gc_kb"], ["live data after GC KB", "live_load_kb"], ["process memory after edits, sorts, pages KB", "mem_end_kb"], ["same after GC KB", "mem_end_gc_kb"], ["live data after GC KB", "live_end_kb"]])
}
if (merged.nested) {
  md += "\n\n### Nested tables open (100 parent rows x 10 cols, 25 comments x 6 cols each)\n\n" + table(merged.nested, [["open", "open"], ["variant", "variant"], ["open-all diff KB", r => kb(r.open_bytes)], ["open-all ms", "open_ms"], ["edit parent (open row) bytes", "edit_parent_open_bytes"], ["ms", "edit_parent_open_ms"], ["server ms", "edit_parent_open_server_ms"], ["script ms", "edit_parent_open_script_ms"], ["layout ms", "edit_parent_open_layout_ms"], ["edit parent (closed row) bytes", "edit_parent_closed_bytes"], ["ms", "edit_parent_closed_ms"], ["edit nested cell bytes", "edit_nested_bytes"], ["ms", "edit_nested_ms"], ["process memory before, GC KB", "mem_before_gc_kb"], ["live before KB", "live_before_kb"], ["process memory open KB", "mem_open_kb"], ["same after GC KB", "mem_open_gc_kb"], ["live open KB", "live_open_kb"]])
}
fs.writeFileSync(`results/${NAME}.md`, md + "\n")
console.log("\n" + md)
