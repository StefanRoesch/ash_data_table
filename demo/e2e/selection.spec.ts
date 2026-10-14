import type { Page } from "@playwright/test"
import { expectNoAxeViolations } from "./support/a11y"
import { storageStateOf } from "./support/actors"
import { contrastOf } from "./support/contrast"
import { SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { switchLocale } from "./support/locale"
import { Table } from "./support/table"

// Row selection and the actions on the selected rows, in a browser: the
// boxes by pointer and by keyboard, what a selection lasts through, "all
// that match", the line above the grid, and what running an action on a
// selection looks like from the question to the result.
//
// /tasks as the admin, who may run every action on every task, unless a
// test says otherwise. Which rows are selected is known to the table's hook
// alone: the server renders the boxes and learns of a selection when a
// button of the line is used. The tests that run an action change the data
// and say so (`writes`).

const FIRST = SEED.task.first
const SECOND = SEED.task.second
const THIRD = SEED.task.third

const REFUSED = "You are not allowed to do this."

test.beforeEach(async ({ tasks }) => {
  await tasks.open()
})

/** The dialog has closed and the hook has heard of it (see editing.spec.ts). */
async function answered(table: Table): Promise<void> {
  await expect(table.question).toBeHidden()
  await table.page.evaluate(() => new Promise((resolve) => setTimeout(resolve, 0)))
}

/** Answers the question of an action on the selected rows with Confirm, and waits for what it came to. */
async function confirmed(table: Table): Promise<void> {
  await expect(table.question).toBeVisible()
  await table.question.getByRole("button", { name: "Confirm" }).click()
  await expect(table.result).toBeVisible()
  await expect(table.grid).not.toHaveAttribute("aria-busy", "true")
}

/** The keys of the rows of the page whose cell of a column reads `text`. */
async function keysWhere(table: Table, column: string, text: string): Promise<string[]> {
  const keys = await table.rowKeys()
  const texts = await table.columnTexts(column)
  return keys.filter((_key, index) => texts[index].trim() === text)
}

test.describe("the boxes", () => {
  test("are the first column of the grid: one in every row, one in the header for the page, and an empty filter cell", async ({
    tasks,
  }) => {
    // the boxes, the expanders, the twenty-two columns of the table, the actions
    await expect(tasks.grid).toHaveAttribute("aria-colcount", "25")
    await expect(tasks.grid).toHaveAttribute("aria-multiselectable", "true")
    await expect(tasks.headerCells.first()).toHaveId("task-select-head")
    await expect(tasks.pageBoxCell).toHaveRole("columnheader")
    await expect(tasks.pageBoxCell).toHaveAttribute("aria-colindex", "1")
    await expect(tasks.pageBox).toHaveAccessibleName("Select all rows of this page")
    await expect(tasks.pageBox).not.toBeChecked()

    await expect(tasks.rowCells(FIRST).first()).toHaveId(`task-row-${FIRST}-s`)
    await expect(tasks.boxCell(FIRST)).toHaveRole("gridcell")
    await expect(tasks.boxCell(FIRST)).toHaveAttribute("aria-colindex", "1")
    await expect(tasks.box(FIRST)).toHaveAccessibleName("Select row")
    await expect(tasks.boxes).toHaveCount(25)

    // the expander is the cell after it, and the first column the one after that
    await expect(tasks.rowCells(FIRST).nth(1)).toHaveId(`task-row-${FIRST}-e`)
    await expect(tasks.expanderCell(FIRST)).toHaveAttribute("aria-colindex", "2")
    await expect(tasks.cell(FIRST, "title")).toHaveAttribute("aria-colindex", "3")

    // no box is a tab stop: the grid is one, and it is where it was
    for (const box of [tasks.pageBox, tasks.box(FIRST)]) await expect(box).toHaveAttribute("tabindex", "-1")
    expect(await tasks.tabStops()).toEqual([`task-row-${FIRST}-c-title`])
  })

  test("every row says whether it is selected, and none is at first", async ({ tasks }) => {
    const said = await tasks.rows.evaluateAll((rows) =>
      rows.map((row) => (row as HTMLTableSectionElement).rows[0].getAttribute("aria-selected")),
    )
    expect(said).toEqual(Array(25).fill("false"))
    expect(await tasks.selectedKeys()).toEqual([])

    // the rows of the header say nothing of it: they cannot be selected
    await expect(tasks.grid.locator(":scope > thead > tr[aria-selected]")).toHaveCount(0)

    // nothing is selected: the line holds no text and shows no button
    await expect(tasks.selectionLine).toHaveRole("group")
    await expect(tasks.selectionLine).toHaveAccessibleName("Selected rows")
    await expect(tasks.selectedCount).toHaveText("")
    await expect(tasks.clearSelection).toBeHidden()
    await expect(tasks.bulkButtons.first()).toBeHidden()
  })

  test("make a row no higher, and take nothing from the grid's width that a row needs", async ({
    browser,
    page,
    tasks,
  }) => {
    const height = (await tasks.rowLine(FIRST).boundingBox())!.height
    const box = (await tasks.box(FIRST).boundingBox())!
    const cell = (await tasks.boxCell(FIRST).boundingBox())!
    // the box stands in the middle of its cell
    expect(Math.abs(box.y + box.height / 2 - (cell.y + cell.height / 2))).toBeLessThanOrEqual(1)

    // a viewer can run no action, and has no boxes
    const context = await browser.newContext({
      storageState: storageStateOf("viewer"),
      baseURL: new URL(page.url()).origin,
      viewport: page.viewportSize(),
    })
    try {
      const other = new Table(await context.newPage(), "task", "/tasks")
      await other.open()
      await expect(other.boxes).toHaveCount(0)
      expect((await other.rowLine(FIRST).boundingBox())!.height).toBeCloseTo(height, 0)
    } finally {
      await context.close()
    }
  })

  for (const actor of ["viewer", "nobody"] as const) {
    test.describe(() => {
      test.use({ actor })

      test(`are not there for the ${actor}, who can run no action`, async ({ tasks }) => {
        await expect(tasks.pageBoxCell).toHaveCount(0)
        await expect(tasks.grid.locator("[data-selector]")).toHaveCount(0)
        await expect(tasks.selectionLine).toHaveCount(0)
        await expect(tasks.grid).not.toHaveAttribute("aria-multiselectable")
        await expect(tasks.grid.locator("tr[aria-selected]")).toHaveCount(0)
      })
    })
  }
})

test.describe("selecting with the pointer", () => {
  test("a click on a row's box selects the row, and another takes it out", async ({ tasks, frames }) => {
    await frames.clear()
    await tasks.box(SECOND).click()

    await expect(tasks.box(SECOND)).toBeChecked()
    await expect(tasks.rowLine(SECOND)).toHaveAttribute("aria-selected", "true")
    await expect(tasks.rowLine(FIRST)).toHaveAttribute("aria-selected", "false")
    expect(await tasks.selectedKeys()).toEqual([SECOND])
    await expect(tasks.selectedCount).toHaveText("1 selected")
    await expect(tasks.clearSelection).toBeVisible()
    await expect(tasks.bulkButtons).toHaveText(["Archive", "Reassign", "Set progress", "Destroy", "Set labels"])
    // focus is on the box's cell, which is the grid's tab stop now
    expect(await tasks.focused()).toBe(`task-row-${SECOND}-s`)

    await tasks.box(SECOND).click()
    await expect(tasks.box(SECOND)).not.toBeChecked()
    expect(await tasks.selectedKeys()).toEqual([])
    await expect(tasks.selectedCount).toHaveText("")
    await expect(tasks.clearSelection).toBeHidden()

    expect(await frames.all(), "selecting sends nothing").toEqual([])
  })

  test("a click beside the box, in its cell, does the same", async ({ tasks }) => {
    const cell = (await tasks.boxCell(FIRST).boundingBox())!
    await tasks.page.mouse.click(cell.x + 2, cell.y + 2)

    await expect(tasks.box(FIRST)).toBeChecked()
    expect(await tasks.selectedKeys()).toEqual([FIRST])
  })

  test("the box in the header selects every row of the page, is mixed while some are selected, and takes all out again", async ({
    tasks,
    frames,
  }) => {
    const mixed = () => tasks.pageBox.evaluate((box) => (box as HTMLInputElement).indeterminate)
    await frames.clear()

    await tasks.box(FIRST).click()
    await expect(tasks.pageBox).not.toBeChecked()
    expect(await mixed()).toBe(true)

    await tasks.pageBox.click()
    await expect(tasks.pageBox).toBeChecked()
    expect(await mixed()).toBe(false)
    expect(await tasks.selectedKeys()).toHaveLength(25)
    await expect(tasks.selectedCount).toHaveText("25 selected")
    for (const box of await tasks.boxes.all()) await expect(box).toBeChecked()

    await tasks.pageBox.click()
    await expect(tasks.pageBox).not.toBeChecked()
    expect(await tasks.selectedKeys()).toEqual([])
    await expect(tasks.selectedCount).toHaveText("")

    expect(await frames.all(), "selecting sends nothing").toEqual([])
  })

  test("Shift and a click selects the rows from the one that was selected last to this one, and no text", async ({
    tasks,
  }) => {
    const keys = await tasks.rowKeys()

    await tasks.box(keys[1]).click()
    // a click in a text is where the browser would start its own selection from
    await tasks.cell(keys[1], "title").click()
    await tasks.cell(keys[4], "title").click({ modifiers: ["Shift"] })

    expect(await tasks.selectedKeys()).toEqual(keys.slice(1, 5))
    await expect(tasks.selectedCount).toHaveText("4 selected")
    expect(await tasks.page.evaluate(() => String(window.getSelection())), "no text is selected").toBe("")
    expect(await tasks.focused()).toBe(`task-row-${keys[4]}-c-title`)

    // upwards, from the same row; it adds and takes nothing out
    await tasks.box(keys[0]).click({ modifiers: ["Shift"] })
    expect(await tasks.selectedKeys()).toEqual(keys.slice(0, 5))
  })

  test("a click on a cell without Shift selects nothing", async ({ tasks }) => {
    await tasks.cell(FIRST, "title").click()
    await tasks.cell(SECOND, "status").click()
    expect(await tasks.selectedKeys()).toEqual([])
  })
})

test.describe("selecting from the keyboard", () => {
  test("Space on any cell of a row selects the row, and takes it out again; the page does not scroll", async ({
    page,
    tasks,
    frames,
  }) => {
    await tasks.cell(FIRST, "title").focus()
    await frames.clear()

    await page.keyboard.press("Space")
    expect(await tasks.selectedKeys()).toEqual([FIRST])
    await expect(tasks.selectedCount).toHaveText("1 selected")
    // focus is where it was: the count is read out, and nothing is taken
    expect(await tasks.focused()).toBe(`task-row-${FIRST}-c-title`)

    await tasks.press("ArrowDown", "ArrowRight", "Space")
    expect(await tasks.selectedKeys()).toEqual([FIRST, SECOND])

    // on the box's own cell, and on the actions cell
    await tasks.press("Home", "ArrowDown", "Space")
    expect(await tasks.focused()).toBe(`task-row-${THIRD}-s`)
    expect(await tasks.selectedKeys()).toEqual([FIRST, SECOND, THIRD])
    await tasks.press("End", "Space")
    expect(await tasks.focused()).toBe(`task-row-${THIRD}-a`)
    expect(await tasks.selectedKeys()).toEqual([FIRST, SECOND])

    await tasks.press("ArrowUp", "Space")
    expect(await tasks.selectedKeys()).toEqual([FIRST])

    expect(await page.evaluate(() => window.scrollY)).toBe(0)
    expect(await frames.all(), "selecting and moving send nothing").toEqual([])
  })

  test("Space on a boolean cell selects the row and leaves the value alone: Enter toggles it", async ({
    page,
    tasks,
    frames,
  }) => {
    const cell = tasks.cell(FIRST, "billable?")
    const before = await cell.textContent()
    await cell.focus()
    await frames.clear()

    await page.keyboard.press("Space")

    expect(await tasks.selectedKeys()).toEqual([FIRST])
    await expect(cell).toHaveText(before!)
    expect(await frames.count("save")).toBe(0)
  })

  test("Space on the cell of the box in the header selects the rows of the page", async ({ page, tasks }) => {
    await tasks.cell(FIRST, "title").focus()
    await tasks.press("Home", "ArrowUp", "ArrowUp")
    expect(await tasks.focused()).toBe("task-select-head")

    await page.keyboard.press("Space")
    expect(await tasks.selectedKeys()).toHaveLength(25)
    await expect(tasks.pageBox).toBeChecked()

    await page.keyboard.press("Space")
    expect(await tasks.selectedKeys()).toEqual([])
  })

  test("Space on a heading, a filter cell and a relationship line selects nothing", async ({ page, tasks }) => {
    await tasks.header("title").focus()
    await page.keyboard.press("Space")
    await tasks.filterCell("title").focus()
    await page.keyboard.press("Space")

    await tasks.expand(FIRST)
    await tasks.lineCell(FIRST, "comments").focus()
    await page.keyboard.press("Space")

    expect(await tasks.selectedKeys()).toEqual([])
    await expect(tasks.selectedCount).toHaveText("")
    // nor was the filter gone into, or anything typed there
    await expect(tasks.filterValue("title")).toHaveValue("")
  })

  test("Space on a button in a cell uses the button, and selects nothing", async ({ page, tasks }) => {
    await tasks.expanderCell(FIRST).focus()
    await tasks.expander(FIRST).focus()
    await page.keyboard.press("Space")

    await expect(tasks.expander(FIRST)).toHaveAttribute("aria-expanded", "true")
    expect(await tasks.selectedKeys()).toEqual([])
  })

  test("Shift with Down Arrow and Up Arrow selects as it goes, and takes rows out on the way back", async ({
    tasks,
    frames,
  }) => {
    const keys = await tasks.rowKeys()
    await tasks.cell(keys[2], "status").focus()
    await frames.clear()

    await tasks.press("Shift+ArrowDown", "Shift+ArrowDown")
    expect(await tasks.selectedKeys()).toEqual(keys.slice(2, 5))
    // focus has moved with it, in the same column
    expect(await tasks.focused()).toBe(`task-row-${keys[4]}-c-status`)

    await tasks.press("Shift+ArrowUp")
    expect(await tasks.selectedKeys()).toEqual(keys.slice(2, 4))

    // past where it began, the other way
    await tasks.press("Shift+ArrowUp", "Shift+ArrowUp", "Shift+ArrowUp")
    expect(await tasks.selectedKeys()).toEqual(keys.slice(0, 3))
    expect(await tasks.focused()).toBe(`task-row-${keys[0]}-c-status`)

    // at the first row of records it stops: the header rows are not selected into
    await tasks.press("Shift+ArrowUp")
    expect(await tasks.focused()).toBe(`task-row-${keys[0]}-c-status`)

    // what was selected before stays, and a new range starts where the key is pressed next
    await tasks.press("ArrowDown", "ArrowDown", "ArrowDown", "ArrowDown", "ArrowDown", "Shift+ArrowDown")
    expect(await tasks.selectedKeys()).toEqual([...keys.slice(0, 3), keys[5], keys[6]])

    expect(await frames.all(), "none of it is sent").toEqual([])
  })

  test("Shift with an arrow key passes over what is open under a row", async ({ tasks }) => {
    const keys = await tasks.rowKeys()
    await tasks.expand(keys[0])
    await tasks.cell(keys[0], "title").focus()

    await tasks.press("Shift+ArrowDown")

    expect(await tasks.focused()).toBe(`task-row-${keys[1]}-c-title`)
    expect(await tasks.selectedKeys()).toEqual(keys.slice(0, 2))
  })

  test("the arrow keys still send nothing, and the tab stop is still one, while rows are selected", async ({
    tasks,
    frames,
  }) => {
    await tasks.cell(FIRST, "title").focus()
    await tasks.press("Space")
    await frames.clear()

    await tasks.press("ArrowDown", "ArrowRight", "ArrowDown", "ArrowLeft", "End", "Home", "PageDown", "Control+Home")

    expect(await frames.all()).toEqual([])
    expect(await tasks.tabStops()).toHaveLength(1)
    expect(await tasks.selectedKeys()).toEqual([FIRST])
  })

  test("Left Arrow from the first column reaches the expander and then the box; Tab enters on the first column", async ({
    page,
    tasks,
  }) => {
    await page.keyboard.press("Tab")
    while (!(await tasks.hasFocus())) await page.keyboard.press("Tab")
    expect(await tasks.focused()).toBe(`task-row-${FIRST}-c-title`)

    await tasks.press("ArrowLeft")
    expect(await tasks.focused()).toBe(`task-row-${FIRST}-e`)
    await tasks.press("ArrowLeft")
    expect(await tasks.focused()).toBe(`task-row-${FIRST}-s`)
    await tasks.press("ArrowLeft")
    expect(await tasks.focused()).toBe(`task-row-${FIRST}-s`)
  })

  test("the buttons of the line are reached with Shift+Tab from the grid, and used with Enter", async ({
    page,
    tasks,
  }) => {
    await tasks.cell(FIRST, "title").focus()
    // "Columns" (hiding.spec.ts) stands between the line's buttons and the grid
    await tasks.press("Space", "Shift+Tab")
    expect(await tasks.focused()).toBe("task-columns-button")
    await tasks.press("Shift+Tab")
    expect(await tasks.focused()).toBe("task-bulk-set_labels")
    await tasks.press("Shift+Tab", "Shift+Tab", "Shift+Tab", "Shift+Tab", "Shift+Tab")
    expect(await tasks.focused()).toBe("task-clear-selection")

    await page.keyboard.press("Enter")
    expect(await tasks.selectedKeys()).toEqual([])
    // the button went with the selection: focus is back in the grid
    expect(await tasks.focused()).toBe(`task-row-${FIRST}-c-title`)
  })
})

test.describe("a selection", () => {
  test("lasts through a change of page and a sort, and counts the rows of other pages", async ({ tasks }) => {
    await tasks.box(FIRST).click()
    await tasks.box(THIRD).click()

    await tasks.reads(() => tasks.next.click())
    expect(await tasks.selectedKeys()).toEqual([])
    await expect(tasks.selectedCount).toHaveText("2 selected")
    await expect(tasks.pageBox).not.toBeChecked()

    const [onSecondPage] = await tasks.rowKeys()
    await tasks.box(onSecondPage).click()
    await expect(tasks.selectedCount).toHaveText("3 selected")

    await tasks.reads(() => tasks.previous.click())
    expect(await tasks.selectedKeys()).toEqual([FIRST, THIRD])
    await expect(tasks.box(FIRST)).toBeChecked()
    await expect(tasks.selectedCount).toHaveText("3 selected")

    await tasks.reads(() => tasks.header("inserted_at").click())
    await expect(tasks.selectedCount).toHaveText("3 selected")
  })

  test("is given up when a filter changes", async ({ page, tasks }) => {
    await tasks.box(FIRST).click()
    await tasks.box(SECOND).click()

    await tasks.filterCell("title").focus()
    await page.keyboard.press("Enter")
    await tasks.reads(async () => {
      await page.keyboard.type("email")
      await page.keyboard.press("Enter")
    })

    await expect(tasks.selectedCount).toHaveText("")
    expect(await tasks.selectedKeys()).toEqual([])
    await expect(tasks.clearSelection).toBeHidden()
    for (const box of await tasks.boxes.all()) await expect(box).not.toBeChecked()

    // and is not back with the filter gone
    await tasks.reads(() => tasks.clearFilters.click())
    await expect(tasks.selectedCount).toHaveText("")
    expect(await tasks.selectedKeys()).toEqual([])
  })

  test.describe(() => {
    test.use({ writes: true })

    test("lasts through a save of one of its rows, whose row comes back from the server", async ({
      page,
      tasks,
    }) => {
      await tasks.box(FIRST).click()
      const title = tasks.cell(FIRST, "title")
      await title.focus()
      await page.keyboard.press("Enter")
      await tasks.retype("Renamed while selected")
      await tasks.saves(title, () => page.keyboard.press("Enter"))

      await expect(title).toHaveText("Renamed while selected")
      await expect(tasks.rowLine(FIRST)).toHaveAttribute("aria-selected", "true")
      await expect(tasks.box(FIRST)).toBeChecked()
      await expect(tasks.selectedCount).toHaveText("1 selected")
    })

    test("loses a row that its own action takes away", async ({ tasks }) => {
      await tasks.box(FIRST).click()
      await tasks.box(SECOND).click()

      await tasks.action(FIRST, "destroy").click()
      await tasks.question.getByRole("button", { name: "Confirm" }).click()
      await expect(tasks.row(FIRST)).toHaveCount(0)

      await expect(tasks.selectedCount).toHaveText("1 selected")
      expect(await tasks.selectedKeys()).toEqual([SECOND])
    })
  })
})

test.describe("all that match", () => {
  test("is offered once every row of the page is selected, and selects on every page", async ({ tasks }) => {
    await tasks.box(FIRST).click()
    await expect(tasks.selectAll).toBeHidden()

    await tasks.pageBox.click()
    await expect(tasks.selectAll).toBeVisible()
    await expect(tasks.selectAll).toHaveText(`Select all ${SEED.tasks.acme} that match`)

    await tasks.selectAll.click()
    await expect(tasks.selectedCount).toHaveText(`All ${SEED.tasks.acme} that match are selected`)
    await expect(tasks.selectAll).toBeHidden()
    // the button is gone: focus is on the one beside it
    expect(await tasks.focused()).toBe("task-clear-selection")

    await tasks.reads(() => tasks.next.click())
    expect(await tasks.selectedKeys()).toHaveLength(25)
    await expect(tasks.pageBox).toBeChecked()
    await expect(tasks.selectedCount).toHaveText(`All ${SEED.tasks.acme} that match are selected`)
  })

  test("taking one row out leaves the other rows of this page", async ({ tasks }) => {
    await tasks.pageBox.click()
    await tasks.selectAll.click()

    await tasks.box(SECOND).click()

    await expect(tasks.selectedCount).toHaveText("24 selected")
    expect(await tasks.selectedKeys()).toHaveLength(24)
    await expect(tasks.box(SECOND)).not.toBeChecked()
    await expect(tasks.selectAll, "the page is not all selected any more").toBeHidden()
  })

  test("the box in the header clears it, and so does a filter", async ({ page, tasks }) => {
    await tasks.pageBox.click()
    await tasks.selectAll.click()
    await tasks.pageBox.click()
    await expect(tasks.selectedCount).toHaveText("")
    expect(await tasks.selectedKeys()).toEqual([])

    await tasks.pageBox.click()
    await tasks.selectAll.click()
    await tasks.filterCell("title").focus()
    await page.keyboard.press("Enter")
    await tasks.reads(async () => {
      await page.keyboard.type("email")
      await page.keyboard.press("Enter")
    })
    await expect(tasks.selectedCount).toHaveText("")
    expect(await tasks.selectedKeys()).toEqual([])
  })

  test("is not offered where the page is all there is", async ({ page, tasks }) => {
    await tasks.filterCell("title").focus()
    await page.keyboard.press("Enter")
    await tasks.reads(async () => {
      await page.keyboard.type("onboarding email")
      await page.keyboard.press("Enter")
    })
    expect((await tasks.rowKeys()).length).toBeLessThan(25)

    await tasks.pageBox.click()
    await expect(tasks.clearSelection).toBeVisible()
    await expect(tasks.selectAll).toBeHidden()
  })

  test("on a table that pages by keyset, with the number its action counts", async ({ page }) => {
    const comments = new Table(page, "comment", "/comments")
    await comments.open()

    await comments.pageBox.click()
    await expect(comments.selectAll).toHaveText(`Select all ${SEED.comments.acme} that match`)
    await comments.selectAll.click()
    await expect(comments.selectedCount).toHaveText(`All ${SEED.comments.acme} that match are selected`)
  })
})

test.describe("the line above the grid", () => {
  test("says how many rows are selected in a live region, and leaves the focus where it is", async ({
    page,
    tasks,
  }) => {
    await expect(tasks.selectedCount).toHaveRole("status")
    await tasks.cell(FIRST, "title").focus()

    // what a screen reader is told is what the region comes to hold
    await page.evaluate(() => {
      const said: string[] = []
      ;(window as any).__said = said
      new MutationObserver(() => said.push(document.getElementById("task-selected")!.textContent!)).observe(
        document.getElementById("task-selected")!,
        { childList: true, characterData: true, subtree: true },
      )
    })

    await tasks.press("Space", "ArrowDown", "Space", "ArrowDown", "ArrowDown", "Space", "Space")

    expect(await page.evaluate(() => (window as any).__said)).toEqual([
      "1 selected",
      "2 selected",
      "3 selected",
      "2 selected",
    ])
    expect(await tasks.hasFocus()).toBe(true)
  })

  test("does not move the grid when its buttons appear, and stands at the other end from Clear filters", async ({
    page,
    tasks,
  }) => {
    const top = async () => (await tasks.grid.boundingBox())!.y
    const before = await top()

    await tasks.box(FIRST).click()
    await expect(tasks.clearSelection).toBeVisible()
    expect(await top()).toBe(before)

    await tasks.pageBox.click()
    await expect(tasks.selectAll).toBeVisible()
    expect(await top()).toBe(before)

    // a filter takes the selection with it, and leaves its own button at the right
    await tasks.filterCell("title").focus()
    await page.keyboard.press("Enter")
    await tasks.reads(async () => {
      await page.keyboard.type("email")
      await page.keyboard.press("Enter")
    })
    await tasks.box((await tasks.rowKeys())[0]).click()
    const clear = (await tasks.clearSelection.boundingBox())!
    const filters = (await tasks.clearFilters.boundingBox())!
    expect(clear.x).toBeLessThan(filters.x)
    expect(Math.abs(clear.y - filters.y)).toBeLessThanOrEqual(1)
    expect(await top()).toBe(before)
  })

  test("Clear selection takes every row out, on every page, and sends focus to the grid", async ({ tasks }) => {
    await tasks.box(FIRST).click()
    await tasks.reads(() => tasks.next.click())
    await tasks.pageBox.click()
    await expect(tasks.selectedCount).toHaveText("26 selected")

    await tasks.clearSelection.click()

    await expect(tasks.selectedCount).toHaveText("")
    expect(await tasks.selectedKeys()).toEqual([])
    expect(await tasks.hasFocus()).toBe(true)

    await tasks.reads(() => tasks.previous.click())
    expect(await tasks.selectedKeys()).toEqual([])
  })
})

test.describe("an action on the selected rows", () => {
  test.use({ writes: true })

  test("asks first, with the number of records; Cancel and Escape run nothing", async ({ page, tasks, frames }) => {
    await tasks.box(FIRST).click()
    await tasks.box(SECOND).click()
    await tasks.box(THIRD).click()
    await frames.clear()

    await tasks.bulk("archive").click()
    await expect(tasks.question).toBeVisible()
    await expect(tasks.question.locator("p")).toHaveText("Run “Archive” on 3 records?")
    await expect(tasks.question.getByRole("button", { name: "Confirm" })).toHaveClass(/btn-primary/)
    // focus is on Cancel, the safe answer
    await expect(tasks.question.getByRole("button", { name: "Cancel" })).toBeFocused()

    await tasks.question.getByRole("button", { name: "Cancel" }).click()
    await answered(tasks)
    expect(await tasks.focused()).toBe("task-bulk-archive")

    await tasks.bulk("archive").click()
    await expect(tasks.question).toBeVisible()
    await page.keyboard.press("Escape")
    await answered(tasks)

    expect(await frames.count("bulk")).toBe(2)
    expect(await frames.count("bulk_run")).toBe(0)
    await expect(tasks.cell(FIRST, "status")).not.toHaveText("Archived")
    await expect(tasks.selectedCount).toHaveText("3 selected")
    await expect(tasks.result).toHaveCount(0)
  })

  test("runs on the selected rows, says how many were done, reads the table again, and leaves nothing selected", async ({
    tasks,
    frames,
  }) => {
    await tasks.box(FIRST).click()
    await tasks.box(THIRD).click()
    await frames.clear()

    await tasks.bulk("archive").click()
    await confirmed(tasks)

    await expect(tasks.result).toHaveText("Archive: 2 done.")
    await expect(tasks.status).toHaveText("Archive: 2 done.")
    await expect(tasks.cell(FIRST, "status")).toHaveText("Archived")
    await expect(tasks.cell(THIRD, "status")).toHaveText("Archived")
    await expect(tasks.cell(SECOND, "status")).not.toHaveText("Archived")

    await expect(tasks.selectedCount).toHaveText("")
    expect(await tasks.selectedKeys()).toEqual([])
    await expect(tasks.bulk("archive")).toBeHidden()
    // the buttons are gone: focus is in the grid
    expect(await tasks.hasFocus()).toBe(true)

    expect(await frames.count("bulk")).toBe(1)
    expect(await frames.count("bulk_run")).toBe(1)
  })

  test("what it came to stays through a sort, and goes when something else is selected", async ({ tasks }) => {
    await tasks.box(FIRST).click()
    await tasks.bulk("archive").click()
    await confirmed(tasks)

    await tasks.reads(() => tasks.header("title").click())
    await expect(tasks.result).toHaveText("Archive: 1 done.")

    await tasks.box((await tasks.rowKeys())[0]).click()
    await expect(tasks.result).toHaveCount(0)
  })

  test("a destroy asks its own question with the number after it, in the error colour, and takes the rows away", async ({
    tasks,
  }) => {
    await tasks.box(FIRST).click()
    await tasks.box(SECOND).click()

    await tasks.bulk("destroy").click()
    await expect(tasks.question.locator("p")).toHaveText(
      "Delete this task? This cannot be undone. 2 records are selected.",
    )
    await expect(tasks.question.getByRole("button", { name: "Confirm" })).toHaveClass(/btn-error/)
    await confirmed(tasks)

    await expect(tasks.result).toHaveText("Destroy: 2 done.")
    await expect(tasks.row(FIRST)).toHaveCount(0)
    await expect(tasks.row(SECOND)).toHaveCount(0)
    await expect(tasks.range).toHaveText(`1–25 of ${SEED.tasks.acme - 2}`)
    expect(await tasks.hasFocus()).toBe(true)
    expect(await tasks.tabStops()).toHaveLength(1)
  })

  test("with inputs opens its panel once, with empty fields, and gives every record what they hold", async ({
    page,
    tasks,
    frames,
  }) => {
    await tasks.box(FIRST).click()
    await tasks.box(SECOND).click()

    await tasks.bulk("reassign").click()
    await expect(tasks.panel).toBeVisible()
    await expect(tasks.panelTitle).toHaveText("Reassign: 2 records")
    expect(await tasks.fields()).toEqual(["assignee_id", "reason"])
    await expect(tasks.fieldKey("assignee_id")).toHaveValue("")
    await expect(tasks.fieldChosen("assignee_id")).toHaveCount(0)
    await expect(tasks.field("reason")).toHaveValue("")

    // what the action makes of a value is at its field as it is typed
    await tasks.field("reason").fill("No")
    await tasks.panelSettled()
    await expect(tasks.fieldError("reason")).toHaveText("length must be greater than or equal to 3")

    // "Run" asks first; the action refuses the reason, and the panel stays
    await tasks.panelSubmit.click()
    await expect(tasks.question.locator("p")).toHaveText("Run “Reassign” on 2 records?")
    await tasks.question.getByRole("button", { name: "Confirm" }).click()
    await answered(tasks)
    await tasks.panelSettled()
    await expect(tasks.panel).toBeVisible()
    await expect(tasks.fieldError("reason")).toBeVisible()
    await expect(tasks.result).toHaveCount(0)

    await frames.clear()
    await tasks.field("reason").fill("Back from leave")
    await tasks.panelSettled()
    await tasks.panelSubmit.click()
    await tasks.question.getByRole("button", { name: "Confirm" }).click()

    await expect(tasks.panel).toHaveCount(0)
    await expect(tasks.result).toHaveText("Reassign: 2 done.")
    await expect(tasks.cell(FIRST, "assignee")).toHaveText("")
    await expect(tasks.cell(SECOND, "assignee")).toHaveText("")
    await expect(tasks.selectedCount).toHaveText("")
    expect(await tasks.hasFocus()).toBe(true)
    expect(await frames.count("panel_submit")).toBe(1)

    await page.keyboard.press("ArrowDown")
    expect(await tasks.tabStops()).toHaveLength(1)
  })

  test("Escape in its panel runs nothing and keeps the selection, with focus back on the button", async ({
    page,
    tasks,
  }) => {
    await tasks.box(FIRST).click()
    await tasks.bulk("set_progress").click()
    await expect(tasks.panelTitle).toHaveText("Set progress: 1 record")

    await page.keyboard.press("Escape")

    await expect(tasks.panel).toHaveCount(0)
    await expect(tasks.selectedCount).toHaveText("1 selected")
    await expect(tasks.result).toHaveCount(0)
    expect(await tasks.focused()).toBe("task-bulk-set_progress")
  })

  test("that a validation refuses on some rows is done on the others, and says why", async ({ tasks }) => {
    const [done] = await keysWhere(tasks, "status", "Done")
    const [todo] = await keysWhere(tasks, "status", "To do")
    await tasks.box(done).click()
    await tasks.box(todo).click()

    await tasks.bulk("set_progress").click()
    await expect(tasks.panel).toBeVisible()
    await tasks.field("progress").fill("50")
    await tasks.panelSettled()
    await tasks.panelSubmit.click()
    await confirmed(tasks)

    await expect(tasks.result.locator("[data-summary]")).toHaveText("Set progress: 1 done, 1 not done.")
    await expect(tasks.result.locator("[data-failure]")).toHaveText([
      "Progress: must be 100 when the task is done (1)",
    ])
    await expect(tasks.status).toHaveText(
      "Set progress: 1 done, 1 not done. Progress: must be 100 when the task is done (1)",
    )
    // the row it did not run on is still selected, and no other
    expect(await tasks.selectedKeys()).toEqual([done])
    await expect(tasks.selectedCount).toHaveText("1 selected")
    await expect(tasks.cell(todo, "progress")).toContainText("50")
  })

  test("on all that match runs on the rows of every page", async ({ tasks }) => {
    await tasks.pageBox.click()
    await tasks.selectAll.click()

    await tasks.bulk("archive").click()
    await expect(tasks.question.locator("p")).toHaveText(`Run “Archive” on ${SEED.tasks.acme} records?`)
    await tasks.question.getByRole("button", { name: "Confirm" }).click()
    await expect(tasks.result).toHaveText(`Archive: ${SEED.tasks.acme} done.`, { timeout: 20_000 })
    await expect(tasks.grid).not.toHaveAttribute("aria-busy", "true")

    await expect(tasks.selectedCount).toHaveText("")
    for (const text of await tasks.columnTexts("status")) expect(text).toBe("Archived")
    await tasks.reads(() => tasks.pageButton(13).click())
    for (const text of await tasks.columnTexts("status")) expect(text).toBe("Archived")
  })

  test.describe("as the member", () => {
    test.use({ actor: "member" })

    test("runs on the rows they may change; the others are counted, say why, and stay selected", async ({
      tasks,
    }) => {
      await tasks.pageBox.click()
      await tasks.bulk("archive").click()
      await confirmed(tasks)

      const summary = (await tasks.result.locator("[data-summary]").textContent())!
      const [, done, failed] = summary.match(/^Archive: (\d+) done, (\d+) not done\.$/)!.map(Number)
      expect(done + failed).toBe(25)
      expect(done).toBeGreaterThan(0)
      await expect(tasks.result.locator("[data-failure]")).toHaveText([`${REFUSED} (${failed})`])

      // the rows it was refused on, and no others
      const selected = await tasks.selectedKeys()
      expect(selected).toHaveLength(failed)
      expect(selected).toContain(FIRST)
      expect(selected).not.toContain(SEED.task.membersOwn)
      await expect(tasks.selectedCount).toHaveText(`${failed} selected`)
      await expect(tasks.cell(SEED.task.membersOwn, "status")).toHaveText("Archived")
      await expect(tasks.cell(FIRST, "status")).not.toHaveText("Archived")

      // the buttons are still there, with the focus on the one that was used
      expect(await tasks.focused()).toBe("task-bulk-archive")
    })
  })
})

test.describe("a nested table", () => {
  test("has its own boxes, its own line and its own selection", async ({ tasks, frames }) => {
    const comments = await tasks.openLine(FIRST, "comments")
    const [comment] = await comments.rowKeys()
    await frames.clear()

    await expect(comments.grid).toHaveAttribute("aria-multiselectable", "true")
    await comments.box(comment).click()

    await expect(comments.selectedCount).toHaveText("1 selected")
    await expect(comments.bulkButtons).toHaveText(["Destroy"])
    expect(await comments.selectedKeys()).toEqual([comment])
    // the table around it has none of it
    await expect(tasks.selectedCount).toHaveText("")
    expect(await tasks.selectedKeys()).toEqual([])
    await expect(tasks.clearSelection).toBeHidden()

    await tasks.box(SECOND).click()
    await expect(tasks.selectedCount).toHaveText("1 selected")
    await expect(comments.selectedCount).toHaveText("1 selected")
    expect(await comments.selectedKeys()).toEqual([comment])

    // each header's box stands for the rows of its own table: one of the
    // 25 tasks, and every comment or some of them
    const mixed = (table: Table) => table.pageBox.evaluate((box) => (box as HTMLInputElement).indeterminate)
    const every = (await comments.rowKeys()).length === 1
    expect(await mixed(tasks)).toBe(true)
    await expect(tasks.pageBox).not.toBeChecked()
    expect(await mixed(comments)).toBe(!every)
    expect(await comments.pageBox.isChecked()).toBe(every)

    await tasks.clearSelection.click()
    expect(await comments.selectedKeys()).toEqual([comment])

    // and the buttons of its line are its own: the line is inside the grid around it
    await tasks.box(SECOND).click()
    await comments.clearSelection.click()
    expect(await comments.selectedKeys()).toEqual([])
    expect(await tasks.selectedKeys()).toEqual([SECOND])
    await expect(tasks.selectedCount).toHaveText("1 selected")
    expect(await frames.all()).toEqual([])
  })

  test("Space selects in the grid that has the focus, and its buttons are reached from the keyboard", async ({
    page,
    tasks,
  }) => {
    const comments = await tasks.openLine(FIRST, "comments")
    const [comment] = await comments.rowKeys()

    await comments.cell(comment, "body").focus()
    await page.keyboard.press("Space")
    expect(await comments.selectedKeys()).toEqual([comment])
    expect(await tasks.selectedKeys()).toEqual([])

    // its "Columns" button (hiding.spec.ts) stands between them and its grid
    await page.keyboard.press("Shift+Tab")
    expect(await tasks.focused()).toBe(`${comments.id}-columns-button`)
    await page.keyboard.press("Shift+Tab")
    expect(await tasks.focused()).toBe(`${comments.id}-bulk-destroy`)
  })

  test.describe(() => {
    test.use({ writes: true })

    test("runs its action on its own rows, and stays open", async ({ tasks }) => {
      const comments = await tasks.openLine(FIRST, "comments")
      const keys = await comments.rowKeys()
      expect(keys.length).toBeGreaterThan(0)

      await comments.box(keys[0]).click()
      await comments.bulk("destroy").click()
      await expect(comments.question.locator("p")).toHaveText("Delete this comment? 1 record is selected.")
      await comments.question.getByRole("button", { name: "Confirm" }).click()

      await expect(comments.result).toHaveText("Destroy: 1 done.")
      await expect(comments.row(keys[0])).toHaveCount(0)
      await expect(tasks.line(FIRST, "comments")).toHaveAttribute("aria-expanded", "true")
      await expect(tasks.result).toHaveCount(0)
      expect(await tasks.tabStops()).toHaveLength(1)
    })
  })
})

test.describe("rows with a primary key of two attributes", () => {
  test.use({ writes: true })

  test("are selected and run on like any others", async ({ page }) => {
    const labels = new Table(page, "task_label", "/task_labels")
    await labels.open()
    const { first, second, third } = SEED.taskLabel

    await labels.box(first).click()
    await labels.box(third).click()
    await expect(labels.selectedCount).toHaveText("2 selected")

    // "Remove" asks nothing in a row; for several rows it asks
    await labels.bulk("destroy").click()
    await expect(labels.question.locator("p")).toHaveText("Run “Remove” on 2 records?")
    await labels.question.getByRole("button", { name: "Confirm" }).click()

    await expect(labels.result).toHaveText("Remove: 2 done.")
    await expect(labels.row(first)).toHaveCount(0)
    await expect(labels.row(third)).toHaveCount(0)
    await expect(labels.row(second)).toHaveCount(1)
  })
})

test.describe("an action the block keeps to one row", () => {
  test("is in the rows and not on the line", async ({ page }) => {
    const projects = new Table(page, "project", "/projects")
    await projects.open()
    const [project] = await projects.rowKeys()

    await expect(projects.actions(project)).toHaveText([
      "Set status",
      "Set budget",
      "Destroy",
      "Assign open tasks",
    ])
    await projects.box(project).click()
    await expect(projects.bulkButtons).toHaveText(["Set status", "Set budget", "Assign open tasks"])
  })
})

// The labels, as the member, who can run no action on them: the table of
// /labels has no boxes for him.
test.describe("tables that are told to let their rows be selected, with nothing to run on them", () => {
  test.use({ actor: "member" })

  let one: Table
  let several: Table

  /** What the page was told about the selections of its tables, by table. */
  async function heard(page: Page): Promise<Record<string, { mode: string; all: boolean; rows: unknown[] }>> {
    return page.evaluate(() => (window as any).__selections)
  }

  test.beforeEach(async ({ page }) => {
    // the surrounding page listens, as any code around a table can
    await page.addInitScript(() => {
      ;(window as any).__selections = {}
      window.addEventListener("ash_data_table:selection", (event) => {
        const detail = (event as CustomEvent).detail
        ;(window as any).__selections[detail.table] = detail
      })
    })
    one = new Table(page, "one", "/e2e/select")
    several = new Table(page, "several", "/e2e/select")
    await one.open()
    await several.ready()
  })

  test("one row at a time: a radio button in every row, of one group, and none for the page; another row takes the first one's place", async ({
    page,
  }) => {
    const [first, second] = await one.rowKeys()

    // one of a set: a grid that says it is not multi-selectable, rows that
    // say whether they are selected, and radio buttons of one group
    await expect(one.grid).toHaveAttribute("aria-multiselectable", "false")
    await expect(one.pageBox).toHaveCount(0)
    await expect(one.pageBoxCell).toHaveText("Select row")
    await expect(one.selectionLine).toHaveCount(0)
    await expect(one.boxes).toHaveCount(0)
    await expect(one.radios).toHaveCount(SEED.labels.acme)
    await expect(one.radio(first)).toHaveRole("radio")
    await expect(one.radio(first)).toHaveAccessibleName("Select row")
    expect(new Set(await one.radios.evaluateAll((radios) => radios.map((radio) => (radio as HTMLInputElement).name)))).toEqual(
      new Set(["one-select"]),
    )
    await expect(one.rowLine(first)).toHaveAttribute("aria-selected", "false")

    await one.radio(first).click()
    expect(await one.selectedKeys()).toEqual([first])
    await expect(one.radio(first)).toBeChecked()
    expect((await heard(page)).one).toEqual({ table: "one", mode: "single", all: false, rows: [first] })

    await one.cell(second, "name").focus()
    await page.keyboard.press("Space")
    expect(await one.selectedKeys()).toEqual([second])
    await expect(one.radio(first)).not.toBeChecked()
    await expect(one.radio(second)).toBeChecked()
    expect(await one.radios.evaluateAll((radios) => radios.filter((radio) => (radio as HTMLInputElement).checked).length)).toBe(1)
    expect((await heard(page)).one.rows).toEqual([second])

    // Shift selects no range here
    await page.keyboard.press("Shift+ArrowDown")
    expect(await one.selectedKeys()).toEqual([second])
    await one.cell(first, "name").click({ modifiers: ["Shift"] })
    expect(await one.selectedKeys()).toEqual([second])

    // focus is on the row that was clicked: Space selects it in the other's
    // place. As a radio button, the selected row stays selected when it is
    // used again, from the keyboard or with the pointer.
    await page.keyboard.press("Space")
    expect(await one.selectedKeys()).toEqual([first])
    await page.keyboard.press("Space")
    expect(await one.selectedKeys()).toEqual([first])
    await one.radio(first).click()
    expect(await one.selectedKeys()).toEqual([first])
    await expect(one.radio(first)).toBeChecked()
    expect((await heard(page)).one.rows).toEqual([first])

    // a table that is told to let one row be selected is not one to choose
    // from: a click on another cell of a row selects nothing
    await one.cell(second, "name").click()
    expect(await one.selectedKeys()).toEqual([first])

    // the other table has heard nothing, and selected nothing
    expect((await heard(page)).several).toBeUndefined()
    expect(await several.selectedKeys()).toEqual([])
  })

  test("several: the boxes, the count and Clear selection, and no action", async ({ page }) => {
    const keys = await several.rowKeys()

    await expect(several.grid).toHaveAttribute("aria-multiselectable", "true")
    await several.box(keys[0]).click()
    await several.box(keys[2]).click({ modifiers: ["Shift"] })

    await expect(several.selectedCount).toHaveText("3 selected")
    await expect(several.clearSelection).toBeVisible()
    await expect(several.bulkButtons).toHaveCount(0)
    expect((await heard(page)).several).toEqual({
      table: "several",
      mode: "multi",
      all: false,
      rows: keys.slice(0, 3),
    })

    await several.clearSelection.click()
    expect((await heard(page)).several.rows).toEqual([])
  })

  test("axe finds nothing wrong with either, with rows selected", async ({ page }) => {
    const [first] = await one.rowKeys()
    await one.radio(first).click()
    await several.pageBox.click()
    await expectNoAxeViolations(page)
  })
})

test.describe("in German", () => {
  test.use({ writes: true })

  test("the boxes, the line, the question and the result", async ({ page, tasks }) => {
    await switchLocale(page, "de")
    await tasks.ready()

    await expect(tasks.box(FIRST)).toHaveAccessibleName("Zeile auswählen")
    await expect(tasks.pageBox).toHaveAccessibleName("Alle Zeilen dieser Seite auswählen")
    await tasks.box(FIRST).click()
    await tasks.box(SECOND).click()
    await expect(tasks.selectedCount).toHaveText("2 ausgewählt")
    await expect(tasks.clearSelection).toHaveText("Auswahl aufheben")

    await tasks.pageBox.click()
    await expect(tasks.selectAll).toHaveText(`Alle ${SEED.tasks.acme} passenden auswählen`)
    await tasks.pageBox.click()
    await tasks.box(FIRST).click()

    await tasks.bulk("archive").click()
    await expect(tasks.question.locator("p")).toHaveText("„Archivieren“ für 1 Eintrag ausführen?")
    await tasks.question.getByRole("button", { name: "Bestätigen" }).click()
    await expect(tasks.result).toHaveText("Archivieren: 1 erledigt.")

    await switchLocale(page, "en")
  })
})

// axe-core on every state this file brings a table into, in both themes.
for (const theme of ["light", "dark"] as const) {
  test.describe(`axe, in the ${theme} theme`, () => {
    test.use({ writes: true })

    test.beforeEach(async ({ page, tasks }) => {
      await page.addInitScript((theme) => localStorage.setItem("phx:theme", theme), theme)
      await tasks.open()
      await expect(page.locator("html")).toHaveAttribute("data-theme", theme)
    })

    test("rows selected, with the line and its buttons", async ({ page, tasks }) => {
      await tasks.box(FIRST).click()
      await tasks.box(THIRD).click()
      await expect(tasks.bulk("archive")).toBeVisible()
      await expectNoAxeViolations(page)
    })

    test("a whole page selected, with all that match on offer, and then selected", async ({ page, tasks }) => {
      await tasks.pageBox.click()
      await expect(tasks.selectAll).toBeVisible()
      await expectNoAxeViolations(page)

      await tasks.selectAll.click()
      await expectNoAxeViolations(page)
    })

    test("the question of an action on the selected rows", async ({ page, tasks }) => {
      await tasks.box(FIRST).click()
      await tasks.bulk("destroy").click()
      await expect(tasks.question).toBeVisible()
      await expectNoAxeViolations(page)
    })

    test("the panel of an action on the selected rows, with an error", async ({ page, tasks }) => {
      await tasks.box(FIRST).click()
      await tasks.box(SECOND).click()
      await tasks.bulk("reassign").click()
      await expect(tasks.panel).toBeVisible()
      await expectNoAxeViolations(page)

      await tasks.field("reason").fill("No")
      await tasks.panelSettled()
      await expect(tasks.fieldError("reason")).toBeVisible()
      await expectNoAxeViolations(page)
    })

    test("what an action came to: all done, and some not done with rows still selected", async ({
      page,
      tasks,
    }) => {
      const [done] = await keysWhere(tasks, "status", "Done")
      await tasks.box(done).click()
      await tasks.box(FIRST).click()
      await tasks.bulk("set_progress").click()
      await tasks.field("progress").fill("50")
      await tasks.panelSettled()
      await tasks.panelSubmit.click()
      await confirmed(tasks)
      await expect(tasks.result.locator("[data-failure]")).toHaveCount(1)
      await expectNoAxeViolations(page)

      await tasks.clearSelection.click()
      await tasks.box(SECOND).click()
      await tasks.bulk("archive").click()
      await confirmed(tasks)
      await expect(tasks.result).toHaveText("Archive: 1 done.")
      await expectNoAxeViolations(page)
    })

    test("a nested table with rows selected, under a selected row", async ({ page, tasks }) => {
      const comments = await tasks.openLine(FIRST, "comments")
      const [comment] = await comments.rowKeys()
      await comments.box(comment).click()
      await tasks.box(FIRST).click()
      await expectNoAxeViolations(page)
    })
  })
}

// What a locator's element looks like to the eye is the contrast tests'
// (contrast.spec.ts); here: that the box of a row has an edge that is seen.
test("the box of a row has an edge of enough contrast, in both themes", async ({ page, tasks }) => {
  for (const theme of ["light", "dark"] as const) {
    await page.evaluate((theme) => {
      localStorage.setItem("phx:theme", theme)
      document.documentElement.setAttribute("data-theme", theme)
    }, theme)
    expect(await contrastOf(tasks.box(FIRST), "border"), `a row's box, ${theme}`).toBeGreaterThanOrEqual(3)
    expect(await contrastOf(tasks.pageBox, "border"), `the page's box, ${theme}`).toBeGreaterThanOrEqual(3)
  }
  await page.evaluate(() => localStorage.removeItem("phx:theme"))
})
