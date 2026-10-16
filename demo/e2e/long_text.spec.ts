import type { Locator, Page } from "@playwright/test"
import { expectNoAxeViolations } from "./support/a11y"
import { MAPS, SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { Table } from "./support/table"

// Long text, in a browser. A cell is one line, or as many as its column says
// with `max_lines`: "Body" of the compact comments (/comments/compact) shows
// up to three. What is cut off, in whichever cell, is shown as a whole under
// the cell while the cell has the focus or the pointer has rested on it: a
// popover of the table (`ID-whole`), which the hook fills from the cell's
// own text.
//
// One comment in ten of the seed is long, of three paragraphs: it starts
// with "Done on my side, please review." and ends with "merge it as it is."
//
// The popover comes after a moment (400 ms of focus, 500 ms of the
// pointer). A test that says it does not come runs the page's clock on past
// that moment, and does not wait for it.

const LONG = "Done on my side, please review."
const LONG_END = "If nobody objects by Friday I will merge it as it is."
/** Longer than any of the popover's moments. */
const A_WHILE = 2_000

const compact = (page: Page) => new Table(page, "comment_compact", "/comments/compact")
const comments = (page: Page) => new Table(page, "comment", "/comments")
const whole = (table: Table) => table.page.locator(`[id="${table.id}-whole"]`)

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

/** The page's clock runs on, past every moment of the popover. */
async function later(page: Page): Promise<void> {
  await page.clock.fastForward(A_WHILE)
}

/** Makes a column as narrow as it can be, from the keyboard. */
async function narrow(table: Table, column: string): Promise<void> {
  await table.header(column).focus()
  await table.press("F2")
  await expect(table.resizer(column)).toBeFocused()
  await table.press("Home", "Escape")
  await expect(table.header(column)).toBeFocused()
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

    const height = async (key: string) => (await table.rowLine(key).boundingBox())!.height
    const line = await height(keys.without[0])
    expect(await height(keys.with[0])).toBeGreaterThan(line + 30)
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

    // and what is cut off now is shown as a whole
    await cell.focus()
    await expect(whole(table)).toBeVisible()
    expect(await text(whole(table))).toBe("Moved to the next sprint.")
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

    const released = await page.request.post("/e2e/held/release")
    expect(await released.json()).toEqual({ released: true })
    await expect(cell).not.toHaveAttribute("aria-busy")
    expect(await paragraph(cell)).toMatchObject({ lines: 3, cut: true, clamp: "3" })
    expect(await text(cell)).toBe(typed)
  })
})

