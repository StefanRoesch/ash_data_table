import type { Locator, Page } from "@playwright/test"
import { expectNoAxeViolations } from "./support/a11y"
import { MAPS } from "./support/data"
import { expect, test } from "./support/fixtures"
import { switchLocale } from "./support/locale"
import { Table } from "./support/table"

// A sensitive column in a browser: "Budget" at /projects. Its cells show a
// mask, the same for every budget, and a button; the budget itself is not in
// the page, and not in what the server sends, until somebody asks for the
// one cell. It is hidden again when focus leaves the cell. Its editor hides
// what is typed. A member may see a project's budget; a viewer has no such
// column.

/** Projects of Acme by what their budget is in the seed. */
const PORTAL = { id: MAPS.project.customerPortal.id, budget: "23500" }
const WAREHOUSE = { id: MAPS.project.dataWarehouse, budget: "57500" }
const TOOLS = { id: MAPS.project.internalTools.id, budget: "85500" }
/** "Mobile app" has none. */
const MOBILE = "72f2d7c8-f124-4435-9f12-15b4956af76b"
/** Every budget of the seed's projects of Acme. */
const BUDGETS = ["66500", "23500", "57500", "85500", "86000"]

const MASK = "••••••"

test.use({ actor: "member" })

function projectsOf(page: Page): Table {
  return new Table(page, "project", "/projects")
}

/** What the page received over its WebSocket: the rows, the patches, the answers. */
class Received {
  private frames: string[] = []

  constructor(page: Page) {
    page.on("websocket", (socket) => {
      socket.on("framereceived", (frame) => {
        if (typeof frame.payload === "string") this.frames.push(frame.payload)
      })
    })
  }

  clear(): void {
    this.frames = []
  }

  /** The frames that hold `text`. */
  holding(text: string): string[] {
    return this.frames.filter((frame) => frame.includes(text))
  }

  get count(): number {
    return this.frames.length
  }
}

/** The parts of a sensitive cell. */
function parts(cell: Locator) {
  return {
    mask: cell.locator("[data-mask]"),
    value: cell.locator("[data-secret]"),
    button: cell.getByRole("button"),
  }
}

/** What the grid holds, as markup: where a budget must never be. */
async function markup(projects: Table): Promise<string> {
  return projects.root.evaluate((root) => root.outerHTML)
}

async function expectNoBudgetIn(text: string): Promise<void> {
  for (const budget of BUDGETS) expect(text, `the budget ${budget}`).not.toContain(budget)
}

/** The height of a row, which showing a value must not change. */
async function rowHeight(projects: Table, key: string): Promise<number> {
  const box = await projects.row(key).getByRole("row").boundingBox()
  return box!.height
}

test.describe("a sensitive cell at rest", () => {
  test("shows the mask and a button named with the column; an empty one shows nothing", async ({ page }) => {
    const projects = projectsOf(page)
    await projects.open()

    for (const project of [PORTAL, WAREHOUSE, TOOLS]) {
      const cell = projects.cell(project.id, "budget")
      const { mask, value, button } = parts(cell)

      await expect(mask).toHaveText(MASK)
      await expect(mask).toHaveAttribute("aria-hidden", "true")
      await expect(value).toHaveText("")
      await expect(value).toHaveAttribute("aria-live", "polite")
      await expect(button).toHaveText("Show")
      await expect(button).toHaveAccessibleName("Show Budget")
      // no tab stop of its own: the grid has one
      await expect(button).toHaveAttribute("tabindex", "-1")
    }

    const empty = projects.cell(MOBILE, "budget")
    await expect(empty).toHaveText("")
    await expect(empty.locator("*")).toHaveCount(0)
  })

  test("holds nothing of the budget: not in the page, and not in what the server sent", async ({ page }) => {
    const received = new Received(page)
    const projects = projectsOf(page)
    await projects.open()

    expect(received.count).toBeGreaterThan(0)
    await expectNoBudgetIn(await markup(projects))
    for (const budget of BUDGETS) expect(received.holding(budget), `frames with ${budget}`).toEqual([])
    // the rows did come over the wire
    expect(received.holding("Customer portal").length).toBeGreaterThan(0)
  })

  test("is neither sorted nor filtered by, and a URL that says so is not followed", async ({ page, pushed }) => {
    const projects = projectsOf(page)
    await projects.open()

    await expect(projects.header("budget")).not.toHaveAttribute("aria-sort")
    await expect(projects.filterCell("budget").locator("input, select, button")).toHaveCount(0)
    await pushed.clear()
    await projects.header("budget").click()
    expect(await pushed.all()).toEqual([])

    const before = await projects.columnTexts("name")
    await projects.open(`/projects?project[sort]=-budget&project[f][budget]=${PORTAL.budget}`)
    expect(await projects.columnTexts("name")).toEqual(before)
  })

  test("is as high as every other row, with a budget or without", async ({ page }) => {
    const projects = projectsOf(page)
    await projects.open()

    expect(await rowHeight(projects, PORTAL.id)).toBe(await rowHeight(projects, MOBILE))
  })
})

