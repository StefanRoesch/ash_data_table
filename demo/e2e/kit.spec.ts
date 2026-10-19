import type { Page } from "@playwright/test"
import { expectNoAxeViolations } from "./support/a11y"
import { expect, test } from "./support/fixtures"
import { Table } from "./support/table"

// A kit of one's own:
// /e2e/kit draws a table of `AshDataTable.Test.Resource` with the demo's
// kit of `div`s (`DemoWeb.DivKit`), whose action panel and picker open in
// the page (`data-presentation="inline"`), or over it with
// `?presentation=modal`, or the panel and the picker over the page with
// the question in it (`?presentation=mixed`), or the panel over the page
// with the picker and the question in it (`?presentation=inside`). What
// opens: focus goes in, Escape and Cancel take it away and put focus back
// on what opened it, and Tab leaves what is inline; axe finds nothing wrong
// either way. One question at a time: a new one gives up the one that is
// open. The grid of `div`s: the arrow keys, editing, a nested table.

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
  // connected: the join's patch, which mounts the hooks, is in the page
  await expect(page.locator(".phx-connected").first()).toBeAttached()
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

test.describe("the question in the page, asked from a panel over it", () => {
  test("is shown inside the panel, takes the focus, and Escape and Cancel give it up there", async ({ page }) => {
    const anchor = await opened(page, "?presentation=mixed")
    // the panel of a map cell, which asks before it saves a change
    await cell(page, anchor, "place").focus()
    await page.keyboard.press("Enter")
    const panel = page.locator('dialog[id="kit-panel"]')
    await expect.poll(() => panel.evaluate((dialog) => (dialog as HTMLDialogElement).open)).toBe(true)
    await panel.locator('[data-field="place.city"] :is(input, textarea)').fill("Thun")
    const submit = page.locator('[id="kit-panel-submit"]')
    // the place the server draws for it inside the panel
    const question = panel.locator('[id="kit-dialog-in-panel"]')
    await expect(question).toBeHidden()
    for (const answer of ["Escape", "cancel"]) {
      await submit.click()
      await expect(question).toBeVisible()
      await expect(question).toHaveAttribute("role", "region")
      await expect(question).toHaveAttribute("data-presentation", "inline")
      await expect(question.locator('[id="kit-dialog-question-in-panel"]')).toHaveText("Change the place?")
      await expect(question.locator("button[value='cancel']")).toBeFocused()
      if (answer === "Escape") {
        await expectNoAxeViolations(page)
        await page.keyboard.press("Escape")
      } else await question.locator("button[value='cancel']").click()
      await expect(question).toBeHidden()
      // the panel stays open, and focus is back on its button
      await expect.poll(() => panel.evaluate((dialog) => (dialog as HTMLDialogElement).open)).toBe(true)
      await expect(submit).toBeFocused()
    }
    // the question of the page itself was not shown
    await expect(page.locator('[id="kit-dialog"]')).toBeHidden()
  })
})

test.describe("one question at a time", () => {
  const question = (page: Page) => page.locator('[id="kit-dialog"]')

  /** Selects the row of `key` and asks to run "Delete" on it: the question is open. */
  async function bulkAsked(page: Page, key: string) {
    await page.locator(`[id="kit-row-${key}-s"] input`).click()
    // after the first two of its actions on the selection, in the menu "More"
    const more = page.locator('[id="kit-bulk-more-button"]')
    if ((await page.locator('[id="kit-bulk-more"] [data-bulk="destroy"]').count()) > 0) await more.click()
    await page.locator("[data-bulk='destroy']").click()
    await expect(question(page)).toBeVisible()
    await expect(page.locator('[id="kit-dialog-question"]')).toContainText("Delete it?")
  }

  test("a table action asked while a question about the selection is open shows its own, and the first runs nothing", async ({
    page,
    pushed,
  }) => {
    const anchor = await opened(page)
    await bulkAsked(page, anchor)
    await pushed.clear()

    await page.locator('[id="kit-do-greet"]').click()
    await expect(page.locator('[id="kit-dialog-question"]')).toHaveText("Greet everyone?")
    await expect(question(page).locator("button[value='cancel']")).toBeFocused()
    await question(page).locator("button[value='confirm']").click()
    await expect(question(page)).toBeHidden()

    await expect.poll(() => pushed.count("table_run")).toBe(1)
    expect(await pushed.count("bulk_run")).toBe(0)
    await expect(page.locator(`[id="kit-row-${anchor}"]`)).toHaveCount(1)
  })

  test("a question about the selection is given up when the selection changes, and runs nothing", async ({
    page,
    pushed,
  }) => {
    const anchor = await opened(page)
    const bolt = await key(page, "Bolt")
    await bulkAsked(page, anchor)
    await pushed.clear()

    // Tab leaves the question in the page, and the selection changes
    await page.locator(`[id="kit-row-${bolt}-s"] input`).click()
    await expect(question(page)).toBeHidden()
    expect(await pushed.count("bulk_run")).toBe(0)
    await expect(page.locator(`[id="kit-row-${anchor}"]`)).toHaveCount(1)
    await expect(page.locator(`[id="kit-row-${bolt}"]`)).toHaveCount(1)
  })
})

