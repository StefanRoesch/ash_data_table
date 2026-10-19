import type { Page } from "@playwright/test"
import { expect, test } from "./support/fixtures"
import { Table } from "./support/table"

// The grid's hook finds the table's elements by their markers alone:
// /e2e/markers draws a grid with
// `div`s and `span`s, no `table`, `tr` or `td`, that carries the markers
// (`DemoWeb.E2E.MarkersLive`), with a table nested in a cell. If the hook
// relied on a tag, these would fail.
//
// And the development check of the hooks: while LiveView's client
// debug is on, a part that lacks a marker is named on the console.

const cell = (page: Page, key: string, column: string) => page.locator(`[id="kit-row-${key}-c-${column}"]`)
const holder = (page: Page) => page.locator('[id="kit-row-a-n-parts-c"]')
const line = (page: Page) => page.locator('[id="kit-row-a-l-parts-c"]')
const part = (page: Page, key: string) => page.locator(`[id="kit-row-a-t-parts-row-${key}-c-title"]`)

/** The table of /e2e/markers, for its Tab walks: `Table.walk` names what has focus after each press. */
const kit = (page: Page) => new Table(page, "kit", "/e2e/markers")

async function opened(page: Page, path = "/e2e/markers"): Promise<void> {
  await page.goto(path)
  await expect(page.locator('[id="kit-grid"]')).toBeAttached()
  // connected: the join's patch, which mounts the hooks, is in the page
  await expect(page.locator(".phx-connected").first()).toBeAttached()
}

