import type { Page } from "@playwright/test"
import { SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { Table } from "./support/table"

// Tables attached to a LiveView of the page's own (`AshDataTable.attach/4`):
// /e2e/attached. The labels with their import keep their state in
// the URL, and nest their tasks, and under a task its labels; the tasks keep
// their state themselves. No live component draws them: their events go
// to the LiveView, and its hooks hand them to the tables. Beside them the
// page has a stream and buttons of its own.
//
// Every test fails on an error in the console (support/fixtures.ts), which
// is how a portal without its target, or an event the page does not know,
// shows. As the admin; the tests change the data.

const FIRST = SEED.task.first
const PATH = "/e2e/attached"

function csv(name: string, text: string) {
  return { name, mimeType: "text/csv", buffer: Buffer.from(text, "utf8") }
}

const params = (page: Page) => Object.fromEntries(new URL(page.url()).searchParams)

/**
 * How many nested tables the page shows through portals, by the table's own
 * marker of each (`data-ash-data-table-portal`, which names the cell it goes
 * into), and how many of them are not in that cell.
 */
async function portals(page: Page): Promise<{ portals: number; loose: number }> {
  return page.evaluate(() => {
    const marked = Array.from(document.querySelectorAll<HTMLElement>("[data-ash-data-table-portal]"))
    return {
      portals: marked.length,
      loose: marked.filter(
        (marker) => marker.closest("[role=gridcell][data-nested]")?.id !== marker.dataset.ashDataTablePortal,
      ).length,
    }
  })
}

async function opened(page: Page): Promise<{ labels: Table; tasks: Table }> {
  const labels = new Table(page, "label", PATH)
  await labels.open()
  const tasks = new Table(page, "task", PATH)
  await tasks.ready()
  return { labels, tasks }
}

test("the page's own stream and button work beside the tables", async ({ page }) => {
  const { labels, tasks } = await opened(page)
  const before = await tasks.rowKeys()

  await page.locator("#note").click()
  await page.locator("#note").click()
  await expect(page.locator("#notes > li")).toHaveText(["Note 1", "Note 2"])

  expect(await tasks.rowKeys()).toEqual(before)
  await expect(labels.rows).not.toHaveCount(0)
})

test("sorting a table that keeps its state itself leaves the URL alone", async ({ page }) => {
  const { tasks } = await opened(page)

  await tasks.reads(() => tasks.header("title").click())
  await expect(tasks.header("title")).toHaveAttribute("aria-sort", "ascending")
  expect(params(page)).toEqual({})
})

test("a table with its state in the URL keeps it there, and the back button takes it back", async ({ page }) => {
  const { labels } = await opened(page)
  const all = await labels.columnTexts("name")

  await labels.filterCell("name").focus()
  await labels.press("Enter")
  await page.keyboard.type("bu")
  await labels.reads(() => labels.press("Enter"))
  await expect(labels.columnCells("name")).toHaveText(["bug"])
  expect(Object.keys(params(page)).every((name) => name.startsWith("label[f]"))).toBe(true)
  expect(Object.values(params(page))).toContain("bu")

  await labels.reads(() => page.goBack())
  expect(params(page)).toEqual({})
  await expect(labels.columnCells("name")).toHaveText(all)

  await labels.reads(() => page.goForward())
  await expect(labels.columnCells("name")).toHaveText(["bug"])

  await page.reload()
  await labels.ready()
  await expect(labels.columnCells("name")).toHaveText(["bug"])
  await expect(labels.filterValue("name")).toHaveValue("bu")
})

test("a cell is saved", async ({ page }) => {
  const { tasks } = await opened(page)
  const cell = tasks.cell(FIRST, "title")

  await cell.focus()
  await tasks.press("Enter")
  await expect(tasks.editor(cell)).toBeFocused()
  await tasks.retype("Saved on an attached table")
  await tasks.saves(cell, () => tasks.press("Enter"))
  await expect(cell).toHaveText("Saved on an attached table")
})

test("a nested table two levels deep, each in the row of the one above it", async ({ page }) => {
  const { labels } = await opened(page)
  const [label] = await labels.rowKeys()
  const tasks = await labels.openLine(label, "tasks")
  const [task] = await tasks.rowKeys()
  const nested = await tasks.openLine(task, "labels")

  await expect(nested.rows).not.toHaveCount(0)
  expect(await portals(page)).toEqual({ portals: 2, loose: 0 })

  // and back up
  await labels.line(label, "tasks").click()
  await expect(tasks.root).toHaveCount(0)
  await expect(nested.root).toHaveCount(0)
  expect(await portals(page)).toEqual({ portals: 0, loose: 0 })
})

test("the picker of a reference cell opens with its table, and closes", async ({ page }) => {
  const { tasks } = await opened(page)

  await tasks.cell(FIRST, "assignee").focus()
  await tasks.press("Enter")
  await expect(tasks.picker).toBeVisible()
  const people = tasks.pickerTable("assignee")
  await people.ready()
  await expect(people.rows).not.toHaveCount(0)

  await tasks.pickerCancel.click()
  await expect(tasks.picker).toHaveCount(0)
  await expect(people.root).toHaveCount(0)
  await expect(tasks.cell(FIRST, "assignee")).toBeFocused()
})

test("a file is sent from the panel of the top table and from that of a nested table", async ({ page }) => {
  const { labels } = await opened(page)
  // a label with tasks: the import puts a new one at the top
  const [label] = await labels.rowKeys()

  await labels.tableAction("import").click()
  await expect(labels.panel).toBeVisible()
  await labels.panel.locator('input[type="file"]').setInputFiles(csv("top.csv", "alpha\n"))
  await labels.panelSettled()
  await labels.panelSubmit.click()
  await expect(labels.panel).toHaveCount(0)
  await expect(labels.result).toHaveText("Import: 1")

  const tasks = await labels.openLine(label, "tasks")
  const [task] = await tasks.rowKeys()
  const nested = await tasks.openLine(task, "labels")
  await tasks.lineAction(task, "labels", "import").click()
  await expect(nested.panel).toBeVisible()
  await nested.panel.locator('input[type="file"]').setInputFiles(csv("nested.csv", "beta\n"))
  await nested.panelSettled()
  await nested.panelSubmit.click()
  await expect(nested.panel).toHaveCount(0)
  await expect(nested.result).toHaveText("Import: 1")
})

test("attached again as another person, the tables under the rows close and the rows are read again", async ({
  page,
}) => {
  const { tasks } = await opened(page)
  const comments = await tasks.openLine(FIRST, "comments")
  await expect(tasks.lineCreate(FIRST, "comments")).toBeVisible()

  await tasks.reads(() => page.locator("#become").click())
  await expect(comments.root).toHaveCount(0)
  await expect(tasks.expander(FIRST)).toHaveAttribute("aria-expanded", "false")
  expect(await portals(page)).toEqual({ portals: 0, loose: 0 })

  // opened again, it is the viewer's: they may write no comment
  const again = await tasks.openLine(FIRST, "comments")
  await expect(again.rows).not.toHaveCount(0)
  await expect(tasks.lineCreate(FIRST, "comments")).toHaveCount(0)
})

test("detached with a nested table open, the table goes with what it shows, and can be attached again", async ({
  page,
}) => {
  const { labels, tasks } = await opened(page)
  const comments = await tasks.openLine(FIRST, "comments")
  await expect(comments.rows).not.toHaveCount(0)

  await page.locator("#detach").click()
  await expect(tasks.root).toHaveCount(0)
  await expect(comments.root).toHaveCount(0)
  expect(await portals(page)).toEqual({ portals: 0, loose: 0 })
  await expect(labels.rows).not.toHaveCount(0)

  await page.locator("#again").click()
  await tasks.ready()
  await expect(tasks.row(FIRST)).toHaveCount(1)
  const reopened = await tasks.openLine(FIRST, "comments")
  await expect(reopened.rows).not.toHaveCount(0)
})
