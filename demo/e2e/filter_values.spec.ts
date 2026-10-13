import type { Page } from "@playwright/test"
import { expectNoAxeViolations } from "./support/a11y"
import { SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { Table } from "./support/table"
import { params } from "./support/url"

// The filters that take more than one value, at /tasks as the admin: "is
// any of" for the state, which opens a list of boxes, and "between" for the
// due date, which has two inputs. What is ticked or typed applies as a typed
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
    list,
    box: (label: string) => list.getByRole("checkbox", { name: label, exact: true }),
    ticked: () => list.locator("input:checked").evaluateAll((boxes) => boxes.map((box) => (box as HTMLInputElement).value)),
  }
}

test.beforeEach(async ({ tasks }) => {
  await tasks.open()
})

test.describe("is any of", () => {
  test("by mouse: the list opens under its button, and what is ticked applies when it is left", async ({
    page,
    tasks,
    frames,
  }) => {
    const state = several(tasks, "status")

    // the operator alone filters nothing, and brings the button
    await tasks.filterOperator("status").selectOption("is any of")
    await expect(state.button).toHaveText("Any")
    await expect(state.button).toHaveAttribute("aria-expanded", "false")
    await expect(state.list).toBeHidden()
    expect(params(page)).toEqual({})

    await state.button.click()
    await expect(state.list).toBeVisible()
    await expect(state.button).toHaveAttribute("aria-expanded", "true")
    await expect(page.getByRole("group", { name: "Filter State" })).toHaveId("task-filter-status-values")
    const button = (await state.button.boundingBox())!
    const list = (await state.list.boundingBox())!
    expect(list.y, "under the button").toBeGreaterThanOrEqual(button.y + button.height)

    await frames.clear()
    await state.list.getByText("To do", { exact: true }).click()
    await state.list.getByText("Done", { exact: true }).click()
    await expect(state.box("To do")).toBeChecked()
    await expect(state.list, "ticking leaves the list open").toBeVisible()
    expect(await frames.all(), "ticking asks the server nothing").toEqual([])
    expect(params(page)).toEqual({})

    // a click anywhere else closes the list and applies
    await tasks.reads(() => tasks.range.click())
    await expect(state.list).toBeHidden()
    await expect(state.button).toHaveAttribute("aria-expanded", "false")
    await expect(state.button).toHaveText("2 selected")
    expect(all(page, STATES)).toEqual(["todo", "done"])
    for (const text of await tasks.columnTexts("status")) expect(["To do", "Done"]).toContain(text)
    await expect(tasks.filterClear("status")).toBeVisible()

    // the button closes it as well; with nothing changed, nothing is read
    await state.button.click()
    await expect(state.list).toBeVisible()
    await frames.clear()
    await state.button.click()
    await expect(state.list).toBeHidden()
    expect(await frames.count("filter")).toBe(0)

    // one value less, and the button names the one that is left
    await state.button.click()
    await state.box("To do").uncheck()
    await tasks.reads(() => state.button.click())
    await expect(state.button).toHaveText("Done")
    expect(all(page, STATES)).toEqual(["done"])
  })

  test("by keyboard: Enter opens the list and applies it, Escape gives up what was ticked", async ({
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
    await expect(state.list).toBeVisible()
    await expect(state.box("Backlog"), "focus goes into the list").toBeFocused()

    await tasks.press("ArrowDown")
    await expect(state.box("To do")).toBeFocused()
    await tasks.press("Space", "ArrowDown", "ArrowDown", "ArrowDown")
    await expect(state.box("Done")).toBeFocused()
    await tasks.press("Space")
    expect(await state.ticked()).toEqual(["todo", "done"])
    expect(params(page)).toEqual({})

    await tasks.reads(() => tasks.press("Enter"))
    await expect(state.list).toBeHidden()
    await expect(state.button).toBeFocused()
    await expect(state.button).toHaveText("2 selected")
    expect(all(page, STATES)).toEqual(["todo", "done"])
    expect(await tasks.tabStops(), "the grid is still one tab stop").toHaveLength(1)

    // Escape: the list closes, and is as it was
    await tasks.press("ArrowDown")
    await expect(state.box("Backlog")).toBeFocused()
    await tasks.press("Space")
    expect(await state.ticked()).toEqual(["backlog", "todo", "done"])
    await tasks.press("Escape")
    await expect(state.list).toBeHidden()
    await expect(state.button).toBeFocused()
    expect(await state.ticked()).toEqual(["todo", "done"])
    expect(all(page, STATES)).toEqual(["todo", "done"])

    // and once more, back to the cell
    await tasks.press("Escape")
    await expect(tasks.filterCell("status")).toBeFocused()

    // Tab from the list goes on through the filter's controls, which applies
    await tasks.press("Enter", "Enter")
    await expect(state.box("Backlog")).toBeFocused()
    await tasks.press("Space")
    for (let box = 0; box < 5; box++) await tasks.press("Tab")
    await expect(state.box("Archived")).toBeFocused()
    await tasks.reads(() => tasks.press("Tab"))
    await expect(state.list).toBeHidden()
    expect(all(page, STATES)).toEqual(["backlog", "todo", "done"])
  })

  test("is none of leaves the chosen values out", async ({ page, tasks }) => {
    const state = several(tasks, "status")

    await tasks.filterOperator("status").selectOption("is none of")
    await state.button.click()
    await state.box("Done").check()
    await state.box("Archived").check()
    await tasks.reads(() => page.keyboard.press("Enter"))

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
    await tasks.reads(() => tasks.filterTo("progress").press("Enter"))

    expect(params(page)).toEqual({
      "task[f][progress][between][from]": "50",
      "task[f][progress][between][to]": "50",
    })
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
    await state.button.click()
    await state.box("In review").check()
    await state.box("To do").check()
    await tasks.reads(() => page.keyboard.press("Enter"))
    await tasks.filterOperator("progress").selectOption("between")
    await expect(tasks.filterTo("progress")).toBeVisible()
    await tasks.filterValue("progress").fill("20")
    await tasks.reads(() => tasks.filterValue("progress").press("Enter"))

    // the values in the order the column has them, whatever the order they were ticked in
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
    expect(await state.ticked()).toEqual(["todo", "in_review"])
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
    await expect(state.list).toHaveCount(0)
    await expect(tasks.filterOperator("progress")).toHaveValue("equals")
    await expect(tasks.filterTo("progress")).toHaveCount(0)
  })
})

test.describe("in a narrow column", () => {
  test("the controls stay inside their cell, and the list is not cut off", async ({ tasks }) => {
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
      for (const control of await tasks.filterCell(column).locator("select, input:not([type=checkbox]), button").all()) {
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

    // the list is as wide as its values need, whatever the column
    await state.button.click()
    await expect(state.list).toBeVisible()
    const list = (await state.list.boundingBox())!
    const last = (await state.list.getByText("In progress", { exact: true }).boundingBox())!
    expect(last.x + last.width).toBeLessThanOrEqual(list.x + list.width)
    expect(list.width).toBeGreaterThan(120)
  })
})

for (const theme of ["light", "dark"] as const) {
  test.describe(`axe, in the ${theme} theme`, () => {
    test("finds nothing with the list open and a range typed", async ({ page, tasks }) => {
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
      await state.box("Done").check()
      await expect(state.list).toBeVisible()

      await expectNoAxeViolations(page)
    })
  })
}
