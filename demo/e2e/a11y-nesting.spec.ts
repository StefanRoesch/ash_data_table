import { expectNoAxeViolations } from "./support/a11y"
import { SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { switchLocale } from "./support/locale"
import { Table } from "./support/table"

// axe-core on nested tables (see a11y-tables.spec.ts).

// Nested tables: a table in a cell of a table, at every depth, and what is
// around it (the lines, the pages in the last row, an editor, the dialog).
test.describe("nested tables", () => {
  const FIRST = SEED.task.first

  test("a row expanded to its lines", async ({ page, tasks }) => {
    await tasks.open()
    await tasks.expand(FIRST)
    await expect(tasks.lines(FIRST)).toHaveCount(7)
    await expectNoAxeViolations(page)

    // with focus on a line's button
    await tasks.line(FIRST, "comments").focus()
    await expectNoAxeViolations(page)
  })

  test("nested tables open one level down: several rows, one row, none, and one with pages", async ({
    page,
    tasks,
  }) => {
    // Five runs of axe over the two largest pages of the suite, three of
    // them with a table of 25 tasks nested in the page: about seven seconds
    // each, which is all the time a test has.
    test.slow()
    await tasks.open()
    await tasks.openLine(FIRST, "comments")
    await tasks.openLine(FIRST, "project")
    await tasks.openLine(FIRST, "labels")
    await tasks.openLine(SEED.task.third, "comments")
    await expect(tasks.nested(SEED.task.third, "comments").empty).toHaveText("No records")
    await expectNoAxeViolations(page)

    const projects = new Table(page, "project", "/projects")
    await projects.open()
    const nested = await projects.openLine(SEED.project.mobileApp, "tasks")
    await expect(nested.pagination).toBeVisible()
    await expectNoAxeViolations(page)

    // inside it: focus on a cell, in its filter, and on its pages
    await nested.cell((await nested.rowKeys())[0], "title").focus()
    await expectNoAxeViolations(page)
    await nested.filterValue("title").focus()
    await page.keyboard.type("Fix")
    await nested.reads(() => page.keyboard.press("Enter"))
    await expectNoAxeViolations(page)
    await nested.pageButton(1).focus()
    await expectNoAxeViolations(page)
  })

  test("three levels down, where the rows have no expanders", async ({ page, tasks }) => {
    await tasks.open()
    const project = await tasks.openLine(FIRST, "project")
    const projectTasks = await project.openLine((await project.rowKeys())[0], "tasks")
    const comments = await projectTasks.openLine((await projectTasks.rowKeys())[0], "comments")
    await expect(comments.expanders).toHaveCount(0)
    await expectNoAxeViolations(page)
  })

  test("an editor open in a nested table, its dialog, and a cell whose save failed", async ({
    page,
  }) => {
    const projects = new Table(page, "project", "/projects")
    await projects.open()
    const nested = await projects.openLine(SEED.project.mobileApp, "tasks")
    const [key] = await nested.rowKeys()

    const title = nested.cell(key, "title")
    await title.focus()
    await projects.press("Enter")
    await expect(nested.editor(title)).toBeFocused()
    await expectNoAxeViolations(page)

    await projects.retype("ab")
    await nested.saves(title, () => projects.press("Enter"))
    await expect(nested.failure(title)).toBeVisible()
    await expectNoAxeViolations(page)
    await projects.press("Escape")

    const status = nested.cell(key, "status")
    await status.dblclick()
    await nested.editor(status).selectOption({ label: "In review" })
    await expect(nested.dialog).toBeVisible()
    await expectNoAxeViolations(page)
  })

  for (const actor of ["member", "viewer", "outsider"] as const) {
    test.describe(() => {
      test.use({ actor })

      test(`as the ${actor}: a task's lines and tables, and a project's tasks`, async ({ page, tasks }) => {
        await tasks.open()
        const key = await tasks.rowKey(1)
        await tasks.openLine(key, "comments")
        await tasks.openLine(key, "project")
        await expectNoAxeViolations(page)

        const projects = new Table(page, "project", "/projects")
        await projects.open()
        await projects.openLine(await projects.rowKey(1), "tasks")
        await expectNoAxeViolations(page)
      })
    })
  }

  test("in German", async ({ page, tasks }) => {
    await tasks.open()
    await switchLocale(page, "de")
    await tasks.ready()
    await tasks.expander(FIRST).click()
    await expect(tasks.lines(FIRST).first()).toContainText("Kommentare")
    await tasks.line(FIRST, "comments").click()
    await tasks.nested(FIRST, "comments").loaded()
    await expectNoAxeViolations(page)
  })

  test("the dashboard, a nested table open in each of its tables", async ({ page }) => {
    const projects = new Table(page, "dashboard-projects", "/dashboard")
    const tasks = new Table(page, "dashboard-tasks", "/dashboard")
    await projects.open()
    await tasks.ready()
    await projects.openLine(await projects.rowKey(1), "tasks")
    await tasks.openLine(await tasks.rowKey(1), "comments")
    await expectNoAxeViolations(page)
  })
})