test.describe("showing a value", () => {
  test("the button asks the server for the one cell, and the cell shows and says the value", async ({
    page,
    pushed,
  }) => {
    const received = new Received(page)
    const projects = projectsOf(page)
    await projects.open()
    const cell = projects.cell(PORTAL.id, "budget")
    const { mask, value, button } = parts(cell)
    const height = await rowHeight(projects, PORTAL.id)

    await pushed.clear()
    received.clear()
    await button.click()

    await expect(value).toHaveText(PORTAL.budget)
    await expect(mask).toBeHidden()
    await expect(button).toHaveText("Hide")
    await expect(button).toHaveAccessibleName("Hide Budget")
    // the value is shown for as long as the cell has the focus
    await expect(cell).toBeFocused()
    expect(await rowHeight(projects, PORTAL.id)).toBe(height)

    // one event, with the row and the column, and one answer with the value
    expect(await pushed.count("reveal")).toBe(1)
    expect((await pushed.all()).length).toBe(1)
    expect(received.holding(PORTAL.budget).length).toBe(1)
    // and no other budget came with it
    for (const budget of BUDGETS.filter((budget) => budget !== PORTAL.budget)) {
      expect(received.holding(budget)).toEqual([])
    }
  })

  test("the button hides it again, and so does leaving the cell: nothing of it stays in the page", async ({
    page,
  }) => {
    const projects = projectsOf(page)
    await projects.open()
    const cell = projects.cell(PORTAL.id, "budget")
    const { mask, value, button } = parts(cell)

    await button.click()
    await expect(value).toHaveText(PORTAL.budget)
    await button.click()
    await expect(value).toHaveText("")
    await expect(mask).toBeVisible()
    await expect(button).toHaveAccessibleName("Show Budget")
    await expectNoBudgetIn(await markup(projects))

    await button.click()
    await expect(value).toHaveText(PORTAL.budget)
    await projects.press("ArrowRight")
    await expect(projects.cell(PORTAL.id, "client")).toBeFocused()
    await expect(value).toHaveText("")
    await expect(mask).toBeVisible()
    await expectNoBudgetIn(await markup(projects))
  })

  test("Shift+Enter on the cell shows it and hides it; Escape hides it; Tab out of the grid hides it", async ({
    page,
    pushed,
  }) => {
    const projects = projectsOf(page)
    await projects.open()
    const cell = projects.cell(WAREHOUSE.id, "budget")
    const { mask, value } = parts(cell)

    await cell.focus()
    await pushed.clear()
    await projects.press("Shift+Enter")
    await expect(value).toHaveText(WAREHOUSE.budget)
    await expect(cell).toBeFocused()
    expect(await pushed.count("reveal")).toBe(1)
    // no editor: Enter alone is the editor's
    await expect(projects.openEditors).toHaveCount(0)

    await projects.press("Shift+Enter")
    await expect(value).toHaveText("")
    await expect(mask).toBeVisible()

    await projects.press("Shift+Enter")
    await expect(value).toHaveText(WAREHOUSE.budget)
    await projects.press("Escape")
    await expect(value).toHaveText("")
    await expect(cell).toBeFocused()

    await projects.press("Shift+Enter")
    await expect(value).toHaveText(WAREHOUSE.budget)
    await projects.press("Tab")
    await expect(value).toHaveText("")
    await expect(mask).toBeVisible()
    await expectNoBudgetIn(await markup(projects))
  })

  test("one cell at a time: showing another hides the first", async ({ page }) => {
    const projects = projectsOf(page)
    await projects.open()
    const first = parts(projects.cell(PORTAL.id, "budget"))
    const second = parts(projects.cell(TOOLS.id, "budget"))

    await first.button.click()
    await expect(first.value).toHaveText(PORTAL.budget)
    await second.button.click()
    await expect(second.value).toHaveText(TOOLS.budget)
    await expect(first.value).toHaveText("")
    await expect(first.mask).toBeVisible()
  })

  test("a new read of the table hides it, though focus stays where it was", async ({ page }) => {
    const projects = projectsOf(page)
    await projects.open()
    const cell = projects.cell(PORTAL.id, "budget")
    const { mask, value, button } = parts(cell)

    await cell.focus()
    await projects.press("Shift+Enter")
    await expect(value).toHaveText(PORTAL.budget)

    // sorted by a script, as nothing a person does leaves focus in the cell
    await projects.reads(() => projects.header("name").evaluate((header: HTMLElement) => header.click()))

    await expect(projects.header("name")).toHaveAttribute("aria-sort", "ascending")
    await expect(value).toHaveText("")
    await expect(mask).toBeVisible()
    await expect(button).toHaveAccessibleName("Show Budget")
    await expectNoBudgetIn(await markup(projects))
  })

  test("an empty cell has nothing to show: Shift+Enter asks nothing", async ({ page, pushed }) => {
    const projects = projectsOf(page)
    await projects.open()

    await projects.cell(MOBILE, "budget").focus()
    await pushed.clear()
    await projects.press("Shift+Enter")
    expect(await pushed.all()).toEqual([])
  })
})

