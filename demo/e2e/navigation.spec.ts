import { expect, test } from "./support/fixtures"

// Spec section 8: the grid is one tab stop, and the arrow keys move in it
// without a word to the server. /tasks as the admin: 17 columns, 25 rows,
// before the first column the expanders of the rows (nesting.spec.ts), and
// after the last the buttons of their actions (actions.spec.ts).

const FIRST = "title"
const SECOND = "status"
const LAST = "reporter"

test.beforeEach(async ({ tasks }) => {
  await tasks.open()
})

test("the grid is one tab stop: Tab enters it and leaves it", async ({ page, tasks }) => {
  const first = await tasks.rowKey(1)
  expect(await tasks.tabStops()).toEqual([`task-row-${first}-c-${FIRST}`])

  // backwards from the pagination, which is outside the grid ("Previous" is
  // disabled on the first page)
  await tasks.pageButton(1).focus()
  await page.keyboard.press("Shift+Tab")
  await expect(tasks.cell(first, FIRST)).toBeFocused()

  // one more leaves the grid at its other end: the header rows are no stops
  await page.keyboard.press("Shift+Tab")
  expect(await tasks.hasFocus()).toBe(false)

  await page.keyboard.press("Tab")
  await expect(tasks.cell(first, FIRST)).toBeFocused()
  await page.keyboard.press("Tab")
  await expect(tasks.pageButton(1)).toBeFocused()
  await page.keyboard.press("Shift+Tab")

  // the cell a person moved to is where Tab comes back to
  await tasks.press("ArrowDown", "ArrowRight", "Tab", "Shift+Tab")
  await expect(tasks.cell(await tasks.rowKey(2), SECOND)).toBeFocused()
  expect(await tasks.tabStops()).toHaveLength(1)
})

test("arrow keys move one cell and do not wrap", async ({ tasks }) => {
  const keys = await tasks.rowKeys()
  const [first, second] = keys
  const last = keys.at(-1)!

  await tasks.cell(first, FIRST).focus()
  await tasks.press("ArrowRight")
  await expect(tasks.cell(first, SECOND)).toBeFocused()
  await tasks.press("ArrowLeft")
  await expect(tasks.cell(first, FIRST)).toBeFocused()
  // one more reaches the row's expander, and one more the box that selects
  // the row, which is the first cell of the row
  await tasks.press("ArrowLeft")
  await expect(tasks.expanderCell(first)).toBeFocused()
  await tasks.press("ArrowLeft")
  await expect(tasks.boxCell(first)).toBeFocused()
  await tasks.press("ArrowLeft")
  await expect(tasks.boxCell(first), "the first cell of a row is where Left ends").toBeFocused()

  await tasks.cell(first, FIRST).focus()
  await tasks.press("ArrowDown")
  await expect(tasks.cell(second, FIRST)).toBeFocused()
  await tasks.press("ArrowUp")
  await expect(tasks.cell(first, FIRST)).toBeFocused()

  // after the last column is the cell of the row's actions
  await tasks.cell(first, LAST).focus()
  await tasks.press("ArrowRight")
  await expect(tasks.actionsCell(first)).toBeFocused()
  await tasks.press("ArrowRight")
  await expect(tasks.actionsCell(first), "the last cell of a row is where Right ends").toBeFocused()

  // under the last record is the footer row of the summaries (footer.spec.ts)
  await tasks.cell(last, SECOND).focus()
  await tasks.press("ArrowDown")
  await expect(tasks.summary(SECOND)).toBeFocused()
  await tasks.press("ArrowDown")
  await expect(tasks.summary(SECOND), "the last row is where Down ends").toBeFocused()
})

test("Home and End go to the ends of the row, with Ctrl to the corners of the data", async ({
  tasks,
}) => {
  const keys = await tasks.rowKeys()
  const first = keys[0]
  const third = keys[2]
  const last = keys.at(-1)!

  await tasks.cell(third, "progress").focus()
  // the last cell of a row holds its actions
  await tasks.press("End")
  await expect(tasks.actionsCell(third)).toBeFocused()
  // the first cell of a row is the box that selects it
  await tasks.press("Home")
  await expect(tasks.boxCell(third)).toBeFocused()

  await tasks.press("Control+End")
  await expect(tasks.actionsCell(last)).toBeFocused()
  await tasks.press("Control+Home")
  await expect(tasks.boxCell(first), "the first data row, not the header").toBeFocused()
})

