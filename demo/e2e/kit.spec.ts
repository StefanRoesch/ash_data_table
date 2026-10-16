import type { Page } from "@playwright/test"
import { expectNoAxeViolations } from "./support/a11y"
import { expect, test } from "./support/fixtures"

// A kit of one's own (the design note of stage 7, test groups AA and Y):
// /e2e/kit draws a table of `AshDataTable.Test.Resource` with the demo's
// kit of `div`s (`DemoWeb.DivKit`), whose action panel and picker open in
// the page (`data-presentation="inline"`), or over it with
// `?presentation=modal`. What opens: focus goes in, Escape and Cancel take
// it away and put focus back on what opened it, and Tab leaves what is
// inline; axe finds nothing wrong either way. The grid of `div`s: the
// arrow keys, editing, a nested table.

/** The key of the record called `name`, as its row group's id says it. */
async function key(page: Page, name: string): Promise<string> {
  const group = page.locator('[id^="kit-row-"][role=rowgroup]').filter({ hasText: name }).first()
  const id = await group.getAttribute("id")
  return (id ?? "").replace(/^kit-row-/, "")
}

const cell = (page: Page, key: string, column: string) => page.locator(`[id="kit-row-${key}-c-${column}"]`)

/** Whether focus is inside the element of that id. */
const focusIn = (page: Page, id: string) =>
  page.evaluate((id) => !!document.getElementById(id)?.contains(document.activeElement), id)

async function opened(page: Page, query = ""): Promise<string> {
  await page.goto(`/e2e/kit${query}`)
  await expect(page.locator('[id="kit-table"][data-kit="div"]')).toBeAttached()
  await expect(page.locator('[id^="kit-row-"][role=rowgroup]').filter({ hasText: "Anchor" })).toHaveCount(1)
  // the hook has made its tab stop
  await expect(page.locator('[id="kit-table"] [tabindex="0"]')).toHaveCount(1)
  return key(page, "Anchor")
}

test.describe("the action panel in the page", () => {
  test("takes the focus as it opens, and Escape takes it away and puts focus back on its button", async ({
    page,
  }) => {
    const anchor = await opened(page)
    const button = page.locator(`[id="kit-row-${anchor}-a-stamp"]`)
    await button.click()
    const panel = page.locator('[id="kit-panel"]')
    await expect(panel).toHaveAttribute("data-presentation", "inline")
    await expect(panel).toHaveAttribute("role", "region")
    await expect(page.locator('dialog[id="kit-panel"]')).toHaveCount(0)
    await expect.poll(() => focusIn(page, "kit-panel")).toBe(true)
    // the page is not inert: what is after the table can be clicked
    await page.locator('[id="after"]').click({ trial: true })
    await page.locator('[id="kit-panel"] textarea').first().focus()
    await page.keyboard.press("Escape")
    await expect(panel).toHaveCount(0)
    await expect(button).toBeFocused()
  })

  test("Cancel takes it away, and Tab leaves it for the page", async ({ page }) => {
    const anchor = await opened(page)
    const button = page.locator(`[id="kit-row-${anchor}-a-stamp"]`)
    await button.click()
    const panel = page.locator('[id="kit-panel"]')
    await expect.poll(() => focusIn(page, "kit-panel")).toBe(true)
    // from its last control, Tab goes on to the page after it
    await page.locator('[id="kit-panel-submit"]').focus()
    await page.keyboard.press("Tab")
    await expect.poll(() => focusIn(page, "kit-panel")).toBe(false)
    await expect(panel).toBeVisible()
    await page.locator('[id="kit-panel-cancel"]').click()
    await expect(panel).toHaveCount(0)
    await expect(button).toBeFocused()
  })

  test("has nothing axe finds wrong", async ({ page }) => {
    const anchor = await opened(page)
    await page.locator(`[id="kit-row-${anchor}-a-stamp"]`).click()
    await expect.poll(() => focusIn(page, "kit-panel")).toBe(true)
    await expectNoAxeViolations(page)
  })
})

test.describe("the picker in the page", () => {
  test("takes the focus into its table, and Escape takes it away and puts focus back on the cell", async ({
    page,
  }) => {
    const anchor = await opened(page)
    const owner = cell(page, anchor, "owner")
    await owner.focus()
    await page.keyboard.press("Enter")
    const picker = page.locator('[id="kit-picker"]')
    await expect(picker).toHaveAttribute("data-presentation", "inline")
    await expect(picker).toHaveAttribute("role", "region")
    await expect.poll(() => focusIn(page, "kit-pick-owner-table")).toBe(true)
    await page.keyboard.press("Escape")
    await expect(picker).toHaveCount(0)
    await expect(owner).toBeFocused()
  })

  test("has nothing axe finds wrong, and Cancel takes it away", async ({ page }) => {
    const anchor = await opened(page)
    const owner = cell(page, anchor, "owner")
    await owner.focus()
    await page.keyboard.press("Enter")
    await expect.poll(() => focusIn(page, "kit-pick-owner-table")).toBe(true)
    await expectNoAxeViolations(page)
    await page.locator('[id="kit-picker-cancel"]').click()
    await expect(page.locator('[id="kit-picker"]')).toHaveCount(0)
    await expect(owner).toBeFocused()
  })
})