test.describe("editing a sensitive cell", () => {
  test("Enter opens an editor that hides what is typed, and holds nothing; Escape gives it up", async ({
    page,
    pushed,
  }) => {
    const projects = projectsOf(page)
    await projects.open()
    const cell = projects.cell(PORTAL.id, "budget")

    await cell.focus()
    await projects.press("Enter")
    const editor = projects.editor(cell)
    await expect(editor).toBeFocused()
    await expect(editor).toHaveAttribute("type", "password")
    await expect(editor).toHaveAccessibleName("Budget")
    await expect(editor).toHaveValue("")

    await pushed.clear()
    await page.keyboard.type("99")
    await projects.press("Escape")
    await expect(projects.openEditors).toHaveCount(0)
    await expect(cell).toBeFocused()
    await expect(parts(cell).mask).toHaveText(MASK)
    expect(await pushed.all()).toEqual([])
  })

  test("an editor nothing was typed into saves nothing", async ({ page, pushed }) => {
    const projects = projectsOf(page)
    await projects.open()
    const cell = projects.cell(PORTAL.id, "budget")

    await cell.focus()
    await pushed.clear()
    await projects.press("Enter", "Enter")
    await expect(projects.openEditors).toHaveCount(0)
    expect(await pushed.all()).toEqual([])

    // and the budget is what it was
    await projects.press("Shift+Enter")
    await expect(parts(cell).value).toHaveText(PORTAL.budget)
  })

  test("what is typed is saved, and is shown nowhere: the cell keeps its mask, and the server sends nothing of it back", async ({
    page,
    pushed,
  }) => {
    const received = new Received(page)
    const projects = projectsOf(page)
    await projects.open()
    const cell = projects.cell(PORTAL.id, "budget")
    const height = await rowHeight(projects, PORTAL.id)

    await cell.focus()
    await projects.press("Enter")
    await page.keyboard.type("4455667")
    expect(await rowHeight(projects, PORTAL.id)).toBe(height)

    received.clear()
    await pushed.clear()
    await projects.saves(cell, () => projects.press("Enter"))

    expect(await pushed.count("save")).toBe(1)
    await expect(parts(cell).mask).toHaveText(MASK)
    await expect(cell).toBeFocused()
    expect(await markup(projects)).not.toContain("4455667")
    expect(received.holding("4455667")).toEqual([])

    await projects.press("Shift+Enter")
    await expect(parts(cell).value).toHaveText("4455667")
  })

  test("typing on the cell starts the editor with what is typed, hidden", async ({ page }) => {
    const projects = projectsOf(page)
    await projects.open()
    const cell = projects.cell(MOBILE, "budget")

    await cell.focus()
    await page.keyboard.type("1500")
    const editor = projects.editor(cell)
    await expect(editor).toHaveAttribute("type", "password")
    await expect(editor).toHaveValue("1500")

    await projects.saves(cell, () => projects.press("Enter"))
    // the cell had no budget: it has its mask now
    await expect(parts(cell).mask).toHaveText(MASK)
    await expect(parts(cell).button).toHaveAccessibleName("Show Budget")
  })

  test("a save the action refuses marks the cell, which shows its mask and never what was typed", async ({
    page,
  }) => {
    const received = new Received(page)
    const projects = projectsOf(page)
    await projects.open()
    const cell = projects.cell(PORTAL.id, "budget")

    await cell.focus()
    await projects.press("Enter")
    await page.keyboard.type("77x88x99")
    received.clear()
    await projects.saves(cell, () => projects.press("Enter"))

    await expect(cell).toHaveAttribute("aria-invalid", "true")
    await expect(projects.failure(cell)).toHaveText("is invalid")
    await expect(parts(cell).mask).toHaveText(MASK)
    await expect(projects.status).toHaveText(/Budget was not saved: is invalid/)
    expect(await markup(projects)).not.toContain("77x88x99")
    expect(received.holding("77x88x99")).toEqual([])
    await expectNoBudgetIn(await markup(projects))

    // the editor opens empty again, and Escape on the cell gives the edit up
    await projects.press("Enter")
    await expect(projects.editor(cell)).toHaveValue("")
    await projects.press("Escape", "Escape")
    await expect(cell).not.toHaveAttribute("aria-invalid")
    await expect(cell).toBeFocused()
  })
})

