import type { Locator, Page } from "@playwright/test"
import { expectNoAxeViolations } from "./support/a11y"
import { SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { ownedSheets, Table } from "./support/table"

// Scrolling sideways: every table in an area of its own, a nested table as
// wide as what is seen of the table around it, the scrollbar at the bottom
// edge of the window, and the label column that stays in view where a table
// says `sticky_label? true`.
//
// In a window of 1000 by 600 pixels, which /tasks (thirty columns) and the
// tables nested in it are far wider than. /tasks says `sticky_label? true`;
// /labels and the comments do not.

test.use({ viewport: { width: 1000, height: 600 } })

/** The first row of /tasks. */
const FIRST = SEED.task.first

/** Acme's "Mobile app": 57 tasks, a nested table of 25 rows, higher than the window. */
const MOBILE_APP = SEED.project.mobileApp

type Box = { left: number; right: number; top: number; bottom: number }

/** Where an element is in the window, in whole pixels. */
async function box(locator: Locator): Promise<Box> {
  return locator.evaluate((element) => {
    const { left, right, top, bottom } = element.getBoundingClientRect()
    return {
      left: Math.round(left),
      right: Math.round(right),
      top: Math.round(top),
      bottom: Math.round(bottom),
    }
  })
}

/** Whether an element is what is seen at its own middle: nothing lies over it there. */
async function onTop(locator: Locator): Promise<boolean> {
  return locator.evaluate((element) => {
    const { left, right, top, bottom } = element.getBoundingClientRect()
    const seen = document.elementFromPoint((left + right) / 2, (top + bottom) / 2)
    return !!seen && (seen === element || element.contains(seen))
  })
}

/** How far the page is scrolled down. */
function scrolledDown(page: Page): Promise<number> {
  return page.evaluate(() => Math.round(window.scrollY))
}

/** The pointer over the middle of what is seen of a table's area, `down` pixels under its top. */
async function pointAt(page: Page, table: Table, down: number): Promise<void> {
  const area = await box(table.hookRoot)
  await page.mouse.move(area.left + 500, area.top + down)
}

/** The cell that has the focus. */
// How far a nested table stands in from the table around it: the line
// down the left of the nested area and the one inset after it (the
// default kit's look), the same at every depth.
async function inset(page: Page): Promise<number> {
  return page
    .locator("[data-ash-data-table-view]")
    .first()
    .evaluate((view) => {
      const style = getComputedStyle(view)
      return parseFloat(style.borderInlineStartWidth) + parseFloat(style.paddingInlineStart)
    })
}

/** What has focus: an editable cell, or a control in a cell. */
function focused(page: Page): Locator {
  return page.locator(":focus")
}

test.describe("every table scrolls sideways in an area of its own", () => {
  test("a nested table is as wide as what is seen of the table around it, less its inset, and scrolls alone", async ({
    page,
    tasks,
  }) => {
    await tasks.open()
    const comments = await tasks.openLine(FIRST, "comments")

    const outer = await tasks.area()
    const inner = await comments.area()
    const step = await inset(page)
    expect(step).toBeGreaterThan(0)
    expect(outer.all).toBeGreaterThan(outer.seen)
    // as wide as what is seen of /tasks, less its inset, and in the same
    // place after it; wider inside
    expect(inner.seen).toBe(outer.seen - step)
    expect(inner.left).toBe(outer.left + step)
    expect(inner.all).toBeGreaterThan(inner.seen)

    // the line that opened it has its mark still: a triangle, turned (once
    // its turn, a transition, is done)
    await expect
      .poll(() =>
        tasks.line(FIRST, "comments").evaluate((button) => {
          const mark = getComputedStyle(button, "::before")
          return [mark.borderInlineStartWidth !== "0px", mark.rotate]
        }),
      )
      .toEqual([true, "90deg"])

    // the nested table scrolls, and the table around it stays
    await comments.scrollTo(200)
    expect(await tasks.scrollLeft()).toBe(0)

    // the table around it scrolls under the nested one, which stays where
    // it is and as it is scrolled; so does what its line holds
    const line = await box(tasks.line(FIRST, "comments"))
    const status = await box(tasks.cell(FIRST, "status"))
    await tasks.scrollTo(300)
    expect(await comments.area()).toEqual(inner)
    expect(await comments.scrollLeft()).toBe(200)
    expect(await box(tasks.line(FIRST, "comments"))).toEqual(line)
    // the columns of /tasks did move
    expect((await box(tasks.cell(FIRST, "status"))).left).toBe(status.left - 300)
  })

  test("at depth 2 as at depth 1, and when the window is another size", async ({ page, tasks }) => {
    await tasks.open()
    const project = await tasks.openLine(FIRST, "project")
    const inner = await project.openLine(await project.rowKey(1), "tasks")

    const outer = await tasks.area()
    const step = await inset(page)
    // one inset per level
    expect((await project.area()).seen).toBe(outer.seen - step)
    expect(await inner.area()).toMatchObject({ seen: outer.seen - 2 * step, left: outer.left + 2 * step })
    expect((await inner.area()).all).toBeGreaterThan(outer.seen - 2 * step)

    // each of the three scrolls alone
    await inner.scrollTo(400)
    await project.scrollTo(100)
    expect(await tasks.scrollLeft()).toBe(0)
    expect(await inner.scrollLeft()).toBe(400)
    await tasks.scrollTo(250)
    expect(await project.scrollLeft()).toBe(100)
    expect(await inner.scrollLeft()).toBe(400)
    expect(await inner.area()).toMatchObject({ seen: outer.seen - 2 * step, left: outer.left + 2 * step })

    // a narrower window: all three are as wide as what is seen now, less
    // their insets
    await page.setViewportSize({ width: 800, height: 600 })
    await expect.poll(async () => (await tasks.area()).seen).toBeLessThan(outer.seen)
    const narrow = (await tasks.area()).seen
    await expect.poll(async () => (await project.area()).seen).toBe(narrow - step)
    await expect.poll(async () => (await inner.area()).seen).toBe(narrow - 2 * step)

    // and a wider one
    await page.setViewportSize({ width: 1200, height: 600 })
    await expect.poll(async () => (await tasks.area()).seen).toBeGreaterThan(outer.seen)
    const wide = (await tasks.area()).seen
    await expect.poll(async () => (await project.area()).seen).toBe(wide - step)
    await expect.poll(async () => (await inner.area()).seen).toBe(wide - 2 * step)
  })

  test("Shift and the wheel scroll the table under the pointer, and no other; the wheel alone scrolls the page", async ({
    page,
    tasks,
  }) => {
    await tasks.open()
    const comments = await tasks.openLine(FIRST, "comments")
    const most = await comments.hookRoot.evaluate((grid) => grid.scrollWidth - grid.clientWidth)

    // over the nested table: it scrolls, the table around it does not
    await pointAt(page, comments, 20)
    await page.keyboard.down("Shift")
    await page.mouse.wheel(0, 150)
    await expect.poll(() => comments.scrollLeft()).toBe(150)
    expect(await tasks.scrollLeft()).toBe(0)

    // to its end and on: the table around it does not take over
    await page.mouse.wheel(0, 5000)
    await expect.poll(() => comments.scrollLeft()).toBe(Math.round(most))
    await page.mouse.wheel(0, 500)
    await page.keyboard.up("Shift")

    // The wheel alone scrolls the page down, and nothing sideways. It comes
    // after the wheel above, so what that one did is done by now.
    await page.mouse.wheel(0, 120)
    await expect.poll(() => scrolledDown(page)).toBe(120)
    expect(await tasks.scrollLeft()).toBe(0)
    expect(await comments.scrollLeft()).toBe(Math.round(most))

    // over a row of /tasks: /tasks scrolls, the nested table stays as it is
    await page.evaluate(() => window.scrollTo(0, 0))
    await expect.poll(() => scrolledDown(page)).toBe(0)
    const row = await box(tasks.cell(FIRST, "status"))
    await page.mouse.move(row.left + 20, row.top + 10)
    await page.keyboard.down("Shift")
    await page.mouse.wheel(0, 200)
    await page.keyboard.up("Shift")
    await expect.poll(() => tasks.scrollLeft()).toBe(200)
    expect(await comments.scrollLeft()).toBe(Math.round(most))
  })

  test("the areas are no tab stops of their own; what they hold is", async ({ tasks }) => {
    await tasks.open()
    const comments = await tasks.openLine(FIRST, "comments")
    await expect(tasks.hookRoot).toHaveAttribute("tabindex", "-1")
    await expect(comments.hookRoot).toHaveAttribute("tabindex", "-1")
    const stops = await tasks.tabStops()
    expect(stops).not.toContain(`${tasks.id}-grid`)
    expect(stops).not.toContain(`${comments.id}-grid`)
    // the nested table's area holds stops of its own: its rows' controls and editable cells
    expect(stops.filter((id) => id.startsWith(`${comments.id}-row-`)).length).toBeGreaterThan(0)
  })
})

test.describe("the scrollbar at the bottom edge of the window", () => {
  test("is there while the table's own is below the window, and scrolls the table", async ({
    page,
    tasks,
  }) => {
    await tasks.open()
    const bar = tasks.scrollbar
    await expect(bar).toBeVisible()

    // as wide as the table's area, at the bottom edge of the window
    const area = await box(tasks.hookRoot)
    const at = await box(bar)
    expect(at.left).toBe(area.left)
    expect(at.right - at.left).toBe((await tasks.area()).seen)
    expect(at.bottom).toBe(await page.evaluate(() => document.documentElement.clientHeight))
    expect(area.bottom).toBeGreaterThan(at.bottom)

    // for the pointer alone
    await expect(bar).toHaveAttribute("aria-hidden", "true")
    await expect(bar).toHaveAttribute("tabindex", "-1")

    // the bar scrolls the table
    await bar.evaluate((bar) => {
      bar.scrollLeft = 300
    })
    await expect.poll(() => tasks.scrollLeft()).toBe(300)
    // and the table the bar
    await tasks.scrollTo(120)
    await expect.poll(() => bar.evaluate((bar) => Math.round(bar.scrollLeft))).toBe(120)
    expect(await tasks.scrollLeft()).toBe(120)

    // the wheel over the bar, with Shift, scrolls the table as well
    await page.mouse.move(at.left + 300, (at.top + at.bottom) / 2)
    await page.keyboard.down("Shift")
    await page.mouse.wheel(0, 100)
    await page.keyboard.up("Shift")
    await expect.poll(() => tasks.scrollLeft()).toBe(220)

    // the table's own scrollbar is in view: the one at the edge is gone
    await tasks.hookRoot.evaluate((grid) => grid.scrollIntoView({ block: "end" }))
    await expect(bar).toBeHidden()
    expect(await tasks.scrollLeft()).toBe(220)

    // and back
    await page.evaluate(() => window.scrollTo(0, 0))
    await expect(bar).toBeVisible()
    await expect.poll(() => bar.evaluate((bar) => Math.round(bar.scrollLeft))).toBe(220)
  })

  test("is not there for a table that has nothing to scroll", async ({ page }) => {
    // /labels fits a wide window, and is higher than a low one
    await page.setViewportSize({ width: 1600, height: 300 })
    const labels = new Table(page, "label", "/labels")
    await labels.open()
    const area = await labels.area()
    expect(area.all).toBe(area.seen)
    expect((await box(labels.hookRoot)).bottom).toBeGreaterThan(300)
    await expect(labels.scrollbar).toBeHidden()

    // in a narrow window it has: the bar comes
    await page.setViewportSize({ width: 500, height: 300 })
    await expect(labels.scrollbar).toBeVisible()
  })

  test("belongs to the innermost table that is cut off at the bottom edge", async ({ page }) => {
    const projects = new Table(page, "project", "/projects")
    await projects.open()
    const nested = await projects.openLine(MOBILE_APP, "tasks")

    // the nested table is higher than the window: its bar, and not the one of /projects
    await nested.hookRoot.evaluate((grid) => grid.scrollIntoView({ block: "start" }))
    await expect(nested.scrollbar).toBeVisible()
    await expect(projects.scrollbar).toBeHidden()
    await expect(page.locator("[data-scrollbar]:visible")).toHaveCount(1)

    await nested.scrollbar.evaluate((bar) => {
      bar.scrollLeft = 250
    })
    await expect.poll(() => nested.scrollLeft()).toBe(250)
    expect(await projects.scrollLeft()).toBe(0)

    // the end of the nested table is in view, with its own scrollbar
    await nested.hookRoot.evaluate((grid) => grid.scrollIntoView({ block: "end" }))
    await expect(nested.scrollbar).toBeHidden()

    // a nested table that is closed takes its bar with it
    await nested.hookRoot.evaluate((grid) => grid.scrollIntoView({ block: "start" }))
    await expect(nested.scrollbar).toBeVisible()
    await projects.line(MOBILE_APP, "tasks").click()
    await expect(nested.scrollbar).toHaveCount(0)
    // and what its hook had written
    await expect.poll(() => ownedSheets(page)).toEqual({ sheets: 1, grids: 1 })
    await expect(page.locator("[data-scrollbar]:visible")).toHaveCount(
      (await projects.area()).all > (await projects.area()).seen &&
        (await box(projects.hookRoot)).bottom > 600
        ? 1
        : 0,
    )
  })
})

test.describe("the label column", () => {
  test("stays in view where the table says `sticky_label? true`, with the cells that select and expand a row", async ({
    tasks,
  }) => {
    await tasks.open()
    const kept = [
      tasks.pageBoxCell,
      tasks.boxCell(FIRST),
      tasks.expanderCell(FIRST),
      tasks.header("title"),
      tasks.filterCell("title"),
      tasks.cell(FIRST, "title"),
    ]
    const before = await Promise.all(kept.map(box))
    const status = await box(tasks.cell(FIRST, "status"))
    // the label column begins where the expander ends, and the next column after it
    expect(before[5].left).toBe(before[2].right)
    expect(status.left).toBe(before[5].right)

    await tasks.scrollTo(600)
    expect(await Promise.all(kept.map(box))).toEqual(before)
    for (const cell of kept) expect(await onTop(cell)).toBe(true)
    // the other columns went under them
    expect((await box(tasks.cell(FIRST, "status"))).left).toBe(status.left - 600)
    await expect(tasks.header("title")).toHaveCSS("position", "sticky")

    // what is under them does not show through
    const ground = await tasks.cell(FIRST, "title").evaluate((cell) => getComputedStyle(cell).backgroundColor)
    expect(ground).not.toMatch(/rgba\(.*, 0\)|transparent|\/ 0\)/)

    // The order of the grid is what it was: the cells of a row in their
    // order, each saying where it stands.
    expect(
      await tasks
        .rowCells(FIRST)
        .evaluateAll((cells) => cells.slice(0, 4).map((cell) => cell.getAttribute("aria-colindex"))),
    ).toEqual(["1", "2", "3", "4"])
  })

  test("in a nested table that says so, in the nested table's own area", async ({ page }) => {
    const projects = new Table(page, "project", "/projects")
    await projects.open()
    const nested = await projects.openLine(MOBILE_APP, "tasks")
    const key = await nested.rowKey(1)
    await nested.hookRoot.evaluate((grid) => grid.scrollIntoView({ block: "start" }))

    const before = await box(nested.cell(key, "title"))
    const status = await box(nested.cell(key, "status"))
    await nested.scrollTo(500)
    expect(await box(nested.cell(key, "title"))).toEqual(before)
    expect((await box(nested.cell(key, "status"))).left).toBe(status.left - 500)
    expect(await onTop(nested.cell(key, "title"))).toBe(true)
  })

  test("scrolls away with the others in a table that does not say so", async ({ page, tasks }) => {
    await page.setViewportSize({ width: 500, height: 600 })
    const labels = new Table(page, "label", "/labels")
    await labels.open()
    const key = await labels.rowKey(1)
    const name = await box(labels.cell(key, "name"))
    const first = await box(labels.rowCells(key).first())

    await labels.scrollTo(150)
    expect((await box(labels.cell(key, "name"))).left).toBe(name.left - 150)
    expect((await box(labels.rowCells(key).first())).left).toBe(first.left - 150)
    // nothing of the table stays: no cell of it is sticky
    expect(
      await labels.grid.evaluate(
        (table) =>
          Array.from(table.querySelectorAll("th,td")).filter(
            (cell) => getComputedStyle(cell).position === "sticky",
          ).length,
      ),
    ).toBe(0)

    // nor in the comments under a task, whose table says nothing either
    await tasks.open()
    const comments = await tasks.openLine(FIRST, "comments")
    const box0 = await box(comments.rowCells(await comments.rowKey(1)).first())
    await comments.scrollTo(100)
    expect((await box(comments.rowCells(await comments.rowKey(1)).first())).left).toBe(box0.left - 100)
  })

  test("a column is made wider and others are hidden while it stays", async ({ tasks }) => {
    await tasks.open()
    await tasks.scrollTo(400)
    const title = await box(tasks.cell(FIRST, "title"))

    // its own handle: the column is wider, and begins where it began
    await tasks.drag("title", 60)
    await expect.poll(async () => (await box(tasks.cell(FIRST, "title"))).right).toBe(title.right + 60)
    expect((await box(tasks.cell(FIRST, "title"))).left).toBe(title.left)
    expect(await box(tasks.header("title"))).toMatchObject({ left: title.left, right: title.right + 60 })
    expect(await onTop(tasks.cell(FIRST, "title"))).toBe(true)

    // from the keyboard as well: its width field
    await tasks.typeWidth("title", Math.round(title.right + 50 - title.left))
    await expect.poll(async () => (await box(tasks.cell(FIRST, "title"))).right).toBe(title.right + 50)
    await tasks.page.keyboard.press("Escape")

    // columns are hidden: the label column stays where it is, and cannot be hidden
    await tasks.hide("status", "priority")
    expect(await tasks.listedColumns()).not.toContain("title")
    // the list closed again: it stands over the label column while it is open
    await tasks.page.keyboard.press("Escape")
    await expect(tasks.columnsList).toBeHidden()
    expect(await box(tasks.cell(FIRST, "title"))).toMatchObject({ left: title.left, right: title.right + 50 })
    expect(await onTop(tasks.cell(FIRST, "title"))).toBe(true)
  })
})

