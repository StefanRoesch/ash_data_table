import { expect, test } from "./support/fixtures"
import { Table } from "./support/table"
import { params } from "./support/url"

// Spec section 6.4: the filter row. /tasks as the admin has a filter of
// every kind; /specimens and /comments show what /tasks cannot.

/** The total the pagination shows: the "320" of "1–25 of 320". */
async function total(table: Table): Promise<number> {
  const range = await table.range.textContent()
  return Number(range!.split(" of ")[1])
}

test.beforeEach(async ({ tasks }) => {
  await tasks.open()
})

test.describe("the controls of the filter row", () => {
  test("every filterable column has a filter, named after the column", async ({ page, tasks }) => {
    await expect(page.getByRole("textbox", { name: "Filter Title", exact: true })).toHaveId(
      "task-filter-title-value",
    )
    await expect(page.getByRole("combobox", { name: "How to filter Title" })).toHaveId(
      "task-filter-title-operator",
    )
    await expect(page.getByRole("spinbutton", { name: "Filter Progress" })).toHaveId(
      "task-filter-progress-value",
    )
    await expect(page.getByRole("combobox", { name: "Filter State", exact: true })).toHaveId(
      "task-filter-status-value",
    )
    await expect(page.getByRole("combobox", { name: "Filter Billable?" })).toHaveId(
      "task-filter-billable?-value",
    )
    await expect(tasks.filterValue("due_on")).toHaveAttribute("type", "date")
    await expect(tasks.filterValue("completed_at")).toHaveAttribute("type", "datetime-local")

    // `description` says `filterable? false`; `headline` is computed in Elixir
    for (const column of ["description", "headline"]) {
      await expect(tasks.filterCell(column).locator("input, select, button")).toHaveCount(0)
    }
  })

  test("each kind of column offers its operators, and \"is empty\" only where a value can be missing", async ({
    tasks,
  }) => {
    const operators = (column: string) => tasks.filterOperator(column).locator("option")
    const choices = (column: string) => tasks.filterValue(column).locator("option")

    // text: one that is required and one that is not
    await expect(operators("title")).toHaveText(["contains", "equals", "starts with"])
    await expect(operators("external_ref")).toHaveText([
      "contains",
      "equals",
      "starts with",
      "is empty",
    ])
    // numbers
    const number = ["equals", "greater than", "less than", "at least", "at most"]
    await expect(operators("progress")).toHaveText(number)
    await expect(operators("estimate_hours")).toHaveText([...number, "is empty"])
    await expect(operators("comment_count"), "an aggregate").toHaveText(number)
    // a date and datetimes
    await expect(operators("due_on")).toHaveText(["on", "before", "after", "is empty"])
    await expect(operators("completed_at")).toHaveText(["before", "after", "is empty"])
    await expect(operators("inserted_at")).toHaveText(["before", "after"])
    // a boolean and a choice have no operator menu: the choice is the filter
    await expect(tasks.filterOperator("billable?")).toHaveCount(0)
    await expect(choices("billable?")).toHaveText(["Any", "Yes", "No"])
    await expect(choices("overdue?"), "a calculation").toHaveText(["Any", "Yes", "No"])
    await expect(tasks.filterOperator("status")).toHaveCount(0)
    await expect(choices("status")).toHaveText([
      "Any",
      "Backlog",
      "To do",
      "In progress",
      "In review",
      "Done",
      "Archived",
    ])
  })

  test("the filters are no tab stops, and the keys in an input are the input's", async ({
    page,
    tasks,
    frames,
  }) => {
    await tasks.filterCell("title").focus()
    expect(await tasks.tabStops()).toEqual(["task-filter-title"])

    await tasks.press("Enter")
    await expect(tasks.filterValue("title")).toBeFocused()
    await frames.clear()
    await page.keyboard.type("se")
    await tasks.press("ArrowLeft", "ArrowRight", "ArrowDown", "ArrowUp", "Home", "End")
    await expect(tasks.filterValue("title")).toBeFocused()
    await page.keyboard.type("ss")
    await expect(tasks.filterValue("title")).toHaveValue("sess")

    expect(await frames.all(), "typing asks the server nothing").toEqual([])
    expect(await tasks.tabStops()).toEqual(["task-filter-title"])
  })

  test("F2 goes into a filter as Enter does, and a click into an input stays there", async ({
    tasks,
  }) => {
    await tasks.filterCell("progress").focus()
    await tasks.press("F2")
    await expect(tasks.filterValue("progress")).toBeFocused()

    await tasks.filterValue("title").click()
    await expect(tasks.filterValue("title")).toBeFocused()
  })

  test("Tab walks the controls of one filter, then leaves the grid", async ({ page, tasks }) => {
    await tasks.filterCell("title").focus()
    await tasks.press("Enter")
    await page.keyboard.type("sess")
    await tasks.reads(() => tasks.press("Enter"))

    await tasks.press("Shift+Tab")
    await expect(tasks.filterOperator("title")).toBeFocused()
    await tasks.press("Shift+Tab")
    await expect(tasks.filterCell("title"), "before the first control is the cell").toBeFocused()

    await tasks.press("Enter", "Tab")
    await expect(tasks.filterClear("title")).toBeFocused()
    await tasks.press("Tab")
    expect(await tasks.hasFocus(), "after the last control Tab leaves the grid").toBe(false)

    await tasks.press("Shift+Tab")
    await expect(tasks.filterCell("title"), "the grid's one tab stop").toBeFocused()
  })
})