// A sensitive cell cannot say "no value" by what is typed: its editor starts
// empty, and an empty editor saves nothing. So the editor has a button that
// asks for it, "Clear", where the cell holds a value and the column can be
// empty. So has the field of a row action's panel.
test.describe("emptying a sensitive cell", () => {
  /** Opens the editor of a budget cell and returns its input and its button. */
  async function open(projects: Table, cell: Locator) {
    await cell.focus()
    await projects.press("Enter")
    const editor = projects.editor(cell)
    await expect(editor).toBeFocused()
    return { editor, clear: cell.getByRole("button", { name: "Clear Budget" }) }
  }

  test("the editor of a cell with a budget has \"Clear\", named with the column; one without a budget has none", async ({
    page,
  }) => {
    const projects = projectsOf(page)
    await projects.open()
    const cell = projects.cell(PORTAL.id, "budget")
    const height = await rowHeight(projects, PORTAL.id)
    const width = (await cell.boundingBox())!.width

    const { clear } = await open(projects, cell)
    await expect(clear).toBeVisible()
    await expect(clear).toHaveText("Clear")
    await expect(clear).toHaveAttribute("type", "button")
    // The row is as high as it was. The cell is as wide as the input and
    // the button need: in a column no wider than its mask, a little wider.
    expect(await rowHeight(projects, PORTAL.id)).toBe(height)
    expect((await cell.boundingBox())!.width).toBeLessThanOrEqual(width + 20)
    await projects.press("Escape")

    const empty = projects.cell(MOBILE, "budget")
    await empty.focus()
    await projects.press("Enter")
    await expect(projects.editor(empty)).toBeFocused()
    await expect(empty.getByRole("button")).toHaveCount(0)
  })

  test("Tab goes from the input to \"Clear\" and Shift+Tab back, without closing the editor or saving", async ({
    page,
    pushed,
  }) => {
    const projects = projectsOf(page)
    await projects.open()
    const cell = projects.cell(PORTAL.id, "budget")
    const { editor, clear } = await open(projects, cell)
    await pushed.clear()

    await page.keyboard.type("12")
    await projects.press("Tab")
    await expect(clear).toBeFocused()
    await expect(projects.openEditors).toHaveCount(1)
    await projects.press("Shift+Tab")
    await expect(editor).toBeFocused()
    await expect(editor, "what was typed is still there").toHaveValue("12")
    expect(await pushed.all(), "nothing was saved on the way").toEqual([])

    // Escape on the button gives the edit up, as it does on the input
    await projects.press("Tab")
    await expect(clear).toBeFocused()
    await projects.press("Escape")
    await expect(projects.openEditors).toHaveCount(0)
    await expect(cell).toBeFocused()
    expect(await pushed.all()).toEqual([])
    await projects.press("Shift+Enter")
    await expect(parts(cell).value).toHaveText(PORTAL.budget)
  })

  test("Tab from \"Clear\" leaves the grid and saves what was typed, as leaving the input does", async ({
    page,
    pushed,
  }) => {
    const projects = projectsOf(page)
    await projects.open()
    const cell = projects.cell(PORTAL.id, "budget")
    const { clear } = await open(projects, cell)
    await page.keyboard.type("4455")
    await projects.press("Tab")
    await expect(clear).toBeFocused()
    await pushed.clear()

    await projects.saves(cell, () => projects.press("Tab"))

    expect(await projects.hasFocus()).toBe(false)
    expect(await pushed.count("save")).toBe(1)
    expect(await pushed.count("clear")).toBe(0)
    await expect(projects.openEditors).toHaveCount(0)
    await cell.focus()
    await projects.press("Shift+Enter")
    await expect(parts(cell).value).toHaveText("4455")
  })

  for (const key of ["Enter", "Space"] as const) {
    test(`${key} on "Clear" empties the budget: one event that names the cell, and the cell is empty`, async ({
      page,
      pushed,
    }) => {
      const received = new Received(page)
      const projects = projectsOf(page)
      await projects.open()
      const cell = projects.cell(PORTAL.id, "budget")
      const { clear } = await open(projects, cell)
      // what was typed is given up: "Clear" is what was asked for
      await page.keyboard.type("999")
      await projects.press("Tab")
      await expect(clear).toBeFocused()
      await pushed.clear()
      received.clear()

      await projects.saves(cell, () => projects.press(key))

      expect(await pushed.count("clear")).toBe(1)
      expect(await pushed.count("save")).toBe(0)
      const [sent] = (await pushed.all()).filter((one) => one.event === "clear")
      // the server is asked by name: the row and the column, and no value
      expect(sent.params).toEqual({ row: PORTAL.id, column: "budget" })

      await expect(projects.openEditors).toHaveCount(0)
      await expect(cell).toBeFocused()
      await expect(cell).toHaveText("")
      await expect(cell.getByRole("button")).toHaveCount(0)
      await expect(cell).not.toHaveAttribute("aria-invalid")
      expect(received.holding(PORTAL.budget), "the budget it had is not sent").toEqual([])
      expect(received.holding("999")).toEqual([])

      // it is empty for good: the page read again says the same
      await projects.open()
      await expect(projects.cell(PORTAL.id, "budget")).toHaveText("")
      // and the other budgets are as they were
      const other = projects.cell(TOOLS.id, "budget")
      await other.focus()
      await projects.press("Shift+Enter")
      await expect(parts(other).value).toHaveText(TOOLS.budget)
    })
  }

  test("a click on \"Clear\" empties the budget too, and an empty editor still saves nothing", async ({
    page,
    pushed,
  }) => {
    const projects = projectsOf(page)
    await projects.open()
    const cell = projects.cell(PORTAL.id, "budget")

    // nothing typed, Enter: nothing is sent, and the budget stays
    await open(projects, cell)
    await pushed.clear()
    await projects.press("Enter")
    await expect(projects.openEditors).toHaveCount(0)
    expect(await pushed.all()).toEqual([])
    await expect(parts(cell).mask).toHaveText(MASK)

    const { clear } = await open(projects, cell)
    await projects.saves(cell, () => clear.click())
    expect(await pushed.count("clear")).toBe(1)
    await expect(cell).toHaveText("")
    await expect(cell).toBeFocused()
  })

  test("a column with a question asks it first: Cancel goes back to the editor, Confirm empties", async ({
    page,
    pushed,
  }) => {
    const projects = projectsOf(page)
    await projects.open()
    // The demo's budget column has no `confirm`. The hook reads a column's
    // question from the column's editor, as the server renders it there:
    // here it is put there by hand.
    await page.evaluate(() => {
      document.getElementById("project-editor-budget")!.dataset.confirm = "Change the budget?"
    })
    const cell = projects.cell(PORTAL.id, "budget")
    const { editor, clear } = await open(projects, cell)
    await pushed.clear()

    await clear.click()
    await expect(projects.question.locator("p")).toHaveText("Change the budget?")
    await projects.question.getByRole("button", { name: "Cancel" }).click()
    await expect(editor).toBeFocused()
    expect(await pushed.all()).toEqual([])
    await expect(projects.openEditors).toHaveCount(1)

    await clear.click()
    await expect(projects.question.locator("p")).toHaveText("Change the budget?")
    await projects.saves(cell, () => projects.question.getByRole("button", { name: "Confirm" }).click())
    expect(await pushed.count("clear")).toBe(1)
    await expect(cell).toHaveText("")
  })
})

