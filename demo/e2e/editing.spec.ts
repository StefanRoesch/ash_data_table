import type { Locator, Page } from "@playwright/test"
import { expect, test } from "./support/fixtures"
import { deleteTask, SEED } from "./support/data"
import { Table } from "./support/table"

// Spec sections 8 and 9: inline editing on /tasks as the admin, who may
// change every task. These tests save: the database is seeded again after
// each of them (`writes`).

const FIRST = SEED.task.first
// still to do, with a progress of 5
const SECOND = SEED.task.second
const THIRD = SEED.task.third

const TOO_SHORT = "length must be greater than or equal to 3"

test.use({ writes: true })

test.beforeEach(async ({ tasks }) => {
  await tasks.open()
})

/** The height of a row, which editing and a failed save must not change. */
async function rowHeight(tasks: Table, key: string): Promise<number> {
  const box = await tasks.row(key).getByRole("row").boundingBox()
  return box!.height
}

/**
 * Lets a `<select>` editor open as the closed menu it is. The hook opens the
 * browser's menu when it can (`showPicker`); where that menu is in the way
 * of what a test is about, the test takes it away first, as a browser
 * without `showPicker` would.
 */
async function withoutMenu(page: Page): Promise<void> {
  await page.evaluate(() => {
    HTMLSelectElement.prototype.showPicker = () => {
      throw new DOMException("no menu in this test", "NotSupportedError")
    }
  })
}

/** Slows the page's talk with the server down, as LiveView's own latency simulator does. */
async function withLatency(page: Page, milliseconds: number): Promise<void> {
  await page.evaluate((ms) => (window as any).liveSocket.enableLatencySim(ms), milliseconds)
}

test.afterEach(async ({ page }) => {
  // the simulator remembers itself in the session storage
  await page.evaluate(() => (window as any).liveSocket?.disableLatencySim())
})

test.describe("which cells can be edited", () => {
  test("a cell that cannot be edited says so, and no key opens it", async ({ tasks, frames }) => {
    // a calculation, an aggregate, a column with `update_action false`, and
    // an attribute no action accepts
    for (const column of ["overdue?", "comment_count", "headline", "external_ref", "inserted_at"]) {
      await expect(tasks.cell(FIRST, column)).toHaveAttribute("aria-readonly", "true")
    }
    for (const column of ["title", "status", "priority", "progress", "estimate_hours"]) {
      await expect(tasks.cell(FIRST, column)).not.toHaveAttribute("aria-readonly")
    }
    await expect(tasks.editorTemplates).toHaveCount(9)

    const headline = tasks.cell(FIRST, "headline")
    await headline.focus()
    await frames.clear()
    await tasks.press("Enter", "F2", "x")
    await headline.dblclick()
    await expect(tasks.openEditors).toHaveCount(0)
    await expect(headline).toBeFocused()
    expect(await frames.all()).toEqual([])
  })
})

test.describe("starting and giving up an edit", () => {
  test("Enter opens the column's editor in the cell, with the cell's value", async ({
    page,
    tasks,
    frames,
  }) => {
    const title = tasks.cell(FIRST, "title")
    const editor = tasks.editor(title)
    const height = await rowHeight(tasks, FIRST)

    await title.focus()
    await frames.clear()
    await tasks.press("Enter")

    await expect(editor).toBeFocused()
    await expect(editor).toHaveValue("Rename the onboarding email")
    await expect(editor).toHaveAccessibleName("Title")
    expect(await rowHeight(tasks, FIRST), "the row keeps its height").toBeCloseTo(height, 0)
    expect(await tasks.tabStops(), "the grid is one tab stop: the editor").toEqual(["TEXTAREA"])

    // the keys that move through the grid are the editor's now
    await tasks.press("ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", "Home", "End")
    await expect(editor).toBeFocused()

    await page.keyboard.type(" changed")
    await tasks.press("Escape")
    await expect(title).toHaveText("Rename the onboarding email")
    await expect(title).toBeFocused()
    await expect(tasks.openEditors).toHaveCount(0)
    expect(await tasks.tabStops()).toEqual([`task-row-${FIRST}-c-title`])
    expect(await frames.all(), "the server heard nothing of it").toEqual([])
  })

  test("F2 opens the editor; Enter on a value that has not changed saves nothing", async ({
    tasks,
    frames,
  }) => {
    const title = tasks.cell(FIRST, "title")
    await title.focus()
    await frames.clear()

    await tasks.press("F2")
    await expect(tasks.editor(title)).toBeFocused()
    await expect(tasks.editor(title)).toHaveValue("Rename the onboarding email")

    await tasks.press("Enter")
    await expect(title).toBeFocused()
    await expect(title).toHaveText("Rename the onboarding email")
    await expect(title).not.toHaveAttribute("aria-busy")
    expect(await frames.all()).toEqual([])

    // typed over with the same text: still nothing to save
    await tasks.press("Enter")
    await tasks.retype("Rename the onboarding email")
    await tasks.press("Enter")
    await expect(title).toBeFocused()
    expect(await frames.all()).toEqual([])
  })

  test("a printable key starts the edit with that character", async ({ tasks }) => {
    const title = tasks.cell(FIRST, "title")
    await title.focus()
    await tasks.press("Z")

    await expect(tasks.editor(title)).toBeFocused()
    await expect(tasks.editor(title), "typing replaces the text").toHaveValue("Z")
    await tasks.press("Escape")
    await expect(title).toHaveText("Rename the onboarding email")
  })

  test("a double click opens the editor", async ({ tasks }) => {
    const title = tasks.cell(SECOND, "title")
    await title.dblclick()

    await expect(tasks.editor(title)).toBeFocused()
    await expect(tasks.editor(title)).toHaveValue("Remove the dashboard charts")
    // a click in the editor stays in the editor
    await tasks.editor(title).click()
    await expect(tasks.editor(title)).toBeFocused()
    await tasks.press("Escape")
    await expect(title).toBeFocused()
  })
})