test.describe("applying a filter", () => {
  test("Enter applies what was typed, and focus stays in the input", async ({ page, tasks }) => {
    await tasks.filterCell("title").focus()
    await tasks.press("Enter")
    await page.keyboard.type("sess")
    await tasks.reads(() => tasks.press("Enter"))

    expect(params(page)).toEqual({ "task[f][title]": "sess" })
    await expect(tasks.range).toHaveText("1–18 of 18")
    for (const title of await tasks.columnTexts("title")) expect(title).toContain("sess")
    await expect(tasks.filterValue("title")).toBeFocused()
    await expect(tasks.filterValue("title")).toHaveValue("sess")

    await expect(tasks.clearFilters).toBeVisible()
    await expect(tasks.filterClear("title")).toBeVisible()
    expect(await tasks.tabStops()).toEqual(["task-filter-title"])
  })

  test("leaving the input applies what was typed", async ({ page, tasks }) => {
    await tasks.filterValue("title").focus()
    await page.keyboard.type("Fix")
    await tasks.reads(() => tasks.press("Tab"))

    expect(params(page)).toEqual({ "task[f][title]": "Fix" })
    await expect(tasks.range).toHaveText("1–23 of 23")
    for (const title of await tasks.columnTexts("title")) expect(title).toContain("Fix")
  })

  test("Escape gives up what was typed and not applied, and goes back to the cell", async ({
    page,
    tasks,
  }) => {
    await tasks.filterValue("title").focus()
    await page.keyboard.type("sess")
    await tasks.reads(() => tasks.press("Enter"))
    const filtered = await tasks.rowKeys()

    await page.keyboard.type("zzz")
    await expect(tasks.filterValue("title")).toHaveValue("sesszzz")
    await tasks.press("Escape")

    await expect(tasks.filterValue("title")).toHaveValue("sess")
    await expect(tasks.filterCell("title")).toBeFocused()
    expect(params(page)).toEqual({ "task[f][title]": "sess" })
    expect(await tasks.rowKeys()).toEqual(filtered)
    await expect(tasks.grid, "nothing is read again").not.toHaveAttribute("aria-busy")

    // on a filter never applied, Escape empties the input
    await tasks.filterValue("external_ref").focus()
    await page.keyboard.type("EXT")
    await tasks.press("Escape")
    await expect(tasks.filterValue("external_ref")).toHaveValue("")
    await expect(tasks.filterCell("external_ref")).toBeFocused()
  })

  test("text: contains, equals, starts with", async ({ page, tasks }) => {
    // "contains" is what applies when a value is simply typed
    await tasks.filterValue("title").fill("error messages")
    await tasks.reads(() => tasks.filterValue("title").press("Enter"))
    const contains = await total(tasks)
    expect(contains).toBeGreaterThan(1)

    // changing the operator with a value present applies at once
    await tasks.reads(() => tasks.filterOperator("title").selectOption("starts_with"))
    expect(params(page)).toEqual({ "task[f][title][starts_with]": "error messages" })
    await expect(tasks.empty).toHaveText("No records")

    await tasks.filterValue("title").fill("Add")
    await tasks.reads(() => tasks.filterValue("title").press("Enter"))
    for (const title of await tasks.columnTexts("title")) expect(title).toMatch(/^Add/)

    await tasks.filterValue("title").fill("Add error messages")
    await tasks.reads(() => tasks.filterOperator("title").selectOption("equals"))
    expect(params(page)).toEqual({ "task[f][title][equals]": "Add error messages" })
    expect(await tasks.columnTexts("title")).toEqual(["Add error messages"])
  })

  test("text is matched as the resource says: a :string minds the case, a :ci_string does not", async ({
    page,
    tasks,
  }) => {
    await tasks.filterValue("title").fill("Session")
    await tasks.reads(() => tasks.filterValue("title").press("Enter"))
    await expect(tasks.empty, "every title has it in small letters").toHaveText("No records")

    const specimens = new Table(page, "specimen", "/specimens")
    await specimens.open()
    await specimens.filterValue("a_ci_string").fill("ALPHA")
    await specimens.reads(() => specimens.filterValue("a_ci_string").press("Enter"))
    const found = await specimens.columnTexts("a_ci_string")
    expect(found.length).toBeGreaterThan(0)
    for (const text of found) expect(text).toBe("Alpha")
  })

  test("a number: the operators compare", async ({ page, tasks }) => {
    await tasks.filterValue("progress").fill("50")
    await tasks.reads(() => tasks.filterValue("progress").press("Enter"))
    expect(params(page)).toEqual({ "task[f][progress]": "50" })
    await expect(tasks.range).toHaveText("1–8 of 8")
    expect(await tasks.columnTexts("progress")).toEqual(Array(8).fill("50"))

    await tasks.reads(() => tasks.filterOperator("progress").selectOption("at_least"))
    expect(params(page)).toEqual({ "task[f][progress][at_least]": "50" })
    expect(await total(tasks)).toBe(138)
    for (const progress of await tasks.columnTexts("progress")) {
      expect(Number(progress)).toBeGreaterThanOrEqual(50)
    }

    await tasks.reads(() => tasks.filterOperator("progress").selectOption("less_than"))
    expect(await total(tasks)).toBe(320 - 138)
    for (const progress of await tasks.columnTexts("progress")) {
      expect(Number(progress)).toBeLessThan(50)
    }
  })

  test("\"is empty\" needs no value: it applies when picked and takes the input away", async ({
    page,
    tasks,
  }) => {
    await tasks.reads(() => tasks.filterOperator("due_on").selectOption("is_empty"))

    expect(params(page)).toEqual({ "task[f][due_on][is_empty]": "" })
    await expect(tasks.filterValue("due_on")).toHaveCount(0)
    expect(await total(tasks)).toBe(72)
    for (const due of await tasks.columnTexts("due_on")) expect(due).toBe("")

    // Enter on the cell goes to what is left of the filter: its menu
    await tasks.filterCell("due_on").focus()
    await tasks.press("Enter")
    await expect(tasks.filterOperator("due_on")).toBeFocused()
    await tasks.press("Escape")
    await expect(tasks.filterCell("due_on")).toBeFocused()

    // another operator brings the input back; without a value nothing is filtered
    await tasks.reads(() => tasks.filterOperator("due_on").selectOption("before"))
    await expect(tasks.filterValue("due_on")).toBeVisible()
    expect(params(page)).toEqual({})
  })

  test("a date and a datetime: before and after", async ({ page, tasks }) => {
    await tasks.filterOperator("due_on").selectOption("before")
    await tasks.filterValue("due_on").fill("2000-01-01")
    await tasks.reads(() => tasks.filterValue("due_on").press("Enter"))
    expect(params(page)).toEqual({ "task[f][due_on][before]": "2000-01-01" })
    await expect(tasks.empty).toHaveText("No records")

    await tasks.reads(() => tasks.filterOperator("due_on").selectOption("after"))
    expect(await total(tasks), "every task with a due date").toBe(320 - 72)

    await tasks.reads(() => tasks.filterClear("due_on").click())
    await tasks.filterValue("completed_at").fill("2000-01-01T00:00:01")
    await tasks.reads(() => tasks.filterValue("completed_at").press("Enter"))
    expect(params(page)).toEqual({ "task[f][completed_at]": "2000-01-01T00:00:01" })
    await expect(tasks.empty, "\"before\" is the first operator of a datetime").toHaveText(
      "No records",
    )
    await tasks.reads(() => tasks.filterOperator("completed_at").selectOption("after"))
    expect(await total(tasks), "every task that was completed").toBe(61)
  })

  test("a boolean and a choice apply when picked", async ({ page, tasks }) => {
    await tasks.reads(() => tasks.filterValue("billable?").selectOption("yes"))
    expect(params(page)).toEqual({ "task[f][billable?]": "yes" })
    expect(await total(tasks)).toBe(128)
    for (const cell of await tasks.columnTexts("billable?")) expect(cell).toContain("Yes")

    await tasks.reads(() => tasks.filterValue("billable?").selectOption("no"))
    expect(await total(tasks)).toBe(320 - 128)

    await tasks.reads(() => tasks.filterValue("status").selectOption({ label: "Done" }))
    expect(params(page)).toEqual({ "task[f][billable?]": "no", "task[f][status]": "done" })
    for (const state of await tasks.columnTexts("status")) expect(state).toBe("Done")

    // "Any" takes the filter away
    await tasks.reads(() => tasks.filterValue("billable?").selectOption({ label: "Any" }))
    expect(params(page)).toEqual({ "task[f][status]": "done" })
    expect(await total(tasks)).toBe(61)
  })

  test("a calculation and an aggregate filter in the database, combined with AND", async ({
    page,
    tasks,
  }) => {
    await tasks.reads(() => tasks.filterValue("overdue?").selectOption("yes"))
    const overdue = await total(tasks)
    expect(overdue).toBeGreaterThan(0)

    await tasks.filterOperator("comment_count").selectOption("greater_than")
    await tasks.filterValue("comment_count").fill("2")
    await tasks.reads(() => tasks.filterValue("comment_count").press("Enter"))

    expect(params(page)).toEqual({
      "task[f][overdue?]": "yes",
      "task[f][comment_count][greater_than]": "2",
    })
    expect(await total(tasks)).toBeLessThan(overdue)
    for (const cell of await tasks.columnTexts("overdue?")) expect(cell).toContain("Yes")
    for (const count of await tasks.columnTexts("comment_count")) {
      expect(Number(count)).toBeGreaterThan(2)
    }
  })

  test("a filter change goes back to the first page; a sort stays", async ({ page, tasks }) => {
    await tasks.open("/tasks?task[sort]=-progress&task[page]=3")
    await expect(tasks.range).toHaveText("51–75 of 320")

    await tasks.reads(() => tasks.filterValue("billable?").selectOption("yes"))
    expect(params(page)).toEqual({ "task[sort]": "-progress", "task[f][billable?]": "yes" })
    await expect(tasks.range).toHaveText("1–25 of 128")
    await expect(tasks.header("progress")).toHaveAttribute("aria-sort", "descending")
  })
})

