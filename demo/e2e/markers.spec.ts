import type { Page } from "@playwright/test"
import { expect, test } from "./support/fixtures"

// The grid's hook finds the table's elements by their markers alone (the
// design note of stage 7, D4; test group Y): /e2e/markers draws a grid with
// `div`s and `span`s, no `table`, `tr` or `td`, that carries the markers
// (`DemoWeb.E2E.MarkersLive`), with a table nested in a cell. If the hook
// relied on a tag, these would fail.
//
// And the development check of the hooks (D13): while LiveView's client
// debug is on, a part that lacks a marker is named on the console.

const cell = (page: Page, key: string, column: string) => page.locator(`[id="kit-row-${key}-c-${column}"]`)
const row = (page: Page, key: string) => page.locator(`[id="kit-row-${key}-r"]`)
const holder = (page: Page) => page.locator('[id="kit-row-a-n-parts-c"]')
const part = (page: Page, key: string) => page.locator(`[id="kit-row-a-t-parts-row-${key}-c-title"]`)

/** The cells that are a tab stop: one for the grid and the grid in it. */
const tabStops = (page: Page) =>
  page
    .locator('[id="kit-grid"]')
    .evaluate((grid) => Array.from(grid.querySelectorAll<HTMLElement>('[tabindex="0"]')).map((node) => node.id))

async function opened(page: Page): Promise<void> {
  await page.goto("/e2e/markers")
  await expect(page.locator('[id="kit-grid"]')).toBeAttached()
  // the hook has made its tab stop
  await expect.poll(() => tabStops(page)).toEqual(["kit-row-a-c-name"])
}