test.describe("saving", () => {
  test("Enter saves, and focus stays on the cell", async ({ page, tasks, frames }) => {
    const title = tasks.cell(FIRST, "title")
    await title.focus()
    await frames.clear()
    await tasks.press("Enter")
    await tasks.retype("Edited in the browser")

    await tasks.saves(title, async () => {
      await tasks.press("Enter")
      await expect(title, "at once, before the server has answered").toBeFocused()
    })

    await expect(title).toHaveText("Edited in the browser")
    await expect(title, "and after the row was patched").toBeFocused()
    expect(await frames.count("save")).toBe(1)
    expect(await tasks.tabStops()).toEqual([`task-row-${FIRST}-c-title`])
    // the row is shown from the action's result: its calculation has followed
    await expect(tasks.cell(FIRST, "headline")).toContainText("Edited in the browser")

    await page.reload()
    await tasks.ready()
    await expect(title).toHaveText("Edited in the browser")
  })

  test("leaving the cell saves: a click elsewhere, with focus left where the click went", async ({
    tasks,
  }) => {
    const estimate = tasks.cell(FIRST, "estimate_hours")
    const elsewhere = tasks.cell(SECOND, "title")

    await estimate.focus()
    await tasks.press("Enter")
    await tasks.retype("3.25")
    await tasks.saves(estimate, () => elsewhere.click())

    await expect(estimate).toHaveText("3.25 h")
    await expect(elsewhere).toBeFocused()
    await expect(tasks.openEditors).toHaveCount(0)
  })

  test("Tab and Shift+Tab save and leave the grid, and come back to the cell", async ({ tasks }) => {
    const estimate = tasks.cell(FIRST, "estimate_hours")
    await estimate.focus()
    await tasks.press("Enter")
    await tasks.retype("5")

    await tasks.saves(estimate, () => tasks.press("Tab"))
    await expect(estimate).toHaveText("5 h")
    expect(await tasks.hasFocus(), "Tab left the grid").toBe(false)
    await expect(tasks.pageButton(1)).toBeFocused()

    await tasks.press("Shift+Tab")
    await expect(estimate).toBeFocused()

    await tasks.press("Enter")
    await tasks.retype("6.5")
    await tasks.saves(estimate, () => tasks.press("Shift+Tab"))
    await expect(estimate).toHaveText("6.5 h")
    expect(await tasks.hasFocus(), "Shift+Tab left the grid, backwards").toBe(false)
    await expect(tasks.pageButton(1)).not.toBeFocused()
    expect(await tasks.tabStops()).toEqual([`task-row-${FIRST}-c-estimate_hours`])

    await tasks.press("Tab")
    await expect(estimate).toBeFocused()
  })

  // "Estimate hours" is edited with the demo's own component, whose control
  // is a number input: it behaves as the table's own number editor does.
  test("a number: a digit starts with that digit, a letter keeps the number, empty saves nothing as the value", async ({
    tasks,
  }) => {
    const estimate = tasks.cell(FIRST, "estimate_hours")
    const editor = tasks.editor(estimate)
    await expect(estimate).toHaveText("39 h")

    await estimate.focus()
    await tasks.press("7")
    await expect(editor).toHaveValue("7")
    await expect(editor).toHaveAttribute("type", "number")
    await tasks.press("Escape")

    await tasks.press("a")
    await expect(editor).toBeFocused()
    await expect(editor, "a number input takes no letter").toHaveValue("39")
    await tasks.press("Escape")
    await expect(estimate).toHaveText("39 h")

    // emptied: the action decides what that becomes, here nil
    await tasks.press("Enter")
    await tasks.retype("")
    await tasks.saves(estimate, () => tasks.press("Enter"))
    await expect(estimate).toHaveText("")
    await expect(estimate).not.toHaveAttribute("aria-invalid")
  })

  test("the number editor of the table itself, on /specimens: a digit starts with that digit, a letter keeps the number", async ({
    page,
  }) => {
    // on /tasks both numbers have a component; this one has the editor of its type
    const specimens = new Table(page, "specimen", "/specimens")
    await specimens.open()
    const integer = specimens.cell(SEED.specimens.first, "an_integer")
    const editor = specimens.editor(integer)
    const before = (await integer.textContent())!
    expect(before).toMatch(/^-?\d+$/)

    await integer.focus()
    await specimens.press("7")
    await expect(editor).toHaveValue("7")
    await expect(editor).toHaveAttribute("type", "number")
    await specimens.press("Escape")
    await expect(integer).toHaveText(before)

    await specimens.press("a")
    await expect(editor).toBeFocused()
    await expect(editor, "a number input takes no letter").toHaveValue(before)
    await specimens.press("Escape")
    await expect(integer).toHaveText(before)
    await expect(integer).toBeFocused()
  })

  test("a date: typing keeps the date; a new date saves, and the row's calculation follows", async ({
    tasks,
  }) => {
    const due = tasks.cell(SECOND, "due_on")
    const editor = tasks.editor(due)
    const before = (await due.textContent())!
    await expect(tasks.cell(SECOND, "overdue?")).toContainText("No")

    await due.focus()
    await tasks.press("q")
    await expect(editor).toBeFocused()
    await expect(editor).toHaveAttribute("type", "date")
    await expect(editor, "a letter changes nothing").toHaveValue(before)
    await tasks.press("Escape")

    await tasks.press("1")
    await expect(editor).toBeFocused()
    await expect(editor, "a digit goes into the date's first part").not.toHaveValue(before)
    await expect(editor).not.toHaveValue("")
    await tasks.press("Escape")
    await expect(due).toHaveText(before)

    await tasks.press("Enter")
    await editor.fill("2001-02-03")
    await tasks.saves(due, () => tasks.press("Enter"))
    await expect(due).toHaveText("2001-02-03")
    await expect(due).toBeFocused()
    await expect(tasks.cell(SECOND, "overdue?"), "a task due long ago is overdue").toContainText("Yes")
  })

  test("a datetime saves to the second", async ({ tasks }) => {
    const completed = tasks.cell(FIRST, "completed_at")
    await completed.focus()
    await tasks.press("Enter")
    await expect(tasks.editor(completed)).toHaveAttribute("type", "datetime-local")

    await tasks.editor(completed).fill("2031-02-03T04:05:06")
    await tasks.saves(completed, () => tasks.press("Enter"))
    await expect(completed).toHaveText("2031-02-03T04:05:06")
  })

  test("a checkbox cell toggles with Enter or F2 and saves at once; Space and typing do nothing", async ({
    tasks,
    frames,
  }) => {
    const billable = tasks.cell(FIRST, "billable?")
    await expect(billable).toHaveAttribute("data-value", "true")
    await expect(billable).toContainText("Yes")

    await billable.focus()
    await frames.clear()
    await tasks.press("Space", "x")
    await expect(billable).toHaveAttribute("data-value", "true")
    await expect(tasks.openEditors).toHaveCount(0)
    expect(await frames.all()).toEqual([])

    await tasks.saves(billable, () => tasks.press("Enter"))
    await expect(billable).toHaveAttribute("data-value", "false")
    await expect(billable).toContainText("No")
    await expect(billable).toBeFocused()

    await tasks.saves(billable, () => tasks.press("F2"))
    await expect(billable).toHaveAttribute("data-value", "true")
    await expect(billable).toContainText("Yes")
    await expect(billable).toBeFocused()
    expect(await frames.count("save")).toBe(2)
  })

  test("text of several lines: Shift+Enter makes a line, Enter saves", async ({ page, tasks }) => {
    const description = tasks.cell(FIRST, "description")
    const editor = tasks.editor(description)
    const height = await rowHeight(tasks, FIRST)

    await description.focus()
    await tasks.press("Enter")
    await tasks.retype("First line")
    await tasks.press("Shift+Enter")
    await page.keyboard.type("second line")
    await expect(editor).toBeFocused()
    await expect(editor).toHaveValue("First line\nsecond line")
    expect(await rowHeight(tasks, FIRST), "the editor grows with its text").toBeGreaterThan(height)

    await tasks.saves(description, () => tasks.press("Enter"))
    expect(await description.textContent()).toBe("First line\nsecond line")
    expect(await rowHeight(tasks, FIRST), "the row is one line high again").toBeCloseTo(height, 0)

    await tasks.press("Enter")
    await expect(editor, "the editor shows both lines again").toHaveValue("First line\nsecond line")
    await tasks.press("Escape")
  })

  test("a column with an action of its own saves through it: progress starts a task", async ({
    tasks,
  }) => {
    // `set_progress` moves a task that is still to do to "In progress"
    const progress = tasks.cell(SECOND, "progress")
    await expect(tasks.cell(SECOND, "status")).toHaveText("To do")

    // the column's editor is a slider (components.spec.ts): End is its maximum
    await progress.focus()
    await tasks.press("Enter", "End")
    await tasks.saves(progress, () => tasks.press("Enter"))

    await expect(progress).toHaveText("100")
    await expect(tasks.cell(SECOND, "status"), "the same row, from the action's result").toHaveText(
      "In progress",
    )
    await expect(tasks.cell(SECOND, "status")).toHaveAttribute("data-value", "in_progress")
  })

  test("an editable cell of every type on /specimens saves", async ({ page }) => {
    const specimens = new Table(page, "specimen", "/specimens")
    await specimens.open()
    const key = await specimens.rowKey(1)

    const text = specimens.cell(key, "a_string")
    await text.focus()
    await specimens.press("Enter")
    await specimens.retype("A specimen, edited")
    await specimens.saves(text, () => specimens.press("Enter"))
    await expect(text).toHaveText("A specimen, edited")

    const integer = specimens.cell(key, "an_integer")
    await integer.focus()
    await specimens.press("Enter")
    await specimens.retype("12")
    await specimens.saves(integer, () => specimens.press("Enter"))
    await expect(integer).toHaveText("12")

    // the attribute has `min: -1000, max: 1000`
    await specimens.press("Enter")
    await specimens.retype("5000")
    await specimens.saves(integer, () => specimens.press("Enter"))
    await expect(integer).toHaveAttribute("aria-invalid", "true")
    await expect(specimens.failure(integer)).toHaveText("must be less than or equal to 1000")

    await page.reload()
    await specimens.ready()
    await expect(text).toHaveText("A specimen, edited")
    await expect(integer).toHaveText("12")
  })
})

