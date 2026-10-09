import type { Locator } from "@playwright/test"
import { expectNoAxeViolations } from "./support/a11y"
import { SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { Table } from "./support/table"

// The array columns of /tasks as the admin, who may change every task:
// "Tags", an array of text with at most five values of two to twenty
// characters, edited value by value; and "Checks", an array of enum values,
// edited as multiple choice. These tests save: the database is seeded again
// after each of them (`writes`).

// tags: api, customer, quick-win; checks: Reviewed, Released
const FIRST = SEED.task.first
// tags: backend; checks: Released
const SECOND = SEED.task.second

const TOO_SHORT = "length must be greater than or equal to 2"

test.use({ writes: true })

test.beforeEach(async ({ tasks }) => {
  await tasks.open()
})

/** The group an array's editor is: named by its column. */
function group(cell: Locator, name: string): Locator {
  return cell.getByRole("group", { name, exact: true })
}

/** The controls of the values of a list editor, top to bottom. */
function values(cell: Locator): Locator {
  return cell.locator("[data-item] textarea")
}

/** The boxes of a multiple choice, top to bottom. */
function boxes(cell: Locator): Locator {
  return cell.getByRole("checkbox")
}

/** What the boxes say: each label with whether it is ticked. */
async function ticks(cell: Locator): Promise<string[]> {
  return cell.locator("label").evaluateAll((labels) =>
    labels.map((label) => {
      const box = label.querySelector("input") as HTMLInputElement
      return `${box.checked ? "x" : " "} ${label.textContent!.trim()}`
    }),
  )
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

  test("has neither a sort nor a filter: Enter on its header and on its filter cell does nothing", async ({
    tasks,
    frames,
  }) => {
    for (const column of ["tags", "checks"]) {
      await expect(tasks.header(column)).not.toHaveAttribute("aria-sort")
      await expect(tasks.filterCell(column).locator("input, select, button")).toHaveCount(0)
    }

    await frames.clear()
    await tasks.header("tags").focus()
    await tasks.press("Enter")
    await tasks.press("ArrowDown")
    await expect(tasks.filterCell("tags")).toBeFocused()
    await tasks.press("Enter")
    await expect(tasks.filterCell("tags")).toBeFocused()
    await tasks.header("checks").click()
    expect(await frames.all()).toEqual([])
  })

  test("is a cell like any other to the arrow keys, which send nothing", async ({ tasks, frames }) => {
    await tasks.cell(FIRST, "description").focus()
    await frames.clear()

    await tasks.press("ArrowRight")
    await expect(tasks.cell(FIRST, "tags")).toBeFocused()
    await tasks.press("ArrowRight")
    await expect(tasks.cell(FIRST, "checks")).toBeFocused()
    await tasks.press("ArrowDown")
    await expect(tasks.cell(SECOND, "checks")).toBeFocused()
    await tasks.press("ArrowLeft")
    await expect(tasks.cell(SECOND, "tags")).toBeFocused()
    expect(await frames.all()).toEqual([])
  })
})

