// The clips and the picture of the README, recorded by scripts/record-gifs.sh
// against a demo of its own (GIFS_URL). Not a test, and not part of `npm
// test` (which runs `*.spec.ts`): each clip is one browser context with a
// video, written to VIDEOS_DIR as <name>.webm; the picture goes to SHOT.
// CLIPS (names, separated by spaces) records only those clips.
import { readFile, rename } from "node:fs/promises"
import path from "node:path"
import { chromium } from "@playwright/test"

const BASE = process.env.GIFS_URL ?? "http://127.0.0.1:4490"
const VIDEOS = process.env.VIDEOS_DIR ?? "test-results/videos"
const SHOT = process.env.SHOT
const ONLY = (process.env.CLIPS ?? "").split(/\s+/).filter(Boolean)
const SIZE = { width: 1440, height: 810 }

const browser = await chromium.launch()
// the clips that failed: the others are still recorded, and the run fails at the end
const failed = []

// Ada Admin's session, made once without a video, so that each clip starts on
// its page as her
const adminState = await (async () => {
  const context = await browser.newContext({ baseURL: BASE })
  const page = await context.newPage()
  await page.goto("/")
  await connected(page)
  await actAs(page, "Ada Admin · admin · acme", "You are now Ada Admin (admin).")
  const state = await context.storageState()
  await context.close()
  return state
})()

/** One clip: a fresh context, its video saved as `name`.webm. */
async function clip(name, play) {
  if (ONLY.length > 0 && !ONLY.includes(name)) return
  const context = await browser.newContext({
    baseURL: BASE,
    viewport: SIZE,
    timezoneId: "UTC",
    storageState: adminState,
    recordVideo: { dir: VIDEOS, size: SIZE },
  })
  const page = await context.newPage()
  page.on("pageerror", (error) => console.error(`${name}: page error:`, error.message))
  page.on("console", (message) => {
    if (message.type() === "error") console.error(`${name}: console:`, message.text())
  })
  try {
    await play(page)
  } catch (error) {
    failed.push(name)
    console.error(`The clip ${name} failed:`, error)
  } finally {
    const video = page.video()
    await context.close()
    await rename(await video.path(), path.join(VIDEOS, `${name}.webm`))
  }
}

const pause = (page, ms) => page.waitForTimeout(ms)

/** The demo has no login: a person is chosen in "Acting as". */
async function actAs(page, label, flash) {
  await page.getByLabel("Acting as").selectOption({ label })
  await page.getByText(flash).waitFor()
}

async function connected(page) {
  await page.locator(".phx-connected").first().waitFor({ state: "attached" })
  await page.locator("body > canvas").waitFor({ state: "hidden" }).catch(() => {})
}

/** Opens a page, as the session of its context. */
async function open(page, url) {
  await page.goto(url)
  await connected(page)
  await page.mouse.move(SIZE.width - 10, 70)
}

/** Opens the first row, the task with the most comments, into its comments. */
async function openComments(page) {
  const expander = page.locator("[data-expander] button").first()
  await point(page, expander)
  await pause(page, 300)
  await expander.click()
  const line = page.locator("[data-detail]").first().getByRole("button", { name: /^Comments/ }).first()
  await line.waitFor()
  await pause(page, 900)
  await point(page, line)
  await line.click()
  await page.getByText("Open in full view").first().waitFor()
}

function titleCell(page, row) {
  return page.locator('[role=row] > [role=rowheader][id$="-c-title"]').nth(row)
}

/** Moves the mouse to the middle of a locator, slowly, so that it is seen. */
async function point(page, locator) {
  await locator.scrollIntoViewIfNeeded()
  const box = await locator.boundingBox()
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2, { steps: 15 })
}

/** Points at a locator, then clicks it. */
async function pointAndClick(page, locator, wait = 250) {
  await point(page, locator)
  await pause(page, wait)
  await locator.click()
}

const byId = (page, id) => page.locator(`[id="${id}"]`)

/** The key of the row of a table at a position of its page, counted from 1. */
async function rowKey(page, table, position) {
  const prefix = `${table}-row-`
  const rows = byId(page, `${table}-table`).locator(":scope > [role=rowgroup]:not([data-detail])")
  await rows.nth(position - 1).waitFor()
  const id = await rows.nth(position - 1).getAttribute("id")
  return id.slice(prefix.length)
}

const cellOf = (page, table, key, column) => byId(page, `${table}-row-${key}-c-${column}`)

/** Types over what a cell's editor holds, and saves it with Enter. */
async function retypeCell(page, cell, text) {
  await point(page, cell)
  await pause(page, 300)
  await cell.dblclick()
  const editor = cell.locator("textarea, input")
  await editor.waitFor()
  await pause(page, 400)
  await editor.press("ControlOrMeta+a")
  await editor.pressSequentially(text, { delay: 45 })
  await pause(page, 400)
  await editor.press("Enter")
  await editor.waitFor({ state: "detached" })
}