test.describe("the whole text of a cell that cuts some off", () => {
  test("is shown under the cell while it has the focus, which the cell keeps, and for the eye alone", async ({
    page,
  }) => {
    const table = compact(page)
    await table.open()
    const keys = await keysBy(table, "body", LONG)
    const cell = table.cell(keys.with[0], "body")
    const popover = whole(table)

    // the server renders it empty, and closed
    await expect(popover).toBeHidden()
    expect(await text(popover)).toBe("")

    await cell.focus()
    await expect(popover).toBeVisible()
    expect(await text(popover)).toBe(await text(cell))
    expect(await text(popover)).toContain(LONG_END)
    await expect(cell).toBeFocused()

    // under the cell, at its start, and with the line breaks of the text
    const at = (await popover.boundingBox())!
    const box = (await cell.boundingBox())!
    expect(at.y).toBeGreaterThanOrEqual(box.y + box.height)
    expect(at.y).toBeLessThanOrEqual(box.y + box.height + 4)
    expect(Math.round(at.x)).toBe(Math.round(box.x))
    expect(await popover.evaluate((node) => getComputedStyle(node).whiteSpace)).toBe("pre-line")

    // a screen reader has the text in the cell, and is told nothing of this
    await expect(popover).toHaveAttribute("aria-hidden", "true")
    await expect(cell).not.toHaveAttribute("aria-describedby")
    await expect(cell).not.toHaveAttribute("title")
    expect(await popover.evaluate((node) => node.querySelectorAll("a,button,input,[tabindex]").length)).toBe(0)

    // gone at once when the focus moves on
    await table.press("ArrowRight")
    await expect(popover).toBeHidden()
    expect(await text(popover)).toBe("")
  })

  test("is not shown for a cell that shows all of its text, and not while the arrow keys go through cells", async ({
    page,
  }) => {
    await page.clock.install()
    const table = compact(page)
    await table.open()
    const keys = await table.rowKeys()
    const texts = await keysBy(table, "body", LONG)
    const popover = whole(table)

    await table.cell(texts.without[0], "body").focus()
    await later(page)
    await expect(popover).toBeHidden()
    await table.cell(texts.with[0], "author").focus()
    await later(page)
    await expect(popover).toBeHidden()

    // down the column, over the long ones, without stopping: nothing shows
    await table.cell(keys[0], "body").focus()
    for (const _key of keys.slice(1)) {
      await table.press("ArrowDown")
      await expect(popover).toBeHidden()
    }
    // the one that the focus stops on shows, if it is cut off
    await table.cell(texts.with[0], "body").focus()
    await expect(popover).toBeVisible()
  })

  test("is shown when the pointer rests on the cell, and stays while the pointer is on the text itself", async ({
    page,
  }) => {
    await page.clock.install()
    const table = compact(page)
    await table.open()
    const keys = await keysBy(table, "body", LONG)
    const cell = table.cell(keys.with[0], "body")
    const popover = whole(table)

    await cell.hover()
    await expect(popover).toBeVisible()
    expect(await text(popover)).toBe(await text(cell))
    // the pointer did not bring the focus with it
    await expect(cell).not.toBeFocused()

    // onto the text: it stays, for as long as the pointer is there
    await popover.hover()
    await later(page)
    await expect(popover).toBeVisible()

    // and away from both: it goes
    await page.getByRole("heading", { level: 1 }).hover()
    await expect(popover).toBeHidden()

    // a cell that shows all of its text has none
    await table.cell(keys.without[0], "body").hover()
    await later(page)
    await expect(popover).toBeHidden()
  })

  test("Escape takes it away and does nothing else; it comes back when the cell is come back to", async ({ page }) => {
    await page.clock.install()
    const table = compact(page)
    await table.open()
    const keys = await keysBy(table, "body", LONG)
    const cell = table.cell(keys.with[0], "body")
    const popover = whole(table)

    await cell.focus()
    await expect(popover).toBeVisible()
    await table.press("Escape")
    await expect(popover).toBeHidden()
    await expect(cell).toBeFocused()
    await later(page)
    await expect(popover).toBeHidden()

    await table.press("ArrowRight", "ArrowLeft")
    await expect(cell).toBeFocused()
    await expect(popover).toBeVisible()

    // with the pointer on the cell, and the focus somewhere else
    await table.press("ArrowRight")
    await expect(popover).toBeHidden()
    await cell.hover()
    await expect(popover).toBeVisible()
    await table.press("Escape")
    await expect(popover).toBeHidden()
    await expect(table.cell(keys.with[0], "author")).toBeFocused()
  })

  test("goes when the page scrolls, and scrolls by itself when the text is long", async ({ page }) => {
    await page.setViewportSize({ width: 1600, height: 500 })
    const table = compact(page)
    await table.open()
    const keys = await keysBy(table, "body", LONG)
    const cell = table.cell(keys.with[0], "body")
    const popover = whole(table)

    // a column of 48 pixels: the text takes more lines than the popover is high
    await narrow(table, "body")
    await cell.focus()
    await expect(popover).toBeVisible()
    const sizes = await popover.evaluate((node) => ({
      seen: node.clientHeight,
      all: node.scrollHeight,
      width: node.getBoundingClientRect().width,
    }))
    expect(sizes.all).toBeGreaterThan(sizes.seen)
    expect(sizes.seen).toBeLessThanOrEqual(240)
    expect(sizes.width).toBeLessThanOrEqual(448)

    // scrolling the text leaves it there
    await popover.evaluate((node) => {
      node.scrollTop = 40
      return new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)))
    })
    await expect(popover).toBeVisible()
    expect(await popover.evaluate((node) => node.scrollTop)).toBe(40)

    // scrolling the page takes it away
    await page.mouse.wheel(0, 60)
    await expect(popover).toBeHidden()
  })

  test("is above the cell where there is no room under it", async ({ page }) => {
    const table = compact(page)
    await table.open()
    const keys = await keysBy(table, "body", LONG)
    const cell = table.cell(keys.with[0], "body")
    const popover = whole(table)

    // a window that ends right under the cell
    const box = (await cell.boundingBox())!
    await page.setViewportSize({ width: 1600, height: Math.ceil(box.y + box.height + 8) })

    await cell.focus()
    await expect(popover).toBeVisible()
    const at = (await popover.boundingBox())!
    const now = (await cell.boundingBox())!
    expect(at.y + at.height).toBeLessThanOrEqual(now.y)
    expect(at.y + at.height).toBeGreaterThanOrEqual(now.y - 4)
    expect(at.y).toBeGreaterThanOrEqual(0)
  })

  test("a cell of one line has it too, once its column is too narrow for its text", async ({ page }) => {
    await page.clock.install()
    const table = compact(page)
    await table.open()
    const key = await table.rowKey(1)
    const cell = table.cell(key, "author")
    const popover = whole(table)
    const name = await text(cell)

    expect(await cut(cell)).toBe(false)
    await cell.focus()
    await later(page)
    await expect(popover).toBeHidden()

    await narrow(table, "author")
    expect(await cut(cell)).toBe(true)
    await cell.focus()
    await expect(popover).toBeVisible()
    expect(await text(popover)).toBe(name)
  })
})

