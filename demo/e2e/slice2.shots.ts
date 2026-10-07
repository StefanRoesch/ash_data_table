import { mkdirSync } from "node:fs"
import path from "node:path"
import type { Page } from "@playwright/test"
import { SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { switchLocale } from "./support/locale"
import { Table } from "./support/table"

// Pictures of row actions and row create, for a person to look at: the
// actions column, a failed action, the action panel, the create button on
// the line of a table's name and on the line of a nested table, at several
// widths, in the dark theme and in German. `npm run shots` takes them
// (playwright.shots.config.ts); they assert nothing but that the state they
// show was reached.

const DIR = process.env.SHOTS_DIR ?? path.join(import.meta.dirname, "test-results", "shots")
const FIRST = SEED.task.first

mkdirSync(DIR, { recursive: true })

test.use({ writes: true, viewport: { width: 1500, height: 900 } })

async function shot(page: Page, name: string): Promise<void> {
  // the demo's progress bar belongs to no state of a table
  await expect(page.locator("body > canvas")).toBeHidden()
  await page.screenshot({ path: path.join(DIR, `${name}.png`) })
}

/** Scrolls the grid sideways to its last column, the actions. */
async function toActions(tasks: Table, key: string): Promise<void> {
  await tasks.action(key, "destroy").scrollIntoViewIfNeeded()
}

async function dark(page: Page): Promise<void> {
  await page.addInitScript(() => localStorage.setItem("phx:theme", "dark"))
}

test("the actions column, and the line of the table's name", async ({ page, tasks }) => {
  await tasks.open()
  await shot(page, "final-header-mounted")

  await toActions(tasks, FIRST)
  await tasks.actionsCell(SEED.task.second).focus()
  await tasks.press("Enter", "ArrowRight")
  await shot(page, "final-actions-column")

  await tasks.action(SEED.task.second, "destroy").click()
  await expect(tasks.question).toBeVisible()
  await shot(page, "final-confirm-destroy")
})

test.describe("as the member", () => {
  test.use({ actor: "member" })

  test("an action that failed", async ({ page, tasks }) => {
    await tasks.open()
    await toActions(tasks, FIRST)
    await tasks.acts(FIRST, () => tasks.action(FIRST, "archive").click())
    await page.mouse.move(5, 5)
    await expect(tasks.failure(tasks.actionsCell(FIRST))).toBeVisible()
    await shot(page, "final-failed-action")
  })
})

test("the action panel: a row action, with errors, and the create panel", async ({ page, tasks }) => {
  await tasks.open()
  await tasks.acts(FIRST, () => tasks.action(FIRST, "reassign").click())
  await expect(tasks.field("assignee_id")).toBeFocused()
  await shot(page, "final-panel-reassign")

  await tasks.field("assignee_id").fill("nobody")
  await tasks.panelSubmit.click()
  await expect(tasks.fieldError("reason")).toBeVisible()
  await shot(page, "final-panel-errors")
  await tasks.press("Escape")
  await expect(tasks.panel).toHaveCount(0)

  await tasks.create.click()
  await expect(tasks.field("title")).toBeFocused()
  await shot(page, "final-panel-create")
})

test("a nested table: the create button on its line, and its panel", async ({ page, tasks }) => {
  await tasks.open()
  const comments = await tasks.openLine(FIRST, "comments")
  await tasks.openLine(FIRST, "labels")
  await expect(tasks.lineCreate(FIRST, "comments")).toBeVisible()
  await page.mouse.move(5, 5)
  await shot(page, "final-nested-create")

  await tasks.lineCreate(FIRST, "comments").click()
  await expect(comments.field("body")).toBeFocused()
  await shot(page, "final-nested-create-panel")
})

test("the full view, and the dashboard", async ({ page }) => {
  const comments = new Table(page, "comment", "/comments")
  await comments.open(`/comments?comment[of][task][comments]=${FIRST}`)
  await shot(page, "final-full-view")

  const projects = new Table(page, "dashboard-projects", "/dashboard")
  await projects.open()
  await new Table(page, "dashboard-tasks", "/dashboard").ready()
  await page.screenshot({ path: path.join(DIR, "final-dashboard.png"), fullPage: true })
})

test.describe("at 900 px", () => {
  test.use({ viewport: { width: 900, height: 900 } })

  test("the header, the actions column, a nested table and the panel", async ({ page, tasks }) => {
    await tasks.open()
    await shot(page, "final-900")

    const comments = await tasks.openLine(FIRST, "comments")
    await expect(tasks.lineCreate(FIRST, "comments")).toBeVisible()
    await page.mouse.move(5, 5)
    await shot(page, "final-900-nested")
    await tasks.expander(FIRST).click()
    await expect(comments.root).toHaveCount(0)

    await toActions(tasks, FIRST)
    await page.mouse.move(5, 5)
    await shot(page, "final-900-actions")

    await tasks.acts(FIRST, () => tasks.action(FIRST, "reassign").click())
    await expect(tasks.field("assignee_id")).toBeFocused()
    await shot(page, "final-900-panel")
  })

  test("the full view and the dashboard", async ({ page }) => {
    const comments = new Table(page, "comment", "/comments")
    await comments.open(`/comments?comment[of][task][comments]=${FIRST}`)
    await shot(page, "final-900-full-view")

    const projects = new Table(page, "dashboard-projects", "/dashboard")
    await projects.open()
    await shot(page, "final-900-dashboard")
  })
})

test.describe("in the dark theme", () => {
  test.use({ actor: "member" })

  test("the header, a failed action, a nested table and the panel", async ({ page, tasks }) => {
    await dark(page)
    await tasks.open()
    await shot(page, "final-dark-header")

    const comments = await tasks.openLine(FIRST, "comments")
    await expect(tasks.lineCreate(FIRST, "comments")).toBeVisible()
    await page.mouse.move(5, 5)
    await shot(page, "final-dark-nested")
    await tasks.expander(FIRST).click()
    await expect(comments.root).toHaveCount(0)

    await toActions(tasks, FIRST)
    await tasks.acts(FIRST, () => tasks.action(FIRST, "archive").click())
    await page.mouse.move(5, 5)
    await expect(tasks.failure(tasks.actionsCell(FIRST))).toBeVisible()
    await shot(page, "final-dark")

    await tasks.acts(FIRST, () => tasks.action(FIRST, "reassign").click())
    await tasks.field("reason").fill("I will take it")
    await tasks.panelSubmit.click()
    await expect(tasks.panelErrors).toBeVisible()
    await shot(page, "final-dark-panel")
  })
})

test("in German", async ({ page, tasks }) => {
  await tasks.open()
  await switchLocale(page, "de")
  await tasks.ready()
  await toActions(tasks, FIRST)
  await shot(page, "final-german-actions")

  await tasks.acts(FIRST, () => tasks.action(FIRST, "reassign").click())
  await tasks.panelSubmit.click()
  await expect(tasks.fieldError("reason")).toBeVisible()
  await shot(page, "final-german")
  await tasks.press("Escape")
  await expect(tasks.panel).toHaveCount(0)

  await tasks.create.click()
  await expect(tasks.field("title")).toBeFocused()
  await shot(page, "final-german-create")
})

test.describe("on a narrow window", () => {
  test.use({ viewport: { width: 390, height: 800 } })

  test("the header and the panel", async ({ page, tasks }) => {
    await tasks.open()
    await shot(page, "final-narrow")

    await tasks.create.click()
    await expect(tasks.field("title")).toBeFocused()
    await shot(page, "final-narrow-panel")
  })
})
