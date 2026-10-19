import { SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { Table } from "./support/table"

// "Open" offered by the page: /e2e/opened attaches the tasks with
// `open: "Open"`, and shows the key of the row it was told was opened.

const FIRST = SEED.task.first

test("Tab reaches Open first in the actions cell, and Enter tells the page the row", async ({ page }) => {
  const tasks = new Table(page, "task", "/e2e/opened")
  await tasks.open()

  const cell = tasks.actionsCell(FIRST)
  const open = cell.locator("button[data-open]")
  await expect(open).toHaveText("Open")
  // the first button of the cell: the stop before it is the row's last stop before the actions
  const stops = await tasks.rowStops(FIRST)
  const before = stops[stops.indexOf(`task-row-${FIRST}-a-open`) - 1]
  expect(before).not.toMatch(new RegExp(`^task-row-${FIRST}-a-`))
  await open.focus()
  await expect(open).toBeFocused()

  await tasks.press("Enter")
  await expect(page.locator("#opened")).toHaveText(FIRST)
  // nothing else changes: focus stays on the button
  await expect(open).toBeFocused()
})
