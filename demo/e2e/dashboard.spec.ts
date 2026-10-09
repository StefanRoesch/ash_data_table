import { expect, test } from "./support/fixtures"
import { SEED } from "./support/data"
import { Table } from "./support/table"

// /dashboard: two tables placed in a LiveView of the demo's own with
// `<AshTable.table>`, where the router's `ash_table` gives a table a page to
// itself. Each keeps its sort, filters and page itself, nothing of them is
// in the URL, and neither moves when the other does. Two grids on one page:
// each is one tab stop, and each has a keyboard of its own.

const FIRST = SEED.task.first
const SECOND = SEED.task.second

let projects: Table
let tasks: Table

test.beforeEach(async ({ page, actor }) => {
  projects = new Table(page, "dashboard-projects", "/dashboard")
  tasks = new Table(page, "dashboard-tasks", "/dashboard")
  await tasks.open()
  // nobody may not read the projects, and that table is not there for them
  if (actor !== "nobody") await projects.ready()
})

test.describe("the page", () => {
  test("is reached from the header and from the front page", async ({ page }) => {
    await page.goto("/")
    await page.getByRole("navigation", { name: "Main" }).getByRole("link", { name: "Dashboard" }).click()
    await expect(page).toHaveURL(/\/dashboard$/)
    await tasks.ready()

    await page.goto("/")
    await page.locator("#embedded").getByRole("link", { name: "dashboard" }).click()
    await expect(page).toHaveURL(/\/dashboard$/)
    await projects.ready()
    await tasks.ready()
    await expect(page).toHaveTitle("Dashboard · ash_table demo")
  })

  test("holds two tables, each a grid named after its resource under a heading of its own", async ({
    page,
  }) => {
    await expect(page.getByRole("heading", { level: 1 })).toHaveText("Dashboard")
    await expect(page.getByRole("heading", { level: 2 })).toHaveText(["Projects", "Tasks"])
    await expect(page.getByRole("grid")).toHaveCount(2)
    await expect(page.getByRole("grid", { name: "Projects" })).toHaveId("dashboard-projects-table")
    await expect(page.getByRole("grid", { name: "Tasks" })).toHaveId("dashboard-tasks-table")

    // as on their own pages (tables.spec.ts)
    await expect(projects.headers).toHaveText([
      "ID",
      "Name",
      "Description",
      "Status",
      "Starts on",
      "Budget",
      "Inserted at",
    ])
    await expect(projects.rows).toHaveCount(SEED.projects.acme)
    await expect(projects.range).toHaveText("1–6 of 6")
    await expect(tasks.headers).toHaveCount(19)
    await expect(tasks.rows).toHaveCount(25)
    await expect(tasks.range).toHaveText(`1–25 of ${SEED.tasks.acme}`)
    expect((await tasks.rowKeys()).slice(0, 2)).toEqual([FIRST, SECOND])

    // the pagination of each is a landmark with a name of its own
    await expect(projects.pagination).toHaveAccessibleName("Pagination: Projects")
    await expect(tasks.pagination).toHaveAccessibleName("Pagination: Tasks")

    // every id in the page is used once
    const ids = await page.locator("[id]").evaluateAll((elements) => elements.map((e) => e.id))
    expect(ids.filter((id, index) => ids.indexOf(id) !== index)).toEqual([])
  })
})

