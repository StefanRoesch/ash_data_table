import type { Locator, Page } from "@playwright/test"
import { expectNoAxeViolations } from "./support/a11y"
import { expect, test } from "./support/fixtures"
import { switchLocale } from "./support/locale"
import { Table } from "./support/table"

// A union in a browser: "A union" at /specimens is a number, a text, a
// shade or an address. Its cell shows the value it holds and nothing of the
// kind; it is edited in the side panel, where the kind is chosen first and
// that kind's fields follow. Anyone may edit a specimen. These tests save.

/** Specimens of the seed by what their union holds: the first rows of /specimens. */
const NUMBER = { id: "2b63fed9-48ab-4270-aa82-3d81c7cbafae", shown: "969" }
const ADDRESS = {
  id: "85ddfce1-41d0-481c-9838-8376c7d9b6db",
  shown: "Street: Unionsweg 559, City: Leipzig, Primary?: No",
}
const SHADE = { id: "cbde76d0-28c4-4bdb-84f2-0da2e8db7907", shown: "Light" }
const TEXT = { id: "77e2dc17-630b-4dd3-afb7-2bd379af9ed5", shown: "chore" }

function specimensOf(page: Page): Table {
  return new Table(page, "specimen", "/specimens")
}

/** The union's group in the panel, the choice of its kind, and a field of the kind. */
function union(table: Table): Locator {
  return table.panel.getByRole("group", { name: "A union", exact: true })
}

function kind(table: Table): Locator {
  return union(table).getByRole("combobox", { name: "Kind", exact: true })
}

test.describe("the cell of a union", () => {
  test("shows the value it holds as plain text, as its kind is shown, and nothing of the kind", async ({ page }) => {
    const specimens = specimensOf(page)
    await specimens.open()

    for (const specimen of [NUMBER, ADDRESS, SHADE, TEXT]) {
      const cell = specimens.cell(specimen.id, "a_union")
      await expect(cell).toHaveText(specimen.shown)
      await expect(cell.locator("*")).toHaveCount(0)
      await expect(cell).not.toHaveAttribute("aria-readonly")
    }
  })

  test("has neither a sort nor a filter", async ({ page, pushed }) => {
    const specimens = specimensOf(page)
    await specimens.open()

    await expect(specimens.header("a_union")).not.toHaveAttribute("aria-sort")
    await expect(specimens.filterCell("a_union").locator("input, select, button")).toHaveCount(0)
    await pushed.clear()
    await specimens.header("a_union").click()
    expect(await pushed.all()).toEqual([])
  })
})