test.describe("with the keyboard", () => {
  test("what Tab moves focus to is seen whole: beside the cells that stay, and above the scrollbar", async ({
    page,
    tasks,
  }) => {
    await tasks.open()
    const kept = (await box(tasks.cell(FIRST, "title"))).right
    const area = await box(tasks.hookRoot)
    const end = area.left + (await tasks.area()).seen
    const stops = (await tasks.tabStops()).filter((id) => id.startsWith(`task-row-${FIRST}-`))

    // to the end of the row, and back stop by stop: none is under the label column
    await page.locator(`[id="${stops.at(-1)}"]`).focus()
    expect(await tasks.scrollLeft()).toBeGreaterThan(0)
    for (let step = 0; step < 8; step++) {
      await page.keyboard.press("Shift+Tab")
      await expect(focused(page)).toHaveId(stops.at(-2 - step)!)
      const at = await box(focused(page))
      expect(at.left).toBeGreaterThanOrEqual(kept)
      expect(at.right).toBeLessThanOrEqual(end)
      expect(await onTop(focused(page))).toBe(true)
    }

    // forward again: none is cut off at the end of the area
    for (let step = 0; step < 8; step++) {
      await page.keyboard.press("Tab")
      const at = await box(focused(page))
      expect(at.left).toBeGreaterThanOrEqual(kept)
      expect(at.right).toBeLessThanOrEqual(end)
    }

    // from the last stop of a row to the first of the next, down the page:
    // it is above the scrollbar at the bottom edge
    await expect(tasks.scrollbar).toBeVisible()
    const keys = await tasks.rowKeys()
    for (let row = 0; row < 14; row++) {
      const last = (await tasks.tabStops()).filter((id) => id.startsWith(`task-row-${keys[row]}-`)).at(-1)!
      await page.locator(`[id="${last}"]`).focus()
      await page.keyboard.press("Tab")
      await expect(tasks.boxCell(keys[row + 1]).locator("input")).toBeFocused()
      const at = await box(focused(page))
      expect(at.bottom).toBeLessThanOrEqual((await box(tasks.scrollbar)).top)
      expect(at.top).toBeGreaterThanOrEqual(0)
      expect(await onTop(focused(page))).toBe(true)
    }
    expect(await scrolledDown(page)).toBeGreaterThan(0)
  })

  test("in a nested table, in that table's own area, and the table around it stays", async ({
    page,
    tasks,
  }) => {
    await tasks.open()
    const comments = await tasks.openLine(FIRST, "comments")
    const key = await comments.rowKey(1)
    await tasks.scrollTo(300)
    // the row's stops: its controls and editable cells, left to right
    const stops = comments
      .row(key)
      .locator(":is(button, input, select, a[href], [tabindex='0']):not([tabindex='-1'])")
      .filter({ visible: true })
    const count = await stops.count()
    expect(count).toBeGreaterThan(2)

    // Tab to the row's last stop
    await stops.nth(count - 2).focus()
    await page.keyboard.press("Tab")
    await expect(stops.nth(count - 1)).toBeFocused()
    expect(await comments.scrollLeft()).toBeGreaterThan(0)
    const area = await box(comments.hookRoot)
    const last = await box(focused(page))
    expect(last.right).toBeLessThanOrEqual(area.left + (await comments.area()).seen)

    // and Shift+Tab back to its first
    await stops.nth(1).focus()
    await page.keyboard.press("Shift+Tab")
    await expect(stops.nth(0)).toBeFocused()
    await expect.poll(() => comments.scrollLeft()).toBe(0)
    expect((await box(comments.rowCells(key).first())).left).toBe(area.left)

    // /tasks did not move through any of it
    expect(await tasks.scrollLeft()).toBe(300)
  })
})

