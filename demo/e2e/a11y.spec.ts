import { expectNoAxeViolations } from "./support/a11y"
import { ACTOR_KEYS } from "./support/actors"
import { deleteTask, SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { switchLocale } from "./support/locale"
import { Table } from "./support/table"

// Spec section 8: axe-core must report no violations, on every table and in
// every state a table can be in. Each test brings the page into one state
// and runs every rule axe has on the whole document.

const SECOND = SEED.task.second

test.describe("every mounted table, as the admin", () => {
  for (const [path, id] of [
    ["/tasks", "task"],
    ["/projects", "project"],
    ["/comments", "comment"],
    ["/labels", "label"],
    ["/task_labels", "task_label"],
    ["/specimens", "specimen"],
  ]) {
    test(path, async ({ page }) => {
      await new Table(page, id, path).open()
      await expectNoAxeViolations(page)
    })
  }

  test("/bare/labels: the table itself", async ({ page }) => {
    const labels = new Table(page, "label", "/bare/labels")
    await labels.open()
    await expectNoAxeViolations(page, "#label-page")
  })

  // A table mounted with `layout: false` brings no landmark of its own: the
  // main landmark around it is the demo's root layout's.
  test("/bare/labels: the whole page", async ({ page }) => {
    await new Table(page, "label", "/bare/labels").open()
    await expectNoAxeViolations(page)
  })

  test("the front page, where the tables are linked from", async ({ page }) => {
    await page.goto("/")
    await expect(page.getByRole("heading", { level: 1 })).toBeVisible()
    await expectNoAxeViolations(page)
  })
})

test.describe("two tables in one page: /dashboard", () => {
  let projects: Table
  let tasks: Table

  test.beforeEach(async ({ page }) => {
    projects = new Table(page, "dashboard-projects", "/dashboard")
    tasks = new Table(page, "dashboard-tasks", "/dashboard")
    await projects.open()
    await tasks.ready()
  })

  test("as it opens: every landmark has a name of its own", async ({ page }) => {
    await expectNoAxeViolations(page)

    // what axe's `landmark-unique` is about, said outright
    const names = await page
      .getByRole("navigation")
      .evaluateAll((landmarks) => landmarks.map((landmark) => landmark.getAttribute("aria-label")))
    expect(names).toEqual(["Main", "Pagination: Projects", "Pagination: Tasks"])
    await expect(page.getByRole("region")).toHaveCount(2)
    await expect(page.getByRole("region", { name: "Projects" })).toHaveId("dashboard-projects-section")
    await expect(page.getByRole("region", { name: "Tasks" })).toHaveId("dashboard-tasks-section")
  })

  test("both sorted and filtered, the tasks on a later page", async ({ page }) => {
    await projects.reads(() => projects.header("name").click())
    await projects.filterValue("name").fill("i")
    await projects.reads(() => projects.filterValue("name").press("Enter"))
    await tasks.reads(() => tasks.header("title").click())
    await tasks.reads(() => tasks.filterValue("billable?").selectOption("yes"))
    await tasks.reads(() => tasks.next.click())
    await expect(tasks.next).toBeFocused()
    await expect(projects.clearFilters).toBeVisible()
    await expect(tasks.clearFilters).toBeVisible()
    await expectNoAxeViolations(page)
  })

  test("an editor open in one of them, and a cell whose save failed", async ({ page }) => {
    const title = tasks.cell(SECOND, "title")
    await title.focus()
    await tasks.press("Enter")
    await expect(tasks.editor(title)).toBeFocused()
    await expectNoAxeViolations(page)

    await tasks.retype("ab")
    await tasks.saves(title, () => tasks.press("Enter"))
    await expect(tasks.failure(title)).toBeVisible()
    await expectNoAxeViolations(page)
  })

  test("the confirm dialog of the one table that has it", async ({ page }) => {
    const status = tasks.cell(SECOND, "status")
    await status.dblclick()
    await tasks.editor(status).selectOption({ label: "In review" })
    await expect(tasks.dialog).toBeVisible()
    await expectNoAxeViolations(page)
  })

})

test.describe("/dashboard as nobody, for whom one of its tables is not there", () => {
  test.use({ actor: "nobody" })

  test("the page with the table that is left", async ({ page }) => {
    const tasks = new Table(page, "dashboard-tasks", "/dashboard")
    await tasks.open()
    await expect(page.getByRole("grid")).toHaveCount(1)
    await expect(tasks.empty).toHaveText("No records")
    await expectNoAxeViolations(page)
  })
})

test.describe("in German", () => {
  test("/tasks, with a filter active and a cell whose save failed", async ({ page, tasks }) => {
    await tasks.open()
    await switchLocale(page, "de")
    await tasks.ready()
    await expectNoAxeViolations(page)

    await tasks.reads(() => tasks.filterValue("status").selectOption("todo"))
    const title = tasks.cell(SECOND, "title")
    await title.focus()
    await tasks.press("Enter")
    await tasks.retype("ab")
    await tasks.saves(title, () => tasks.press("Enter"))
    await expect(tasks.failure(title)).toHaveText("muss mindestens 3 Zeichen lang sein")
    await expectNoAxeViolations(page)
  })

  test("/dashboard", async ({ page }) => {
    const projects = new Table(page, "dashboard-projects", "/dashboard")
    await projects.open()
    await switchLocale(page, "de")
    await projects.ready()
    await new Table(page, "dashboard-tasks", "/dashboard").ready()

    await expectNoAxeViolations(page)
    const names = await page
      .getByRole("navigation")
      .evaluateAll((landmarks) => landmarks.map((landmark) => landmark.getAttribute("aria-label")))
    expect(names).toEqual(["Main", "Seiten: Projects", "Seiten: Aufgaben"])
  })
})

test.describe("/tasks as each actor", () => {
  for (const actor of ACTOR_KEYS) {
    test.describe(() => {
      test.use({ actor })

      test(`as the ${actor}`, async ({ page, tasks }) => {
        await tasks.open()
        await expectNoAxeViolations(page)
      })
    })
  }
})

test.describe("reading states", () => {
  test("sorted, on a later page", async ({ page, tasks }) => {
    await tasks.open("/tasks?task[sort]=-title&task[page]=2")
    await expect(tasks.header("title")).toHaveAttribute("aria-sort", "descending")
    await expectNoAxeViolations(page)
  })

  test("a filter active, with focus in its input", async ({ page, tasks }) => {
    await tasks.open()
    await tasks.filterCell("title").focus()
    await tasks.press("Enter")
    await page.keyboard.type("sess")
    await tasks.reads(() => tasks.press("Enter"))
    await expect(tasks.clearFilters).toBeVisible()
    await expect(tasks.status).toHaveText("18 results")
    await expectNoAxeViolations(page)
  })

  test("several filters active, one of them without a value", async ({ page, tasks }) => {
    await tasks.open(
      "/tasks?task[f][billable?]=yes&task[f][progress][at_least]=50&task[f][due_on][is_empty]=&task[f][status]=in_progress",
    )
    await expect(tasks.filterValue("due_on")).toHaveCount(0)
    await expectNoAxeViolations(page)
  })

  test("a filter value that was rejected", async ({ page, tasks }) => {
    await tasks.open()
    await tasks.filterValue("progress").focus()
    await page.keyboard.type("1.5")
    await tasks.press("Enter")
    await expect(tasks.filterError("progress")).toHaveText("Not a valid value")
    await expectNoAxeViolations(page)
  })

  test("no records: a filter that finds nothing", async ({ page, tasks }) => {
    await tasks.open("/tasks?task[f][title]=no%20such%20task")
    await expect(tasks.empty).toHaveText("No records")
    await expectNoAxeViolations(page)
  })

  test("a read that failed", async ({ page }) => {
    const comments = new Table(page, "comment", "/comments")
    await comments.open("/comments?comment[after]=nonsense")
    await expect(comments.error).toHaveText("The records could not be loaded.")
    await expectNoAxeViolations(page)
  })
})

test.describe("editing states", () => {
  test.beforeEach(async ({ tasks }) => {
    await tasks.open()
  })

  test("a text editor open", async ({ page, tasks }) => {
    const title = tasks.cell(SECOND, "title")
    await title.focus()
    await tasks.press("Enter")
    await expect(tasks.editor(title)).toBeFocused()
    await expectNoAxeViolations(page)
  })

  test("a number, a date and a datetime editor open", async ({ page, tasks }) => {
    for (const column of ["estimate_hours", "due_on", "completed_at"]) {
      const cell = tasks.cell(SECOND, column)
      await cell.focus()
      await tasks.press("Enter")
      await expect(tasks.editor(cell)).toBeFocused()
      await expectNoAxeViolations(page)
      await tasks.press("Escape")
    }
  })

  test("a select editor open", async ({ page, tasks }) => {
    const priority = tasks.cell(SECOND, "priority")
    await priority.focus()
    await tasks.press("Enter")
    await expect(tasks.editor(priority)).toBeFocused()
    await expectNoAxeViolations(page)
  })

  test("the confirm dialog open", async ({ page, tasks }) => {
    const status = tasks.cell(SECOND, "status")
    await status.dblclick()
    await tasks.editor(status).selectOption({ label: "In review" })
    await expect(tasks.dialog).toBeVisible()
    await expectNoAxeViolations(page)
  })

  test.describe("a cell whose save failed", () => {
    test.beforeEach(async ({ page, tasks }) => {
      const title = tasks.cell(SECOND, "title")
      await title.focus()
      await tasks.press("Enter")
      await tasks.retype("ab")
      await tasks.saves(title, () => tasks.press("Enter"))
      await expect(title).toHaveAttribute("aria-invalid", "true")
      await page.mouse.move(5, 5)
    })

    test("with focus: its message showing", async ({ page, tasks }) => {
      await expect(tasks.failure(tasks.cell(SECOND, "title"))).toBeVisible()
      await expectNoAxeViolations(page)
    })

    test("without focus: marked only", async ({ page, tasks }) => {
      await tasks.press("ArrowDown")
      await expect(tasks.failure(tasks.cell(SECOND, "title"))).toBeHidden()
      await expectNoAxeViolations(page)
    })

    test("with its editor open again", async ({ page, tasks }) => {
      await tasks.press("Enter")
      await expect(tasks.editor(tasks.cell(SECOND, "title"))).toHaveValue("ab")
      await expectNoAxeViolations(page)
    })
  })

  test.describe("a cell the hook marked itself", () => {
    test.use({ writes: true })

    test("the record is gone", async ({ page, request, tasks }) => {
      const title = tasks.cell(SECOND, "title")
      await deleteTask(request, SECOND)
      await title.focus()
      await tasks.press("Enter")
      await tasks.retype("Gone already")
      await tasks.saves(title, () => tasks.press("Enter"))
      await expect(tasks.failure(title)).toBeVisible()
      await expectNoAxeViolations(page)
    })
  })
})

test.describe("what a person may not see or do", () => {
  test.describe("the member", () => {
    test.use({ actor: "member" })

    test("a cell that refused the save", async ({ page, tasks }) => {
      await tasks.open()
      const title = tasks.cell(SEED.task.first, "title")
      await title.focus()
      await tasks.press("Enter")
      await tasks.retype("Not mine to change")
      await tasks.saves(title, () => tasks.press("Enter"))
      await expect(tasks.failure(title)).toHaveText("You are not allowed to change this.")
      await expectNoAxeViolations(page)
    })

    test("focus on a cell whose field is hidden from them", async ({ page, tasks }) => {
      await tasks.open()
      await tasks.cell(SEED.task.first, "estimate_hours").focus()
      await expectNoAxeViolations(page)
    })
  })

  test.describe("nobody", () => {
    test.use({ actor: "nobody" })

    test("the table that says it is not allowed", async ({ page }) => {
      const comments = new Table(page, "comment", "/comments")
      await comments.open()
      await expect(comments.error).toHaveText("You are not allowed to see these records.")
      await expectNoAxeViolations(page)
    })

    test("a table without records", async ({ page }) => {
      const labels = new Table(page, "label", "/labels")
      await labels.open()
      await expect(labels.empty).toHaveText("No records")
      await expectNoAxeViolations(page)
    })
  })
})

// Nested tables: a grid in a cell of a grid, at every depth, and what is
// around it (the lines, the pages in the last row, an editor, the dialog).
test.describe("nested tables", () => {
  const FIRST = SEED.task.first

  test("a row expanded to its lines", async ({ page, tasks }) => {
    await tasks.open()
    await tasks.expand(FIRST)
    await expect(tasks.lines(FIRST)).toHaveCount(7)
    await expectNoAxeViolations(page)

    // with focus on a line
    await tasks.lineCell(FIRST, "comments").focus()
    await expectNoAxeViolations(page)
  })

  test("nested tables open one level down: several rows, one row, none, and one with pages", async ({
    page,
    tasks,
  }) => {
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
    await nested.pagerCell.focus()
    await projects.press("Enter")
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