test.describe("the whole text and editing (/comments)", () => {
  test("a cell of one line that is cut off shows it; not while the cell is edited, where the editor holds the text", async ({
    page,
  }) => {
    await page.clock.install()
    const table = comments(page)
    await table.open()
    const keys = await keysBy(table, "body", LONG)
    const cell = table.cell(keys.with[0], "body")
    const popover = whole(table)

    // the default table of the comments: one line per row
    await expect(cell).not.toHaveAttribute("data-lines")
    expect(await cut(cell)).toBe(true)

    await cell.focus()
    await expect(popover).toBeVisible()
    expect(await text(popover)).toContain(LONG_END)

    await table.press("Enter")
    await expect(table.editor(cell)).toBeFocused()
    await expect(popover).toBeHidden()
    await later(page)
    await expect(popover).toBeHidden()
    // nor does the pointer bring it while the editor is open
    await cell.hover()
    await later(page)
    await expect(popover).toBeHidden()

    // the edit given up: the cell has the focus again, and its text is shown again
    await page.getByRole("heading", { level: 1 }).hover()
    await table.press("Escape")
    await expect(cell).toBeFocused()
    await expect(table.openEditors).toHaveCount(0)
    await expect(popover).toBeVisible()
  })
})

test.describe("the whole text of a nested table, and of a row that changes", () => {
  const TYPED =
    "Typed under its task, and long enough to be cut off in a table that shows three lines of it: " +
    "one sentence after the other, none of which says much, until the cell has more than it shows. ".repeat(4) +
    "The end of it."

  test("a nested table has its own; Escape takes it away first, and leaves the nested table next", async ({
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
    await expect(typed).toHaveText(TYPED)

    // the board nests the compact comments, which show three lines
    const table = new Table(page, "task_board", "/tasks/board")
    await table.open()
    const nested = await table.openLine(SEED.task.first, "comments")
    const cell = nested.cell(comment, "body")
    expect(await paragraph(cell)).toMatchObject({ lines: 3, cut: true })

    await cell.focus()
    await expect(whole(nested)).toBeVisible()
    expect(await text(whole(nested))).toBe(TYPED)
    // the table around it shows nothing of its own
    await expect(whole(table)).toBeHidden()

    await nested.press("Escape")
    await expect(whole(nested)).toBeHidden()
    await expect(cell).toBeFocused()
    await nested.press("Escape")
    await expect(table.nestedCell(SEED.task.first, "comments")).toBeFocused()
  })

  test("a live update of the row brings the new text, and takes the popover away when nothing is cut off any more", async ({
    page,
    context,
  }) => {
    const table = compact(page)
    await table.open()
    const keys = await keysBy(table, "body", LONG)
    const key = keys.with[0]
    const cell = table.cell(key, "body")
    const popover = whole(table)

    // the pointer rests on the cell
    await cell.hover()
    await expect(popover).toBeVisible()
    expect(await text(popover)).toContain(LONG_END)

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
    await expect(cell).toHaveText(TYPED)
    await expect.poll(() => text(popover)).toBe(TYPED)
    await expect(popover).toBeVisible()

    await retype("Short now.")
    await expect(cell).toHaveText("Short now.")
    await expect(popover).toBeHidden()
    expect(await text(popover)).toBe("")
  })
})

// "Budget" at /projects is sensitive: masked until somebody asks for it.
// Made as narrow as a column can be, its cell cuts off what it holds, masked
// and shown, and still has no popover: neither the mask nor the value is
// ever put into one.
test.describe("a sensitive cell", () => {
  test.use({ actor: "member" })

  const PORTAL = { id: MAPS.project.customerPortal.id, budget: "23500" }

  test("has no popover, masked or shown, however much of it is cut off", async ({ page }) => {
    await page.clock.install()
    const table = new Table(page, "project", "/projects")
    await table.open()
    const cell = table.cell(PORTAL.id, "budget")
    const popover = whole(table)

    await narrow(table, "budget")
    await expect(cell.locator("[data-mask]")).toBeVisible()
    expect(await cut(cell), "the masked cell is cut off").toBe(true)

    await cell.focus()
    await later(page)
    await expect(popover).toBeHidden()
    expect(await text(popover)).toBe("")
    await cell.hover()
    await later(page)
    await expect(popover).toBeHidden()
    expect(await text(popover)).toBe("")

    // shown: the value is in the cell, cut off, and nowhere else
    await page.getByRole("heading", { level: 1 }).hover()
    await table.press("Shift+Enter")
    await expect(cell.locator("[data-secret]")).toHaveText(PORTAL.budget)
    expect(await cut(cell), "the cell that shows its value is cut off").toBe(true)
    await later(page)
    await expect(popover).toBeHidden()
    expect(await text(popover)).toBe("")
    await cell.hover()
    await later(page)
    await expect(cell.locator("[data-secret]")).toHaveText(PORTAL.budget)
    await expect(popover).toBeHidden()
    expect(await text(popover)).toBe("")

    // a cell beside it that is cut off has its popover, as everywhere
    await narrow(table, "name")
    const name = table.cell(PORTAL.id, "name")
    await name.focus()
    await expect(popover).toBeVisible()
    expect(await text(popover)).toBe(await text(name))
    expect(await text(popover)).not.toContain(PORTAL.budget)
  })
})

// A member may not see the estimate of a task that is not theirs: the cell
// says so to a screen reader and shows nothing. There is nothing to show as
// a whole either.
test.describe("a cell of a field the person may not see", () => {
  test.use({ actor: "member" })

  test("has no popover", async ({ page, tasks }) => {
    await page.clock.install()
    await tasks.open()
    const cell = tasks.cell(SEED.task.first, "estimate_hours")
    await expect(cell.locator(".sr-only")).toHaveCount(1)

    await narrow(tasks, "estimate_hours")
    await cell.focus()
    await later(page)
    await expect(whole(tasks)).toBeHidden()
    expect(await text(whole(tasks))).toBe("")
  })
})

for (const theme of ["light", "dark"] as const) {
  test.describe(`axe, in the ${theme} theme`, () => {
    test.beforeEach(async ({ page }) => {
      await page.addInitScript((theme) => localStorage.setItem("phx:theme", theme), theme)
    })

    test("finds nothing wrong with the compact comments, the whole text of a cell showing", async ({ page }) => {
      const table = compact(page)
      await table.open()
      await expect(page.locator("html")).toHaveAttribute("data-theme", theme)
      const keys = await keysBy(table, "body", LONG)
      await expectNoAxeViolations(page)

      await table.cell(keys.with[0], "body").focus()
      await expect(whole(table)).toBeVisible()
      await expectNoAxeViolations(page)

      // and with a text so long that it scrolls
      await narrow(table, "body")
      await table.cell(keys.with[0], "body").focus()
      await expect(whole(table)).toBeVisible()
      await expectNoAxeViolations(page)
    })
  })
}

test.describe("in forced colours", () => {
  test.use({ forcedColors: "active" })

  test("the whole text has an edge", async ({ page }) => {
    const table = compact(page)
    await table.open()
    const keys = await keysBy(table, "body", LONG)
    await table.cell(keys.with[0], "body").focus()
    await expect(whole(table)).toBeVisible()
    const edge = await whole(table).evaluate((node) => {
      const style = getComputedStyle(node)
      return { width: style.borderTopWidth, line: style.borderTopStyle }
    })
    expect(edge).toEqual({ width: "1px", line: "solid" })
  })
})
