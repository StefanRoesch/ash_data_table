import type { Locator } from "@playwright/test"
import { expectNoAxeViolations } from "./support/a11y"
import { SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { Table } from "./support/table"

// The array columns of /tasks as the admin, who may change every task:
// "Tags", an array of text with at most five values of two to twenty
// characters, edited value by value; and "Checks", an array of enum values,
// edited as multiple choice. A cell of an array has no editor of its own:
// Enter, a double click or a key typed on it opens the table's side
// panel with that one field, a form of the column's update action. "Save"
// saves; Cancel and Escape close it, and the focus is on the cell again.
// These tests save.

// tags: api, customer, quick-win; checks: Reviewed, Released
const FIRST = SEED.task.first
// tags: backend; checks: Released
const SECOND = SEED.task.second

const TOO_SHORT = "length must be greater than or equal to 2"

test.beforeEach(async ({ tasks }) => {
  await tasks.open()
})

/** The controls of the values of an array's field, top to bottom. */
function values(field: Locator): Locator {
  return field.locator("[data-item] textarea")
}

/** The boxes of a multiple choice, top to bottom. */
function boxes(field: Locator): Locator {
  return field.getByRole("checkbox")
}

/** What the boxes say: each label with whether it is ticked. */
async function ticks(field: Locator): Promise<string[]> {
  return field.locator("label").evaluateAll((labels) =>
    labels.map((label) => {
      const box = label.querySelector("input") as HTMLInputElement
      return `${box.checked ? "x" : " "} ${label.textContent!.trim()}`
    }),
  )
}

/** Opens the side panel of a cell with a key, and returns the field of its values. */
async function edit(table: Table, cell: Locator, column: string, key = "Enter"): Promise<Locator> {
  await cell.focus()
  await table.press(key)
  await expect(table.panel).toBeVisible()
  return table.field(column)
}

/** "Save" in the side panel; the panel is gone after. */
async function save(table: Table): Promise<void> {
  await table.panelSettled()
  await table.panelSubmit.click()
  await expect(table.panel).toHaveCount(0)
}

/** The first row of the page whose cell of a column is empty. */
async function emptyCell(tasks: Table, column: string): Promise<Locator> {
  const keys = await tasks.rowKeys()
  const texts = await tasks.columnTexts(column)
  const index = texts.findIndex((text) => text === "")
  expect(index, `a row without ${column} on the first page`).toBeGreaterThanOrEqual(0)
  return tasks.cell(keys[index], column)
}

test.describe("an array cell", () => {
  test("shows its values as plain text, separated by commas: nothing else is in the cell", async ({
    tasks,
  }) => {
    const tags = tasks.cell(FIRST, "tags")
    const checks = tasks.cell(FIRST, "checks")

    await expect(tags).toHaveText("api, customer, quick-win")
    // the labels of the enum's values
    await expect(checks).toHaveText("Reviewed, Released")
    await expect(tags.locator("*")).toHaveCount(0)
    await expect(checks.locator("*")).toHaveCount(0)

    // an array without values is an empty cell
    await expect(await emptyCell(tasks, "tags")).toBeEmpty()
    await expect(await emptyCell(tasks, "checks")).toBeEmpty()
  })

  test("has neither a sort nor a filter: its header and its filter cell are no stops; its cell is one", async ({
    tasks,
    pushed,
  }) => {
    for (const column of ["tags", "checks"]) {
      await expect(tasks.header(column)).not.toHaveAttribute("aria-sort")
      await expect(tasks.sortButton(column)).toHaveCount(0)
      await expect(tasks.header(column)).not.toHaveAttribute("tabindex")
      await expect(tasks.filterCell(column).locator("input, select, button")).toHaveCount(0)
      await expect(tasks.filterCell(column)).not.toHaveAttribute("tabindex")
      // an editable cell like any other: a Tab stop
      await expect(tasks.cell(FIRST, column)).toHaveAttribute("tabindex", "0")
    }

    await pushed.clear()
    await tasks.header("checks").click()
    await tasks.filterCell("tags").click()
    expect(await pushed.all()).toEqual([])
    // Tab goes from one array to the next, and sends nothing
    await tasks.cell(FIRST, "tags").focus()
    expect(await tasks.walk(1)).toEqual([`task-row-${FIRST}-c-checks`])
    expect(await pushed.all()).toEqual([])
  })
})

test.describe("an array of text: one control per value, in the side panel", () => {
  test("Enter opens the side panel with its one field: a group named by the column, a named control per value, a button to take each away and one to add", async ({
    tasks,
    pushed,
  }) => {
    const tags = tasks.cell(FIRST, "tags")
    await tags.focus()
    await pushed.clear()
    await tasks.press("Enter")

    await expect(tasks.panel).toBeVisible()
    await expect(tasks.panel).toHaveAccessibleName(/^Tags: /)
    await expect(tasks.panelSubmit).toHaveText("Save")
    expect(await tasks.fields()).toEqual(["tags"])
    const field = tasks.field("tags")
    await expect(field).toHaveRole("group")
    await expect(field).toHaveAccessibleName("Tags")
    await expect(values(field)).toHaveCount(3)

    for (const [index, value] of ["api", "customer", "quick-win"].entries()) {
      await expect(field.getByRole("textbox", { name: `Tags ${index + 1}`, exact: true })).toHaveValue(value)
      await expect(field.getByRole("button", { name: `Remove Tags ${index + 1}`, exact: true })).toBeVisible()
    }
    await expect(field.getByRole("button", { name: "Add value", exact: true })).toBeVisible()

    // focus is in the first value
    await expect(values(field).nth(0)).toBeFocused()
    expect(await pushed.count("edit"), "the panel is the server's: the hook asks for it").toBe(1)
    expect(await pushed.count("save")).toBe(0)
    expect(await pushed.count("panel_submit")).toBe(0)

    // nothing of it is in the cell, and the column's editor is no editor of the cell's
    await expect(tags).toHaveText("api, customer, quick-win")
    await expect(tasks.openEditors).toHaveCount(0)
    const template = tasks.editorTemplates.and(tasks.page.locator(`#task-editor-tags`))
    await expect(template).toHaveAttribute("data-editor", "list")
    expect(await template.evaluate((node) => (node as HTMLTemplateElement).content.childElementCount)).toBe(0)
  })

  test("a double click and a key typed on the cell open it too; Escape and Cancel close it, and the focus is on the cell again", async ({
    page,
    tasks,
    pushed,
  }) => {
    const tags = tasks.cell(FIRST, "tags")
    await pushed.clear()

    await tags.dblclick()
    const field = tasks.field("tags")
    await expect(tasks.panel).toBeVisible()
    await expect(values(field).nth(0)).toBeFocused()
    await tasks.panelCancel.click()
    await expect(tasks.panel).toHaveCount(0)
    await expect(tags).toBeFocused()

    // a key typed on the cell opens it, and is typed into nothing
    await tasks.press("u")
    await expect(tasks.panel).toBeVisible()
    await expect(values(field)).toHaveCount(3)
    await expect(values(field).nth(0)).toBeFocused()
    await expect(values(field).nth(0)).toHaveValue("api")
    await page.keyboard.press("Escape")
    await expect(tasks.panel).toHaveCount(0)
    await expect(tags).toBeFocused()

    await expect(tags).toHaveText("api, customer, quick-win")
    expect(await pushed.count("edit")).toBe(2)
    expect(await pushed.count("panel_submit")).toBe(0)
    expect(await pushed.count("save")).toBe(0)
  })

  test("the keys belong to the panel's controls: arrow keys stay in the value, Tab goes through the controls", async ({
    page,
    tasks,
    pushed,
  }) => {
    const field = await edit(tasks, tasks.cell(FIRST, "tags"), "tags")
    await pushed.clear()

    // the value's (a textarea's) own keys
    await tasks.press("ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", "Home", "End")
    await expect(values(field).nth(0)).toBeFocused()

    await page.keyboard.press("Tab")
    await expect(field.getByRole("button", { name: "Remove Tags 1" })).toBeFocused()
    await page.keyboard.press("Tab")
    await expect(values(field).nth(1)).toBeFocused()
    await page.keyboard.press("Shift+Tab")
    await page.keyboard.press("Shift+Tab")
    await expect(values(field).nth(0)).toBeFocused()
    await expect(tasks.panel, "the panel is open still").toBeVisible()
    expect(await pushed.count("panel_submit")).toBe(0)
    expect(await pushed.count("save")).toBe(0)
  })

  test("a value is added with the button, from the keyboard, and Save saves the whole list once", async ({
    page,
    tasks,
    pushed,
  }) => {
    const tags = tasks.cell(FIRST, "tags")
    const field = await edit(tasks, tags, "tags")
    await pushed.clear()

    // through the three values and their buttons to "Add value"
    for (let step = 0; step < 6; step++) await page.keyboard.press("Tab")
    await expect(field.getByRole("button", { name: "Add value" })).toBeFocused()
    // Enter on a button uses the button
    await page.keyboard.press("Enter")

    await expect(values(field)).toHaveCount(4)
    const added = field.getByRole("textbox", { name: "Tags 4", exact: true })
    await expect(added).toBeFocused()
    await expect(added).toHaveValue("")

    await page.keyboard.type("needs-design")
    expect(await pushed.count("panel_submit"), "nothing is saved while the list is being put together").toBe(0)
    expect(await pushed.count("save")).toBe(0)
    await save(tasks)

    await expect(tags).toHaveText("api, customer, quick-win, needs-design")
    await expect(tags).toBeFocused()
    expect(await pushed.count("panel_submit")).toBe(1)
    expect(await pushed.count("save"), "the panel's form saves, not the cell").toBe(0)

    const [{ params }] = (await pushed.all()).filter((sent) => sent.event === "panel_submit")
    // the field's own entry, then the values as typed
    expect(params.panel.tags, "the values as typed, as a list").toEqual([
      "",
      "api",
      "customer",
      "quick-win",
      "needs-design",
    ])

    await page.reload()
    await tasks.ready()
    await expect(tags).toHaveText("api, customer, quick-win, needs-design")
  })

  test("a value is taken away with its button; focus goes to the value after it, and the names follow", async ({
    page,
    tasks,
  }) => {
    const tags = tasks.cell(FIRST, "tags")
    const field = await edit(tasks, tags, "tags")

    await page.keyboard.press("Tab")
    await expect(field.getByRole("button", { name: "Remove Tags 1" })).toBeFocused()
    await page.keyboard.press("Enter")

    await expect(values(field)).toHaveCount(2)
    const first = field.getByRole("textbox", { name: "Tags 1", exact: true })
    await expect(first).toHaveValue("customer")
    await expect(first).toBeFocused()
    await expect(field.getByRole("textbox", { name: "Tags 3", exact: true })).toHaveCount(0)

    // the last value: focus goes to the one before it
    await field.getByRole("button", { name: "Remove Tags 2" }).focus()
    await page.keyboard.press("Space")
    await expect(values(field)).toHaveCount(1)
    await expect(first).toBeFocused()

    // and the only one: to the button that adds one
    await field.getByRole("button", { name: "Remove Tags 1" }).focus()
    await page.keyboard.press("Enter")
    await expect(values(field)).toHaveCount(0)
    await expect(field.getByRole("button", { name: "Add value" })).toBeFocused()

    await save(tasks)
    await expect(tags).toBeEmpty()
    await expect(tags).not.toHaveAttribute("data-failed")
    await expect(tags).toBeFocused()
  })

  test("Escape gives up everything that was done in the panel, and saves nothing", async ({
    page,
    tasks,
    pushed,
  }) => {
    const tags = tasks.cell(FIRST, "tags")
    const field = await edit(tasks, tags, "tags")
    await pushed.clear()

    await page.keyboard.type("changed")
    await field.getByRole("button", { name: "Remove Tags 2" }).click()
    await field.getByRole("button", { name: "Add value" }).click()
    await page.keyboard.type("another")
    await page.keyboard.press("Escape")

    await expect(tasks.panel).toHaveCount(0)
    await expect(tags).toHaveText("api, customer, quick-win")
    await expect(tags).toBeFocused()
    expect(await pushed.count("panel_submit")).toBe(0)
    expect(await pushed.count("save")).toBe(0)

    // nothing was saved
    await page.reload()
    await tasks.ready()
    await expect(tags).toHaveText("api, customer, quick-win")
  })

  test("Save with the values the task has closes the panel and changes nothing", async ({ tasks, pushed }) => {
    const tags = tasks.cell(FIRST, "tags")
    await edit(tasks, tags, "tags")
    await pushed.clear()
    await save(tasks)
    await expect(tags).toBeFocused()
    await expect(tags).toHaveText("api, customer, quick-win")
    await expect(tasks.status).toBeEmpty()

    // a value taken away and typed again
    const field = await edit(tasks, tags, "tags")
    await field.getByRole("button", { name: "Remove Tags 3" }).click()
    await field.getByRole("button", { name: "Add value" }).click()
    await tasks.page.keyboard.type("quick-win")
    await save(tasks)

    await expect(tags).toBeFocused()
    await expect(tags).toHaveText("api, customer, quick-win")
    await expect(tags).not.toHaveAttribute("data-failed")
    await expect(tasks.status).toBeEmpty()
    expect(await pushed.count("save")).toBe(0)
  })

  test("a click on the panel's buttons and in its field stays in the panel", async ({ tasks, pushed }) => {
    const tags = tasks.cell(FIRST, "tags")
    await tags.dblclick()
    await expect(tasks.panel).toBeVisible()
    const field = tasks.field("tags")
    await pushed.clear()

    await field.getByRole("button", { name: "Add value" }).click()
    await expect(values(field)).toHaveCount(4)
    await expect(values(field).nth(3)).toBeFocused()

    await values(field).nth(1).click()
    await expect(values(field).nth(1)).toBeFocused()
    await expect(values(field)).toHaveCount(4)
    await expect(tasks.panel).toBeVisible()
    expect(await pushed.count("panel_submit")).toBe(0)
    expect(await pushed.count("save")).toBe(0)
    await tasks.panelCancel.click()
    await expect(tags).toBeFocused()
  })

  test("an array without values opens with the button that adds one; a value left empty is not saved", async ({
    page,
    tasks,
  }) => {
    const tags = await emptyCell(tasks, "tags")
    const field = await edit(tasks, tags, "tags")

    await expect(values(field)).toHaveCount(0)
    await expect(field.getByRole("button", { name: "Add value" })).toBeFocused()

    await page.keyboard.press("Enter")
    await page.keyboard.type("first")
    await field.getByRole("button", { name: "Add value" }).click()
    await expect(values(field).nth(1)).toBeFocused()
    // left empty: the form of the action leaves it out
    await save(tasks)

    await expect(tags).toHaveText("first")
    await expect(tags).not.toHaveAttribute("data-failed")
    await expect(tags).toBeFocused()
  })

  test("the row is as high as before while the panel is open: nothing of it is in the cell", async ({ tasks }) => {
    const tags = tasks.cell(FIRST, "tags")
    const height = (await tasks.rowLine(FIRST).boundingBox())!.height

    await edit(tasks, tags, "tags")
    expect((await tasks.rowLine(FIRST).boundingBox())!.height).toBeCloseTo(height, 0)
    await tasks.page.keyboard.press("Escape")
    await expect(tasks.panel).toHaveCount(0)
    expect((await tasks.rowLine(FIRST).boundingBox())!.height).toBeCloseTo(height, 0)
  })
})

test.describe("an array of text: a save the action refuses", () => {
  test.beforeEach(async ({ page, tasks }) => {
    const field = await edit(tasks, tasks.cell(FIRST, "tags"), "tags")
    await field.getByRole("button", { name: "Add value" }).click()
    await page.keyboard.type("x")
    await tasks.panelSettled()
    await tasks.panelSubmit.click()
    await tasks.panelSettled()
  })

  test("the panel stays with what was typed, the action's message at the field and the refused value marked; it is read out", async ({
    page,
    tasks,
  }) => {
    const tags = tasks.cell(FIRST, "tags")
    const field = tasks.field("tags")

    await expect(tasks.panel).toBeVisible()
    await expect(values(field)).toHaveCount(4)
    await expect(values(field).nth(3)).toHaveValue("x")
    // the message says which value: by the name its control has in the panel
    await expect(tasks.fieldError("tags")).toHaveText(`Tags 4: ${TOO_SHORT}`)
    await expect(field).toHaveAccessibleDescription(`Tags 4: ${TOO_SHORT}`)
    await expect(tasks.status).toContainText(`Tags was not saved: Tags: Tags 4: ${TOO_SHORT}`)
    // the control of the value the action refused is marked, and no other
    await expect(values(field).nth(3)).toHaveAttribute("aria-invalid", "true")
    for (const index of [0, 1, 2]) await expect(values(field).nth(index)).not.toHaveAttribute("aria-invalid")
    await expectNoAxeViolations(page)

    // the cell is as the task has it: nothing failed in it
    await expect(tags).toHaveText("api, customer, quick-win")
    await expect(tags).not.toHaveAttribute("data-failed")
    await expect(tasks.failure(tags)).toHaveCount(0)

    // Cancel: the focus is on the cell, and nothing was saved
    await tasks.panelCancel.click()
    await expect(tasks.panel).toHaveCount(0)
    await expect(tags).toBeFocused()
    await page.reload()
    await tasks.ready()
    await expect(tags).toHaveText("api, customer, quick-win")
  })

  test("taking another value away leaves the mark on its value, under its new name; typed over, it is saved", async ({
    tasks,
  }) => {
    const tags = tasks.cell(FIRST, "tags")
    const field = tasks.field("tags")

    await field.getByRole("button", { name: "Remove Tags 1" }).click()
    await tasks.panelSettled()
    const refused = field.getByRole("textbox", { name: "Tags 3", exact: true })
    await expect(refused).toHaveValue("x")
    await expect(refused).toHaveAttribute("aria-invalid", "true")
    await expect(values(field).nth(0)).not.toHaveAttribute("aria-invalid")
    await expect(values(field).nth(1)).not.toHaveAttribute("aria-invalid")

    // typed over, it is another value, which nobody has refused
    await refused.fill("xl")
    await tasks.panelSettled()
    await expect(refused).not.toHaveAttribute("aria-invalid")
    await save(tasks)
    await expect(tags).toHaveText("customer, quick-win, xl")
    await expect(tags).toBeFocused()
    await expect(tags).not.toHaveAttribute("data-failed")
  })

  test("Escape gives the edit up; so does going back to the values the task has", async ({ page, tasks, pushed }) => {
    const tags = tasks.cell(FIRST, "tags")
    await page.keyboard.press("Escape")
    await expect(tasks.panel).toHaveCount(0)
    await expect(tags).toHaveText("api, customer, quick-win")
    await expect(tags).not.toHaveAttribute("data-failed")
    await expect(tags).toBeFocused()

    // opened again, it has the values the task has
    const field = await edit(tasks, tags, "tags")
    await expect(values(field)).toHaveCount(3)
    await field.getByRole("button", { name: "Add value" }).click()
    await page.keyboard.type("y")
    await tasks.panelSettled()
    await tasks.panelSubmit.click()
    await tasks.panelSettled()
    await expect(tasks.fieldError("tags")).toHaveText(`Tags 4: ${TOO_SHORT}`)

    // the fourth value taken away again: the task's own values, which save nothing
    await field.getByRole("button", { name: "Remove Tags 4" }).click()
    await pushed.clear()
    await save(tasks)
    await expect(tags).toHaveText("api, customer, quick-win")
    await expect(tags).not.toHaveAttribute("data-failed")
    await expect(tags).toBeFocused()
    // (the live region keeps what it said last: nothing new is said of a
    // save that changes nothing)
    expect(await pushed.count("save"), "the task's own values: no cell save runs").toBe(0)
  })
})

test.describe("an array of enum values: multiple choice, in the side panel", () => {
  test("Enter opens the side panel with a box per value of the enum in declared order, named by its label, the task's ticked", async ({
    tasks,
    pushed,
  }) => {
    const checks = tasks.cell(FIRST, "checks")
    await checks.focus()
    await pushed.clear()
    await tasks.press("Enter")

    await expect(tasks.panel).toBeVisible()
    await expect(tasks.panel).toHaveAccessibleName(/^Checks: /)
    const field = tasks.field("checks")
    await expect(field).toHaveRole("group")
    await expect(field).toHaveAccessibleName("Checks")
    expect(await ticks(field)).toEqual(["x Reviewed", "  Tested", "  Documented", "x Released"])

    for (const name of ["Reviewed", "Tested", "Documented", "Released"]) {
      await expect(field.getByRole("checkbox", { name, exact: true })).toBeVisible()
    }

    await expect(boxes(field).nth(0)).toBeFocused()
    expect(await pushed.count("edit")).toBe(1)
    expect(await pushed.count("save")).toBe(0)
    // nothing of it is in the cell, and the column's editor is no editor of the cell's
    await expect(tasks.openEditors).toHaveCount(0)
    const template = tasks.editorTemplates.and(tasks.page.locator(`#task-editor-checks`))
    await expect(template).toHaveAttribute("data-editor", "choices")
    expect(await template.evaluate((node) => (node as HTMLTemplateElement).content.childElementCount)).toBe(0)
  })

  test("Space ticks, Tab goes from box to box, and Save saves once: nothing is saved before", async ({
    page,
    tasks,
    pushed,
  }) => {
    const checks = tasks.cell(FIRST, "checks")
    const field = await edit(tasks, checks, "checks")
    await pushed.clear()

    // Reviewed off, Tested on, Documented on
    await page.keyboard.press("Space")
    await page.keyboard.press("Tab")
    await expect(boxes(field).nth(1)).toBeFocused()
    await page.keyboard.press("Space")
    await page.keyboard.press("Tab")
    await page.keyboard.press("Space")
    await page.keyboard.press("Shift+Tab")
    await expect(boxes(field).nth(1)).toBeFocused()

    expect(await ticks(field)).toEqual(["  Reviewed", "x Tested", "x Documented", "x Released"])
    expect(await pushed.count("panel_submit"), "ticking is not saving").toBe(0)
    expect(await pushed.count("save")).toBe(0)

    await save(tasks)

    await expect(checks).toHaveText("Tested, Documented, Released")
    await expect(checks).toBeFocused()
    expect(await pushed.count("panel_submit")).toBe(1)
    expect(await pushed.count("save")).toBe(0)

    const [{ params }] = (await pushed.all()).filter((sent) => sent.event === "panel_submit")
    expect(params.panel.checks).toEqual(["", "tested", "documented", "released"])

    await page.reload()
    await tasks.ready()
    await expect(checks).toHaveText("Tested, Documented, Released")
  })

  test("Escape gives the ticks up; ticks that end where they began save nothing", async ({
    page,
    tasks,
    pushed,
  }) => {
    const checks = tasks.cell(FIRST, "checks")
    await edit(tasks, checks, "checks")
    await pushed.clear()

    await page.keyboard.press("Space")
    await page.keyboard.press("Escape")
    await expect(tasks.panel).toHaveCount(0)
    await expect(checks).toHaveText("Reviewed, Released")
    await expect(checks).toBeFocused()
    expect(await pushed.count("panel_submit")).toBe(0)

    await edit(tasks, checks, "checks")
    await page.keyboard.press("Space")
    await page.keyboard.press("Space")
    await save(tasks)
    await expect(checks).toHaveText("Reviewed, Released")
    await expect(checks).toBeFocused()
    await expect(tasks.status).toBeEmpty()
    expect(await pushed.count("save")).toBe(0)
  })

  test("a letter typed on the cell opens the panel, and ticks nothing", async ({ tasks, pushed }) => {
    const checks = tasks.cell(FIRST, "checks")
    await checks.focus()
    await pushed.clear()
    await tasks.press("d")

    await expect(tasks.panel).toBeVisible()
    const field = tasks.field("checks")
    await expect(boxes(field).nth(0)).toBeFocused()
    expect(await ticks(field)).toEqual(["x Reviewed", "  Tested", "  Documented", "x Released"])
    await tasks.page.keyboard.press("Escape")
    await expect(tasks.panel).toHaveCount(0)
    await expect(checks).toBeFocused()
    expect(await pushed.count("panel_submit")).toBe(0)
    expect(await pushed.count("save")).toBe(0)
  })

  test("with the pointer: a double click opens it, a click on a box or its label ticks it, and Save saves", async ({
    tasks,
  }) => {
    const checks = tasks.cell(FIRST, "checks")
    await checks.dblclick()
    await expect(tasks.panel).toBeVisible()
    const field = tasks.field("checks")

    await field.getByText("Tested", { exact: true }).click()
    await expect(field.getByRole("checkbox", { name: "Tested" })).toBeChecked()
    await field.getByRole("checkbox", { name: "Released" }).click()
    expect(await ticks(field)).toEqual(["x Reviewed", "x Tested", "  Documented", "  Released"])
    await expect(tasks.panel).toBeVisible()

    await save(tasks)
    await expect(checks).toHaveText("Reviewed, Tested")
    await expect(checks).toBeFocused()
  })

  test("everything unticked saves the empty array, and the cell is empty", async ({ page, tasks }) => {
    const checks = tasks.cell(SECOND, "checks")
    await expect(checks).toHaveText("Released")
    const field = await edit(tasks, checks, "checks")
    await field.getByRole("checkbox", { name: "Released" }).focus()
    await page.keyboard.press("Space")
    await save(tasks)

    await expect(checks).toBeEmpty()
    await expect(checks).not.toHaveAttribute("data-failed")
  })
})

// Only an array of atoms limited by `one_of` can hold a value its choices
// no longer have and still be read, and the demo's tables have none (the
// library's tests of it are `array_table_test.exs`, which also says that the
// server draws such a value as a hidden input after the boxes). What the
// browser does with it is send it with the form: so the panel is given one
// here, as the server would draw it, once the server has answered the ticks.
test.describe("a multiple choice whose field holds a value that is none of its choices", () => {
  test("has no box for it, and sends it back after the ticked values: only what a person could change has changed", async ({
    tasks,
    pushed,
  }) => {
    const checks = tasks.cell(FIRST, "checks")
    const field = await edit(tasks, checks, "checks")
    await expect(boxes(field)).toHaveCount(4)

    await field.getByRole("checkbox", { name: "Tested" }).check()
    await tasks.panelSettled()
    await field.evaluate((group) => {
      const held = document.createElement("input")
      held.type = "hidden"
      held.name = group.querySelector<HTMLInputElement>("input[type=checkbox]")!.name
      held.value = "legacy"
      group.append(held)
    })
    // a hidden input is no box
    await expect(boxes(field)).toHaveCount(4)
    expect(await ticks(field)).toEqual(["x Reviewed", "x Tested", "  Documented", "x Released"])

    await pushed.clear()
    await tasks.panelSubmit.click()
    await tasks.panelSettled()

    const [{ params }] = (await pushed.all()).filter((sent) => sent.event === "panel_submit")
    expect(params.panel.checks).toEqual(["", "reviewed", "tested", "released", "legacy"])

    // whether the list is taken is the action's to say: this enum has no such value
    await expect(tasks.panel).toBeVisible()
    await expect(tasks.fieldError("checks")).toHaveText("is invalid")
    await tasks.panelCancel.click()
    await expect(checks).toHaveText("Reviewed, Released")
    await expect(checks).toBeFocused()
  })
})

test.describe("the member, on a task that is not theirs", () => {
  test.use({ actor: "member" })

  test("is refused in the panel of either array, with what was ticked kept, and nothing saved", async ({
    page,
    tasks,
  }) => {
    const checks = tasks.cell(FIRST, "checks")
    const field = await edit(tasks, checks, "checks")
    await page.keyboard.press("Space")
    await tasks.panelSettled()
    await tasks.panelSubmit.click()
    await tasks.panelSettled()

    await expect(tasks.panel).toBeVisible()
    await expect(tasks.panelErrors).toHaveText("You are not allowed to change this.")
    expect(await ticks(field)).toEqual(["  Reviewed", "  Tested", "  Documented", "x Released"])
    await expectNoAxeViolations(page)

    await page.keyboard.press("Escape")
    await expect(tasks.panel).toHaveCount(0)
    await expect(checks).toHaveText("Reviewed, Released")
    await expect(checks).toBeFocused()
    await expect(checks).not.toHaveAttribute("data-failed")

    // and the list of text
    const tags = tasks.cell(FIRST, "tags")
    const list = await edit(tasks, tags, "tags")
    await list.getByRole("button", { name: "Add value" }).click()
    await page.keyboard.type("mine")
    await tasks.panelSettled()
    await tasks.panelSubmit.click()
    await tasks.panelSettled()
    await expect(tasks.panelErrors).toHaveText("You are not allowed to change this.")
    await expect(values(list).nth(3)).toHaveValue("mine")
    await tasks.panelCancel.click()
    await expect(tags).toHaveText("api, customer, quick-win")
    await expect(tags).toBeFocused()
  })
})

// "Integers" on /specimens: an array of numbers that has to keep one value,
// none of them below 0.
test.describe("an array of numbers, on /specimens", () => {
  let specimens: Table
  let integers: Locator
  let before: string[]

  test.beforeEach(async ({ page }) => {
    specimens = new Table(page, "specimen", "/specimens")
    await specimens.open()
    integers = specimens.cell(SEED.specimens.first, "integers")
    before = (await integers.textContent())!.split(", ")
    expect(before.length, "the first specimen has integers").toBeGreaterThan(0)
  })

  test("is a number input per value in the panel; a digit typed on the cell opens it and adds no value", async ({
    page,
    pushed,
  }) => {
    await pushed.clear()
    const field = await edit(specimens, integers, "integers")
    const numbers = field.locator("[data-item] input[type=number]")
    await expect(field).toHaveAccessibleName("Integers")
    await expect(numbers).toHaveCount(before.length)
    await expect(field.getByRole("spinbutton", { name: "Integers 1", exact: true })).toHaveValue(before[0])
    await expect(numbers.nth(0)).toBeFocused()
    await page.keyboard.press("Escape")
    await expect(specimens.panel).toHaveCount(0)
    await expect(integers).toBeFocused()

    await specimens.press("7")
    await expect(specimens.panel).toBeVisible()
    await expect(numbers).toHaveCount(before.length)
    await expect(numbers.nth(0)).toBeFocused()
    await expect(numbers.nth(0)).toHaveValue(before[0])

    // a value added in the panel, and saved
    await field.getByRole("button", { name: "Add value" }).click()
    await expect(numbers.last()).toBeFocused()
    await page.keyboard.type("7")
    await save(specimens)

    await expect(integers).toHaveText([...before, "7"].join(", "))
    await expect(integers).toBeFocused()
    expect(await pushed.count("panel_submit")).toBe(1)
    expect(await pushed.count("save")).toBe(0)
  })

  test("a list the action refuses is shown with the action's message at the field: no value left, and a value below 0", async ({
    page,
  }) => {
    const field = await edit(specimens, integers, "integers")
    for (let left = before.length; left > 0; left--) {
      await field.getByRole("button", { name: "Remove Integers 1", exact: true }).click()
    }
    await expect(field.getByRole("button", { name: "Add value" })).toBeFocused()
    await specimens.panelSettled()
    await specimens.panelSubmit.click()
    await specimens.panelSettled()

    await expect(specimens.panel).toBeVisible()
    await expect(specimens.fieldError("integers")).toHaveText("must have 1 or more items")

    await field.getByRole("button", { name: "Add value" }).click()
    await page.keyboard.type("-5")
    await specimens.panelSettled()
    await specimens.panelSubmit.click()
    await specimens.panelSettled()

    await expect(specimens.panel).toBeVisible()
    await expect(specimens.fieldError("integers")).toHaveText("Integers 1: must be greater than or equal to 0")
    await expect(field).toHaveAccessibleDescription("Integers 1: must be greater than or equal to 0")
    const refused = field.getByRole("spinbutton", { name: "Integers 1", exact: true })
    await expect(refused).toHaveValue("-5")
    await expect(refused).toHaveAttribute("aria-invalid", "true")
    await expectNoAxeViolations(page)

    // given up: the cell is as the specimen has it
    await page.keyboard.press("Escape")
    await expect(specimens.panel).toHaveCount(0)
    await expect(integers).toHaveText(before.join(", "))
    await expect(integers).not.toHaveAttribute("data-failed")
    await expect(integers).toBeFocused()
  })
})

test.describe("in a nested table: the tasks under a project", () => {
  test("both open the nested table's panel as on the page of the tasks; Escape closes it, and focus is on the cell again", async ({
    page,
    pushed,
  }) => {
    const projects = new Table(page, "project", "/projects")
    await projects.open()
    const nested = await projects.openLine(SEED.project.mobileApp, "tasks")
    const [key] = await nested.rowKeys()
    const tags = nested.cell(key, "tags")
    const checks = nested.cell(key, "checks")

    const list = await edit(nested, tags, "tags")
    await expect(list).toHaveAccessibleName("Tags")
    await list.getByRole("button", { name: "Add value" }).focus()
    await page.keyboard.press("Enter")
    await page.keyboard.type("under-a-project")
    await nested.panelSettled()
    await pushed.clear()
    await save(nested)

    await expect(tags).toContainText("under-a-project")
    await expect(tags).toBeFocused()
    expect(await pushed.count("panel_submit")).toBe(1)
    expect(
      (await pushed.besides("panel_change")).map((sent) => sent.event),
      "the projects around it are not read again",
    ).toEqual(["panel_submit"])

    const before = await checks.textContent()
    const field = await edit(nested, checks, "checks")
    await expect(boxes(field).nth(0)).toBeFocused()
    await page.keyboard.press("Space")
    await page.keyboard.press("Escape")
    await expect(nested.panel).toHaveCount(0)
    await expect(checks).toHaveText(before!)
    await expect(checks).toBeFocused()

    await edit(nested, checks, "checks")
    const released = field.getByRole("checkbox", { name: "Released" })
    const was = await released.isChecked()
    await released.focus()
    await page.keyboard.press("Space")
    await save(nested)
    if (was) await expect(checks).not.toContainText("Released")
    else await expect(checks).toContainText("Released")
    await expect(checks).toBeFocused()
  })
})

test.describe("accessibility, with an array's panel open", () => {
  test("the list of an array of text", async ({ page, tasks }) => {
    const field = await edit(tasks, tasks.cell(FIRST, "tags"), "tags")
    await field.getByRole("button", { name: "Add value" }).click()
    await expect(values(field)).toHaveCount(4)
    await expectNoAxeViolations(page)
  })

  test("the boxes of a multiple choice", async ({ page, tasks }) => {
    const field = await edit(tasks, tasks.cell(FIRST, "checks"), "checks")
    await expect(boxes(field).nth(0)).toBeFocused()
    await expectNoAxeViolations(page)
  })

  test("both in the dark theme", async ({ page, tasks }) => {
    await page.addInitScript(() => localStorage.setItem("phx:theme", "dark"))
    await tasks.open()
    await expect(page.locator("html")).toHaveAttribute("data-theme", "dark")

    const tags = tasks.cell(FIRST, "tags")
    await edit(tasks, tags, "tags")
    await expectNoAxeViolations(page)
    await page.keyboard.press("Escape")
    await expect(tasks.panel).toHaveCount(0)
    await expect(tags).toBeFocused()

    await edit(tasks, tasks.cell(FIRST, "checks"), "checks")
    await expectNoAxeViolations(page)
  })
})

test.describe("in the action panel: New task", () => {
  test.beforeEach(async ({ tasks }) => {
    await tasks.create.click()
    await expect(tasks.panel).toBeVisible()
  })

  test("the field of an array is a group named by its label: no values yet, and a box per check", async ({
    tasks,
  }) => {
    const tags = tasks.field("tags")
    const checks = tasks.field("checks")

    await expect(tags).toHaveRole("group")
    await expect(tags).toHaveAccessibleName("Tags")
    await expect(tags.locator("[data-item]")).toHaveCount(0)
    await expect(tags.getByRole("button", { name: "Add value" })).toBeVisible()

    await expect(checks).toHaveRole("group")
    await expect(checks).toHaveAccessibleName("Checks")
    expect(await ticks(checks)).toEqual(["  Reviewed", "  Tested", "  Documented", "  Released"])
  })

  test("values are added, typed and taken away from the keyboard, and the task is created with them", async ({
    page,
    tasks,
  }) => {
    const tags = tasks.field("tags")
    const checks = tasks.field("checks")

    await tasks.field("title").fill("Made with arrays")
    await tasks.chooseField("project_id", SEED.project.mobileApp)

    await tags.getByRole("button", { name: "Add value" }).focus()
    await page.keyboard.press("Enter")
    await expect(tags.getByRole("textbox", { name: "Tags 1", exact: true })).toBeFocused()
    await page.keyboard.type("to-go")
    await page.keyboard.press("Tab")
    await expect(tags.getByRole("button", { name: "Remove Tags 1" })).toBeFocused()
    await page.keyboard.press("Tab")
    await expect(tags.getByRole("button", { name: "Add value" })).toBeFocused()
    await page.keyboard.press("Space")
    await expect(tags.getByRole("textbox", { name: "Tags 2", exact: true })).toBeFocused()
    await page.keyboard.type("frontend")
    await tags.getByRole("button", { name: "Add value" }).click()
    await page.keyboard.type("api")

    // the first is taken away: focus goes to the value after it, which is the first now
    await tags.getByRole("button", { name: "Remove Tags 1" }).focus()
    await page.keyboard.press("Enter")
    await expect(tags.getByRole("textbox", { name: "Tags 1", exact: true })).toBeFocused()
    await expect(tags.getByRole("textbox", { name: "Tags 1", exact: true })).toHaveValue("frontend")
    await expect(tags.locator("[data-item]")).toHaveCount(2)

    await checks.getByRole("checkbox", { name: "Tested" }).focus()
    await page.keyboard.press("Space")
    await checks.getByText("Documented", { exact: true }).click()
    await tasks.panelSettled()

    // what the server has answered meanwhile has taken nothing away
    await expect(tags.getByRole("textbox", { name: "Tags 2", exact: true })).toHaveValue("api")
    expect(await ticks(checks)).toEqual(["  Reviewed", "x Tested", "x Documented", "  Released"])

    await tasks.panelSubmit.click()
    await expect(tasks.panel).toHaveCount(0)

    const key = await tasks.rowKey(1)
    await expect(tasks.cell(key, "title")).toHaveText("Made with arrays")
    await expect(tasks.cell(key, "tags")).toHaveText("frontend, api")
    await expect(tasks.cell(key, "checks")).toHaveText("Tested, Documented")
  })

  test("what the action says about an array is shown at its field, with the values kept", async ({
    page,
    tasks,
  }) => {
    const tags = tasks.field("tags")
    const first = tags.getByRole("textbox", { name: "Tags 1", exact: true })

    await tasks.field("title").fill("Made with arrays")
    await tasks.chooseField("project_id", SEED.project.mobileApp)
    await tags.getByRole("button", { name: "Add value" }).click()
    await page.keyboard.type("x")
    await tasks.panelSettled()

    await expect(tasks.fieldError("tags")).toHaveText(`Tags 1: ${TOO_SHORT}`)
    await expect(tags).toHaveAccessibleDescription(`Tags 1: ${TOO_SHORT}`)
    await expect(first).toHaveAttribute("aria-invalid", "true")
    await expectNoAxeViolations(page)

    // a value added after it is not marked, and the first stays so
    await tags.getByRole("button", { name: "Add value" }).click()
    await page.keyboard.type("fine")
    await tasks.panelSettled()
    await expect(tasks.fieldError("tags")).toHaveText(`Tags 1: ${TOO_SHORT}`)
    await expect(tags.getByRole("textbox", { name: "Tags 2", exact: true })).not.toHaveAttribute("aria-invalid")
    await expect(first).toHaveAttribute("aria-invalid", "true")
    await tags.getByRole("button", { name: "Remove Tags 2" }).click()
    await tasks.panelSettled()

    await tasks.panelSubmit.click()
    await tasks.panelSettled()
    await expect(tasks.panel).toBeVisible()
    await expect(tasks.fieldError("tags")).toHaveText(`Tags 1: ${TOO_SHORT}`)
    await expect(first).toHaveValue("x")
    await expect(first).toHaveAttribute("aria-invalid", "true")

    await first.fill("xl")
    await tasks.panelSettled()
    await expect(tasks.fieldError("tags")).toHaveCount(0)
    await expect(first).not.toHaveAttribute("aria-invalid")
  })

  test("accessibility: the panel with values added and boxes ticked", async ({ page, tasks }) => {
    const tags = tasks.field("tags")
    await tags.getByRole("button", { name: "Add value" }).click()
    await page.keyboard.type("frontend")
    await tags.getByRole("button", { name: "Add value" }).click()
    await tasks.field("checks").getByRole("checkbox", { name: "Released" }).check()
    await tasks.panelSettled()
    await expectNoAxeViolations(page)
  })
})