test.describe("a choice", () => {
  test("Enter opens the menu at the cell's value; moving through it saves nothing, Enter saves", async ({
    tasks,
    frames,
  }) => {
    const priority = tasks.cell(FIRST, "priority")
    const editor = tasks.editor(priority)
    await expect(priority).toHaveText("Medium")

    await priority.focus()
    await frames.clear()
    await tasks.press("Enter")
    await expect(editor).toBeFocused()
    await expect(editor).toHaveValue("medium")
    await expect(editor).toHaveAccessibleName("Priority")
    await expect(editor.locator("option")).toHaveText(["Low", "Medium", "High", "Urgent"])

    await tasks.press("ArrowDown")
    await expect(editor).toBeFocused()
    expect(await frames.count("save")).toBe(0)

    await tasks.saves(priority, () => tasks.press("Enter"))
    await expect(priority).toHaveText("High")
    await expect(priority).toHaveAttribute("data-value", "high")
    await expect(priority).toBeFocused()
    expect(await frames.count("save")).toBe(1)
  })

  test("a choice made with the pointer saves when it is made", async ({ tasks, frames }) => {
    const priority = tasks.cell(FIRST, "priority")
    await priority.dblclick()
    await frames.clear()

    await tasks.saves(priority, () => tasks.editor(priority).selectOption({ label: "Low" }))
    await expect(priority).toHaveText("Low")
    await expect(priority).toBeFocused()
    await expect(tasks.openEditors).toHaveCount(0)
    expect(await frames.count("save")).toBe(1)
  })

  test("a letter opens the menu at the first choice that starts with it, unsaved; Escape gives it up", async ({
    page,
    tasks,
    frames,
  }) => {
    await withoutMenu(page)
    const priority = tasks.cell(FIRST, "priority")
    await priority.focus()
    await frames.clear()

    await tasks.press("u")
    await expect(tasks.editor(priority)).toBeFocused()
    await expect(tasks.editor(priority)).toHaveValue("urgent")
    expect(await frames.count("save")).toBe(0)

    await tasks.press("Escape")
    await expect(priority).toHaveText("Medium")
    await expect(priority).toBeFocused()
    expect(await frames.all()).toEqual([])
  })

  test("in a closed menu the arrow keys change the value without saving; Enter or leaving saves", async ({
    page,
    tasks,
    frames,
  }) => {
    await withoutMenu(page)
    const priority = tasks.cell(FIRST, "priority")
    const editor = tasks.editor(priority)
    await priority.focus()
    await frames.clear()

    await tasks.press("Enter", "ArrowDown", "ArrowDown")
    await expect(editor).toBeFocused()
    await expect(editor).toHaveValue("urgent")
    expect(await frames.count("save"), "a step through the choices is not yet a choice").toBe(0)

    await tasks.saves(priority, () => tasks.press("Enter"))
    await expect(priority).toHaveText("Urgent")
    await expect(priority).toBeFocused()

    await tasks.press("Enter", "ArrowUp")
    await expect(editor).toHaveValue("high")
    await tasks.saves(priority, () => tasks.cell(SECOND, "title").click())
    await expect(priority).toHaveText("High")
    expect(await frames.count("save")).toBe(2)
  })

  test("with the browser's menu open, Escape closes the menu first and the editor stays", async ({
    tasks,
    frames,
  }) => {
    const priority = tasks.cell(FIRST, "priority")
    const editor = tasks.editor(priority)
    await priority.focus()
    await frames.clear()

    await tasks.press("Enter")
    await expect(editor).toBeFocused()
    await tasks.press("Escape")
    await expect(editor, "the first Escape is the menu's").toBeFocused()

    await tasks.press("Escape")
    await expect(priority).toBeFocused()
    await expect(priority).toHaveText("Medium")
    expect(await frames.all()).toEqual([])
  })
})