test.describe("an array of text: one control per value", () => {
  test("Enter opens the editor in the cell: a group named by the column, a named control per value, a button to take each away and one to add", async ({
    tasks,
    frames,
  }) => {
    const tags = tasks.cell(FIRST, "tags")
    await tags.focus()
    await frames.clear()
    await tasks.press("Enter")

    await expect(group(tags, "Tags")).toBeVisible()
    await expect(values(tags)).toHaveCount(3)
    await expect(values(tags).nth(0)).toHaveValue("api")
    await expect(values(tags).nth(1)).toHaveValue("customer")
    await expect(values(tags).nth(2)).toHaveValue("quick-win")

    for (const [index, value] of ["api", "customer", "quick-win"].entries()) {
      await expect(tags.getByRole("textbox", { name: `Tags ${index + 1}`, exact: true })).toHaveValue(value)
      await expect(tags.getByRole("button", { name: `Remove Tags ${index + 1}`, exact: true })).toBeVisible()
    }
    await expect(tags.getByRole("button", { name: "Add value", exact: true })).toBeVisible()

    // focus is in the first value, with its text selected
    await expect(values(tags).nth(0)).toBeFocused()
    expect(await values(tags).nth(0).evaluate((input: HTMLTextAreaElement) => input.selectionEnd)).toBe(3)
    expect(await frames.all(), "opening an editor is the browser's alone").toEqual([])
  })

  test("the keys belong to its controls: arrow keys stay in the value, Tab goes through the controls", async ({
    page,
    tasks,
    frames,
  }) => {
    const tags = tasks.cell(FIRST, "tags")
    await tags.focus()
    await tasks.press("Enter")
    await frames.clear()

    await tasks.press("ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", "Home", "End")
    await expect(values(tags).nth(0)).toBeFocused()

    await page.keyboard.press("Tab")
    await expect(tags.getByRole("button", { name: "Remove Tags 1" })).toBeFocused()
    await page.keyboard.press("Tab")
    await expect(values(tags).nth(1)).toBeFocused()
    await page.keyboard.press("Shift+Tab")
    await page.keyboard.press("Shift+Tab")
    await expect(values(tags).nth(0)).toBeFocused()
    await expect(group(tags, "Tags"), "the editor is open still").toBeVisible()
    expect(await frames.all()).toEqual([])
  })

  test("a value is added with the button, from the keyboard, and Enter saves the whole list once", async ({
    page,
    tasks,
    frames,
  }) => {
    const tags = tasks.cell(FIRST, "tags")
    await tags.focus()
    await tasks.press("Enter")
    await frames.clear()

    // through the three values and their buttons to "Add value"
    for (let step = 0; step < 6; step++) await page.keyboard.press("Tab")
    await expect(tags.getByRole("button", { name: "Add value" })).toBeFocused()
    // Enter on a button uses the button
    await page.keyboard.press("Enter")

    await expect(values(tags)).toHaveCount(4)
    const added = tags.getByRole("textbox", { name: "Tags 4", exact: true })
    await expect(added).toBeFocused()
    await expect(added).toHaveValue("")
    expect(await frames.all(), "nothing is sent while the list is being put together").toEqual([])

    await page.keyboard.type("needs-design")
    await tasks.saves(tags, async () => {
      await tasks.press("Enter")
      await expect(tags, "at once, before the server has answered").toBeFocused()
    })

    await expect(tags).toHaveText("api, customer, quick-win, needs-design")
    await expect(tags).toBeFocused()
    await expect(tags.locator("*")).toHaveCount(0)
    expect(await frames.count("save")).toBe(1)
    expect(await tasks.tabStops()).toEqual([`task-row-${FIRST}-c-tags`])

    const [, , , , payload] = JSON.parse((await frames.all())[0])
    expect(payload.value.value, "the values as typed, as a list").toEqual([
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
    await tags.focus()
    await tasks.press("Enter")

    await page.keyboard.press("Tab")
    await expect(tags.getByRole("button", { name: "Remove Tags 1" })).toBeFocused()
    await page.keyboard.press("Enter")

    await expect(values(tags)).toHaveCount(2)
    const first = tags.getByRole("textbox", { name: "Tags 1", exact: true })
    await expect(first).toHaveValue("customer")
    await expect(first).toBeFocused()
    await expect(tags.getByRole("textbox", { name: "Tags 3", exact: true })).toHaveCount(0)

    // the last value: focus goes to the one before it
    await tags.getByRole("button", { name: "Remove Tags 2" }).focus()
    await page.keyboard.press("Space")
    await expect(values(tags)).toHaveCount(1)
    await expect(first).toBeFocused()

    // and the only one: to the button that adds one
    await tags.getByRole("button", { name: "Remove Tags 1" }).focus()
    await page.keyboard.press("Enter")
    await expect(values(tags)).toHaveCount(0)
    await expect(tags.getByRole("button", { name: "Add value" })).toBeFocused()

    // Enter on that button would add a value: leaving the editor saves
    await tasks.saves(tags, () => page.keyboard.press("Tab"))
    await expect(tags).toBeEmpty()
    await expect(tags).not.toHaveAttribute("aria-invalid")
  })

  test("Escape gives up everything that was done in the editor, and sends nothing", async ({
    page,
    tasks,
    frames,
  }) => {
    const tags = tasks.cell(FIRST, "tags")
    await tags.focus()
    await tasks.press("Enter")
    await frames.clear()

    await page.keyboard.type("changed")
    await tags.getByRole("button", { name: "Remove Tags 2" }).click()
    await tags.getByRole("button", { name: "Add value" }).click()
    await page.keyboard.type("another")
    await tasks.press("Escape")

    await expect(tags).toHaveText("api, customer, quick-win")
    await expect(tags).toBeFocused()
    await expect(tags.locator("*")).toHaveCount(0)
    expect(await tasks.tabStops()).toEqual([`task-row-${FIRST}-c-tags`])
    expect(await frames.all()).toEqual([])
  })

  test("values that have not changed save nothing, on Enter and on leaving", async ({ tasks, frames }) => {
    const tags = tasks.cell(FIRST, "tags")
    await tags.focus()
    await frames.clear()

    await tasks.press("F2")
    await expect(values(tags).nth(0)).toBeFocused()
    await tasks.press("Enter")
    await expect(tags).toBeFocused()
    await expect(tags).toHaveText("api, customer, quick-win")

    // a value taken away and typed again
    await tasks.press("Enter")
    await tags.getByRole("button", { name: "Remove Tags 3" }).click()
    await tags.getByRole("button", { name: "Add value" }).click()
    await tasks.page.keyboard.type("quick-win")
    await tasks.cell(SECOND, "title").click()

    await expect(tasks.cell(SECOND, "title")).toBeFocused()
    await expect(tags).toHaveText("api, customer, quick-win")
    await expect(tags).not.toHaveAttribute("aria-busy")
    expect(await frames.all()).toEqual([])
  })

  test("leaving the editor saves: a click on another cell, and Tab from its last control", async ({
    page,
    tasks,
  }) => {
    const tags = tasks.cell(FIRST, "tags")
    const elsewhere = tasks.cell(SECOND, "title")

    await tags.dblclick()
    await expect(values(tags).nth(0)).toBeFocused()
    await tasks.retype("apis")
    await tasks.saves(tags, () => elsewhere.click())
    await expect(tags).toHaveText("apis, customer, quick-win")
    await expect(elsewhere).toBeFocused()

    await tags.focus()
    await tasks.press("Enter")
    await tags.getByRole("button", { name: "Add value" }).focus()
    await page.keyboard.press("Enter")
    await page.keyboard.type("mobile")
    await page.keyboard.press("Tab")
    await page.keyboard.press("Tab")
    await expect(tags.getByRole("button", { name: "Add value" })).toBeFocused()
    // from the last control Tab leaves the grid, as it does from a cell
    await tasks.saves(tags, () => page.keyboard.press("Tab"))
    await expect(tags).toHaveText("apis, customer, quick-win, mobile")
    expect(await tasks.hasFocus()).toBe(false)
  })

  test("a click on its buttons and beside its controls stays in the editor", async ({ tasks, frames }) => {
    const tags = tasks.cell(FIRST, "tags")
    await tags.dblclick()
    await frames.clear()

    await tags.getByRole("button", { name: "Add value" }).click()
    await expect(values(tags)).toHaveCount(4)
    await expect(values(tags).nth(3)).toBeFocused()

    // beside a control, in the editor: the focus stays where it is
    const row = (await tags.locator("[data-item]").nth(3).boundingBox())!
    await tasks.page.mouse.click(row.x + row.width - 1, row.y + row.height - 1)
    await expect(values(tags).nth(3)).toBeFocused()

    await values(tags).nth(1).click()
    await expect(values(tags).nth(1)).toBeFocused()
    await expect(values(tags)).toHaveCount(4)
    expect(await frames.all()).toEqual([])
    await tasks.press("Escape")
  })

  test("typing on the cell starts a new value with the character, and keeps the others", async ({
    page,
    tasks,
  }) => {
    const tags = tasks.cell(FIRST, "tags")
    await tags.focus()
    await tasks.press("u")

    await expect(values(tags)).toHaveCount(4)
    await expect(values(tags).nth(3)).toBeFocused()
    await expect(values(tags).nth(3)).toHaveValue("u")
    await expect(values(tags).nth(0)).toHaveValue("api")

    await page.keyboard.type("rgent")
    await tasks.saves(tags, () => tasks.press("Enter"))
    await expect(tags).toHaveText("api, customer, quick-win, urgent")
  })

  test("an array without values opens with the button that adds one; a value left empty is not saved", async ({
    page,
    tasks,
    frames,
  }) => {
    const tags = await emptyCell(tasks, "tags")
    await tags.focus()
    await frames.clear()
    await tasks.press("Enter")

    await expect(values(tags)).toHaveCount(0)
    await expect(tags.getByRole("button", { name: "Add value" })).toBeFocused()

    await page.keyboard.press("Enter")
    await page.keyboard.type("first")
    await tags.getByRole("button", { name: "Add value" }).click()
    await expect(values(tags).nth(1)).toBeFocused()
    // left empty: the form of the action leaves it out
    await tasks.saves(tags, () => tasks.press("Enter"))

    await expect(tags).toHaveText("first")
    await expect(tags).not.toHaveAttribute("aria-invalid")
    expect(await frames.count("save")).toBe(1)
  })

  test("the row is as high as before once the editor is closed", async ({ tasks }) => {
    const tags = tasks.cell(FIRST, "tags")
    const height = (await tasks.rowLine(FIRST).boundingBox())!.height

    await tags.focus()
    await tasks.press("Enter")
    expect((await tasks.rowLine(FIRST).boundingBox())!.height, "open, the row has room for the values").toBeGreaterThan(
      height,
    )
    await tasks.press("Escape")
    expect((await tasks.rowLine(FIRST).boundingBox())!.height).toBeCloseTo(height, 0)
  })
})

test.describe("an array of text: a save the action refuses", () => {
  test.beforeEach(async ({ page, tasks }) => {
    const tags = tasks.cell(FIRST, "tags")
    await tags.focus()
    await tasks.press("Enter")
    await tags.getByRole("button", { name: "Add value" }).click()
    await page.keyboard.type("x")
    await tasks.saves(tags, () => tasks.press("Enter"))
    await expect(tags).toHaveAttribute("aria-invalid", "true")
    await page.mouse.move(5, 5)
  })

  test("marks the cell, which keeps what was typed and shows the action's message; it is read out", async ({
    page,
    tasks,
  }) => {
    const tags = tasks.cell(FIRST, "tags")

    await expect(tags).toBeFocused()
    await expect(tags).toContainText("api, customer, quick-win, x")
    await expect(tasks.failure(tags)).toBeVisible()
    await expect(tasks.failure(tags)).toHaveText(TOO_SHORT)
    await expect(tags).toHaveAccessibleDescription(TOO_SHORT)
    await expect(tasks.status).toContainText(`Tags was not saved: ${TOO_SHORT}`)
    await expectNoAxeViolations(page)

    // nothing was saved
    await page.reload()
    await tasks.ready()
    await expect(tags).toHaveText("api, customer, quick-win")
  })

  test("opens again with what was typed; a value the action takes is saved and the mark is gone", async ({
    page,
    tasks,
  }) => {
    const tags = tasks.cell(FIRST, "tags")
    await tasks.press("Enter")

    await expect(values(tags)).toHaveCount(4)
    await expect(values(tags).nth(3)).toHaveValue("x")
    await expectNoAxeViolations(page)

    await values(tags).nth(3).fill("xl")
    await tasks.saves(tags, () => tasks.press("Enter"))
    await expect(tags).toHaveText("api, customer, quick-win, xl")
    await expect(tags).not.toHaveAttribute("aria-invalid")
  })

  test("Escape on the cell gives the edit up; so does going back to the values the task has", async ({
    tasks,
    frames,
  }) => {
    const tags = tasks.cell(FIRST, "tags")
    await tasks.press("Escape")
    await expect(tags).toHaveText("api, customer, quick-win")
    await expect(tags).not.toHaveAttribute("aria-invalid")
    await expect(tags).toBeFocused()

    // failed once more, and then the fourth value is taken away again
    await tasks.press("Enter")
    await tags.getByRole("button", { name: "Add value" }).click()
    await tasks.page.keyboard.type("y")
    await tasks.saves(tags, () => tasks.press("Enter"))
    await expect(tags).toHaveAttribute("aria-invalid", "true")

    await tasks.press("Enter")
    await tags.getByRole("button", { name: "Remove Tags 4" }).click()
    await frames.clear()
    await tasks.press("Enter")
    await expect(tags).toHaveText("api, customer, quick-win")
    await expect(tags).not.toHaveAttribute("aria-invalid")
    expect(await frames.count("save"), "the task's own values: no action runs").toBe(0)
  })
})

test.describe("an array of enum values: multiple choice", () => {
  test("Enter opens a list of boxes in the cell: one per value of the enum in declared order, named by its label, the task's ticked", async ({
    tasks,
    frames,
  }) => {
    const checks = tasks.cell(FIRST, "checks")
    await checks.focus()
    await frames.clear()
    await tasks.press("Enter")

    await expect(group(checks, "Checks")).toBeVisible()
    expect(await ticks(checks)).toEqual(["x Reviewed", "  Tested", "  Documented", "x Released"])

    for (const name of ["Reviewed", "Tested", "Documented", "Released"]) {
      await expect(checks.getByRole("checkbox", { name, exact: true })).toBeVisible()
    }

    await expect(boxes(checks).nth(0)).toBeFocused()
    expect(await frames.all()).toEqual([])
  })

  test("Space ticks, the arrow keys go from box to box, and Enter saves once: nothing is sent before", async ({
    page,
    tasks,
    frames,
  }) => {
    const checks = tasks.cell(FIRST, "checks")
    await checks.focus()
    await tasks.press("Enter")
    await frames.clear()

    // Reviewed off, Tested on, Documented on
    await page.keyboard.press("Space")
    await tasks.press("ArrowDown")
    await expect(boxes(checks).nth(1)).toBeFocused()
    await page.keyboard.press("Space")
    await tasks.press("ArrowDown")
    await page.keyboard.press("Space")
    // the arrow keys stop at the ends, and never leave the cell
    await tasks.press("ArrowDown", "ArrowDown", "ArrowDown")
    await expect(boxes(checks).nth(3)).toBeFocused()
    await tasks.press("ArrowUp")
    await expect(boxes(checks).nth(2)).toBeFocused()
    await tasks.press("ArrowLeft", "ArrowRight")
    await expect(boxes(checks).nth(2)).toBeFocused()

    expect(await ticks(checks)).toEqual(["  Reviewed", "x Tested", "x Documented", "x Released"])
    expect(await frames.all(), "ticking is not saving").toEqual([])

    await tasks.saves(checks, async () => {
      await tasks.press("Enter")
      await expect(checks).toBeFocused()
    })

    await expect(checks).toHaveText("Tested, Documented, Released")
    await expect(checks).toBeFocused()
    await expect(checks.locator("*")).toHaveCount(0)
    expect(await frames.count("save")).toBe(1)

    const [, , , , payload] = JSON.parse((await frames.all())[0])
    expect(payload.value.value).toEqual(["tested", "documented", "released"])

    await page.reload()
    await tasks.ready()
    await expect(checks).toHaveText("Tested, Documented, Released")
  })

  test("Tab goes through the boxes, and from the last one out of the grid, which saves", async ({
    page,
    tasks,
  }) => {
    const checks = tasks.cell(SECOND, "checks")
    await expect(checks).toHaveText("Released")
    await checks.focus()
    await tasks.press("F2")

    await page.keyboard.press("Space")
    await page.keyboard.press("Tab")
    await expect(boxes(checks).nth(1)).toBeFocused()
    await page.keyboard.press("Tab")
    await page.keyboard.press("Tab")
    await expect(boxes(checks).nth(3)).toBeFocused()
    await tasks.saves(checks, () => page.keyboard.press("Tab"))

    await expect(checks).toHaveText("Reviewed, Released")
    expect(await tasks.hasFocus()).toBe(false)
  })

  test("Escape gives the ticks up; ticks that end where they began save nothing", async ({
    page,
    tasks,
    frames,
  }) => {
    const checks = tasks.cell(FIRST, "checks")
    await checks.focus()
    await tasks.press("Enter")
    await frames.clear()

    await page.keyboard.press("Space")
    await tasks.press("Escape")
    await expect(checks).toHaveText("Reviewed, Released")
    await expect(checks).toBeFocused()

    await tasks.press("Enter")
    await page.keyboard.press("Space")
    await page.keyboard.press("Space")
    await tasks.press("Enter")
    await expect(checks).toHaveText("Reviewed, Released")
    await expect(checks).toBeFocused()
    expect(await frames.all()).toEqual([])
  })

  test("a letter typed on the cell opens the list at the first choice that starts with it, and ticks nothing", async ({
    tasks,
    frames,
  }) => {
    const checks = tasks.cell(FIRST, "checks")
    await checks.focus()
    await frames.clear()
    await tasks.press("d")

    await expect(checks.getByRole("checkbox", { name: "Documented" })).toBeFocused()
    expect(await ticks(checks)).toEqual(["x Reviewed", "  Tested", "  Documented", "x Released"])
    await tasks.press("Escape")
    expect(await frames.all()).toEqual([])
  })

  test("with the pointer: a click on a box or its label ticks it and stays in the editor; a click elsewhere saves", async ({
    tasks,
  }) => {
    const checks = tasks.cell(FIRST, "checks")
    const elsewhere = tasks.cell(SECOND, "title")
    await checks.dblclick()

    await checks.getByText("Tested", { exact: true }).click()
    await expect(checks.getByRole("checkbox", { name: "Tested" })).toBeFocused()
    await checks.getByRole("checkbox", { name: "Released" }).click()
    await expect(checks.getByRole("checkbox", { name: "Released" })).toBeFocused()
    expect(await ticks(checks)).toEqual(["x Reviewed", "x Tested", "  Documented", "  Released"])

    await tasks.saves(checks, () => elsewhere.click())
    await expect(checks).toHaveText("Reviewed, Tested")
    await expect(elsewhere).toBeFocused()
  })

  test("everything unticked saves the empty array, and the cell is empty", async ({ page, tasks }) => {
    const checks = tasks.cell(SECOND, "checks")
    await checks.focus()
    await tasks.press("Enter")
    await tasks.press("ArrowDown", "ArrowDown", "ArrowDown")
    await page.keyboard.press("Space")
    await tasks.saves(checks, () => tasks.press("Enter"))

    await expect(checks).toBeEmpty()
    await expect(checks).not.toHaveAttribute("aria-invalid")
  })
})

test.describe("the member, on a task that is not theirs", () => {
  test.use({ actor: "member" })

  test("is refused on the cell of either array, with the editor's values kept", async ({ page, tasks }) => {
    const checks = tasks.cell(FIRST, "checks")
    await checks.focus()
    await tasks.press("Enter")
    await page.keyboard.press("Space")
    await tasks.saves(checks, () => tasks.press("Enter"))

    await expect(checks).toHaveAttribute("aria-invalid", "true")
    await expect(checks).toContainText("Released")
    await expect(tasks.failure(checks)).toHaveText("You are not allowed to change this.")
    await expectNoAxeViolations(page)

    await tasks.press("Enter")
    expect(await ticks(checks)).toEqual(["  Reviewed", "  Tested", "  Documented", "x Released"])
    await tasks.press("Escape")
    await tasks.press("Escape")
    await expect(checks).toHaveText("Reviewed, Released")
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

  test("is a number input per value; a digit typed on the cell starts a new value, a letter adds none", async ({
    frames,
  }) => {
    const numbers = integers.locator("[data-item] input[type=number]")
    await integers.focus()
    await frames.clear()

    await specimens.press("Enter")
    await expect(group(integers, "Integers")).toBeVisible()
    await expect(numbers).toHaveCount(before.length)
    await expect(integers.getByRole("spinbutton", { name: "Integers 1", exact: true })).toHaveValue(before[0])
    await expect(numbers.nth(0)).toBeFocused()
    await specimens.press("Escape")

    // a letter is nothing a number takes: the editor opens, and no value is added
    await specimens.press("q")
    await expect(numbers).toHaveCount(before.length)
    await expect(numbers.last()).toBeFocused()
    await specimens.press("Escape")
    await expect(integers).toBeFocused()
    expect(await frames.all()).toEqual([])

    await specimens.press("7")
    await expect(numbers).toHaveCount(before.length + 1)
    await expect(numbers.last()).toBeFocused()
    await expect(numbers.last()).toHaveValue("7")
    await specimens.saves(integers, () => specimens.press("Enter"))

    await expect(integers).toHaveText([...before, "7"].join(", "))
    await expect(integers).toBeFocused()
    expect(await frames.count("save")).toBe(1)
  })

  test("a list the action refuses is marked with the action's message: no value left, and a value below 0", async ({
    page,
  }) => {
    await integers.focus()
    await specimens.press("Enter")
    for (let left = before.length; left > 0; left--) {
      await integers.getByRole("button", { name: "Remove Integers 1", exact: true }).click()
    }
    await expect(integers.getByRole("button", { name: "Add value" })).toBeFocused()
    await specimens.saves(integers, () => page.keyboard.press("Tab"))

    await expect(integers).toHaveAttribute("aria-invalid", "true")
    await expect(specimens.failure(integers)).toHaveText("must have 1 or more items")

    // the editor opens with what was typed: nothing
    await integers.focus()
    await specimens.press("Enter")
    await expect(integers.locator("[data-item]")).toHaveCount(0)
    await page.keyboard.press("Enter")
    await page.keyboard.type("-5")
    await specimens.saves(integers, () => specimens.press("Enter"))

    await expect(integers).toHaveAttribute("aria-invalid", "true")
    await expect(integers).toContainText("-5")
    await expect(integers).toHaveAccessibleDescription("must be greater than or equal to 0")
    await page.mouse.move(5, 5)
    await expectNoAxeViolations(page)

    await specimens.press("Escape")
    await expect(integers).toHaveText(before.join(", "))
    await expect(integers).not.toHaveAttribute("aria-invalid")
  })
})

test.describe("in a nested table: the tasks under a project", () => {
  test("both editors work as on the page of the tasks; Escape gives the edit up, and only the next one leaves the table", async ({
    page,
    frames,
  }) => {
    const projects = new Table(page, "project", "/projects")
    await projects.open()
    const nested = await projects.openLine(SEED.project.mobileApp, "tasks")
    const [key] = await nested.rowKeys()
    const tags = nested.cell(key, "tags")
    const checks = nested.cell(key, "checks")

    await tags.focus()
    await projects.press("Enter")
    await expect(group(tags, "Tags")).toBeVisible()
    await tags.getByRole("button", { name: "Add value" }).focus()
    await page.keyboard.press("Enter")
    await page.keyboard.type("under-a-project")
    // while a cell is edited the controls of its editor are the tab stops of the tree
    expect((await projects.tabStops()).every((stop) => stop === "TEXTAREA" || stop === "BUTTON")).toBe(true)
    await frames.clear()
    await nested.saves(tags, () => projects.press("Enter"))

    await expect(tags).toContainText("under-a-project")
    await expect(tags).toBeFocused()
    expect(await frames.count("save")).toBe(1)
    expect(await frames.all(), "the projects around it are not read again").toHaveLength(1)
    expect(await projects.tabStops()).toHaveLength(1)

    await checks.focus()
    const before = await checks.textContent()
    await projects.press("Enter")
    await expect(boxes(checks).nth(0)).toBeFocused()
    await page.keyboard.press("Space")
    await projects.press("Escape")
    await expect(checks).toHaveText(before!)
    await expect(checks).toBeFocused()
    await projects.press("Escape")
    await expect(projects.nestedCell(SEED.project.mobileApp, "tasks")).toBeFocused()

    await checks.focus()
    await projects.press("Enter")
    await projects.press("ArrowDown", "ArrowDown", "ArrowDown")
    const released = await boxes(checks).nth(3).isChecked()
    await page.keyboard.press("Space")
    await nested.saves(checks, () => projects.press("Enter"))
    if (released) await expect(checks).not.toContainText("Released")
    else await expect(checks).toContainText("Released")
    await expect(checks).toBeFocused()
  })
})

test.describe("accessibility, with an array's editor open", () => {
  test("the list of an array of text", async ({ page, tasks }) => {
    const tags = tasks.cell(FIRST, "tags")
    await tags.focus()
    await tasks.press("Enter")
    await tags.getByRole("button", { name: "Add value" }).click()
    await expect(values(tags)).toHaveCount(4)
    await expectNoAxeViolations(page)
  })

  test("the boxes of a multiple choice", async ({ page, tasks }) => {
    const checks = tasks.cell(FIRST, "checks")
    await checks.focus()
    await tasks.press("Enter")
    await expect(boxes(checks).nth(0)).toBeFocused()
    await expectNoAxeViolations(page)
  })

  test("both in the dark theme", async ({ page, tasks }) => {
    await page.addInitScript(() => localStorage.setItem("phx:theme", "dark"))
    await tasks.open()
    await expect(page.locator("html")).toHaveAttribute("data-theme", "dark")

    const tags = tasks.cell(FIRST, "tags")
    await tags.focus()
    await tasks.press("Enter")
    await expectNoAxeViolations(page)
    await tasks.press("Escape")

    const checks = tasks.cell(FIRST, "checks")
    await checks.focus()
    await tasks.press("Enter")
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
    await tasks.field("project_id").fill(SEED.project.mobileApp)

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

    await tasks.field("title").fill("Made with arrays")
    await tasks.field("project_id").fill(SEED.project.mobileApp)
    await tags.getByRole("button", { name: "Add value" }).click()
    await page.keyboard.type("x")
    await tasks.panelSettled()

    await expect(tasks.fieldError("tags")).toHaveText(TOO_SHORT)
    await expect(tags).toHaveAccessibleDescription(TOO_SHORT)
    await expectNoAxeViolations(page)

    await tasks.panelSubmit.click()
    await tasks.panelSettled()
    await expect(tasks.panel).toBeVisible()
    await expect(tasks.fieldError("tags")).toHaveText(TOO_SHORT)
    await expect(tags.getByRole("textbox", { name: "Tags 1", exact: true })).toHaveValue("x")

    await tags.getByRole("textbox", { name: "Tags 1", exact: true }).fill("xl")
    await tasks.panelSettled()
    await expect(tasks.fieldError("tags")).toHaveCount(0)
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
