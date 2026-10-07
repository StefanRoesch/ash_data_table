import { SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { Table } from "./support/table"

// Nested tables in a browser: the expander and the lines by pointer and by
// keyboard, into a nested table and back out, the one tab stop of the whole
// tree, and focus through everything that patches the page.
//
// /tasks as the admin. A row of it expands into seven lines; "Comments" is
// a table of several rows with keyset pages, "Project" a table of one row
// whose rows expand again into their tasks.

/** The first two rows of /tasks: a task of "Data warehouse" with one comment, and one with two labels. */
const FIRST = SEED.task.first
const SECOND = SEED.task.second

/** Acme's "Mobile app": 57 tasks, three offset pages of a nested table. */
const MOBILE_APP = SEED.project.mobileApp

test.beforeEach(async ({ tasks }) => {
  await tasks.open()
})

test.describe("with the pointer", () => {
  test("the expander shows a line per relationship, and a line opens the table of the related records", async ({
    tasks,
  }) => {
    await expect(tasks.expander(FIRST)).toHaveAttribute("aria-expanded", "false")
    await expect(tasks.expander(FIRST)).toHaveAccessibleName("Related records")
    await expect(tasks.lines(FIRST)).toHaveCount(0)

    await tasks.expander(FIRST).click()
    await expect(tasks.expander(FIRST)).toHaveAttribute("aria-expanded", "true")
    await expect(tasks.lines(FIRST)).toHaveText([
      /Comments/,
      /First comment/,
      /Newest comment/,
      /Labels/,
      /Project/,
      /Assignee/,
      /Reported by/,
    ])
    // the click leaves focus on the expander's cell, which is the tab stop
    await expect(tasks.expanderCell(FIRST)).toBeFocused()
    expect(await tasks.tabStops()).toEqual([`task-row-${FIRST}-e`])

    const project = await tasks.openLine(FIRST, "project")
    await expect(tasks.line(FIRST, "project")).toHaveAttribute("aria-expanded", "true")
    await expect(tasks.lineCell(FIRST, "project")).toBeFocused()
    await expect(project.rows).toHaveCount(1)
    expect(await project.columns()).toEqual([
      "id",
      "name",
      "description",
      "status",
      "starts_on",
      "budget",
      "inserted_at",
    ])

    // a grid of its own, named by its line and by the row it belongs to
    const title = await tasks.cell(FIRST, "title").textContent()
    await expect(project.grid).toHaveRole("grid")
    await expect(project.grid).toHaveAccessibleName(`Project ${title}`)

    await tasks.line(FIRST, "project").click()
    await expect(tasks.line(FIRST, "project")).toHaveAttribute("aria-expanded", "false")
    await expect(project.root).toHaveCount(0)

    await tasks.expander(FIRST).click()
    await expect(tasks.expander(FIRST)).toHaveAttribute("aria-expanded", "false")
    await expect(tasks.lines(FIRST)).toHaveCount(0)
  })

  test("a nested table leaves the columns of the table around it as wide as they were", async ({
    tasks,
  }) => {
    const widths = () =>
      tasks.headerCells.evaluateAll((cells) => cells.map((cell) => Math.round(cell.getBoundingClientRect().width)))
    const before = await widths()

    // the tasks of a project, 14 columns wide, under a row of /tasks
    const project = await tasks.openLine(FIRST, "project")
    const [key] = await project.rowKeys()
    await project.openLine(key, "tasks")

    expect(await widths()).toEqual(before)
  })

  test("a table that never nests has no expanders: the people under a task", async ({ tasks }) => {
    const reporter = await tasks.openLine(FIRST, "reporter")

    await expect(reporter.rows).toHaveCount(1)
    await expect(reporter.expanders).toHaveCount(0)
    expect(await reporter.columns()).toEqual(["name", "email", "role"])
    await expect(reporter.grid).toHaveAttribute("aria-colcount", "3")
  })
})

test.describe("with the keyboard", () => {
  test("Tab enters the grid at the first data cell, with the expander one cell to its left", async ({
    page,
    tasks,
  }) => {
    await tasks.pageButton(1).focus()
    await page.keyboard.press("Shift+Tab")
    await expect(tasks.cell(FIRST, "title")).toBeFocused()

    await tasks.press("ArrowLeft")
    await expect(tasks.expanderCell(FIRST)).toBeFocused()
    await tasks.press("ArrowLeft")
    await expect(tasks.expanderCell(FIRST), "the first cell of a row is where Left ends").toBeFocused()
    await expect(tasks.expander(FIRST)).toHaveAttribute("aria-expanded", "false")
  })

  test("Right Arrow on an expander opens it, Left Arrow closes it, and Enter does either", async ({
    tasks,
  }) => {
    await tasks.expanderCell(FIRST).focus()

    await tasks.press("ArrowRight")
    await expect(tasks.expander(FIRST)).toHaveAttribute("aria-expanded", "true")
    await expect(tasks.lines(FIRST)).toHaveCount(7)
    await expect(tasks.expanderCell(FIRST), "focus stays on the expander").toBeFocused()

    // open already: Right Arrow moves on
    await tasks.press("ArrowRight")
    await expect(tasks.cell(FIRST, "title")).toBeFocused()
    await tasks.press("ArrowLeft")
    await expect(tasks.expanderCell(FIRST)).toBeFocused()

    await tasks.press("ArrowLeft")
    await expect(tasks.expander(FIRST)).toHaveAttribute("aria-expanded", "false")
    await expect(tasks.lines(FIRST)).toHaveCount(0)
    await expect(tasks.expanderCell(FIRST)).toBeFocused()

    await tasks.press("Enter")
    await expect(tasks.expander(FIRST)).toHaveAttribute("aria-expanded", "true")
    await tasks.press("Enter")
    await expect(tasks.expander(FIRST)).toHaveAttribute("aria-expanded", "false")
    expect(await tasks.tabStops()).toEqual([`task-row-${FIRST}-e`])
  })

  test("the lines are cells the arrow keys stop at, and open and close as the expander does", async ({
    tasks,
  }) => {
    await tasks.expanderCell(FIRST).focus()
    await tasks.press("ArrowRight")
    await expect(tasks.lines(FIRST)).toHaveCount(7)

    await tasks.press("ArrowDown")
    await expect(tasks.lineCell(FIRST, "comments")).toBeFocused()
    await tasks.press("ArrowDown", "ArrowDown", "ArrowDown", "ArrowDown")
    await expect(tasks.lineCell(FIRST, "project")).toBeFocused()

    await tasks.press("ArrowRight")
    await expect(tasks.line(FIRST, "project")).toHaveAttribute("aria-expanded", "true")
    await expect(tasks.lineCell(FIRST, "project"), "focus stays on the line").toBeFocused()
    await tasks.nested(FIRST, "project").loaded()
    // open already: Right Arrow has nowhere to go in a cell that spans the table
    await tasks.press("ArrowRight")
    await expect(tasks.lineCell(FIRST, "project")).toBeFocused()

    await tasks.press("ArrowLeft")
    await expect(tasks.line(FIRST, "project")).toHaveAttribute("aria-expanded", "false")
    await expect(tasks.nested(FIRST, "project").root).toHaveCount(0)
    await expect(tasks.lineCell(FIRST, "project")).toBeFocused()

    await tasks.press("Enter")
    await expect(tasks.line(FIRST, "project")).toHaveAttribute("aria-expanded", "true")
    await tasks.press("Enter")
    await expect(tasks.line(FIRST, "project")).toHaveAttribute("aria-expanded", "false")

    // down from the last line is the next row, in the column the person came from
    await tasks.press("ArrowDown", "ArrowDown", "ArrowDown")
    await expect(tasks.expanderCell(SECOND)).toBeFocused()
    // and up from there is the last line again, then the lines, then the row itself
    await tasks.press("ArrowUp")
    await expect(tasks.lineCell(FIRST, "reporter")).toBeFocused()
    await tasks.press("ArrowUp", "ArrowUp", "ArrowUp", "ArrowUp", "ArrowUp", "ArrowUp", "ArrowUp")
    await expect(tasks.expanderCell(FIRST)).toBeFocused()
    expect(await tasks.tabStops()).toHaveLength(1)
  })

  test("Enter on the cell of a nested table goes into it, and Escape comes back out", async ({
    tasks,
  }) => {
    await tasks.expanderCell(FIRST).focus()
    await tasks.press("ArrowRight")
    await tasks.lineCell(FIRST, "project").focus()
    await tasks.press("ArrowRight")
    const project = tasks.nested(FIRST, "project")
    await project.loaded()
    const [key] = await project.rowKeys()

    // the cell that holds the nested table is the next stop down
    await tasks.press("ArrowDown")
    await expect(tasks.nestedCell(FIRST, "project")).toBeFocused()

    await tasks.press("Enter")
    await expect(project.cell(key, "id"), "its first data cell").toBeFocused()
    expect(await tasks.tabStops()).toEqual([`${project.id}-row-${key}-c-id`])

    // in it, the arrow keys are its own
    await tasks.press("ArrowRight")
    await expect(project.cell(key, "name")).toBeFocused()
    await tasks.press("ArrowUp")
    await expect(project.filterCell("name")).toBeFocused()
    await tasks.press("ArrowUp")
    await expect(project.header("name")).toBeFocused()
    await tasks.press("ArrowUp")
    await expect(project.header("name"), "Up ends at its header, not in the table around it").toBeFocused()
    await tasks.press("ArrowDown", "ArrowDown", "ArrowDown")
    await expect(project.cell(key, "name"), "Down ends at its last row").toBeFocused()

    await tasks.press("Escape")
    await expect(tasks.nestedCell(FIRST, "project")).toBeFocused()
    expect(await tasks.tabStops()).toEqual([`task-row-${FIRST}-n-project-c`])

    // and back in at the cell it was left at
    await tasks.press("F2")
    await expect(project.cell(key, "name")).toBeFocused()
    await tasks.press("Escape", "ArrowUp")
    await expect(tasks.lineCell(FIRST, "project")).toBeFocused()
  })

  test("Tab leaves the whole tree from inside a nested table, and comes back to where it was", async ({
    page,
    tasks,
  }) => {
    const project = await tasks.openLine(FIRST, "project")
    const [key] = await project.rowKeys()
    const nestedTasks = await project.openLine(key, "tasks")
    const [inner] = await nestedTasks.rowKeys()

    await nestedTasks.cell(inner, "title").click()
    await expect(nestedTasks.cell(inner, "title")).toBeFocused()
    // the pages of the nested table are no tab stops: the next one is outside the grid
    expect(await tasks.tabStops()).toEqual([`${nestedTasks.id}-row-${inner}-c-title`])

    await page.keyboard.press("Tab")
    await expect(tasks.pageButton(1)).toBeFocused()
    await page.keyboard.press("Shift+Tab")
    await expect(nestedTasks.cell(inner, "title")).toBeFocused()

    await page.keyboard.press("Shift+Tab")
    expect(await tasks.hasFocus()).toBe(false)
  })

  test("moving about, in the lines and in a nested table, sends nothing; opening a line sends one event", async ({
    tasks,
    frames,
  }) => {
    await tasks.expanderCell(FIRST).focus()
    await frames.clear()
    await tasks.press("ArrowRight")
    await expect(tasks.lines(FIRST)).toHaveCount(7)
    expect(await frames.count("expand")).toBe(1)
    expect(await frames.all()).toHaveLength(1)

    await tasks.press("ArrowDown")
    await frames.clear()
    await tasks.press("ArrowRight")
    const comments = tasks.nested(FIRST, "comments")
    await comments.loaded()
    expect(await frames.count("toggle")).toBe(1)
    expect(await frames.all()).toHaveLength(1)

    await frames.clear()
    await tasks.press("ArrowDown", "Enter")
    await tasks.press("ArrowRight", "ArrowDown", "ArrowUp", "ArrowUp", "ArrowLeft", "End", "Home")
    await tasks.press("Control+End", "Control+Home", "PageDown", "PageUp", "Escape")
    await expect(tasks.nestedCell(FIRST, "comments")).toBeFocused()
    await tasks.press("ArrowDown", "ArrowDown", "ArrowUp", "ArrowUp", "ArrowUp", "ArrowUp")
    await expect(tasks.expanderCell(FIRST)).toBeFocused()

    expect(await frames.all()).toEqual([])
    expect(await tasks.tabStops()).toHaveLength(1)
  })

  test("Space and a character do nothing on an expander, a line and the cell of a nested table", async ({
    page,
    tasks,
    frames,
  }) => {
    await tasks.openLine(FIRST, "project")
    await frames.clear()

    for (const cell of [
      tasks.expanderCell(FIRST),
      tasks.lineCell(FIRST, "project"),
      tasks.nestedCell(FIRST, "project"),
    ]) {
      await cell.focus()
      await page.keyboard.press("Space")
      await page.keyboard.press("x")
      await page.keyboard.press("F2")
      await expect(tasks.openEditors).toHaveCount(0)
    }

    // F2 on the cell of the nested table went into it; nothing else happened
    expect(await frames.all()).toEqual([])
    await expect(tasks.expander(FIRST)).toHaveAttribute("aria-expanded", "true")
    await expect(tasks.line(FIRST, "project")).toHaveAttribute("aria-expanded", "true")
  })
})

test.describe("three levels down", () => {
  test("nested tables expand again, with one tab stop at every depth, down to the limit", async ({
    tasks,
  }) => {
    // tasks -> project -> tasks -> comments
    const project = await tasks.openLine(FIRST, "project")
    expect(await tasks.tabStops()).toHaveLength(1)
    const [projectKey] = await project.rowKeys()

    const projectTasks = await project.openLine(projectKey, "tasks")
    expect(await tasks.tabStops()).toHaveLength(1)
    await expect(projectTasks.rows).toHaveCount(25)
    await expect(projectTasks.expanders).toHaveCount(25)
    const [taskKey] = await projectTasks.rowKeys()

    const comments = await projectTasks.openLine(taskKey, "comments")
    expect(await tasks.tabStops()).toHaveLength(1)
    // at depth 3 of 3: the same table as one level up, without expanders
    await expect(comments.expanders).toHaveCount(0)
    await expect(comments.headerCells).toHaveCount(5)
    await expect(comments.grid).toHaveAttribute("aria-colcount", "5")

    // by keyboard all the way in, and all the way out again
    await projectTasks.cell(taskKey, "title").focus()
    await tasks.press("ArrowLeft")
    await expect(projectTasks.expanderCell(taskKey)).toBeFocused()
    await tasks.press("ArrowDown", "ArrowDown")
    await expect(projectTasks.nestedCell(taskKey, "comments")).toBeFocused()
    await tasks.press("Enter")
    expect(await comments.hasFocus()).toBe(true)
    expect(await tasks.tabStops()).toHaveLength(1)

    await tasks.press("Escape")
    await expect(projectTasks.nestedCell(taskKey, "comments")).toBeFocused()
    await tasks.press("Escape")
    await expect(project.nestedCell(projectKey, "tasks")).toBeFocused()
    await tasks.press("Escape")
    await expect(tasks.nestedCell(FIRST, "project")).toBeFocused()
    await tasks.press("Escape")
    await expect(tasks.nestedCell(FIRST, "project"), "at the top Escape has nowhere to go").toBeFocused()
    expect(await tasks.tabStops()).toEqual([`task-row-${FIRST}-n-project-c`])
  })
})

test.describe("focus", () => {
  test("stays in a nested table through its own sort, and goes to the cell at the same place when its rows change", async ({
    tasks,
  }) => {
    const project = await tasks.openLine(FIRST, "project")
    const [projectKey] = await project.rowKeys()
    const nested = await project.openLine(projectKey, "tasks")

    await nested.header("title").focus()
    await nested.reads(() => tasks.press("Enter"))
    await expect(nested.header("title")).toHaveAttribute("aria-sort", "ascending")
    await expect(nested.header("title")).toBeFocused()
    // the table around it has not moved
    await expect(tasks.header("title")).toHaveAttribute("aria-sort", "none")
    await expect(tasks.line(FIRST, "project")).toHaveAttribute("aria-expanded", "true")
    expect(tasks.page.url()).not.toContain("sort")

    const sorted = await nested.rowKeys()
    await nested.cell(sorted[2], "priority").focus()
    await nested.reads(() => nested.header("title").click())
    await nested.cell((await nested.rowKeys())[2], "priority").focus()
    await nested.reads(() => nested.header("progress").click())
    const resorted = await nested.rowKeys()
    expect(resorted).not.toEqual(sorted)
    expect(await tasks.tabStops()).toHaveLength(1)
    expect(await nested.hasFocus()).toBe(true)
  })

  test("goes through the pages of a nested table from its last row, and stays on the control that was used", async ({
    page,
    tasks,
  }) => {
    const projects = new Table(page, "project", "/projects")
    await projects.open()
    const nested = await projects.openLine(MOBILE_APP, "tasks")
    await expect(nested.range).toHaveText("1–25 of 57")

    // the pages are a group in the last row of the grid, and no tab stops
    await expect(nested.pagination).toHaveRole("group")
    await expect(nested.pagination).toHaveAccessibleName("Pagination: Tasks")
    const last = (await nested.rowKeys()).at(-1)!
    await nested.cell(last, "title").focus()
    expect(await projects.tabStops()).toHaveLength(1)

    await projects.press("ArrowDown")
    await expect(nested.pagerCell).toBeFocused()
    await projects.press("ArrowDown")
    await expect(nested.pagerCell, "the last row is where Down ends").toBeFocused()

    // Enter goes to the first control that can be used; Left and Right move between them
    await projects.press("Enter")
    await expect(nested.pageButton(1)).toBeFocused()
    await projects.press("ArrowRight")
    await expect(nested.pageButton(2)).toBeFocused()
    await nested.reads(() => projects.press("Enter"))
    await expect(nested.range).toHaveText("26–50 of 57")
    await expect(nested.pageButton(2)).toBeFocused()
    expect(page.url()).not.toContain("page")
    await expect(projects.range, "the projects around it are on their page").toHaveText("1–6 of 6")

    await projects.press("ArrowRight", "ArrowRight")
    await expect(nested.next).toBeFocused()
    await nested.reads(() => projects.press("Enter"))
    await expect(nested.range).toHaveText("51–57 of 57")
    // Next is disabled on the last page: focus goes to the page that is shown
    await expect(nested.pageButton(3)).toBeFocused()

    await projects.press("Escape")
    await expect(nested.pagerCell).toBeFocused()
    await projects.press("ArrowUp")
    expect(await nested.focused()).toMatch(new RegExp(`^${nested.id}-row-.*-c-title$`))
    expect(await projects.tabStops()).toHaveLength(1)
  })

  test("comes back to the line when its nested table is closed from inside, and to the expander when the row is", async ({
    tasks,
  }) => {
    const project = await tasks.openLine(FIRST, "project")
    const [key] = await project.rowKeys()

    // focus is in the nested table; the pointer closes the line around it
    await project.cell(key, "name").click()
    await tasks.line(FIRST, "project").click()
    await expect(project.root).toHaveCount(0)
    await expect(tasks.lineCell(FIRST, "project")).toBeFocused()

    await tasks.line(FIRST, "project").click()
    await project.loaded()
    await project.cell(key, "name").click()
    await tasks.expander(FIRST).click()
    await expect(tasks.lines(FIRST)).toHaveCount(0)
    await expect(tasks.expanderCell(FIRST)).toBeFocused()
    expect(await tasks.tabStops()).toEqual([`task-row-${FIRST}-e`])
  })

  test("stays in the grid when a new read of the table around it takes an open nested table away", async ({
    page,
    tasks,
  }) => {
    const project = await tasks.openLine(FIRST, "project")
    const [key] = await project.rowKeys()
    await project.cell(key, "name").click()

    // the back button after a sort reads the tasks again, from outside the grid
    await tasks.reads(() => tasks.header("title").click())
    await expect(tasks.lines(FIRST)).toHaveCount(0)

    const opened = await tasks.rowKey(1)
    const again = await tasks.openLine(opened, "project")
    const [nestedKey] = await again.rowKeys()
    await again.cell(nestedKey, "name").click()
    await tasks.reads(() => page.goBack())

    await expect(tasks.expander(FIRST)).toHaveAttribute("aria-expanded", "false")
    expect(await tasks.hasFocus()).toBe(true)
    expect(await tasks.tabStops()).toHaveLength(1)
  })
})

test.describe("filtering in a nested table", () => {
  test("its filter row works as on a page of its own, and Escape leaves the filter before it leaves the table", async ({
    page,
    tasks,
  }) => {
    const projects = new Table(page, "project", "/projects")
    await projects.open()
    const nested = await projects.openLine(MOBILE_APP, "tasks")

    await nested.filterCell("title").focus()
    await projects.press("Enter")
    await expect(nested.filterValue("title")).toBeFocused()
    await page.keyboard.type("Fix")
    await nested.reads(() => projects.press("Enter"))

    await expect(nested.status).toHaveText("7 results")
    await expect(nested.range).toHaveText("1–7 of 7")
    for (const title of await nested.columnTexts("title")) expect(title).toContain("Fix")
    await expect(nested.filterValue("title")).toBeFocused()
    expect(page.url()).not.toContain("Fix")
    // the projects are not filtered, and say nothing
    await expect(projects.rows).toHaveCount(6)
    await expect(projects.status).toHaveText("")
    await expect(projects.clearFilters).toHaveCount(0)

    // "Clear filters" of a nested table is there for the pointer, and no tab stop
    await expect(nested.clearFilters).toBeVisible()
    expect(await projects.tabStops()).toHaveLength(1)

    await projects.press("Escape")
    await expect(nested.filterCell("title")).toBeFocused()
    await projects.press("Escape")
    await expect(projects.nestedCell(MOBILE_APP, "tasks")).toBeFocused()

    await nested.reads(() => nested.clearFilters.click())
    await expect(nested.range).toHaveText("1–25 of 57")
    expect(await projects.hasFocus()).toBe(true)
    expect(await projects.tabStops()).toHaveLength(1)
  })
})

test.describe("editing in a nested table", () => {
  test.use({ writes: true })

  test("a cell is edited and saved as on a page of its own, and the table around it is not read again", async ({
    page,
    frames,
  }) => {
    const projects = new Table(page, "project", "/projects")
    await projects.open()
    const nested = await projects.openLine(MOBILE_APP, "tasks")
    const [key] = await nested.rowKeys()
    const title = nested.cell(key, "title")

    await title.focus()
    await projects.press("Enter")
    await expect(nested.editor(title)).toBeFocused()
    // while a cell is edited its editor is the one tab stop of the tree
    expect(await projects.tabStops()).toEqual(["TEXTAREA"])
    await projects.retype("Edited under its project")
    await frames.clear()
    await nested.saves(title, () => projects.press("Enter"))

    await expect(title).toHaveText("Edited under its project")
    await expect(title).toBeFocused()
    expect(await frames.count("save")).toBe(1)
    expect(await frames.all()).toHaveLength(1)
    await expect(projects.line(MOBILE_APP, "tasks")).toHaveAttribute("aria-expanded", "true")

    // Escape gives the edit up, and only the next one leaves the table
    await projects.press("Enter")
    await projects.retype("Given up")
    await projects.press("Escape")
    await expect(title).toHaveText("Edited under its project")
    await expect(title).toBeFocused()
    await projects.press("Escape")
    await expect(projects.nestedCell(MOBILE_APP, "tasks")).toBeFocused()

    // the record is saved: the page of the tasks shows it
    const tasks = new Table(page, "task", "/tasks")
    await tasks.open(`/tasks?task[f][title]=Edited under its project`)
    await expect(tasks.rows).toHaveCount(1)
  })

  test("a column that asks first asks in the nested table's own dialog, and a failed save marks its cell", async ({
    page,
  }) => {
    const projects = new Table(page, "project", "/projects")
    await projects.open()
    const nested = await projects.openLine(MOBILE_APP, "tasks")
    const [key] = await nested.rowKeys()

    const status = nested.cell(key, "status")
    await status.dblclick()
    await nested.editor(status).selectOption({ label: "Archived" })
    await expect(nested.dialog).toBeVisible()
    await expect(nested.dialog).toContainText("Change the state of this task?")
    await nested.saves(status, () => nested.dialog.getByRole("button", { name: "Confirm" }).click())
    await expect(status).toHaveText("Archived")

    const title = nested.cell(key, "title")
    await title.focus()
    await projects.press("Enter")
    await projects.retype("ab")
    await nested.saves(title, () => projects.press("Enter"))
    await expect(title).toHaveAttribute("aria-invalid", "true")
    await expect(nested.failure(title)).toHaveText("length must be greater than or equal to 3")
    await expect(nested.status).toHaveText("Title was not saved: length must be greater than or equal to 3")
    await expect(projects.status).toHaveText("")

    // Escape on the failed cell restores it; the next one leaves the table
    await projects.press("Escape")
    await expect(title).not.toHaveAttribute("aria-invalid", "true")
    await expect(title).toBeFocused()
    await projects.press("Escape")
    await expect(projects.nestedCell(MOBILE_APP, "tasks")).toBeFocused()
  })

  test("a row of the table around it that is saved keeps what is open under it, and the focus", async ({
    tasks,
  }) => {
    const comments = await tasks.openLine(SECOND, "labels")
    const title = tasks.cell(SECOND, "title")

    await title.focus()
    await tasks.press("Enter")
    await tasks.retype("Saved with its labels open")
    await tasks.saves(title, () => tasks.press("Enter"))

    await expect(title).toHaveText("Saved with its labels open")
    await expect(title).toBeFocused()
    await expect(tasks.expander(SECOND)).toHaveAttribute("aria-expanded", "true")
    await expect(tasks.line(SECOND, "labels")).toHaveAttribute("aria-expanded", "true")
    await expect(comments.grid).toBeVisible()
    // the nested table is named after the row as it is now
    await expect(comments.grid).toHaveAccessibleName("Labels Saved with its labels open")
    expect(await tasks.tabStops()).toEqual([`task-row-${SECOND}-c-title`])
  })
})

test.describe("many tables open at once", () => {
  test("a line of every row of the page, and the page is as usable as before", async ({ tasks }) => {
    // 75 clicks, each waited for
    test.setTimeout(120_000)
    const keys = await tasks.rowKeys()

    for (const key of keys) await tasks.expander(key).click()
    for (const key of keys) await expect(tasks.expander(key)).toHaveAttribute("aria-expanded", "true")
    for (const key of keys) await tasks.line(key, "comments").click()
    for (const key of keys) await tasks.nested(key, "comments").loaded()
    for (const key of keys) await tasks.line(key, "project").click()
    for (const key of keys) await tasks.nested(key, "project").loaded()

    await expect(tasks.grid.getByRole("grid")).toHaveCount(50)
    expect(await tasks.tabStops()).toHaveLength(1)
    await expect(tasks.rows).toHaveCount(25)

    // the keyboard works among them
    await tasks.cell(keys[3], "title").focus()
    await tasks.press("ArrowLeft", "ArrowDown")
    await expect(tasks.lineCell(keys[3], "comments")).toBeFocused()
    expect(await tasks.tabStops()).toHaveLength(1)
  })
})

test.describe("as the member", () => {
  test.use({ actor: "member" })

  test("a nested table hides what its own page hides: a column, and a field on some records", async ({
    page,
  }) => {
    const projects = new Table(page, "project", "/projects")
    await projects.open()
    const nested = await projects.openLine(MOBILE_APP, "tasks")

    expect(await nested.columns()).not.toContain("external_ref")
    expect(await nested.columns()).toContain("estimate_hours")
    const estimates = await nested.columnTexts("estimate_hours")
    expect(estimates, "hidden on the tasks that are not theirs").toContain("Not available")
  })
})

test.describe("as the viewer", () => {
  test.use({ actor: "viewer" })

  test("the lines to what they may never read are not there, and nothing in a nested table can be edited", async ({
    page,
    tasks,
  }) => {
    await tasks.expand(FIRST)
    await expect(tasks.lines(FIRST)).toHaveText([
      /Comments/,
      /First comment/,
      /Newest comment/,
      /Labels/,
      /Project/,
    ])

    const projects = new Table(page, "project", "/projects")
    await projects.open()
    const nested = await projects.openLine(MOBILE_APP, "tasks")
    await expect(nested.editorTemplates).toHaveCount(0)
    const [key] = await nested.rowKeys()
    await nested.cell(key, "title").dblclick()
    await expect(nested.openEditors).toHaveCount(0)
  })
})