/** Answers the table's question ("Move this task …?") with Confirm. */
async function confirm(page, table) {
  const button = byId(page, `${table}-dialog`).getByRole("button", { name: "Confirm" })
  await button.waitFor()
  await pause(page, 600)
  await pointAndClick(page, button)
}

try {
  // (a) a title edited in place
  await clip("edit-cell", async (page) => {
    await open(page, "/tasks")
    const cell = titleCell(page, 1)
    await pause(page, 300)
    await point(page, cell)
    await pause(page, 400)
    await cell.dblclick()
    const editor = cell.locator("textarea, input")
    await editor.waitFor()
    await pause(page, 500)
    await editor.press("ControlOrMeta+a")
    await editor.pressSequentially("Ship the onboarding flow by Friday", { delay: 45 })
    await pause(page, 500)
    await editor.press("Enter")
    await editor.waitFor({ state: "detached" })
    await pause(page, 2500)
  })

  // (b) a row opened into its comments, as a nested table
  await clip("nested-table", async (page) => {
    await open(page, "/tasks?task[sort]=-comment_count")
    await pause(page, 800)
    await openComments(page)
    await page.mouse.move(SIZE.width - 10, 70, { steps: 10 })
    await pause(page, 4000)
  })

  // (c) another person: columns and buttons change, on the four columns of
  // the board, which fit on the screen
  await clip("acting-as", async (page) => {
    await open(page, "/tasks/board")
    await pause(page, 2500)
    await point(page, page.getByLabel("Acting as"))
    await pause(page, 400)
    await actAs(page, "Vera Viewer · viewer · acme", "You are now Vera Viewer (viewer).")
    await connected(page)
    await pause(page, 4500)
  })

  // (d) a reference cell: another project, chosen from the projects' own table
  await clip("picker", async (page) => {
    await open(page, "/tasks")
    const key = await rowKey(page, "task", 1)
    const cell = cellOf(page, "task", key, "project")
    await pause(page, 300)
    await point(page, cell)
    await pause(page, 400)
    await cell.click()
    await pause(page, 300)
    await page.keyboard.press("Enter")
    const picker = byId(page, "task-picker")
    await picker.waitFor()
    const radios = byId(page, "task-pick-project-table").locator("input[type=radio]")
    await radios.first().waitFor()
    await pause(page, 1200)
    // the first project that is not the task's now
    const count = await radios.count()
    let other = radios.first()
    for (let i = 0; i < count; i++) {
      if (!(await radios.nth(i).isChecked())) {
        other = radios.nth(i)
        break
      }
    }
    await pointAndClick(page, other, 400)
    await pause(page, 600)
    await pointAndClick(page, byId(page, "task-picker-choose"), 400)
    await confirm(page, "task")
    await picker.waitFor({ state: "detached" })
    await page.mouse.move(SIZE.width - 10, 70, { steps: 10 })
    await pause(page, 2500)
  })

  // (e) Ash's validation, at the cell: done with a progress under 100
  await clip("validation", async (page) => {
    await open(page, "/tasks")
    // the second row: a task still to do, with a progress of 5
    const key = await rowKey(page, "task", 2)
    const cell = cellOf(page, "task", key, "status")
    await pause(page, 300)
    await point(page, cell)
    await pause(page, 400)
    await cell.dblclick()
    const editor = cell.locator("select")
    await editor.waitFor()
    await pause(page, 600)
    await editor.selectOption({ label: "Done" })
    await confirm(page, "task")
    await cell.locator(":scope > [id$='-error']").waitFor()
    await page.mouse.move(SIZE.width - 10, 70, { steps: 10 })
    await pause(page, 3000)
    await cell.focus()
    await page.keyboard.press("Escape")
    await pause(page, 2000)
  })

  // (f) the action panel: a row action with an input (Reassign, its reason).
  // (New task would need a project chosen in the picker: the picker clip.)
  await clip("action-panel", async (page) => {
    await open(page, "/tasks")
    await pause(page, 600)
    const key = await rowKey(page, "task", 2)
    await pointAndClick(page, byId(page, `task-row-${key}-a-reassign`), 500)
    const reason = byId(page, "task-panel-f-reason")
    await reason.waitFor()
    await pause(page, 800)
    await reason.pressSequentially("Kim is away next week", { delay: 50 })
    await pause(page, 800)
    await pointAndClick(page, byId(page, "task-panel-submit"), 500)
    await byId(page, "task-panel").waitFor({ state: "detached" })
    await page.mouse.move(SIZE.width - 10, 70, { steps: 10 })
    await pause(page, 2500)
  })

  // (g) live updates: two tables of the comments on /named
  await clip("live-updates", async (page) => {
    await open(page, "/named?comment[per]=10")
    await page.evaluate(() =>
      document.getElementById("named-default-section").scrollIntoView({ block: "start" }),
    )
    await pause(page, 1200)
    const key = await rowKey(page, "comment", 1)
    await retypeCell(page, cellOf(page, "comment", key, "body"), "Looks good, merging today")
    await pause(page, 600)
    // the compact table's first rows are in view below the first table's
    const theirs = cellOf(page, "comment_compact", key, "body")
    await point(page, theirs)
    await pause(page, 2200)
  })

  // (h) the React kit: an edit, a nested table, the link back to HEEx
  await clip("react-kit", async (page) => {
    await open(page, "/react/tasks")
    await page.locator("#task-grid-island #task-grid").waitFor()
    await pause(page, 300)
    const key = await rowKey(page, "task", 1)
    await retypeCell(page, cellOf(page, "task", key, "title"), "Drawn by React")
    await pause(page, 300)
    await pointAndClick(page, byId(page, `task-row-${key}-e`).locator("button"), 300)
    const line = byId(page, `task-row-${key}-l-comments-b`)
    await line.waitFor()
    await pause(page, 300)
    await pointAndClick(page, line, 300)
    await byId(page, `task-row-${key}-t-comments-table`).waitFor()
    await pause(page, 1500)
    const heex = page.getByRole("link", { name: "The same table in HEEx" })
    await page.evaluate(() => window.scrollTo({ top: 0, behavior: "smooth" }))
    await pause(page, 300)
    await pointAndClick(page, heex, 300)
    await page.waitForURL(/\/tasks(\?|$)/)
    await connected(page)
    await pause(page, 1800)
  })

  // (i) the sprint planner: ticked tasks fill the cards above
  await clip("planner", async (page) => {
    await open(page, "/tasks/planner")
    await pause(page, 1000)
    for (const position of [1, 3, 4]) {
      const key = await rowKey(page, "task", position)
      await pointAndClick(page, byId(page, `task-row-${key}-s`).locator("input[type=checkbox]"), 200)
      await pause(page, 700)
    }
    const key = await rowKey(page, "task", 3)
    await retypeCell(page, cellOf(page, "task", key, "estimate_hours"), "6")
    await pause(page, 600)
    await page.mouse.move(SIZE.width / 2, 200, { steps: 15 })
    await pause(page, 3000)
  })

  // (j) the selection exported as CSV, a file the browser saves
  await clip("export-csv", async (page) => {
    await open(page, "/tasks")
    await pause(page, 600)
    for (const position of [1, 2, 3]) {
      const key = await rowKey(page, "task", position)
      await pointAndClick(page, byId(page, `task-row-${key}-s`).locator("input[type=checkbox]"), 200)
      await pause(page, 250)
    }
    await pointAndClick(page, byId(page, "task-bulk-more-button"), 300)
    const exportButton = byId(page, "task-bulk-export_csv")
    await exportButton.waitFor()
    await pause(page, 600)
    const saved = page.waitForEvent("download")
    await pointAndClick(page, exportButton, 300)
    const download = await saved
    await byId(page, "task-result").waitFor()
    await page.mouse.move(SIZE.width - 10, 70, { steps: 10 })
    await pause(page, 1200)
    // headless Chromium draws no download bar: the file as it was saved
    const csv = await readFile(await download.path(), "utf8")
    const lines = csv.split("\r\n").filter((line) => line !== "")
    await page.setContent(
      `<body style="margin:0;padding:24px;font:15px/1.5 ui-monospace,monospace;background:#fff;color:#111">
         <div style="font:600 18px system-ui,sans-serif;margin-bottom:12px">Downloads / ${download.suggestedFilename()}</div>
         <pre style="margin:0;white-space:pre">${lines.slice(0, 4).join("\n").replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" })[c])}</pre>
       </body>`,
    )
    await pause(page, 2500)
  })

  // the picture at the top of the README
  if (SHOT) {
    const context = await browser.newContext({
      baseURL: BASE,
      viewport: SIZE,
      timezoneId: "UTC",
      storageState: adminState,
    })
    const page = await context.newPage()
    await open(page, "/tasks?task[sort]=-comment_count")
    await openComments(page)
    await page.mouse.move(SIZE.width - 10, 70)
    await pause(page, 500)
    await page.screenshot({ path: SHOT })
    await context.close()
  }
} finally {
  await browser.close()
}

if (failed.length > 0) {
  console.error(`Failed: ${failed.join(", ")}`)
  process.exit(1)
}