test.describe("a value that is none", () => {
  test("a number input takes no letters", async ({ page, tasks }) => {
    await tasks.filterValue("progress").focus()
    await page.keyboard.type("abc")
    await expect(tasks.filterValue("progress")).toHaveValue("")
  })

  test("a value the column cannot hold is marked and not applied", async ({ page, tasks }) => {
    const unfiltered = await tasks.rowKeys()

    // a decimal gets through the number input; `progress` is a whole number
    await tasks.filterValue("progress").focus()
    await page.keyboard.type("1.5")
    await tasks.press("Enter")

    const input = tasks.filterValue("progress")
    await expect(input).toHaveAttribute("aria-invalid", "true")
    await expect(tasks.filterError("progress")).toHaveText("Not a valid value")
    await expect(input).toHaveAttribute("aria-describedby", "task-filter-progress-error")
    await expect(input, "what was typed stays").toHaveValue("1.5")
    await expect(tasks.filterClear("progress")).toHaveCount(0)
    expect(params(page)).toEqual({})
    expect(await tasks.rowKeys()).toEqual(unfiltered)

    // emptied, the filter is as it was
    await tasks.retype("")
    await tasks.press("Enter")
    await expect(input).not.toHaveAttribute("aria-invalid")
    await expect(tasks.filterError("progress")).toHaveCount(0)

    // and a good value then applies
    await page.keyboard.type("50")
    await tasks.reads(() => tasks.press("Enter"))
    expect(params(page)).toEqual({ "task[f][progress]": "50" })
  })
})

