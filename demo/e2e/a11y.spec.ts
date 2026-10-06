import { expectNoAxeViolations } from "./support/a11y"
import { ACTOR_KEYS } from "./support/actors"
import { deleteTask, SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
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

  test("/bare/labels: the whole page", async ({ page }) => {
    test.fail(
      true,
      "FINDING (demo, or library): mounted with `layout: false`, the table's page has no main " +
        "landmark: AshTable.Live.Page renders its heading and the table straight into the " +
        "root layout. axe reports the best-practice rules `landmark-one-main` (html) and " +
        "`region` (h1, #label-grid), both of moderate impact. In the app layout (/labels) " +
        "the same table has no violation.",
    )
    await new Table(page, "label", "/bare/labels").open()
    await expectNoAxeViolations(page)
  })

  test("the front page, where the tables are linked from", async ({ page }) => {
    await page.goto("/")
    await expect(page.getByRole("heading", { level: 1 })).toBeVisible()
    await expectNoAxeViolations(page)
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