test.describe("what floats over a table that is scrolled", () => {
  test("the list of columns of a nested table is whole and on top", async ({ page, tasks }) => {
    await tasks.open()
    const comments = await tasks.openLine(FIRST, "comments")
    await tasks.scrollTo(300)
    await comments.scrollTo(150)

    // the button is in view whatever is scrolled, and its list opens under it
    const button = await box(comments.columnsButton)
    expect(button.left).toBeGreaterThanOrEqual((await box(tasks.hookRoot)).left)
    await comments.openColumns()
    const list = await box(comments.columnsList)
    expect(list.top).toBeGreaterThanOrEqual(button.bottom)
    expect(list.left).toBeGreaterThanOrEqual(0)
    expect(list.right).toBeLessThanOrEqual(1000)
    expect(await onTop(comments.columnsList)).toBe(true)

    // hiding a column from it works as before
    const columns = await comments.listedColumns()
    await comments.columnBox(columns[0]).uncheck()
    await expect(comments.header(columns[0])).toBeHidden()
  })

  test("the editor of a cell and the dialog of a row action in a scrolled table", async ({ page, tasks }) => {
    await tasks.open()
    await tasks.scrollTo(400)

    // the label column is edited where it stays
    await tasks.cell(FIRST, "title").dblclick()
    const editor = tasks.editor(tasks.cell(FIRST, "title"))
    await expect(editor).toBeFocused()
    expect(await onTop(editor)).toBe(true)
    expect(await tasks.scrollLeft()).toBe(400)
    await page.keyboard.press("Escape")
    await expect(tasks.cell(FIRST, "title")).toBeFocused()

    // a row action at the far end asks in the dialog, which is in the middle of the window
    await tasks.scrollTo(100000)
    await tasks.action(FIRST, "destroy").click()
    await expect(tasks.dialog).toBeVisible()
    const dialog = await box(tasks.dialog)
    expect(dialog.left).toBeGreaterThanOrEqual(0)
    expect(dialog.right).toBeLessThanOrEqual(1000)
    expect(await onTop(tasks.dialog)).toBe(true)
    await tasks.dialog.getByRole("button", { name: "Cancel" }).click()
    await expect(tasks.dialog).toBeHidden()
  })
})

for (const theme of ["light", "dark"] as const) {
  test.describe(`axe, in the ${theme} theme`, () => {
    test.beforeEach(async ({ page }) => {
      await page.addInitScript((theme) => localStorage.setItem("phx:theme", theme), theme)
    })

    test("a table and a nested table, both scrolled, with the scrollbar at the bottom edge", async ({
      page,
      tasks,
    }) => {
      test.slow()
      await tasks.open()
      await expect(page.locator("html")).toHaveAttribute("data-theme", theme)
      const comments = await tasks.openLine(FIRST, "comments")
      await tasks.scrollTo(300)
      await comments.scrollTo(150)
      await expect(page.locator("[data-scrollbar]:visible")).toHaveCount(1)
      await expectNoAxeViolations(page)

      // with focus on a cell that stays, and on one beside it
      await tasks.cell(FIRST, "title").focus()
      await expectNoAxeViolations(page, "#task-table > [role=rowgroup]:first-of-type")
      await page.keyboard.press("Tab")
      await expectNoAxeViolations(page, "#task-table > [role=rowgroup]:first-of-type")
    })
  })
}
