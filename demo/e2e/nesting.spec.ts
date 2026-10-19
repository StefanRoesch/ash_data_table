import { SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { Table } from "./support/table"

// Nested tables in a browser: the expander and the lines by pointer and by
// keyboard, Tab into a nested table and back out (it is simply further down
// the page), and focus through everything that patches the page.
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
    // the click leaves focus on the expander, a button
    await expect(tasks.expander(FIRST)).toBeFocused()

    const project = await tasks.openLine(FIRST, "project")
    await expect(tasks.line(FIRST, "project")).toHaveAttribute("aria-expanded", "true")
    await expect(tasks.line(FIRST, "project")).toBeFocused()
    await expect(project.rows).toHaveCount(1)
    expect(await project.columns()).toEqual([
      "id",
      "name",
      "description",
      "status",
      "starts_on",
      "budget",
      "client",
      "milestones",
      "inserted_at",
    ])

    // a table of its own, named by its line and by the row it belongs to
    const title = await tasks.cell(FIRST, "title").textContent()
    await expect(project.grid).toHaveRole("table")
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

    // the tasks of a project, 19 columns wide, under a row of /tasks
    const project = await tasks.openLine(FIRST, "project")
    const [key] = await project.rowKeys()
    await project.openLine(key, "tasks")

    expect(await widths()).toEqual(before)
  })

  test("a table that never nests has no expanders: the people under a task", async ({ tasks }) => {
    const reporter = await tasks.openLine(FIRST, "reporter")

    await expect(reporter.rows).toHaveCount(1)
    await expect(reporter.expanders).toHaveCount(0)
    expect(await reporter.columns()).toEqual(["name", "email", "role", "assigned_hours"])
    await expect(reporter.grid).toHaveAttribute("aria-colcount", "4")
  })
})