test.describe("clearing", () => {
  test("a filter's clear button takes that filter away, and focus goes to its cell", async ({
    page,
    tasks,
  }) => {
    await tasks.open("/tasks?task[f][title]=sess&task[f][billable?]=yes")
    await expect(tasks.filterValue("title")).toHaveValue("sess")

    // by keyboard: into the filter, on to its button
    await tasks.filterCell("title").focus()
    await tasks.press("Enter", "Tab")
    await expect(tasks.filterClear("title")).toBeFocused()
    await expect(tasks.filterClear("title")).toHaveAccessibleName("Clear the Title filter")
    await tasks.reads(() => tasks.press("Enter"))

    expect(params(page)).toEqual({ "task[f][billable?]": "yes" })
    await expect(tasks.filterValue("title")).toHaveValue("")
    await expect(tasks.filterClear("title")).toHaveCount(0)
    await expect(tasks.filterCell("title"), "the button is gone: its cell has the focus").toBeFocused()
    await expect(tasks.clearFilters, "another filter is still active").toBeVisible()
  })

  test("\"Clear filters\" takes them all away, and focus goes to the grid", async ({
    page,
    tasks,
  }) => {
    await tasks.open("/tasks?task[f][title]=sess&task[f][billable?]=yes&task[sort]=title")
    const unfiltered = 320

    await tasks.reads(() => tasks.clearFilters.click())

    expect(params(page), "the sort stays").toEqual({ "task[sort]": "title" })
    expect(await total(tasks)).toBe(unfiltered)
    await expect(tasks.clearFilters).toHaveCount(0)
    await expect(tasks.filterValue("title")).toHaveValue("")
    await expect(tasks.filterValue("billable?")).toHaveValue("")
    expect(await tasks.hasFocus(), "the button is gone: the grid has the focus").toBe(true)
    await expect(tasks.tabStop).toBeFocused()
  })
})