test.describe("a column that asks before it saves", () => {
  // `status` is declared with `confirm "Change the state of this task?"`
  let status: Locator
  let editor: Locator
  let cancel: Locator
  let confirm: Locator

  /**
   * The dialog has closed and the hook has heard of it. The browser tells
   * the page that a dialog closed in a task of its own; a key that a test
   * presses before that is over arrives while the hook still waits for the
   * answer, and is ignored. No person is that fast.
   */
  async function answered(tasks: Table) {
    await expect(tasks.dialog).toBeHidden()
    await tasks.page.evaluate(() => new Promise((resolve) => setTimeout(resolve, 0)))
  }

  test.beforeEach(async ({ page, tasks, frames }) => {
    await withoutMenu(page)
    status = tasks.cell(SECOND, "status")
    editor = tasks.editor(status)
    cancel = tasks.dialog.getByRole("button", { name: "Cancel" })
    confirm = tasks.dialog.getByRole("button", { name: "Confirm" })

    // "To do" becomes "In progress" in the editor, and Enter commits
    await status.focus()
    await frames.clear()
    await tasks.press("Enter", "ArrowDown")
    await expect(editor).toHaveValue("in_progress")
    await tasks.press("Enter")
    await expect(tasks.dialog).toBeVisible()
  })

  test("the dialog opens at the moment of commit, before anything is saved", async ({
    tasks,
    frames,
  }) => {
    await expect(tasks.dialog).toBeVisible()
    await expect(tasks.dialog).toHaveAccessibleName("Change the state of this task?")
    await expect(cancel, "focus is on the safe answer").toBeFocused()
    expect(await frames.count("save")).toBe(0)

    // Tab stays in the dialog
    await tasks.press("Tab")
    await expect(confirm).toBeFocused()
    for (let i = 0; i < 3; i++) {
      await tasks.press("Tab")
      expect(await tasks.hasFocus(), "the page behind is out of reach").toBe(false)
    }
  })

  test("Cancel returns to the editor, with what was chosen", async ({ tasks, frames }) => {
    await cancel.click()
    await answered(tasks)

    await expect(editor).toBeFocused()
    await expect(editor).toHaveValue("in_progress")
    expect(await frames.count("save")).toBe(0)

    // and the question comes again at the next commit
    await tasks.press("Enter")
    await expect(tasks.dialog).toBeVisible()
    await cancel.click()
    await answered(tasks)
    await tasks.press("Escape")
    await expect(status).toHaveText("To do")
    await expect(status).toBeFocused()
    expect(await frames.all()).toEqual([])
  })

  test("Escape in the dialog acts as Cancel", async ({ tasks, frames }) => {
    await tasks.press("Escape")
    await answered(tasks)

    await expect(editor).toBeFocused()
    await expect(editor).toHaveValue("in_progress")
    expect(await frames.count("save")).toBe(0)
  })

  test("Confirm saves, and focus returns to the cell", async ({ tasks, frames }) => {
    await tasks.saves(status, () => confirm.click())

    await expect(tasks.dialog).toBeHidden()
    await expect(status).toHaveText("In progress")
    await expect(status).toBeFocused()
    expect(await frames.count("save")).toBe(1)
  })

  test("Confirm by keyboard saves too", async ({ tasks }) => {
    await tasks.press("Tab")
    await tasks.saves(status, () => tasks.press("Enter"))

    await expect(status).toHaveText("In progress")
    await expect(status).toBeFocused()
  })

  test("leaving the cell asks too: Cancel pulls back into the editor, Confirm leaves focus where it went", async ({
    tasks,
    frames,
  }) => {
    const elsewhere = tasks.cell(THIRD, "title")
    await cancel.click()
    await answered(tasks)
    await expect(editor).toBeFocused()

    await elsewhere.click()
    await expect(tasks.dialog).toBeVisible()
    expect(await frames.count("save")).toBe(0)
    await cancel.click()
    await answered(tasks)
    await expect(editor).toBeFocused()
    await expect(editor).toHaveValue("in_progress")

    await elsewhere.click()
    await expect(tasks.dialog).toBeVisible()
    await tasks.saves(status, () => confirm.click())
    await expect(status).toHaveText("In progress")
    await expect(elsewhere).toBeFocused()
    expect(await frames.count("save")).toBe(1)
  })

  test("a choice made with the pointer asks as well", async ({ tasks, frames }) => {
    await cancel.click()
    await answered(tasks)
    await editor.selectOption({ label: "In review" })

    await expect(tasks.dialog).toBeVisible()
    expect(await frames.count("save")).toBe(0)
    await tasks.saves(status, () => confirm.click())
    await expect(status).toHaveText("In review")
  })
})

