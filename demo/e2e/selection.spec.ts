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
// test says otherwise. The table's hook paints the rows and their boxes at
// once, and tells the server of every change (`select`); the line above the
// grid is the server's, drawn from what it holds: its count, its buttons and
// "all that match" come one round trip after a box is used, which the tests
// wait for. The tests that run an action change the data.

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
    await expect(tasks.headerCells.first()).toHaveId("task-select-head")
    await expect(tasks.pageBoxCell).toHaveRole("columnheader")
    await expect(tasks.pageBoxCell).toHaveAttribute("aria-colindex", "1")
    await expect(tasks.pageBox).toHaveAccessibleName("Select all rows of this page")
    await expect(tasks.pageBox).not.toBeChecked()

    await expect(tasks.rowCells(FIRST).first()).toHaveId(`task-row-${FIRST}-s`)
    await expect(tasks.boxCell(FIRST)).toHaveRole("cell")
    await expect(tasks.boxCell(FIRST)).toHaveAttribute("aria-colindex", "1")
    await expect(tasks.box(FIRST)).toHaveAccessibleName("Select row")
    await expect(tasks.boxes).toHaveCount(25)

    // the expander is the cell after it, and the first column the one after that
    await expect(tasks.rowCells(FIRST).nth(1)).toHaveId(`task-row-${FIRST}-e`)
    await expect(tasks.expanderCell(FIRST)).toHaveAttribute("aria-colindex", "2")
    await expect(tasks.cell(FIRST, "title")).toHaveAttribute("aria-colindex", "3")

    // every box is a Tab stop, the browser's own checkbox; its cell is none
    for (const box of [tasks.pageBox, tasks.box(FIRST)]) await expect(box).not.toHaveAttribute("tabindex")
    await expect(tasks.boxCell(FIRST)).not.toHaveAttribute("tabindex")
    const stops = await tasks.stops()
    expect(stops).toContain("task-select-head>input")
    expect(stops).toContain(`task-row-${FIRST}-s>input`)
    expect(stops).not.toContain(`task-row-${FIRST}-s`)
  })

  test("each row's box says whether it is selected, and none is at first", async ({ tasks }) => {
    await expect(tasks.boxes).toHaveCount(25)
    for (const box of await tasks.boxes.all()) await expect(box).not.toBeChecked()
    expect(await tasks.selectedKeys()).toEqual([])

    // nothing is selected: the line holds no text and shows no button
    await expect(tasks.selectionLine).toHaveRole("group")
    await expect(tasks.page.locator("#task-selection-controls")).toBeHidden()
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
      })
    })
  }
})

