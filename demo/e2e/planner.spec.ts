import { expectNoAxeViolations } from "./support/a11y"
import { SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { Table } from "./support/table"

// /tasks/planner: a LiveView of the demo's own (`DemoWeb.PlannerLive`) with
// the tasks attached below two cards. "Selected for the sprint" reads the
// selection back on every change of it and on every save of a selected
// row; "Last changes" says the last saves, creates and deletes; "Clear
// selection" is the page telling the table. The admin unless a test says
// otherwise; what a test changes is rolled back when it ends.

const FIRST = SEED.task.first
const SECOND = SEED.task.second

let tasks: Table

test.beforeEach(async ({ page }) => {
  tasks = new Table(page, "task", "/tasks/planner")
  await tasks.open()
})

/** Types a new estimate into a cell and saves it with Enter. */
async function estimate(key: string, hours: string): Promise<void> {
  const cell = tasks.cell(key, "estimate_hours")
  await cell.focus()
  await tasks.press("Enter")
  await tasks.retype(hours)
  await tasks.saves(cell, () => tasks.press("Enter"))
}

test("is reached from the header, with the cards above the table", async ({ page }) => {
  await page.goto("/")
  await page.getByRole("navigation", { name: "Main" }).getByRole("link", { name: "Sprint planner" }).click()
  await expect(page).toHaveURL(/\/tasks\/planner$/)
  await tasks.ready()

  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Sprint planner")
  await expect(page.getByRole("region", { name: "Selected for the sprint" })).toBeVisible()
  await expect(page.getByRole("region", { name: "Last changes" })).toBeVisible()
  await expect(page.getByRole("region", { name: "Tasks" }).getByRole("table", { name: "Tasks" })).toBeVisible()
  await expect(page.locator("#planner-sprint-summary")).toHaveText(/No tasks selected/)
  await expect(page.getByRole("region", { name: "Selected for the sprint" }).getByRole("button", { name: "Clear selection" })).toBeDisabled()
})

test("ticked rows fill the card, a saved estimate changes it, and Clear selection empties it", async ({ page }) => {
  await tasks.box(FIRST).check()
  await tasks.box(SECOND).check()
  await expect(page.locator("#planner-count")).toHaveText("2")

  await estimate(FIRST, "5")
  await estimate(SECOND, "2.5")
  await expect(page.locator("#planner-hours")).toHaveText("7.5 h")
  await expect(page.locator("#planner-feed li")).toHaveCount(2)
  await expect(page.locator("#planner-feed li").first()).toHaveText(/^Estimate hours of “.+” saved$/)
  await expect(page.locator("#planner-feed")).toHaveAttribute("aria-live", "polite")

  await expectNoAxeViolations(page)

  await page.getByRole("region", { name: "Selected for the sprint" }).getByRole("button", { name: "Clear selection" }).click()
  await expect(page.locator("#planner-sprint-summary")).toHaveText(/No tasks selected/)
  await expect.poll(() => tasks.selectedKeys()).toEqual([])
  await expect(page.getByRole("region", { name: "Selected for the sprint" }).getByRole("button", { name: "Clear selection" })).toBeDisabled()
})

test.describe("as the member", () => {
  test.use({ actor: "member" })

  test("an estimate they may not see is counted as unknown", async ({ page }) => {
    // the first row is neither assigned to the member nor reported by them
    await tasks.box(FIRST).check()
    await expect(page.locator("#planner-hours")).toHaveText(/\+ 1 unknown$/)
    await expectNoAxeViolations(page)
  })
})
