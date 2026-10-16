import type { Browser } from "@playwright/test"
import { expectNoAxeViolations } from "./support/a11y"
import { storageStateOf } from "./support/actors"
import { SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { Table } from "./support/table"
import { params } from "./support/url"

// The time zone of the page, in a browser that is in Europe/Berlin: the demo
// takes the browser's zone (`DemoWeb.Zone`, from the LiveView's connect
// params) and gives it to the tables, which show, take and filter by
// datetimes in it. Every other file runs in UTC (playwright.config.ts).
//
// The times are in July 2031, when Berlin is two hours ahead of UTC, and no
// task of the seed is completed then. What the LiveView tests cover besides
// (the changes of the clocks, the panel, the placed table) is in
// time_zone_test.exs.

const FIRST = SEED.task.first

test.use({ timezoneId: "Europe/Berlin" })

/** /tasks as the admin in a browser that is in UTC: what is stored, seen from there. */
async function inUtc(browser: Browser, baseURL: string | undefined): Promise<Table> {
  const context = await browser.newContext({
    baseURL,
    storageState: storageStateOf("admin"),
    timezoneId: "UTC",
  })
  const table = new Table(await context.newPage(), "task", "/tasks")
  await table.open()
  return table
}

test.beforeEach(async ({ tasks }) => {
  await tasks.open()
})

test("a time typed in the cell is shown back as typed, and stored as the instant it is", async ({
  page,
  tasks,
  browser,
  baseURL,
}) => {
  await expect(page.locator("#time-zone")).toHaveText("Times in Europe/Berlin")

  const completed = tasks.cell(FIRST, "completed_at")
  await completed.focus()
  await tasks.press("Enter")
  await tasks.editor(completed).fill("2031-07-15T16:30:15")
  await tasks.saves(completed, () => tasks.press("Enter"))
  await expect(completed).toHaveText("2031-07-15T16:30:15")
  await expect(completed).not.toHaveAttribute("aria-invalid", "true")

  // the editor opens again on the time it was given
  await tasks.press("Enter")
  await expect(tasks.editor(completed)).toHaveValue("2031-07-15T16:30:15")
  await tasks.press("Escape")

  // two hours earlier in UTC: the instant that was typed in Berlin
  const utc = await inUtc(browser, baseURL)
  await expect(utc.cell(FIRST, "completed_at")).toHaveText("2031-07-15T14:30:15")
  await utc.page.context().close()
})

test("a filter on a datetime means the times there, and the URL keeps them as typed", async ({
  page,
  tasks,
  browser,
  baseURL,
}) => {
  // just after midnight there, still the day before in UTC
  const completed = tasks.cell(FIRST, "completed_at")
  await completed.focus()
  await tasks.press("Enter")
  await tasks.editor(completed).fill("2031-07-16T00:30:15")
  await tasks.saves(completed, () => tasks.press("Enter"))
  await expect(completed).toHaveText("2031-07-16T00:30:15")

  const from = tasks.filterValue("completed_at")
  const to = tasks.filterTo("completed_at")
  // nothing to read yet: "between" without its ends is no filter
  await tasks.filterOperator("completed_at").selectOption("between")
  await expect(to).toBeVisible()
  await from.fill("2031-07-16T00:00")
  await tasks.reads(() => from.press("Enter"))
  await to.fill("2031-07-16T23:59:59")
  await tasks.reads(() => to.press("Enter"))

  expect(params(page)).toEqual({
    "task[f][completed_at][between][from]": "2031-07-16T00:00",
    "task[f][completed_at][between][to]": "2031-07-16T23:59:59",
  })
  expect(await tasks.rowKeys()).toEqual([FIRST])

  // the same link in UTC is that day there, which the task is not completed on
  const utc = await inUtc(browser, baseURL)
  await utc.open(new URL(page.url()).pathname + new URL(page.url()).search)
  await expect(utc.empty).toHaveText("No records")
  await utc.page.context().close()
})

for (const theme of ["light", "dark"] as const) {
  test.describe(`in the ${theme} theme`, () => {
    test("the page that says its zone, with a datetime editor open", async ({ page, tasks }) => {
      await page.addInitScript((theme) => localStorage.setItem("phx:theme", theme), theme)
      await tasks.open()
      await expect(page.locator("html")).toHaveAttribute("data-theme", theme)
      await expect(page.locator("#time-zone")).toHaveText("Times in Europe/Berlin")
      await expectNoAxeViolations(page)

      const completed = tasks.cell(FIRST, "completed_at")
      await completed.focus()
      await tasks.press("Enter")
      await expect(tasks.editor(completed)).toBeFocused()
      await expectNoAxeViolations(page)
      await tasks.press("Escape")
    })
  })
}