test.describe("the side panel of a union", () => {
  test("Enter opens it with the kind chosen and that kind's value; a key that types does not; Escape closes it, and focus is on the cell again", async ({
    page,
    pushed,
  }) => {
    const specimens = specimensOf(page)
    await specimens.open()
    const cell = specimens.cell(NUMBER.id, "a_union")

    await cell.focus()
    await pushed.clear()
    await specimens.press("7", "x")
    await expect(specimens.panel).toHaveCount(0)
    expect(await pushed.all()).toEqual([])

    await specimens.press("Enter")
    await expect(specimens.panel).toBeVisible()
    expect(await specimens.panel.evaluate((panel) => panel.matches(":modal"))).toBe(true)
    await expect(specimens.panel).toHaveAccessibleName(`A union: ${NUMBER.id}`)
    await expect(specimens.panelSubmit).toHaveText("Save")

    // the kind first, and it has the focus
    await expect(kind(specimens)).toBeFocused()
    await expect(kind(specimens).locator("option")).toHaveText(["", "Number", "Text", "Shade", "Address"])
    await expect(kind(specimens)).toHaveValue("number")
    await expect(union(specimens).getByRole("spinbutton", { name: "Number", exact: true })).toHaveValue("969")
    expect(await specimens.fields()).toEqual(["a_union", "a_union._union_type", "a_union._union_value"])

    await page.keyboard.press("Escape")
    await expect(specimens.panel).toHaveCount(0)
    await expect(cell).toBeFocused()
    await expect(cell).toHaveText(NUMBER.shown)
    expect(await pushed.count("panel_submit")).toBe(0)
  })

  test("a kind made of fields has those fields; F2 and a double click open the panel too", async ({ page }) => {
    const specimens = specimensOf(page)
    await specimens.open()
    const cell = specimens.cell(ADDRESS.id, "a_union")

    await cell.focus()
    await specimens.press("F2")
    await expect(specimens.panel).toBeVisible()
    await expect(kind(specimens)).toHaveValue("address")
    await expect(union(specimens).getByRole("textbox", { name: "Street" })).toHaveValue("Unionsweg 559")
    await expect(union(specimens).getByRole("textbox", { name: "City" })).toHaveValue("Leipzig")
    await expect(union(specimens).getByRole("checkbox", { name: "Primary?" })).not.toBeChecked()
    expect(await specimens.fields()).toEqual([
      "a_union",
      "a_union._union_type",
      "a_union._union_value.street",
      "a_union._union_value.city",
      "a_union._union_value.postcode",
      "a_union._union_value.primary?",
    ])
    await specimens.panelCancel.click()
    await expect(specimens.panel).toHaveCount(0)
    await expect(cell).toBeFocused()

    await cell.dblclick()
    await expect(specimens.panel).toBeVisible()
    await expect(kind(specimens)).toBeFocused()
  })

  test("choosing another kind puts that kind's fields in place of the others, empty, and the choice keeps the focus", async ({
    page,
  }) => {
    const specimens = specimensOf(page)
    await specimens.open()
    await specimens.cell(NUMBER.id, "a_union").dblclick()

    await kind(specimens).selectOption("Text")
    const text = union(specimens).getByRole("textbox", { name: "Text", exact: true })
    await expect(text).toHaveValue("")
    await expect(union(specimens).getByRole("spinbutton")).toHaveCount(0)
    await expect(kind(specimens)).toBeFocused()

    await kind(specimens).selectOption("Shade")
    const shade = union(specimens).getByRole("combobox", { name: "Shade", exact: true })
    await expect(shade.locator("option")).toHaveText(["", "Light", "Medium", "Dark"])
    await expect(shade).toHaveValue("")
    await expect(text).toHaveCount(0)

    await kind(specimens).selectOption("Address")
    await expect(union(specimens).getByRole("textbox", { name: "Street" })).toHaveValue("")
    await expect(union(specimens).getByRole("textbox", { name: "Street" })).toHaveAttribute("aria-required", "true")
    await expect(shade).toHaveCount(0)

    // no kind: nothing but the choice
    await kind(specimens).selectOption("")
    await specimens.panelSettled()
    expect(await specimens.fields()).toEqual(["a_union", "a_union._union_type"])

    // and back: the number that was there is not, nothing was saved
    await kind(specimens).selectOption("Number")
    await expect(union(specimens).getByRole("spinbutton", { name: "Number", exact: true })).toHaveValue("")
    await page.keyboard.press("Escape")
    await expect(specimens.cell(NUMBER.id, "a_union")).toHaveText(NUMBER.shown)
  })
})