test.describe("what is read out", () => {
  test("the count after each change, in a live region", async ({ page, tasks }) => {
    await expect(tasks.status).toHaveAttribute("aria-live", "polite")
    await expect(tasks.status, "nothing before the first change").toHaveText("")

    await tasks.filterValue("title").fill("sess")
    await tasks.reads(() => tasks.filterValue("title").press("Enter"))
    await expect(tasks.status).toHaveText("18 results")

    await tasks.reads(() => tasks.filterOperator("title").selectOption("equals"))
    await expect(tasks.status).toHaveText("0 results")

    await tasks.filterValue("title").fill("Add error messages")
    await tasks.reads(() => tasks.filterValue("title").press("Enter"))
    await expect(tasks.status).toHaveText("1 result")

    await tasks.reads(() => tasks.clearFilters.click())
    await expect(tasks.status).toHaveText("320 results")

    // a sort or a page change is not announced: the text stays as it is
    const before = await page.evaluate(() => document.querySelector("#task-status")!.textContent)
    await tasks.reads(() => tasks.header("title").click())
    await tasks.reads(() => tasks.next.click())
    expect(await page.evaluate(() => document.querySelector("#task-status")!.textContent)).toBe(before)
  })

  test("the same count twice in a row is still a change of the region's text", async ({
    page,
    tasks,
  }) => {
    const spoken = () => page.evaluate(() => document.querySelector("#task-status")!.textContent)

    await tasks.reads(() => tasks.filterValue("billable?").selectOption("yes"))
    const first = await spoken()

    // a second filter that every task passes
    await tasks.filterOperator("progress").selectOption("at_least")
    await tasks.filterValue("progress").fill("0")
    await tasks.reads(() => tasks.filterValue("progress").press("Enter"))
    const second = await spoken()

    expect(first!.trim()).toBe("128 results")
    expect(second!.trim()).toBe("128 results")
    expect(second, "a screen reader only reads a region that has changed").not.toBe(first)
  })

  test("a keyset table cannot count: it says that the results have changed", async ({ page }) => {
    const comments = new Table(page, "comment", "/comments")
    await comments.open()

    await comments.filterValue("body").fill("a")
    await comments.reads(() => comments.filterValue("body").press("Enter"))
    await expect(comments.status).toHaveText("Results updated")
    expect(params(page)).toEqual({ "comment[f][body]": "a" })
  })
})

