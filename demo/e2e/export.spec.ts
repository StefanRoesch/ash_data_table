import { readFile } from "node:fs/promises"

import { SEED } from "./support/data"
import { expect, test } from "./support/fixtures"

// "Export CSV" of /tasks in a browser: an action on the selection
// (`selection_argument`) that returns a file (`Ash.Type.File`). The server
// pushes the file to the page (`ash_data_table:download`), and the
// library's window listener (`assets/js/download.js`) has the browser save
// it. What the file holds for each selection kind and sort is in the
// LiveView tests (`test/demo_web/tables/task_export_test.exs`); this is
// the real download, which the `react` project runs again with the React
// kit.

const FIRST = SEED.task.first
const SECOND = SEED.task.second

test.beforeEach(async ({ tasks }) => {
  await tasks.open()
})

test("saves tasks.csv with the selected tasks, and says so above the grid", async ({ page, tasks }) => {
  await tasks.box(FIRST).click()
  await tasks.box(SECOND).click()
  await expect(tasks.selectedCount).toHaveText("2 selected")

  const saved = page.waitForEvent("download")
  await tasks.useBulk("export_csv")
  const download = await saved

  expect(download.suggestedFilename()).toBe("tasks.csv")
  const lines = (await readFile(await download.path(), "utf8")).split("\r\n").filter((line) => line !== "")

  expect(lines[0]).toBe("id,title,status,priority,progress,billable,due_on,completed_at,tags,inserted_at")
  expect(lines.slice(1).map((line) => line.split(",")[0]).sort()).toEqual([FIRST, SECOND].sort())

  // said above the grid, as a table action's result is, and nothing asked
  await expect(tasks.result).toHaveText("Export CSV: tasks.csv")
  await expect(tasks.question).toBeHidden()
  // the rows stay selected
  await expect(tasks.box(FIRST)).toBeChecked()
  await expect(tasks.box(SECOND)).toBeChecked()
})
