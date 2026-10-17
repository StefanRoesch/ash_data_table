import type { Page } from "@playwright/test"
import { expectNoAxeViolations } from "./support/a11y"
import { MAPS, SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { switchLocale } from "./support/locale"
import { Table, columnRules, ownedSheets } from "./support/table"
import { params } from "./support/url"

// A person hides columns of a table and shows them again: "Columns" above
// the grid opens a list with a box per column. Hiding is the browser's
// alone: the column is still read and still in the page, nothing is sent,
// nothing is in the URL, and a page that is loaded again shows every column.
// /tasks as the admin: the boxes, the expanders, "Title" (the label, which
// stays), 21 columns that can be hidden, and the actions.

const FIRST = SEED.task.first
const SECOND = SEED.task.second

/** The columns of /tasks that can be hidden, in order. */
const HIDEABLE = [
  "status",
  "priority",
  "progress",
  "estimate_hours",
  "billable?",
  "due_on",
  "completed_at",
  "overdue?",
  "comment_count",
  "headline",
  "due_within?",
  "due_within",
  "external_ref",
  "description",
  "tags",
  "checks",
  "recurrence",
  "inserted_at",
  "project",
  "assignee",
  "reporter",
]

function specimensOf(page: Page): Table {
  return new Table(page, "specimen", "/specimens")
}

/**
 * Uses the box of a column as a script does: the box changes and says so,
 * and focus stays where it is. A person's click moves focus to the box in
 * most browsers, and in some it does not.
 */
async function toggleInPlace(table: Table, column: string): Promise<void> {
  await table.columnBox(column).evaluate((box: HTMLInputElement) => box.click())
}

/** How wide the table is, and how wide the cells of its header row that are shown are together. */
async function layout(table: Table): Promise<{ table: number; cells: number }> {
  return table.grid.evaluate((node) => {
    const grid = node as HTMLTableElement
    const cells = Array.from(grid.tHead!.rows[0].cells).filter((cell) => cell.getClientRects().length > 0)
    return {
      table: grid.getBoundingClientRect().width,
      cells: cells.reduce((sum, cell) => sum + cell.getBoundingClientRect().width, 0),
    }
  })
}

test.describe("the button and its list", () => {
  test.beforeEach(async ({ tasks }) => {
    await tasks.open()
  })

  test("\"Columns\" opens a list with a box per column; a box hides its column and shows it again", async ({
    page,
    tasks,
    pushed,
  }) => {
    await pushed.clear()
    await expect(tasks.columnsButton).toHaveText("Columns")
    // the list is the browser's popover, which the button opens: the browser
    // says whether it is open, and what the button controls
    await expect(tasks.columnsButton).toHaveAttribute("popovertarget", "task-columns")
    await expect(tasks.columnsList).toHaveAttribute("popover", "auto")
    await expect(tasks.columnsList).toBeHidden()
    expect(await tasks.columnsOpen()).toBe(false)

    await tasks.columnsButton.click()
    await expect(tasks.columnsList).toBeVisible()
    expect(await tasks.columnsOpen()).toBe(true)
    await expect(page.getByRole("group", { name: "Columns" })).toBeVisible()
    await expect(page.getByRole("checkbox", { name: "State", exact: true })).toBeChecked()
    for (const column of HIDEABLE) await expect(tasks.columnBox(column)).toBeChecked()

    // under its button, inside the window
    const button = (await tasks.columnsButton.boundingBox())!
    const list = (await tasks.columnsList.boundingBox())!
    expect(list.y).toBeGreaterThanOrEqual(button.y + button.height)
    expect(list.y).toBeLessThan(button.y + button.height + 8)
    expect(list.x + list.width).toBeLessThanOrEqual(page.viewportSize()!.width)

    const colcount = await tasks.grid.getAttribute("aria-colcount")
    const colindex = await tasks.cell(FIRST, "priority").getAttribute("aria-colindex")
    const before = await tasks.columns()

    await tasks.columnBox("status").uncheck()
    await expect(tasks.header("status")).toBeHidden()
    await expect(tasks.filterCell("status")).toBeHidden()
    await expect(tasks.cell(FIRST, "status")).toBeHidden()
    await expect(tasks.cell(SECOND, "status")).toBeHidden()
    await expect(tasks.header("priority")).toBeVisible()
    await expect(tasks.cell(FIRST, "priority")).toBeVisible()
    expect(await tasks.shownColumns()).toEqual(before.filter((column) => column !== "status"))
    await expect(tasks.columnsButton).toHaveText("Columns (1 hidden)")
    await expect(tasks.columnsStatus).toHaveText("State hidden")
    // the list stays open: several columns are hidden one after the other
    await expect(tasks.columnsList).toBeVisible()

    // still a column of the grid: in the page, and counted
    await expect(tasks.cell(FIRST, "status")).toHaveCount(1)
    await expect(tasks.grid).toHaveAttribute("aria-colcount", colcount!)
    await expect(tasks.cell(FIRST, "priority")).toHaveAttribute("aria-colindex", colindex!)
    // and nothing a screen reader is told of
    await expect(page.getByRole("columnheader", { name: "State", exact: true })).toHaveCount(0)
    await expect(page.getByRole("columnheader", { name: "Priority", exact: true })).toHaveCount(1)

    await tasks.columnBox("priority").uncheck()
    await expect(tasks.columnsButton).toHaveText("Columns (2 hidden)")
    await expect(tasks.columnsStatus).toHaveText("Priority hidden")

    await tasks.columnBox("status").check()
    await expect(tasks.header("status")).toBeVisible()
    await expect(tasks.cell(FIRST, "status")).toBeVisible()
    await expect(tasks.columnsButton).toHaveText("Columns (1 hidden)")
    await expect(tasks.columnsStatus).toHaveText("State shown")
    await tasks.columnBox("priority").check()
    await expect(tasks.columnsButton).toHaveText("Columns")
    expect(await tasks.shownColumns()).toEqual(before)

    // the server has heard of none of it, and the URL says nothing
    expect(await pushed.all()).toEqual([])
    expect(params(page)).toEqual({})
  })

  test("every column has a box but the label's, the boxes', the expanders' and the actions'", async ({ tasks }) => {
    const columns = await tasks.columns()
    expect(columns[0]).toBe("title")
    expect(await tasks.listedColumns()).toEqual(HIDEABLE)
    expect(await tasks.listedColumns()).toEqual(columns.slice(1))
    await expect(tasks.columnBox("title")).toHaveCount(0)

    // all of them can be hidden at once: the label stays, and no box is held back
    await tasks.hide(...HIDEABLE)
    expect(await tasks.shownColumns()).toEqual(["title"])
    await expect(tasks.columnsButton).toHaveText("Columns (21 hidden)")
    for (const column of HIDEABLE) await expect(tasks.columnBox(column)).toBeEnabled()
    await expect(tasks.boxCell(FIRST)).toBeVisible()
    await expect(tasks.expanderCell(FIRST)).toBeVisible()
    await expect(tasks.actionsCell(FIRST)).toBeVisible()
    // the table is as wide as its place still
    const wide = await layout(tasks)
    expect(wide.cells).toBeCloseTo(wide.table, 0)
  })

  test("Escape closes the list and gives the button the focus; so does a click elsewhere, without the focus", async ({
    page,
    tasks,
  }) => {
    await tasks.columnsButton.click()
    await tasks.columnBox("status").uncheck()
    await expect(tasks.columnBox("status")).toBeFocused()
    await page.keyboard.press("Escape")
    await expect(tasks.columnsList).toBeHidden()
    await expect.poll(() => tasks.columnsOpen()).toBe(false)
    await expect(tasks.columnsButton).toBeFocused()
    // what was hidden stays hidden
    await expect(tasks.header("status")).toBeHidden()

    // Escape on the button too
    await page.keyboard.press("Enter")
    await expect(tasks.columnsList).toBeVisible()
    await expect(tasks.columnsButton).toBeFocused()
    await page.keyboard.press("Escape")
    await expect(tasks.columnsList).toBeHidden()

    // the button closes what it opened
    await tasks.columnsButton.click()
    await expect(tasks.columnsList).toBeVisible()
    await tasks.columnsButton.click()
    await expect(tasks.columnsList).toBeHidden()
    await expect.poll(() => tasks.columnsOpen()).toBe(false)

    // a click on a cell: the list closes, and the cell has the focus
    await tasks.columnsButton.click()
    await tasks.cell(SECOND, "title").click()
    await expect(tasks.columnsList).toBeHidden()
    await expect.poll(() => tasks.columnsOpen()).toBe(false)
    await expect(tasks.cell(SECOND, "title")).toBeFocused()

    // a click on nothing in particular
    await tasks.columnsButton.click()
    await page.locator("h1, [id='task-name']").first().click()
    await expect(tasks.columnsList).toBeHidden()

    // a click in the list beside the boxes leaves it open
    await tasks.columnsButton.click()
    await tasks.columnsList.click({ position: { x: 2, y: 2 } })
    await expect(tasks.columnsList).toBeVisible()
  })

  test("from the keyboard: Enter opens, Tab goes through the boxes, Space hides, and Tab past the last box closes", async ({
    page,
    tasks,
  }) => {
    await tasks.columnsButton.focus()
    await page.keyboard.press("Enter")
    await expect(tasks.columnsList).toBeVisible()
    await expect(tasks.columnsButton).toBeFocused()

    await page.keyboard.press("Tab")
    await expect(tasks.columnBox("status")).toBeFocused()
    await page.keyboard.press("Space")
    await expect(tasks.header("status")).toBeHidden()
    await expect(tasks.columnBox("status")).toBeFocused()
    await page.keyboard.press("Tab")
    await expect(tasks.columnBox("priority")).toBeFocused()
    await page.keyboard.press("Shift+Tab")
    await page.keyboard.press("Space")
    await expect(tasks.header("status")).toBeVisible()

    // out of the list at its end: it closes, and focus is in the grid
    await tasks.columnBox("reporter").focus()
    await page.keyboard.press("Tab")
    await expect(tasks.columnsList).toBeHidden()
    await expect.poll(() => tasks.columnsOpen()).toBe(false)
    expect(await tasks.hasFocus()).toBe(true)

    // and at its start
    await tasks.columnsButton.focus()
    await page.keyboard.press("Space")
    await expect(tasks.columnsList).toBeVisible()
    await page.keyboard.press("Shift+Tab")
    await expect(tasks.columnsList).toBeHidden()
  })

  test("in a narrow window the list stays inside it", async ({ page, tasks }) => {
    await page.setViewportSize({ width: 520, height: 900 })
    await tasks.columnsButton.click()
    const button = (await tasks.columnsButton.boundingBox())!
    const list = (await tasks.columnsList.boundingBox())!
    // the button is at the window's edge: the list would reach past it
    expect(button.x + list.width).toBeGreaterThan(520)
    expect(list.x + list.width).toBeLessThanOrEqual(520)
    expect(list.x).toBeGreaterThanOrEqual(0)
  })

  test("the list follows its button when the page scrolls", async ({ page, tasks }) => {
    await tasks.columnsButton.click()
    await page.mouse.wheel(0, 60)
    await expect
      .poll(async () => {
        const button = (await tasks.columnsButton.boundingBox())!
        const list = (await tasks.columnsList.boundingBox())!
        return Math.round(list.y - (button.y + button.height))
      })
      .toBe(2)
  })
})

test.describe("a table without a column of its label", () => {
  test("lets every column be hidden but the last one that is shown", async ({ page }) => {
    const comments = new Table(page, "comment", "/comments")
    await comments.open()
    const columns = await comments.columns()
    expect(await comments.listedColumns()).toEqual(columns)
    const [kept, ...others] = [...columns].reverse()

    await comments.openColumns()
    for (const column of columns) await expect(comments.columnBox(column)).toBeEnabled()
    await comments.hide(...others)
    expect(await comments.shownColumns()).toEqual([kept])
    // the box of the one column left cannot be used, and is ticked
    await expect(comments.columnBox(kept)).toBeDisabled()
    await expect(comments.columnBox(kept)).toBeChecked()
    await comments.columnBox(kept).click({ force: true })
    await expect(comments.header(kept)).toBeVisible()
    await expect(comments.columnsButton).toHaveText(`Columns (${others.length} hidden)`)

    // once another is shown again, either can go
    await comments.columnBox(others[0]).check()
    await expect(comments.columnBox(kept)).toBeEnabled()
    await comments.columnBox(kept).uncheck()
    await expect(comments.header(kept)).toBeHidden()
    await expect(comments.columnBox(others[0])).toBeDisabled()
    expect(await comments.shownColumns()).toEqual([others[0]])
  })

  test("shows a column again when the server takes the last one that is shown away", async ({ page }) => {
    const comments = new Table(page, "comment", "/comments")
    await comments.open()
    const columns = await comments.columns()
    const [kept, next, ...others] = columns
    await comments.hide(next, ...others)
    await page.keyboard.press("Escape")

    // what a patch does that takes a column away: its header, its filter,
    // its cells and its box go
    await page.evaluate(
      ([id, column]) => {
        const head = document.getElementById(`${id}-head-${column}`) as HTMLTableCellElement
        const place = head.getAttribute("aria-colindex")
        const table = head.closest("table")!
        document.getElementById(`${id}-column-${column}-entry`)!.remove()
        for (const cell of Array.from(table.querySelectorAll(`[aria-colindex="${place}"]:not([colspan])`))) cell.remove()
      },
      [comments.id, kept],
    )

    await expect(comments.header(next)).toBeVisible()
    expect(await comments.shownColumns()).toEqual([next])
    await expect(comments.columnsButton).toHaveText(`Columns (${others.length} hidden)`)
    await comments.openColumns()
    await expect(comments.columnBox(next)).toBeChecked()
    await expect(comments.columnBox(next)).toBeDisabled()
  })
})

test.describe("the keys of the grid", () => {
  test.beforeEach(async ({ tasks }) => {
    await tasks.open()
  })

  test("the arrow keys, Home and End pass over hidden columns, in the rows, the header and the filters", async ({
    page,
    tasks,
  }) => {
    await tasks.hide("status", "priority", "assignee", "reporter")
    await page.keyboard.press("Escape")
    const keys = await tasks.rowKeys()
    const [first, second] = keys
    const last = keys.at(-1)!

    await tasks.cell(first, "title").focus()
    await tasks.press("ArrowRight")
    await expect(tasks.cell(first, "progress")).toBeFocused()
    await tasks.press("ArrowDown")
    await expect(tasks.cell(second, "progress")).toBeFocused()
    await tasks.press("ArrowLeft")
    await expect(tasks.cell(second, "title")).toBeFocused()
    await tasks.press("ArrowLeft")
    await expect(tasks.expanderCell(second)).toBeFocused()

    await tasks.press("End")
    await expect(tasks.actionsCell(second)).toBeFocused()
    await tasks.press("ArrowLeft")
    await expect(tasks.cell(second, "project")).toBeFocused()
    await tasks.press("ArrowRight")
    await expect(tasks.actionsCell(second)).toBeFocused()
    await tasks.press("Home")
    await expect(tasks.boxCell(second)).toBeFocused()

    // the header and the filter row
    await tasks.header("title").focus()
    await tasks.press("ArrowRight")
    await expect(tasks.header("progress")).toBeFocused()
    await tasks.press("ArrowDown")
    await expect(tasks.filterCell("progress")).toBeFocused()
    await tasks.press("ArrowLeft")
    await expect(tasks.filterCell("title")).toBeFocused()
    await tasks.press("ArrowRight", "ArrowDown")
    await expect(tasks.cell(first, "progress")).toBeFocused()

    await tasks.press("Control+End")
    await expect(tasks.actionsCell(last)).toBeFocused()
    await tasks.press("Control+Home")
    await expect(tasks.boxCell(first)).toBeFocused()

    // no key has reached a cell that is not shown
    expect(await tasks.tabStops()).toEqual([`task-row-${first}-s`])
  })

  test("where the first and the last column are hidden, Home and End go to the first and the last that are shown", async ({
    page,
  }) => {
    const specimens = specimensOf(page)
    await specimens.open()
    // no boxes, no expanders, no actions: the columns are all there is
    await expect(specimens.hookRoot).toHaveAttribute("data-lead", "0")
    await expect(specimens.actionsHeader).toHaveCount(0)
    const columns = await specimens.columns()
    expect(await specimens.listedColumns()).toEqual(columns)
    const key = await specimens.rowKey(1)
    const first = columns[0]
    const last = columns.at(-1)!

    await specimens.hide(first, columns[1], last)
    await page.keyboard.press("Escape")
    // the tab stop was the first cell of the first row: it is the first one shown now
    expect(await specimens.tabStops()).toEqual([`specimen-row-${key}-c-${columns[2]}`])

    await specimens.cell(key, columns[4]).focus()
    await specimens.press("Home")
    await expect(specimens.cell(key, columns[2])).toBeFocused()
    await specimens.press("ArrowLeft")
    await expect(specimens.cell(key, columns[2])).toBeFocused()
    await specimens.press("End")
    await expect(specimens.cell(key, columns.at(-2)!)).toBeFocused()
    await specimens.press("ArrowRight")
    await expect(specimens.cell(key, columns.at(-2)!)).toBeFocused()
    await specimens.press("Control+Home")
    await expect(specimens.cell(key, columns[2])).toBeFocused()
    await specimens.press("ArrowUp", "ArrowUp", "Home")
    await expect(specimens.header(columns[2])).toBeFocused()
    await specimens.press("End")
    await expect(specimens.header(columns.at(-2)!)).toBeFocused()

    // the last column is hidden and its neighbour on that side is none: the tab stop goes to the left
    await specimens.unhide(last)
    await specimens.cell(key, last).focus()
    await specimens.hide(last)
    expect(await specimens.tabStops()).toEqual([`specimen-row-${key}-c-${columns.at(-2)!}`])
  })

  test("the tab stop leaves a column that is hidden, for the next one that is shown", async ({ page, tasks }) => {
    const first = await tasks.rowKey(1)
    await tasks.cell(first, "status").focus()
    expect(await tasks.tabStops()).toEqual([`task-row-${first}-c-status`])

    await tasks.hide("status")
    expect(await tasks.tabStops()).toEqual([`task-row-${first}-c-priority`])
    await tasks.hide("priority")
    expect(await tasks.tabStops()).toEqual([`task-row-${first}-c-progress`])
    // one that is not the tab stop's leaves it where it is
    await tasks.hide("due_on")
    expect(await tasks.tabStops()).toEqual([`task-row-${first}-c-progress`])

    // Tab from the button, with the list closed, goes into the grid: to that cell
    await page.keyboard.press("Escape")
    await expect(tasks.columnsButton).toBeFocused()
    await page.keyboard.press("Tab")
    await expect(tasks.cell(first, "progress")).toBeFocused()
    // and Down Arrow stays in its column
    await tasks.press("ArrowDown")
    await expect(tasks.cell(await tasks.rowKey(2), "progress")).toBeFocused()

    // shown again, the column is reached as before
    await tasks.unhide("priority")
    await page.keyboard.press("Escape")
    await tasks.cell(first, "progress").focus()
    await tasks.press("ArrowLeft")
    await expect(tasks.cell(first, "priority")).toBeFocused()
  })

  test("focus that is in a column when it is hidden goes to the next cell that is shown", async ({ tasks }) => {
    await tasks.openColumns()

    // on a cell
    await tasks.cell(SECOND, "priority").focus()
    await toggleInPlace(tasks, "priority")
    await expect(tasks.header("priority")).toBeHidden()
    await expect(tasks.cell(SECOND, "progress")).toBeFocused()
    expect(await tasks.tabStops()).toEqual([`task-row-${SECOND}-c-progress`])

    // in the filter of the column
    await tasks.filterValue("progress").focus()
    await toggleInPlace(tasks, "progress")
    await expect(tasks.filterCell("estimate_hours")).toBeFocused()

    // on its header
    await tasks.header("estimate_hours").focus()
    await toggleInPlace(tasks, "estimate_hours")
    await expect(tasks.header("billable?")).toBeFocused()
    expect(await tasks.hasFocus()).toBe(true)
  })
})

test("from a line under a row, Up Arrow goes to the column a person was in, or to the next one that is shown", async ({
  tasks,
}) => {
  await tasks.open()
  await tasks.expand(FIRST)
  await tasks.openColumns()
  await tasks.cell(FIRST, "status").focus()
  await tasks.press("ArrowDown")
  const line = tasks.lines(FIRST).first()
  await expect(line).toBeFocused()

  // the column the person came from goes while they are on the line
  await toggleInPlace(tasks, "status")
  await expect(tasks.header("status")).toBeHidden()
  await expect(line).toBeFocused()
  await tasks.press("ArrowUp")
  await expect(tasks.cell(FIRST, "priority")).toBeFocused()
})

test.describe("what is hidden outlives what the server sends", () => {
  test("a sort, a filter, another page, a saved cell and an expanded row", async ({ page, tasks, pushed }) => {
    await tasks.open()
    const hidden = ["status", "priority", "due_on"]
    await tasks.hide(...hidden)
    await page.keyboard.press("Escape")
    const shown = (await tasks.columns()).filter((column) => !hidden.includes(column))
    const same = async (after: string) => {
      expect(await tasks.shownColumns(), after).toEqual(shown)
      const key = await tasks.rowKey(1)
      for (const column of hidden) {
        await expect(tasks.header(column), after).toBeHidden()
        await expect(tasks.filterCell(column), after).toBeHidden()
        await expect(tasks.cell(key, column), after).toBeHidden()
        await expect(tasks.cell(key, column), after).toHaveCount(1)
        await expect(tasks.columnBox(column), after).not.toBeChecked()
      }
      await expect(tasks.cell(key, "progress"), after).toBeVisible()
      await expect(tasks.columnBox("progress"), after).toBeChecked()
      await expect(tasks.columnsButton, after).toHaveText("Columns (3 hidden)")
      expect(await tasks.tabStops(), after).toHaveLength(1)
    }
    await same("at first")

    await tasks.reads(() => tasks.header("progress").click({ position: { x: 20, y: 10 } }))
    await expect(tasks.header("progress")).toHaveAttribute("aria-sort", "ascending")
    await same("after a sort")

    await tasks.filterValue("title").fill("the")
    await tasks.reads(() => tasks.filterValue("title").press("Enter"))
    await expect(tasks.clearFilters).toBeVisible()
    await same("after a filter")

    await tasks.reads(() => tasks.next.click())
    await same("on another page")

    const key = await tasks.rowKey(1)
    const title = tasks.cell(key, "title")
    await title.focus()
    await tasks.press("Enter")
    await tasks.retype("A title of another kind")
    await tasks.saves(title, () => tasks.press("Enter"))
    await expect(title).toHaveText("A title of another kind")
    await same("after a save")

    await tasks.expand(key)
    await same("with a row expanded")
    await tasks.openLine(key, "comments")
    await same("with a nested table open")

    // with the list open, too, and focus on the box of a hidden column: the
    // list stays open, and where it was, and the box as it is
    await tasks.openColumns()
    await tasks.columnBox("status").focus()
    const place = await tasks.columnsList.boundingBox()
    // sorted without a click, which would take the focus to the header
    await tasks.reads(() =>
      tasks.forge("sort", { column: "title" }),
    )
    await expect(tasks.header("title")).toHaveAttribute("aria-sort", "ascending")
    await expect(tasks.columnsList).toBeVisible()
    expect(await tasks.columnsOpen()).toBe(true)
    await expect(tasks.columnBox("status")).toBeFocused()
    expect(await tasks.columnsList.boundingBox()).toEqual(place)
    await same("after a sort with the list open")
    await page.keyboard.press("Escape")

    await tasks.reads(() => tasks.clearFilters.click())
    await same("after the filters were cleared")

    // of all of it, the server heard the sorts, the filters, the page, the save and the rows that opened
    expect(await pushed.count("save")).toBe(1)
    expect(params(page)).toEqual({ "task[sort]": "title" })
  })

  test("a patch that brings no row: the boxes stay as they are, with the list open", async ({ tasks }) => {
    await tasks.open()
    const rows = await tasks.rowKeys()
    await tasks.hide("status", "progress")
    await expect(tasks.columnsList).toBeVisible()

    // A value the read action refuses is said at its input, and the rows
    // stay: nothing of the grid is sent again. Sent by a script, so that
    // focus stays in the list and the list open.
    await tasks.argument("due_within-days").evaluate((input: HTMLInputElement) => {
      input.value = "-1"
      input.form!.requestSubmit()
    })
    await expect(tasks.argumentError("due_within-days")).toHaveText("must be greater than or equal to 0")
    expect(await tasks.rowKeys()).toEqual(rows)

    await expect(tasks.columnsList).toBeVisible()
    await expect(tasks.columnBox("status")).not.toBeChecked()
    await expect(tasks.columnBox("progress")).not.toBeChecked()
    await expect(tasks.columnBox("priority")).toBeChecked()
    await expect(tasks.columnsButton).toHaveText("Columns (2 hidden)")
    expect(await tasks.columnsOpen()).toBe(true)
    await expect(tasks.header("status")).toBeHidden()
  })

  test("a page that is loaded again shows every column", async ({ page, tasks }) => {
    await tasks.open()
    const before = await tasks.columns()
    await tasks.hide("status", "progress")
    expect(await tasks.shownColumns()).not.toEqual(before)

    await page.reload()
    await tasks.ready()
    expect(await tasks.shownColumns()).toEqual(before)
    await expect(tasks.columnsButton).toHaveText("Columns")
    await tasks.openColumns()
    for (const column of HIDEABLE) await expect(tasks.columnBox(column)).toBeChecked()
    // one sheet per grid, for what its hook says of scrolling sideways, and
    // none for widths or hidden columns
    expect(await ownedSheets(page)).toEqual({ sheets: 1, grids: 1 })
    expect(await columnRules(page)).toBe(0)
    expect(await page.evaluate(() => Object.keys(localStorage).filter((key) => key !== "phx:theme"))).toEqual([])
    expect(await page.evaluate(() => sessionStorage.length)).toBe(0)
  })

  test("so does a page that was left and come back to", async ({ page, tasks }) => {
    await tasks.open()
    const before = await tasks.columns()
    await tasks.hide("status")
    await page.keyboard.press("Escape")

    await page.getByRole("navigation", { name: "Main" }).getByRole("link", { name: "Labels" }).click()
    await new Table(page, "label", "/labels").ready()
    // one sheet per grid, for what its hook says of scrolling sideways, and
    // none for widths or hidden columns
    expect(await ownedSheets(page)).toEqual({ sheets: 1, grids: 1 })
    expect(await columnRules(page)).toBe(0)
    await page.goBack()
    await tasks.ready()
    expect(await tasks.shownColumns()).toEqual(before)
  })

  test("the hidden columns stay hidden when the header gets another column in front", async ({ tasks }) => {
    await tasks.open()
    await tasks.hide("status", "progress")
    const shown = await tasks.shownColumns()

    // What a patch does that takes the column of the boxes away: its cells
    // go, and every cell after them stands one place further to the left.
    await tasks.grid.evaluate((table) => {
      for (const row of Array.from((table as HTMLTableElement).rows)) {
        const first = row.cells[0]
        if (first.colSpan > 1) continue
        first.remove()
        for (const cell of Array.from(row.cells)) {
          cell.setAttribute("aria-colindex", String(Number(cell.getAttribute("aria-colindex")) - 1))
        }
      }
    })

    await expect(tasks.cell(FIRST, "priority")).toBeVisible()
    await expect(tasks.cell(FIRST, "status")).toBeHidden()
    await expect(tasks.cell(FIRST, "progress")).toBeHidden()
    await expect(tasks.cell(FIRST, "estimate_hours")).toBeVisible()
    expect(await tasks.shownColumns()).toEqual(shown)
  })

  test("a hidden column that the server takes away is counted no longer, and is hidden still when it comes back", async ({
    page,
    tasks,
  }) => {
    await tasks.open()
    await tasks.hide("status", "progress")
    await expect(tasks.columnsButton).toHaveText("Columns (2 hidden)")

    // what a patch does that takes the column away, and one that brings it back
    const entry = await page.evaluate(() => {
      const entry = document.getElementById("task-column-progress-entry")!
      const html = entry.outerHTML
      entry.remove()
      return html
    })
    await expect(tasks.columnsButton).toHaveText("Columns (1 hidden)")

    await page.evaluate((entry) => {
      document.getElementById("task-column-status-entry")!.insertAdjacentHTML("afterend", entry)
      // as the server sends it: ticked
      ;(document.getElementById("task-column-progress") as HTMLInputElement).checked = true
    }, entry)
    await expect(tasks.columnsButton).toHaveText("Columns (2 hidden)")
    await expect(tasks.columnBox("progress")).not.toBeChecked()
    await expect(tasks.header("progress")).toBeHidden()
  })
})

test.describe("a hidden column that the rows are filtered or sorted by", () => {
  test.beforeEach(async ({ tasks }) => {
    await tasks.open()
  })

  test("keeps its filter and its sort, and the button and its box say so", async ({ page, tasks }) => {
    await tasks.filterValue("progress").fill("100")
    await tasks.reads(() => tasks.filterValue("progress").press("Enter"))
    await tasks.reads(() => tasks.header("progress").click({ position: { x: 20, y: 10 } }))
    await tasks.filterValue("title").fill("e")
    await tasks.reads(() => tasks.filterValue("title").press("Enter"))
    const range = await tasks.range.textContent()
    const rows = await tasks.rowKeys()
    expect(params(page)).toEqual({
      "task[sort]": "progress",
      "task[f][progress]": "100",
      "task[f][title]": "e",
    })

    // shown, it has no word at its box: its filter is there to be seen
    await tasks.openColumns()
    await expect(tasks.columnsButton).toHaveText("Columns")
    await expect(tasks.columnFlag("progress")).toHaveText("(filtered, sorted)")
    await expect(tasks.columnFlag("progress")).toBeHidden()
    await expect(page.getByRole("checkbox", { name: "Progress", exact: true })).toBeChecked()

    await tasks.hide("progress")
    await expect(tasks.columnsButton).toHaveText("Columns (1 hidden, 1 filtered, 1 sorted)")
    await expect(tasks.columnEntry("progress")).toHaveText("Progress (filtered, sorted)")
    await expect(tasks.columnFlag("progress")).toBeVisible()
    await expect(page.getByRole("checkbox", { name: "Progress (filtered, sorted)", exact: true })).not.toBeChecked()
    // another hidden column says nothing of the kind
    await tasks.hide("status")
    await expect(tasks.columnsButton).toHaveText("Columns (2 hidden, 1 filtered, 1 sorted)")
    await expect(tasks.columnEntry("status")).toHaveText("State")
    await expect(tasks.columnFlag("status")).toHaveCount(0)

    // the rows are as they were, and so is the URL
    expect(await tasks.rowKeys()).toEqual(rows)
    await expect(tasks.range).toHaveText(range!)
    expect(params(page)).toEqual({
      "task[sort]": "progress",
      "task[f][progress]": "100",
      "task[f][title]": "e",
    })

    // sorted by another column: the button and the box follow, with the list open
    await tasks.reads(() =>
      tasks.forge("sort", { column: "title" }),
    )
    await expect(tasks.columnsList).toBeVisible()
    await expect(tasks.columnsButton).toHaveText("Columns (2 hidden, 1 filtered)")
    await expect(tasks.columnEntry("progress")).toHaveText("Progress (filtered)")

    // "Clear filters" clears the one that is out of sight as well
    await page.keyboard.press("Escape")
    await tasks.reads(() => tasks.clearFilters.click())
    await expect(tasks.columnsButton).toHaveText("Columns (2 hidden)")
    expect(params(page)).toEqual({ "task[sort]": "title" })
    await tasks.openColumns()
    await expect(tasks.columnEntry("progress")).toHaveText("Progress")
    await expect(tasks.columnBox("progress")).not.toBeChecked()

    await tasks.unhide("progress")
    await expect(tasks.filterValue("progress")).toHaveValue("")
  })

  test("a sort that leaves the rows as they stand is said all the same", async ({ tasks }) => {
    // one row: sorted by whatever, it is the same row in the same place
    await tasks.filterValue("title").fill("Rename the onboarding email")
    await tasks.reads(() => tasks.filterValue("title").press("Enter"))
    expect(await tasks.rowKeys()).toEqual([FIRST])
    await tasks.hide("priority")
    await expect(tasks.columnsButton).toHaveText("Columns (1 hidden)")

    await tasks.forge("sort", { column: "priority" })
    await expect(tasks.header("priority")).toHaveAttribute("aria-sort", "ascending")
    await expect(tasks.columnsButton).toHaveText("Columns (1 hidden, 1 sorted)")
    await expect(tasks.columnFlag("priority")).toBeVisible()
  })

  test("a column that is hidden first and sorted by afterwards", async ({ tasks }) => {
    await tasks.hide("priority")
    await expect(tasks.columnsButton).toHaveText("Columns (1 hidden)")
    // sorted by a script: its header is not there to be clicked
    await tasks.reads(() => tasks.header("priority").evaluate((header: HTMLElement) => header.click()))
    await expect(tasks.columnsButton).toHaveText("Columns (1 hidden, 1 sorted)")
    await expect(tasks.columnEntry("priority")).toHaveText("Priority (sorted)")
    await tasks.unhide("priority")
    await expect(tasks.columnsButton).toHaveText("Columns")
    await expect(tasks.columnFlag("priority")).toBeHidden()
    await expect(tasks.header("priority")).toHaveAttribute("aria-sort", "ascending")
  })
})

test.describe("the widths of the columns", () => {
  test.beforeEach(async ({ tasks }) => {
    await tasks.open()
  })

  test("a column keeps the width a person gave it while it is hidden", async ({ page, tasks }) => {
    const status = await tasks.width("status")
    await tasks.drag("status", 60)
    await tasks.drag("title", -80)
    const title = await tasks.width("title")
    const wide = await layout(tasks)

    await tasks.hide("status")
    await page.keyboard.press("Escape")
    expect(await tasks.width("title")).toBe(title)
    // its handle says what it said: there is no width to read meanwhile
    await expect(tasks.resizer("status")).toHaveAttribute("aria-valuenow", String(status + 60))
    const narrow = await layout(tasks)
    expect(narrow.table).toBeCloseTo(wide.table - (status + 60), 0)
    expect(narrow.cells).toBeCloseTo(narrow.table, 0)

    // the others can be changed meanwhile
    await tasks.drag("title", 30)
    expect(await tasks.width("title")).toBe(title + 30)

    await tasks.unhide("status")
    await page.keyboard.press("Escape")
    expect(await tasks.width("status")).toBe(status + 60)
    await expect(tasks.resizer("status")).toHaveAttribute("aria-valuenow", String(status + 60))
    expect((await tasks.cell(FIRST, "status").boundingBox())!.width).toBe(status + 60)
    expect(await tasks.width("title")).toBe(title + 30)

    // "the width it had before" is still the one from before
    await tasks.resizer("status").dblclick()
    expect(await tasks.width("status")).toBe(status)
  })

  test("a column that was hidden when the widths were first changed gets one when it is shown", async ({
    page,
    tasks,
  }) => {
    await tasks.hide("priority")
    await page.keyboard.press("Escape")
    const title = await tasks.width("title")
    const status = await tasks.width("status")

    await tasks.drag("title", -70)
    expect(await tasks.width("title")).toBe(title - 70)
    expect(await tasks.width("status")).toBe(status)

    await tasks.unhide("priority")
    await page.keyboard.press("Escape")
    const priority = await tasks.width("priority")
    expect(priority).toBeGreaterThan(0)
    expect(await tasks.width("title")).toBe(title - 70)
    expect(await tasks.width("status")).toBe(status)
    await expect(tasks.resizer("priority")).toHaveAttribute("aria-valuenow", String(Math.round(priority)))

    await tasks.drag("priority", 40)
    expect(await tasks.width("priority")).toBe(Math.round(priority) + 40)
    expect(await tasks.width("title")).toBe(title - 70)
    await tasks.resizer("priority").dblclick()
    expect(await tasks.width("priority")).toBeCloseTo(priority, 0)
  })
})

test.describe("what is open in a column when it is hidden", () => {
  test("an editor is left as focus leaves it: what was typed is saved", async ({ page, tasks, pushed }) => {
    await tasks.open()
    const cell = tasks.cell(FIRST, "description")
    await tasks.openColumns()
    await cell.focus()
    await tasks.press("Enter")
    await expect(tasks.editor(cell)).toBeFocused()
    await tasks.retype("A text of another kind")
    await pushed.clear()

    await toggleInPlace(tasks, "description")
    await expect(tasks.header("description")).toBeHidden()
    await expect.poll(() => pushed.count("save")).toBe(1)
    await expect(tasks.openEditors).toHaveCount(0)
    await expect(cell).toHaveText("A text of another kind")
    await expect(cell).not.toHaveAttribute("aria-busy")
    // focus is on the next cell that is shown, which is the tab stop
    await expect(tasks.cell(FIRST, "tags")).toBeFocused()
    expect(await tasks.tabStops()).toEqual([`task-row-${FIRST}-c-tags`])

    await tasks.unhide("description")
    await expect(cell).toBeVisible()
    await expect(cell).toHaveText("A text of another kind")
    await page.reload()
    await tasks.ready()
    await expect(cell).toHaveText("A text of another kind")
  })

  test("an editor a person leaves for the list is saved before its column goes", async ({ tasks, pushed }) => {
    await tasks.open()
    const cell = tasks.cell(FIRST, "description")
    await cell.focus()
    await tasks.press("Enter")
    await tasks.retype("A text of a third kind")
    await pushed.clear()

    await tasks.saves(cell, () => tasks.columnsButton.click())
    await tasks.hide("description")
    expect(await pushed.count("save")).toBe(1)
    await tasks.unhide("description")
    await expect(cell).toHaveText("A text of a third kind")
  })

  test("the counter of an editor in another column stays in its cell when the columns move", async ({ page }) => {
    const labels = new Table(page, "label", "/labels")
    await labels.open()
    const name = labels.cell(await labels.rowKey(1), "name")
    const [first] = await labels.listedColumns()
    await labels.openColumns()
    await name.focus()
    await labels.press("Enter")
    const count = name.locator("[data-count]")
    await expect(count).toBeVisible()
    const before = (await name.boundingBox())!

    await toggleInPlace(labels, first)
    await expect(labels.header(first)).toBeHidden()
    // the table fills its place: the cell is another width now, or elsewhere
    const cell = (await name.boundingBox())!
    expect([cell.x, cell.width]).not.toEqual([before.x, before.width])
    // the counter is in the cell, under the editor
    const box = (await count.boundingBox())!
    expect(box.x).toBeGreaterThanOrEqual(cell.x - 0.5)
    expect(box.x + box.width).toBeLessThanOrEqual(cell.x + cell.width + 0.5)
    expect(box.y + box.height).toBeLessThanOrEqual(cell.y + cell.height + 0.5)
    await expect(labels.editor(name)).toBeFocused()
    await labels.press("Escape")
  })

  test("a sensitive value that is shown is hidden again", async ({ page }) => {
    const projects = new Table(page, "project", "/projects")
    await projects.open()
    const id = MAPS.project.dataWarehouse
    const cell = projects.cell(id, "budget")
    await projects.openColumns()
    await cell.focus()
    await projects.press("Shift+Enter")
    await expect(cell.locator("[data-secret]")).toHaveText("57500")

    await toggleInPlace(projects, "budget")
    await expect(projects.header("budget")).toBeHidden()
    await expect(cell.locator("[data-secret]")).toHaveText("")

    await projects.unhide("budget")
    await expect(cell.locator("[data-mask]")).toBeVisible()
    await expect(cell.locator("[data-secret]")).toHaveText("")
    await expect(cell.getByRole("button")).toHaveAccessibleName("Show Budget")
  })

  test("the message of a cell whose save failed goes with the column, and is there again when the column is", async ({
    page,
  }) => {
    const specimens = specimensOf(page)
    await specimens.open()
    const key = await specimens.rowKey(1)
    const cell = specimens.cell(key, "an_integer")
    await cell.focus()
    await specimens.press("Enter")
    await specimens.editor(cell).fill("5000")
    await specimens.saves(cell, () => specimens.press("Enter"))
    await expect(cell).toHaveAttribute("aria-invalid", "true")
    // the message is in the cell, under what it shows, and always there to be seen
    await expect(specimens.failure(cell)).toBeVisible()
    await expect(cell).toHaveAttribute("aria-describedby", /-error$/)

    await specimens.openColumns()
    await cell.focus()
    await toggleInPlace(specimens, "an_integer")
    await expect(cell).toBeHidden()
    await expect(specimens.failure(cell)).toBeHidden()

    // the cell is marked still, and says why, without a person coming to it
    await specimens.unhide("an_integer")
    await expect(cell).toHaveAttribute("aria-invalid", "true")
    await expect(specimens.failure(cell)).toBeVisible()
    await expect(specimens.failure(cell)).toHaveText("must be less than or equal to 1000")
    await page.keyboard.press("Escape")
    await cell.focus()

    // and the message goes with its cell when a column before it goes
    await page.mouse.move(1, 1)
    await expect(specimens.failure(cell)).toBeVisible()
    const columns = await specimens.columns()
    const before = (await cell.boundingBox())!
    await toggleInPlace(specimens, columns[0])
    await expect(specimens.header(columns[0])).toBeHidden()
    const after = (await cell.boundingBox())!
    expect(after.x).toBeLessThan(before.x)
    await expect(cell).toBeFocused()
    const message = (await specimens.failure(cell).boundingBox())!
    expect(message.x, "inside its cell").toBeGreaterThanOrEqual(after.x - 0.5)
    expect(message.x + message.width, "inside its cell").toBeLessThanOrEqual(after.x + after.width + 0.5)
    expect(message.y + message.height, "inside its cell").toBeLessThanOrEqual(after.y + after.height + 0.5)
  })

  test("the action panel has the fields of hidden columns, and rows are selected as before", async ({ tasks }) => {
    await tasks.open()
    await tasks.hide("progress", "status")
    await tasks.columnsButton.press("Escape")

    await tasks.action(FIRST, "set_progress").click()
    await expect(tasks.panel).toBeVisible()
    await expect(tasks.field("progress")).toBeVisible()
    await tasks.panelCancel.click()
    await expect(tasks.panel).toHaveCount(0)
    await expect(tasks.header("progress")).toBeHidden()

    await tasks.box(FIRST).click()
    await tasks.box(SECOND).click()
    await expect(tasks.selectedCount).toHaveText("2 selected")
    await expect(tasks.columnsButton).toHaveText("Columns (2 hidden)")
    await expect(tasks.columnsButton).toBeVisible()
  })
})

test.describe("each table on its own", () => {
  test("a nested table has its own button, which looks and works as any table's", async ({ page, tasks }) => {
    await tasks.open()
    const comments = await tasks.openLine(FIRST, "comments")
    const outer = await tasks.shownColumns()
    const inner = await comments.columns()

    // the same button, and the same list
    const look = (table: Table) =>
      table.columnsButton.evaluate((button) => {
        const { height, fontSize, fontWeight, paddingLeft, paddingRight, borderRadius, backgroundColor, color } =
          getComputedStyle(button)
        return {
          classes: button.className,
          height,
          fontSize,
          fontWeight,
          paddingLeft,
          paddingRight,
          borderRadius,
          backgroundColor,
          color,
        }
      })
    expect(await look(comments)).toEqual(await look(tasks))
    await comments.openColumns()
    await tasks.openColumns()
    // one list at a time: the other's button is a click elsewhere
    await expect(comments.columnsList).toBeHidden()
    const listLook = (table: Table) =>
      table.columnsList.evaluate((list) => {
        const { padding, borderTopWidth, borderRadius, backgroundColor, fontSize, position } = getComputedStyle(list)
        return { classes: list.className, padding, borderTopWidth, borderRadius, backgroundColor, fontSize, position }
      })
    const outerLook = await listLook(tasks)
    await comments.openColumns()
    expect(await listLook(comments)).toEqual(outerLook)

    // under its own button, and not cut off by the grid around it
    const button = (await comments.columnsButton.boundingBox())!
    const list = (await comments.columnsList.boundingBox())!
    expect(Math.round(list.y - (button.y + button.height))).toBe(2)
    expect(Math.round(list.x)).toBe(Math.round(button.x))
    const last = (await comments.columnBox(inner.at(-1)!).boundingBox())!
    expect(last.y + last.height).toBeLessThanOrEqual(list.y + list.height)
    await expect(comments.columnBox(inner.at(-1)!)).toBeVisible()

    await comments.hide("body")
    await expect(comments.header("body")).toBeHidden()
    await expect(comments.columnsButton).toHaveText("Columns (1 hidden)")
    await expect(comments.columnsStatus).toHaveText("Body hidden")
    expect(await comments.shownColumns()).toEqual(inner.filter((column) => column !== "body"))
    // the table around it is as it was
    expect(await tasks.shownColumns()).toEqual(outer)
    await expect(tasks.columnsButton).toHaveText("Columns")

    // and the other way round
    await tasks.hide("status", "priority")
    expect(await comments.shownColumns()).toEqual(inner.filter((column) => column !== "body"))
    await expect(comments.columnsButton).toHaveText("Columns (1 hidden)")
    await expect(tasks.columnsButton).toHaveText("Columns (2 hidden)")
    await page.keyboard.press("Escape")

    // the line and the nested table's cell span the columns that are shown, and no more
    const wide = await layout(tasks)
    expect(wide.cells).toBeCloseTo(wide.table, 0)
    const line = (await tasks.lineCell(FIRST, "comments").boundingBox())!
    const row = (await tasks.rowLine(FIRST).boundingBox())!
    expect(line.width).toBeCloseTo(row.width, 0)

    // the keys of the nested grid pass over its hidden column
    const key = await comments.rowKey(1)
    const at = inner.indexOf("body")
    await comments.cell(key, inner[at - 1]).focus()
    await tasks.press("ArrowRight")
    await expect(comments.cell(key, inner[at + 1])).toBeFocused()

    // Left at a cell of a column that is hidden afterwards, the nested
    // table is come back into at the next cell that is shown.
    await comments.unhide("body")
    await comments.cell(key, "body").focus()
    await tasks.press("Escape")
    await expect(tasks.nestedCell(FIRST, "comments")).toBeFocused()
    await toggleInPlace(comments, "body")
    await expect(comments.header("body")).toBeHidden()
    await tasks.press("Enter")
    await expect(comments.cell(key, inner[at + 1])).toBeFocused()
  })

  test("a nested table that is closed and opened again shows every column", async ({ tasks }) => {
    await tasks.open()
    const comments = await tasks.openLine(FIRST, "comments")
    const inner = await comments.columns()
    await comments.hide("body")
    await expect(comments.header("body")).toBeHidden()

    await tasks.line(FIRST, "comments").click()
    await expect(comments.grid).toHaveCount(0)
    await tasks.line(FIRST, "comments").click()
    await comments.loaded()
    await expect(comments.header("body")).toBeVisible()
    expect(await comments.shownColumns()).toEqual(inner)
    await expect(comments.columnsButton).toHaveText("Columns")
  })

  test("the table of a picker: Escape closes its list and leaves the picker open", async ({ page, tasks }) => {
    await tasks.open()
    await tasks.hide("priority")
    await page.keyboard.press("Escape")
    await tasks.cell(FIRST, "assignee").focus()
    await tasks.press("Enter")
    await expect(tasks.picker).toBeVisible()
    const users = tasks.pickerTable("assignee")
    await users.ready()
    const columns = await users.columns()
    const listed = await users.listedColumns()
    expect(listed.length).toBeGreaterThan(0)
    const selected = await users.selectedKeys()

    await users.openColumns()
    // on top of the dialog, and inside the window
    const list = (await users.columnsList.boundingBox())!
    expect(list.x + list.width).toBeLessThanOrEqual(page.viewportSize()!.width)
    await users.columnBox(listed[0]).uncheck()
    await expect(users.header(listed[0])).toBeHidden()
    await expect(users.columnsButton).toHaveText("Columns (1 hidden)")
    expect(await users.shownColumns()).toEqual(columns.filter((column) => column !== listed[0]))

    await page.keyboard.press("Escape")
    await expect(users.columnsList).toBeHidden()
    await expect(users.columnsButton).toBeFocused()
    await expect(tasks.picker).toBeVisible()
    // hiding has selected or chosen no row
    expect(await users.selectedKeys()).toEqual(selected)
    // the table behind the picker has its own
    await expect(tasks.columnsButton).toHaveText("Columns (1 hidden)")

    // with the list closed, Escape is the picker's again
    await page.keyboard.press("Escape")
    await expect(tasks.picker).toHaveCount(0)
    await expect(tasks.header("priority")).toBeHidden()
  })

  test("two tables in one page", async ({ page }) => {
    const projects = new Table(page, "dashboard-projects", "/dashboard")
    const tasks = new Table(page, "dashboard-tasks", "/dashboard")
    await projects.open()
    await tasks.ready()
    const mine = await tasks.shownColumns()
    const theirs = await projects.shownColumns()

    // both have a column called "status"
    await projects.hide("status")
    await expect(projects.columnsButton).toHaveText("Columns (1 hidden)")
    expect(await projects.shownColumns()).toEqual(theirs.filter((column) => column !== "status"))
    expect(await tasks.shownColumns()).toEqual(mine)
    await expect(tasks.columnsButton).toHaveText("Columns")

    // the other table's button closes this one's list
    await tasks.columnsButton.click()
    await expect(projects.columnsList).toBeHidden()
    await expect.poll(() => projects.columnsOpen()).toBe(false)
    await expect(tasks.columnsList).toBeVisible()
    await tasks.columnBox("priority").uncheck()
    await expect(tasks.header("priority")).toBeHidden()
    await expect(tasks.header("status")).toBeVisible()
    await page.keyboard.press("Escape")

    // a patch of one leaves both as they are
    await projects.reads(() => projects.header("name").click({ position: { x: 20, y: 10 } }))
    await expect(projects.header("status")).toBeHidden()
    await expect(tasks.header("priority")).toBeHidden()
    await expect(projects.columnsButton).toHaveText("Columns (1 hidden)")
    await expect(tasks.columnsButton).toHaveText("Columns (1 hidden)")
  })
})

test("in German the button, its list and what is read out are German", async ({ page, tasks }) => {
  await tasks.open()
  await switchLocale(page, "de")
  await tasks.ready()
  await expect(tasks.columnsButton).toHaveText("Spalten")
  await tasks.columnsButton.click()
  await expect(page.getByRole("group", { name: "Spalten" })).toBeVisible()

  const label = (await tasks.header("progress").getAttribute("aria-label"))!
  await tasks.filterValue("progress").fill("100")
  await tasks.reads(() => tasks.filterValue("progress").press("Enter"))
  await tasks.hide("progress", "status")
  await expect(tasks.columnsButton).toHaveText("Spalten (2 ausgeblendet, 1 gefiltert)")
  await expect(tasks.columnEntry("progress")).toHaveText(`${label} (gefiltert)`)
  await tasks.columnBox("progress").check()
  await expect(tasks.columnsStatus).toHaveText(`${label} eingeblendet`)
  await tasks.columnBox("progress").uncheck()
  await expect(tasks.columnsStatus).toHaveText(`${label} ausgeblendet`)
})

for (const theme of ["light", "dark"] as const) {
  test.describe(`axe, in the ${theme} theme`, () => {
    test.beforeEach(async ({ page, tasks }) => {
      await page.addInitScript((theme) => localStorage.setItem("phx:theme", theme), theme)
      await tasks.open()
      await expect(page.locator("html")).toHaveAttribute("data-theme", theme)
    })

    test("with the list open, and with columns hidden", async ({ page, tasks }) => {
      await tasks.columnsButton.click()
      await expect(tasks.columnsList).toBeVisible()
      await expectNoAxeViolations(page)

      await tasks.hide("status", "priority", "due_on")
      await expectNoAxeViolations(page)
    })

    test("with columns hidden and the list closed, and with a hidden column that is filtered by", async ({
      page,
      tasks,
    }) => {
      await tasks.filterValue("progress").fill("100")
      await tasks.reads(() => tasks.filterValue("progress").press("Enter"))
      await tasks.hide("progress", "status")
      await expect(tasks.columnFlag("progress")).toBeVisible()
      await expect(tasks.columnsButton).toHaveText("Columns (2 hidden, 1 filtered)")
      await tasks.columnBox("progress").focus()
      await expectNoAxeViolations(page)

      await page.keyboard.press("Escape")
      await expect(tasks.columnsList).toBeHidden()
      await expectNoAxeViolations(page)
    })

    test("in a nested table, and where one column has to stay", async ({ page, tasks }) => {
      const comments = await tasks.openLine(FIRST, "comments")
      const columns = await comments.columns()
      await comments.hide(...columns.slice(1))
      await expect(comments.columnBox(columns[0])).toBeDisabled()
      await expectNoAxeViolations(page)
      await page.keyboard.press("Escape")
      await expectNoAxeViolations(page)
    })
  })
}
