import { expectNoAxeViolations } from "./support/a11y"
import { deleteTask, SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { switchLocale } from "./support/locale"
import { Table } from "./support/table"

// axe-core on the states of editing, on the components of a column, and on
// what a person may not see or do (see a11y-tables.spec.ts).

const FIRST_TASK = SEED.task.first
const SECOND = SEED.task.second

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
