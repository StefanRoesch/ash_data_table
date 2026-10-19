import { expectNoAxeViolations } from "./support/a11y"
import { SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { switchLocale } from "./support/locale"
import { Table } from "./support/table"
import { params } from "./support/url"

// The argument line: the inputs above a table's rows in which a person gives
// the arguments of the table's read action, and those its calculation
// columns ask for.
//
// /tasks reads through an action with an argument that may be left empty, a
// search term, and shows the calculation `due_within?` twice: once with its
// days fixed, once asking for them ("Due within", which starts with 30).
// /deadlines reads the same tasks through an action that requires a day,
// and takes a box with a default and a list of tags besides.

const FIRST = SEED.task.first

/** The total the pagination shows: the "320" of "1–25 of 320". */
async function total(table: Table): Promise<number> {
  const range = await table.range.textContent()
  return Number(range!.split(" of ")[1])
}

/** A day from today, as a date input holds it. */
function inDays(days: number): string {
  const day = new Date()
  day.setDate(day.getDate() + days)
  return [
    day.getFullYear(),
    String(day.getMonth() + 1).padStart(2, "0"),
    String(day.getDate()).padStart(2, "0"),
  ].join("-")
}

test.describe("the line of /tasks", () => {
  test.beforeEach(async ({ tasks }) => {
    await tasks.open()
  })

  test("has a labelled input per argument, between the table's name and its grid", async ({
    page,
    tasks,
  }) => {
    await expect(tasks.argumentLine.locator("input, select")).toHaveCount(2)
    await expect(page.getByRole("textbox", { name: "Search", exact: true })).toHaveId("task-arg-search")
    await expect(page.getByRole("spinbutton", { name: "Due within: Days" })).toHaveId(
      "task-arg-due_within-days",
    )
    await expect(tasks.argument("search")).toHaveValue("")
    // what the column's `ask` starts with
    await expect(tasks.argument("due_within-days")).toHaveValue("30")
    // it cannot be empty, and says so
    await expect(tasks.argument("due_within-days")).toHaveAttribute("aria-required", "true")
    // no button runs the line
    await expect(tasks.argumentLine.getByRole("button")).toHaveCount(0)

    // on the heading line, after the table's name and "Columns", before the
    // create button at its far end; the line's form makes no box of its own
    const name = (await tasks.name.boundingBox())!
    const columns = (await tasks.columnsButton.boundingBox())!
    const search = (await tasks.argument("search").boundingBox())!
    const days = (await tasks.argument("due_within-days").boundingBox())!
    const create = (await tasks.create.boundingBox())!
    const heading = (await tasks.headerLine.boundingBox())!
    const grid = (await tasks.grid.boundingBox())!
    expect(search.x).toBeGreaterThan(columns.x + columns.width)
    expect(columns.x).toBeGreaterThan(name.x + name.width)
    expect(days.x).toBeGreaterThan(search.x)
    expect(create.x).toBeGreaterThan(days.x + days.width)
    for (const box of [name, columns, search, days, create]) {
      expect(Math.abs(box.y + box.height / 2 - (search.y + search.height / 2))).toBeLessThanOrEqual(2)
    }
    expect(heading.y + heading.height).toBeLessThanOrEqual(grid.y)

    await expectNoAxeViolations(page)
  })

  test("its inputs are ordinary tab stops before the table", async ({ page, tasks }) => {
    // after "Columns" (hiding.spec.ts) on the heading line
    await tasks.columnsButton.focus()
    await page.keyboard.press("Tab")
    await expect(tasks.argument("search")).toBeFocused()
    await page.keyboard.press("Tab")
    await expect(tasks.argument("due_within-days")).toBeFocused()
    // between them and the table: the create button at the line's end,
    // then the table's "Skip table"
    await page.keyboard.press("Tab")
    await expect(tasks.create).toBeFocused()
    await page.keyboard.press("Tab")
    await expect(tasks.skip).toBeFocused()
    // and back
    await page.keyboard.press("Shift+Tab")
    await page.keyboard.press("Shift+Tab")
    await expect(tasks.argument("due_within-days")).toBeFocused()
  })

  test("what is typed is sent when Enter is used, not at every key, and is in the URL", async ({
    page,
    tasks,
    pushed,
  }) => {
    await tasks.argument("search").focus()
    await pushed.clear()
    await page.keyboard.type("login")
    expect(await pushed.all(), "typing sends nothing").toEqual([])
    await expect(tasks.rows).toHaveCount(25)

    await tasks.reads(() => page.keyboard.press("Enter"))

    // LiveView sends what the input held back, and then the form: once or
    // twice the same, of which the second changes nothing
    expect(await pushed.count("arguments")).toBeGreaterThan(0)
    expect(await pushed.count("arguments")).toBeLessThanOrEqual(2)
    await expect(tasks.argument("search"), "focus stays where the person is typing").toBeFocused()
    expect(params(page)).toEqual({ "task[a][search]": "login" })

    const found = await total(tasks)
    expect(found).toBeGreaterThan(0)
    expect(found).toBeLessThan(SEED.tasks.acme)
    // in the title or the description, whatever the case
    const titles = await tasks.columnTexts("title")
    const descriptions = await tasks.columnTexts("description")
    titles.forEach((title, row) =>
      expect(`${title} ${descriptions[row]}`.toLowerCase()).toContain("login"),
    )
    await expect(tasks.status, "read out as a change of the filters is").toHaveText(
      new RegExp(`^${found} results?\\s*$`),
    )
  })

  test("what is typed is sent when the input is left, too", async ({ page, tasks, pushed }) => {
    await tasks.argument("search").fill("login")
    await pushed.clear()
    await tasks.reads(() => page.keyboard.press("Tab"))

    expect(await pushed.count("arguments")).toBe(1)
    await expect(tasks.argument("due_within-days")).toBeFocused()
    expect(await total(tasks)).toBeLessThan(SEED.tasks.acme)
  })

  test("the page can be reloaded and linked", async ({ page, tasks }) => {
    await tasks.argument("search").fill("login")
    await tasks.reads(() => tasks.argument("search").press("Enter"))
    const found = await total(tasks)

    await page.reload()
    await tasks.ready()
    await expect(tasks.argument("search")).toHaveValue("login")
    expect(await total(tasks)).toBe(found)
  })

  test("Back takes the argument away again, and Forward brings it back", async ({ page, tasks }) => {
    await tasks.argument("search").fill("login")
    await tasks.reads(() => tasks.argument("search").press("Enter"))
    const found = await total(tasks)
    // out of the input: a patch leaves what an input with the focus holds alone
    await tasks.cell(await tasks.rowKey(1), "title").focus()

    await tasks.reads(() => page.goBack())
    await expect(tasks.argument("search")).toHaveValue("")
    expect(await total(tasks)).toBe(SEED.tasks.acme)

    await tasks.reads(() => page.goForward())
    await expect(tasks.argument("search")).toHaveValue("login")
    expect(await total(tasks)).toBe(found)
  })

  test("the line of the selection under it takes one line once it fills, and none again when it empties", async ({
    tasks,
  }) => {
    const before = (await tasks.grid.boundingBox())!.y

    await tasks.box(FIRST).click()
    await expect(tasks.selectedCount).toHaveText("1 selected")
    const selected = (await tasks.grid.boundingBox())!.y
    expect(selected).toBeGreaterThan(before)
    await tasks.reads(() => tasks.filterValue("billable?").selectOption("yes"))
    await expect(tasks.clearFilters).toBeVisible()
    // the filter's button is on the same line
    expect((await tasks.grid.boundingBox())!.y).toBe(selected)

    await tasks.reads(() => tasks.clearFilters.click())
    await expect(tasks.selectedCount).toHaveText("")
    expect((await tasks.grid.boundingBox())!.y).toBe(before)
  })

  test("a selection is given up when an argument changes", async ({ tasks }) => {
    await tasks.box(FIRST).click()
    await expect(tasks.selectedCount).toHaveText("1 selected")

    await tasks.argument("search").fill("the")
    await tasks.reads(() => tasks.argument("search").press("Enter"))

    await expect(tasks.selectedCount).toHaveText("")
    expect(await tasks.selectedKeys()).toEqual([])
  })
})

test.describe("the argument a column of /tasks asks for", () => {
  test.beforeEach(async ({ tasks }) => {
    await tasks.open()
  })

  test("is what its column is computed with, and its column alone", async ({ page, tasks }) => {
    await expect(tasks.header("due_within?")).toHaveText("Due within 7 days")
    await expect(tasks.header("due_within")).toHaveText("Due within")

    const yes = async (column: string) =>
      (await tasks.columnTexts(column)).filter((text) => text.includes("Yes")).length
    const fixed = await yes("due_within?")
    const asked = await yes("due_within")
    expect(asked, "30 days hold what 7 days hold").toBeGreaterThanOrEqual(fixed)

    await tasks.argument("due_within-days").fill("0")
    await tasks.reads(() => tasks.argument("due_within-days").press("Enter"))

    expect(params(page)).toEqual({ "task[c][due_within][days]": "0" })
    expect(await yes("due_within?"), "the column that fixes its argument is as it was").toBe(fixed)
    expect(await yes("due_within")).toBeLessThanOrEqual(fixed)
  })

  test("its column is sorted and filtered by with it", async ({ page, tasks }) => {
    await tasks.reads(() => tasks.filterValue("due_within").selectOption("yes"))
    const within30 = await total(tasks)

    await tasks.argument("due_within-days").fill("365")
    await tasks.reads(() => tasks.argument("due_within-days").press("Enter"))
    const within365 = await total(tasks)

    expect(within365).toBeGreaterThan(within30)
    expect(params(page)).toEqual({
      "task[c][due_within][days]": "365",
      "task[f][due_within]": "yes",
    })

    // and not within 7 days, which is the other column's own argument
    await tasks.reads(() => tasks.filterValue("due_within?").selectOption("no"))
    expect(await total(tasks)).toBeLessThan(within365)
    for (const text of await tasks.columnTexts("due_within?")) expect(text).toContain("No")
    for (const text of await tasks.columnTexts("due_within")) expect(text).toContain("Yes")

    await tasks.sortBy("due_within")
    await expect(tasks.header("due_within")).toHaveAttribute("aria-sort", "ascending")
    await expect(tasks.error).toHaveCount(0)
  })

  for (const theme of ["light", "dark"] as const) {
    test(`a value Ash refuses is said at its input, and the rows stay (${theme})`, async ({
      page,
      tasks,
    }) => {
      await page.addInitScript((theme) => localStorage.setItem("phx:theme", theme), theme)
      await tasks.open()
      const rows = await tasks.rowKeys()

      const days = tasks.argument("due_within-days")
      await days.fill("-1")
      await days.press("Enter")

      await expect(tasks.argumentError("due_within-days")).toHaveText(
        "must be greater than or equal to 0",
      )
      await expect(days).toHaveAttribute("aria-invalid", "true")
      await expect(days).toHaveAccessibleDescription("must be greater than or equal to 0")
      await expect(days, "what was typed stays, to be put right").toHaveValue("-1")
      await expect(days).toBeFocused()
      await expect(tasks.status).toHaveText(
        /^Due within: Days: must be greater than or equal to 0\s*$/,
      )
      // no error in place of the rows, which are the ones that were there
      await expect(tasks.error).toHaveCount(0)
      expect(await tasks.rowKeys()).toEqual(rows)
      expect(params(page)).toEqual({})
      await expectNoAxeViolations(page)

      await days.fill("14")
      await tasks.reads(() => days.press("Enter"))
      await expect(tasks.argumentError("due_within-days")).toHaveCount(0)
      await expect(days).not.toHaveAttribute("aria-invalid")
    })
  }
})

test.describe("/deadlines: a read action that requires an argument", () => {
  let deadlines: Table

  test.beforeEach(async ({ page }) => {
    deadlines = new Table(page, "deadline", "/deadlines")
  })

  for (const theme of ["light", "dark"] as const) {
    test(`asks for it in place of the rows, and shows them once it is given (${theme})`, async ({
      page,
    }) => {
      await page.addInitScript((theme) => localStorage.setItem("phx:theme", theme), theme)
      await deadlines.open()
      await expect(page.locator("html")).toHaveAttribute("data-theme", theme)

      await expect(deadlines.fill).toHaveText("Fill in Due by to see records.")
      await expect(deadlines.rows).toHaveCount(0)
      await expect(deadlines.empty).toHaveCount(0)
      await expect(deadlines.error).toHaveCount(0)
      await expect(deadlines.pagination).toHaveCount(0)
      await expect(deadlines.status).toHaveText(/^Fill in Due by to see records\.\s*$/)
      await expect(page.getByLabel("Due by")).toHaveId("deadline-arg-by")
      await expect(deadlines.argument("by")).toHaveAttribute("aria-required", "true")
      await expect(deadlines.argument("include_done?")).not.toBeChecked()
      await expectNoAxeViolations(page)

      const before = (await deadlines.grid.boundingBox())!.y

      await deadlines.argument("by").fill(inDays(60))
      await deadlines.reads(() => deadlines.argument("by").press("Enter"))

      await expect(deadlines.fill).toHaveCount(0)
      expect(await deadlines.rows.count()).toBeGreaterThan(0)
      expect(params(page)).toEqual({ "deadline[a][by]": inDays(60) })
      expect((await deadlines.grid.boundingBox())!.y, "the grid is where it was").toBe(before)
      await expectNoAxeViolations(page)
    })
  }

  test("the table is reached with Tab from the line while it has no rows", async ({ page }) => {
    await deadlines.open()

    // (a date input is several tab stops of the browser's own)
    await deadlines.argument("include_done?").focus()
    await page.keyboard.press("Tab")
    await expect(page.locator("#deadline-arg-tags-add")).toBeFocused()
    // the line is the last of the heading line ("Columns" comes before it,
    // hiding.spec.ts), and the table creates nothing: then "Skip table", and
    // the table's header
    await page.keyboard.press("Tab")
    await expect(deadlines.skip).toBeFocused()
    await page.keyboard.press("Tab")
    expect(await deadlines.grid.evaluate((table) => table.contains(document.activeElement))).toBe(true)
  })

  test("a box is applied when it is ticked, and its default is not in the URL", async ({ page }) => {
    await deadlines.open(`/deadlines?deadline[a][by]=${inDays(60)}`)
    const open = await total(deadlines)

    await deadlines.reads(() => deadlines.argument("include_done?").check())
    expect(await total(deadlines)).toBeGreaterThan(open)
    expect(params(page)).toEqual({
      "deadline[a][by]": inDays(60),
      "deadline[a][include_done?]": "true",
    })

    await deadlines.reads(() => deadlines.argument("include_done?").uncheck())
    expect(await total(deadlines)).toBe(open)
    expect(params(page)).toEqual({ "deadline[a][by]": inDays(60) })
  })

  test("a list is given value by value, with the keyboard", async ({ page }) => {
    await deadlines.open(`/deadlines?deadline[a][by]=${inDays(60)}`)
    const all = await total(deadlines)
    const add = page.locator("#deadline-arg-tags-add")

    await add.focus()
    await page.keyboard.press("Enter")
    const first = page.locator("#deadline-arg-tags-0")
    await expect(first, "focus goes into the row that was added").toBeFocused()
    await expect(first).toHaveAccessibleName("Tags 1")

    await page.keyboard.type("api")
    await deadlines.reads(() => page.keyboard.press("Enter"))
    const api = await total(deadlines)
    expect(api).toBeLessThan(all)
    for (const tags of await deadlines.columnTexts("tags")) expect(tags).toContain("api")
    expect(params(page)).toEqual({ "deadline[a][by]": inDays(60), "deadline[a][tags][]": "api" })
    await expect(first).toBeFocused()

    await add.click()
    const second = page.locator("#deadline-arg-tags-1")
    await expect(second).toBeFocused()
    await page.keyboard.type("mobile")
    await deadlines.reads(() => page.keyboard.press("Enter"))
    expect(await total(deadlines)).toBeGreaterThan(api)
    await expectNoAxeViolations(page)

    // taken away again: focus goes to what stands in its place
    await deadlines.reads(() => page.getByRole("button", { name: "Remove Tags 1" }).click())
    await expect(first).toHaveValue("mobile")
    await expect(first).toBeFocused()
    await deadlines.reads(() => page.getByRole("button", { name: "Remove Tags 1" }).click())
    await expect(add).toBeFocused()
    expect(await total(deadlines)).toBe(all)
    expect(params(page)).toEqual({ "deadline[a][by]": inDays(60) })
  })

  test("in German", async ({ page }) => {
    await deadlines.open()
    await switchLocale(page, "de")
    await deadlines.ready()

    await expect(deadlines.fill).toHaveText("Fällig bis ausfüllen, um Datensätze zu sehen.")
    await expect(page.getByLabel("Fällig bis")).toHaveId("deadline-arg-by")
    await expectNoAxeViolations(page)
  })
})

test.describe("a table without arguments", () => {
  test("has no line: it is as it was", async ({ page }) => {
    const labels = new Table(page, "label", "/labels")
    await labels.open()

    await expect(labels.argumentLine).toHaveCount(0)
    await expect(labels.fill).toHaveCount(0)
    await expect(page.locator("form[data-arguments]")).toHaveCount(0)
  })
})

test.describe("a nested table", () => {
  test("has its own line, whose inputs Tab stops at, and keeps its arguments out of the URL", async ({
    page,
  }) => {
    const projects = new Table(page, "project", "/projects")
    await projects.open()
    const tasks = await projects.openLine(SEED.project.mobileApp, "tasks")

    await expect(tasks.argumentLine.locator("input")).toHaveCount(2)
    await expect(tasks.range).toHaveText("1–25 of 57")

    // from the line's button, Tab goes on to the nested table's heading line:
    // its "Columns", then its inputs
    await projects.line(SEED.project.mobileApp, "tasks").focus()
    expect(await tasks.walk(2)).toEqual([`${tasks.id}-columns-button`, `${tasks.id}-arg-search`])

    await page.keyboard.type("Fix")
    await tasks.reads(() => page.keyboard.press("Enter"))

    await expect(tasks.range).toHaveText("1–7 of 7")
    await expect(tasks.argument("search")).toBeFocused()
    expect(params(page)).toEqual({})
    await expectNoAxeViolations(page)
  })
})

test.describe("the picker", () => {
  test("has the line of the table it shows: the tasks to choose from are searched", async ({
    page,
  }) => {
    const comments = new Table(page, "comment", "/comments")
    await comments.open()
    await comments.create.click()
    await comments.fieldChoose("task_id").click()
    await expect(comments.picker).toBeVisible()

    const tasks = comments.pickerTable("task_id")
    await expect(tasks.argument("search")).toBeVisible()

    await tasks.argument("search").fill("login")
    await tasks.reads(() => tasks.argument("search").press("Enter"))
    const key = await tasks.rowKey(1)
    const title = await tasks.cell(key, "title").textContent()
    await expectNoAxeViolations(page)

    await tasks.radio(key).click()
    await comments.pickerChoose.click()

    await expect(comments.picker).toHaveCount(0)
    await expect(comments.fieldChosen("task_id")).toHaveText(title!)
  })
})