test("Page Down and Page Up move by a screenful and stay in the data rows", async ({ tasks }) => {
  const keys = await tasks.rowKeys()
  const position = async () => {
    const focused = await tasks.focused()
    expect(focused, "focus stays in the column").toMatch(/-c-priority$/)
    return keys.findIndex((key) => focused === `task-row-${key}-c-priority`)
  }

  await tasks.cell(keys[0], "priority").focus()
  await tasks.press("PageDown")
  const down = await position()
  expect(down, "several rows down").toBeGreaterThan(1)

  await tasks.press("PageUp")
  expect(await position()).toBe(0)
  await tasks.press("PageUp")
  expect(await position(), "the first data row is where Page Up ends").toBe(0)

  await tasks.press("PageDown", "PageDown", "PageDown", "PageDown")
  expect(await position(), "the last row is where Page Down ends").toBe(keys.length - 1)
})

test("Up from the first data row reaches the filter row, then the header", async ({ tasks }) => {
  const first = await tasks.rowKey(1)

  await tasks.cell(first, FIRST).focus()
  await tasks.press("ArrowUp")
  await expect(tasks.filterCell(FIRST)).toBeFocused()
  await tasks.press("ArrowUp")
  await expect(tasks.header(FIRST)).toBeFocused()
  await tasks.press("ArrowUp")
  await expect(tasks.header(FIRST), "the header is where Up ends").toBeFocused()

  await tasks.press("ArrowRight")
  await expect(tasks.header(SECOND)).toBeFocused()
  await tasks.press("ArrowDown")
  await expect(tasks.filterCell(SECOND)).toBeFocused()
  await tasks.press("ArrowLeft")
  await expect(tasks.filterCell(FIRST)).toBeFocused()
  await tasks.press("ArrowDown")
  await expect(tasks.cell(first, FIRST)).toBeFocused()

  // the header row has every column, the ones without a sort too; of the
  // filter row only the cells that hold a filter are stops
  await tasks.press("End", "ArrowUp")
  await expect(tasks.actionsHeader, "past the empty filter cell of the actions").toBeFocused()
  await tasks.press("ArrowLeft")
  await expect(tasks.header(LAST)).toBeFocused()
  await tasks.press("ArrowDown")
  await expect(tasks.cell(first, LAST), "past the empty filter cell of a column without a filter").toBeFocused()
  await tasks.press("ArrowUp", "ArrowLeft", "ArrowDown")
  await expect(tasks.cell(first, "assignee")).toBeFocused()
  expect(await tasks.tabStops()).toEqual([`task-row-${first}-c-assignee`])
})

test("moving about sends nothing to the server", async ({ tasks, pushed }) => {
  await tasks.cell(await tasks.rowKey(1), FIRST).focus()
  await pushed.clear()

  await tasks.press("ArrowRight", "ArrowDown", "ArrowLeft", "ArrowUp")
  await tasks.press("End", "Home", "Control+End", "Control+Home", "PageDown", "PageUp")
  await tasks.press("ArrowUp", "ArrowUp", "ArrowRight", "ArrowDown", "ArrowDown")

  expect(await pushed.all()).toEqual([])
  expect(await tasks.tabStops()).toHaveLength(1)
})

test("a click on a cell moves focus and the tab stop to it", async ({ tasks }) => {
  const second = await tasks.rowKey(2)

  await tasks.cell(second, "headline").click()
  await expect(tasks.cell(second, "headline")).toBeFocused()
  expect(await tasks.tabStops()).toEqual([`task-row-${second}-c-headline`])

  await tasks.press("ArrowLeft")
  await expect(tasks.cell(second, "comment_count")).toBeFocused()
})