test.describe("Save", () => {
  test("by keyboard alone: another kind, its value, Enter; the cell shows it and has the focus", async ({
    page,
    pushed,
  }) => {
    const specimens = specimensOf(page)
    await specimens.open()
    const cell = specimens.cell(NUMBER.id, "a_union")

    await cell.focus()
    await specimens.press("Enter")
    await expect(kind(specimens)).toBeFocused()
    // the next kind in the list
    await page.keyboard.press("ArrowDown")
    await expect(kind(specimens)).toHaveValue("text")
    const text = union(specimens).getByRole("textbox", { name: "Text", exact: true })
    await expect(text).toBeVisible()
    await page.keyboard.press("Tab")
    await expect(text).toBeFocused()
    await page.keyboard.type("by keyboard")
    await specimens.panelSettled()
    await pushed.clear()
    await page.keyboard.press("Tab")
    await expect(specimens.panelCancel).toBeFocused()
    await page.keyboard.press("Tab")
    await expect(specimens.panelSubmit).toBeFocused()
    await page.keyboard.press("Enter")

    await expect(specimens.panel).toHaveCount(0)
    await expect(cell).toHaveText("by keyboard")
    await expect(cell).toBeFocused()
    expect(await pushed.count("panel_submit")).toBe(1)

    // it is stored: the page shows it again after a reload
    await specimens.open()
    await expect(specimens.cell(NUMBER.id, "a_union")).toHaveText("by keyboard")
  })

  test("a kind made of fields, in place of a number", async ({ page }) => {
    const specimens = specimensOf(page)
    await specimens.open()
    const cell = specimens.cell(NUMBER.id, "a_union")

    await cell.dblclick()
    await kind(specimens).selectOption("Address")
    await union(specimens).getByRole("textbox", { name: "Street" }).fill("Kai 1")
    await union(specimens).getByRole("textbox", { name: "City" }).fill("Kiel")
    await union(specimens).getByRole("checkbox", { name: "Primary?" }).check()
    await specimens.panelSubmit.click()

    await expect(specimens.panel).toHaveCount(0)
    await expect(cell).toHaveText("Street: Kai 1, City: Kiel, Primary?: Yes")
  })

  test("no kind takes the value away, and the panel then opens without one", async ({ page }) => {
    const specimens = specimensOf(page)
    await specimens.open()
    const cell = specimens.cell(SHADE.id, "a_union")

    await cell.dblclick()
    await expect(union(specimens).getByRole("combobox", { name: "Shade", exact: true })).toHaveValue("light")
    await kind(specimens).selectOption("")
    await specimens.panelSubmit.click()
    await expect(specimens.panel).toHaveCount(0)
    await expect(cell).toBeEmpty()

    await cell.dblclick()
    await expect(kind(specimens)).toHaveValue("")
    expect(await specimens.fields()).toEqual(["a_union", "a_union._union_type"])
  })

  test("unchanged sends the form and saves nothing; the panel closes", async ({ page }) => {
    const specimens = specimensOf(page)
    await specimens.open()
    const updated = await specimens.cell(TEXT.id, "updated_at").textContent()

    await specimens.cell(TEXT.id, "a_union").dblclick()
    await specimens.panelSubmit.click()
    await expect(specimens.panel).toHaveCount(0)
    await expect(specimens.cell(TEXT.id, "updated_at")).toHaveText(updated!)
  })

  for (const theme of ["light", "dark"] as const) {
    test(`what the action says of the value is shown at the value's field, and of a field of a kind at that field (${theme})`, async ({
      page,
    }) => {
      await page.addInitScript((theme) => localStorage.setItem("phx:theme", theme), theme)
      const specimens = specimensOf(page)
      await specimens.open()
      await expect(page.locator("html")).toHaveAttribute("data-theme", theme)
      const cell = specimens.cell(NUMBER.id, "a_union")

      await cell.dblclick()
      await expect(specimens.panel).toBeVisible()
      await expectNoAxeViolations(page)

      const number = union(specimens).getByRole("spinbutton", { name: "Number", exact: true })
      await number.fill("-3")
      await specimens.panelSubmit.click()
      await specimens.panelSettled()

      await expect(specimens.panel).toBeVisible()
      await expect(number).toHaveAttribute("aria-invalid", "true")
      await expect(number).toHaveAccessibleDescription("must be greater than or equal to 0")
      await expect(specimens.root.locator('[id="specimen-status"]')).toHaveText(
        "A union was not saved: A union: must be greater than or equal to 0",
      )
      await expectNoAxeViolations(page)

      // a kind made of fields: at the field that is wrong
      await kind(specimens).selectOption("Address")
      const street = union(specimens).getByRole("textbox", { name: "Street" })
      await expect(street).toHaveValue("")
      await union(specimens).getByRole("textbox", { name: "City" }).fill("Kiel")
      await specimens.panelSubmit.click()
      await specimens.panelSettled()

      await expect(street).toHaveAttribute("aria-invalid", "true")
      await expect(street).toHaveAccessibleDescription("is required")
      await expect(union(specimens).getByRole("textbox", { name: "City" })).not.toHaveAttribute("aria-invalid")
      await expectNoAxeViolations(page)

      await page.keyboard.press("Escape")
      await expect(cell).toHaveText(NUMBER.shown)
    })
  }
})

test.describe("in German", () => {
  test("the choice of the kind and the kinds are in the table's language", async ({ page }) => {
    const specimens = specimensOf(page)
    await specimens.open()
    await switchLocale(page, "de")
    await specimens.ready()

    await specimens.cell(ADDRESS.id, "a_union").dblclick()
    const art = specimens.panel.getByRole("combobox", { name: "Art", exact: true })
    await expect(art.locator("option")).toHaveText(["", "Zahl", "Text", "Farbton", "Adresse"])
    await expect(art).toHaveValue("address")
    await expect(specimens.panel.getByRole("textbox", { name: "Straße" })).toHaveValue("Unionsweg 559")
    await expect(specimens.panelSubmit).toHaveText("Speichern")
  })
})