test.describe("emptying a sensitive field of the action panel", () => {
  test("\"Set budget\" has \"Clear\" for a project with a budget, and none for one without", async ({ page }) => {
    const projects = projectsOf(page)
    await projects.open()

    await projects.action(MOBILE, "set_budget").click()
    await expect(projects.panel).toBeVisible()
    await expect(projects.field("budget")).toHaveAttribute("type", "password")
    await expect(projects.panel.getByRole("button", { name: /Clear|Keep/ })).toHaveCount(0)
    await projects.panelCancel.click()
    await expect(projects.panel).toHaveCount(0)

    await projects.action(PORTAL.id, "set_budget").click()
    await expect(projects.panel).toBeVisible()
    const clear = projects.panel.getByRole("button", { name: "Clear Budget" })
    await expect(clear).toHaveText("Clear")
    // after the field, before the panel's own buttons: Tab goes there from the input
    await expect(projects.field("budget")).toBeFocused()
    await projects.press("Tab")
    await expect(clear).toBeFocused()
  })

  test("used, the field says that it will be cleared and the button says \"Keep\"; \"Keep\" takes it back; nothing has run", async ({
    page,
    pushed,
  }) => {
    const projects = projectsOf(page)
    await projects.open()
    await projects.action(PORTAL.id, "set_budget").click()
    await expect(projects.panel).toBeVisible()
    await pushed.clear()

    await projects.press("Tab", "Enter")
    const keep = projects.panel.getByRole("button", { name: "Keep Budget" })
    await expect(keep).toHaveText("Keep")
    await expect(keep, "focus stays on the button").toBeFocused()
    await expect(keep).toHaveAccessibleDescription("Will be cleared.")
    await expect(projects.panel.getByText("Will be cleared.")).toBeVisible()
    await expect(projects.field("budget")).toHaveCount(0)
    expect(await pushed.count("panel_submit")).toBe(0)

    await projects.press("Enter")
    const clear = projects.panel.getByRole("button", { name: "Clear Budget" })
    await expect(clear).toBeFocused()
    await expect(projects.panel.getByText("Will be cleared.")).toHaveCount(0)
    await expect(projects.field("budget")).toHaveAttribute("type", "password")
    await expect(projects.field("budget")).toHaveValue("")

    // run as it is: an empty field changes nothing
    await projects.panelSubmit.click()
    await expect(projects.panel).toHaveCount(0)
    const cell = projects.cell(PORTAL.id, "budget")
    await cell.focus()
    await projects.press("Shift+Enter")
    await expect(parts(cell).value).toHaveText(PORTAL.budget)
  })

  test("\"Run\" empties the budget that was asked to be cleared, and nothing of it is sent", async ({ page }) => {
    const received = new Received(page)
    const projects = projectsOf(page)
    await projects.open()
    await projects.action(PORTAL.id, "set_budget").click()
    await expect(projects.panel).toBeVisible()

    await projects.panel.getByRole("button", { name: "Clear Budget" }).click()
    await expect(projects.panel.getByText("Will be cleared.")).toBeVisible()
    received.clear()
    await projects.panelSubmit.click()
    await expect(projects.panel).toHaveCount(0)

    const cell = projects.cell(PORTAL.id, "budget")
    await expect(cell).toHaveText("")
    await expect(cell.getByRole("button")).toHaveCount(0)
    expect(received.holding(PORTAL.budget)).toEqual([])
  })
})