test("Space on a cell selects its row, and does nothing else", async ({ page, tasks, pushed }) => {
  const first = await tasks.rowKey(1)
  const cell = tasks.cell(first, FIRST)
  const text = await cell.textContent()

  await cell.focus()
  await pushed.clear()
  await page.keyboard.press("Space")

  // what selecting is and lasts through is in selection.spec.ts
  expect(await tasks.selectedKeys()).toEqual([first])
  await expect(cell).toBeFocused()
  await expect(cell).toHaveText(text!)
  await expect(tasks.openEditors).toHaveCount(0)
  expect(await page.evaluate(() => window.scrollY), "the page does not scroll").toBe(0)
  await pushed.expectSelected(tasks)
  expect(await pushed.besides("select")).toEqual([])
})

test.describe(() => {
  test.use({ actor: "viewer" })

  test("Space does nothing on a cell of a table whose rows cannot be selected", async ({
    page,
    tasks,
    pushed,
  }) => {
    const first = await tasks.rowKey(1)
    const cell = tasks.cell(first, FIRST)
    const text = await cell.textContent()

    await cell.focus()
    await pushed.clear()
    await page.keyboard.press("Space")

    await expect(tasks.grid.locator("[aria-selected]")).toHaveCount(0)
    await expect(cell).toBeFocused()
    await expect(cell).toHaveText(text!)
    await expect(tasks.openEditors).toHaveCount(0)
    expect(await page.evaluate(() => window.scrollY), "the page does not scroll").toBe(0)
    expect(await pushed.all()).toEqual([])
  })
})

test.describe("focus after a patch", () => {
  test("it stays on the header a sort was started from", async ({ tasks }) => {
    await tasks.header(FIRST).focus()
    await tasks.reads(() => tasks.press("Enter"))

    await expect(tasks.header(FIRST)).toHaveAttribute("aria-sort", "ascending")
    await expect(tasks.header(FIRST)).toBeFocused()
    expect(await tasks.tabStops()).toEqual(["task-head-title"])
  })

  test("it stays on a cell that is still there when the rows are replaced, and else goes to the cell at the same place", async ({
    page,
    tasks,
  }) => {
    const unsorted = await tasks.rowKeys()
    await tasks.reads(() => tasks.header("progress").click())
    const sorted = await tasks.rowKeys()
    const kept = sorted.find((key) => unsorted.includes(key))!
    const gone = sorted.findIndex((key) => !unsorted.includes(key))
    expect(kept, "a row on both pages").toBeDefined()
    expect(gone, "a row on the sorted page only").toBeGreaterThan(-1)

    // the back button undoes the sort: the row is on the page again, elsewhere
    await tasks.cell(kept, "progress").focus()
    await tasks.reads(() => page.goBack())
    expect(await tasks.rowKeys()).toEqual(unsorted)
    await expect(tasks.cell(kept, "progress")).toBeFocused()
    expect(await tasks.tabStops()).toEqual([`task-row-${kept}-c-progress`])

    // the row is not on the page any more: the cell where it was
    await tasks.reads(() => page.goForward())
    await tasks.cell(sorted[gone], "priority").focus()
    await tasks.reads(() => page.goBack())
    await expect(tasks.cell(unsorted[gone], "priority")).toBeFocused()
    expect(await tasks.tabStops()).toEqual([`task-row-${unsorted[gone]}-c-priority`])
  })

  test("after a page change the grid's tab stop is the cell at the same place", async ({
    page,
    tasks,
  }) => {
    const pageOne = await tasks.rowKeys()
    await tasks.cell(pageOne[1], SECOND).focus()

    await tasks.reads(() => tasks.next.click())
    await expect(tasks.range).toHaveText("26–50 of 320")

    const pageTwo = await tasks.rowKeys()
    expect(pageTwo).not.toEqual(pageOne)
    expect(await tasks.tabStops()).toEqual([`task-row-${pageTwo[1]}-c-${SECOND}`])

    // and focus that is in the grid when the rows go stays in the grid
    await tasks.cell(pageTwo[4], FIRST).focus()
    await tasks.reads(() => page.goBack())
    await expect(tasks.range).toHaveText("1–25 of 320")
    await expect(tasks.cell(pageOne[4], FIRST)).toBeFocused()
  })
})
