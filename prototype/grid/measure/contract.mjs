// THROWAWAY PROTOTYPE (#11). Walks the keyboard and editing contract in every
// variant and prints what held. Not a test suite: it exists to replace "it
// felt fine" with something that was actually run.
//
//   node contract.mjs              all variants
//   node contract.mjs --no-observer  hook relies on updated() only
import {launch, open, goto, reset, act, settle, focusCell, active, tabStops, poke, VARIANTS} from "./lib.mjs"

const noObserver = process.argv.includes("--no-observer")
const only = process.argv.find(a => VARIANTS.includes(a))
const browser = await launch()
const summary = {}

for (const variant of VARIANTS.filter(v => !only || v === only)) {
  const {page, frames, errors} = await open(browser, {noObserver})
  const results = []
  const check = (name, ok, detail = "") => {
    results.push({name, ok})
    console.log(`${ok ? "  ok  " : " FAIL "} ${variant.padEnd(10)} ${name}${detail ? "  -> " + detail : ""}`)
  }
  const key = k => page.keyboard.press(k)
  const cell = (r, col) => page.evaluate(([r, col]) => {
    const table = document.querySelector("#g > table")
    const th = table.rows[0].querySelector(`th[data-col="${col}"]`)
    const td = Array.from(table.rows).filter(tr => tr.dataset.pk)[r].cells[th.cellIndex]
    const v = td.querySelector("[data-v]")
    const box = td.querySelector("input[type=checkbox]")
    return {
      id: td.id,
      text: v ? v.textContent : td.querySelector("[role=alert]") ? "" : td.textContent.trim(),
      invalid: td.getAttribute("aria-invalid"),
      error: td.querySelector("[role=alert]")?.textContent ?? null,
      busy: td.getAttribute("aria-busy"),
      tabindex: td.getAttribute("tabindex"),
      checked: box ? box.checked : null,
      hasInput: !!td.querySelector("[data-editor]")
    }
  }, [r, col])
  const a = (fn, quiet) => act(page, frames, fn, quiet)

  await reset()
  await goto(page, variant, 25, 10)

  // ---- tab stops ---------------------------------------------------------
  check("one tabindex=0 in the grid after mount", (await tabStops(page)).length === 1, JSON.stringify(await tabStops(page)))
  await page.focus("text=A link before the grid")
  await key("Tab")
  const firstStop = await active(page)
  await key("Tab")
  const secondStop = await active(page)
  check("Tab enters the grid on one cell, the next Tab is outside the table",
    firstStop.tag === "TD" && secondStop.tag !== "TD" && secondStop.tag !== "TH", `${firstStop.id} then ${secondStop.tag} ${secondStop.text}`)

  // ---- navigation: no round trips ------------------------------------------
  await focusCell(page, 0, "title")
  let r = await a(async () => {
    await key("ArrowRight"); await key("ArrowDown"); await key("ArrowDown"); await key("ArrowLeft"); await key("ArrowUp")
  })
  let at = await active(page)
  check("arrow keys move one cell", at.id === (await cell(1, "title")).id, at.id)
  check("arrow keys send no frames", r.sent === 0 && r.received === 0, `sent ${r.sent} received ${r.received}`)
  await key("End"); const endCell = await active(page)
  await key("ArrowRight"); const afterEnd = await active(page)
  await key("Home"); const homeCell = await active(page)
  await key("ArrowLeft"); const afterHome = await active(page)
  check("Home/End go to the row ends and arrows do not wrap",
    endCell.id === (await cell(1, "starts_at")).id && afterEnd.id === endCell.id && homeCell.id.endsWith("-x") && afterHome.id === homeCell.id,
    `${endCell.id} ${afterEnd.id} ${homeCell.id} ${afterHome.id}`)
  await key("Control+End"); const corner2 = await active(page)
  await key("ArrowDown"); const below = await active(page)
  await key("Control+Home"); const corner1 = await active(page)
  check("Ctrl+End / Ctrl+Home go to the corners", corner2.id === (await cell(24, "starts_at")).id && below.id === corner2.id && corner1.id === "g-1-x", `${corner2.id} ${corner1.id}`)
  await key("PageDown"); const pd = await active(page)
  await key("PageUp"); const pu = await active(page)
  check("PageDown / PageUp move several rows", pd.id !== corner1.id && pd.id !== "g-2-x" && pu.id !== pd.id, `${pd.id} ${pu.id}`)
  await focusCell(page, 0, "title")
  r = await a(async () => { await key("Space") })
  check("Space does nothing (reserved)", r.sent === 0 && (await active(page)).id === (await cell(0, "title")).id && !(await cell(0, "title")).hasInput)

  // ---- editing: text -------------------------------------------------------
  const original = (await cell(0, "title")).text
  await key("Enter")
  at = await active(page)
  check("Enter opens an editor holding the cell's value", at.tag === "INPUT" && at.text === original, `${at.tag} "${at.text}"`)
  r = await a(async () => { await key("Enter") })
  check("an unchanged value calls nothing", r.sent === 0 && (await cell(0, "title")).text === original && (await active(page)).id === (await cell(0, "title")).id, `sent ${r.sent}`)

  await key("F2")
  await page.keyboard.type("thrown away")
  r = await a(async () => { await key("Escape") })
  check("F2 edits, Escape cancels and restores, nothing sent", r.sent === 0 && (await cell(0, "title")).text === original && (await active(page)).id === (await cell(0, "title")).id)

  await page.keyboard.type("Zed is")
  at = await active(page)
  check("a printable key starts editing with that character", at.tag === "INPUT" && at.text === "Zed is", `"${at.text}"`)
  r = await a(async () => { await key("Enter") })
  let c = await cell(0, "title")
  at = await active(page)
  check("Enter saves: one event, row replaced, focus stays on the cell",
    r.sent === 1 && c.text === "Zed is" && at.id === c.id && c.busy === null, `sent ${r.sent} text "${c.text}" focus ${at.id} busy ${c.busy}`)
  check("still one tabindex=0 after the save patch", (await tabStops(page)).length === 1 && (await tabStops(page))[0] === c.id, JSON.stringify(await tabStops(page)))
  summary[variant] = {edit_reply_bytes: r.recv_bytes}

  await key("Enter")
  await page.keyboard.type("Saved by leaving")
  const other = await cell(3, "assignee")
  r = await a(async () => { await page.click(`#${other.id}`) })
  at = await active(page)
  check("leaving the cell (click elsewhere) saves and focus follows the click",
    r.sent === 1 && (await cell(0, "title")).text === "Saved by leaving" && at.id === other.id, `sent ${r.sent} focus ${at.id}`)

  // ---- failed save ---------------------------------------------------------
  await focusCell(page, 0, "title")
  await key("Enter")
  await page.keyboard.type("ab")
  r = await a(async () => { await page.click(`#${other.id}`) })
  c = await cell(0, "title")
  at = await active(page)
  check("failed save: focus is not pulled back", at.id === other.id, at.id)
  check("failed save: cell keeps the typed value, aria-invalid, error shown in a role=alert",
    c.text === "ab" && c.invalid === "true" && !!c.error, `text "${c.text}" invalid ${c.invalid} error "${c.error}"`)
  await focusCell(page, 0, "title")
  await key("Enter")
  at = await active(page)
  const reopened = at.text
  await key("Escape")
  await settle(page)
  c = await cell(0, "title")
  check("going back: the editor reopens with the rejected value, Escape restores the saved one",
    reopened === "ab" && c.text === "Saved by leaving" && c.invalid === null, `reopened "${reopened}" now "${c.text}" invalid ${c.invalid}`)
  await key("Enter"); await page.keyboard.type("x"); await key("Enter"); await settle(page)
  c = await cell(0, "title")
  const stayed = (await active(page)).id === c.id
  await key("Escape"); await settle(page)
  const afterEsc = await cell(0, "title")
  check("failed save by Enter, then Escape on the cell (no editor) restores", stayed && c.invalid === "true" && afterEsc.text === "Saved by leaving" && afterEsc.invalid === null, `"${afterEsc.text}"`)

  // ---- other editors -------------------------------------------------------
  await focusCell(page, 0, "progress")
  await page.keyboard.type("150"); await key("Enter"); await settle(page)
  c = await cell(0, "progress")
  check("number: out of range is the action's error", c.invalid === "true", `"${c.error}"`)
  await key("Enter"); await page.keyboard.press("Control+a"); await page.keyboard.type("55"); await key("Enter"); await settle(page)
  c = await cell(0, "progress")
  check("number: a valid value saves and clears the error", c.text === "55" && c.invalid === null, c.text)

  await focusCell(page, 0, "done")
  const before = (await cell(0, "done")).checked
  r = await a(async () => { await key("Enter") })
  c = await cell(0, "done")
  check("checkbox: Enter toggles and saves at once", r.sent === 1 && c.checked === !before && (await active(page)).id === c.id, `sent ${r.sent} checked ${c.checked}`)
  r = await a(async () => { await page.click(`#${c.id} input`) })
  c = await cell(0, "done")
  check("checkbox: a click toggles, saves, focus ends on the cell", r.sent === 1 && c.checked === before && (await active(page)).id === c.id, `focus ${(await active(page)).id}`)

  await focusCell(page, 0, "status")
  await key("Enter")
  at = await active(page)
  r = await a(async () => { await page.selectOption(`#${(await cell(0, "status")).id} select`, "review") })
  c = await cell(0, "status")
  check("select: choosing saves at once (per-column action :set_status)", at.tag === "SELECT" && r.sent === 1 && c.text === "review" && (await active(page)).id === c.id, `${at.tag} "${c.text}"`)
  await key("Enter")
  await page.selectOption(`#${c.id} select`, "done"); await settle(page)
  c = await cell(0, "status")
  check("an error about ANOTHER field is shown on the edited cell", c.invalid === "true" && /progress/.test(c.error || ""), `"${c.error}"`)
  await key("Escape"); await settle(page)

  await focusCell(page, 0, "due_on")
  await key("Enter")
  at = await active(page)
  await page.fill(`#${(await cell(0, "due_on")).id} input`, "2027-01-02")
  await key("Enter"); await settle(page)
  check("date editor saves", at.tag === "INPUT" && (await cell(0, "due_on")).text === "2027-01-02", (await cell(0, "due_on")).text)

  await focusCell(page, 0, "starts_at")
  await key("Enter")
  await page.fill(`#${(await cell(0, "starts_at")).id} input`, "2027-01-02T10:30")
  await key("Enter"); await settle(page)
  c = await cell(0, "starts_at")
  check("datetime-local editor saves", c.text === "2027-01-02 10:30" && c.invalid === null, `"${c.text}" ${c.error ?? ""}`)

  await focusCell(page, 0, "price")
  await page.keyboard.type("-5"); await key("Enter"); await settle(page)
  c = await cell(0, "price")
  check("decimal through :reprice: the action's validation message", c.invalid === "true", `"${c.error}"`)
  await key("Enter"); await page.keyboard.press("Control+a"); await page.keyboard.type("200000"); await key("Enter"); await settle(page)
  c = await cell(0, "price")
  check("an error with NO field is shown on the edited cell", c.invalid === "true" && /approval/.test(c.error || ""), `"${c.error}"`)
  await key("Enter"); await page.keyboard.press("Control+a"); await page.keyboard.type("12.5"); await key("Enter"); await settle(page)
  c = await cell(0, "price")
  check("decimal: a valid value saves", c.text === "12.5" && c.invalid === null, c.text)

  await focusCell(page, 0, "id")
  r = await a(async () => { await key("Enter"); await page.keyboard.type("9") })
  check("a read-only cell does not open", !(await cell(0, "id")).hasInput && r.sent === 0)

  // ---- patches that do not come from the focused cell ----------------------
  await focusCell(page, 1, "title")
  const watched = await cell(1, "title")
  await poke(page, 1, "assignee", "poked-" + variant); await page.waitForTimeout(300); await settle(page)
  at = await active(page)
  check("a patch of the focused cell's row keeps focus and tabindex",
    at.id === watched.id && (await tabStops(page)).join() === watched.id && (await cell(1, "assignee")).text === "poked-" + variant,
    `focus ${at.id} stops ${JSON.stringify(await tabStops(page))}`)

  await key("Enter"); await page.keyboard.press("Control+a"); await page.keyboard.type("still typing")
  await poke(page, 5, "assignee", "other-row"); await page.waitForTimeout(300)
  at = await active(page)
  const survivedOther = at.tag === "INPUT" && at.text === "still typing" && (await cell(5, "assignee")).text === "other-row"
  await poke(page, 1, "assignee", "same-row"); await page.waitForTimeout(300)
  at = await active(page)
  const survivedSame = at.tag === "INPUT" && at.text === "still typing" && (await cell(1, "assignee")).text === "same-row"
  check("an open editor's typed value survives a patch of another row", survivedOther, `${at.tag} "${at.text}"`)
  check("an open editor's typed value survives a patch of its own row", survivedSame, `${at.tag} "${at.text}"`)
  await key("Enter"); await settle(page)
  c = await cell(1, "title")
  check("...and then saves normally", c.text === "still typing" && (await active(page)).id === c.id && (await cell(1, "assignee")).text === "same-row", `"${c.text}"`)

  // ---- a slow save that returns while the person types in the SAME row -------
  // (with streams the whole row is re-inserted, so this is the case to fear)
  await page.evaluate(() => window.liveSocket.enableLatencySim(400))
  await focusCell(page, 2, "title")
  await key("Enter"); await page.keyboard.press("Control+a"); await page.keyboard.type("Slow save")
  const sameRow = await cell(2, "assignee")
  await page.click(`#${sameRow.id}`)
  await key("Enter"); await page.keyboard.press("Control+a"); await page.keyboard.type("typed during")
  const busyMeanwhile = (await cell(2, "title")).busy
  await page.waitForTimeout(900)
  at = await active(page)
  c = await cell(2, "title")
  check("slow save shows aria-busy until it returns", busyMeanwhile === "true" && c.busy === null, `during ${busyMeanwhile} after ${c.busy}`)
  check("a save returning while typing in another cell of the same row keeps that editor, its value and focus",
    at.tag === "INPUT" && at.text === "typed during" && c.text === "Slow save", `${at.tag} "${at.text}" title "${c.text}"`)
  await key("Enter"); await page.waitForTimeout(900)
  c = await cell(2, "assignee")
  check("...and that second edit then saves", c.text === "typed during" && (await cell(2, "title")).text === "Slow save" && (await active(page)).id === c.id, `"${c.text}"`)

  await focusCell(page, 2, "title")
  await key("Enter"); await page.keyboard.press("Control+a"); await page.keyboard.type("ab")
  await page.click(`#${sameRow.id}`)
  await key("Enter"); await page.keyboard.press("Control+a"); await page.keyboard.type("second")
  await page.waitForTimeout(900)
  at = await active(page)
  c = await cell(2, "title")
  check("a FAILED save returning while typing in the same row: error shown, editor and focus untouched",
    at.tag === "INPUT" && at.text === "second" && c.invalid === "true" && c.text === "ab", `${at.tag} "${at.text}" invalid ${c.invalid}`)
  await key("Enter"); await page.waitForTimeout(900)
  c = await cell(2, "title")
  check("...the second edit saves and the first cell's error survives that row refresh",
    (await cell(2, "assignee")).text === "second" && c.invalid === "true" && c.text === "ab", `assignee "${(await cell(2, "assignee")).text}" title invalid ${c.invalid}`)
  await focusCell(page, 2, "title"); await key("Escape"); await page.waitForTimeout(900)
  check("Escape on it restores the saved value", (await cell(2, "title")).text === "Slow save" && (await cell(2, "title")).invalid === null, (await cell(2, "title")).text)
  await page.evaluate(() => window.liveSocket.disableLatencySim())

  // ---- sort ----------------------------------------------------------------
  await focusCell(page, 0, "title")
  await key("ArrowUp")
  const header = await active(page)
  const sortState = () => page.evaluate(() => document.querySelector('#g th[data-col="title"]').getAttribute("aria-sort"))
  const states = []
  for (let i = 0; i < 3; i++) { r = await a(async () => { await key("Enter") }); states.push(await sortState()) }
  at = await active(page)
  check("Enter on a header cycles ascending, descending, none", states.join() === "ascending,descending,none", states.join())
  check("focus stays on the header after the sort patch", at.id === header.id && (await tabStops(page)).join() === header.id, `${at.id} ${JSON.stringify(await tabStops(page))}`)
  await a(async () => { await page.click('#g th[data-col="progress"]') })
  const firstProgress = Number((await cell(0, "progress")).text)
  const secondProgress = Number((await cell(5, "progress")).text)
  check("click on a header sorts", firstProgress <= secondProgress && (await page.evaluate(() => document.querySelector('#g th[data-col="progress"]').getAttribute("aria-sort"))) === "ascending", `${firstProgress} <= ${secondProgress}`)
  await a(async () => { await page.click('#g th[data-col="progress"]') })
  await a(async () => { await page.click('#g th[data-col="progress"]') })

  // ---- row expansion and the nested table ----------------------------------
  await focusCell(page, 0, "id")
  await key("ArrowLeft")
  const expander = await active(page)
  r = await a(async () => { await key("ArrowRight") })
  const nestedInfo = () => page.evaluate(() => {
    const n = document.querySelector("#g [data-grid]")
    return n ? {id: n.id, rows: n.querySelectorAll("tr[data-pk]").length} : null
  })
  let nested = await nestedInfo()
  at = await active(page)
  check("Right Arrow on the expander opens the nested table, focus stays", !!nested && nested.rows === 25 && at.id === expander.id, `${JSON.stringify(nested)} focus ${at.id}`)
  check("still exactly one tabindex=0 with a nested grid open", (await tabStops(page)).length === 1, JSON.stringify(await tabStops(page)))
  await key("ArrowRight")
  check("Right Arrow on an open expander moves to the next cell", (await active(page)).id === (await cell(0, "id")).id)
  await key("ArrowLeft")
  await key("ArrowDown")
  const detail = await active(page)
  await key("Enter")
  const inNested = await active(page)
  check("Down reaches the detail cell, Enter moves into the nested grid", detail.id.endsWith("-dc") && inNested.id.startsWith(nested.id + "-"), `${detail.id} -> ${inNested.id}`)
  await key("ArrowRight"); await key("ArrowRight"); await key("ArrowDown")
  const nestedCell = await active(page)
  r = await a(async () => { await key("ArrowDown"); await key("ArrowUp") })
  check("arrows inside the nested grid stay inside and send nothing", nestedCell.id.startsWith(nested.id + "-") && (await active(page)).id === nestedCell.id && r.sent === 0, nestedCell.id)
  check("one tabindex=0 in the whole tree while focus is nested", (await tabStops(page)).join() === nestedCell.id, JSON.stringify(await tabStops(page)))
  await page.keyboard.type("Nested edit")
  r = await a(async () => { await key("Enter") })
  at = await active(page)
  check("editing inside the nested grid saves and keeps focus", r.sent === 1 && at.id === nestedCell.id && at.text === "Nested edit", `sent ${r.sent} ${at.id} "${at.text}"`)
  summary[variant].nested_edit_reply_bytes = r.recv_bytes
  await key("Tab")
  at = await active(page)
  check("Tab from inside a nested grid leaves the whole grid", at.tag !== "TD" && at.tag !== "TH", `${at.tag} "${at.text.slice(0, 30)}"`)
  await key("Shift+Tab")
  check("Shift+Tab comes back to the nested cell", (await active(page)).id === nestedCell.id, (await active(page)).id)
  await key("Escape")
  check("Escape in the nested grid returns to the parent's detail cell", (await active(page)).id === detail.id, (await active(page)).id)
  await key("ArrowUp")
  await key("Home")
  r = await a(async () => { await key("ArrowLeft") })
  check("Left Arrow on the expander closes the nested table, focus stays", (await nestedInfo()) === null && (await active(page)).id === expander.id, (await active(page)).id)

  // ---- page change ---------------------------------------------------------
  await focusCell(page, 2, "title")
  r = await a(async () => { await page.click('#g [data-pager="next"]') })
  const stops = await tabStops(page)
  check("page change: new rows, still one tabindex=0", (await cell(0, "id")).text === "26" && stops.length === 1, `first id ${(await cell(0, "id")).text} stops ${JSON.stringify(stops)}`)

  const counts = await page.evaluate(() => document.getElementById("g")._ashHook.counts)
  summary[variant].hook = counts
  // what the hook did just before each time it had to put focus back
  summary[variant].focus_restored_after = await page.evaluate(() => {
    const log = window.__m.log
    return log.map((e, i) => e === "focus-restored" ? log.slice(Math.max(0, i - 3), i).join(" > ") : null).filter(Boolean)
  })
  summary[variant].failed = results.filter(x => !x.ok).map(x => x.name)
  check("no console or page errors", errors.length === 0, errors.join(" | "))
  await page.close()
}
await browser.close()
console.log(`\nSUMMARY (observer ${noObserver ? "OFF" : "on"})\n` + JSON.stringify(summary, null, 2))