test.describe("a save that fails", () => {
  // a title must have three characters
  async function typeTooShort(tasks: Table, title: Locator) {
    await title.focus()
    await tasks.press("Enter")
    await tasks.retype("ab")
  }

  test("focus is not pulled back; the cell keeps what was typed and is marked with the action's message", async ({
    page,
    tasks,
  }) => {
    const title = tasks.cell(SECOND, "title")
    const elsewhere = tasks.cell(THIRD, "progress")
    const message = tasks.failure(title)
    const height = await rowHeight(tasks, SECOND)

    await typeTooShort(tasks, title)
    await tasks.saves(title, () => elsewhere.click())

    await expect(elsewhere, "focus stays where the person went").toBeFocused()
    await expect(title).toHaveAttribute("aria-invalid", "true")
    await expect(title).toHaveAttribute("data-value", "ab")
    await expect(title).toHaveAttribute("data-saved", "Remove the dashboard charts")
    await expect(title).toContainText("ab")
    await expect(message).toHaveText(TOO_SHORT)
    await expect(title).toHaveAttribute("aria-describedby", (await message.getAttribute("id"))!)
    await expect(title).toHaveAccessibleDescription(TOO_SHORT)
    await expect(tasks.status, "it is read out").toHaveText(`Title was not saved: ${TOO_SHORT}`)

    // the message shows while the cell has focus or the pointer, and the row never grows
    await page.mouse.move(5, 5)
    await expect(message).toBeHidden()
    expect(await rowHeight(tasks, SECOND)).toBeCloseTo(height, 0)

    await title.focus()
    await expect(message).toBeVisible()
    expect(await rowHeight(tasks, SECOND)).toBeCloseTo(height, 0)
    await tasks.press("ArrowDown")
    await expect(message).toBeHidden()

    await title.hover()
    await expect(message).toBeVisible()
    await page.mouse.move(5, 5)
    await expect(message).toBeHidden()

    // nothing was saved
    await page.reload()
    await tasks.ready()
    await expect(title).toHaveText("Remove the dashboard charts")
    await expect(title).not.toHaveAttribute("aria-invalid")
  })

  test("with Enter, focus stays on the failed cell and its message shows; Escape restores the value", async ({
    tasks,
    frames,
  }) => {
    const title = tasks.cell(SECOND, "title")
    await typeTooShort(tasks, title)
    await tasks.saves(title, () => tasks.press("Enter"))

    await expect(title).toBeFocused()
    await expect(title).toHaveAttribute("aria-invalid", "true")
    await expect(tasks.failure(title)).toBeVisible()
    expect(await tasks.tabStops()).toEqual([`task-row-${SECOND}-c-title`])

    await tasks.press("Escape")
    await expect(title).not.toHaveAttribute("aria-invalid")
    await expect(title).toHaveText("Remove the dashboard charts")
    await expect(title).not.toHaveAttribute("data-value")
    await expect(title).toBeFocused()
    await expect(tasks.failure(title)).toHaveCount(0)
    expect(await frames.count("discard")).toBe(1)
  })

  test("the editor of a failed cell holds what was typed; Escape in it restores the value", async ({
    tasks,
  }) => {
    const title = tasks.cell(SECOND, "title")
    await typeTooShort(tasks, title)
    await tasks.saves(title, () => tasks.press("Enter"))

    await tasks.press("Enter")
    await expect(tasks.editor(title)).toBeFocused()
    await expect(tasks.editor(title)).toHaveValue("ab")

    await tasks.press("Escape")
    await expect(title).not.toHaveAttribute("aria-invalid")
    await expect(title).toHaveText("Remove the dashboard charts")
    await expect(title).toBeFocused()
  })

  test("a failed cell can be put right: a good value saves, the old value is no failure", async ({
    tasks,
    frames,
  }) => {
    const title = tasks.cell(SECOND, "title")
    await typeTooShort(tasks, title)
    await tasks.saves(title, () => tasks.press("Enter"))
    await frames.clear()

    // typing the value the record has gives the edit up: nothing is saved
    await tasks.press("Enter")
    await tasks.retype("Remove the dashboard charts")
    await tasks.press("Enter")
    await expect(title).not.toHaveAttribute("aria-invalid")
    await expect(title).toHaveText("Remove the dashboard charts")
    expect(await frames.count("save")).toBe(0)

    await typeTooShort(tasks, title)
    await tasks.saves(title, () => tasks.press("Enter"))
    await tasks.press("Enter")
    await tasks.retype("abc")
    await tasks.saves(title, () => tasks.press("Enter"))
    await expect(title).not.toHaveAttribute("aria-invalid")
    await expect(title).toHaveText("abc")
    await expect(tasks.failure(title)).toHaveCount(0)
  })

  test("the failed cell stays failed when another cell of its row is saved", async ({ tasks }) => {
    const title = tasks.cell(SECOND, "title")
    const estimate = tasks.cell(SECOND, "estimate_hours")
    await typeTooShort(tasks, title)
    await tasks.saves(title, () => tasks.press("Enter"))

    await estimate.focus()
    await tasks.press("Enter")
    await tasks.retype("9")
    await tasks.saves(estimate, () => tasks.press("Enter"))

    await expect(estimate).toHaveText("9 h")
    await expect(title).toHaveAttribute("aria-invalid", "true")
    await expect(title).toContainText("ab")
    await expect(tasks.failure(title)).toHaveText(TOO_SHORT)
  })

  test("a number out of the attribute's range fails with the action's message", async ({ tasks }) => {
    // the estimate has `min: 0`
    const estimate = tasks.cell(THIRD, "estimate_hours")
    await estimate.focus()
    await tasks.press("Enter")
    await tasks.retype("-3")
    await tasks.saves(estimate, () => tasks.press("Enter"))

    await expect(estimate).toHaveAttribute("aria-invalid", "true")
    await expect(estimate).toContainText("-3")
    await expect(tasks.failure(estimate)).toHaveText("must be greater than or equal to 0")
    await expect(tasks.status).toHaveText(
      "Estimate hours was not saved: must be greater than or equal to 0",
    )
  })

  test("an error about another field is shown on the cell that was edited, with the field's name", async ({
    page,
    tasks,
  }) => {
    await withoutMenu(page)
    // a task can only be done with a progress of 100; this one has 5
    const status = tasks.cell(SECOND, "status")
    await status.focus()
    await tasks.press("Enter")
    await tasks.editor(status).selectOption({ label: "Done" })
    await tasks.saves(status, () => tasks.dialog.getByRole("button", { name: "Confirm" }).click())

    await expect(status).toHaveAttribute("aria-invalid", "true")
    await expect(status, "what was chosen").toContainText("Done")
    await expect(status).toHaveAttribute("data-value", "done")
    await expect(tasks.failure(status)).toHaveText("Progress: must be 100 when the task is done")
    await expect(tasks.cell(SECOND, "progress"), "the other cell is not marked").not.toHaveAttribute(
      "aria-invalid",
    )
    await expect(tasks.status).toHaveText(
      "State was not saved: Progress: must be 100 when the task is done",
    )

    await status.focus()
    await tasks.press("Escape")
    await expect(status).toHaveText("To do")
    await expect(status).not.toHaveAttribute("aria-invalid")
  })
})

