import type { Locator } from "@playwright/test"
import { expectNoAxeViolations } from "./support/a11y"
import { MAPS, SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { Table } from "./support/table"

// What an input says of its limits before anything is saved: a number input
// has the least and the most its constraints allow (`min`, `max`) and its
// steps (`step`), so that the arrows stop there and a screen reader reads
// them. They describe and never judge: a value past them is sent as it was
// typed, and what Ash says of it is shown at the cell or the field, as it
// was before. Only what the browser cannot read as a number at all is held
// back, as it was before.
//
// Text says nothing of its length: the browser would stop the typing, and
// counts differently from Ash.
//
// /specimens has a number of every type with the editor of its type;
// "Repeats" on /tasks is a map whose field "Every" takes 1 to 365; the
// argument "Days" of /tasks takes 0 and more.

const FIRST = SEED.specimens.first
const WEEKLY = MAPS.task.weekly

/** What the browser itself makes of what a control holds. */
async function validity(control: Locator): Promise<Record<string, boolean>> {
  return control.evaluate((element) => {
    const { valid, badInput, rangeOverflow, rangeUnderflow, stepMismatch, tooLong } = (
      element as HTMLInputElement
    ).validity
    return { valid, badInput, rangeOverflow, rangeUnderflow, stepMismatch, tooLong }
  })
}

test.describe("the editor of a number cell", () => {
  let specimens: Table

  test.beforeEach(async ({ page }) => {
    specimens = new Table(page, "specimen", "/specimens")
    await specimens.open()
  })

  test("says the least and the most the number takes, and its steps", async () => {
    const integer = specimens.cell(FIRST, "an_integer")
    await integer.focus()
    await specimens.press("Enter")
    const editor = specimens.editor(integer)
    await expect(editor).toHaveAttribute("min", "-1000")
    await expect(editor).toHaveAttribute("max", "1000")
    await expect(editor).toHaveAttribute("step", "1")
    await expect(editor).toHaveAttribute("aria-required", "true")
    // the browser's own word for it is never used: nothing is checked by it
    await expect(editor).not.toHaveAttribute("required")
    await specimens.press("Escape")

    const float = specimens.cell(FIRST, "a_float")
    await float.focus()
    await specimens.press("Enter")
    await expect(specimens.editor(float)).toHaveAttribute("min", "0.0")
    await expect(specimens.editor(float)).toHaveAttribute("max", "1.0")
    await expect(specimens.editor(float)).toHaveAttribute("step", "any")
    await specimens.press("Escape")

    // one that may be empty, without constraints
    const optional = specimens.cell(FIRST, "opt_integer")
    await optional.focus()
    await specimens.press("Enter")
    await expect(specimens.editor(optional)).not.toHaveAttribute("min")
    await expect(specimens.editor(optional)).not.toHaveAttribute("max")
    await expect(specimens.editor(optional)).not.toHaveAttribute("aria-required")
  })

  test("the number field's own Up and Down stop at the limit", async ({ page }) => {
    const integer = specimens.cell(FIRST, "an_integer")
    await integer.focus()
    await specimens.press("Enter")
    const editor = specimens.editor(integer)

    // the number field's own keys
    await editor.fill("999")
    await page.keyboard.press("ArrowUp")
    await expect(editor).toHaveValue("1000")
    await page.keyboard.press("ArrowUp")
    await expect(editor, "the most it takes").toHaveValue("1000")

    await editor.fill("-1000")
    await page.keyboard.press("ArrowDown")
    await expect(editor, "the least it takes").toHaveValue("-1000")
    await specimens.press("Escape")
  })

  for (const theme of ["light", "dark"] as const) {
    test(`a number past its limit is typed, sent and refused by Ash, at the cell (${theme})`, async ({
      page,
      pushed,
    }) => {
      await page.addInitScript((theme) => localStorage.setItem("phx:theme", theme), theme)
      await specimens.open()
      await expect(page.locator("html")).toHaveAttribute("data-theme", theme)

      const integer = specimens.cell(FIRST, "an_integer")
      await integer.focus()
      await specimens.press("Enter")
      const editor = specimens.editor(integer)
      await editor.fill("5000")
      // the browser knows, and holds nothing back
      expect(await validity(editor)).toMatchObject({ valid: false, rangeOverflow: true })
      await expectNoAxeViolations(page)

      await pushed.clear()
      await specimens.saves(integer, () => specimens.press("Enter"))

      expect(await pushed.count("save")).toBe(1)
      await expect(integer).toHaveAttribute("data-failed")
      await expect(specimens.failure(integer)).toHaveText("must be less than or equal to 1000")
      await expect(integer).toContainText("5000")
      await expectNoAxeViolations(page)
    })
  }

  test("a fraction in a whole number is sent and refused by Ash too", async ({ pushed }) => {
    const integer = specimens.cell(FIRST, "an_integer")
    await integer.focus()
    await specimens.press("Enter")
    const editor = specimens.editor(integer)
    await editor.fill("1.5")
    expect(await validity(editor)).toMatchObject({ valid: false, stepMismatch: true })

    await pushed.clear()
    await specimens.saves(integer, () => specimens.press("Enter"))

    expect(await pushed.count("save")).toBe(1)
    await expect(integer).toHaveAttribute("data-failed")
    await expect(specimens.failure(integer)).not.toBeEmpty()
  })
})

test.describe("the editor of a text cell", () => {
  test("has no limit of the browser's: text past the length Ash takes is typed in full, and Ash says so", async ({
    page,
  }) => {
    const specimens = new Table(page, "specimen", "/specimens")
    await specimens.open()
    // `a_string` takes 2 to 50 characters
    const text = specimens.cell(FIRST, "a_string")
    await text.focus()
    await specimens.press("Enter")
    const editor = specimens.editor(text)
    await expect(editor).not.toHaveAttribute("maxlength")
    await expect(editor).not.toHaveAttribute("minlength")

    const long = "x".repeat(51)
    await editor.fill("")
    await page.keyboard.type(long)
    await expect(editor, "nothing stops the typing").toHaveValue(long)
    await specimens.saves(text, () => specimens.press("Enter"))

    await expect(text).toHaveAttribute("data-failed")
    await expect(specimens.failure(text)).toHaveText("length must be less than or equal to 50")
  })

  test("takes text of the length Ash takes that a limit of the browser's would cut: 50 characters of two code units each", async ({
    page,
  }) => {
    const specimens = new Table(page, "specimen", "/specimens")
    await specimens.open()
    const text = specimens.cell(FIRST, "a_string")
    await text.focus()
    await specimens.press("Enter")
    const editor = specimens.editor(text)

    // 50 characters to Ash, 100 to a browser's `maxlength`
    const fifty = "😀".repeat(50)
    expect(fifty.length).toBe(100)
    await editor.fill(fifty)
    await specimens.saves(text, () => specimens.press("Enter"))

    await expect(text).not.toHaveAttribute("data-failed")
    await expect(text).toHaveText(fifty)
  })
})

test.describe("a number field of the action panel", () => {
  test.beforeEach(async ({ tasks }) => {
    await tasks.open()
    await tasks.cell(WEEKLY.id, "recurrence").dblclick()
    await expect(tasks.panel).toBeVisible()
  })

  test("says its limits, in a form the browser does not check", async ({ tasks }) => {
    const every = tasks.panel.getByRole("spinbutton", { name: "Every" })
    await expect(every).toHaveAttribute("min", "1")
    await expect(every).toHaveAttribute("max", "365")
    await expect(every).toHaveAttribute("step", "1")
    await expect(every).toHaveAttribute("aria-required", "true")
    await expect(every).not.toHaveAttribute("required")
    await expect(tasks.panelForm).toHaveAttribute("novalidate", "")
  })

  for (const theme of ["light", "dark"] as const) {
    test(`a number past its limit is sent when Save is used, and refused by Ash at the field (${theme})`, async ({
      page,
      tasks,
      pushed,
    }) => {
      await page.addInitScript((theme) => localStorage.setItem("phx:theme", theme), theme)
      await tasks.open()
      await expect(page.locator("html")).toHaveAttribute("data-theme", theme)
      await tasks.cell(WEEKLY.id, "recurrence").dblclick()

      const every = tasks.panel.getByRole("spinbutton", { name: "Every" })
      await every.fill("400")
      expect(await validity(every)).toMatchObject({ valid: false, rangeOverflow: true })
      await tasks.panelSettled()
      await expectNoAxeViolations(page)

      await pushed.clear()
      await tasks.panelSubmit.click()
      await tasks.question.getByRole("button", { name: "Confirm" }).click()
      await tasks.panelSettled()

      expect(await pushed.count("panel_submit")).toBe(1)
      await expect(tasks.panel).toBeVisible()
      await expect(every).toHaveValue("400")
      await expect(every).toHaveAttribute("aria-invalid", "true")
      await expect(every).toHaveAccessibleDescription("must be less than or equal to 365")
      await expectNoAxeViolations(page)
    })
  }

  test("what the browser cannot read as a number is still held back, and never sent as nothing", async ({
    tasks,
    pushed,
  }) => {
    const every = tasks.panel.getByRole("spinbutton", { name: "Every" })
    await every.fill("")
    // digits, then a sign where none can be: no number
    await every.pressSequentially("1e")
    expect(await validity(every)).toMatchObject({ valid: false, badInput: true })
    await expect(every, "which the control gives as nothing").toHaveValue("")
    await tasks.panelSettled()

    await pushed.clear()
    await tasks.panelSubmit.click()

    // once the server has heard everything the page pushed so far
    expect(await pushed.count("panel_submit")).toBe(0)
    await expect(tasks.question).toBeHidden()
    await expect(tasks.panel).toBeVisible()
    await expect(every).toBeFocused()
    await expect(tasks.cell(WEEKLY.id, "recurrence")).toHaveText(WEEKLY.recurrence)
  })
})

test.describe("a number of the argument line", () => {
  test.beforeEach(async ({ tasks }) => {
    await tasks.open()
  })

  test("says its limits, in a form the browser does not check", async ({ tasks }) => {
    const days = tasks.argument("due_within-days")
    await expect(days).toHaveAttribute("min", "0")
    await expect(days).not.toHaveAttribute("max")
    await expect(days).toHaveAttribute("step", "1")
    await expect(days).not.toHaveAttribute("required")
    await expect(tasks.argumentLine).toHaveAttribute("novalidate", "")
    // text is one line, and says nothing of itself
    await expect(tasks.argument("search")).not.toHaveAttribute("maxlength")
  })

  test("the number field's own Up and Down stop at the limit", async ({ page, tasks }) => {
    const days = tasks.argument("due_within-days")
    // the number field's own keys
    await days.fill("1")
    await page.keyboard.press("ArrowDown")
    await expect(days).toHaveValue("0")
    await page.keyboard.press("ArrowDown")
    await expect(days, "the least it takes").toHaveValue("0")
  })

  test("a number past its limit is sent on Enter and refused by Ash at the input", async ({
    tasks,
    pushed,
  }) => {
    const days = tasks.argument("due_within-days")
    await days.fill("-1")
    expect(await validity(days)).toMatchObject({ valid: false, rangeUnderflow: true })

    await pushed.clear()
    await days.press("Enter")

    await expect(tasks.argumentError("due_within-days")).toHaveText(
      "must be greater than or equal to 0",
    )
    // the change of the input, and the line itself
    expect(await pushed.count("arguments")).toBeGreaterThan(0)
    await expect(days).toHaveValue("-1")
  })

  test("what the browser cannot read as a number is still held back on Enter", async ({
    tasks,
    pushed,
  }) => {
    const days = tasks.argument("due_within-days")
    await days.fill("")
    await days.pressSequentially("1e")
    expect(await validity(days)).toMatchObject({ valid: false, badInput: true })

    await pushed.clear()
    await days.press("Enter")

    // once the server has heard everything the page pushed so far
    expect(await pushed.count("arguments")).toBe(0)
    await expect(days).toBeFocused()
    await expect(tasks.argumentError("due_within-days")).toHaveCount(0)
  })
})