test.describe("each table keeps its own sort, filters and page", () => {
  test("a sort, a filter and a page of one leave the other and the URL as they are", async ({
    page,
  }) => {
    const url = page.url()
    const projectKeys = await projects.rowKeys()
    const taskKeys = await tasks.rowKeys()

    // sorting the projects
    await projects.reads(() => projects.header("name").click())
    await projects.reads(() => projects.header("name").click())
    await expect(projects.header("name")).toHaveAttribute("aria-sort", "descending")
    const names = await projects.columnTexts("name")
    expect(names).toEqual([...names].sort().reverse())
    await expect(tasks.header("title")).toHaveAttribute("aria-sort", "none")
    expect(await tasks.rowKeys()).toEqual(taskKeys)
    expect(page.url()).toBe(url)

    // paging the tasks
    await tasks.reads(() => tasks.next.click())
    await expect(tasks.range).toHaveText("26–50 of 320")
    await expect(tasks.pageButton(2)).toHaveAttribute("aria-current", "page")
    await expect(projects.range).toHaveText("1–6 of 6")
    await expect(projects.pageButton(1)).toHaveAttribute("aria-current", "page")
    expect(await projects.columnTexts("name")).toEqual(names)
    expect(page.url()).toBe(url)

    // filtering the tasks goes back to their first page
    await tasks.filterValue("title").fill("sess")
    await tasks.reads(() => tasks.filterValue("title").press("Enter"))
    await expect(tasks.range).toHaveText("1–18 of 18")
    await expect(tasks.status).toHaveText("18 results")
    await expect(projects.status, "only the table that was filtered says so").toHaveText("")
    await expect(tasks.clearFilters).toBeVisible()
    await expect(projects.clearFilters).toHaveCount(0)
    expect(await projects.columnTexts("name")).toEqual(names)
    expect(page.url()).toBe(url)

    // filtering the projects
    await projects.filterValue("name").fill("Billing")
    await projects.reads(() => projects.filterValue("name").press("Enter"))
    expect(await projects.columnTexts("name")).toEqual(["Billing"])
    await expect(projects.status).toHaveText("1 result")
    await expect(tasks.range).toHaveText("1–18 of 18")
    await expect(tasks.filterValue("title")).toHaveValue("sess")
    expect(page.url()).toBe(url)

    // "Clear filters" is each table's own
    await projects.reads(() => projects.clearFilters.click())
    await expect(projects.rows).toHaveCount(SEED.projects.acme)
    await expect(projects.header("name"), "the sort stays").toHaveAttribute("aria-sort", "descending")
    await expect(tasks.range).toHaveText("1–18 of 18")
    expect(page.url()).toBe(url)

    // nothing was in the URL: a reload shows both as they were at first
    await page.reload()
    await projects.ready()
    await tasks.ready()
    expect(await projects.rowKeys()).toEqual(projectKeys)
    expect(await tasks.rowKeys()).toEqual(taskKeys)
    await expect(tasks.filterValue("title")).toHaveValue("")
  })

  test("the back button leaves the page: no state of a table is in the history", async ({ page }) => {
    await page.goto("/")
    await page.locator("#embedded").getByRole("link", { name: "dashboard" }).click()
    await tasks.ready()
    await tasks.reads(() => tasks.next.click())
    await tasks.reads(() => tasks.header("title").click())

    await page.goBack()
    await expect(page).toHaveURL(/\/$/)
    await expect(page.locator("#embedded")).toBeVisible()
  })

  test("Next and a page number keep the focus, as on a page of the table's own", async () => {
    await tasks.next.focus()
    await tasks.reads(() => tasks.press("Enter"))
    await expect(tasks.range).toHaveText("26–50 of 320")
    await expect(tasks.next).toBeFocused()

    await tasks.reads(() => tasks.pageButton(13).click())
    await expect(tasks.pageButton(13)).toBeFocused()
    await tasks.reads(() => tasks.previous.click())
    await tasks.reads(() => tasks.next.click())
    await expect(tasks.next).toBeDisabled()
    await expect(tasks.pageButton(13), "the last page: its own button").toBeFocused()
  })
})