test.describe("a save that returns while the person is typing in another cell of the same row", () => {
  const LATENCY = 600

  test("a cell whose save is on its way shows what was typed and cannot be edited again", async ({
    page,
    tasks,
  }) => {
    await withLatency(page, LATENCY)
    const title = tasks.cell(THIRD, "title")

    await title.focus()
    await tasks.press("Enter")
    await tasks.retype("Saved under latency")
    await tasks.press("Enter")

    await expect(title).toHaveAttribute("aria-busy", "true")
    await expect(title).toHaveText("Saved under latency")
    await tasks.press("Enter", "F2", "x")
    await expect(tasks.openEditors).toHaveCount(0)
    await expect(title).toBeFocused()

    await expect(title).not.toHaveAttribute("aria-busy")
    await expect(title).toHaveText("Saved under latency")
  })

  test("a save that succeeds leaves the open editor as it is", async ({ page, tasks }) => {
    await withLatency(page, LATENCY)
    const title = tasks.cell(THIRD, "title")
    const estimate = tasks.cell(THIRD, "estimate_hours")
    await expect(estimate).toHaveText("6.25 h")

    await title.focus()
    await tasks.press("Enter")
    await tasks.retype("Saved under latency")
    await tasks.press("Enter")

    await estimate.focus()
    await tasks.press("Enter")
    await tasks.retype("4")
    // the answer patches the row, with the new headline, around the editor
    await expect(title).not.toHaveAttribute("aria-busy")
    await page.keyboard.type("5")

    await expect(tasks.editor(estimate)).toBeFocused()
    await expect(tasks.editor(estimate)).toHaveValue("45")
    await expect(title).toHaveText("Saved under latency")
    await expect(tasks.cell(THIRD, "headline")).toContainText("Saved under latency")

    // Escape still restores what this cell held
    await tasks.press("Escape")
    await expect(estimate).toHaveText("6.25 h")
    await expect(estimate).toBeFocused()
  })

  test("a save that fails leaves the open editor as it is, and marks its own cell", async ({
    page,
    tasks,
  }) => {
    await withLatency(page, LATENCY)
    const title = tasks.cell(THIRD, "title")
    const estimate = tasks.cell(THIRD, "estimate_hours")

    await title.focus()
    await tasks.press("Enter")
    await tasks.retype("ab")
    await tasks.press("Enter")

    await estimate.focus()
    await tasks.press("Enter")
    await tasks.retype("1")
    await expect(title).toHaveAttribute("aria-invalid", "true")
    await page.keyboard.type("2")

    await expect(tasks.editor(estimate)).toBeFocused()
    await expect(tasks.editor(estimate)).toHaveValue("12")
    await expect(title).toContainText("ab")
    await expect(tasks.failure(title)).toHaveText(TOO_SHORT)

    // the cell typed in meanwhile saves, and the failed one stays failed
    await tasks.saves(estimate, () => tasks.press("Enter"))
    await expect(estimate).toHaveText("12 h")
    await expect(title).toHaveAttribute("aria-invalid", "true")
  })

  test("an edit given up after its row was patched shows the value the record has now", async ({
    page,
    tasks,
  }) => {
    // `set_progress` moves the task to "In progress" while its state cell is open
    await withoutMenu(page)
    await withLatency(page, LATENCY)
    const progress = tasks.cell(SECOND, "progress")
    const status = tasks.cell(SECOND, "status")

    // the slider's maximum, saved with Enter
    await progress.focus()
    await tasks.press("Enter", "End", "Enter")

    await status.focus()
    await tasks.press("Enter")
    await expect(tasks.editor(status)).toBeFocused()
    await expect(progress).not.toHaveAttribute("aria-busy")
    await tasks.press("Escape")

    await expect(status).toBeFocused()
    await expect(status).toHaveText("In progress", { timeout: 1500 })
  })
})