test.describe("with the keyboard", () => {
  test("Tab goes along a row: its box, its expander, its editable cells", async ({ tasks }) => {
    await tasks.box(FIRST).focus()
    expect(await tasks.walk(2)).toEqual([`task-row-${FIRST}-e>button`, `task-row-${FIRST}-c-title`])
    expect(await tasks.walk(2, true)).toEqual([`task-row-${FIRST}-e>button`, `task-row-${FIRST}-s>input`])
    await expect(tasks.expander(FIRST)).toHaveAttribute("aria-expanded", "false")
  })

  test("Enter and Space on the expander open and close the row, focus stays on it, and Tab goes on to its first line", async ({
    tasks,
    pushed,
  }) => {
    await tasks.expander(FIRST).focus()
    await pushed.clear()
    await tasks.press("Enter")
    await expect(tasks.expander(FIRST)).toHaveAttribute("aria-expanded", "true")
    await expect(tasks.lines(FIRST)).toHaveCount(7)
    await expect(tasks.expander(FIRST), "focus stays on the expander").toBeFocused()
    expect(await pushed.count("expand")).toBe(1)
    expect(await pushed.all()).toHaveLength(1)

    await tasks.press(" ")
    await expect(tasks.expander(FIRST)).toHaveAttribute("aria-expanded", "false")
    await expect(tasks.lines(FIRST)).toHaveCount(0)
    await expect(tasks.expander(FIRST)).toBeFocused()
    await tasks.press(" ")
    await expect(tasks.lines(FIRST)).toHaveCount(7)

    // the lines stand under the row: after the row's own stops, its actions last
    await tasks.actions(FIRST).last().focus()
    expect(await tasks.walk(7)).toEqual(
      ["comments", "first_comment", "latest_comment", "labels", "project", "assignee", "reporter"].map(
        (name) => `task-row-${FIRST}-l-${name}-b`,
      ),
    )
    // and after the last line, the next row
    expect(await tasks.walk(1)).toEqual([`task-row-${SECOND}-s>input`])
  })

  test("Enter and Space on a line's button open and close its table, focus stays on it, and Tab goes into the table and out to the next line", async ({
    tasks,
    pushed,
  }) => {
    await tasks.expand(FIRST)
    const line = tasks.line(FIRST, "project")
    const project = tasks.nested(FIRST, "project")
    await line.focus()
    await pushed.clear()
    await tasks.press("Enter")
    await project.loaded()
    await expect(line).toHaveAttribute("aria-expanded", "true")
    await expect(line, "focus stays on the line").toBeFocused()
    expect(await pushed.count("toggle")).toBe(1)
    expect(await pushed.all()).toHaveLength(1)

    // into it: its heading line, which stands on the line, its "Skip table", its header and its row
    const [key] = await project.rowKeys()
    const stops = await tasks.walk(6)
    expect(stops).toContain(`${project.id}-skip`)
    expect(stops.at(-1)!.startsWith(project.id)).toBe(true)

    // out of it: after its last stop, the link to its full view, the next line
    await project.fullView.focus()
    expect(await tasks.walk(1)).toEqual([`task-row-${FIRST}-l-assignee-b`])
    expect(await tasks.walk(1, true)).toEqual([`${project.id}-full-view`])
    // its cells are in it, not around it: the first one that is a stop is its record's
    expect(await project.tabStops()).toContain(`${project.id}-row-${key}-c-name`)

    await line.focus()
    await tasks.press(" ")
    await expect(line).toHaveAttribute("aria-expanded", "false")
    await expect(project.root).toHaveCount(0)
    await expect(line).toBeFocused()
    await tasks.press("Enter")
    await expect(line).toHaveAttribute("aria-expanded", "true")
    await tasks.press("Enter")
    await expect(line).toHaveAttribute("aria-expanded", "false")
    await expect(line).toBeFocused()
  })

  test("a table where no column filters has no filter row", async ({ page, tasks }) => {
    // "Reported by": no column filters
    const reporter = await tasks.openLine(FIRST, "reporter")
    await expect(page.locator(`[id='${reporter.id}-filter-row']`)).toHaveCount(0)
    // "Comments": its ID does not filter, its Body does
    const comments = await tasks.openLine(FIRST, "comments")
    await expect(comments.filterCell("id").locator("input, select, button")).toHaveCount(0)
    await expect(comments.filterValue("body")).toBeVisible()
  })

  test("Shift+Tab from a nested table's first stop goes back to its line, and the inputs of its argument line stand on that line", async ({
    page,
    tasks,
  }) => {
    const project = await tasks.openLine(FIRST, "project")
    const [key] = await project.rowKeys()
    const nestedTasks = await project.openLine(key, "tasks")

    // its argument line is on its line, after the line's button; its "Skip table" after it
    await nestedTasks.skip.focus()
    await page.keyboard.press("Shift+Tab")
    expect(await nestedTasks.hasFocus()).toBe(false)
    const back = await tasks.walk(4, true)
    expect(back).toContain(`${nestedTasks.id}-arg-search`)
    expect(back).toContain(`${nestedTasks.id}-arg-due_within-days`)
    expect(back).toContain(`${project.id}-row-${key}-l-tasks-b`)

    // and forwards from its last input, into the table
    await nestedTasks.argument("due_within-days").focus()
    const on = await tasks.walk(3)
    expect(on).toContain(`${nestedTasks.id}-skip`)
  })

  test("a character does nothing on an expander and a line's button, and Tab about sends nothing", async ({
    page,
    tasks,
    pushed,
  }) => {
    await tasks.openLine(FIRST, "project")
    await pushed.clear()

    for (const button of [tasks.expander(FIRST), tasks.line(FIRST, "project")]) {
      await button.focus()
      await page.keyboard.press("x")
      await expect(tasks.openEditors).toHaveCount(0)
    }
    await tasks.expander(FIRST).focus()
    await tasks.walk(12)
    await tasks.walk(12, true)

    expect(await pushed.all()).toEqual([])
    expect(await tasks.selectedKeys()).toEqual([])
    await expect(tasks.expander(FIRST)).toHaveAttribute("aria-expanded", "true")
    await expect(tasks.line(FIRST, "project")).toHaveAttribute("aria-expanded", "true")
  })
})