test.describe("selecting with the pointer", () => {
  test("a click on a row's box selects the row, and another takes it out", async ({ tasks, pushed }) => {
    await pushed.clear()
    await tasks.box(SECOND).click()

    await expect(tasks.box(SECOND)).toBeChecked()
    await expect(tasks.box(FIRST)).not.toBeChecked()
    expect(await tasks.selectedKeys()).toEqual([SECOND])
    await pushed.expectSelected(tasks)
    await expect(tasks.selectedCount).toHaveText("1 selected")
    await expect(tasks.clearSelection).toBeVisible()
    await expect(tasks.bulkButtons).toHaveText(["Archive", "Reassign", "Set progress", "Destroy", "Set labels"])
    // focus is on the box
    await expect(tasks.box(SECOND)).toBeFocused()

    await tasks.box(SECOND).click()
    await expect(tasks.box(SECOND)).not.toBeChecked()
    expect(await tasks.selectedKeys()).toEqual([])
    await expect(tasks.selectedCount).toHaveText("")
    await expect(tasks.clearSelection).toBeHidden()

    await pushed.expectSelected(tasks)
    expect(await pushed.besides("select"), "selecting sends nothing but what is selected").toEqual([])
  })

  test("a click beside the box, in its cell, does the same", async ({ tasks }) => {
    const cell = (await tasks.boxCell(FIRST).boundingBox())!
    await tasks.page.mouse.click(cell.x + 2, cell.y + 2)

    await expect(tasks.box(FIRST)).toBeChecked()
    expect(await tasks.selectedKeys()).toEqual([FIRST])
  })

  test("the box in the header selects every row of the page, is mixed while some are selected, and takes all out again", async ({
    tasks,
    pushed,
  }) => {
    const mixed = () => tasks.pageBox.evaluate((box) => (box as HTMLInputElement).indeterminate)
    await pushed.clear()

    await tasks.box(FIRST).click()
    await expect(tasks.pageBox).not.toBeChecked()
    expect(await mixed()).toBe(true)

    await tasks.pageBox.click()
    await expect(tasks.pageBox).toBeChecked()
    expect(await mixed()).toBe(false)
    expect(await tasks.selectedKeys()).toHaveLength(25)
    await pushed.expectSelected(tasks)
    await expect(tasks.selectedCount).toHaveText("25 selected")
    for (const box of await tasks.boxes.all()) await expect(box).toBeChecked()

    await tasks.pageBox.click()
    await expect(tasks.pageBox).not.toBeChecked()
    expect(await tasks.selectedKeys()).toEqual([])
    await expect(tasks.selectedCount).toHaveText("")

    await pushed.expectSelected(tasks)
    expect(await pushed.besides("select"), "selecting sends nothing but what is selected").toEqual([])
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
  test("Space on a row's box selects the row, and takes it out again; focus stays, and the page does not scroll", async ({
    page,
    tasks,
    pushed,
  }) => {
    await tasks.box(FIRST).focus()
    await pushed.clear()

    await page.keyboard.press("Space")
    expect(await tasks.selectedKeys()).toEqual([FIRST])
    await expect(tasks.selectedCount).toHaveText("1 selected")
    // focus is where it was: the count is read out, and nothing is taken
    await expect(tasks.box(FIRST)).toBeFocused()

    for (const key of [SECOND, THIRD]) {
      await tasks.box(key).focus()
      await page.keyboard.press("Space")
    }
    expect(await tasks.selectedKeys()).toEqual([FIRST, SECOND, THIRD])
    await page.keyboard.press("Space")
    expect(await tasks.selectedKeys()).toEqual([FIRST, SECOND])

    expect(await page.evaluate(() => window.scrollY)).toBe(0)
    await pushed.expectSelected(tasks)
    expect(await pushed.besides("select"), "selecting sends nothing but what is selected").toEqual([])
  })

  test("Space on a boolean cell selects nothing and leaves its value alone: Enter toggles it", async ({
    page,
    tasks,
    pushed,
  }) => {
    const cell = tasks.cell(FIRST, "billable?")
    const before = await cell.textContent()
    await cell.focus()
    await pushed.clear()
    await page.keyboard.press("Space")
    await expect(cell).toHaveText(before!)
    expect(await pushed.all()).toEqual([])
    expect(await tasks.selectedKeys()).toEqual([])
    await expect(tasks.openEditors).toHaveCount(0)
  })

  test("Space on the box in the header selects the rows of the page", async ({ page, tasks }) => {
    await tasks.pageBox.focus()
    await page.keyboard.press("Space")
    expect(await tasks.selectedKeys()).toHaveLength(25)
    await expect(tasks.pageBox).toBeChecked()

    await page.keyboard.press("Space")
    expect(await tasks.selectedKeys()).toEqual([])
  })

  test("Space on a relationship line's button and on the expander uses the button, and selects nothing", async ({
    page,
    tasks,
  }) => {
    await tasks.expander(FIRST).focus()
    await page.keyboard.press("Space")
    await expect(tasks.expander(FIRST)).toHaveAttribute("aria-expanded", "true")

    await tasks.line(FIRST, "comments").focus()
    await page.keyboard.press("Space")
    await expect(tasks.line(FIRST, "comments")).toHaveAttribute("aria-expanded", "true")
    await tasks.nested(FIRST, "comments").loaded()

    expect(await tasks.selectedKeys()).toEqual([])
    await expect(tasks.selectedCount).toHaveText("")
  })

  test("the buttons of the line are reached with Shift+Tab from \"Skip table\", and used with Enter", async ({
    page,
    tasks,
  }) => {
    await tasks.box(FIRST).focus()
    await tasks.press("Space")
    // the server draws the buttons once it is told of the selection
    await expect(tasks.clearSelection).toBeVisible()
    // the line stands right before the table's "Skip table": its last button
    // is "More", whose menu holds the actions after the first two
    await tasks.skip.focus()
    await tasks.press("Shift+Tab")
    expect(await tasks.focused()).toBe("task-bulk-more-button")
    await tasks.press("Shift+Tab")
    expect(await tasks.focused()).toBe("task-bulk-reassign")
    await tasks.press("Shift+Tab", "Shift+Tab")
    expect(await tasks.focused()).toBe("task-clear-selection")

    await page.keyboard.press("Enter")
    expect(await tasks.selectedKeys()).toEqual([])
    // the button went with the selection: focus is on the table's first stop, the box of the page
    await expect(tasks.pageBox).toBeFocused()
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

    await tasks.sortBy("inserted_at")
    await expect(tasks.selectedCount).toHaveText("3 selected")
  })

  test("is given up when a filter changes", async ({ page, tasks }) => {
    await tasks.box(FIRST).click()
    await tasks.box(SECOND).click()

    await tasks.filterValue("title").focus()
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
    // the button goes: focus is on the one beside it at once, before the server answers
    expect(await tasks.focused()).toBe("task-clear-selection")
    await expect(tasks.selectedCount).toHaveText(`All ${SEED.tasks.acme} that match are selected`)
    await expect(tasks.selectAll).toBeHidden()
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
    await tasks.filterValue("title").focus()
    await tasks.reads(async () => {
      await page.keyboard.type("email")
      await page.keyboard.press("Enter")
    })
    await expect(tasks.selectedCount).toHaveText("")
    expect(await tasks.selectedKeys()).toEqual([])
  })

  test("is not offered where the page is all there is", async ({ page, tasks }) => {
    await tasks.filterValue("title").focus()
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
    const keys = await tasks.rowKeys()

    // what a screen reader is told is what the region comes to hold
    await page.evaluate(() => {
      const said: string[] = []
      ;(window as any).__said = said
      new MutationObserver(() => said.push(document.getElementById("task-selected")!.textContent!)).observe(
        document.getElementById("task-selected")!,
        { childList: true, characterData: true, subtree: true },
      )
    })

    for (const key of [keys[0], keys[1], keys[3]]) {
      await tasks.box(key).focus()
      await tasks.press("Space")
    }
    await tasks.press("Space")

    // the server says each count as it is told of each change
    await expect.poll(() => page.evaluate(() => (window as any).__said)).toEqual([
      "1 selected",
      "2 selected",
      "3 selected",
      "2 selected",
    ])
    await expect(tasks.box(keys[3])).toBeFocused()
  })

  test("takes no room while nothing is selected, one line once something is, and stands at the other end from Clear filters", async ({
    page,
    tasks,
  }) => {
    const top = async () => (await tasks.grid.boundingBox())!.y
    const before = await top()
    // nothing is kept free for it: the heading line is right above the grid
    expect((await tasks.selectionLine.boundingBox())?.height ?? 0).toBe(0)
    const heading = (await tasks.headerLine.boundingBox())!
    expect(before - (heading.y + heading.height)).toBeLessThanOrEqual(12)

    await tasks.box(FIRST).click()
    await expect(tasks.clearSelection).toBeVisible()
    const selected = await top()
    expect(selected).toBeGreaterThan(before)

    await tasks.pageBox.click()
    await expect(tasks.selectAll).toBeVisible()
    expect(await top()).toBe(selected)

    // a filter takes the selection with it, and leaves its own button at the right
    await tasks.filterValue("title").focus()
    await tasks.reads(async () => {
      await page.keyboard.type("email")
      await page.keyboard.press("Enter")
    })
    await tasks.box((await tasks.rowKeys())[0]).click()
    await expect(tasks.clearSelection).toBeVisible()
    const clear = (await tasks.clearSelection.boundingBox())!
    const filters = (await tasks.clearFilters.boundingBox())!
    expect(clear.x).toBeLessThan(filters.x)
    expect(Math.abs(clear.y - filters.y)).toBeLessThanOrEqual(1)
    expect(await top()).toBe(selected)

    // and with the selection and the filter gone, it takes no room again
    await tasks.reads(() => tasks.clearFilters.click())
    await expect(tasks.clearFilters).toHaveCount(0)
    expect(await top()).toBe(before)
  })

  test("Clear selection takes every row out, on every page, and sends focus to the table's first stop", async ({ tasks }) => {
    await tasks.box(FIRST).click()
    await tasks.reads(() => tasks.next.click())
    await tasks.pageBox.click()
    await expect(tasks.selectedCount).toHaveText("26 selected")

    await tasks.clearSelection.click()

    // the hook sends focus to the table's first stop at once, the box of
    // the page; the server then takes the buttons away
    await expect(tasks.pageBox).toBeFocused()
    await expect(tasks.selectedCount).toHaveText("")
    await expect(tasks.clearSelection).toBeHidden()
    expect(await tasks.selectedKeys()).toEqual([])
    await expect(tasks.pageBox).toBeFocused()

    await tasks.reads(() => tasks.previous.click())
    expect(await tasks.selectedKeys()).toEqual([])
  })
})

test.describe("an action on the selected rows", () => {
  test("asks first, with the number of records; Cancel and Escape run nothing", async ({ page, tasks, pushed }) => {
    await tasks.box(FIRST).click()
    await tasks.box(SECOND).click()
    await tasks.box(THIRD).click()
    await pushed.clear()

    await tasks.useBulk("archive")
    await expect(tasks.question).toBeVisible()
    await expect(tasks.question.locator("p")).toHaveText("Run “Archive” on 3 records?")
    await expect(tasks.question.getByRole("button", { name: "Confirm" })).not.toHaveAttribute("data-destructive")
    // focus is on Cancel, the safe answer
    await expect(tasks.question.getByRole("button", { name: "Cancel" })).toBeFocused()

    await tasks.question.getByRole("button", { name: "Cancel" }).click()
    await answered(tasks)
    expect(await tasks.focused()).toBe("task-bulk-archive")

    await tasks.useBulk("archive")
    await expect(tasks.question).toBeVisible()
    await page.keyboard.press("Escape")
    await answered(tasks)

    expect(await pushed.count("bulk")).toBe(2)
    expect(await pushed.count("bulk_run")).toBe(0)
    await expect(tasks.cell(FIRST, "status")).not.toHaveText("Archived")
    await expect(tasks.selectedCount).toHaveText("3 selected")
    await expect(tasks.result).toHaveCount(0)
  })

  test("runs on the selected rows, says how many were done, reads the table again, and leaves nothing selected", async ({
    tasks,
    pushed,
  }) => {
    await tasks.box(FIRST).click()
    await tasks.box(THIRD).click()
    await pushed.clear()

    await tasks.useBulk("archive")
    await confirmed(tasks)

    await expect(tasks.result).toHaveText("Archive: 2 done.")
    await expect(tasks.status).toHaveText("Archive: 2 done.")
    await expect(tasks.cell(FIRST, "status")).toHaveText("Archived")
    await expect(tasks.cell(THIRD, "status")).toHaveText("Archived")
    await expect(tasks.cell(SECOND, "status")).not.toHaveText("Archived")

    await expect(tasks.selectedCount).toHaveText("")
    expect(await tasks.selectedKeys()).toEqual([])
    await expect(tasks.bulk("archive")).toBeHidden()
    // the server took the buttons away: the hook sends focus on to the table's first stop
    await expect(tasks.pageBox).toBeFocused()

    expect(await pushed.count("bulk")).toBe(1)
    expect(await pushed.count("bulk_run")).toBe(1)
  })

  test("runs on what the server holds as selected: rows of two pages, each told it as it was selected", async ({
    tasks,
    pushed,
  }) => {
    await pushed.clear()
    await tasks.box(FIRST).click()
    await tasks.reads(() => tasks.next.click())
    const [onSecondPage] = await tasks.rowKeys()
    await tasks.box(onSecondPage).click()
    // the server is told every change, and the action names nothing else
    expect(await pushed.count("select")).toBe(2)

    await tasks.useBulk("archive")
    await expect(tasks.question.locator("p")).toHaveText("Run “Archive” on 2 records?")
    await confirmed(tasks)
    await expect(tasks.result).toHaveText("Archive: 2 done.")
    await expect(tasks.cell(onSecondPage, "status")).toHaveText("Archived")
    await tasks.reads(() => tasks.previous.click())
    await expect(tasks.cell(FIRST, "status")).toHaveText("Archived")
    // and it told the hook that nothing stays selected
    await expect(tasks.selectedCount).toHaveText("")
  })

  test("what it came to stays through a sort, and goes when something else is selected", async ({ tasks }) => {
    await tasks.box(FIRST).click()
    await tasks.useBulk("archive")
    await confirmed(tasks)

    await tasks.sortBy("title")
    await expect(tasks.result).toHaveText("Archive: 1 done.")

    await tasks.box((await tasks.rowKeys())[0]).click()
    await expect(tasks.result).toHaveCount(0)
  })

  test("a destroy asks its own question with the number after it, in the error colour, and takes the rows away", async ({
    tasks,
  }) => {
    await tasks.box(FIRST).click()
    await tasks.box(SECOND).click()

    await tasks.useBulk("destroy")
    await expect(tasks.question.locator("p")).toHaveText(
      "Delete this task? This cannot be undone. 2 records are selected.",
    )
    await expect(tasks.question.getByRole("button", { name: "Confirm" })).toHaveAttribute("data-destructive")
    await confirmed(tasks)

    await expect(tasks.result).toHaveText("Destroy: 2 done.")
    await expect(tasks.row(FIRST)).toHaveCount(0)
    await expect(tasks.row(SECOND)).toHaveCount(0)
    await expect(tasks.range).toHaveText(`1–25 of ${SEED.tasks.acme - 2}`)
    expect(await tasks.hasFocus()).toBe(true)
  })

  test("with inputs opens its panel once, with empty fields, and gives every record what they hold", async ({
    page,
    tasks,
    pushed,
  }) => {
    await tasks.box(FIRST).click()
    await tasks.box(SECOND).click()

    await tasks.useBulk("reassign")
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

    await pushed.clear()
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
    expect(await pushed.count("panel_submit")).toBe(1)
  })

  test("Escape in its panel runs nothing and keeps the selection, with focus back on the button", async ({
    page,
    tasks,
  }) => {
    await tasks.box(FIRST).click()
    await tasks.useBulk("set_progress")
    await expect(tasks.panelTitle).toHaveText("Set progress: 1 record")

    await page.keyboard.press("Escape")

    await expect(tasks.panel).toHaveCount(0)
    await expect(tasks.selectedCount).toHaveText("1 selected")
    await expect(tasks.result).toHaveCount(0)
    // an action of the menu "More" closed: focus is back on its button
    await expect(tasks.bulkMore.locator("xpath=following-sibling::*[@popover]")).toBeHidden()
    expect(await tasks.focused()).toBe("task-bulk-more-button")
  })

  test("that a validation refuses on some rows is done on the others, and says why", async ({ tasks }) => {
    const [done] = await keysWhere(tasks, "status", "Done")
    const [todo] = await keysWhere(tasks, "status", "To do")
    await tasks.box(done).click()
    await tasks.box(todo).click()

    await tasks.useBulk("set_progress")
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

    await tasks.useBulk("archive")
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
      await tasks.useBulk("archive")
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
  test("has its own boxes, its own line and its own selection", async ({ tasks, pushed }) => {
    const comments = await tasks.openLine(FIRST, "comments")
    const [comment] = await comments.rowKeys()
    await pushed.clear()

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
    await pushed.expectSelected(tasks)
    await pushed.expectSelected(comments)
    expect(await pushed.besides("select")).toEqual([])
  })

  test("Space on its box selects in its own table, and its line's buttons are reached from the keyboard", async ({
    page,
    tasks,
  }) => {
    const comments = await tasks.openLine(FIRST, "comments")
    const [comment] = await comments.rowKeys()

    await comments.box(comment).focus()
    await page.keyboard.press("Space")
    expect(await comments.selectedKeys()).toEqual([comment])
    expect(await tasks.selectedKeys()).toEqual([])
    await expect(comments.clearSelection).toBeVisible()

    // right before its "Skip table": the buttons of its selection line
    await comments.skip.focus()
    await page.keyboard.press("Shift+Tab")
    expect(await tasks.focused()).toBe(`${comments.id}-bulk-destroy`)
    // which, as the only action, stands on the line, and in the error colour
    await expect(comments.bulk("destroy")).toHaveClass(/btn-outline/)
    await expect(comments.bulk("destroy")).toHaveClass(/btn-error/)
    await expect(comments.bulkMore).toHaveCount(0)
  })

  test.describe(() => {
    test("runs its action on its own rows, and stays open", async ({ tasks }) => {
      const comments = await tasks.openLine(FIRST, "comments")
      const keys = await comments.rowKeys()
      expect(keys.length).toBeGreaterThan(0)

      await comments.box(keys[0]).click()
      await comments.useBulk("destroy")
      await expect(comments.question.locator("p")).toHaveText("Delete this comment? 1 record is selected.")
      await comments.question.getByRole("button", { name: "Confirm" }).click()

      await expect(comments.result).toHaveText("Destroy: 1 done.")
      await expect(comments.row(keys[0])).toHaveCount(0)
      await expect(tasks.line(FIRST, "comments")).toHaveAttribute("aria-expanded", "true")
      await expect(tasks.result).toHaveCount(0)
    })
  })
})

test.describe("rows with a primary key of two attributes", () => {
  test("are selected and run on like any others", async ({ page }) => {
    const labels = new Table(page, "task_label", "/task_labels")
    await labels.open()
    const { first, second, third } = SEED.taskLabel

    await labels.box(first).click()
    await labels.box(third).click()
    await expect(labels.selectedCount).toHaveText("2 selected")

    // "Remove" asks nothing in a row; for several rows it asks
    await labels.useBulk("destroy")
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
test.describe("in German", () => {
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
    await expect(tasks.selectAll).toBeVisible()
    await expect(tasks.selectAll).toHaveText(`Alle ${SEED.tasks.acme} passenden auswählen`)
    await tasks.pageBox.click()
    await tasks.box(FIRST).click()

    await tasks.useBulk("archive")
    await expect(tasks.question.locator("p")).toHaveText("„Archivieren“ für 1 Eintrag ausführen?")
    await tasks.question.getByRole("button", { name: "Bestätigen" }).click()
    await expect(tasks.result).toHaveText("Archivieren: 1 erledigt.")

    await switchLocale(page, "en")
  })
})

// axe-core on every state this file brings a table into, in both themes.
for (const theme of ["light", "dark"] as const) {
  test.describe(`axe, in the ${theme} theme`, () => {
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
      await tasks.useBulk("destroy")
      await expect(tasks.question).toBeVisible()
      await expectNoAxeViolations(page)
    })

    test("the panel of an action on the selected rows, with an error", async ({ page, tasks }) => {
      await tasks.box(FIRST).click()
      await tasks.box(SECOND).click()
      await tasks.useBulk("reassign")
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
      await tasks.useBulk("set_progress")
      await tasks.field("progress").fill("50")
      await tasks.panelSettled()
      await tasks.panelSubmit.click()
      await confirmed(tasks)
      await expect(tasks.result.locator("[data-failure]")).toHaveCount(1)
      await expectNoAxeViolations(page)

      await tasks.clearSelection.click()
      await tasks.box(SECOND).click()
      await tasks.useBulk("archive")
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