test.describe("filters in the URL", () => {
  test("a link shows the rows and fills the filter row", async ({ tasks }) => {
    await tasks.open(
      "/tasks?task[f][progress][at_least]=50&task[f][billable?]=yes&task[f][due_on][is_empty]=&task[sort]=progress",
    )

    await expect(tasks.filterValue("progress")).toHaveValue("50")
    await expect(tasks.filterOperator("progress")).toHaveValue("at_least")
    await expect(tasks.filterValue("billable?")).toHaveValue("yes")
    await expect(tasks.filterOperator("due_on")).toHaveValue("is_empty")
    await expect(tasks.filterValue("due_on")).toHaveCount(0)
    await expect(tasks.clearFilters).toBeVisible()

    const progress = (await tasks.columnTexts("progress")).map(Number)
    expect(progress.length).toBeGreaterThan(0)
    expect(progress).toEqual([...progress].sort((a, b) => a - b))
    expect(progress[0]).toBeGreaterThanOrEqual(50)
    for (const cell of await tasks.columnTexts("billable?")) expect(cell).toContain("Yes")
    for (const due of await tasks.columnTexts("due_on")) expect(due).toBe("")
  })

  test("a reload and the back button show the filters again", async ({ page, tasks }) => {
    await tasks.reads(() => tasks.filterValue("billable?").selectOption("yes"))
    await tasks.filterValue("title").fill("sess")
    await tasks.reads(() => tasks.filterValue("title").press("Enter"))
    const both = await tasks.rowKeys()
    expect(params(page)).toEqual({ "task[f][billable?]": "yes", "task[f][title]": "sess" })

    await tasks.reads(() => page.goBack())
    expect(params(page)).toEqual({ "task[f][billable?]": "yes" })
    await expect(tasks.range).toHaveText("1–25 of 128")
    await expect(tasks.filterValue("billable?")).toHaveValue("yes")

    await tasks.reads(() => page.goForward())
    expect(await tasks.rowKeys()).toEqual(both)

    await page.reload()
    await tasks.ready()
    expect(await tasks.rowKeys()).toEqual(both)
    await expect(tasks.filterValue("title")).toHaveValue("sess")
    await expect(tasks.filterValue("billable?")).toHaveValue("yes")
  })

  test("a filter the URL asks for on a column without one, or with a value that is none, is ignored", async ({
    tasks,
  }) => {
    const plain = await tasks.rowKeys()

    for (const query of [
      "task[f][description]=slow",
      "task[f][no_such_column]=1",
      "task[f][progress]=abc",
      "task[f][title][no_such_operator]=x",
    ]) {
      await tasks.open(`/tasks?${query}`)
      expect(await tasks.rowKeys(), query).toEqual(plain)
      await expect(tasks.clearFilters, query).toHaveCount(0)
    }
  })
})