test.describe("three levels down", () => {
  test("nested tables expand again at every depth, down to the limit, and Tab goes into the deepest and out", async ({
    tasks,
  }) => {
    // tasks -> project -> tasks -> comments
    const project = await tasks.openLine(FIRST, "project")
    const [projectKey] = await project.rowKeys()

    const projectTasks = await project.openLine(projectKey, "tasks")
    await expect(projectTasks.rows).toHaveCount(25)
    await expect(projectTasks.expanders).toHaveCount(25)
    const [taskKey] = await projectTasks.rowKeys()

    const comments = await projectTasks.openLine(taskKey, "comments")
    // at depth 3 of 3: the same table as one level up, without expanders:
    // the boxes that select a row, its five columns and the one of its actions
    await expect(comments.expanders).toHaveCount(0)
    await expect(comments.headerCells).toHaveCount(7)
    await expect(comments.grid).toHaveAttribute("aria-colcount", "7")

    // in from its line, by Tab
    await projectTasks.line(taskKey, "comments").focus()
    expect(await tasks.walk(5)).toContain(`${comments.id}-skip`)
    // its "Skip table" skips it alone: the next stop is the next line of its row
    await comments.skip.focus()
    await tasks.press("Enter")
    await expect(comments.skipTarget).toBeFocused()
    expect(await tasks.walk(1)).toEqual([`${projectTasks.id}-row-${taskKey}-l-first_comment-b`])
  })
})

test.describe("focus", () => {
  test("stays on a nested table's sort button through its own sort; when its rows change, on the same cell if it is back, else on the cell at the same place", async ({
    tasks,
  }) => {
    const project = await tasks.openLine(FIRST, "project")
    const [projectKey] = await project.rowKeys()
    const nested = await project.openLine(projectKey, "tasks")

    await nested.sortButton("title").focus()
    await nested.reads(() => tasks.press("Enter"))
    await expect(nested.header("title")).toHaveAttribute("aria-sort", "ascending")
    await expect(nested.sortButton("title")).toBeFocused()
    // the table around it has not moved
    await expect(tasks.header("title")).toHaveAttribute("aria-sort", "none")
    await expect(tasks.line(FIRST, "project")).toHaveAttribute("aria-expanded", "true")
    expect(tasks.page.url()).not.toContain("sort")

    // its rows are read again under the focus (sent without a click,
    // which would move the focus): a sort brings the row back, and focus
    // is on the same cell, wherever it stands now
    const sorted = await nested.rowKeys()
    await nested.cell(sorted[2], "priority").focus()
    await nested.reads(() => nested.forge("sort", { column: "progress" }))
    const resorted = await nested.rowKeys()
    expect(resorted).not.toEqual(sorted)
    expect(resorted).toContain(sorted[2])
    await expect(nested.cell(sorted[2], "priority")).toBeFocused()

    // another page brings other rows: the same cell of the row at the place the focused row stood
    const place = resorted.indexOf(sorted[2])
    await nested.reads(() => nested.forge("page", { to: "2" }))
    const other = await nested.rowKeys()
    expect(other).not.toContain(sorted[2])
    await expect(nested.cell(other[place], "priority")).toBeFocused()
  })

  test("goes through the pages of a nested table, Tab stops after its rows, and stays on the control that was used", async ({
    page,
  }) => {
    const projects = new Table(page, "project", "/projects")
    await projects.open()
    const nested = await projects.openLine(MOBILE_APP, "tasks")
    await expect(nested.range).toHaveText("1–25 of 57")

    // the pages are a group in a row at the end of its table
    await expect(nested.pagination).toHaveRole("group")
    await expect(nested.pagination).toHaveAccessibleName("Pagination: Tasks")
    // Previous is disabled on the first page: the first page's button is the first stop of the pages
    await nested.pageButton(1).focus()
    expect(await projects.walk(1)).toEqual([`${nested.id}-page-2`])

    await nested.reads(() => projects.press("Enter"))
    await expect(nested.range).toHaveText("26–50 of 57")
    await expect(nested.pageButton(2)).toBeFocused()
    expect(page.url()).not.toContain("page")
    await expect(projects.range, "the projects around it are on their page").toHaveText("1–6 of 6")

    await nested.next.focus()
    await nested.reads(() => projects.press("Enter"))
    await expect(nested.range).toHaveText("51–57 of 57")
    // Next is disabled on the last page: focus goes to the page that is shown
    await expect(nested.pageButton(3)).toBeFocused()
    // after the pages: "Rows per page", then its link to the full view
    await expect(nested.next).toBeDisabled()
    expect(await projects.walk(2)).toEqual([`${nested.id}-page-size`, `${nested.id}-full-view`])
  })

  test("comes back to the line when its nested table is closed while focus is in it, and to the expander when the row is", async ({
    tasks,
  }) => {
    const project = await tasks.openLine(FIRST, "project")
    const [key] = await project.rowKeys()

    // focus is in the nested table; the line closes without a click on it
    await project.cell(key, "name").focus()
    await tasks.forge("toggle", { row: FIRST, relationship: "project" })
    await expect(project.root).toHaveCount(0)
    await expect(tasks.line(FIRST, "project")).toBeFocused()

    await tasks.line(FIRST, "project").click()
    await project.loaded()
    await project.cell(key, "name").focus()
    await tasks.forge("expand", { row: FIRST })
    await expect(tasks.lines(FIRST)).toHaveCount(0)
    await expect(tasks.expander(FIRST)).toBeFocused()
  })

  test("stays in the table when a new read of the table around it takes an open nested table away", async ({
    page,
    tasks,
  }) => {
    const project = await tasks.openLine(FIRST, "project")
    await expect(project.rows).toHaveCount(1)

    // the back button after a sort reads the tasks again, from outside the table
    await tasks.sortBy("title")
    await expect(tasks.lines(FIRST)).toHaveCount(0)

    const opened = await tasks.rowKey(1)
    const again = await tasks.openLine(opened, "project")
    const [nestedKey] = await again.rowKeys()
    await again.cell(nestedKey, "name").focus()
    await tasks.reads(() => page.goBack())

    await expect(tasks.expander(FIRST)).toHaveAttribute("aria-expanded", "false")
    expect(await tasks.hasFocus()).toBe(true)
  })
})

