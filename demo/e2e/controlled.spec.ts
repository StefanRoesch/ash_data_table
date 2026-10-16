import { expect, test } from "./support/fixtures"
import { Table } from "./support/table"

// Controlled mode (stage 6): /e2e/controlled attaches memos with
// `controlled: [:panel]`, and draws the panel of "Rename" as a form of its
// own, from what the table holds of the request.

test("the page draws the panel of a row action, and its form runs the action through the table", async ({ page }) => {
  const memos = new Table(page, "memo", "/e2e/controlled")
  await memos.open()
  const [key] = await memos.rowKeys()

  await memos.action(key, "rename").click()
  // the table draws no panel of its own
  await expect(page.locator("#memo-panel")).toHaveCount(0)
  await expect(page.locator("#request-heading")).toContainText("Rename")

  // without the reason the action refuses: the page's form says so
  await page.locator("#request-title").fill("Buy oat milk")
  await page.locator("#request-run").click()
  await expect(page.locator("#request .request-error")).not.toHaveCount(0)
  await expect(memos.cell(key, "title")).toHaveText("Buy milk")

  await page.locator("#request-reason").fill("No cows")
  await page.locator("#request-run").click()
  await expect(page.locator("#request")).toHaveCount(0)
  await expect(memos.cell(key, "title")).toHaveText("Buy oat milk")
})
