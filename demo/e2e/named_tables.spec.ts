import { expectNoAxeViolations } from "./support/a11y"
import { SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { Table } from "./support/table"
import { params } from "./support/url"

// Named tables, in a browser: a second table of a resource beside its
// default one. The board of the tasks (/tasks/board) and the compact
// comments (/comments/compact) as pages of their own, the compact comments
// and the short labels nested under a task of the board, the full view of a
// nested named table, and two tables of the comments on one page (/named).
//
// As the admin.

/** The first row of the board, as of /tasks: a task with one comment. */
const FIRST = SEED.task.first

type Page = import("@playwright/test").Page

const board = (page: Page) => new Table(page, "task_board", "/tasks/board")
const compact = (page: Page) => new Table(page, "comment_compact", "/comments/compact")

async function headerTexts(table: Table): Promise<string[]> {
  const columns = await table.columns()
  return Promise.all(columns.map(async (column) => (await table.header(column).innerText()).trim()))
}

test.describe("a named table as a page of its own", () => {
  test("the compact comments: their own columns under their own id, and nothing to do in a row", async ({ page }) => {
    const table = compact(page)
    await table.open()

    await expect(page.getByRole("heading", { level: 1 })).toHaveText("Comments")
    expect(await table.columns()).toEqual(["body", "author", "inserted_at"])
    expect(await headerTexts(table)).toEqual(["Body", "Author", "Inserted at"])
    await expect(table.rows).toHaveCount(20)

    // the default table of the comments has all of these
    await expect(table.actionsHeader).toHaveCount(0)
    await expect(table.create).toHaveCount(0)
    await expect(table.expanders).toHaveCount(0)
    await expect(table.editorTemplates).toHaveCount(0)

    // the author is a name here, where /comments shows the key
    const key = await table.rowKey(1)
    await expect(table.cell(key, "author")).not.toHaveText(/^[0-9a-f-]{36}$/)

    // a cell is no editor: Enter on it opens nothing
    await table.cell(key, "body").focus()
    await table.press("Enter")
    await expect(table.openEditors).toHaveCount(0)
  })

  test("keeps its sort in the URL under its own id, through a reload", async ({ page }) => {
    const table = compact(page)
    await table.open()

    await table.sortBy("body")
    expect(params(page)).toEqual({ "comment_compact[sort]": "body" })
    await expect(table.header("body")).toHaveAttribute("aria-sort", "ascending")
    const sorted = await table.columnTexts("body")

    await page.reload()
    await table.ready()
    await expect(table.header("body")).toHaveAttribute("aria-sort", "ascending")
    expect(await table.columnTexts("body")).toEqual(sorted)

    // what is under the default table's id is not this table's
    await table.open("/comments/compact?comment[sort]=-body")
    await expect(table.header("body")).toHaveAttribute("aria-sort", "none")
  })

  test("the board of the tasks: four columns, one row action, and its own keyboard", async ({ page }) => {
    const table = board(page)
    await table.open()

    await expect(page.getByRole("heading", { level: 1 })).toHaveText("Tasks")
    expect(await table.columns()).toEqual(["title", "status", "assignee", "due_on"])
    await expect(table.rows).toHaveCount(25)
    expect(await table.rowKey(1)).toBe(FIRST)

    await expect(table.actions(FIRST)).toHaveText(["Archive"])
    await expect(table.create).toHaveCount(0)

    // Tab goes along a row's stops, as on any table, its Archive button
    // last, and on to the next row
    const row = `task_board-row-${FIRST}-`
    const stops = (await table.stops()).filter((id) => id.startsWith(row))
    expect(stops.at(-1)).toBe(`${row}a-archive`)
    // the first is the row's box, which has no id of its own: `ID-s>input`
    const [holder, tag] = stops[0].split(">")
    await table.page.locator(`[id="${holder}"]`).locator(tag ?? ":scope").first().focus()
    expect(await table.walk(stops.length - 1)).toEqual(stops.slice(1))
    const [next] = await table.walk(1)
    expect(next.startsWith(`task_board-row-${await table.rowKey(2)}-`)).toBe(true)
  })

  test("both are reached from the front page and from the page of the named tables", async ({ page }) => {
    await page.goto("/")
    await page.getByRole("link", { name: "/tasks/board", exact: true }).click()
    await board(page).ready()
    await expect(page).toHaveURL(/\/tasks\/board$/)

    await page.getByRole("navigation", { name: "Main" }).getByRole("link", { name: "Named tables" }).click()
    await expect(page.getByRole("heading", { level: 1 })).toHaveText("Named tables")
    await page.getByRole("link", { name: "compact comments" }).click()
    await compact(page).ready()
    await expect(page).toHaveURL(/\/comments\/compact$/)
  })
})

test.describe("editing and acting in a named table", () => {
  test("a cell of the board is saved through the board's own update action", async ({ page }) => {
    const table = board(page)
    await table.open()

    const cell = table.cell(FIRST, "title")
    await cell.focus()
    await table.press("Enter")
    await expect(table.editor(cell)).toBeFocused()
    await table.retype("Renamed on the board")
    await table.saves(cell, () => table.press("Enter"))
    await expect(cell).toHaveText("Renamed on the board")
    await expect(cell).toBeFocused()

    // the default table shows the same record
    const tasks = new Table(page, "task", "/tasks")
    await tasks.open()
    await expect(tasks.cell(FIRST, "title")).toHaveText("Renamed on the board")
  })

  test("the assignee is chosen in the picker, which shows the people's default table", async ({ page }) => {
    const table = board(page)
    await table.open()

    const cell = table.cell(FIRST, "assignee")
    await cell.focus()
    await table.press("Enter")
    await expect(table.picker).toBeVisible()
    await expect(table.pickerTitle).toHaveText("Assignee: choose user")

    const people = table.pickerTable("assignee")
    await people.loaded()
    expect(await people.columns()).toEqual(["name", "email", "role", "assigned_hours"])

    const keys = await people.rowKeys()
    const chosen = keys.at(-1)!
    const name = (await people.cell(chosen, "name").textContent())!.trim()
    await people.radio(chosen).check()
    await table.saves(cell, () => table.pickerChoose.click())
    await expect(table.picker).toHaveCount(0)
    await expect(cell).toHaveText(name)
  })
})

test.describe("nested under a row of the board", () => {
  test("the comments are the compact table, and link to the page of that same table", async ({ page }) => {
    const table = board(page)
    await table.open()
    const title = (await table.cell(FIRST, "title").textContent())!.trim()

    await table.expand(FIRST)
    await expect(table.lines(FIRST)).toHaveText(["Comments", "Labels"])

    const nested = await table.openLine(FIRST, "comments")
    expect(await nested.columns()).toEqual(["body", "author", "inserted_at"])
    const bodies = await nested.columnTexts("body")
    expect(bodies.length).toBeGreaterThan(0)
    // nothing to do in it, and no "New comment" on its line
    await expect(nested.actionsHeader).toHaveCount(0)
    await expect(table.lineCreate(FIRST, "comments")).toHaveCount(0)

    await expect(nested.fullView).toHaveText("Open in full view")
    await nested.fullView.click()

    const full = compact(page)
    await full.ready()
    expect(new URL(page.url()).pathname).toBe("/comments/compact")
    // the parent is named with the table that offers the relationship
    expect(params(page)).toEqual({ "comment_compact[of][task_board][comments]": FIRST })
    await expect(full.relatedHeading).toHaveText(`${title}: Comments`)
    expect(await full.columns()).toEqual(["body", "author", "inserted_at"])
    expect(await full.columnTexts("body")).toEqual(bodies)

    // the limit stays through a sort and a reload
    await full.sortBy("body")
    expect(params(page)).toEqual({
      "comment_compact[of][task_board][comments]": FIRST,
      "comment_compact[sort]": "body",
    })
    await page.reload()
    await full.ready()
    expect((await full.columnTexts("body")).sort()).toEqual([...bodies].sort())

    // the parent in the heading leads back to the board, not to /tasks
    await expect(full.relatedParent).toHaveAttribute("href", /^\/tasks\/board/)

    await full.reads(() => full.relatedClear.click())
    expect(params(page)).toEqual({})
    await expect(full.rows).toHaveCount(20)
  })

  test("the labels are the short table, which is mounted nowhere: no link, though /labels exists", async ({
    page,
  }) => {
    const table = board(page)
    await table.open()

    const comments = await table.openLine(FIRST, "comments")
    await expect(comments.fullView).toHaveCount(1)

    const labels = await table.openLine(FIRST, "labels")
    expect(await labels.columns()).toEqual(["name", "colour"])
    await expect(labels.fullView).toHaveCount(0)
    await expect(labels.viewCell).toHaveCount(0)
    await expect(labels.actionsHeader).toHaveCount(0)

    // on /tasks the same relationship nests the default table of the labels, which is mounted
    const tasks = new Table(page, "task", "/tasks")
    await tasks.open()
    const defaults = await tasks.openLine(FIRST, "labels")
    expect(await defaults.columns()).toEqual(["id", "name", "colour"])
    await expect(defaults.fullView).toHaveCount(1)
    await expect(defaults.fullView).toHaveAttribute("href", /^\/labels\?/)
  })

  test("the comments under a task of /tasks are still the default table, with its link to /comments", async ({
    tasks,
  }) => {
    await tasks.open()
    const nested = await tasks.openLine(FIRST, "comments")
    expect(await nested.columns()).toEqual(["id", "body", "inserted_at", "task_id", "author_id"])
    await expect(nested.fullView).toHaveAttribute("href", /^\/comments\?comment/)
    await expect(tasks.lineCreate(FIRST, "comments")).toHaveCount(1)
  })

  test("a limit from a table that nests another table of the comments is no limit", async ({ page }) => {
    const full = compact(page)
    // the default table of the tasks nests the default comments, not these
    await full.open(`/comments/compact?comment_compact[of][task][comments]=${FIRST}`)
    await expect(full.relatedHeading).toHaveCount(0)
    await expect(full.rows).toHaveCount(20)
  })
})

test.describe("two tables of one resource on one page", () => {
  const both = (page: Page) => ({
    defaults: new Table(page, "comment", "/named"),
    named: new Table(page, "comment_compact", "/named"),
  })

  test("each has its own id, name, columns and \"Skip table\", without an id being written", async ({ page }) => {
    const { defaults, named } = both(page)
    await page.goto("/named")
    await defaults.ready()
    await named.ready()

    await expect(page.getByRole("heading", { level: 2 })).toHaveText(["Comments", "Comments, compact"])
    await expect(page.getByRole("region", { name: "Comments", exact: true })).toHaveId("named-default-section")
    await expect(page.getByRole("region", { name: "Comments, compact" })).toHaveId("named-compact-section")

    expect(await defaults.columns()).toEqual(["id", "body", "inserted_at", "task_id", "author_id"])
    expect(await named.columns()).toEqual(["body", "author", "inserted_at"])

    // every id in the page is used once
    const ids = await page.locator("[id]").evaluateAll((elements) => elements.map((e) => e.id))
    expect(ids.filter((id, index) => ids.indexOf(id) !== index)).toEqual([])

    // each has its own "Skip table", named after it
    await expect(defaults.skip).toHaveText("Skip table Comments")
    await expect(named.skip).toHaveText("Skip table Comments, compact")
  })

  test("each keeps its own sort and page in the one URL, through a reload", async ({ page }) => {
    const { defaults, named } = both(page)
    await page.goto("/named")
    await defaults.ready()
    await named.ready()

    await named.sortBy("body")
    expect(params(page)).toEqual({ "comment_compact[sort]": "body" })
    await expect(defaults.header("body")).toHaveAttribute("aria-sort", "none")

    await defaults.sortBy("body")
    await defaults.sortBy("body")
    expect(params(page)).toEqual({ "comment[sort]": "-body", "comment_compact[sort]": "body" })

    await named.reads(() => named.next.click())
    expect(Object.keys(params(page)).sort()).toEqual([
      "comment[sort]",
      "comment_compact[after]",
      "comment_compact[sort]",
    ])
    const upper = await defaults.columnTexts("body")
    const lower = await named.columnTexts("body")

    await page.reload()
    await defaults.ready()
    await named.ready()
    await expect(defaults.header("body")).toHaveAttribute("aria-sort", "descending")
    await expect(named.header("body")).toHaveAttribute("aria-sort", "ascending")
    expect(await defaults.columnTexts("body")).toEqual(upper)
    expect(await named.columnTexts("body")).toEqual(lower)
  })
})

for (const theme of ["light", "dark"] as const) {
  test.describe(`axe, in the ${theme} theme`, () => {
    test.beforeEach(async ({ page }) => {
      await page.addInitScript((theme) => localStorage.setItem("phx:theme", theme), theme)
    })

    test("finds nothing wrong with the two tables of the comments on one page", async ({ page }) => {
      const defaults = new Table(page, "comment", "/named")
      const named = new Table(page, "comment_compact", "/named")
      await page.goto("/named")
      await defaults.ready()
      await named.ready()
      await expect(page.locator("html")).toHaveAttribute("data-theme", theme)
      await expectNoAxeViolations(page)

      await named.sortBy("body")
      await expectNoAxeViolations(page)
    })

    test("finds nothing wrong with the board, its nested named tables open", async ({ page }) => {
      const table = board(page)
      await table.open()
      await expect(page.locator("html")).toHaveAttribute("data-theme", theme)
      await expectNoAxeViolations(page)

      await table.openLine(FIRST, "comments")
      await table.openLine(FIRST, "labels")
      await expectNoAxeViolations(page)
    })

    test("finds nothing wrong with the compact comments, as a page and as a full view", async ({ page }) => {
      const table = compact(page)
      await table.open()
      await expect(page.locator("html")).toHaveAttribute("data-theme", theme)
      await expectNoAxeViolations(page)

      await table.open(`/comments/compact?comment_compact[of][task_board][comments]=${FIRST}`)
      await expect(table.relatedHeading).toBeVisible()
      await expectNoAxeViolations(page)
    })
  })
}