test.describe("filtering in a nested table", () => {
  test("its filter row works as on a page of its own; Escape gives up what was typed, and focus stays", async ({
    page,
  }) => {
    const projects = new Table(page, "project", "/projects")
    await projects.open()
    const nested = await projects.openLine(MOBILE_APP, "tasks")

    await nested.filterValue("title").focus()
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

    await page.keyboard.type("es")
    await projects.press("Escape")
    await expect(nested.filterValue("title")).toHaveValue("Fix")
    await expect(nested.filterValue("title")).toBeFocused()

    // "Clear filters" of a nested table is a Tab stop of its own
    await nested.clearFilters.focus()
    await nested.reads(() => projects.press("Enter"))
    await expect(nested.range).toHaveText("1–25 of 57")
    expect(await nested.hasFocus()).toBe(true)
  })
})

test.describe("editing in a nested table", () => {
  test("a cell is edited and saved as on a page of its own, and the table around it is not read again", async ({
    page,
    pushed,
  }) => {
    const projects = new Table(page, "project", "/projects")
    await projects.open()
    const nested = await projects.openLine(MOBILE_APP, "tasks")
    const [key] = await nested.rowKeys()
    const title = nested.cell(key, "title")

    await title.focus()
    await projects.press("Enter")
    await expect(nested.editor(title)).toBeFocused()
    await projects.retype("Edited under its project")
    await pushed.clear()
    await nested.saves(title, () => projects.press("Enter"))

    await expect(title).toHaveText("Edited under its project")
    await expect(title).toBeFocused()
    expect(await pushed.count("save")).toBe(1)
    expect(await pushed.all()).toHaveLength(1)
    await expect(projects.line(MOBILE_APP, "tasks")).toHaveAttribute("aria-expanded", "true")

    // Escape gives the edit up; focus stays on the cell
    await projects.press("Enter")
    await projects.retype("Given up")
    await projects.press("Escape")
    await expect(title).toHaveText("Edited under its project")
    await expect(title).toBeFocused()

    // the record is saved: the page of the tasks shows it
    const tasks = new Table(page, "task", "/tasks")
    await tasks.open(`/tasks?task[f][title]=Edited under its project`)
    await expect(tasks.rows).toHaveCount(1)
  })

  test("the comments, the labels and the project under a task are edited as on their own pages", async ({
    page,
    tasks,
    pushed,
  }) => {
    for (const { relationship, column, value, path, id } of [
      { relationship: "comments", column: "body", value: "Edited under its task", path: "/comments", id: "comment" },
      { relationship: "labels", column: "colour", value: "#123456", path: "/labels", id: "label" },
      { relationship: "project", column: "name", value: "Renamed under its task", path: "/projects", id: "project" },
    ]) {
      await tasks.open()
      const nested = await tasks.openLine(FIRST, relationship)
      await expect(nested.editorTemplates, relationship).not.toHaveCount(0)
      const keys = await nested.rowKeys()
      const cell = nested.cell(keys[0], column)
      await expect(cell, relationship).toHaveAttribute("tabindex", "0")

      await cell.focus()
      await tasks.press("Enter")
      await expect(nested.editor(cell), relationship).toBeFocused()
      await tasks.retype(value)
      await pushed.clear()
      await nested.saves(cell, () => tasks.press("Enter"))

      await expect(cell, relationship).toHaveText(value)
      await expect(cell, relationship).toBeFocused()
      await expect(cell, relationship).not.toHaveAttribute("data-failed")
      // one save, of this table, and nothing is read again: the rows stay where they are
      expect(await pushed.count("save"), relationship).toBe(1)
      expect(await pushed.all(), relationship).toHaveLength(1)
      expect(await nested.rowKeys(), relationship).toEqual(keys)
      await expect(tasks.line(FIRST, relationship)).toHaveAttribute("aria-expanded", "true")

      // the record that was saved is that one: its own page shows it, and no other record has the value
      const own = new Table(page, id, path)
      await own.open(`${path}?${id}[f][${column}]=${encodeURIComponent(value)}`)
      expect(await own.rowKeys(), relationship).toEqual([keys[0]])
    }
  })

  test("the people under a task cannot be edited: their table names no update action", async ({ tasks, pushed }) => {
    const reporter = await tasks.openLine(FIRST, "reporter")
    await expect(reporter.editorTemplates).toHaveCount(0)
    // no cell of it is a Tab stop
    await expect(reporter.grid.locator(":is([role=cell],[role=rowheader])[tabindex]")).toHaveCount(0)

    const name = reporter.cell(await reporter.rowKey(1), "name")
    await pushed.clear()
    await name.dblclick()
    await expect(reporter.openEditors).toHaveCount(0)
    expect(await pushed.all()).toEqual([])
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
    await expect(title).toHaveAttribute("data-failed")
    await expect(nested.failure(title)).toHaveText("length must be greater than or equal to 3")
    await expect(nested.status).toHaveText("Title was not saved: length must be greater than or equal to 3")
    await expect(projects.status).toHaveText("")

    // Escape on the failed cell restores it; focus stays on it
    await projects.press("Escape")
    await expect(title).not.toHaveAttribute("data-failed")
    await expect(title).toBeFocused()
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

    await expect(tasks.grid.getByRole("table")).toHaveCount(50)
    await expect(tasks.rows).toHaveCount(25)

    // the keyboard works among them: from a row's last action to its first line
    await tasks.actions(keys[3]).last().focus()
    expect(await tasks.walk(1)).toEqual([`task-row-${keys[3]}-l-comments-b`])
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
