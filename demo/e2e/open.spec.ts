import { SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { Table } from "./support/table"

// "Open" offered by the page (stage 6): /e2e/opened attaches the tasks with
// `open: "Open"`, and shows the key of the row it was told was opened.

const FIRST = SEED.task.first

test("the keyboard reaches Open first in the actions cell, and Enter tells the page the row", async ({ page }) => {
  const tasks = new Table(page, "task", "/e2e/opened")
  await tasks.open()

  const cell = tasks.actionsCell(FIRST)
  await cell.focus()
  await tasks.press("Enter")
  const open = cell.locator("button[data-open]")
  await expect(open).toBeFocused()
  await expect(open).toHaveText("Open")

  await tasks.press("Enter")
  await expect(page.locator("#opened")).toHaveText(FIRST)
  // nothing else changes: focus stays on the button
  await expect(open).toBeFocused()
})