test.describe("the question in the page, asked from a panel over it, answered there", () => {
  async function asked(page: Page) {
    const anchor = await opened(page, "?presentation=mixed")
    await cell(page, anchor, "place").focus()
    await page.keyboard.press("Enter")
    const panel = page.locator('dialog[id="kit-panel"]')
    await expect.poll(() => panel.evaluate((dialog) => (dialog as HTMLDialogElement).open)).toBe(true)
    await panel.locator('[data-field="place.city"] :is(input, textarea)').fill("Thun")
    await page.locator('[id="kit-panel-submit"]').click()
    const copy = panel.locator('[id="kit-dialog-in-panel"]')
    await expect(copy).toBeVisible()
    return { anchor, panel, copy }
  }

  test("Confirm inside the panel saves, and the panel goes", async ({ page }) => {
    const { anchor, panel, copy } = await asked(page)
    await copy.locator("button[value='confirm']").click()
    await expect(panel).toHaveCount(0)
    await expect(cell(page, anchor, "place")).toContainText("Thun")
    await expect(cell(page, anchor, "place")).toBeFocused()
  })

  test("a patch of the panel leaves the question as it is, and the panel that goes while it asks answers it as Cancel: nothing is saved", async ({
    page,
    pushed,
  }) => {
    const { anchor, panel, copy } = await asked(page)
    await pushed.clear()
    // the server draws the panel again; the question's place is the hook's
    await new Table(page, "kit", "/e2e/kit").forge("panel_validate", { panel: { place: { city: "Thun", zip: "3000" } } })
    await expect.poll(() => pushed.count("panel_validate")).toBe(1)
    await expect(copy).toBeVisible()
    await expect(copy.locator('[id="kit-dialog-question-in-panel"]')).toHaveText("Change the place?")
    expect(await pushed.count("panel_submit")).toBe(0)
    // the panel's own Cancel takes the panel, and the question in it, away
    await page.locator('[id="kit-panel-cancel"]').click()
    await expect(panel).toHaveCount(0)
    expect(await pushed.count("panel_submit")).toBe(0)
    await expect(cell(page, anchor, "place")).toContainText("Bern")
    // the question of the page itself was not shown
    await expect(page.locator('[id="kit-dialog"]')).toBeHidden()
  })
})