test.describe("who may see the budget", () => {
  test.describe("a viewer", () => {
    test.use({ actor: "viewer" })

    test("has no such column, and nothing of a budget in the page", async ({ page }) => {
      const received = new Received(page)
      const projects = projectsOf(page)
      await projects.open()

      expect(await projects.columns()).not.toContain("budget")
      await expectNoBudgetIn(await markup(projects))
      for (const budget of BUDGETS) expect(received.holding(budget)).toEqual([])
    })
  })

  test.describe("an admin", () => {
    test.use({ actor: "admin" })

    test("types a budget hidden in the panel of a new project", async ({ page }) => {
      const projects = projectsOf(page)
      await projects.open()

      await projects.create.click()
      await expect(projects.panel).toBeVisible()
      await expect(projects.field("budget")).toHaveAttribute("type", "password")
      await expect(projects.field("budget")).toHaveValue("")
      await expect(projects.field("budget")).toHaveAccessibleName("Budget")
    })
  })
})

test("in German the cell and its button speak German", async ({ page }) => {
  const projects = projectsOf(page)
  await projects.open()
  await switchLocale(page, "de")
  await projects.ready()

  const { button, value } = parts(projects.cell(PORTAL.id, "budget"))
  await expect(button).toHaveText("Anzeigen")
  await expect(button).toHaveAccessibleName("Budget anzeigen")
  await button.click()
  await expect(value).toHaveText(PORTAL.budget)
  await expect(button).toHaveText("Verbergen")
  await expect(button).toHaveAccessibleName("Budget verbergen")

  // and so does "Clear", in the editor and in the panel
  const cell = projects.cell(PORTAL.id, "budget")
  await cell.focus()
  await projects.press("Enter")
  const clear = cell.getByRole("button", { name: "Budget leeren" })
  await expect(clear).toHaveText("Leeren")
  await projects.press("Escape")

  await projects.action(PORTAL.id, "set_budget").click()
  await expect(projects.panelTitle).toHaveText(/^Budget setzen/)
  await projects.panel.getByRole("button", { name: "Budget leeren" }).click()
  await expect(projects.panel.getByText("Wird geleert.")).toBeVisible()
  await expect(projects.panel.getByRole("button", { name: "Budget behalten" })).toHaveText("Behalten")
  await projects.panelCancel.click()

  await switchLocale(page, "en")
})

