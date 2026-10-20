import type { Page } from "@playwright/test"
import { expect, test } from "./support/fixtures"
import { Table } from "./support/table"

// Controlled mode: /e2e/controlled attaches memos with
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

// Controlled mode widened: /e2e/controlled/kit
// attaches a table of `AshDataTable.Test.Resource` with `controlled:
// [:confirm, :picker]`, and draws the questions and the owner's picker
// itself.
test.describe("what the page draws of the questions and the picker", () => {
  async function opened(page: Page): Promise<string> {
    await page.goto("/e2e/controlled/kit")
    await expect(page.locator('[id^="kit-row-"][role=rowgroup]').filter({ hasText: "Anchor" })).toHaveCount(1)
    // connected: the join's patch, which mounts the hooks, is in the page
    await expect(page.locator(".phx-connected").first()).toBeAttached()
    const group = page.locator('[id^="kit-row-"][role=rowgroup]').filter({ hasText: "Anchor" }).first()
    return ((await group.getAttribute("id")) ?? "").replace(/^kit-row-/, "")
  }

  const cell = (page: Page, key: string, column: string) => page.locator(`[id="kit-row-${key}-c-${column}"]`)

  test("a column's question is the page's: the cell waits, and Confirm saves it", async ({ page }) => {
    const anchor = await opened(page)
    const note = cell(page, anchor, "note")
    await note.focus()
    await page.keyboard.press("Enter")
    await note.locator("textarea").fill("second")
    await page.keyboard.press("Enter")

    // the table asks nothing itself: the page's question, and the cell waits
    await expect(page.locator("#kit-dialog")).not.toBeVisible()
    await expect(page.locator("#host-question-text")).toHaveText("Change the note?")
    await expect(note).toHaveAttribute("aria-busy", "true")
    await expect(note).toHaveText("second")

    await page.locator("#host-confirm").click()
    await expect(page.locator("#host-question")).toHaveCount(0)
    await expect(note).not.toHaveAttribute("aria-busy")
    await expect(note).toHaveText("second")
  })

  test("Cancel of a column's question puts the cell back as it was", async ({ page }) => {
    const anchor = await opened(page)
    const note = cell(page, anchor, "note")
    await note.focus()
    await page.keyboard.press("Enter")
    await note.locator("textarea").fill("second")
    await page.keyboard.press("Enter")
    await expect(note).toHaveAttribute("aria-busy", "true")

    await page.locator("#host-cancel").click()
    await expect(page.locator("#host-question")).toHaveCount(0)
    await expect(note).not.toHaveAttribute("aria-busy")
    await expect(note).toHaveText("first")
  })

  test("a cell held for the page stays busy while a patch puts its row back, and Cancel leaves the patch", async ({ page }) => {
    const anchor = await opened(page)
    const note = cell(page, anchor, "note")
    await note.focus()
    await page.keyboard.press("Enter")
    await note.locator("textarea").fill("second")
    await page.keyboard.press("Enter")
    await expect(page.locator("#host-question-text")).toHaveText("Change the note?")
    await expect(note).toHaveAttribute("aria-busy", "true")

    // another cell of the row saves: the server sends the row again, and
    // the note waits still. The default kit's patch draws the note as the
    // record has it; the React kit draws a busy cell as it was until the
    // hook gives it back (react-kit-design.md §15, "a cell the hook
    // holds"), what was typed
    const name = cell(page, anchor, "name")
    await name.focus()
    await page.keyboard.press("Enter")
    await name.locator("textarea").fill("Anchored")
    await page.keyboard.press("Enter")
    await expect(name).toHaveText("Anchored")
    await expect(name).not.toHaveAttribute("aria-busy")
    await expect(note).toHaveText(test.info().project.name === "react" ? "second" : "first")
    await expect(note).toHaveAttribute("aria-busy", "true")

    await page.locator("#host-cancel").click()
    await expect(page.locator("#host-question")).toHaveCount(0)
    await expect(note).not.toHaveAttribute("aria-busy")
    await expect(note).toHaveText("first")
    await expect(name).toHaveText("Anchored")
  })

  test("a nested table's question is the page's too: its cell waits, and Confirm saves it", async ({ page }) => {
    const anchor = await opened(page)
    await page.locator(`[id="kit-row-${anchor}-e"] button`).click()
    await page.locator(`[id="kit-row-${anchor}-l-parts-b"]`).click()
    const nested = `kit-row-${anchor}-t-parts`
    const group = page.locator(`[id^="${nested}-row-"][role=rowgroup]`).filter({ hasText: "Pin" })
    await expect(group).toHaveCount(1)
    const part = ((await group.getAttribute("id")) ?? "").replace(`${nested}-row-`, "")
    const title = page.locator(`[id="${nested}-row-${part}-c-title"]`)

    await title.focus()
    await page.keyboard.press("Enter")
    await title.locator("textarea").fill("Bolt")
    await page.keyboard.press("Enter")

    // the nested table asks nothing itself: the page's question, and its cell waits
    await expect(page.locator(`[id="${nested}-dialog"]`)).not.toBeVisible()
    await expect(page.locator("#host-question-text")).toHaveText("Change the title?")
    await expect(title).toHaveAttribute("aria-busy", "true")
    await expect(title).toHaveText("Bolt")

    await page.locator("#host-confirm").click()
    await expect(page.locator("#host-question")).toHaveCount(0)
    await expect(title).not.toHaveAttribute("aria-busy")
    await expect(title).toHaveText("Bolt")
  })

  test("the picker is the page's, and its choice is asked about and saved", async ({ page }) => {
    const anchor = await opened(page)
    const owner = cell(page, anchor, "owner")
    await owner.focus()
    await page.keyboard.press("Enter")

    // the table draws no picker and reads no table for it
    await expect(page.locator("#host-picker")).toBeVisible()
    await expect(page.locator('[id="kit-picker"]')).toHaveCount(0)
    await expect(page.locator('[id="kit-pick-owner"]')).toHaveCount(0)

    await page.locator("#host-pick-Bob").click()
    // the column asks first: the page's question
    await expect(page.locator("#host-question-text")).toHaveText("Change the owner?")
    await expect(owner).toHaveText("Ann")

    await page.locator("#host-confirm").click()
    await expect(page.locator("#host-question")).toHaveCount(0)
    await expect(owner).toHaveText("Bob")
  })
})
