import { expectNoAxeViolations } from "./support/a11y"
import { ACTOR_KEYS } from "./support/actors"
import { SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { switchLocale } from "./support/locale"
import { Table } from "./support/table"

// Spec section 8: axe-core must report no violations, on every table and in
// every state a table can be in. Each test brings the page into one state
// and runs every rule axe has on the whole document.
//
// This file: every mounted table, the dashboard with its two tables, German,
// each actor, and the states of reading. The others are a11y-editing,
// a11y-nesting and a11y-actions: four files, so that they run side by side.

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