test.describe("the question in the page", () => {
  const question = (page: Page) => page.locator('[id="kit-dialog"]')

  async function asked(page: Page, anchor: string) {
    const button = page.locator(`[id="kit-row-${anchor}-a-destroy"]`)
    await button.focus()
    await page.keyboard.press("Enter")
    await expect(question(page)).toBeVisible()
    await expect(question(page)).toHaveAttribute("data-presentation", "inline")
    await expect(question(page)).toHaveAttribute("role", "region")
    await expect(page.locator('dialog[id="kit-dialog"]')).toHaveCount(0)
    await expect(page.locator('[id="kit-dialog-question"]')).toHaveText("Delete it?")
    // focus on the safe answer
    await expect(question(page).locator("button[value='cancel']")).toBeFocused()
    return button
  }

  test("Escape and Cancel give it up, run nothing, and put focus back on the button", async ({ page }) => {
    const anchor = await opened(page)
    let button = await asked(page, anchor)
    await page.keyboard.press("Escape")
    await expect(question(page)).toBeHidden()
    await expect(button).toBeFocused()
    button = await asked(page, anchor)
    await question(page).locator("button[value='cancel']").click()
    await expect(question(page)).toBeHidden()
    await expect(button).toBeFocused()
    await expect(page.locator(`[id="kit-row-${anchor}"]`)).toHaveCount(1)
  })

  test("Tab leaves it, axe finds nothing wrong, and Confirm runs the action", async ({ page }) => {
    const anchor = await opened(page)
    await asked(page, anchor)
    await expectNoAxeViolations(page)
    await question(page).locator("button[value='confirm']").focus()
    await page.keyboard.press("Tab")
    await expect.poll(() => focusIn(page, "kit-dialog")).toBe(false)
    await expect(question(page)).toBeVisible()
    await question(page).locator("button[value='confirm']").click()
    await expect(question(page)).toBeHidden()
    await expect(page.locator(`[id="kit-row-${anchor}"]`)).toHaveCount(0)
  })
})

test.describe("what opens over the page, with the same kit", () => {
  test("the panel is a modal dialog: focus in, Escape takes it away, focus back", async ({ page }) => {
    const anchor = await opened(page, "?presentation=modal")
    const button = page.locator(`[id="kit-row-${anchor}-a-stamp"]`)
    await button.click()
    const panel = page.locator('dialog[id="kit-panel"]')
    await expect(panel).toHaveAttribute("data-presentation", "modal")
    await expect.poll(() => panel.evaluate((dialog) => (dialog as HTMLDialogElement).open)).toBe(true)
    await expect.poll(() => focusIn(page, "kit-panel")).toBe(true)
    await expectNoAxeViolations(page)
    await page.keyboard.press("Escape")
    await expect(panel).toHaveCount(0)
    await expect(button).toBeFocused()
  })

  test("the picker is a modal dialog: focus in its table, Escape takes it away, focus back", async ({
    page,
  }) => {
    const anchor = await opened(page, "?presentation=modal")
    const owner = cell(page, anchor, "owner")
    await owner.focus()
    await page.keyboard.press("Enter")
    const picker = page.locator('dialog[id="kit-picker"]')
    await expect.poll(() => picker.evaluate((dialog) => (dialog as HTMLDialogElement).open)).toBe(true)
    await expect.poll(() => focusIn(page, "kit-pick-owner-table")).toBe(true)
    await page.keyboard.press("Escape")
    await expect(picker).toHaveCount(0)
    await expect(owner).toBeFocused()
  })
})

test.describe("the grid of divs", () => {
  test("the arrow keys move in it, Enter edits a cell and saves it", async ({ page }) => {
    const anchor = await opened(page)
    const name = cell(page, anchor, "name")
    await name.focus()
    await page.keyboard.press("ArrowRight")
    await expect(cell(page, anchor, "note")).toBeFocused()
    await page.keyboard.press("ArrowLeft")
    await expect(name).toBeFocused()
    await page.keyboard.press("Enter")
    const editor = name.locator("textarea")
    await expect(editor).toBeFocused()
    await editor.fill("Anvil")
    await page.keyboard.press("Enter")
    await expect(name).toHaveText("Anvil")
    await expect(name).toBeFocused()
  })

  test("a row opens its nested table, which Enter goes into and Escape out of", async ({ page }) => {
    const anchor = await opened(page)
    const expander = page.locator(`[id="kit-row-${anchor}-e"]`)
    await expander.focus()
    await page.keyboard.press("Enter")
    const line = page.locator(`[id="kit-row-${anchor}-l-parts-c"]`)
    await expect(line).toBeVisible()
    await page.keyboard.press("ArrowDown")
    await expect(line).toBeFocused()
    await page.keyboard.press("Enter")
    const holder = page.locator(`[id="kit-row-${anchor}-n-parts-c"]`)
    await expect(holder.locator('[role=grid][data-kit="div"]')).toBeAttached()
    await page.keyboard.press("ArrowDown")
    await expect(holder).toBeFocused()
    await page.keyboard.press("Enter")
    await expect.poll(() => holder.evaluate((cell) => cell.querySelector("[role=grid]")?.contains(document.activeElement))).toBe(true)
    await page.keyboard.press("Escape")
    await expect(holder).toBeFocused()
  })
})