test.describe("a grid drawn with other elements than a table's", () => {
  test.beforeEach(async ({ page }) => {
    await opened(page)
  })

  test("Tab goes from control to control in page order, over the nested table, and passes over read-only cells", async ({
    page,
    pushed,
  }) => {
    // the hook has put "Show all" into the note that cuts its text off
    await expect(cell(page, "a", "note").locator(":scope > [data-whole]")).toBeAttached()
    await page.locator('[id="kit-columns-button"]').focus()
    const stops = [
      "kit-select-head>input",
      "kit-row-a-s>input",
      // its one editable cell; "Size" is read-only, "Note" offers its whole text
      "kit-row-a-c-name",
      "kit-row-a-c-note>button",
      // the line under it; the nested table under that has no stop, its cells are read-only
      "kit-row-a-l-parts-c>button",
      "kit-row-b-s>input",
      "kit-row-b-c-name",
      "kit-row-c-s>input",
      "kit-row-c-c-name",
    ]
    expect(await kit(page).walk(stops.length)).toEqual(stops)
    expect(await kit(page).walk(stops.length - 1, true)).toEqual(stops.slice(0, -1).reverse())
    // moving about sends nothing
    expect(await pushed.besides("select")).toEqual([])
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
    // the save has been answered: a cell whose save is on its way opens no editor
    await expect(name).not.toHaveAttribute("aria-busy")

    await page.keyboard.press("Enter")
    await expect(name.locator("textarea")).toBeFocused()
    await page.keyboard.type("Axe")
    await page.keyboard.press("Escape")
    await expect(name).toHaveText("Anvil")
    await expect(name).toBeFocused()
  })

  test("Space on a row's box selects the row, and the box of the page selects its records, not the header, which is a row group too", async ({
    page,
    pushed,
  }) => {
    const box = (key: string) => page.locator(`[id="kit-row-${key}-s"] input`)
    await box("a").focus()
    await page.keyboard.press(" ")
    await expect(box("a")).toBeChecked()
    await expect(box("b")).not.toBeChecked()
    await expect.poll(() => pushed.selected("kit")).toEqual(["a"])

    await expect(page.locator('[id="kit-head"]')).toHaveAttribute("role", "rowgroup")
    await page.locator('[id="kit-select-head"] input').focus()
    await page.keyboard.press(" ")
    for (const key of ["a", "b", "c"]) await expect(box(key)).toBeChecked()
    await expect.poll(async () => [...((await pushed.selected("kit")) as string[])].sort()).toEqual(["a", "b", "c"])
    // no row says it is selected but by its box
    await expect(page.locator('[id="kit"] [aria-selected]')).toHaveCount(0)
  })

  test("a column is made wider with its handle, and from the keyboard in its width field; Reset widths undoes both", async ({
    page,
  }) => {
    const head = page.locator('[id="kit-head-name"]')
    const width = async () => Math.round((await cell(page, "a", "name").boundingBox())!.width)
    const before = await width()

    // the handle, dragged with the pointer
    const handle = (await page.locator('[id="kit-resize-name"]').boundingBox())!
    await page.mouse.move(handle.x + handle.width / 2, handle.y + handle.height / 2)
    await page.mouse.down()
    await page.mouse.move(handle.x + handle.width / 2 + 30, handle.y + handle.height / 2 + 3, { steps: 4 })
    await page.mouse.up()
    await expect.poll(async () => (await width()) - before).toBeGreaterThanOrEqual(29)
    await expect
      .poll(async () => Math.round((await head.boundingBox())!.width))
      .toBe(Math.round((await cell(page, "b", "name").boundingBox())!.width))

    // the width field of the list of "Columns", from the keyboard
    await page.locator('[id="kit-columns-button"]').click()
    const field = page.locator('[id="kit-column-name-width"]')
    await expect(field).toBeVisible()
    await field.focus()
    await page.keyboard.press("ControlOrMeta+A")
    await page.keyboard.type("200")
    await page.keyboard.press("Tab")
    await expect.poll(width).toBe(200)

    await page.locator('[id="kit-reset-widths"]').focus()
    await page.keyboard.press("Enter")
    await expect.poll(width).toBe(before)
  })

  test("a cell that cuts its text off after its lines offers its whole text in place: a button, a Tab stop named after its column", async ({
    page,
  }) => {
    const note = cell(page, "a", "note")
    // the button the hook puts into the cell (`data-whole`)
    const whole = note.locator(":scope > [data-whole]")
    expect(await note.evaluate((node) => {
      const paragraph = node.querySelector(":scope > [data-paragraph]")!
      return paragraph.scrollHeight > paragraph.clientHeight
    })).toBe(true)
    // the whole text is in the cell, for a screen reader
    await expect(note.locator(":scope > [data-paragraph]")).toHaveText(/where it is kept$/)

    await expect(whole).toBeVisible()
    await expect(whole).toHaveRole("button")
    await expect(whole).toHaveAccessibleName("Show all of Note")
    await expect(whole).toHaveAttribute("data-whole", "Show all")
    await expect(whole).toHaveAttribute("aria-expanded", "false")

    // Enter on it shows it all, and cuts it off again; focus stays on it
    await whole.focus()
    await page.keyboard.press("Enter")
    await expect(whole).toHaveAttribute("aria-expanded", "true")
    await expect(whole).toHaveAttribute("data-whole", "Show less")
    await expect(whole).toHaveAccessibleName("Show less of Note")
    await expect(whole).toBeFocused()
    await page.keyboard.press("Enter")
    await expect(whole).toHaveAttribute("aria-expanded", "false")
    await expect(whole).toBeFocused()

    // Space too, as on any button; a click does the same, and the text
    // stays whole while focus moves on
    await page.keyboard.press(" ")
    await expect(whole).toHaveAttribute("aria-expanded", "true")
    await whole.click()
    await expect(whole).toHaveAttribute("aria-expanded", "false")
    await whole.click()
    await page.keyboard.press("Tab")
    await expect(whole).not.toBeFocused()
    await expect(whole).toHaveAttribute("aria-expanded", "true")

    // a cell whose text is all shown gets no button
    await expect(cell(page, "b", "note").locator(":scope > [data-whole]")).toHaveCount(0)
  })

  test("the button's name takes the column's label as it is, also what a replacement pattern would read as its own", async ({
    page,
  }) => {
    // `$$` and `$&` mean something to String.prototype.replace with a
    // string in place of the match; a label is no pattern
    await opened(page, `/e2e/markers?note=${encodeURIComponent("Cost $$ and $& more")}`)
    const whole = cell(page, "a", "note").locator(":scope > [data-whole]")
    await expect(whole).toHaveAccessibleName("Show all of Cost $$ and $& more")
    await whole.click()
    await expect(whole).toHaveAccessibleName("Show less of Cost $$ and $& more")
  })

  test("Enter on the button of a line closes the nested table under it, and opens it again; focus stays on the button", async ({ page, pushed }) => {
    const button = line(page).locator("button")
    await button.focus()
    await expect(button).toHaveAttribute("aria-expanded", "true")
    await page.keyboard.press("Enter")
    await expect(holder(page)).toHaveCount(0)
    await expect(button).toHaveAttribute("aria-expanded", "false")
    await expect(button).toBeFocused()
    await page.keyboard.press("Enter")
    await expect(part(page, "p1")).toBeAttached()
    await expect(button).toHaveAttribute("aria-expanded", "true")
    expect((await pushed.all()).filter((sent) => sent.event === "toggle").map((sent) => sent.params)).toEqual([
      { row: "a", relationship: "parts" },
      { row: "a", relationship: "parts" },
    ])
  })

  test("a hidden column is not shown, and Tab passes over what it holds", async ({ page }) => {
    await page.locator('[id="kit-columns-button"]').click()
    await page.locator('[id="kit-column-note"]').uncheck()
    await expect(page.locator('[id="kit-head-note"]')).toBeHidden()
    await expect(cell(page, "a", "note")).toBeHidden()
    await expect(page.locator('[id="kit-filter-note"]')).toBeHidden()

    // the note's "Show all" is hidden with its cell: Tab goes from the name to the line
    await cell(page, "a", "name").focus()
    expect(await kit(page).walk(1)).toEqual(["kit-row-a-l-parts-c>button"])
  })
})