test.describe("a grid drawn with other elements than a table's", () => {
  test.beforeEach(async ({ page }) => {
    await opened(page)
  })

  test("is one tab stop, and the arrow keys move in it, over the cell a table is nested in", async ({
    page,
  }) => {
    await cell(page, "a", "name").focus()
    await page.keyboard.press("ArrowRight")
    await expect(cell(page, "a", "size")).toBeFocused()
    await page.keyboard.press("ArrowLeft")
    await page.keyboard.press("ArrowLeft")
    await expect(page.locator('[id="kit-row-a-s"]')).toBeFocused()
    await page.keyboard.press("ArrowRight")
    // down: the cell the nested table is in, then the next record, in the
    // column the person was in
    await page.keyboard.press("ArrowDown")
    await expect(holder(page)).toBeFocused()
    await page.keyboard.press("ArrowDown")
    await expect(cell(page, "b", "name")).toBeFocused()
    // up from the first record: the filter row, then the header
    await page.keyboard.press("ArrowUp")
    await page.keyboard.press("ArrowUp")
    await page.keyboard.press("ArrowUp")
    await expect(page.locator('[id="kit-filter-name"]')).toBeFocused()
    await page.keyboard.press("ArrowUp")
    await expect(page.locator('[id="kit-head-name"]')).toBeFocused()
    await page.keyboard.press("End")
    await expect(page.locator('[id="kit-head-note"]')).toBeFocused()
    expect(await tabStops(page)).toEqual(["kit-head-note"])
  })

  test("Enter goes into the nested table, and Escape back out", async ({ page }) => {
    await holder(page).focus()
    await page.keyboard.press("Enter")
    await expect(part(page, "p1")).toBeFocused()
    await page.keyboard.press("ArrowDown")
    await expect(part(page, "p2")).toBeFocused()
    await page.keyboard.press("Escape")
    await expect(holder(page)).toBeFocused()
  })

  test("Enter edits a cell, Enter saves it, and Escape gives an edit up", async ({ page }) => {
    const name = cell(page, "a", "name")
    await name.focus()
    await page.keyboard.press("Enter")
    const editor = name.locator("textarea")
    await expect(editor).toBeFocused()
    await expect(editor).toHaveValue("Anchor")
    await page.keyboard.press("ControlOrMeta+A")
    await page.keyboard.type("Anvil")
    await page.keyboard.press("Enter")
    await expect(name).toHaveText("Anvil")
    await expect(name.locator("textarea")).toHaveCount(0)

    await page.keyboard.press("Enter")
    await expect(name.locator("textarea")).toBeFocused()
    await page.keyboard.type("Axe")
    await page.keyboard.press("Escape")
    await expect(name).toHaveText("Anvil")
    await expect(name).toBeFocused()
  })

  test("Space selects a row, and Shift with Down Arrow the rows down to the next, over what is under a row", async ({
    page,
  }) => {
    await cell(page, "a", "size").focus()
    await page.keyboard.press(" ")
    await expect(row(page, "a")).toHaveAttribute("aria-selected", "true")
    await expect(row(page, "b")).toHaveAttribute("aria-selected", "false")
    await page.keyboard.press("Shift+ArrowDown")
    await expect(cell(page, "b", "size")).toBeFocused()
    await expect(row(page, "b")).toHaveAttribute("aria-selected", "true")
    await expect(page.locator('[id="kit-row-a-s"] input')).toBeChecked()
    await expect(page.locator('[id="kit-row-b-s"] input')).toBeChecked()
  })

  test("a column is made wider with its handle, its cells with it", async ({ page }) => {
    const head = page.locator('[id="kit-head-name"]')
    const before = (await cell(page, "a", "name").boundingBox())!.width
    await head.focus()
    await page.keyboard.press("F2")
    await expect(page.locator('[id="kit-resize-name"]')).toBeFocused()
    for (let i = 0; i < 3; i++) await page.keyboard.press("ArrowRight")
    await expect
      .poll(async () => Math.round((await cell(page, "a", "name").boundingBox())!.width - before))
      .toBeGreaterThanOrEqual(29)
    await expect
      .poll(async () => Math.round((await head.boundingBox())!.width))
      .toBe(Math.round((await cell(page, "b", "name").boundingBox())!.width))
  })

  test("a hidden column is not shown, and the arrow keys pass over it", async ({ page }) => {
    await page.locator('[id="kit-columns-button"]').click()
    await page.locator('[id="kit-column-size"]').uncheck()
    await expect(page.locator('[id="kit-head-size"]')).toBeHidden()
    await expect(cell(page, "a", "size")).toBeHidden()
    await expect(page.locator('[id="kit-filter-size"]')).toBeHidden()

    await cell(page, "b", "name").focus()
    await page.keyboard.press("ArrowRight")
    await expect(cell(page, "b", "note")).toBeFocused()
  })
})

test.describe("the development check of the hooks", () => {
  /** Turns LiveView's client debug on for the page, and loads it again. */
  async function debugging(page: Page, path: string): Promise<void> {
    await page.goto(path)
    await page.evaluate(() => (window as any).liveSocket.enableDebug())
    await page.reload()
    await expect(page.locator('[id="kit-grid"], [data-ash-data-table]').first()).toBeAttached()
  }

  test("names on the console the cell that has no place, while the client debug is on", async ({
    page,
    consoleErrors,
  }) => {
    const said: string[] = []
    page.on("console", (message) => {
      if (message.type() === "error") said.push(message.text())
    })
    consoleErrors.allow(/^ash_data_table: the grid kit-grid has no aria-colindex on the cell kit-row-b-c-size$/)
    await debugging(page, "/e2e/markers?missing=colindex")
    await expect
      .poll(() => said)
      .toContain("ash_data_table: the grid kit-grid has no aria-colindex on the cell kit-row-b-c-size")
  })

  test("says nothing of a table that has all its markers, nor while the debug is off", async ({ page, tasks }) => {
    // the console stays free of errors: every test ends with that
    await debugging(page, "/tasks")
    await expect(tasks.grid).toBeAttached()
    await tasks.expand(await tasks.rowKey(1))

    await page.evaluate(() => (window as any).liveSocket.disableDebug())
    await page.goto("/e2e/markers?missing=colindex")
    await expect.poll(() => tabStops(page)).toEqual(["kit-row-a-c-name"])
  })
})