test.describe("the question in the page, asked from a picker over it", () => {
  async function asked(page: Page) {
    const anchor = await opened(page, "?presentation=mixed")
    const owner = cell(page, anchor, "owner")
    await expect(owner).toContainText("Ann")
    await owner.focus()
    await page.keyboard.press("Enter")
    const picker = page.locator('dialog[id="kit-picker"]')
    await expect.poll(() => picker.evaluate((dialog) => (dialog as HTMLDialogElement).open)).toBe(true)
    await expect.poll(() => focusIn(page, "kit-pick-owner-table")).toBe(true)
    // the place the server draws for it inside the picker
    const question = picker.locator('[id="kit-dialog-in-picker"]')
    await expect(question).toBeHidden()
    await picker.locator("[role=rowgroup]").filter({ hasText: "Bob" }).locator("[data-selector] input").click()
    const choose = page.locator('[id="kit-picker-choose"]')
    // the server draws Choose from what the picker's table selected
    await expect(choose).not.toHaveAttribute("aria-disabled", "true")
    await choose.click()
    await expect(question).toBeVisible()
    return { anchor, owner, picker, question }
  }

  test("is shown inside the picker, takes the focus, and Escape gives it up there", async ({ page, pushed }) => {
    const { owner, picker, question } = await asked(page)
    await expect(question).toHaveAttribute("role", "region")
    await expect(question).toHaveAttribute("data-presentation", "inline")
    await expect(question.locator('[id="kit-dialog-question-in-picker"]')).toHaveText("Change the owner?")
    await expect(question.locator("button[value='cancel']")).toBeFocused()
    await expectNoAxeViolations(page)
    await pushed.clear()
    await page.keyboard.press("Escape")
    await expect(question).toBeHidden()
    // the picker stays open, focus is in it, and nothing was chosen
    await expect.poll(() => picker.evaluate((dialog) => (dialog as HTMLDialogElement).open)).toBe(true)
    await expect.poll(() => focusIn(page, "kit-picker")).toBe(true)
    expect(await pushed.count("picked")).toBe(0)
    await expect(owner).toContainText("Ann")
    // the question of the page itself was not shown
    await expect(page.locator('[id="kit-dialog"]')).toBeHidden()
  })

  test("Confirm inside the picker chooses, and the picker goes", async ({ page }) => {
    const { owner, picker, question } = await asked(page)
    await question.locator("button[value='confirm']").click()
    await expect(picker).toHaveCount(0)
    await expect(owner).toContainText("Bob")
    await expect(owner).toBeFocused()
  })
})

test.describe("the picker in the page, opened from a panel over it", () => {
  test("is drawn inside the panel, takes the focus, and Escape takes it away and leaves the panel open", async ({
    page,
  }) => {
    const anchor = await opened(page, "?presentation=inside")
    await page.locator(`[id="kit-row-${anchor}-a-staff"]`).click()
    const panel = page.locator('dialog[id="kit-panel"]')
    await expect.poll(() => panel.evaluate((dialog) => (dialog as HTMLDialogElement).open)).toBe(true)
    const choose = panel.locator('[id="kit-panel-f-helpers-choose"]')
    await choose.click()
    const picker = panel.locator('[id="kit-picker"]')
    await expect(picker).toHaveAttribute("data-presentation", "inline")
    await expect(picker).toHaveAttribute("role", "region")
    await expect.poll(() => focusIn(page, "kit-pick-helpers-table")).toBe(true)
    await expectNoAxeViolations(page)
    await page.keyboard.press("Escape")
    await expect(picker).toHaveCount(0)
    await expect.poll(() => panel.evaluate((dialog) => (dialog as HTMLDialogElement).open)).toBe(true)
    await expect(choose).toBeFocused()
  })

  test("a record chosen in it is the field's, and the panel's Cancel is the panel's own", async ({ page }) => {
    const anchor = await opened(page, "?presentation=inside")
    await page.locator(`[id="kit-row-${anchor}-a-staff"]`).click()
    const panel = page.locator('dialog[id="kit-panel"]')
    await expect.poll(() => panel.evaluate((dialog) => (dialog as HTMLDialogElement).open)).toBe(true)
    const field = panel.locator('[data-field="helpers"]')
    await expect(field).toContainText("Bob")
    await page.locator('[id="kit-panel-f-helpers-choose"]').click()
    const picker = panel.locator('[id="kit-picker"]')
    await expect.poll(() => focusIn(page, "kit-pick-helpers-table")).toBe(true)
    await picker.locator('[role=rowgroup]').filter({ hasText: "Ann" }).locator("[data-selector] input").click()
    await picker.locator("[data-take]").click()
    await expect(picker).toHaveCount(0)
    await expect(field).toContainText("Ann")
    await expect.poll(() => panel.evaluate((dialog) => (dialog as HTMLDialogElement).open)).toBe(true)
    await page.locator('[id="kit-panel-cancel"]').click()
    await expect(panel).toHaveCount(0)
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
