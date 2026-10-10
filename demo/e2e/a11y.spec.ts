import { expectNoAxeViolations } from "./support/a11y"
import { ACTOR_KEYS } from "./support/actors"
import { deleteTask, SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { switchLocale } from "./support/locale"
import { Table } from "./support/table"

// Spec section 8: axe-core must report no violations, on every table and in
// every state a table can be in. Each test brings the page into one state
// and runs every rule axe has on the whole document.

const FIRST_TASK = SEED.task.first
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

// The components of /tasks: "State" and "Priority" are badges, "Progress" a
// bar that is edited with a slider, "Estimate hours" the demo's own. The
// tables above are checked with them as they are; these are the states that
// only a component has.
test.describe("the components of a column", () => {
  test.use({ writes: true })

  for (const theme of ["light", "dark"] as const) {
    test.describe(`in the ${theme} theme`, () => {
      test.beforeEach(async ({ page, tasks }) => {
        await page.addInitScript((theme) => localStorage.setItem("phx:theme", theme), theme)
        await tasks.open()
        await expect(page.locator("html")).toHaveAttribute("data-theme", theme)
      })

      test("badges and bars at rest, the slider open, and the editor of the demo's own component", async ({
        page,
        tasks,
      }) => {
        await expect(tasks.cell(SECOND, "status").locator(".badge")).toHaveCount(1)
        await expect(tasks.cell(SECOND, "progress").locator("progress")).toHaveCount(1)
        await expectNoAxeViolations(page)

        const progress = tasks.cell(SECOND, "progress")
        await progress.focus()
        await tasks.press("Enter", "ArrowRight")
        await expect(tasks.editor(progress)).toBeFocused()
        await expect(tasks.editor(progress)).toHaveAccessibleName("Progress")
        await expectNoAxeViolations(page)
        await tasks.press("Escape")

        const estimate = tasks.cell(FIRST_TASK, "estimate_hours")
        await estimate.focus()
        await tasks.press("Enter")
        await expect(tasks.editor(estimate)).toBeFocused()
        await expectNoAxeViolations(page)
      })

      test("the action panel with the slider as a field, and the create panel with both editors", async ({
        page,
        tasks,
      }) => {
        await tasks.acts(SECOND, () => tasks.action(SECOND, "set_progress").click())
        await expect(tasks.field("progress")).toBeFocused()
        await expect(tasks.field("progress")).toHaveAttribute("type", "range")
        await expectNoAxeViolations(page)
        await tasks.press("Escape")
        await expect(tasks.panel).toHaveCount(0)

        await tasks.create.click()
        await expect(tasks.field("title")).toBeFocused()
        await expect(tasks.field("progress")).toHaveAttribute("type", "range")
        await expect(tasks.field("estimate_hours")).toHaveAttribute("type", "number")
        await expectNoAxeViolations(page)

        // with the errors of its required fields
        await tasks.panelSubmit.click()
        await expect(tasks.fieldError("title")).toBeVisible()
        await expectNoAxeViolations(page)
      })
    })
  }

  test("a cell whose save through the slider failed, with its message showing", async ({ page, tasks }) => {
    await tasks.open()
    const states = await tasks.columnTexts("status")
    const key = await tasks.rowKey(states.indexOf("Done") + 1)
    const progress = tasks.cell(key, "progress")

    await progress.focus()
    await tasks.press("Enter", "ArrowLeft")
    await tasks.saves(progress, () => tasks.press("Enter"))
    await expect(progress).toHaveAttribute("aria-invalid", "true")
    await page.mouse.move(5, 5)
    await expect(tasks.failure(progress)).toBeVisible()
    await expectNoAxeViolations(page)
  })

  test("in German, and nested under a project", async ({ page }) => {
    await page.goto("/")
    await switchLocale(page, "de")
    const projects = new Table(page, "project", "/projects")
    await projects.open()
    const nested = await projects.openLine(SEED.project.mobileApp, "tasks")
    const key = await nested.rowKey(1)
    const progress = nested.cell(key, "progress")
    await progress.focus()
    await nested.press("Enter")
    await expect(nested.editor(progress)).toHaveAccessibleName("Fortschritt")
    await expectNoAxeViolations(page)
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

// Row actions and row create: the actions column, the cell of an action
// that failed, and the action panel, a second dialog of the table, empty,
// with errors, and with the dialog that asks a question on top of it.
test.describe("row actions and the action panel", () => {
  const FIRST = SEED.task.first

  test.describe("the actions column", () => {
    test("with focus on its header, on a cell of it, and on a button in the cell", async ({ page, tasks }) => {
      await tasks.open()
      await tasks.actionsHeader.focus()
      await expectNoAxeViolations(page)

      await tasks.actionsCell(FIRST).focus()
      await expectNoAxeViolations(page)

      await tasks.press("Enter", "ArrowRight")
      await expect(tasks.action(FIRST, "reassign")).toBeFocused()
      await expectNoAxeViolations(page)
    })

    test("the dialog that asks before a record is deleted", async ({ page, tasks }) => {
      await tasks.open()
      await tasks.action(FIRST, "destroy").click()
      await expect(tasks.question).toBeVisible()
      await expect(tasks.question.getByRole("button", { name: "Confirm" })).toHaveClass(/\bbtn-error\b/)
      await expectNoAxeViolations(page)
    })

    for (const [path, id] of [
      ["/projects", "project"],
      ["/comments", "comment"],
      ["/labels", "label"],
      ["/task_labels", "task_label"],
    ]) {
      test(`${path}: focus on a button of its first row`, async ({ page }) => {
        const table = new Table(page, id, path)
        await table.open()
        await table.actionsCell(await table.rowKey(1)).focus()
        await table.press("Enter")
        expect(await table.focused()).toMatch(/-a-[a-z_]+$/)
        await expectNoAxeViolations(page)
      })
    }

    test.describe("the member", () => {
      test.use({ actor: "member" })

      test.beforeEach(async ({ page, tasks }) => {
        await tasks.open()
        await tasks.acts(FIRST, () => tasks.action(FIRST, "archive").click())
        await expect(tasks.actionsCell(FIRST)).toHaveAttribute("aria-invalid", "true")
        await page.mouse.move(5, 5)
      })

      test("a cell whose action was refused, with focus: its message showing", async ({ page, tasks }) => {
        await expect(tasks.failure(tasks.actionsCell(FIRST))).toBeVisible()
        await expectNoAxeViolations(page)

        // and with focus on the cell itself
        await tasks.press("Escape")
        await expect(tasks.actionsCell(FIRST)).toBeFocused()
        await expect(tasks.failure(tasks.actionsCell(FIRST))).toBeVisible()
        await expectNoAxeViolations(page)
      })

      test("a cell whose action was refused, without focus: marked only", async ({ page, tasks }) => {
        await tasks.press("Escape", "ArrowDown")
        await expect(tasks.failure(tasks.actionsCell(FIRST))).toBeHidden()
        await expectNoAxeViolations(page)
      })
    })

    test.describe("a cell the hook marked itself", () => {
      test.use({ writes: true })

      test("the record is gone", async ({ page, request, tasks }) => {
        await tasks.open()
        await deleteTask(request, SECOND)
        await tasks.acts(SECOND, () => tasks.action(SECOND, "archive").click())
        await expect(tasks.failure(tasks.actionsCell(SECOND))).toBeVisible()
        await expectNoAxeViolations(page)
      })
    })
  })

  test.describe("the panel of a row action", () => {
    test.beforeEach(async ({ tasks }) => {
      await tasks.open()
      await tasks.acts(FIRST, () => tasks.action(FIRST, "reassign").click())
      await expect(tasks.fieldChoose("assignee_id")).toBeFocused()
    })

    test("as it opens", async ({ page, tasks }) => {
      await expect(tasks.panel).toHaveAccessibleName("Reassign: Rename the onboarding email")
      await expectNoAxeViolations(page)
    })

    test("with an error at a field that was used", async ({ page, tasks }) => {
      await tasks.field("reason").fill("ab")
      await expect(tasks.fieldError("reason")).toBeVisible()
      await expectNoAxeViolations(page)
    })

    test("with the errors of every field, after Run", async ({ page, tasks }) => {
      await tasks.panelSubmit.click()
      await expect(tasks.fieldError("reason")).toBeVisible()
      await expectNoAxeViolations(page)
    })

    test("with the dialog that asks a question on top of it", async ({ page, tasks }) => {
      await tasks.field("reason").fill("Somebody else should")
      await tasks.panelSettled()
      // as the server renders it for an action that has a question (actions.spec.ts)
      await tasks.panel.evaluate((panel) => panel.setAttribute("data-question", "Reassign this task?"))
      await tasks.panelSubmit.click()
      await expect(tasks.question).toBeVisible()
      await expect(tasks.panel).toBeVisible()
      await expectNoAxeViolations(page)
    })
  })

  test("the panel of an action whose input is a number, and of one whose input is a choice", async ({
    page,
    tasks,
  }) => {
    await tasks.open()
    await tasks.acts(FIRST, () => tasks.action(FIRST, "set_progress").click())
    await expect(tasks.field("progress")).toBeFocused()
    await expectNoAxeViolations(page)

    const projects = new Table(page, "project", "/projects")
    await projects.open()
    const key = await projects.rowKey(1)
    await projects.acts(key, () => projects.action(key, "set_status").click())
    await expect(projects.field("status")).toBeFocused()
    await expectNoAxeViolations(page)
  })

  test.describe("the member", () => {
    test.use({ actor: "member" })

    test("a panel whose action was refused: the alert above its fields", async ({ page, tasks }) => {
      await tasks.open()
      await tasks.acts(FIRST, () => tasks.action(FIRST, "reassign").click())
      await tasks.field("reason").fill("I will take it")
      await tasks.panelSubmit.click()
      await expect(tasks.panelErrors).toHaveText("You are not allowed to do this.")
      await expectNoAxeViolations(page)
    })
  })

  test.describe("the create panel", () => {
    for (const actor of ["admin", "member", "outsider"] as const) {
      test.describe(() => {
        test.use({ actor })

        test(`as the ${actor}: the create button, the panel as it opens, and with errors`, async ({
          page,
          tasks,
        }) => {
          await tasks.open()
          await tasks.create.focus()
          await expectNoAxeViolations(page)

          await page.keyboard.press("Enter")
          await expect(tasks.field("title")).toBeFocused()
          await expectNoAxeViolations(page)

          await tasks.field("title").fill("ab")
          await tasks.field("billable?").check()
          await tasks.panelSubmit.click()
          await expect(tasks.fieldError("title")).toBeVisible()
          await expect(tasks.fieldError("project_id")).toBeVisible()
          await expectNoAxeViolations(page)
        })
      })
    }

    for (const [path, id] of [
      ["/projects", "project"],
      ["/comments", "comment"],
      ["/labels", "label"],
      ["/task_labels", "task_label"],
    ]) {
      test(`${path}: its create panel`, async ({ page }) => {
        const table = new Table(page, id, path)
        await table.open()
        await table.create.click()
        await expect(table.panel).toBeVisible()
        await expectNoAxeViolations(page)
      })
    }

    test("on a narrow window, where the panel is as wide as the window", async ({ page, tasks }) => {
      await page.setViewportSize({ width: 390, height: 700 })
      await tasks.open()
      await tasks.create.click()
      await expect(tasks.field("title")).toBeFocused()
      await expectNoAxeViolations(page)
    })
  })

  test.describe("a nested table", () => {
    for (const actor of ["admin", "member"] as const) {
      test.describe(() => {
        test.use({ actor })

        test(`as the ${actor}: the create button on its line, with focus, and its panel`, async ({
          page,
          tasks,
        }) => {
          await tasks.open()
          const comments = await tasks.openLine(FIRST, "comments")
          await expect(tasks.lineCreate(FIRST, "comments")).toBeVisible()
          await expectNoAxeViolations(page)

          await tasks.lineCell(FIRST, "comments").focus()
          await tasks.press("F2", "ArrowRight")
          await expect(tasks.lineCreate(FIRST, "comments")).toBeFocused()
          await expectNoAxeViolations(page)

          await tasks.press("Enter")
          await expect(comments.field("body")).toBeFocused()
          await expectNoAxeViolations(page)

          await comments.panelSubmit.click()
          await expect(comments.fieldError("body")).toBeVisible()
          await expectNoAxeViolations(page)
        })
      })
    }

    test("a row action of a nested table: its buttons, its panel and its question", async ({ page }) => {
      const projects = new Table(page, "project", "/projects")
      await projects.open()
      const nested = await projects.openLine(SEED.project.mobileApp, "tasks")
      const key = await nested.rowKey(1)
      await expect(projects.lineCreate(SEED.project.mobileApp, "tasks")).toBeVisible()

      await nested.actionsCell(key).focus()
      await projects.press("Enter")
      await expect(nested.action(key, "archive")).toBeFocused()
      await expectNoAxeViolations(page)

      await nested.acts(key, () => nested.action(key, "reassign").click())
      await expect(nested.panel).toBeVisible()
      await expectNoAxeViolations(page)
      await projects.press("Escape")
      await expect(nested.panel).toHaveCount(0)

      await nested.action(key, "destroy").click()
      await expect(nested.question).toBeVisible()
      await expectNoAxeViolations(page)
    })
  })

  test("the full view: the create button on the line that says what the table shows, and its panel", async ({
    page,
  }) => {
    const comments = new Table(page, "comment", "/comments")
    await comments.open(`/comments?comment[of][task][comments]=${FIRST}`)
    await expect(comments.create).toBeVisible()
    await expectNoAxeViolations(page)

    await comments.create.click()
    await expect(comments.field("body")).toBeFocused()
    await expectNoAxeViolations(page)
  })

  test("the dashboard: both tables name themselves, and a panel of each", async ({ page }) => {
    const projects = new Table(page, "dashboard-projects", "/dashboard")
    const tasks = new Table(page, "dashboard-tasks", "/dashboard")
    await projects.open()
    await tasks.ready()
    await expect(projects.create).toBeVisible()
    await expect(tasks.create).toBeVisible()

    await projects.create.click()
    await expect(projects.panel).toBeVisible()
    await expectNoAxeViolations(page)
    await projects.press("Escape")
    await expect(projects.panel).toHaveCount(0)

    await tasks.acts(FIRST, () => tasks.action(FIRST, "reassign").click())
    await expect(tasks.panel).toBeVisible()
    await expectNoAxeViolations(page)
  })

  test("in German: the actions, a refused panel and the create panel", async ({ page, tasks }) => {
    await tasks.open()
    await switchLocale(page, "de")
    await tasks.ready()
    await expect(tasks.actions(FIRST)).toHaveText(["Archivieren", "Neu zuweisen", "Fortschritt setzen", "Löschen", "Labels setzen"])

    await tasks.acts(FIRST, () => tasks.action(FIRST, "reassign").click())
    await expect(tasks.panelTitle).toHaveText("Neu zuweisen: Rename the onboarding email")
    await tasks.panelSubmit.click()
    await expect(tasks.fieldError("reason")).toBeVisible()
    await expectNoAxeViolations(page)
    await tasks.press("Escape")
    await expect(tasks.panel).toHaveCount(0)

    await tasks.create.click()
    await expect(tasks.panelTitle).toHaveText("Aufgabe anlegen")
    await expectNoAxeViolations(page)
  })

  // The demo's dark theme, which a person chooses with the toggle in the
  // header: the choice is kept in the browser.
  test.describe("in the dark theme", () => {
    test.use({ actor: "member" })

    test.beforeEach(async ({ page }) => {
      await page.addInitScript(() => localStorage.setItem("phx:theme", "dark"))
    })

    test("the actions column with a failed cell, the panel with errors, and the question on top of it", async ({
      page,
      tasks,
    }) => {
      await tasks.open()
      await expect(page.locator("html")).toHaveAttribute("data-theme", "dark")
      await tasks.acts(FIRST, () => tasks.action(FIRST, "archive").click())
      await page.mouse.move(5, 5)
      await expect(tasks.failure(tasks.actionsCell(FIRST))).toBeVisible()
      await expectNoAxeViolations(page)

      await tasks.acts(FIRST, () => tasks.action(FIRST, "reassign").click())
      await tasks.field("reason").fill("I will take it")
      await tasks.panelSubmit.click()
      await expect(tasks.panelErrors).toBeVisible()
      await expectNoAxeViolations(page)

      await tasks.panelSettled()
      await tasks.panel.evaluate((panel) => panel.setAttribute("data-question", "Reassign this task?"))
      await tasks.panelSubmit.click()
      await expect(tasks.question).toBeVisible()
      await expectNoAxeViolations(page)
    })

    test("a nested table with the create button on its line, and its panel", async ({ page, tasks }) => {
      await tasks.open()
      const comments = await tasks.openLine(FIRST, "comments")
      await expect(tasks.lineCreate(FIRST, "comments")).toBeVisible()
      await expectNoAxeViolations(page)

      await tasks.lineCreate(FIRST, "comments").click()
      await expect(comments.field("body")).toBeFocused()
      await expectNoAxeViolations(page)
    })
  })
})