test.describe("two grids on one page", () => {
  test("each is one tab stop: Tab goes through the first and its pagination to the second", async ({
    page,
  }) => {
    const firstProject = await projects.rowKey(1)
    expect(await projects.tabStops()).toEqual([`dashboard-projects-row-${firstProject}-c-id`])
    expect(await tasks.tabStops()).toEqual([`dashboard-tasks-row-${FIRST}-c-title`])

    await projects.tabStop.focus()
    await page.keyboard.press("Tab")
    await expect(projects.pageButton(1), "Previous and Next are disabled").toBeFocused()
    // above the second grid, on the line of its name: its create button
    await page.keyboard.press("Tab")
    await expect(tasks.create).toBeFocused()
    await page.keyboard.press("Tab")
    await expect(tasks.cell(FIRST, "title")).toBeFocused()
    await page.keyboard.press("Tab")
    await expect(tasks.pageButton(1)).toBeFocused()

    await page.keyboard.press("Shift+Tab")
    await expect(tasks.cell(FIRST, "title")).toBeFocused()
    await page.keyboard.press("Shift+Tab")
    await expect(tasks.create).toBeFocused()
    await page.keyboard.press("Shift+Tab")
    await expect(projects.pageButton(1)).toBeFocused()
    await page.keyboard.press("Shift+Tab")
    await expect(projects.cell(firstProject, "id")).toBeFocused()
    await page.keyboard.press("Shift+Tab")
    expect(await projects.hasFocus(), "one more leaves the first grid at its other end").toBe(false)
    expect(await tasks.hasFocus()).toBe(false)
  })

  test("the keys move in the grid that has the focus, and each grid remembers its own cell", async ({
    page,
    frames,
  }) => {
    const projectKeys = await projects.rowKeys()
    const taskKeys = await tasks.rowKeys()

    await projects.tabStop.focus()
    await frames.clear()
    await projects.press("ArrowDown", "ArrowRight")
    await expect(projects.cell(projectKeys[1], "name")).toBeFocused()
    expect(await projects.tabStops()).toEqual([`dashboard-projects-row-${projectKeys[1]}-c-name`])
    expect(await tasks.tabStops(), "the other grid's tab stop is where it was").toEqual([
      `dashboard-tasks-row-${FIRST}-c-title`,
    ])

    // the ends of the first grid are ends: no key goes on into the second.
    // The last cell of a row holds its actions.
    await projects.press("Control+End")
    await expect(projects.actionsCell(projectKeys.at(-1)!)).toBeFocused()
    await projects.press("ArrowDown", "ArrowRight", "PageDown", "End")
    await expect(projects.actionsCell(projectKeys.at(-1)!)).toBeFocused()
    expect(await tasks.hasFocus()).toBe(false)

    // and the second grid's first rows are its header rows, not the first grid
    await tasks.tabStop.focus()
    await tasks.press("ArrowRight", "ArrowDown", "ArrowDown")
    await expect(tasks.cell(taskKeys[2], "status")).toBeFocused()
    // the first cell of the first data row: its expander
    await tasks.press("Control+Home")
    await expect(tasks.expanderCell(FIRST)).toBeFocused()
    await tasks.cell(FIRST, "title").focus()
    await tasks.press("ArrowUp", "ArrowUp")
    await expect(tasks.header("title")).toBeFocused()
    await tasks.press("ArrowUp", "PageUp")
    await expect(tasks.header("title"), "the top of the second grid").toBeFocused()
    expect(await projects.hasFocus()).toBe(false)
    expect(await frames.all(), "moving about sends nothing").toEqual([])

    // Tab from the one comes to the cell the other was left on
    await tasks.press("ArrowDown", "ArrowDown", "ArrowDown")
    await expect(tasks.cell(taskKeys[1], "title")).toBeFocused()
    // between the two grids: the pages of the first, and the create button of the second
    await page.keyboard.press("Shift+Tab")
    await page.keyboard.press("Shift+Tab")
    await page.keyboard.press("Shift+Tab")
    await expect(projects.actionsCell(projectKeys.at(-1)!)).toBeFocused()
    await page.keyboard.press("Tab")
    await page.keyboard.press("Tab")
    await page.keyboard.press("Tab")
    await expect(tasks.cell(taskKeys[1], "title")).toBeFocused()
    expect(await projects.tabStops()).toHaveLength(1)
    expect(await tasks.tabStops()).toHaveLength(1)
  })

  test("Enter on a header sorts its own grid, and a filter is entered in its own grid", async () => {
    await projects.header("name").focus()
    await projects.reads(() => projects.press("Enter"))
    await expect(projects.header("name")).toHaveAttribute("aria-sort", "ascending")
    await expect(projects.header("name")).toBeFocused()
    await expect(tasks.grid.locator('[aria-sort]:not([aria-sort="none"])')).toHaveCount(0)

    await tasks.filterCell("title").focus()
    await tasks.press("s")
    await expect(tasks.filterValue("title")).toBeFocused()
    await expect(tasks.filterValue("title")).toHaveValue("s")
    await expect(projects.filterValue("name")).toHaveValue("")
  })
})

