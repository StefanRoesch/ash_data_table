import type { Browser, Locator, Page } from "@playwright/test"
import { storageStateOf, type Actor } from "./support/actors"
import { deleteTask, SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { Table } from "./support/table"

// Row actions and row create in a browser: the actions column by pointer and
// by keyboard, the question of an action that asks first, where focus is
// after a row was changed, taken away or added, the cell of an action that
// failed, and the action panel as the modal dialog it is.
//
// /tasks as the admin, who may run every action on every task, unless a
// test says otherwise. A row of it has four actions: "Archive" runs at one
// click, "Reassign" and "Set progress" open the action panel, and "Destroy"
// asks first. These tests change the data: the database is seeded again
// after each of them (`writes`).

const FIRST = SEED.task.first
// still to do, with a progress of 5
const SECOND = SEED.task.second
const THIRD = SEED.task.third

const QUESTION = "Delete this task? This cannot be undone."
const REFUSED = "You are not allowed to do this."
const GONE = "This record is no longer available."

test.use({ writes: true })

test.beforeEach(async ({ tasks }) => {
  await tasks.open()
})

/** The height of a row, which an actions cell and its message must not change. */
async function rowHeight(table: Table, key: string): Promise<number> {
  return (await table.rowLine(key).boundingBox())!.height
}

/** Whether focus is in the action panel of a table. */
async function focusInPanel(table: Table): Promise<boolean> {
  return table.panel.evaluate((panel) => panel.contains(document.activeElement))
}

/**
 * The page as another actor sees it, beside the test's own: a second window
 * with that actor's session, as wide and high as the test's.
 */
async function asActor<T>(
  browser: Browser,
  page: Page,
  actor: Actor,
  look: (page: Page) => Promise<T>,
): Promise<T> {
  const context = await browser.newContext({
    storageState: storageStateOf(actor),
    baseURL: new URL(page.url()).origin,
    viewport: page.viewportSize(),
  })
  try {
    return await look(await context.newPage())
  } finally {
    await context.close()
  }
}

/** The dialog has closed and the hook has heard of it (see editing.spec.ts). */
async function answered(table: Table): Promise<void> {
  await expect(table.question).toBeHidden()
  await table.page.evaluate(() => new Promise((resolve) => setTimeout(resolve, 0)))
}

test.describe("the actions column", () => {
  test("is the last column of the grid: a header, an empty filter cell, and a button per action in every row", async ({
    tasks,
  }) => {
    // the boxes, the expanders, the twenty-two columns of the table, the actions
    await expect(tasks.grid).toHaveAttribute("aria-colcount", "25")
    await expect(tasks.headerCells).toHaveCount(25)
    await expect(tasks.headerCells.last()).toHaveId("task-actions-head")
    await expect(tasks.actionsHeader).toHaveText("Actions")
    await expect(tasks.actionsHeader).toHaveRole("columnheader")
    await expect(tasks.actionsHeader).toHaveAttribute("aria-colindex", "25")
    await expect(tasks.actionsHeader, "it sorts nothing").not.toHaveAttribute("aria-sort")
    await expect(tasks.actionsFilter).toHaveText("")
    await expect(tasks.actionsFilter).toHaveAttribute("aria-colindex", "25")

    await expect(tasks.rowCells(FIRST).last()).toHaveId(`task-row-${FIRST}-a`)
    await expect(tasks.actionsCell(FIRST)).toHaveRole("gridcell")
    await expect(tasks.actionsCell(FIRST)).toHaveAttribute("aria-colindex", "25")
    await expect(tasks.actions(FIRST)).toHaveText(["Archive", "Reassign", "Set progress", "Destroy", "Set labels"])
    await expect(tasks.grid.locator(":scope > tbody > tr > td[data-actions] > button")).toHaveCount(125)

    // the buttons are no tab stops: the grid is one, as it was
    for (const button of await tasks.actions(FIRST).all()) {
      await expect(button).toHaveAttribute("tabindex", "-1")
      await expect(button).toHaveAttribute("type", "button")
    }
    expect(await tasks.tabStops()).toEqual([`task-row-${FIRST}-c-title`])

    // only the action that deletes asks first
    await expect(tasks.action(FIRST, "destroy")).toHaveAttribute("data-question", QUESTION)
    await expect(tasks.action(FIRST, "destroy")).toHaveAttribute("data-destructive")
    for (const name of ["archive", "reassign", "set_progress", "set_labels"]) {
      await expect(tasks.action(FIRST, name)).not.toHaveAttribute("data-question")
      await expect(tasks.action(FIRST, name)).not.toHaveAttribute("data-destructive")
    }

    // what is under an expanded row spans the actions column too
    await tasks.expand(FIRST)
    await expect(tasks.lineCell(FIRST, "comments")).toHaveAttribute("colspan", "25")
  })

  test("its buttons stand in one line, and make a row no higher than a row without them is", async ({
    browser,
    page,
    tasks,
  }) => {
    const withActions = await rowHeight(tasks, FIRST)

    const tops = await tasks
      .actions(FIRST)
      .evaluateAll((buttons) => buttons.map((button) => Math.round(button.getBoundingClientRect().top)))
    expect(new Set(tops).size, "one line of buttons").toBe(1)

    // a viewer can run no action and has no such column
    const without = await asActor(browser, page, "viewer", async (other) => {
      const table = new Table(other, "task", "/tasks")
      await table.open()
      await expect(table.actionsHeader).toHaveCount(0)
      await expect(table.grid.locator("[data-actions]")).toHaveCount(0)
      return rowHeight(table, FIRST)
    })

    expect(withActions).toBeCloseTo(without, 0)
  })

  for (const actor of ["viewer", "nobody"] as const) {
    test.describe(() => {
      test.use({ actor })

      test(`is not there for the ${actor}, who can run no action`, async ({ tasks }) => {
        await expect(tasks.actionsHeader).toHaveCount(0)
        await expect(tasks.actionsFilter).toHaveCount(0)
        await expect(tasks.grid.locator("button[data-action]")).toHaveCount(0)
        await expect(tasks.create).toHaveCount(0)
        // the name is on its line all the same
        await expect(tasks.name).toHaveText("Tasks")
      })
    })
  }
})

test.describe("with the keyboard", () => {
  test("the actions cell is a cell the arrow keys stop at, under a header and a filter cell of its own", async ({
    tasks,
    frames,
  }) => {
    await tasks.cell(FIRST, "reporter").focus()
    await frames.clear()

    await tasks.press("ArrowRight")
    await expect(tasks.actionsCell(FIRST)).toBeFocused()
    await tasks.press("ArrowRight")
    await expect(tasks.actionsCell(FIRST), "the last cell of a row is where Right ends").toBeFocused()
    expect(await tasks.tabStops()).toEqual([`task-row-${FIRST}-a`])

    await tasks.press("ArrowDown")
    await expect(tasks.actionsCell(SECOND)).toBeFocused()
    await tasks.press("ArrowUp", "ArrowUp")
    await expect(tasks.actionsFilter).toBeFocused()
    await tasks.press("ArrowUp")
    await expect(tasks.actionsHeader).toBeFocused()

    // nothing to sort by and nothing to filter: Enter, F2 and a character do nothing there
    await tasks.press("Enter", "F2", "x", "ArrowDown")
    await expect(tasks.actionsFilter).toBeFocused()
    await tasks.press("Enter", "F2", "x")
    await expect(tasks.actionsFilter).toBeFocused()
    await expect(tasks.grid.locator('[aria-sort]:not([aria-sort="none"])')).toHaveCount(0)

    await tasks.press("ArrowDown", "ArrowLeft")
    await expect(tasks.cell(FIRST, "reporter")).toBeFocused()
    await tasks.press("Home", "End")
    await expect(tasks.actionsCell(FIRST), "End is the last cell of the row").toBeFocused()
    await tasks.press("Control+End")
    await expect(tasks.actionsCell((await tasks.rowKeys()).at(-1)!)).toBeFocused()

    expect(await frames.all(), "moving about asks the server nothing").toEqual([])
    expect(await tasks.tabStops()).toHaveLength(1)
  })

  test("Enter and F2 go to the first button; Left and Right move between the buttons, and Escape comes back to the cell", async ({
    tasks,
    frames,
  }) => {
    const cell = tasks.actionsCell(FIRST)
    await cell.focus()
    await frames.clear()

    // Space and a character are nothing on the cell
    await tasks.press("Space", "x")
    await expect(cell).toBeFocused()

    await tasks.press("Enter")
    await expect(tasks.action(FIRST, "archive")).toBeFocused()
    // the cell stays the one tab stop while a button of it has the focus
    expect(await tasks.tabStops()).toEqual([`task-row-${FIRST}-a`])

    await tasks.press("ArrowRight")
    await expect(tasks.action(FIRST, "reassign")).toBeFocused()
    await tasks.press("ArrowRight")
    await expect(tasks.action(FIRST, "set_progress")).toBeFocused()
    await tasks.press("ArrowRight")
    await expect(tasks.action(FIRST, "destroy")).toBeFocused()
    await tasks.press("ArrowRight")
    await expect(tasks.action(FIRST, "set_labels")).toBeFocused()
    await tasks.press("ArrowRight")
    await expect(tasks.action(FIRST, "set_labels"), "Right ends at the last button").toBeFocused()

    await tasks.press("ArrowLeft", "ArrowLeft", "ArrowLeft", "ArrowLeft")
    await expect(tasks.action(FIRST, "archive")).toBeFocused()
    await tasks.press("ArrowLeft")
    await expect(tasks.action(FIRST, "archive"), "and Left at the first").toBeFocused()

    // up and down belong to no button: focus stays where it is
    await tasks.press("ArrowDown", "ArrowUp")
    await expect(tasks.action(FIRST, "archive")).toBeFocused()

    await tasks.press("Escape")
    await expect(cell).toBeFocused()
    await tasks.press("F2")
    await expect(tasks.action(FIRST, "archive")).toBeFocused()
    await tasks.press("Escape", "ArrowDown")
    await expect(tasks.actionsCell(SECOND), "back on the cell, the arrow keys move again").toBeFocused()

    expect(await frames.all(), "none of it asks the server anything").toEqual([])
    expect(await tasks.tabStops()).toEqual([`task-row-${SECOND}-a`])
  })

  test("Tab walks the buttons of the cell, then leaves the grid; before the first button is the cell", async ({
    tasks,
  }) => {
    await tasks.actionsCell(FIRST).focus()
    await tasks.press("Enter", "Tab")
    await expect(tasks.action(FIRST, "reassign")).toBeFocused()
    await tasks.press("Shift+Tab")
    await expect(tasks.action(FIRST, "archive")).toBeFocused()
    await tasks.press("Shift+Tab")
    await expect(tasks.actionsCell(FIRST), "as in a filter").toBeFocused()

    await tasks.press("Enter", "Tab", "Tab", "Tab")
    await expect(tasks.action(FIRST, "destroy")).toBeFocused()
    await tasks.press("Tab")
    await expect(tasks.action(FIRST, "set_labels")).toBeFocused()
    await tasks.press("Tab")
    expect(await tasks.hasFocus(), "after the last button Tab leaves the grid").toBe(false)
    await expect(tasks.pageButton(1)).toBeFocused()

    await tasks.press("Shift+Tab")
    await expect(tasks.actionsCell(FIRST), "the grid's one tab stop").toBeFocused()
  })

  test("Enter on a button runs its action, and so does Space; focus stays on the button", async ({
    tasks,
    frames,
  }) => {
    await tasks.actionsCell(FIRST).focus()
    await frames.clear()
    await tasks.press("Enter")
    await tasks.acts(FIRST, () => tasks.press("Enter"))

    await expect(tasks.cell(FIRST, "status")).toHaveText("Archived")
    await expect(tasks.action(FIRST, "archive"), "through the patch of its row").toBeFocused()
    expect(await frames.count("act")).toBe(1)
    expect(await frames.all()).toHaveLength(1)

    await tasks.press("Escape", "ArrowDown", "F2")
    await expect(tasks.action(SECOND, "archive")).toBeFocused()
    await tasks.acts(SECOND, () => tasks.press("Space"))
    await expect(tasks.cell(SECOND, "status")).toHaveText("Archived")
    await expect(tasks.action(SECOND, "archive")).toBeFocused()
    expect(await frames.count("act")).toBe(2)
    expect(await tasks.tabStops()).toEqual([`task-row-${SECOND}-a`])
  })
})

test.describe("an action that runs straight away", () => {
  test("a click on its button sends one event; the row comes back changed, and focus stays on the button", async ({
    tasks,
    frames,
  }) => {
    const height = await rowHeight(tasks, FIRST)
    await frames.clear()
    await tasks.acts(FIRST, () => tasks.action(FIRST, "archive").click())

    await expect(tasks.cell(FIRST, "status")).toHaveText("Archived")
    await expect(tasks.cell(SECOND, "status"), "and no other row").toHaveText("To do")
    await expect(tasks.action(FIRST, "archive")).toBeFocused()
    await expect(tasks.actionsCell(FIRST)).not.toHaveAttribute("aria-busy")
    await expect(tasks.actionsCell(FIRST)).not.toHaveAttribute("aria-invalid")
    await expect(tasks.status, "it is read out").toHaveText("Archive: done")
    expect(await frames.count("act")).toBe(1)
    expect(await frames.all()).toHaveLength(1)

    // the cell of the button is the grid's tab stop now, and the row is as high as it was
    expect(await tasks.tabStops()).toEqual([`task-row-${FIRST}-a`])
    expect(await rowHeight(tasks, FIRST)).toBeCloseTo(height, 0)
    await expect(tasks.actions(FIRST)).toHaveText(["Archive", "Reassign", "Set progress", "Destroy", "Set labels"])

    await tasks.page.reload()
    await tasks.ready()
    await expect(tasks.cell(FIRST, "status")).toHaveText("Archived")
  })

  test("a click beside the buttons is a click on the cell: nothing runs", async ({ tasks, frames }) => {
    const cell = tasks.actionsCell(FIRST)
    await cell.scrollIntoViewIfNeeded()
    const box = (await cell.boundingBox())!
    await frames.clear()
    // the right end of the cell, after its last button
    await tasks.page.mouse.click(box.x + box.width - 3, box.y + box.height / 2)

    await expect(cell).toBeFocused()
    expect(await frames.all()).toEqual([])
  })

  test.describe("on /task_labels", () => {
    test("a destroy action declared with `confirm false` runs at one click, on a row with a key of two parts", async ({
      page,
      frames,
    }) => {
      const taskLabels = new Table(page, "task_label", "/task_labels")
      await taskLabels.open()
      const { first, second, third } = SEED.taskLabel
      const total = SEED.taskLabels.acme
      await expect(taskLabels.actions(second)).toHaveText(["Remove"])
      await expect(taskLabels.action(second, "destroy")).not.toHaveAttribute("data-question")
      // The row's button asks nothing. The table has its dialog all the
      // same: the action asks when it runs on several rows (selection.spec.ts)
      await expect(taskLabels.question).toBeHidden()

      await frames.clear()
      await taskLabels.action(second, "destroy").click()

      await expect(taskLabels.row(second)).toHaveCount(0)
      expect((await taskLabels.rowKeys()).slice(0, 2)).toEqual([first, third])
      expect(await frames.count("act")).toBe(1)
      await expect(taskLabels.actionsCell(third), "the row after it").toBeFocused()
      await expect(taskLabels.range).toHaveText(`1–24 of ${total - 1}`)
      await expect(taskLabels.status).toHaveText("Remove: done")
    })
  })
})

test.describe("an action that asks first", () => {
  let cancel: Locator
  let confirm: Locator

  test.beforeEach(async ({ tasks }) => {
    cancel = tasks.question.getByRole("button", { name: "Cancel" })
    confirm = tasks.question.getByRole("button", { name: "Confirm" })
  })

  test("the dialog asks the action's question before anything is sent, and says by its colour that the answer deletes", async ({
    tasks,
    frames,
  }) => {
    await frames.clear()
    await tasks.action(SECOND, "destroy").click()

    // the table's own dialog, in the page, and not the browser's `confirm`
    // on top of it: `nativeDialogs` (support/fixtures.ts) ends every test
    // with that
    await expect(tasks.question).toBeVisible()
    await expect(tasks.question).toHaveRole("dialog")
    await expect(tasks.question).toHaveAccessibleName(QUESTION)
    await expect(cancel, "focus is on the safe answer").toBeFocused()
    await expect(confirm).toHaveClass(/\bbtn-error\b/)
    await expect(confirm).not.toHaveClass(/\bbtn-primary\b/)
    expect(await frames.all()).toEqual([])

    // Tab stays in the dialog
    await tasks.press("Tab")
    await expect(confirm).toBeFocused()
    for (let i = 0; i < 3; i++) {
      await tasks.press("Tab")
      expect(await tasks.hasFocus(), "the page behind is out of reach").toBe(false)
    }
  })

  test("Cancel sends nothing and puts focus back on the button; so does Escape", async ({
    tasks,
    frames,
  }) => {
    const destroy = tasks.action(SECOND, "destroy")
    await frames.clear()

    await destroy.click()
    await cancel.click()
    await answered(tasks)
    await expect(destroy).toBeFocused()

    // from the keyboard
    await tasks.press("Enter")
    await expect(tasks.question).toBeVisible()
    await tasks.press("Escape")
    await answered(tasks)
    await expect(destroy).toBeFocused()

    await expect(tasks.rows).toHaveCount(25)
    await expect(tasks.row(SECOND)).toBeVisible()
    await expect(tasks.actionsCell(SECOND)).not.toHaveAttribute("aria-busy")
    expect(await frames.all()).toEqual([])
    expect(await tasks.tabStops()).toEqual([`task-row-${SECOND}-a`])
  })

  test("the answer of a question that deletes nothing is not in the colour of one that does", async ({
    tasks,
  }) => {
    await tasks.action(SECOND, "destroy").click()
    await expect(confirm).toHaveClass(/\bbtn-error\b/)
    await cancel.click()
    await answered(tasks)

    // the question of the column `status`, in the same dialog
    const status = tasks.cell(SECOND, "status")
    await status.dblclick()
    await tasks.editor(status).selectOption({ label: "In review" })
    await expect(tasks.question).toHaveAccessibleName("Change the state of this task?")
    await expect(confirm).toHaveClass(/\bbtn-primary\b/)
    await expect(confirm).not.toHaveClass(/\bbtn-error\b/)
  })

  test("Confirm takes the row out of the page, counts it out, and puts focus on the same cell of the row after it", async ({
    page,
    tasks,
    frames,
  }) => {
    const total = SEED.tasks.acme
    await expect(tasks.range).toHaveText(`1–25 of ${total}`)
    // the records, the two header rows and the footer row of the summaries
    await expect(tasks.grid).toHaveAttribute("aria-rowcount", String(total + 3))
    expect(await tasks.rowIndexes()).toEqual(Array.from({ length: 25 }, (_, index) => index + 3))

    await tasks.action(SECOND, "destroy").click()
    await frames.clear()
    await confirm.click()

    await expect(tasks.row(SECOND)).toHaveCount(0)
    await expect(tasks.question).toBeHidden()
    await expect(tasks.rows).toHaveCount(24)
    expect((await tasks.rowKeys()).slice(0, 2)).toEqual([FIRST, THIRD])
    await expect(tasks.actionsCell(THIRD)).toBeFocused()
    expect(await tasks.tabStops()).toEqual([`task-row-${THIRD}-a`])
    expect(await frames.count("act")).toBe(1)

    await expect(tasks.range).toHaveText(`1–24 of ${total - 1}`)
    await expect(tasks.grid).toHaveAttribute("aria-rowcount", String(total + 2))
    await expect(tasks.status).toHaveText("Destroy: done")
    // every row says where it stands now, those that were not sent again too
    expect(await tasks.rowIndexes()).toEqual(Array.from({ length: 24 }, (_, index) => index + 3))

    // the arrow keys go on from there
    await tasks.press("ArrowUp")
    await expect(tasks.actionsCell(FIRST)).toBeFocused()

    await page.reload()
    await tasks.ready()
    await expect(tasks.row(SECOND)).toHaveCount(0)
    await expect(tasks.range).toHaveText(`1–25 of ${total - 1}`)
  })

  test("by keyboard all the way: Enter on the button, Tab to Confirm, Enter", async ({ tasks }) => {
    await tasks.actionsCell(SECOND).focus()
    await tasks.press("Enter", "ArrowRight", "ArrowRight", "ArrowRight")
    await expect(tasks.action(SECOND, "destroy")).toBeFocused()
    await tasks.press("Enter")
    await expect(cancel).toBeFocused()
    await tasks.press("Tab", "Enter")

    await expect(tasks.row(SECOND)).toHaveCount(0)
    await expect(tasks.actionsCell(THIRD)).toBeFocused()
    expect(await tasks.tabStops()).toEqual([`task-row-${THIRD}-a`])
  })

  test("the last row of the page: focus goes to the row before it; and what was open under the row goes with it", async ({
    tasks,
  }) => {
    const keys = await tasks.rowKeys()
    const last = keys.at(-1)!
    const before = keys.at(-2)!
    await tasks.openLine(last, "comments")

    await tasks.action(last, "destroy").click()
    await confirm.click()

    await expect(tasks.row(last)).toHaveCount(0)
    await expect(tasks.lines(last)).toHaveCount(0)
    await expect(tasks.nested(last, "comments").root).toHaveCount(0)
    await expect(tasks.actionsCell(before)).toBeFocused()
    expect(await tasks.tabStops()).toEqual([`task-row-${before}-a`])
    expect(await tasks.rowIndexes()).toEqual(Array.from({ length: 24 }, (_, index) => index + 3))
  })

  test("the only row of the page: the table reads again, and focus stays in the grid", async ({
    tasks,
  }) => {
    await tasks.open("/tasks?task[f][title]=Rename the onboarding email")
    await expect(tasks.rows).toHaveCount(1)
    const [only] = await tasks.rowKeys()

    await tasks.action(only, "destroy").click()
    await confirm.click()

    await expect(tasks.rows).toHaveCount(0)
    await expect(tasks.empty).toHaveText("No records")
    // no row is left to go to: the cell above where the first one was
    await expect(tasks.filterCell("title")).toBeFocused()
    expect(await tasks.tabStops()).toEqual(["task-filter-title"])
    // the two header rows and the footer row of the summaries
    await expect(tasks.grid).toHaveAttribute("aria-rowcount", "3")
  })
})

test.describe("an action that failed", () => {
  test.describe("as the member, who may change their own tasks only", () => {
    test.use({ actor: "member" })

    test("the actions cell is marked with the action's message, which is read out; focus is not moved", async ({
      page,
      tasks,
      frames,
    }) => {
      const cell = tasks.actionsCell(FIRST)
      const archive = tasks.action(FIRST, "archive")
      const message = tasks.failure(cell)
      const height = await rowHeight(tasks, FIRST)

      await frames.clear()
      await tasks.acts(FIRST, () => archive.click())

      await expect(archive, "focus stays on the button").toBeFocused()
      await expect(cell).toHaveAttribute("aria-invalid", "true")
      await expect(cell).toHaveAttribute("aria-describedby", `task-row-${FIRST}-a-error`)
      await expect(message).toHaveText(REFUSED)
      await expect(message).toHaveId(`task-row-${FIRST}-a-error`)
      await expect(cell).toHaveAccessibleDescription(REFUSED)
      await expect(tasks.status, "it is read out").toHaveText(`Archive failed: ${REFUSED}`)
      await expect(tasks.cell(FIRST, "status"), "nothing was changed").not.toHaveText("Archived")
      await expect(tasks.actions(FIRST)).toHaveText(["Archive", "Reassign", "Set progress", "Destroy", "Set labels"])
      expect(await frames.count("act")).toBe(1)

      // the message shows while the cell, or a button in it, has focus or the
      // pointer, and the row never grows
      await page.mouse.move(5, 5)
      await expect(message, "a button of the cell has the focus").toBeVisible()
      expect(await rowHeight(tasks, FIRST)).toBeCloseTo(height, 0)
      // under the cell, and in the window
      const below = (await message.boundingBox())!
      const box = (await cell.boundingBox())!
      expect(below.y).toBeGreaterThanOrEqual(box.y + box.height)
      expect(below.x + below.width).toBeLessThanOrEqual(page.viewportSize()!.width)

      await tasks.press("Escape")
      await expect(cell).toBeFocused()
      await expect(message, "the cell itself has it").toBeVisible()
      await tasks.press("ArrowDown")
      await expect(message).toBeHidden()

      await cell.hover()
      await expect(message).toBeVisible()
      await page.mouse.move(5, 5)
      await expect(message).toBeHidden()
      await archive.hover()
      await expect(message, "the pointer on a button is the pointer on the cell").toBeVisible()
      await page.mouse.move(5, 5)
    })

    test("Escape on a button goes back to the cell, and Escape on the cell gives the failure up", async ({
      tasks,
      frames,
    }) => {
      const cell = tasks.actionsCell(FIRST)
      await cell.focus()
      await tasks.press("Enter")
      await tasks.acts(FIRST, () => tasks.press("Enter"))
      await expect(cell).toHaveAttribute("aria-invalid", "true")
      await expect(tasks.action(FIRST, "archive")).toBeFocused()

      await frames.clear()
      await tasks.press("Escape")
      await expect(cell).toBeFocused()
      await expect(cell, "the first Escape leaves the button").toHaveAttribute("aria-invalid", "true")
      expect(await frames.all()).toEqual([])

      await tasks.press("Escape")
      await expect(cell).not.toHaveAttribute("aria-invalid")
      await expect(cell).not.toHaveAttribute("aria-describedby")
      await expect(tasks.failure(cell)).toHaveCount(0)
      await expect(cell).toBeFocused()
      expect(await frames.count("dismiss")).toBe(1)
      expect(await tasks.tabStops()).toEqual([`task-row-${FIRST}-a`])
      await expect(tasks.actions(FIRST)).toHaveText(["Archive", "Reassign", "Set progress", "Destroy", "Set labels"])
    })

    test("the next action that runs in the row clears it; one on their own task runs", async ({ tasks }) => {
      const own = SEED.task.membersOwn
      await tasks.acts(FIRST, () => tasks.action(FIRST, "archive").click())
      await expect(tasks.actionsCell(FIRST)).toHaveAttribute("aria-invalid", "true")

      await tasks.acts(own, () => tasks.action(own, "archive").click())
      await expect(tasks.cell(own, "status")).toHaveText("Archived")
      await expect(tasks.actionsCell(own)).not.toHaveAttribute("aria-invalid")
      await expect(tasks.action(own, "archive")).toBeFocused()
      // the other row's failure is that row's, and stays
      await expect(tasks.actionsCell(FIRST)).toHaveAttribute("aria-invalid", "true")
      await expect(tasks.failure(tasks.actionsCell(FIRST)), "without focus or pointer").toBeHidden()
    })

    test("a destroy that is refused leaves the row, with the refusal on its actions cell", async ({
      tasks,
    }) => {
      await tasks.action(FIRST, "destroy").click()
      await tasks.acts(FIRST, () => tasks.question.getByRole("button", { name: "Confirm" }).click())

      await expect(tasks.rows).toHaveCount(25)
      await expect(tasks.actionsCell(FIRST)).toHaveAttribute("aria-invalid", "true")
      await expect(tasks.failure(tasks.actionsCell(FIRST))).toHaveText(REFUSED)
      await expect(tasks.action(FIRST, "destroy"), "the dialog gave the focus back").toBeFocused()
      await expect(tasks.range).toHaveText(`1–25 of ${SEED.tasks.acme}`)
    })
  })

  test.describe("a record that is gone", () => {
    test("the hook marks the actions cell itself, and Escape on the cell takes the mark away", async ({
      request,
      tasks,
      frames,
    }) => {
      const key = await tasks.rowKey(6)
      const cell = tasks.actionsCell(key)
      const height = await rowHeight(tasks, key)
      await deleteTask(request, key)

      await tasks.acts(key, () => tasks.action(key, "archive").click())

      await expect(cell).toHaveAttribute("aria-invalid", "true")
      await expect(cell).toHaveAttribute("aria-describedby", `task-row-${key}-a-error`)
      await expect(tasks.failure(cell)).toHaveText(GONE)
      await expect(tasks.failure(cell), "focus is on a button of the cell").toBeVisible()
      await expect(cell).toHaveAccessibleDescription(GONE)
      await expect(tasks.status).toHaveText(`Archive failed: ${GONE}`)
      await expect(tasks.action(key, "archive")).toBeFocused()
      // the row is as it was: there was nothing to show it from
      await expect(tasks.rows).toHaveCount(25)
      await expect(tasks.actions(key)).toHaveText(["Archive", "Reassign", "Set progress", "Destroy", "Set labels"])
      expect(await rowHeight(tasks, key)).toBeCloseTo(height, 0)

      await frames.clear()
      await tasks.press("Escape", "Escape")
      await expect(cell).not.toHaveAttribute("aria-invalid")
      await expect(cell).not.toHaveAttribute("aria-describedby")
      await expect(tasks.failure(cell)).toHaveCount(0)
      await expect(cell).toBeFocused()
      await expect(tasks.actions(key)).toHaveText(["Archive", "Reassign", "Set progress", "Destroy", "Set labels"])
      expect(await frames.all(), "the mark was the hook's: the server is not asked").toEqual([])
    })

    test("an action with inputs opens no panel for it, and marks the cell", async ({ request, tasks }) => {
      const key = await tasks.rowKey(6)
      await deleteTask(request, key)

      await tasks.acts(key, () => tasks.action(key, "reassign").click())

      await expect(tasks.panel).toHaveCount(0)
      await expect(tasks.failure(tasks.actionsCell(key))).toHaveText(GONE)
      await expect(tasks.status).toHaveText(`Reassign failed: ${GONE}`)
      await expect(tasks.action(key, "reassign")).toBeFocused()
    })
  })
})

test.describe("the action panel", () => {
  test("is a modal dialog at the right edge of the window, named by its heading; focus moves to its first control", async ({
    page,
    tasks,
    frames,
  }) => {
    await frames.clear()
    await tasks.acts(FIRST, () => tasks.action(FIRST, "reassign").click())

    await expect(tasks.panel).toBeVisible()
    await expect(tasks.panel).toHaveRole("dialog")
    await expect(tasks.panel).toHaveAccessibleName("Reassign: Rename the onboarding email")
    await expect(tasks.panelTitle).toHaveRole("heading")
    expect(await tasks.panel.evaluate((panel) => panel.matches(":modal"))).toBe(true)
    expect(await frames.count("act")).toBe(1)
    // nothing has run
    await expect(tasks.status).toHaveText("")

    expect(await tasks.fields()).toEqual(["assignee_id", "reason"])
    // the first field holds the key of a related record: its control is the
    // button that opens the picker (picker.spec.ts)
    await expect(tasks.fieldChoose("assignee_id"), "the first control has the focus").toBeFocused()
    await expect(tasks.panelSubmit).toHaveText("Run")
    await expect(tasks.panelCancel).toHaveText("Cancel")

    // at the right edge, as high as the window, and no wider than a form needs
    const viewport = page.viewportSize()!
    const box = (await tasks.panel.boundingBox())!
    expect(box.x + box.width).toBeCloseTo(viewport.width, 0)
    expect(box.y).toBeCloseTo(0, 0)
    expect(box.height).toBeCloseTo(viewport.height, 0)
    expect(box.width).toBeCloseTo(448, 0)
  })

  test("Tab stays in the panel, and the page behind it is out of reach", async ({ page, tasks, frames }) => {
    await tasks.acts(FIRST, () => tasks.action(FIRST, "reassign").click())
    await expect(tasks.fieldChoose("assignee_id")).toBeFocused()
    await frames.clear()

    await tasks.press("Tab")
    await expect(tasks.field("reason")).toBeFocused()
    await tasks.press("Tab")
    await expect(tasks.panelCancel).toBeFocused()
    await tasks.press("Tab")
    await expect(tasks.panelSubmit).toBeFocused()
    // on from the last control, and back from the first: never into the page
    for (const key of ["Tab", "Tab", "Tab", "Shift+Tab", "Shift+Tab", "Shift+Tab", "Shift+Tab", "Shift+Tab"]) {
      await tasks.press(key)
      expect(await tasks.hasFocus(), `${key}: the grid is out of reach`).toBe(false)
      expect(
        await page.evaluate(() => {
          const active = document.activeElement
          return !active || active === document.body || !!active.closest("dialog")
        }),
        `${key}: focus is in the panel, or with the browser`,
      ).toBe(true)
    }

    // the pointer does not reach the page either: a click on a cell, and one on the create button
    const cell = (await tasks.cell(SECOND, "title").boundingBox())!
    await page.mouse.click(cell.x + 10, cell.y + cell.height / 2)
    await expect(tasks.cell(SECOND, "title")).not.toBeFocused()
    const create = (await tasks.create.boundingBox())!
    await page.mouse.click(create.x + create.width / 2, create.y + create.height / 2)
    await expect(tasks.panel, "a click beside the panel leaves it open").toBeVisible()
    await expect(tasks.panelTitle).toHaveText("Reassign: Rename the onboarding email")
    expect(await tasks.hasFocus()).toBe(false)
    expect(await frames.all()).toEqual([])
  })

  test("Escape closes it and nothing has run; focus is back on the button that opened it. Cancel does the same", async ({
    tasks,
    frames,
  }) => {
    const reassign = tasks.action(FIRST, "reassign")
    await tasks.acts(FIRST, () => reassign.click())
    await tasks.field("reason").fill("Never mind")
    await frames.clear()

    await tasks.press("Escape")
    await expect(tasks.panel).toHaveCount(0)
    await expect(reassign).toBeFocused()
    expect(await frames.count("panel_cancel")).toBe(1)
    expect(await frames.count("panel_submit")).toBe(0)
    expect(await tasks.tabStops()).toEqual([`task-row-${FIRST}-a`])

    // from the keyboard, and with Cancel
    await tasks.acts(FIRST, () => tasks.press("Enter"))
    await expect(tasks.fieldChoose("assignee_id")).toBeFocused()
    await expect(tasks.field("reason"), "opened again, it is empty").toHaveValue("")
    await tasks.panelCancel.click()
    await expect(tasks.panel).toHaveCount(0)
    await expect(reassign).toBeFocused()

    await tasks.acts(FIRST, () => tasks.press("Enter"))
    await tasks.press("Tab", "Tab")
    await expect(tasks.panelCancel).toBeFocused()
    await tasks.press("Enter")
    await expect(tasks.panel).toHaveCount(0)
    await expect(reassign).toBeFocused()
    await expect(tasks.status, "nothing ran").toHaveText("")

    // the grid is as it was: the arrow keys go on from the cell
    await tasks.press("Escape", "ArrowDown")
    await expect(tasks.actionsCell(SECOND)).toBeFocused()
  })

  test("Run runs the action with what the fields hold: the row comes back changed, and focus is on its button again", async ({
    tasks,
    frames,
  }) => {
    // the panel of an attribute shows the record's value
    const progress = tasks.action(SECOND, "set_progress")
    await tasks.acts(SECOND, () => progress.click())
    await expect(tasks.panelTitle).toHaveText("Set progress: Remove the dashboard charts")
    expect(await tasks.fields()).toEqual(["progress"])
    // the slider of the column's component (components.spec.ts)
    await expect(tasks.field("progress")).toHaveAttribute("type", "range")
    await expect(tasks.field("progress")).toHaveValue("5")
    await expect(tasks.field("progress")).toBeFocused()
    await expect(tasks.field("progress")).toHaveAccessibleName(/^Progress/)

    await tasks.field("progress").fill("60")
    await frames.clear()
    // Enter in a field of one line submits the form
    await tasks.press("Enter")

    await expect(tasks.panel).toHaveCount(0)
    await expect(tasks.cell(SECOND, "progress")).toHaveText("60")
    // `set_progress` starts a task that is still to do
    await expect(tasks.cell(SECOND, "status")).toHaveText("In progress")
    await expect(progress).toBeFocused()
    await expect(tasks.status).toHaveText("Set progress: done")
    expect(await frames.count("panel_submit")).toBe(1)
    expect(await tasks.tabStops()).toEqual([`task-row-${SECOND}-a`])

    // an argument and an attribute, with the button
    const reassign = tasks.action(SECOND, "reassign")
    await tasks.acts(SECOND, () => reassign.click())
    await expect(tasks.field("reason")).toHaveValue("")
    await expect(tasks.field("reason")).toHaveAttribute("aria-required", "true")
    await expect(tasks.field("reason")).toHaveAccessibleName(/^Reason/)
    await expect(tasks.panel.locator("[data-field=reason] label")).toHaveText(/Reason\s*\*/)
    await expect(tasks.field("assignee_id")).toHaveRole("group")
    await expect(tasks.field("assignee_id")).toHaveAccessibleName("Assignee")
    await expect(tasks.field("assignee_id").locator(".sr-only")).toHaveCount(0)
    await tasks.chooseField("assignee_id", null)
    await expect(tasks.fieldKey("assignee_id")).toHaveValue("")
    await tasks.field("reason").fill("Nobody has the time")
    await tasks.panelSubmit.click()

    await expect(tasks.panel).toHaveCount(0)
    await expect(tasks.cell(SECOND, "assignee")).toHaveText("")
    await expect(reassign).toBeFocused()
    await expect(tasks.status).toHaveText("Reassign: done")
  })

  test("says what the action makes of a field once that field was used, and of every field after Run", async ({
    page,
    tasks,
    frames,
  }) => {
    await tasks.acts(FIRST, () => tasks.action(FIRST, "reassign").click())
    const reason = tasks.field("reason")
    await expect(tasks.panel.locator("[data-error]")).toHaveCount(0)

    // too short: the field that was typed in says so
    await reason.focus()
    await page.keyboard.type("ab")
    await expect(tasks.fieldError("reason")).toHaveText("length must be greater than or equal to 3")
    await expect(reason).toHaveAttribute("aria-invalid", "true")
    // described by the message, and after it by its counter: the reason has a most it can be long
    await expect(reason).toHaveAttribute(
      "aria-describedby",
      "task-panel-f-reason-error task-panel-f-reason-count",
    )
    await expect(reason).toHaveAccessibleDescription("length must be greater than or equal to 3 2/200")
    await expect(reason, "typing keeps the focus and what was typed").toBeFocused()
    await expect(reason).toHaveValue("ab")
    expect(await frames.count("panel_validate")).toBeGreaterThan(0)
    expect(await frames.count("panel_submit")).toBe(0)

    // put right, it says nothing any more
    await page.keyboard.type("c")
    await expect(reason).not.toHaveAttribute("aria-invalid")
    await expect(tasks.fieldError("reason")).toHaveCount(0)
    await expect(reason).toHaveValue("abc")
    await expect(reason).toBeFocused()

    // Run with a field that was never used: its error shows now
    await tasks.panelCancel.click()
    await expect(tasks.panel).toHaveCount(0)
    await tasks.acts(FIRST, () => tasks.action(FIRST, "reassign").click())
    await expect(tasks.panel.locator("[data-error]")).toHaveCount(0)
    await frames.clear()
    await tasks.panelSubmit.click()

    await expect(tasks.fieldError("reason")).toHaveText("is required")
    await expect(tasks.field("reason")).toHaveAttribute("aria-invalid", "true")
    await expect(tasks.panel, "it stays open").toBeVisible()
    expect(await tasks.panel.evaluate((panel) => panel.matches(":modal"))).toBe(true)
    await expect(tasks.status).toHaveText("Reassign failed: Reason: is required")
    expect(await focusInPanel(tasks)).toBe(true)
    expect(await frames.count("panel_submit")).toBe(1)
    await expect(tasks.cell(FIRST, "status"), "nothing ran").not.toHaveText("Archived")
  })

  test.describe("as the member", () => {
    test.use({ actor: "member" })

    test("a refusal that is about no field stands above the fields as an alert, and the panel stays open", async ({
      tasks,
    }) => {
      // not the member's task: the action is theirs to try, and refused
      await tasks.acts(FIRST, () => tasks.action(FIRST, "reassign").click())
      await tasks.field("reason").fill("I will take it")
      await tasks.panelSubmit.click()

      await expect(tasks.panelErrors).toHaveText(REFUSED)
      await expect(tasks.panelErrors).toHaveRole("alert")
      await expect(tasks.panel).toBeVisible()
      await expect(tasks.field("reason"), "with what was typed").toHaveValue("I will take it")
      await expect(tasks.status).toHaveText(`Reassign failed: ${REFUSED}`)
      // above the first field
      const alert = (await tasks.panelErrors.boundingBox())!
      const field = (await tasks.field("assignee_id").boundingBox())!
      expect(alert.y + alert.height).toBeLessThanOrEqual(field.y)
      // the row is not marked: the panel has said it
      await expect(tasks.actionsCell(FIRST)).not.toHaveAttribute("aria-invalid")

      await tasks.press("Escape")
      await expect(tasks.panel).toHaveCount(0)
      await expect(tasks.action(FIRST, "reassign")).toBeFocused()
    })
  })

  test("an action that asks first asks when Run is used, in the dialog on top of the panel; Cancel comes back to the panel as it was", async ({
    page,
    tasks,
    frames,
  }) => {
    const cancel = tasks.question.getByRole("button", { name: "Cancel" })
    const confirm = tasks.question.getByRole("button", { name: "Confirm" })

    await tasks.acts(SECOND, () => tasks.action(SECOND, "set_progress").click())
    await tasks.field("progress").fill("70")
    // No action of the demo has both a question and inputs. The panel is
    // told of its action's question by this attribute, which the server
    // renders for one that has: it is put there by hand, after the last
    // patch of the panel.
    await tasks.panelSettled()
    await frames.clear()
    await tasks.panel.evaluate((panel) => panel.setAttribute("data-question", "Report this progress?"))

    await tasks.panelSubmit.click()
    await expect(tasks.question).toBeVisible()
    await expect(tasks.question).toHaveAccessibleName("Report this progress?")
    await expect(cancel).toBeFocused()
    await expect(confirm).toHaveClass(/\bbtn-primary\b/)
    expect(await frames.count("panel_submit"), "nothing is sent before the answer").toBe(0)

    // on top of the panel, which is still there behind it
    await expect(tasks.panel).toBeVisible()
    const box = (await tasks.question.boundingBox())!
    expect(
      await page.evaluate(
        ([x, y]) => document.elementFromPoint(x, y)?.closest("dialog")?.id,
        [box.x + box.width / 2, box.y + box.height / 2],
      ),
    ).toBe("task-dialog")
    // Tab stays in the dialog that asks
    for (let i = 0; i < 4; i++) {
      await tasks.press("Tab")
      expect(await focusInPanel(tasks), "the panel behind is out of reach").toBe(false)
      expect(await tasks.hasFocus()).toBe(false)
    }

    await cancel.click()
    await answered(tasks)
    await expect(tasks.panel).toBeVisible()
    await expect(tasks.panelSubmit, "focus is back where it was in the panel").toBeFocused()
    await expect(tasks.field("progress")).toHaveValue("70")
    expect(await frames.all()).toEqual([])

    // Escape answers the question, not the panel
    await tasks.press("Enter")
    await expect(tasks.question).toBeVisible()
    await tasks.press("Escape")
    await answered(tasks)
    await expect(tasks.panel).toBeVisible()
    await expect(tasks.panelSubmit).toBeFocused()
    expect(await frames.all()).toEqual([])

    await tasks.panelSubmit.click()
    await confirm.click()
    await expect(tasks.panel).toHaveCount(0)
    await expect(tasks.cell(SECOND, "progress")).toHaveText("70")
    await expect(tasks.action(SECOND, "set_progress")).toBeFocused()
    expect(await frames.count("panel_submit")).toBe(1)
  })

  test("the question can also be asked while a panel is open: it is on top, and gives the focus back to the panel", async ({
    tasks,
  }) => {
    await tasks.acts(FIRST, () => tasks.action(FIRST, "reassign").click())
    await tasks.field("reason").focus()

    const answer = tasks.hookRoot.evaluate((grid) => (grid as any)._ashTable.ask("Sure?", true))
    await expect(tasks.question).toBeVisible()
    await expect(tasks.question.getByRole("button", { name: "Confirm" })).toHaveClass(/\bbtn-error\b/)
    await tasks.press("Escape")

    expect(await answer).toBe(false)
    await expect(tasks.panel).toBeVisible()
    await expect(tasks.field("reason")).toBeFocused()
  })
})

test.describe("creating a record", () => {
  test("the create button stands on the line of the table's name: the name at the left end, the button at the right", async ({
    browser,
    page,
    tasks,
  }) => {
    await expect(tasks.name).toHaveText("Tasks")
    await expect(tasks.name).toHaveRole("heading")
    await expect(page.getByRole("heading", { level: 1 })).toHaveId("task-name")
    await expect(tasks.create).toHaveText("New task")
    await expect(tasks.create).toHaveRole("button")

    const line = (await tasks.headerLine.boundingBox())!
    const name = (await tasks.name.boundingBox())!
    const button = (await tasks.create.boundingBox())!
    const grid = (await tasks.hookRoot.boundingBox())!
    expect(name.x).toBeCloseTo(line.x, 0)
    expect(button.x + button.width).toBeCloseTo(line.x + line.width, 0)
    // the line is as wide as what is seen of the table, which scrolls sideways under it
    expect(line.x).toBeCloseTo(grid.x, 0)
    expect(line.width).toBeCloseTo(grid.width, 0)
    expect(button.x + button.width).toBeLessThanOrEqual(page.viewportSize()!.width)
    // both on one line, above the grid
    expect(Math.abs(name.y + name.height / 2 - (button.y + button.height / 2))).toBeLessThanOrEqual(1)
    expect(line.y + line.height).toBeLessThanOrEqual(grid.y)

    // the line is as high without the button: the table stands where it stands for a viewer
    const viewers = await asActor(browser, page, "viewer", async (other) => {
      const table = new Table(other, "task", "/tasks")
      await table.open()
      await expect(table.create).toHaveCount(0)
      return {
        line: (await table.headerLine.boundingBox())!.height,
        grid: (await table.hookRoot.boundingBox())!.y,
      }
    })
    expect(line.height).toBeCloseTo(viewers.line, 0)
    expect(grid.y).toBeCloseTo(viewers.grid, 0)
  })

  test("it is a tab stop before the grid, opens the panel with the create action's inputs, and gets the focus back", async ({
    page,
    tasks,
    frames,
  }) => {
    // before the grid stand "Columns" (hiding.spec.ts) and the inputs of
    // the argument line, and before those the create button
    await tasks.cell(FIRST, "title").focus()
    await page.keyboard.press("Shift+Tab")
    await expect(tasks.columnsButton).toBeFocused()
    await page.keyboard.press("Shift+Tab")
    await expect(tasks.argument("due_within-days")).toBeFocused()
    await page.keyboard.press("Shift+Tab")
    await expect(tasks.argument("search")).toBeFocused()
    await page.keyboard.press("Shift+Tab")
    await expect(tasks.create).toBeFocused()

    await frames.clear()
    await page.keyboard.press("Enter")
    await expect(tasks.panel).toBeVisible()
    await expect(tasks.panel).toHaveAccessibleName("New task")
    expect(await tasks.panel.evaluate((panel) => panel.matches(":modal"))).toBe(true)
    await expect(tasks.panelSubmit).toHaveText("Create")
    expect(await frames.count("create")).toBe(1)
    expect(await tasks.fields()).toEqual([
      "title",
      "description",
      "status",
      "priority",
      "progress",
      "estimate_hours",
      "billable?",
      "due_on",
      "external_ref",
      "project_id",
      "assignee_id",
      "tags",
      "checks",
      "recurrence",
    ])
    await expect(tasks.field("title"), "the first field has the focus").toBeFocused()

    // each field is the control of its type, and starts with its attribute's default
    await expect(tasks.field("title")).toHaveJSProperty("tagName", "TEXTAREA")
    await expect(tasks.field("title")).toHaveValue("")
    await expect(tasks.field("status")).toHaveJSProperty("tagName", "SELECT")
    await expect(tasks.field("status")).toHaveValue("todo")
    await expect(tasks.field("priority")).toHaveValue("medium")
    await expect(tasks.field("progress")).toHaveAttribute("type", "range")
    await expect(tasks.field("progress")).toHaveValue("0")
    await expect(tasks.field("estimate_hours")).toHaveAttribute("type", "number")
    await expect(tasks.field("billable?")).toHaveAttribute("type", "checkbox")
    await expect(tasks.field("billable?")).not.toBeChecked()
    await expect(tasks.field("due_on")).toHaveAttribute("type", "date")
    // the key of a related record: what it is called and a button, as a group
    await expect(tasks.field("project_id")).toHaveRole("group")
    await expect(tasks.fieldKey("project_id")).toHaveValue("")
    await expect(tasks.fieldKey("project_id")).toBeHidden()
    await expect(tasks.fieldChoose("project_id")).toHaveText("Choose")

    // named by their labels, as the columns are; what has to be given says so
    await expect(tasks.field("status")).toHaveAccessibleName(/^State/)
    await expect(tasks.field("billable?")).toHaveAccessibleName("Billable?")
    for (const name of ["title", "status", "priority", "progress"]) {
      await expect(tasks.field(name), name).toHaveAttribute("aria-required", "true")
    }
    for (const name of ["description", "estimate_hours", "billable?", "due_on"]) {
      await expect(tasks.field(name), name).not.toHaveAttribute("aria-required")
    }
    // a group cannot say that it is required: its name does
    await expect(tasks.field("project_id")).toHaveAccessibleName(/^Project\s+required$/)
    await expect(tasks.field("assignee_id")).toHaveAccessibleName("Assignee")

    await tasks.press("Escape")
    await expect(tasks.panel).toHaveCount(0)
    await expect(tasks.create).toBeFocused()
    // the grid behind it is as it was, after the inputs of the argument
    // line and "Columns"
    for (let stops = 0; stops < 4; stops++) await page.keyboard.press("Tab")
    await expect(tasks.cell(FIRST, "title")).toBeFocused()
  })

  test("a field of every type is filled in, and the new record is the first row of the page, with the focus on its first cell", async ({
    page,
    tasks,
    frames,
  }) => {
    const total = SEED.tasks.acme
    const before = await tasks.rowKeys()
    await tasks.create.click()
    await expect(tasks.field("title")).toBeFocused()

    // text, with the keyboard: Enter is a new line in it, and submits nothing
    await page.keyboard.type("Made in the browser")
    await tasks.field("description").focus()
    await page.keyboard.type("First line")
    await page.keyboard.press("Enter")
    await page.keyboard.type("second line")
    await expect(tasks.field("description")).toHaveValue("First line\nsecond line")
    await expect(tasks.panel).toBeVisible()

    // a choice, by pointer and by keyboard
    await tasks.field("status").selectOption({ label: "In review" })
    await tasks.field("priority").focus()
    await page.keyboard.press("u")
    await expect(tasks.field("priority")).toHaveValue("urgent")
    // numbers
    await tasks.field("progress").fill("35")
    await tasks.field("estimate_hours").fill("2.5")
    // a box, with Space
    await tasks.field("billable?").focus()
    await page.keyboard.press("Space")
    await expect(tasks.field("billable?")).toBeChecked()
    // a date, and the key of a related record, which is chosen
    await tasks.field("due_on").fill("2031-02-03")
    await tasks.field("external_ref").fill("EXT-E2E")
    await tasks.chooseField("project_id", SEED.project.mobileApp)

    // what was typed first is still there after everything the server has said since
    await expect(tasks.field("title")).toHaveValue("Made in the browser")
    await expect(tasks.panel.locator("[data-error]")).toHaveCount(0)

    await frames.clear()
    await tasks.panelSubmit.click()
    await expect(tasks.panel).toHaveCount(0)
    expect(await frames.count("panel_submit")).toBe(1)

    // the first row of the page, before the rows that were there
    await expect(tasks.rows).toHaveCount(26)
    const keys = await tasks.rowKeys()
    const created = keys[0]
    expect(keys.slice(1)).toEqual(before)
    await expect(tasks.cell(created, "title")).toHaveText("Made in the browser")
    expect(await tasks.cell(created, "description").textContent()).toBe("First line\nsecond line")
    await expect(tasks.cell(created, "status")).toHaveText("In review")
    await expect(tasks.cell(created, "priority")).toHaveText("Urgent")
    await expect(tasks.cell(created, "progress")).toHaveText("35")
    await expect(tasks.cell(created, "estimate_hours")).toHaveText("2.5 h")
    await expect(tasks.cell(created, "billable?")).toContainText("Yes")
    await expect(tasks.cell(created, "due_on")).toHaveText("2031-02-03")
    await expect(tasks.cell(created, "external_ref")).toHaveText("EXT-E2E")
    await expect(tasks.cell(created, "project")).toHaveText("Mobile app")
    await expect(tasks.cell(created, "reporter"), "the person who created it").toHaveText("Ada Admin")
    await expect(tasks.actions(created)).toHaveText(["Archive", "Reassign", "Set progress", "Destroy", "Set labels"])
    await expect(tasks.expander(created)).toHaveAttribute("aria-expanded", "false")

    // focus is on its first data cell, which is the grid's tab stop
    await expect(tasks.cell(created, "title")).toBeFocused()
    expect(await tasks.tabStops()).toEqual([`task-row-${created}-c-title`])

    // counted in, and every row says where it stands now
    await expect(tasks.range).toHaveText(`1–26 of ${total + 1}`)
    // with the two header rows and the footer row of the summaries
    await expect(tasks.grid).toHaveAttribute("aria-rowcount", String(total + 4))
    expect(await tasks.rowIndexes()).toEqual(Array.from({ length: 26 }, (_, index) => index + 3))
    await expect(tasks.status).toHaveText("Task created")

    // a row like the others: the arrow keys, an edit, an action, and what it expands into
    await tasks.press("ArrowDown")
    await expect(tasks.cell(FIRST, "title")).toBeFocused()
    await tasks.press("ArrowUp", "Enter")
    await tasks.retype("Made and renamed")
    await tasks.saves(tasks.cell(created, "title"), () => tasks.press("Enter"))
    await expect(tasks.cell(created, "title")).toHaveText("Made and renamed")
    const comments = await tasks.openLine(created, "comments")
    await expect(comments.empty).toHaveText("No records")

    // taken away again, the rows are numbered as before
    await tasks.action(created, "destroy").click()
    await tasks.question.getByRole("button", { name: "Confirm" }).click()
    await expect(tasks.row(created)).toHaveCount(0)
    await expect(tasks.actionsCell(FIRST)).toBeFocused()
    expect(await tasks.rowKeys()).toEqual(before)
    expect(await tasks.rowIndexes()).toEqual(Array.from({ length: 25 }, (_, index) => index + 3))
    await expect(tasks.range).toHaveText(`1–25 of ${total}`)
    await expect(tasks.grid).toHaveAttribute("aria-rowcount", String(total + 3))
  })

  test("on a later page the new row is the first of that page, and the rows count on from the page's first", async ({
    tasks,
  }) => {
    const total = SEED.tasks.acme
    await tasks.reads(() => tasks.next.click())
    await expect(tasks.range).toHaveText(`26–50 of ${total}`)
    expect(await tasks.rowIndexes()).toEqual(Array.from({ length: 25 }, (_, index) => index + 28))

    await tasks.create.click()
    await tasks.field("title").fill("Made on page two")
    await tasks.chooseField("project_id", SEED.project.mobileApp)
    await tasks.panelSubmit.click()
    await expect(tasks.panel).toHaveCount(0)

    await expect(tasks.rows).toHaveCount(26)
    const created = await tasks.rowKey(1)
    await expect(tasks.cell(created, "title")).toHaveText("Made on page two")
    await expect(tasks.cell(created, "title")).toBeFocused()
    expect(await tasks.rowIndexes()).toEqual(Array.from({ length: 26 }, (_, index) => index + 28))
    await expect(tasks.range).toHaveText(`26–51 of ${total + 1}`)

    // the next read puts it where it belongs: the newest task is the first of page one
    await tasks.reads(() => tasks.previous.click())
    expect(await tasks.rowKey(1)).toBe(created)
    await expect(tasks.range).toHaveText(`1–25 of ${total + 1}`)
  })

  test("the panel says what is wrong with a field once it was used, and with every field after Create; nothing is created", async ({
    page,
    tasks,
  }) => {
    await tasks.create.click()
    // the panel comes from the server: what is typed before it has opened goes nowhere
    await expect(tasks.field("title")).toBeFocused()
    await page.keyboard.type("ab")

    await expect(tasks.fieldError("title")).toHaveText("length must be greater than or equal to 3")
    await expect(tasks.field("title")).toHaveAttribute("aria-invalid", "true")
    await expect(tasks.field("title")).toBeFocused()
    // the project is required too, and was not touched yet
    await expect(tasks.fieldError("project_id")).toHaveCount(0)
    await expect(tasks.panel.locator("[data-error]")).toHaveCount(1)

    await tasks.panelSubmit.click()
    await expect(tasks.fieldError("project_id")).toHaveText("is required")
    await expect(tasks.field("project_id")).toHaveAccessibleDescription("is required")
    await expect(tasks.fieldError("title")).toHaveText("length must be greater than or equal to 3")
    await expect(tasks.panel).toBeVisible()
    await expect(tasks.status).toHaveText(/^New task failed: /)
    await expect(tasks.rows).toHaveCount(25)
    await expect(tasks.range).toHaveText(`1–25 of ${SEED.tasks.acme}`)

    // put right, it is created
    await tasks.field("title").fill("abc")
    await expect(tasks.fieldError("title")).toHaveCount(0)
    await tasks.chooseField("project_id", SEED.project.mobileApp)
    await expect(tasks.fieldError("project_id")).toHaveCount(0)
    await tasks.panelSubmit.click()
    await expect(tasks.panel).toHaveCount(0)
    await expect(tasks.cell(await tasks.rowKey(1), "title")).toHaveText("abc")
  })

  test.describe("as the member", () => {
    test.use({ actor: "member" })

    test("creates tasks, without the field of what they never see; and has no button where they may not create", async ({
      page,
      tasks,
    }) => {
      await tasks.create.click()
      expect(await tasks.fields()).not.toContain("external_ref")
      expect(await tasks.fields()).toContain("estimate_hours")
      await tasks.field("title").fill("A member's task")
      await tasks.chooseField("project_id", SEED.project.mobileApp)
      await tasks.panelSubmit.click()

      await expect(tasks.panel).toHaveCount(0)
      const created = await tasks.rowKey(1)
      await expect(tasks.cell(created, "title")).toBeFocused()
      await expect(tasks.cell(created, "reporter")).toHaveText("Max Member")

      for (const [path, id, name] of [
        ["/projects", "project", "Projects"],
        ["/labels", "label", "Labels"],
      ]) {
        const table = new Table(page, id, path)
        await table.open()
        await expect(table.name).toHaveText(name)
        await expect(table.create).toHaveCount(0)
      }
    })
  })
})

test.describe("creating in a nested table", () => {
  /** How high the lines under a row are, top to bottom. */
  async function lineHeights(table: Table, key: string): Promise<number[]> {
    return table
      .lines(key)
      .evaluateAll((cells) => cells.map((cell) => cell.parentElement!.getBoundingClientRect().height))
  }

  test("the create button stands on the line of a has-many, after its label, once the nested table has read; the line is as high as it was", async ({
    page,
    tasks,
  }) => {
    const create = tasks.lineCreate(FIRST, "comments")
    await tasks.expand(FIRST)
    const closed = await lineHeights(tasks, FIRST)
    await expect(create, "a closed line has none").toHaveCount(0)

    // Watches the page while the line opens: whenever the nested table says
    // that it is loading, is the button to be seen?
    await page.evaluate(
      ([loading, button]) => {
        const seen: boolean[] = []
        ;(window as any).__whileLoading = seen
        new MutationObserver(() => {
          const create = document.getElementById(button)
          if (document.getElementById(loading) && create) seen.push(create.getClientRects().length > 0)
        }).observe(document.body, { subtree: true, childList: true })
      },
      [`${tasks.nested(FIRST, "comments").id}-loading`, `task-row-${FIRST}-l-comments-create`],
    )

    const comments = await tasks.openLine(FIRST, "comments")
    const whileLoading: boolean[] = await page.evaluate(() => (window as any).__whileLoading)
    expect(whileLoading.length, "the nested table was seen loading").toBeGreaterThan(0)
    expect(whileLoading, "and the button was not to be seen then").not.toContain(true)

    await expect(create).toBeVisible()
    await expect(create).toHaveText("New comment")
    await expect(create).toHaveAttribute("tabindex", "-1")
    await expect(tasks.line(FIRST, "comments"), "the line's own button says what it said").toHaveText("Comments")
    expect(await tasks.tabStops(), "the tree is one tab stop still").toHaveLength(1)

    // on the line, right after the label
    const label = (await tasks.line(FIRST, "comments").boundingBox())!
    const button = (await create.boundingBox())!
    const cell = (await tasks.lineCell(FIRST, "comments").boundingBox())!
    expect(button.x).toBeGreaterThanOrEqual(label.x + label.width)
    expect(button.x - (label.x + label.width)).toBeLessThanOrEqual(12)
    expect(button.y).toBeGreaterThanOrEqual(cell.y)
    expect(button.y + button.height).toBeLessThanOrEqual(cell.y + cell.height)

    // no line is higher for it, and the nested table looks as any table does
    expect(await lineHeights(tasks, FIRST)).toEqual(closed)
    await expect(comments.headerLine, "its name is the line").toHaveCount(0)
    await expect(comments.create).toHaveCount(0)

    // a has-one, a many-to-many and a belongs-to have none
    for (const relationship of ["first_comment", "labels", "project"]) {
      await tasks.openLine(FIRST, relationship)
      await expect(tasks.lineCreate(FIRST, relationship), relationship).toHaveCount(0)
    }
    expect(await lineHeights(tasks, FIRST)).toEqual(closed)

    // closed again, the button is gone with the table
    await tasks.line(FIRST, "comments").click()
    await expect(comments.root).toHaveCount(0)
    await expect(create).toHaveCount(0)
    expect(await lineHeights(tasks, FIRST)).toEqual(closed)
  })

  test("with the pointer: the button opens the panel of the nested table, and the new record is its first row, with the focus", async ({
    tasks,
    frames,
  }) => {
    const comments = await tasks.openLine(FIRST, "comments")
    const create = tasks.lineCreate(FIRST, "comments")
    const before = await comments.rowKeys()
    const [first] = await comments.columns()
    const count = await tasks.cell(FIRST, "comment_count").textContent()

    await frames.clear()
    await create.click()
    await expect(comments.panel).toBeVisible()
    await expect(comments.panel).toHaveAccessibleName("New comment")
    expect(await comments.panel.evaluate((panel) => panel.matches(":modal"))).toBe(true)
    // the field that joins the comment to the task is the table's to give
    expect(await comments.fields()).toEqual(["body"])
    await expect(comments.field("body")).toBeFocused()
    await expect(tasks.panel, "the table around it has no panel for it").toHaveCount(0)
    await expect(tasks.line(FIRST, "comments"), "the line stays open").toHaveAttribute("aria-expanded", "true")
    expect(await frames.count("create")).toBe(1)
    expect(await frames.count("toggle")).toBe(0)

    // given up, focus is back on the line's button
    await tasks.press("Escape")
    await expect(comments.panel).toHaveCount(0)
    await expect(create).toBeFocused()
    expect(await tasks.tabStops()).toEqual([`task-row-${FIRST}-l-comments-c`])

    await create.click()
    await comments.field("body").fill("Said in the browser")
    await comments.panelSubmit.click()
    await expect(comments.panel).toHaveCount(0)

    await expect(comments.rows).toHaveCount(before.length + 1)
    const keys = await comments.rowKeys()
    const created = keys[0]
    expect(keys.slice(1)).toEqual(before)
    await expect(comments.cell(created, "body")).toHaveText("Said in the browser")
    await expect(comments.cell(created, first), "its first data cell").toBeFocused()
    expect(await tasks.tabStops()).toEqual([`${comments.id}-row-${created}-c-${first}`])
    expect(await comments.rowIndexes()).toEqual(keys.map((_, index) => index + 3))
    await expect(comments.status).toHaveText("Comment created")
    await expect(tasks.status, "the table around it says nothing").toHaveText("")

    // the row above is not read again for it, and everything around stays open
    await expect(tasks.cell(FIRST, "comment_count")).toHaveText(count!)
    await expect(tasks.line(FIRST, "comments")).toHaveAttribute("aria-expanded", "true")
    await expect(create).toBeVisible()

    // Escape comes back out of the nested table, as from any of its cells
    await tasks.press("Escape")
    await expect(tasks.nestedCell(FIRST, "comments")).toBeFocused()
  })

  test("with the keyboard: F2 on the line goes into its controls, the arrow keys move between them, Enter uses one", async ({
    tasks,
    frames,
  }) => {
    const comments = await tasks.openLine(FIRST, "comments")
    const line = tasks.lineCell(FIRST, "comments")
    const toggle = tasks.line(FIRST, "comments")
    const create = tasks.lineCreate(FIRST, "comments")
    await line.focus()
    await frames.clear()

    await tasks.press("F2")
    await expect(toggle, "first the button that opens the line").toBeFocused()
    await tasks.press("ArrowLeft")
    await expect(toggle, "Left ends at the first control").toBeFocused()
    await tasks.press("ArrowRight")
    await expect(create).toBeFocused()
    await tasks.press("ArrowRight")
    await expect(create, "Right ends at the last").toBeFocused()
    await tasks.press("ArrowLeft")
    await expect(toggle).toBeFocused()
    await tasks.press("Escape")
    await expect(line).toBeFocused()
    expect(await frames.all(), "none of it asks the server anything").toEqual([])
    expect(await tasks.tabStops()).toEqual([`task-row-${FIRST}-l-comments-c`])
    await expect(toggle).toHaveAttribute("aria-expanded", "true")

    // Enter on the create button opens the panel; Escape gives the focus back to it
    await tasks.press("F2", "ArrowRight", "Enter")
    await expect(comments.panel).toBeVisible()
    await expect(comments.field("body")).toBeFocused()
    expect(await frames.count("create")).toBe(1)
    expect(await frames.count("toggle"), "the line was not used").toBe(0)
    await tasks.press("Escape")
    await expect(comments.panel).toHaveCount(0)
    await expect(create).toBeFocused()

    // and Space does as Enter; the record is created by keyboard alone
    await tasks.press("Space")
    await expect(comments.field("body")).toBeFocused()
    await tasks.page.keyboard.type("Typed, not clicked")
    await tasks.press("Tab", "Tab")
    await expect(comments.panelSubmit).toBeFocused()
    await tasks.press("Enter")
    await expect(comments.panel).toHaveCount(0)
    const created = await comments.rowKey(1)
    await expect(comments.cell(created, "body")).toHaveText("Typed, not clicked")
    expect(await comments.hasFocus()).toBe(true)
    expect(await tasks.tabStops()).toHaveLength(1)
  })

  test("the line itself is used as before: Enter opens and closes it, Right opens and Left closes; and its own button can be used from the keyboard", async ({
    tasks,
  }) => {
    await tasks.expand(FIRST)
    const line = tasks.lineCell(FIRST, "comments")
    const toggle = tasks.line(FIRST, "comments")
    const comments = tasks.nested(FIRST, "comments")
    await line.focus()

    // closed, the line has one control, and F2 has nothing to go into
    await tasks.press("F2")
    await expect(line).toBeFocused()

    await tasks.press("Enter")
    await comments.loaded()
    await expect(line).toBeFocused()
    await tasks.press("Enter")
    await expect(comments.root).toHaveCount(0)
    await tasks.press("ArrowRight")
    await comments.loaded()
    await expect(tasks.lineCreate(FIRST, "comments")).toBeVisible()
    await tasks.press("ArrowRight")
    await expect(line, "open already: Right has nowhere to go on a line").toBeFocused()
    await tasks.press("ArrowLeft")
    await expect(comments.root).toHaveCount(0)
    await expect(line).toBeFocused()

    // from inside: Enter on the line's own button closes the line, and focus is not lost
    await tasks.press("ArrowRight")
    await comments.loaded()
    await tasks.press("F2")
    await expect(toggle).toBeFocused()
    await tasks.press("Enter")
    await expect(toggle).toHaveAttribute("aria-expanded", "false")
    await expect(comments.root).toHaveCount(0)
    expect(await tasks.hasFocus()).toBe(true)
    expect(await tasks.tabStops()).toEqual([`task-row-${FIRST}-l-comments-c`])
  })

  test("under a project, its tasks are created with every field but the one that joins them to it", async ({
    page,
  }) => {
    const projects = new Table(page, "project", "/projects")
    await projects.open()
    const nested = await projects.openLine(SEED.project.mobileApp, "tasks")
    const create = projects.lineCreate(SEED.project.mobileApp, "tasks")
    await expect(create).toHaveText("New task")
    await expect(nested.range).toHaveText("1–25 of 57")

    await create.click()
    expect(await nested.fields()).not.toContain("project_id")
    expect(await nested.fields()).toContain("title")
    await nested.field("title").fill("Made under its project")
    await nested.panelSubmit.click()
    await expect(nested.panel).toHaveCount(0)

    const created = await nested.rowKey(1)
    await expect(nested.cell(created, "title")).toHaveText("Made under its project")
    await expect(nested.cell(created, "title")).toBeFocused()
    await expect(nested.range).toHaveText("1–26 of 58")
    expect(await nested.rowIndexes()).toEqual(Array.from({ length: 26 }, (_, index) => index + 3))
    expect(await projects.tabStops()).toEqual([`${nested.id}-row-${created}-c-title`])

    // its own row actions run in the nested table: the panel is that table's
    await nested.acts(created, () => nested.action(created, "set_progress").click())
    await expect(nested.panel).toHaveAccessibleName("Set progress: Made under its project")
    await nested.field("progress").fill("10")
    await nested.panelSubmit.click()
    await expect(nested.panel).toHaveCount(0)
    await expect(nested.cell(created, "progress")).toHaveText("10")
    await expect(nested.action(created, "set_progress")).toBeFocused()
    await expect(projects.panel).toHaveCount(0)

    // and a destroy takes the row out of it, with the focus on the row after
    await nested.action(created, "destroy").click()
    await expect(nested.question).toBeVisible()
    await expect(projects.question, "the question is the nested table's own").toBeHidden()
    await nested.question.getByRole("button", { name: "Confirm" }).click()
    await expect(nested.row(created)).toHaveCount(0)
    await expect(nested.actionsCell(await nested.rowKey(1))).toBeFocused()
    await expect(nested.range).toHaveText("1–25 of 57")
    await expect(projects.line(SEED.project.mobileApp, "tasks")).toHaveAttribute("aria-expanded", "true")
  })

  test.describe("as the viewer", () => {
    test.use({ actor: "viewer" })

    test("no line has a create button for a person who may never create", async ({ tasks }) => {
      const comments = await tasks.openLine(FIRST, "comments")
      await expect(comments.rows.first()).toBeVisible()
      await expect(tasks.lineCreate(FIRST, "comments")).toHaveCount(0)
      await expect(tasks.grid.locator("button[data-create]")).toHaveCount(0)
      // F2 on the line has nothing to go into
      await tasks.lineCell(FIRST, "comments").focus()
      await tasks.press("F2")
      await expect(tasks.lineCell(FIRST, "comments")).toBeFocused()
    })
  })
})

test.describe("creating in the full view", () => {
  test("the create button is on the line that says what the table shows, before the way back; the record is created under that row", async ({
    page,
  }) => {
    const comments = new Table(page, "comment", "/comments")
    await comments.open(`/comments?comment[of][task][comments]=${FIRST}`)
    await expect(comments.relatedHeading).toHaveText("Rename the onboarding email: Comments")
    const before = await comments.rowKeys()

    // the line of the page's name has no button of its own
    await expect(comments.name).toHaveText("Comments")
    await expect(comments.headerLine.getByRole("button")).toHaveCount(0)
    await expect(comments.create).toHaveText("New comment")
    const heading = (await comments.relatedHeading.boundingBox())!
    const create = (await comments.create.boundingBox())!
    const clear = (await comments.relatedClear.boundingBox())!
    expect(heading.x).toBeLessThan(create.x)
    expect(create.x + create.width).toBeLessThanOrEqual(clear.x)
    expect(Math.abs(create.y + create.height / 2 - (clear.y + clear.height / 2))).toBeLessThanOrEqual(1)
    expect(create.height, "as high as the control beside it").toBeCloseTo(clear.height, 0)

    // tab stops in that order, before the grid
    await comments.create.focus()
    await page.keyboard.press("Tab")
    await expect(comments.relatedClear).toBeFocused()
    await page.keyboard.press("Shift+Tab")
    await page.keyboard.press("Enter")

    await expect(comments.panel).toHaveAccessibleName("New comment")
    expect(await comments.fields()).toEqual(["body"])
    await comments.field("body").fill("Said in the full view")
    await comments.panelSubmit.click()
    await expect(comments.panel).toHaveCount(0)

    const keys = await comments.rowKeys()
    expect(keys.slice(1)).toEqual(before)
    await expect(comments.cell(keys[0], "body")).toHaveText("Said in the full view")
    const [first] = await comments.columns()
    await expect(comments.cell(keys[0], first)).toBeFocused()
    await expect(comments.range).toHaveText(`${keys.length} records`)
    await expect(comments.relatedHeading).toHaveText("Rename the onboarding email: Comments")

    // it is a comment of that task: the task's line shows it
    const tasks = new Table(page, "task", "/tasks")
    await tasks.open()
    const nested = await tasks.openLine(FIRST, "comments")
    expect(await nested.columnTexts("body")).toContain("Said in the full view")
  })

  test("a table limited to nothing it can show has no create button", async ({ page }) => {
    const comments = new Table(page, "comment", "/comments")
    // a task that is not there
    await page.goto("/comments?comment[of][task][comments]=00000000-0000-4000-8000-000000000000")
    await expect(comments.error).toHaveText(GONE)
    await expect(comments.create).toHaveCount(0)
    await expect(comments.relatedClear).toBeVisible()
  })
})

test.describe("the two tables of /dashboard", () => {
  let projects: Table
  let tasks: Table

  test.beforeEach(async ({ page }) => {
    projects = new Table(page, "dashboard-projects", "/dashboard")
    tasks = new Table(page, "dashboard-tasks", "/dashboard")
    await projects.open()
    await tasks.ready()
  })

  test("each names itself on a line with its create button, and each has a panel and a dialog of its own", async ({
    page,
  }) => {
    await expect(page.getByRole("heading", { level: 2 })).toHaveText(["Projects", "Tasks"])
    await expect(projects.name).toHaveJSProperty("tagName", "H2")
    await expect(tasks.name).toHaveJSProperty("tagName", "H2")
    await expect(projects.create).toHaveText("New project")
    await expect(tasks.create).toHaveText("New task")

    for (const table of [projects, tasks]) {
      const line = (await table.headerLine.boundingBox())!
      const name = (await table.name.boundingBox())!
      const button = (await table.create.boundingBox())!
      expect(name.x).toBeCloseTo(line.x, 0)
      expect(button.x + button.width).toBeCloseTo(line.x + line.width, 0)
      expect(button.x + button.width).toBeLessThanOrEqual(page.viewportSize()!.width)
    }

    // a row action of the projects, whose input is a choice with the record's value
    const key = await projects.rowKey(1)
    await expect(projects.actions(key)).toHaveText([
      "Set status",
      "Set budget",
      "Destroy",
      "Assign open tasks",
    ])
    const before = await projects.cell(key, "status").getAttribute("data-value")
    await projects.acts(key, () => projects.action(key, "set_status").click())
    await expect(projects.panel).toBeVisible()
    await expect(tasks.panel, "the other table has none").toHaveCount(0)
    await expect(projects.field("status")).toHaveJSProperty("tagName", "SELECT")
    await expect(projects.field("status")).toHaveValue(before!)
    await expect(projects.field("status")).toBeFocused()
    const other = before === "on_hold" ? "active" : "on_hold"
    await projects.field("status").selectOption(other)
    await projects.panelSubmit.click()
    await expect(projects.panel).toHaveCount(0)
    await expect(projects.cell(key, "status")).toHaveAttribute("data-value", other)
    await expect(projects.action(key, "set_status")).toBeFocused()
    await expect(projects.status).toHaveText("Set status: done")
    await expect(tasks.status).toHaveText("")

    // the question of each table is asked in its own dialog
    await tasks.action(FIRST, "destroy").click()
    await expect(tasks.question).toBeVisible()
    await expect(projects.question).toBeHidden()
    await tasks.press("Escape")
    await expect(tasks.question).toBeHidden()
    await expect(tasks.action(FIRST, "destroy")).toBeFocused()

    // every id in the page is used once, with a panel open
    await tasks.create.click()
    await expect(tasks.panel).toBeVisible()
    const ids = await page.locator("[id]").evaluateAll((elements) => elements.map((e) => e.id))
    expect(ids.filter((id, index) => ids.indexOf(id) !== index)).toEqual([])
  })

  test("a task created there is the first row of its table, and the other table is as it was", async ({
    page,
  }) => {
    const url = page.url()
    const projectKeys = await projects.rowKeys()
    await tasks.create.click()
    await tasks.field("title").fill("Made on the dashboard")
    await tasks.chooseField("project_id", SEED.project.mobileApp)
    await tasks.panelSubmit.click()
    await expect(tasks.panel).toHaveCount(0)

    const created = await tasks.rowKey(1)
    await expect(tasks.cell(created, "title")).toHaveText("Made on the dashboard")
    await expect(tasks.cell(created, "title")).toBeFocused()
    await expect(tasks.range).toHaveText(`1–26 of ${SEED.tasks.acme + 1}`)
    expect(await projects.rowKeys()).toEqual(projectKeys)
    await expect(projects.range).toHaveText("1–6 of 6")
    // each grid keeps its own tab stop
    expect(await tasks.tabStops()).toEqual([`dashboard-tasks-row-${created}-c-title`])
    expect(await projects.tabStops()).toHaveLength(1)
    expect(page.url()).toBe(url)
  })
})

test.describe("the look", () => {
  for (const width of [1500, 900]) {
    test(`at ${width} px: the name and the create button at the two ends of what is seen of the table, the panel at the right edge`, async ({
      page,
      tasks,
    }) => {
      await page.setViewportSize({ width, height: 900 })
      await tasks.ready()

      const line = (await tasks.headerLine.boundingBox())!
      const name = (await tasks.name.boundingBox())!
      const button = (await tasks.create.boundingBox())!
      const grid = (await tasks.hookRoot.boundingBox())!
      expect(name.x).toBeCloseTo(line.x, 0)
      expect(button.x + button.width).toBeCloseTo(line.x + line.width, 0)
      expect(line.x).toBeCloseTo(grid.x, 0)
      expect(line.x + line.width).toBeCloseTo(grid.x + grid.width, 0)
      expect(line.x).toBeGreaterThanOrEqual(0)
      expect(line.x + line.width).toBeLessThanOrEqual(width)
      // the table is wider than the window: it scrolls sideways under the line
      expect(await tasks.hookRoot.evaluate((grid) => grid.scrollWidth > grid.clientWidth)).toBe(true)

      // the actions are the last column: scrolled to, a button of it can be used
      const destroy = tasks.action(FIRST, "destroy")
      await destroy.scrollIntoViewIfNeeded()
      const box = (await destroy.boundingBox())!
      expect(box.x + box.width).toBeLessThanOrEqual(grid.x + grid.width)
      expect((await tasks.actionsCell(FIRST).boundingBox())!.height).toBeCloseTo(
        (await tasks.cell(FIRST, "reporter").boundingBox())!.height,
        0,
      )

      await tasks.acts(FIRST, () => tasks.action(FIRST, "reassign").click())
      const panel = (await tasks.panel.boundingBox())!
      expect(panel.x + panel.width).toBeCloseTo(width, 0)
      expect(panel.width).toBeCloseTo(448, 0)
      expect(panel.y).toBeCloseTo(0, 0)
      expect(panel.height).toBeCloseTo(900, 0)
      // its fields are as wide as the panel lets them be, and its buttons at the right
      const field = (await tasks.field("reason").boundingBox())!
      expect(field.x).toBeGreaterThan(panel.x)
      expect(field.x + field.width).toBeLessThan(panel.x + panel.width)
      expect(field.width).toBeGreaterThan(panel.width - 60)
      const submit = (await tasks.panelSubmit.boundingBox())!
      expect(submit.x + submit.width).toBeCloseTo(field.x + field.width, 0)
    })
  }

  test("on a narrow window the panel is as wide as the window, and everything in it can be reached", async ({
    page,
    tasks,
  }) => {
    await page.setViewportSize({ width: 390, height: 700 })
    await tasks.ready()

    const line = (await tasks.headerLine.boundingBox())!
    const button = (await tasks.create.boundingBox())!
    expect(line.x).toBeGreaterThanOrEqual(0)
    expect(button.x + button.width).toBeLessThanOrEqual(390)
    expect((await tasks.name.boundingBox())!.x).toBeCloseTo(line.x, 0)

    await tasks.create.click()
    const panel = (await tasks.panel.boundingBox())!
    expect(panel.x).toBeCloseTo(0, 0)
    expect(panel.width).toBeCloseTo(390, 0)
    expect(panel.height).toBeCloseTo(700, 0)
    // no wider inside than the window: nothing of it is cut off at the side
    expect(await tasks.panel.evaluate((panel) => panel.scrollWidth <= panel.clientWidth)).toBe(true)
    // eleven fields are higher than the window: the panel scrolls, and its buttons are at its end
    expect(await tasks.panel.evaluate((panel) => panel.scrollHeight > panel.clientHeight)).toBe(true)
    await tasks.panelSubmit.scrollIntoViewIfNeeded()
    await expect(tasks.panelSubmit).toBeInViewport()
    const submit = (await tasks.panelSubmit.boundingBox())!
    expect(submit.x + submit.width).toBeLessThanOrEqual(390)

    await tasks.field("title").fill("Made on a narrow window")
    await tasks.chooseField("project_id", SEED.project.mobileApp)
    await tasks.panelSubmit.click()
    await expect(tasks.panel).toHaveCount(0)
    await expect(tasks.cell(await tasks.rowKey(1), "title")).toHaveText("Made on a narrow window")
  })
})