// axe-core on every state this file brings a table into, in both themes.
for (const theme of ["light", "dark"] as const) {
  test.describe(`axe, in the ${theme} theme`, () => {
    test.beforeEach(async ({ page }) => {
      await page.addInitScript((theme) => localStorage.setItem("phx:theme", theme), theme)
      await projectsOf(page).open()
      await expect(page.locator("html")).toHaveAttribute("data-theme", theme)
    })

    test("masked cells, a value that is shown, the editor, and a failed save", async ({ page }) => {
      const projects = projectsOf(page)
      const cell = projects.cell(PORTAL.id, "budget")

      await expectNoAxeViolations(page)

      await cell.focus()
      await projects.press("Shift+Enter")
      await expect(parts(cell).value).toHaveText(PORTAL.budget)
      await expectNoAxeViolations(page)

      await projects.press("Enter")
      await expect(projects.editor(cell)).toBeFocused()
      await expectNoAxeViolations(page)

      await page.keyboard.type("77x88x99")
      await projects.saves(cell, () => projects.press("Enter"))
      await expect(cell).toHaveAttribute("aria-invalid", "true")
      await expectNoAxeViolations(page)
    })

    test("\"Clear\" in the editor, and in the action panel before and after it is used", async ({ page }) => {
      const projects = projectsOf(page)
      const cell = projects.cell(PORTAL.id, "budget")

      await cell.focus()
      await projects.press("Enter", "Tab")
      await expect(cell.getByRole("button", { name: "Clear Budget" })).toBeFocused()
      await expectNoAxeViolations(page)
      await projects.press("Escape")

      await projects.action(PORTAL.id, "set_budget").click()
      await expect(projects.panel).toBeVisible()
      await expectNoAxeViolations(page)
      await projects.panel.getByRole("button", { name: "Clear Budget" }).click()
      await expect(projects.panel.getByRole("button", { name: "Keep Budget" })).toBeVisible()
      await expectNoAxeViolations(page)
    })
  })
}