test.describe("editing", () => {
  test.use({ writes: true })

  test.afterEach(async ({ page }) => {
    // the latency simulator remembers itself in the session storage
    await page.evaluate(() => (window as any).liveSocket?.disableLatencySim())
  })

  test("each table has the editors of its own resource, and one whose resource names no update action has none", async ({
    frames,
  }) => {
    await expect(tasks.editorTemplates).toHaveCount(11)
    // name, description, status, starts on and budget: what the projects' `update` accepts
    await expect(projects.editorTemplates).toHaveCount(5)

    // The people's table names no update action. It has no page; under a
    // task it is the one row of "Reported by".
    const reporter = await tasks.openLine(FIRST, "reporter")
    await expect(reporter.editorTemplates).toHaveCount(0)
    await expect(reporter.grid.locator("[aria-readonly]"), "nothing is marked either").toHaveCount(0)

    const name = reporter.cell(await reporter.rowKey(1), "name")
    await name.focus()
    await frames.clear()
    await tasks.press("Enter", "F2", "x")
    await name.dblclick()
    await expect(reporter.openEditors).toHaveCount(0)
    await expect(tasks.openEditors).toHaveCount(0)
    await expect(projects.openEditors).toHaveCount(0)
    await expect(name).toBeFocused()
    expect(await frames.all()).toEqual([])
  })

  test("a cell of the projects saves through the projects' own action", async ({ page }) => {
    const key = await projects.rowKey(1)
    const name = projects.cell(key, "name")
    const names = await projects.columnTexts("name")

    await name.dblclick()
    await projects.retype("Renamed on the dashboard")
    await projects.saves(name, () => projects.press("Enter"))

    await expect(name).toHaveText("Renamed on the dashboard")
    await expect(name).not.toHaveAttribute("aria-invalid")
    // the row stays where it is, although the table is sorted by name
    expect(await projects.columnTexts("name")).toEqual(["Renamed on the dashboard", ...names.slice(1)])

    const own = new Table(page, "project", "/projects")
    await own.open()
    await expect(own.cell(key, "name")).toHaveText("Renamed on the dashboard")
  })

  test("a cell saves through its own table, and the other table is not read again", async ({
    page,
    frames,
  }) => {
    const names = await projects.columnTexts("name")
    await projects.grid.evaluate((grid) => {
      ;(window as any).__projectsPatched = 0
      new MutationObserver(() => (window as any).__projectsPatched++).observe(grid, {
        subtree: true,
        childList: true,
        attributes: true,
        attributeFilter: ["aria-busy"],
      })
    })

    const title = tasks.cell(SECOND, "title")
    await title.focus()
    await frames.clear()
    await tasks.press("Enter")
    await expect(tasks.editor(title)).toBeFocused()
    await expect(tasks.openEditors).toHaveCount(1)
    await tasks.retype("Edited on the dashboard")
    await tasks.saves(title, () => tasks.press("Enter"))
    await expect(title).toHaveText("Edited on the dashboard")
    await expect(title).toBeFocused()
    expect(await frames.count("save")).toBe(1)
    expect(await tasks.tabStops()).toEqual([`dashboard-tasks-row-${SECOND}-c-title`])

    expect(await page.evaluate(() => (window as any).__projectsPatched)).toBe(0)
    expect(await projects.columnTexts("name")).toEqual(names)
    expect(await projects.tabStops()).toHaveLength(1)

    // it is in the database: the table's own page shows it
    const own = new Table(page, "task", "/tasks")
    await own.open()
    await expect(own.cell(SECOND, "title")).toHaveText("Edited on the dashboard")
  })

  test("a save that returns while the person is in the other table leaves the focus there", async ({
    page,
  }) => {
    await page.evaluate(() => (window as any).liveSocket.enableLatencySim(300))
    const title = tasks.cell(SECOND, "title")
    const elsewhere = projects.cell(await projects.rowKey(3), "status")

    await title.focus()
    await tasks.press("Enter")
    await tasks.retype("Saved from afar")
    // leaving the cell saves it; the click goes to the other grid
    await tasks.saves(title, () => elsewhere.click())

    await expect(title).toHaveText("Saved from afar")
    await expect(elsewhere, "focus stays where the person went").toBeFocused()
    expect(await projects.tabStops()).toEqual([await elsewhere.getAttribute("id")])
    expect(await tasks.tabStops()).toEqual([`dashboard-tasks-row-${SECOND}-c-title`])
  })

  test("a save that fails marks its cell and is read out by its own table", async () => {
    const title = tasks.cell(SECOND, "title")
    await title.focus()
    await tasks.press("Enter")
    await tasks.retype("ab")
    await tasks.saves(title, () => tasks.press("Enter"))

    await expect(title).toHaveAttribute("aria-invalid", "true")
    await expect(tasks.failure(title)).toHaveText("length must be greater than or equal to 3")
    await expect(tasks.status).toHaveText(
      "Title was not saved: length must be greater than or equal to 3",
    )
    await expect(projects.status).toHaveText("")
    await expect(projects.grid.locator("[aria-invalid]")).toHaveCount(0)

    await tasks.press("Escape")
    await expect(title).toHaveText("Remove the dashboard charts")
    await expect(title).not.toHaveAttribute("aria-invalid")
  })

  test("the question before a save is asked by the table the cell is in", async ({ page }) => {
    // only the tasks have a column that asks; each table has a row action
    // that does (actions.spec.ts), and so a dialog of its own
    await expect(page.locator("dialog")).toHaveCount(2)
    expect(await page.locator("dialog").evaluateAll((dialogs) => dialogs.map((dialog) => dialog.id))).toEqual([
      "dashboard-projects-dialog",
      "dashboard-tasks-dialog",
    ])

    const status = tasks.cell(SECOND, "status")
    await status.dblclick()
    await tasks.editor(status).selectOption({ label: "In review" })
    await expect(tasks.question).toBeVisible()
    await expect(projects.question).toBeHidden()
    await expect(tasks.dialog).toBeVisible()
    await expect(tasks.dialog).toHaveAccessibleName("Change the state of this task?")
    await tasks.saves(status, () => tasks.dialog.getByRole("button", { name: "Confirm" }).click())
    await expect(status).toHaveText("In review")
    await expect(status).toBeFocused()
  })
})

test.describe("as another actor", () => {
  test.describe("the member", () => {
    test.use({ actor: "member" })

    test("each table is this person's: the tasks without the column they may never see", async () => {
      expect(await tasks.columns()).not.toContain("external_ref")
      await expect(tasks.headers).toHaveCount(18)
      await expect(tasks.cell(FIRST, "estimate_hours")).toHaveText("Not available")
      await expect(projects.rows).toHaveCount(SEED.projects.acme)
    })
  })

  test.describe("nobody", () => {
    test.use({ actor: "nobody" })

    // /projects answers 404 for nobody; a table in a page of the demo's own
    // cannot make that page disappear
    test("a table whose read is refused shows nothing of itself, and the page stays", async ({
      page,
    }) => {
      await expect(page.getByRole("heading", { level: 1 })).toHaveText("Dashboard")
      await expect(projects.root).toBeHidden()
      await expect(projects.root).toBeEmpty()
      await expect(page.getByRole("grid")).toHaveCount(1)
      await expect(tasks.empty).toHaveText("No records")
      await expect(tasks.error).toHaveCount(0)
    })
  })
})