test.describe("a record that is gone", () => {
  test("the cell is marked with the message, and Escape restores it", async ({
    request,
    tasks,
  }) => {
    const key = await tasks.rowKey(6)
    const title = tasks.cell(key, "title")
    const before = (await title.textContent())!
    await deleteTask(request, key)

    await title.focus()
    await tasks.press("Enter")
    await tasks.retype("Gone already")
    await tasks.saves(title, () => tasks.press("Enter"))

    await expect(title).toHaveAttribute("aria-invalid", "true")
    await expect(title).toContainText("Gone already")
    await expect(tasks.failure(title)).toHaveText("This record is no longer available.")
    await expect(tasks.failure(title), "focus is on the cell").toBeVisible()
    await expect(title).toHaveAccessibleDescription("This record is no longer available.")
    await expect(tasks.status).toHaveText(
      "Title was not saved: This record is no longer available.",
    )

    await tasks.press("Escape")
    await expect(title).not.toHaveAttribute("aria-invalid")
    await expect(title).toHaveText(before)
    await expect(title).toBeFocused()
  })
})

test("after editing, the grid is still one tab stop and the arrow keys are still silent", async ({
  tasks,
  frames,
}) => {
  const title = tasks.cell(FIRST, "title")
  await title.focus()
  await tasks.press("Enter")
  await tasks.retype("Edited")
  await tasks.saves(title, () => tasks.press("Enter"))
  await tasks.press("Enter")
  await tasks.retype("ab")
  await tasks.saves(title, () => tasks.press("Enter"))

  await frames.clear()
  await tasks.press("ArrowRight", "ArrowDown", "ArrowLeft", "ArrowUp", "End", "Home")
  // Home is the first cell of the row, its expander: the title is beside it
  await expect(tasks.expanderCell(FIRST)).toBeFocused()
  await title.focus()
  await tasks.press("PageDown", "PageUp")
  await expect(title).toBeFocused()
  expect(await frames.all()).toEqual([])
  expect(await tasks.tabStops()).toEqual([`task-row-${FIRST}-c-title`])
})
