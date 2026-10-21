import type { Locator, Page } from "@playwright/test"
import { expectNoAxeViolations } from "./support/a11y"
import { MAPS, SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { Table } from "./support/table"

// Long text, in a browser. A cell is one line, or as many as its column says
// with `max_lines`: "Body" of the compact comments (/comments/compact) shows
// up to three. A cell that cuts some of its text off, in whichever column,
// shows all of it in place: the hook puts a button into it (`Table.whole`,
// "Show all", a Tab stop named after its column), and the button, or
// Shift+Enter on an editable cell, shows the whole text in the cell, the row
// as high as it needs, and cuts it off again. Escape on an editable cell
// cuts it off too. Nothing of the text is put anywhere but in the cell: the
// server renders nothing for it. The compact comments edit nothing: their
// cells are no Tab stops, the buttons are.
//
// One comment in ten of the seed is long, of three paragraphs: it starts
// with "Done on my side, please review." and ends with "merge it as it is."

const LONG = "Done on my side, please review."
const LONG_END = "If nobody objects by Friday I will merge it as it is."

const compact = (page: Page) => new Table(page, "comment_compact", "/comments/compact")
const comments = (page: Page) => new Table(page, "comment", "/comments")
/** Every button of a whole text in the page, of whichever table. */
const anyWhole = (page: Page) => page.locator("[data-whole]")

/** The keys of the rows of the page whose `column` starts with `text`, and of those that do not. */
async function keysBy(table: Table, column: string, text: string): Promise<{ with: string[]; without: string[] }> {
  const keys = await table.rowKeys()
  const texts = await table.columnCells(column).evaluateAll((cells) => cells.map((cell) => cell.textContent ?? ""))
  return {
    with: keys.filter((_key, at) => texts[at].startsWith(text)),
    without: keys.filter((_key, at) => !texts[at].startsWith(text)),
  }
}

/** What a cell with several lines shows: its paragraph, measured. */
async function paragraph(cell: Locator) {
  return cell.evaluate((td) => {
    const p = td.querySelector(":scope > [data-paragraph]")!
    const style = getComputedStyle(p)
    return {
      lines: Math.round(p.clientHeight / parseFloat(style.lineHeight)),
      cut: p.scrollHeight > p.clientHeight,
      clamp: style.webkitLineClamp,
      overflow: style.overflow,
      breaks: style.whiteSpace,
    }
  })
}

/** Whether a cell of one line cuts its text off. */
const cut = (cell: Locator) => cell.evaluate((td) => td.scrollWidth > td.clientWidth)

const text = (element: Locator) => element.evaluate((node) => node.textContent ?? "")

/** The text a cell holds, without what the button of its whole text says. */
const own = (cell: Locator) =>
  cell.evaluate((td) => {
    const copy = td.cloneNode(true) as Element
    for (const button of Array.from(copy.querySelectorAll(":scope > [data-whole]"))) button.remove()
    return copy.textContent ?? ""
  })

/** How high a row is. */
const height = async (table: Table, key: string) => (await table.rowLine(key).boundingBox())!.height

/**
 * Makes a column as narrow as it can be, from the keyboard: its width field
 * in "Columns", the least width typed in, the list closed again with Escape.
 */
async function narrow(table: Table, column: string): Promise<void> {
  await table.typeWidth(column, 48)
  await table.press("Escape")
  await expect(table.columnsList).toBeHidden()
  expect(await table.width(column)).toBe(48)
}

test.describe("a column with `max_lines 3` (/comments/compact)", () => {
  test("shows up to three lines of a text, with its line breaks, and cuts off the rest; a row is as high as its cell", async ({
    page,
  }) => {
    const table = compact(page)
    await table.open()
    const keys = await keysBy(table, "body", LONG)
    const long = table.cell(keys.with[0], "body")
    const short = table.cell(keys.without[0], "body")

    await expect(long).toHaveAttribute("data-lines", "3")
    expect(await paragraph(long)).toEqual({ lines: 3, cut: true, clamp: "3", overflow: "hidden", breaks: "pre-line" })
    // the whole text is in the cell, for a screen reader and for a search
    expect(await text(long)).toContain(LONG_END)
    // its first paragraph is a line of its own: the line break of the value is kept
    expect(await text(long)).toContain(`${LONG}\n\n`)

    expect(await paragraph(short)).toMatchObject({ lines: 1, cut: false })

    const line = await height(table, keys.without[0])
    expect(await height(table, keys.with[0])).toBeGreaterThan(line + 30)
    // every cell of the row is as high as the row, the one-line ones too
    const cells = await table
      .rowCells(keys.with[0])
      .evaluateAll((all) => all.map((cell) => Math.round(cell.getBoundingClientRect().height)))
    expect(new Set(cells).size).toBe(1)
    // the other columns are one line, as ever
    await expect(table.cell(keys.with[0], "author")).not.toHaveAttribute("data-lines")
    await expect(table.cell(keys.with[0], "author").locator("p")).toHaveCount(0)
  })

  test("a narrower column gives a short text more lines, up to three", async ({ page }) => {
    const table = compact(page)
    await table.open()
    const keys = await keysBy(table, "body", "Moved to the next sprint.")
    const cell = table.cell(keys.with[0], "body")
    expect(await paragraph(cell)).toMatchObject({ lines: 1, cut: false })

    await narrow(table, "body")
    expect(await paragraph(cell)).toMatchObject({ lines: 3, cut: true })

    // and what is cut off now can be shown as a whole, in the cell
    await expect(table.whole(cell)).toBeVisible()
    await table.whole(cell).click()
    await expect(table.whole(cell)).toHaveAttribute("aria-expanded", "true")
    expect(await paragraph(cell)).toMatchObject({ cut: false })
    expect(await paragraph(cell)).not.toMatchObject({ clamp: "3" })
    expect(await own(cell)).toBe("Moved to the next sprint.")
  })
})

// What the hook puts into a cell with several lines as its save goes out is
// the paragraph the server draws, with its marker, and so cut off as that is.
// The save waits on the server until the test lets it go (/e2e/held, whose
// essays show up to three lines of their body and are edited).
test.describe("a cell with several lines whose save is on its way (/e2e/held)", () => {
  test("shows what was typed cut off after the column's lines, as the server's paragraph is", async ({ page }) => {
    const table = new Table(page, "essay", "/e2e/held")
    await table.open()
    const cell = table.cell((await table.rowKeys())[0], "body")
    await expect(cell).toHaveAttribute("data-lines", "3")
    await cell.focus()
    await table.press("Enter")
    await expect(table.editor(cell)).toBeFocused()
    const typed = "A long line of an essay that goes on. ".repeat(20).trim()
    await table.retype(typed)
    await table.press("Enter")

    // the save is on its way, and waits on the server
    await expect(cell).toHaveAttribute("aria-busy", "true")
    expect(await text(cell)).toBe(typed)
    expect(await paragraph(cell)).toMatchObject({ lines: 3, cut: true, clamp: "3", overflow: "hidden" })
    // a cell whose save is on its way is given no button for its whole text
    await expect(cell).toBeFocused()
    await expect(table.whole(cell)).toHaveCount(0)

    const released = await page.request.post("/e2e/held/release")
    expect(await released.json()).toEqual({ released: true })
    await expect(cell).not.toHaveAttribute("aria-busy")
    expect(await paragraph(cell)).toMatchObject({ lines: 3, cut: true, clamp: "3" })
    expect(await own(cell)).toBe(typed)
  })
})


test.describe("the whole text of a cell that cuts some off", () => {
  // the button is in
  // every cell that cuts its text off, read-only too, and a Tab stop
  test("every cell that cuts its text off has the button, a Tab stop named after its column; Enter and Space show all and cut it off again", async ({
    page,
  }) => {
    const table = compact(page)
    await table.open()
    const keys = await keysBy(table, "body", LONG)
    // without the pointer or the focus: in each cell that cuts text off, in no other
    for (const key of keys.with) await expect(table.whole(table.cell(key, "body"))).toHaveCount(1)
    for (const key of keys.without) await expect(table.whole(table.cell(key, "body"))).toHaveCount(0)

    const cell = table.cell(keys.with[0], "body")
    const button = table.whole(cell)
    await expect(button).toHaveAccessibleName("Show all of Body")
    await expect(button).toHaveAttribute("aria-expanded", "false")
    await expect(button).not.toHaveAttribute("aria-hidden")
    await expect(button).not.toHaveAttribute("tabindex")
    // inside the cell's box
    const at = (await button.boundingBox())!
    const box = (await cell.boundingBox())!
    expect(at.x).toBeGreaterThanOrEqual(box.x)
    expect(at.x + at.width).toBeLessThanOrEqual(box.x + box.width + 1)
    expect(at.y).toBeGreaterThanOrEqual(box.y)
    expect(at.y + at.height).toBeLessThanOrEqual(box.y + box.height + 1)
    // a screen reader has the whole text in the cell, which is described by nothing
    await expect(cell).not.toHaveAttribute("aria-describedby")
    await expect(cell).not.toHaveAttribute("title")
    expect(await own(cell)).toContain(LONG_END)

    // a stop of the Tab order: Shift+Tab leaves it, Tab comes back to it
    await button.focus()
    await page.keyboard.press("Shift+Tab")
    await expect(button).not.toBeFocused()
    await page.keyboard.press("Tab")
    await expect(button).toBeFocused()

    await page.keyboard.press("Enter")
    await expect(button).toHaveAttribute("aria-expanded", "true")
    await expect(button).toHaveAttribute("data-whole", "Show less")
    await expect(button).toHaveAccessibleName("Show less of Body")
    await expect(button).toBeFocused()
    expect(await paragraph(cell)).toMatchObject({ cut: false })
    await expectNoAxeViolations(page)

    await page.keyboard.press("Space")
    await expect(button).toHaveAttribute("aria-expanded", "false")
    await expect(button).toHaveAccessibleName("Show all of Body")
    await expect(button).toBeFocused()
    expect(await paragraph(cell)).toMatchObject({ lines: 3, cut: true })
  })

  test("the button shows all of the text in the cell, the row as high as it needs, and cuts it off again", async ({
    page,
  }) => {
    const table = compact(page)
    await table.open()
    const keys = await keysBy(table, "body", LONG)
    const key = keys.with[0]
    const cell = table.cell(key, "body")
    const button = table.whole(cell)
    const before = await height(table, key)

    await button.click()
    await expect(button).toHaveAttribute("aria-expanded", "true")
    await expect(button).toHaveAttribute("data-whole", "Show less")
    await expect(button).toBeFocused()
    // nothing is cut off any more, and the line breaks of the value are kept
    expect(await paragraph(cell)).toMatchObject({ cut: false, breaks: "pre-line" })
    expect(await paragraph(cell)).not.toMatchObject({ clamp: "3" })
    expect(await paragraph(cell).then((p) => p.lines)).toBeGreaterThan(3)
    expect(await height(table, key)).toBeGreaterThan(before + 10)
    // all of it is in the cell's box
    const shown = await cell.evaluate((td) => {
      const p = td.querySelector(":scope > [data-paragraph]")!.getBoundingClientRect()
      const box = td.getBoundingClientRect()
      return p.bottom <= box.bottom + 1
    })
    expect(shown).toBe(true)

    // the button again: cut off as before
    await button.click()
    await expect(button).toHaveAttribute("aria-expanded", "false")
    await expect(button).toHaveAttribute("data-whole", "Show all")
    expect(await paragraph(cell)).toMatchObject({ lines: 3, cut: true, clamp: "3" })
    expect(await height(table, key)).toBe(before)

    // Enter on it, the same; focus stays on it
    await table.press("Enter")
    await expect(button).toHaveAttribute("aria-expanded", "true")
    expect(await paragraph(cell)).toMatchObject({ cut: false })
    await table.press("Enter")
    await expect(button).toHaveAttribute("aria-expanded", "false")
    expect(await paragraph(cell)).toMatchObject({ lines: 3, cut: true })
    await expect(button).toBeFocused()
    await expect(table.openEditors).toHaveCount(0)
  })

  test("is in no cell that shows all of its text, in any column", async ({ page }) => {
    const table = compact(page)
    await table.open()
    const texts = await keysBy(table, "body", LONG)
    await expect(table.whole(table.cell(texts.with[0], "body"))).toBeVisible()

    for (const key of texts.without) await expect(table.whole(table.cell(key, "body"))).toHaveCount(0)
    for (const key of await table.rowKeys()) await expect(table.whole(table.cell(key, "author"))).toHaveCount(0)
    await expect(anyWhole(page)).toHaveCount(texts.with.length)
  })

  test("a cell whose whole text shows keeps it when focus and pointer go; its button cuts it off again", async ({
    page,
  }) => {
    const table = compact(page)
    await table.open()
    const keys = await keysBy(table, "body", LONG)
    const cell = table.cell(keys.with[0], "body")
    const button = table.whole(cell)

    await button.click()
    await expect(button).toHaveAttribute("aria-expanded", "true")

    // the focus moves on, the pointer is elsewhere: it still shows all
    await page.getByRole("heading", { level: 1 }).hover()
    await table.press("Tab")
    await expect(button).not.toBeFocused()
    await expect(button).toHaveAttribute("aria-expanded", "true")
    expect(await paragraph(cell)).toMatchObject({ cut: false })

    // back to it, and it cuts the text off again
    await table.press("Shift+Tab")
    await expect(button).toBeFocused()
    await table.press(" ")
    await expect(button).toHaveAttribute("aria-expanded", "false")
    expect(await paragraph(cell)).toMatchObject({ lines: 3, cut: true })
    await expect(button).toBeFocused()
  })

  test("a long text in a narrow column: all of it shows in the cell, however many lines it takes", async ({ page }) => {
    const table = compact(page)
    await table.open()
    const keys = await keysBy(table, "body", LONG)
    const key = keys.with[0]
    const cell = table.cell(key, "body")

    // a column of 48 pixels: the text takes many more lines than three
    await narrow(table, "body")
    const before = await height(table, key)
    await table.whole(cell).click()
    await expect(table.whole(cell)).toHaveAttribute("aria-expanded", "true")
    expect(await paragraph(cell)).toMatchObject({ cut: false })
    expect(await height(table, key)).toBeGreaterThan(before + 40)
    // the column keeps its width: it is the row that grows
    expect(await table.width("body")).toBe(48)
  })

  test("a cell of one line has it too, once its column is too narrow for its text", async ({ page }) => {
    const table = compact(page)
    await table.open()
    const key = await table.rowKey(1)
    const cell = table.cell(key, "author")
    const name = await text(cell)

    expect(await cut(cell)).toBe(false)
    await expect(table.whole(cell)).toHaveCount(0)

    await narrow(table, "author")
    expect(await cut(cell)).toBe(true)
    const before = await height(table, key)
    await expect(table.whole(cell)).toBeVisible()
    await table.whole(cell).click()
    await expect(table.whole(cell)).toHaveAttribute("aria-expanded", "true")
    // it wraps, and nothing is cut off
    expect(await cut(cell)).toBe(false)
    expect(await own(cell)).toBe(name)
    expect(await height(table, key)).toBeGreaterThan(before)
  })
})

test.describe("the whole text and editing (/comments)", () => {
  test("a cell of one line that is cut off has the button; not while the cell is edited, where the editor holds the text", async ({
    page,
  }) => {
    const table = comments(page)
    await table.open()
    const keys = await keysBy(table, "body", LONG)
    const cell = table.cell(keys.with[0], "body")
    const button = table.whole(cell)

    // the default table of the comments: one line per row
    await expect(cell).not.toHaveAttribute("data-lines")
    expect(await cut(cell)).toBe(true)

    await cell.focus()
    await expect(button).toBeVisible()
    await table.press("Shift+Enter")
    await expect(button).toHaveAttribute("aria-expanded", "true")
    expect(await cut(cell)).toBe(false)

    // Escape on the cell cuts it off again, and does nothing else
    await table.press("Escape")
    await expect(button).toHaveAttribute("aria-expanded", "false")
    expect(await cut(cell)).toBe(true)
    await expect(cell).toBeFocused()
    await expect(table.openEditors).toHaveCount(0)
    await table.press("Shift+Enter")
    await expect(button).toHaveAttribute("aria-expanded", "true")

    // the editor takes the place of all of it, the button too
    await table.press("Enter")
    await expect(table.editor(cell)).toBeFocused()
    await expect(button).toHaveCount(0)
    expect(await table.editor(cell).inputValue()).toContain(LONG_END)
    // nor does the pointer bring it while the editor is open
    await cell.hover()
    await expect(table.editor(cell)).toBeFocused()
    await expect(button).toHaveCount(0)

    // the edit given up: the cell has the focus again, cut off, with its button again
    await page.getByRole("heading", { level: 1 }).hover()
    await table.press("Escape")
    await expect(cell).toBeFocused()
    await expect(table.openEditors).toHaveCount(0)
    await expect(button).toBeVisible()
    await expect(button).toHaveAttribute("aria-expanded", "false")
    expect(await cut(cell)).toBe(true)
  })
})

test.describe("the whole text of a nested table, and of a row that changes", () => {
  const TYPED =
    "Typed under its task, and long enough to be cut off in a table that shows three lines of it: " +
    "one sentence after the other, none of which says much, until the cell has more than it shows. ".repeat(4) +
    "The end of it."

  test("a nested table has its own, in every cell of it that cuts its text off", async ({
    page,
    tasks,
  }) => {
    // a long comment under the first task, written in the nested table of /tasks
    await tasks.open()
    const under = await tasks.openLine(SEED.task.first, "comments")
    const comment = await under.rowKey(1)
    const typed = under.cell(comment, "body")
    await typed.focus()
    await under.press("Enter")
    await expect(under.editor(typed)).toBeFocused()
    await page.keyboard.press("ControlOrMeta+A")
    await page.keyboard.insertText(TYPED)
    await under.saves(typed, () => under.press("Enter"))
    await expect.poll(() => own(typed)).toBe(TYPED)

    // the board nests the compact comments, which show three lines
    const table = new Table(page, "task_board", "/tasks/board")
    await table.open()
    const nested = await table.openLine(SEED.task.first, "comments")
    const cell = nested.cell(comment, "body")
    expect(await paragraph(cell)).toMatchObject({ lines: 3, cut: true })

    await expect(nested.whole(cell)).toBeVisible()
    await expect(nested.whole(cell)).toHaveAccessibleName("Show all of Body")

    await nested.whole(cell).focus()
    await nested.press("Enter")
    await expect(nested.whole(cell)).toHaveAttribute("aria-expanded", "true")
    expect(await paragraph(cell)).toMatchObject({ cut: false })
    expect(await own(cell)).toBe(TYPED)

    await nested.press("Enter")
    await expect(nested.whole(cell)).toHaveAttribute("aria-expanded", "false")
    await expect(nested.whole(cell)).toBeFocused()
    expect(await paragraph(cell)).toMatchObject({ lines: 3, cut: true })
  })

  test("a live update of the row brings the new text, shown whole again, and takes the button away when nothing is cut off any more", async ({
    page,
    context,
  }) => {
    const table = compact(page)
    await table.open()
    const keys = await keysBy(table, "body", LONG)
    const key = keys.with[0]
    const cell = table.cell(key, "body")
    const button = table.whole(cell)

    // its whole text shows
    await button.click()
    await expect(button).toHaveAttribute("aria-expanded", "true")

    // the same comment is changed in another window, at /comments
    const other = comments(await context.newPage())
    await other.open()
    const retype = async (typed: string) => {
      const edited = other.cell(key, "body")
      await edited.focus()
      await other.press("Enter")
      await expect(other.editor(edited)).toBeFocused()
      await other.page.keyboard.press("ControlOrMeta+A")
      await other.page.keyboard.insertText(typed)
      await other.saves(edited, () => other.press("Enter"))
    }

    await retype(TYPED)
    await expect.poll(() => own(cell)).toBe(TYPED)
    // the patch brought the cell as the server renders it; it shows all of it again
    await expect(button).toHaveAttribute("aria-expanded", "true")
    expect(await paragraph(cell)).toMatchObject({ cut: false })

    await retype("Short now.")
    await expect.poll(() => own(cell)).toBe("Short now.")
    await expect(button).toHaveCount(0)
  })
})

// "Budget" at /projects is sensitive: masked until somebody asks for it.
// Made as narrow as a column can be, its cell cuts off what it holds, masked
// and shown, and still is given no button for its whole text, as every
// other cell that cuts its text off is: neither the mask nor the value is
// ever shown as a whole.
test.describe("a sensitive cell", () => {
  test.use({ actor: "member" })

  const PORTAL = { id: MAPS.project.customerPortal.id, budget: "23500" }

  test("has no whole text, masked or shown, however much of it is cut off", async ({ page }) => {
    const table = new Table(page, "project", "/projects")
    await table.open()
    const cell = table.cell(PORTAL.id, "budget")

    /** The buttons of a whole text in the column of the budgets: none, ever. */
    const budgets = table.columnCells("budget").locator(":scope > [data-whole]")

    await narrow(table, "budget")
    await expect(cell.locator("[data-mask]")).toBeVisible()
    expect(await cut(cell), "the masked cell is cut off").toBe(true)
    // the hook has measured the cells at their new width: a cell beside it
    // that is cut off now has its button
    await narrow(table, "name")
    const name = table.cell(PORTAL.id, "name")
    await expect(table.whole(name)).toBeVisible()
    await expect(budgets).toHaveCount(0)
    await cell.hover()
    await expect(table.whole(cell)).toHaveCount(0)

    // shown: the value is in the cell, cut off, and nowhere else
    await cell.focus()
    await expect(cell).toBeFocused()
    await table.press("Shift+Enter")
    await expect(cell.locator("[data-secret]")).toHaveText(PORTAL.budget)
    expect(await cut(cell), "the cell that shows its value is cut off").toBe(true)
    await expect(table.whole(cell)).toHaveCount(0)
    await cell.hover()
    await expect(cell.locator("[data-secret]")).toHaveText(PORTAL.budget)
    await expect(budgets).toHaveCount(0)

    // the name beside it shows its whole text, and nothing of the budget
    await table.whole(name).click()
    await expect(table.whole(name)).toHaveAttribute("aria-expanded", "true")
    expect(await own(name)).not.toContain(PORTAL.budget)
    await expect(budgets).toHaveCount(0)
  })
})

// A member may not see the estimate of a task that is not theirs: the cell
// says so to a screen reader and shows nothing. There is nothing to show as
// a whole either.
test.describe("a cell of a field the person may not see", () => {
  test.use({ actor: "member" })

  test("has no whole text", async ({ tasks }) => {
    await tasks.open()
    const cell = tasks.cell(SEED.task.first, "estimate_hours")
    await expect(cell.locator(".sr-only")).toHaveCount(1)

    await narrow(tasks, "estimate_hours")
    // the hook has measured the cells at their new width: a cut-off title has its button
    await narrow(tasks, "title")
    await expect(tasks.whole(tasks.cell(SEED.task.first, "title"))).toBeVisible()
    // a read-only cell is no Tab stop; the hidden one has no button, with the pointer on it or not
    await expect(cell).not.toHaveAttribute("tabindex")
    await expect(tasks.whole(cell)).toHaveCount(0)
    await cell.hover()
    await expect(tasks.whole(cell)).toHaveCount(0)
  })
})

for (const theme of ["light", "dark"] as const) {
  test.describe(`axe, in the ${theme} theme`, () => {
    test.beforeEach(async ({ page }) => {
      await page.addInitScript((theme) => localStorage.setItem("phx:theme", theme), theme)
    })

    test("finds nothing wrong with the compact comments, the button of a whole text there and the whole text showing", async ({
      page,
    }) => {
      const table = compact(page)
      await table.open()
      await expect(page.locator("html")).toHaveAttribute("data-theme", theme)
      const keys = await keysBy(table, "body", LONG)
      const cell = table.cell(keys.with[0], "body")
      await expectNoAxeViolations(page)

      await table.whole(cell).focus()
      await expectNoAxeViolations(page)

      await table.press("Enter")
      await expect(table.whole(cell)).toHaveAttribute("aria-expanded", "true")
      await expectNoAxeViolations(page)

      // and in a column so narrow that it takes many lines
      await narrow(table, "body")
      await table.whole(cell).focus()
      await expect(table.whole(cell)).toHaveAttribute("aria-expanded", "true")
      await expectNoAxeViolations(page)
    })
  })
}

test.describe("in forced colours", () => {
  test.use({ forcedColors: "active" })

  test("the button of the whole text is told from the text by its underline, in the system's colours", async ({
    page,
  }) => {
    const table = compact(page)
    await table.open()
    const keys = await keysBy(table, "body", LONG)
    const cell = table.cell(keys.with[0], "body")
    await expect(table.whole(cell)).toBeVisible()
    const look = await table.whole(cell).evaluate((node) => {
      const style = getComputedStyle(node)
      return { underline: style.textDecorationLine, adjust: style.forcedColorAdjust }
    })
    expect(look).toEqual({ underline: "underline", adjust: "auto" })
  })
})
