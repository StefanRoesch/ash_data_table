import type { Page } from "@playwright/test"
import { expectNoAxeViolations } from "./support/a11y"
import { SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { Table } from "./support/table"
import { params } from "./support/url"

// The filters that take more than one value, at /tasks as the admin: "is
// any of" for the state, whose button opens the table's side panel with a
// box per value, which filters on "Apply" and on nothing else; and
// "between" for the due date, which has two inputs, and applies as a typed
// filter does: on Enter, and when the control is left.

/** The total the pagination shows: the "320" of "1–25 of 320". */
async function total(table: Table): Promise<number> {
  const range = await table.range.textContent()
  return Number(range!.split(" of ")[1])
}

/** Every value the URL holds for one parameter: a list is one name several times. */
function all(page: Page, name: string): string[] {
  return new URL(page.url()).searchParams.getAll(name)
}

const STATES = "task[f][status][any_of][]"

/** The parts of the filter for several values of a column. */
function several(tasks: Table, column: string) {
  const list = tasks.filterChoices(column)
  return {
    button: tasks.filterValue(column),
    /** The panel's field: a box per value. */
    list,
    box: (label: string) => list.getByRole("checkbox", { name: label, exact: true }),
    /** What is ticked in the panel. */
    ticked: () => list.locator("input:checked").evaluateAll((boxes) => boxes.map((box) => (box as HTMLInputElement).value)),
    /** What applies: the inputs of the filter row's form, which are not shown. */
    applied: () =>
      tasks
        .filterCell(column)
        .locator(`input[type=hidden][name="filter[${column}][in][]"]`)
        .evaluateAll((inputs) => inputs.map((input) => (input as HTMLInputElement).value)),
  }
}

test.beforeEach(async ({ tasks }) => {
  await tasks.open()
})

test.describe("is any of", () => {
  test("by mouse: the button opens the side panel, and what is ticked applies on \"Apply\" alone", async ({
    page,
    tasks,
    pushed,
  }) => {
    const state = several(tasks, "status")

    // the operator alone filters nothing, and brings the button
    await tasks.filterOperator("status").selectOption("is any of")
    await expect(state.button).toHaveText("Any")
    await expect(state.button).toHaveAttribute("aria-haspopup", "dialog")
    await expect(state.button).toHaveAccessibleName("Filter State: Any")
    await expect(tasks.panel).toHaveCount(0)
    expect(params(page)).toEqual({})

    await state.button.click()
    await expect(tasks.panel).toBeVisible()
    await expect(page.getByRole("dialog", { name: "Filter State" })).toHaveId("task-panel")
    await expect(tasks.panel.getByRole("group", { name: "State", exact: true })).toHaveId("task-panel-f-status")
    await expect(state.list.locator("label")).toHaveText(["Backlog", "To do", "In progress", "In review", "Done", "Archived"])
    await expect(tasks.panelSubmit).toHaveText("Apply")
    expect(await state.ticked()).toEqual([])

    await pushed.clear()
    await state.list.getByText("To do", { exact: true }).click()
    await state.list.getByText("Done", { exact: true }).click()
    await expect(state.box("To do")).toBeChecked()
    await expect(state.box("Done")).toBeChecked()
    await expect(tasks.panel, "ticking leaves the panel open").toBeVisible()
    expect(await pushed.count("filter"), "ticking filters nothing").toBe(0)
    expect(await pushed.count("panel_submit")).toBe(0)
    expect(params(page)).toEqual({})
    expect(await state.applied()).toEqual([])

    // "Apply" filters, and the panel goes
    await tasks.reads(() => tasks.panelSubmit.click())
    await expect(tasks.panel).toHaveCount(0)
    await expect(state.button).toHaveText("2 selected")
    await expect(state.button).toHaveAccessibleName("Filter State: 2 selected")
    await expect(state.button).toHaveAttribute("title", "To do, Done")
    expect(all(page, STATES)).toEqual(["todo", "done"])
    expect(await state.applied()).toEqual(["todo", "done"])
    for (const text of await tasks.columnTexts("status")) expect(["To do", "Done"]).toContain(text)
    await expect(tasks.filterClear("status")).toBeVisible()

    // opened again, it has what applies ticked; Cancel filters nothing
    await state.button.click()
    await expect(tasks.panel).toBeVisible()
    expect(await state.ticked()).toEqual(["todo", "done"])
    await pushed.clear()
    await state.box("Backlog").check()
    await tasks.panelCancel.click()
    await expect(tasks.panel).toHaveCount(0)
    expect(await pushed.count("filter")).toBe(0)
    expect(await pushed.count("panel_submit")).toBe(0)
    await expect(state.button).toHaveText("2 selected")
    expect(all(page, STATES)).toEqual(["todo", "done"])
    expect(await state.applied()).toEqual(["todo", "done"])

    // one value less, and the button names the one that is left
    await tasks.chooseValues("status", ["Done"])
    await expect(state.button).toHaveText("Done")
    expect(all(page, STATES)).toEqual(["done"])
  })

  test("by keyboard: Enter opens the panel, \"Apply\" applies, Escape gives up what was ticked", async ({
    page,
    tasks,
  }) => {
    const state = several(tasks, "status")

    await tasks.filterCell("status").focus()
    await tasks.press("Enter")
    await expect(tasks.filterValue("status")).toBeFocused()
    await tasks.press("Shift+Tab")
    await expect(tasks.filterOperator("status")).toBeFocused()
    await tasks.press("ArrowDown")
    await expect(tasks.filterOperator("status")).toHaveValue("any_of")
    await expect(state.button).toHaveText("Any")

    await tasks.press("Tab")
    await expect(state.button).toBeFocused()
    await tasks.press("Enter")
    await expect(tasks.panel).toBeVisible()
    await expect(state.box("Backlog"), "focus goes into the panel").toBeFocused()

    await tasks.press("Tab")
    await expect(state.box("To do")).toBeFocused()
    await tasks.press("Space", "Tab", "Tab", "Tab")
    await expect(state.box("Done")).toBeFocused()
    await tasks.press("Space")
    expect(await state.ticked()).toEqual(["todo", "done"])
    expect(params(page)).toEqual({})

    // past the last box, Cancel and "Apply"
    await tasks.press("Tab")
    await expect(state.box("Archived")).toBeFocused()
    await tasks.press("Tab")
    await expect(tasks.panelCancel).toBeFocused()
    await tasks.press("Tab")
    await expect(tasks.panelSubmit).toBeFocused()
    await tasks.reads(() => tasks.press("Enter"))
    await expect(tasks.panel).toHaveCount(0)
    await expect(state.button, "focus is back on the button").toBeFocused()
    await expect(state.button).toHaveText("2 selected")
    expect(all(page, STATES)).toEqual(["todo", "done"])
    expect(await tasks.tabStops(), "the grid is still one tab stop").toHaveLength(1)

    // Escape: the panel goes, and nothing of what was ticked applies
    await tasks.press("Enter")
    await expect(tasks.panel).toBeVisible()
    await expect(state.box("Backlog")).toBeFocused()
    await tasks.press("Space")
    expect(await state.ticked()).toEqual(["backlog", "todo", "done"])
    await tasks.press("Escape")
    await expect(tasks.panel).toHaveCount(0)
    await expect(state.button).toBeFocused()
    expect(await state.applied()).toEqual(["todo", "done"])
    expect(all(page, STATES)).toEqual(["todo", "done"])

    // opened again, it is as it was
    await tasks.press("Enter")
    await expect(tasks.panel).toBeVisible()
    expect(await state.ticked()).toEqual(["todo", "done"])
    await tasks.press("Escape")
    await expect(tasks.panel).toHaveCount(0)
    await expect(state.button).toBeFocused()

    // and once more, back to the cell
    await tasks.press("Escape")
    await expect(tasks.filterCell("status")).toBeFocused()
    // The old list applied what was ticked when Tab left it; the panel is a
    // modal dialog, which focus does not leave, and applies on "Apply" alone.
  })

  test("is none of leaves the chosen values out", async ({ page, tasks }) => {
    await tasks.filterOperator("status").selectOption("is none of")
    await tasks.chooseValues("status", ["Done", "Archived"])

    expect(all(page, "task[f][status][none_of][]")).toEqual(["done", "archived"])
    for (const text of await tasks.columnTexts("status")) expect(["Done", "Archived"]).not.toContain(text)
  })
})

test.describe("between", () => {
  test("a range of dates: each end applies on Enter and when it is left, and either may be left open", async ({
    page,
    tasks,
  }) => {
    await tasks.reads(() => tasks.filterOperator("due_on").selectOption("is empty"))
    const undated = await total(tasks)

    const from = tasks.filterValue("due_on")
    const to = tasks.filterTo("due_on")
    await tasks.reads(() => tasks.filterOperator("due_on").selectOption("between"))
    await expect(page.getByLabel("Filter Due on, from")).toHaveId("task-filter-due_on-value")
    await expect(page.getByLabel("Filter Due on, to")).toHaveId("task-filter-due_on-to")
    await expect(from).toHaveAttribute("type", "date")
    await expect(to).toHaveAttribute("type", "date")
    expect(params(page)).toEqual({})

    // from alone: every task that has a date
    await from.fill("2000-01-01")
    await tasks.reads(() => from.press("Enter"))
    expect(params(page)).toEqual({ "task[f][due_on][between][from]": "2000-01-01" })
    const dated = await total(tasks)
    expect(dated + undated).toBe(SEED.tasks.acme)

    // Tab goes to the other end; leaving that one applies it
    await tasks.press("Tab")
    await expect(to).toBeFocused()
    await to.fill("2100-01-01")
    await tasks.reads(() => tasks.range.click())
    expect(params(page)).toEqual({
      "task[f][due_on][between][from]": "2000-01-01",
      "task[f][due_on][between][to]": "2100-01-01",
    })
    expect(await total(tasks)).toBe(dated)

    // a first end past the last finds nothing, and is no mistake
    await to.fill("1999-12-31")
    await tasks.reads(() => to.press("Enter"))
    await expect(tasks.status).toHaveText("0 results")
    await expect(tasks.filterError("due_on")).toHaveCount(0)

    // to alone
    await from.fill("")
    await tasks.reads(() => from.press("Enter"))
    expect(params(page)).toEqual({ "task[f][due_on][between][to]": "1999-12-31" })
  })

  test("a range of numbers has both of its ends in it", async ({ page, tasks }) => {
    await tasks.filterValue("progress").fill("50")
    await tasks.reads(() => tasks.filterValue("progress").press("Enter"))
    const fifty = await total(tasks)
    expect(fifty).toBeGreaterThan(0)

    await tasks.reads(() => tasks.filterOperator("progress").selectOption("between"))
    // one above the other, each as wide as the one input of another operator
    const from = (await tasks.filterValue("progress").boundingBox())!
    const to = (await tasks.filterTo("progress").boundingBox())!
    expect(from.width).toBe(128)
    expect(to.width).toBe(128)
    expect(to.x).toBe(from.x)
    expect(to.y).toBeGreaterThanOrEqual(from.y + from.height)
    await tasks.filterValue("progress").fill("50")
    await tasks.filterTo("progress").fill("50")
    await tasks.filterTo("progress").press("Enter")

    // Leaving "from" already read the table with "from" alone; the read that
    // has both ends may come after the one that is waited for, so the
    // address is waited for itself.
    await expect
      .poll(() => params(page))
      .toEqual({
        "task[f][progress][between][from]": "50",
        "task[f][progress][between][to]": "50",
      })
    await expect(tasks.grid).not.toHaveAttribute("aria-busy", "true")
    expect(await total(tasks)).toBe(fifty)
  })
})

test.describe("in the URL", () => {
  test("a reload shows the rows and the controls again, and \"Clear filters\" takes them away", async ({
    page,
    tasks,
  }) => {
    const state = several(tasks, "status")

    await tasks.filterOperator("status").selectOption("is any of")
    await tasks.chooseValues("status", ["In review", "To do"])
    await tasks.filterOperator("progress").selectOption("between")
    await expect(tasks.filterTo("progress")).toBeVisible()
    await tasks.filterValue("progress").fill("20")
    await tasks.reads(() => tasks.filterValue("progress").press("Enter"))

    // the values in the order the column has them
    expect(all(page, STATES)).toEqual(["todo", "in_review"])
    expect(params(page)["task[f][progress][between][from]"]).toBe("20")
    const rows = await tasks.rowKeys()
    const found = await total(tasks)

    await page.reload()
    await tasks.ready()
    expect(await tasks.rowKeys()).toEqual(rows)
    expect(await total(tasks)).toBe(found)
    await expect(tasks.filterOperator("status")).toHaveValue("any_of")
    await expect(state.button).toHaveText("2 selected")
    expect(await state.applied()).toEqual(["todo", "in_review"])
    await state.button.click()
    await expect(tasks.panel).toBeVisible()
    expect(await state.ticked()).toEqual(["todo", "in_review"])
    await tasks.panelCancel.click()
    await expect(tasks.panel).toHaveCount(0)
    await expect(tasks.filterOperator("progress")).toHaveValue("between")
    await expect(tasks.filterValue("progress")).toHaveValue("20")
    await expect(tasks.filterTo("progress")).toHaveValue("")

    // a hidden column keeps its filter, and the list of columns says so
    await tasks.hide("status")
    await expect(tasks.columnsButton).toHaveText("Columns (1 hidden, 1 filtered)")
    await tasks.unhide("status")

    await tasks.reads(() => tasks.clearFilters.click())
    expect(params(page)).toEqual({})
    expect(await total(tasks)).toBe(SEED.tasks.acme)
    await expect(tasks.filterOperator("status")).toHaveValue("is")
    await expect(tasks.filterValue("status")).toHaveValue("")
    expect(await state.applied()).toEqual([])
    await expect(tasks.filterOperator("progress")).toHaveValue("equals")
    await expect(tasks.filterTo("progress")).toHaveCount(0)
  })
})

test.describe("in a narrow column", () => {
  test("the controls stay inside their cell, and the panel shows every value whole", async ({ tasks }) => {
    const state = several(tasks, "status")
    await tasks.filterOperator("status").selectOption("is any of")
    await expect(state.button).toBeVisible()
    await tasks.filterOperator("progress").selectOption("between")
    await expect(tasks.filterTo("progress")).toBeVisible()

    // a little narrower: the controls give way, as those of every filter do
    for (const column of ["status", "progress"]) {
      const width = await tasks.width(column)
      await tasks.drag(column, -40)
      // a width that was dragged to is a whole number of pixels
      expect(await tasks.width(column), column).toBeCloseTo(width - 40, 0)
      const cell = (await tasks.filterCell(column).boundingBox())!
      expect(cell.width, column).toBe(await tasks.width(column))
      for (const control of await tasks.filterCell(column).locator("select, input:not([type=checkbox], [type=hidden]), button").all()) {
        const box = (await control.boundingBox())!
        expect(box.x, column).toBeGreaterThanOrEqual(cell.x)
        expect(box.x + box.width, column).toBeLessThanOrEqual(cell.x + cell.width + 0.5)
      }
    }
    // and as narrow as a column gets: it is as wide as it was made, whatever its filter holds
    for (const column of ["status", "progress"]) {
      await tasks.drag(column, 60 - (await tasks.width(column)))
      expect(await tasks.width(column), column).toBe(60)
      expect((await tasks.filterCell(column).boundingBox())!.width, column).toBe(60)
    }
    await tasks.drag("status", 60)

    // the values are in the side panel, as wide as it is, whatever the column
    await state.button.click()
    await expect(tasks.panel).toBeVisible()
    const panel = (await tasks.panel.boundingBox())!
    for (const label of ["In progress", "In review"]) {
      const text = (await state.list.getByText(label, { exact: true }).boundingBox())!
      expect(text.x, label).toBeGreaterThanOrEqual(panel.x)
      expect(text.x + text.width, label).toBeLessThanOrEqual(panel.x + panel.width)
    }
    await tasks.panelCancel.click()
    await expect(tasks.panel).toHaveCount(0)
  })
})

for (const theme of ["light", "dark"] as const) {
  test.describe(`axe, in the ${theme} theme`, () => {
    test("finds nothing with the panel of values open and a range typed", async ({ page, tasks }) => {
      await page.addInitScript((theme) => localStorage.setItem("phx:theme", theme), theme)
      await tasks.open()
      await expect(page.locator("html")).toHaveAttribute("data-theme", theme)

      const state = several(tasks, "status")
      await tasks.filterOperator("progress").selectOption("between")
      await expect(tasks.filterTo("progress")).toBeVisible()
      await tasks.filterValue("progress").fill("10")
      await tasks.reads(() => tasks.filterValue("progress").press("Enter"))
      await tasks.filterOperator("status").selectOption("is any of")
      await state.button.click()
      await expect(tasks.panel).toBeVisible()
      await state.box("Done").check()
      await expect(state.box("Done")).toBeChecked()

      await expectNoAxeViolations(page)
    })
  })
}
