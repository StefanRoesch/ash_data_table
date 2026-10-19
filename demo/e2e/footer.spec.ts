import type { Locator } from "@playwright/test"
import { expectNoAxeViolations } from "./support/a11y"
import { SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { Table } from "./support/table"

// Footer summaries, in a browser: the row after the last record of /tasks,
// with the average progress, the sum of the estimates, the latest due date
// and the number of completed tasks, each under its column. The numbers
// are over every task that matches, not over the page; what they are for
// which person is in the LiveView tests (footer_summaries_test.exs).

const SUMMARISED = ["progress", "estimate_hours", "due_on", "completed_at"]

/** One task: a filter that leaves a single row, so that the numbers are that row's. */
const ONE = "/tasks?task[f][title]=Rename the onboarding email"

/** Where an element is across the page, and how wide. */
async function across(locator: Locator): Promise<{ x: number; width: number }> {
  const box = (await locator.boundingBox())!
  return { x: Math.round(box.x), width: Math.round(box.width) }
}

/** The summaries are there: none is on its way. */
async function summed(table: Table): Promise<void> {
  await expect(table.summaries).toBeVisible()
  await expect(table.summaries.locator("[role=cell][aria-busy]")).toHaveCount(0)
}

test.describe("the footer row", () => {
  test("stands after the last record, each number under its column", async ({ tasks }) => {
    await tasks.open()
    await summed(tasks)

    // in the table's footer, the last row of the grid
    await expect(tasks.grid.locator(":scope > [id$='-foot'] > [role=row]")).toHaveCount(1)
    await expect(tasks.summaries).toHaveRole("row")
    const count = await tasks.grid.getAttribute("aria-rowcount")
    expect(count, "the records, the two header rows and this row").toBe(String(SEED.tasks.acme + 3))
    await expect(tasks.summaries).toHaveAttribute("aria-rowindex", count!)

    await expect(tasks.summary("progress")).toHaveText(/^Average \d+(\.\d+)?$/)
    await expect(tasks.summary("estimate_hours")).toHaveText(/^Sum \d+(\.\d+)?$/)
    await expect(tasks.summary("due_on")).toHaveText(/^Max \d{4}-\d{2}-\d{2}$/)
    await expect(tasks.summary("completed_at")).toHaveText(/^Count \d+$/)

    for (const column of SUMMARISED) {
      await expect(tasks.summary(column)).toHaveRole("cell")
      expect(await across(tasks.summary(column)), `under ${column}`).toEqual(
        await across(tasks.header(column)),
      )
    }

    // a column without a summary has an empty cell under it
    await expect(tasks.summary("title")).toHaveText("")
    expect(await across(tasks.summary("title"))).toEqual(await across(tasks.header("title")))
  })

  test("is over what the filters match", async ({ tasks }) => {
    await tasks.open(ONE)
    await expect(tasks.rows).toHaveCount(1)
    await summed(tasks)
    const [only] = await tasks.rowKeys()

    // one task: its own due date is the latest, and it is the one counted or not
    const due = (await tasks.cell(only, "due_on").innerText()).trim()
    await expect(tasks.summary("due_on")).toHaveText(due === "" ? "Max" : `Max ${due}`)
    const completed = (await tasks.cell(only, "completed_at").innerText()).trim()
    await expect(tasks.summary("completed_at")).toHaveText(`Count ${completed === "" ? 0 : 1}`)
  })

  test("has no Tab stop: Tab goes from the last record's stops to the pagination", async ({ page, tasks }) => {
    await tasks.open()
    await summed(tasks)

    await expect(tasks.summaries.locator("[tabindex], button, input, select, a")).toHaveCount(0)
    const last = (await tasks.tabStops()).at(-1)!
    expect(last.startsWith(`task-row-${(await tasks.rowKeys()).at(-1)}`), "the last stop of the grid is the last record's").toBe(true)
    await page.locator(`[id="${last}"]`).focus()
    await tasks.press("Tab")
    await expect(tasks.pageButton(1)).toBeFocused()
  })

  test("a summary is hidden with its column, and comes back with it", async ({ tasks }) => {
    await tasks.open()
    await summed(tasks)

    await tasks.hide("progress")
    await expect(tasks.summary("progress")).toBeHidden()
    await expect(tasks.summary("estimate_hours")).toBeVisible()
    // what is left still stands under its column
    for (const column of ["estimate_hours", "due_on", "completed_at"]) {
      expect(await across(tasks.summary(column)), `under ${column}`).toEqual(
        await across(tasks.header(column)),
      )
    }

    await tasks.unhide("progress")
    await expect(tasks.summary("progress")).toBeVisible()
    await expect(tasks.summary("progress")).toHaveText(/^Average \d+(\.\d+)?$/)
    expect(await across(tasks.summary("progress"))).toEqual(await across(tasks.header("progress")))
  })
})

test.describe("after an inline edit", () => {
  test("the number follows what was saved", async ({ tasks }) => {
    await tasks.open(ONE)
    await expect(tasks.rows).toHaveCount(1)
    await summed(tasks)
    const [only] = await tasks.rowKeys()
    const estimate = tasks.cell(only, "estimate_hours")

    await estimate.focus()
    await tasks.press("Enter")
    await tasks.retype("33")
    await tasks.saves(estimate, () => tasks.press("Enter"))
    await expect(estimate).toHaveText("33 h")
    await expect(tasks.summary("estimate_hours")).toHaveText("Sum 33")
    await summed(tasks)

    await tasks.press("Enter")
    await tasks.retype("7.5")
    await tasks.saves(estimate, () => tasks.press("Enter"))
    await expect(tasks.summary("estimate_hours")).toHaveText("Sum 7.5")
    await expect(estimate, "focus stays on the cell that was edited").toBeFocused()
  })
})

test.describe("a nested table", () => {
  test("has the summaries of its own records, before its pages", async ({ page }) => {
    const projects = new Table(page, "project", "/projects")
    await projects.open()
    // the projects declare no summary: no footer row
    await expect(projects.summaries).toHaveCount(0)

    const nested = await projects.openLine(SEED.project.mobileApp, "tasks")
    await summed(nested)

    await expect(nested.summary("completed_at")).toHaveText(/^Count \d+$/)
    await expect(nested.summary("progress")).toHaveText(/^Average \d+(\.\d+)?$/)
    expect(await across(nested.summary("progress"))).toEqual(await across(nested.header("progress")))

    // the footer of a nested table: the summaries, then its pages and its link
    const footer = await nested.grid
      .locator(":scope > [id$='-foot'] > [role=row]")
      .evaluateAll((rows) => rows.map((row) => row.id.split("-").at(-1)))
    expect(footer[0]).toBe("summaries")
    expect(footer.length).toBeGreaterThan(1)
  })
})

test.describe("a person who sees a field on some tasks only", () => {
  test.use({ actor: "member" })

  test("has a dash in place of its sum, read out as not available", async ({ tasks }) => {
    await tasks.open()
    await summed(tasks)

    const sum = tasks.summary("estimate_hours")
    await expect(sum.locator("[data-summary-kind]")).toHaveText("Sum")
    await expect(sum.locator("[data-summary-unavailable] [aria-hidden=true]")).toHaveText("–")
    await expect(sum.locator("[data-summary-unavailable] .sr-only")).toHaveText("Not available")
    await expect(sum.locator("[data-summary-value]")).toHaveCount(0)

    // what they see on every task is summed for them as for anybody
    await expect(tasks.summary("progress")).toHaveText(/^Average \d+(\.\d+)?$/)
  })
})

test.describe("accessibility", () => {
  for (const theme of ["light", "dark"] as const) {
    test.describe(`in the ${theme} theme`, () => {
      test.beforeEach(async ({ page }) => {
        await page.addInitScript((theme) => localStorage.setItem("phx:theme", theme), theme)
      })

      test("the footer row of a table and of a nested table", async ({ page }) => {
        const projects = new Table(page, "project", "/projects")
        await projects.open()
        await expect(page.locator("html")).toHaveAttribute("data-theme", theme)
        const nested = await projects.openLine(SEED.project.mobileApp, "tasks")
        await summed(nested)

        await expectNoAxeViolations(page)
      })

      test.describe("with a number that is not available", () => {
        test.use({ actor: "member" })

        test("the dash", async ({ page, tasks }) => {
          await tasks.open()
          await expect(page.locator("html")).toHaveAttribute("data-theme", theme)
          await summed(tasks)
          await expect(tasks.summary("estimate_hours").locator("[data-summary-unavailable]")).toBeVisible()

          await expectNoAxeViolations(page)
        })
      })
    })
  }
})