// A question before a save, and a kit that leaves the question dialog out:
// nothing is saved without a question answered (the hook does not take a
// missing dialog for a yes).
test.describe("a column that asks before a save", () => {
  async function renamed(page: Page, path: string): Promise<void> {
    await opened(page, path)
    const name = cell(page, "a", "name")
    await name.focus()
    await page.keyboard.press("Enter")
    await expect(name.locator("textarea")).toBeFocused()
    await page.keyboard.press("ControlOrMeta+A")
    await page.keyboard.type("Anvil")
    await page.keyboard.press("Enter")
  }

  test("asks in the question dialog, and saves once it is confirmed", async ({ page, pushed }) => {
    await renamed(page, "/e2e/markers?asks=1")
    const dialog = page.locator('[id="kit-dialog"]')
    await expect(dialog).toBeVisible()
    await expect(page.locator('[id="kit-dialog-question"]')).toHaveText("Rename this part?")
    await dialog.getByRole("button", { name: "Confirm" }).click()
    await expect(cell(page, "a", "name")).toHaveText("Anvil")
    expect(await pushed.count("save")).toBe(1)
  })

  test("saves nothing where the question dialog is missing, and the development check names it", async ({
    page,
    pushed,
    consoleErrors,
  }) => {
    const said: string[] = []
    page.on("console", (message) => {
      if (message.type() === "error") said.push(message.text())
    })
    consoleErrors.allow(/^ash_data_table: the grid kit-grid has no (its )?question dialog/)
    await page.goto("/e2e/markers?asks=1&missing=dialog")
    await page.evaluate(() => (window as any).liveSocket.enableDebug())
    await page.reload()
    await renamed(page, "/e2e/markers?asks=1&missing=dialog")
    // nothing was saved: the editor is still open, with what was typed
    await expect(cell(page, "a", "name").locator("textarea")).toBeFocused()
    await expect(cell(page, "a", "name").locator("textarea")).toHaveValue("Anvil")
    expect(await pushed.count("save")).toBe(0)
    expect(said).toContain(
      'ash_data_table: the grid kit-grid has no its question dialog (a <dialog> [role=dialog], or [role=region] with data-presentation="inline", with the id kit-dialog)',
    )
    expect(said.some((text) => text.startsWith("ash_data_table: the grid kit-grid has no question dialog"))).toBe(true)
  })
})

test.describe("the question of an action panel", () => {
  test("is asked in the table's question dialog, and the panel runs once it is confirmed", async ({
    page,
    pushed,
  }) => {
    await page.goto("/e2e/markers?panel=1")
    // connected: the panel's hook, which asks, is mounted
    await expect(page.locator(".phx-connected").first()).toBeAttached()
    await page.locator('[id="kit-panel"]').getByRole("button", { name: "Run" }).click()
    const dialog = page.locator('[id="kit-dialog"]')
    await expect(page.locator('[id="kit-dialog-question"]')).toHaveText("Stamp this part?")
    await dialog.getByRole("button", { name: "Confirm" }).click()
    await expect.poll(() => pushed.count("panel_submit")).toBe(1)
  })

  test("runs nothing where the panel finds no grid to ask in, and the development check says so", async ({
    page,
    pushed,
    consoleErrors,
  }) => {
    const said: string[] = []
    page.on("console", (message) => {
      if (message.type() === "error") said.push(message.text())
    })
    consoleErrors.allow(/^ash_data_table: the panel kit-panel finds no grid of its table/)
    await page.goto("/e2e/markers?panel=1&missing=grid")
    await page.evaluate(() => (window as any).liveSocket.enableDebug())
    await page.reload()
    const panel = page.locator('[id="kit-panel"]')
    await expect(panel).toBeVisible()
    await panel.getByRole("button", { name: "Run" }).click()
    await expect
      .poll(() => said.some((text) => text.startsWith("ash_data_table: the panel kit-panel finds no grid of its table")))
      .toBe(true)
    // the push of a submit would be out by now: the error is said in the same handler
    expect(await pushed.count("panel_submit")).toBe(0)
    await expect(page.locator('[id="kit-dialog"]')).toBeHidden()
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
    // connected, and its hook has run: its rows are there
    await tasks.ready()
    await tasks.expand(await tasks.rowKey(1))

    await page.evaluate(() => (window as any).liveSocket.disableDebug())
    await opened(page, "/e2e/markers?missing=colindex")
    // the hook has run: it has offered the cut-off note its whole text
    await expect(cell(page, "a", "note").locator(":scope > [data-whole]")).toBeAttached()
  })
})
