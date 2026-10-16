import { expectNoAxeViolations } from "./support/a11y"
import { deleteTask, SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { switchLocale } from "./support/locale"
import { Table } from "./support/table"

// axe-core on row actions, row create and the action panel (see
// a11y-tables.spec.ts).

const SECOND = SEED.task.second

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
