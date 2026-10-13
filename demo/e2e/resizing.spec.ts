import { expectNoAxeViolations } from "./support/a11y"
import { SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { switchLocale } from "./support/locale"
import { Table, columnRules, ownedSheets } from "./support/table"
import { params } from "./support/url"

// Spec section 17, slice 12: a person changes a column's width with the
// handle at the end of its header, by dragging it or with the arrow keys.
// The widths are the browser's alone: nothing is sent, nothing is in the
// URL, they outlive every patch of the page and are gone with it.

const FIRST = SEED.task.first
const SECOND = SEED.task.second

/** The narrowest and the widest a column can be made, and the step of an arrow key. */
const NARROWEST = 48
const WIDEST = 1000
const STEP = 10

/** The widths of a few columns of /tasks, which a test changes or expects unchanged. */
async function some(table: Table, columns: string[]): Promise<Record<string, number>> {
  const widths: Record<string, number> = {}
  for (const column of columns) widths[column] = await table.width(column)
  return widths
}

test.describe("with the pointer", () => {
  test.beforeEach(async ({ tasks }) => {
    await tasks.open()
  })

  test("dragging the handle makes the column narrower and wider, and no other column changes", async ({
    page,
    tasks,
    frames,
  }) => {
    const before = await tasks.widths()
    const title = await tasks.width("title")
    const index = (await tasks.columns()).indexOf("title") + 2 // the boxes and the expanders come first
    expect(before[index]).toBe(title)
    await frames.clear()

    await tasks.drag("title", -100)
    expect(await tasks.width("title")).toBe(title - 100)
    expect(await tasks.widths()).toEqual(before.map((width, at) => (at === index ? title - 100 : width)))

    // the controls of the column's filter make room: they end inside their cell
    const filter = (await tasks.filterCell("title").boundingBox())!
    const value = (await tasks.filterValue("title").boundingBox())!
    expect(filter.width).toBe(title - 100)
    expect(value.x + value.width).toBeLessThanOrEqual(filter.x + filter.width)

    await tasks.drag("title", 160)
    expect(await tasks.width("title")).toBe(title + 60)
    expect(await tasks.widths()).toEqual(before.map((width, at) => (at === index ? title + 60 : width)))

    // every cell of the column is as wide as its header, the filter's too
    for (const cell of [tasks.filterCell("title"), tasks.cell(FIRST, "title"), tasks.cell(SECOND, "title")]) {
      expect((await cell.boundingBox())!.width).toBe(title + 60)
    }

    // the server has heard of none of it, and the URL says nothing
    expect(await frames.all()).toEqual([])
    expect(params(page)).toEqual({})
  })

  test("the handle stays under the pointer while it is dragged", async ({ page, tasks }) => {
    const handle = tasks.resizer("status")
    const box = (await handle.boundingBox())!
    const x = box.x + box.width / 2
    await page.mouse.move(x, box.y + box.height / 2)
    await page.mouse.down()
    for (const by of [-30, -55, 20, 75]) {
      await page.mouse.move(x + by, box.y + 100)
      const now = (await handle.boundingBox())!
      expect(now.x + now.width / 2).toBe(x + by)
    }
    await expect(handle).toHaveAttribute("data-dragging", "")
    await page.mouse.up()
    await expect(handle).not.toHaveAttribute("data-dragging")
  })

  test("neither a drag nor a click on the handle sorts; a click on the header beside it still does", async ({
    page,
    tasks,
    frames,
  }) => {
    const header = tasks.header("title")
    await expect(header).toHaveAttribute("data-sort", "")
    await frames.clear()

    // let go over the handle itself, over the header, and over a cell of another column
    await tasks.drag("title", -40)
    const box = (await tasks.resizer("title").boundingBox())!
    await page.mouse.move(box.x + 6, box.y + 10)
    await page.mouse.down()
    await page.mouse.move(box.x - 60, box.y + 10, { steps: 3 })
    await page.mouse.up()
    await tasks.resizer("title").click()
    await tasks.resizer("title").dblclick()

    expect(await frames.count("sort")).toBe(0)
    await expect(header).toHaveAttribute("aria-sort", "none")
    expect(params(page)).toEqual({})

    // the click after a drag is the only one that is swallowed
    await tasks.reads(() => header.click({ position: { x: 20, y: 10 } }))
    await expect(header).toHaveAttribute("aria-sort", "ascending")
  })

  test("a double click on the handle makes the column as wide again as it was", async ({ tasks }) => {
    const title = await tasks.width("title")
    await tasks.drag("title", -120)
    await tasks.drag("status", 80)
    const status = await tasks.width("status")
    expect(await tasks.width("title")).toBe(title - 120)

    await tasks.resizer("title").dblclick()
    expect(await tasks.width("title")).toBe(title)
    // and that column alone
    expect(await tasks.width("status")).toBe(status)
  })

  test("a column cannot be made narrower than 48 pixels or wider than 1000", async ({ tasks }) => {
    await tasks.drag("title", -600)
    expect(await tasks.width("title")).toBe(NARROWEST)
    await expect(tasks.resizer("title")).toHaveAttribute("aria-valuenow", String(NARROWEST))
    await expect(tasks.header("title")).toBeVisible()

    await tasks.drag("title", 1300)
    expect(await tasks.width("title")).toBe(WIDEST)
    await expect(tasks.resizer("title")).toHaveAttribute("aria-valuenow", String(WIDEST))
  })

  test("a drag selects no text and leaves the focus where it is, and the pointer shows what the handle is for", async ({
    page,
    tasks,
  }) => {
    await tasks.cell(SECOND, "status").focus()
    await tasks.drag("title", 150)
    await expect(tasks.cell(SECOND, "status")).toBeFocused()
    expect(await page.evaluate(() => String(getSelection()))).toBe("")
    expect(await tasks.resizer("title").evaluate((handle) => getComputedStyle(handle).cursor)).toBe("col-resize")
    expect(await tasks.resizer("title").evaluate((handle) => getComputedStyle(handle).touchAction)).toBe("none")
  })

  test("a narrow column cuts its text off on one line, in the header as in the cells, and no row changes its height", async ({
    tasks,
  }) => {
    const heights = async () => {
      const rows = [tasks.grid.locator(":scope > thead > tr").first(), tasks.rowLine(FIRST), tasks.rowLine(SECOND)]
      return Promise.all(rows.map(async (row) => (await row.boundingBox())!.height))
    }
    const before = await heights()

    await tasks.drag("title", -600)
    await tasks.drag("status", -600)
    await tasks.drag("progress", -600)
    expect(await heights()).toEqual(before)

    for (const cell of [tasks.header("title"), tasks.cell(FIRST, "title")]) {
      const style = await cell.evaluate((cell) => {
        const { overflowX, textOverflow, whiteSpace } = getComputedStyle(cell)
        return { overflowX, textOverflow, whiteSpace, cut: cell.scrollWidth > cell.clientWidth }
      })
      expect(style).toEqual({ overflowX: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", cut: true })
    }
    // the header is still called by its whole name
    await expect(tasks.header("title")).toHaveAccessibleName("Title")
  })

  test("the handle is not seen until it is pointed at, and then a line at the column's edge", async ({
    page,
    tasks,
  }) => {
    const handle = tasks.resizer("title")
    const line = () =>
      handle.evaluate((handle) => {
        const after = getComputedStyle(handle, "::after")
        return after.content === "none" ? null : after.borderInlineEndWidth
      })
    expect(await handle.evaluate((handle) => getComputedStyle(handle).backgroundColor)).toBe("rgba(0, 0, 0, 0)")
    expect(await line()).toBeNull()
    await handle.hover()
    expect(await line()).toBe("2px")
    await page.mouse.move(0, 0)
    expect(await line()).toBeNull()
  })
})

test.describe("how the table is laid out", () => {
  test("until a width is changed the table fills its place; from then on it is as wide as its columns", async ({
    page,
  }) => {
    const labels = new Table(page, "label", "/labels")
    await labels.open()
    const place = () => labels.hookRoot.evaluate((root) => [root.clientWidth, root.scrollWidth])
    const table = async () => (await labels.grid.boundingBox())!.width
    const [room] = await place()
    expect(await table()).toBe(room)
    const before = await labels.widths()
    const name = await labels.width("name")

    // the first change moves no other column
    await labels.drag("name", -50)
    // (a width a person sets is a whole number of pixels)
    const after = await labels.widths()
    expect(after.filter((width, at) => width !== before[at])).toEqual([Math.round(name - 50)])
    const sum = after.reduce((sum, width) => sum + width, 0)
    expect(Math.abs(sum - (room - 50))).toBeLessThan(1)
    expect(await table()).toBe(sum)

    // wider than its place, the table scrolls sideways in it
    await labels.drag("name", 700)
    const [width, scrolls] = await place()
    expect(width).toBe(room)
    expect(scrolls).toBeGreaterThan(room)
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
  })

  test("the columns before and after the table's columns have no handle", async ({ tasks }) => {
    await tasks.open()
    await expect(tasks.headerCells.first().locator("[data-resize]")).toHaveCount(0)
    await expect(tasks.headerCells.nth(1).locator("[data-resize]")).toHaveCount(0)
    await expect(tasks.actionsHeader.locator("[data-resize]")).toHaveCount(0)
    await expect(tasks.grid.locator(":scope > thead [data-resize]")).toHaveCount((await tasks.columns()).length)
  })
})

test.describe("with the keyboard", () => {
  test.beforeEach(async ({ tasks }) => {
    await tasks.open()
  })

  test("F2 on a header goes to its handle; the arrow keys move it, Enter undoes, Escape goes back", async ({
    page,
    tasks,
    frames,
  }) => {
    const header = tasks.header("title")
    const handle = tasks.resizer("title")
    const title = await tasks.width("title")
    await header.focus()
    await frames.clear()

    await tasks.press("F2")
    await expect(handle).toBeFocused()
    await expect(handle).toHaveRole("separator")
    await expect(handle).toHaveAccessibleName("Resize Title")
    await expect(handle).toHaveAttribute("aria-orientation", "vertical")
    await expect(handle).toHaveAttribute("aria-valuemin", String(NARROWEST))
    await expect(handle).toHaveAttribute("aria-valuemax", String(WIDEST))
    await expect(handle).toHaveAttribute("aria-valuenow", String(title))

    await tasks.press("ArrowRight", "ArrowRight", "ArrowRight")
    expect(await tasks.width("title")).toBe(title + 3 * STEP)
    await expect(handle).toHaveAttribute("aria-valuenow", String(title + 3 * STEP))
    await tasks.press("ArrowLeft", "ArrowLeft", "ArrowLeft", "ArrowLeft", "ArrowLeft")
    expect(await tasks.width("title")).toBe(title - 2 * STEP)
    await expect(handle).toHaveAttribute("aria-valuenow", String(title - 2 * STEP))
    await expect(handle).toBeFocused()

    await tasks.press("Home")
    expect(await tasks.width("title")).toBe(NARROWEST)
    await tasks.press("ArrowLeft")
    expect(await tasks.width("title")).toBe(NARROWEST)
    await tasks.press("End")
    expect(await tasks.width("title")).toBe(WIDEST)
    await tasks.press("ArrowRight")
    expect(await tasks.width("title")).toBe(WIDEST)

    await tasks.press("Enter")
    expect(await tasks.width("title")).toBe(title)
    await expect(handle).toHaveAttribute("aria-valuenow", String(title))
    await expect(handle).toBeFocused()

    await tasks.press("ArrowLeft", "Escape")
    await expect(header).toBeFocused()
    expect(await tasks.width("title")).toBe(title - STEP)

    // none of it sorted, or said anything to the server
    expect(await frames.all()).toEqual([])
    expect(params(page)).toEqual({})
    await expect(header).toHaveAttribute("aria-sort", "none")
  })

  test("the keys of the grid are as they were: the handle is no stop of the arrow keys or of Tab", async ({
    page,
    tasks,
  }) => {
    await tasks.header("title").focus()
    await tasks.press("ArrowRight")
    await expect(tasks.header("status")).toBeFocused()
    await tasks.press("ArrowLeft", "ArrowDown")
    await expect(tasks.filterCell("title")).toBeFocused()
    await tasks.press("ArrowUp")
    await expect(tasks.header("title")).toBeFocused()
    expect(await tasks.tabStops()).toEqual(["task-head-title"])

    // on the handle, the keys that move about the grid or scroll the page do nothing
    await tasks.press("F2")
    const scrolled = await page.evaluate(() => window.scrollY)
    await tasks.press("ArrowDown", "ArrowUp", "PageDown", "PageUp", "Space", "x")
    await expect(tasks.resizer("title")).toBeFocused()
    expect(await page.evaluate(() => window.scrollY)).toBe(scrolled)
    // the header is still the one tab stop, and Tab leaves the grid
    expect(await tasks.tabStops()).toEqual(["task-head-title"])
    await tasks.press("Tab")
    expect(await tasks.hookRoot.evaluate((root) => root.contains(document.activeElement))).toBe(false)
    await tasks.press("Shift+Tab")
    await expect(tasks.header("title")).toBeFocused()
  })

  test("Enter on a header still sorts, with a handle in it, and F2 works on a header that does not sort", async ({
    tasks,
  }) => {
    await tasks.header("title").focus()
    await tasks.reads(() => tasks.press("Enter"))
    await expect(tasks.header("title")).toHaveAttribute("aria-sort", "ascending")
    await expect(tasks.header("title")).toBeFocused()

    const tags = tasks.header("tags")
    await expect(tags).not.toHaveAttribute("data-sort")
    const width = await tasks.width("tags")
    await tags.focus()
    await tasks.press("F2", "ArrowRight")
    await expect(tasks.resizer("tags")).toBeFocused()
    expect(await tasks.width("tags")).toBe(Math.round(width) + STEP)
  })

  test("the handle that has the focus shows it: a ring in the text colour, and the line", async ({ tasks }) => {
    await tasks.header("title").focus()
    await tasks.press("F2")
    const handle = tasks.resizer("title")
    const style = await handle.evaluate((handle) => {
      const { outlineStyle, outlineWidth, outlineColor } = getComputedStyle(handle)
      const text = getComputedStyle(handle.closest("table")!.querySelector("td")!).color
      return { outlineStyle, outlineWidth, text: outlineColor === text, line: getComputedStyle(handle, "::after").content }
    })
    expect(style).toEqual({ outlineStyle: "solid", outlineWidth: "2px", text: true, line: '""' })
  })

  test("where text runs from right to left the column's end is on the left, and so are the keys", async ({
    page,
    tasks,
  }) => {
    await page.evaluate(() => document.documentElement.setAttribute("dir", "rtl"))
    const title = Math.round(await tasks.width("title"))
    await tasks.header("title").focus()
    await tasks.press("F2", "ArrowLeft", "ArrowLeft")
    expect(await tasks.width("title")).toBe(title + 2 * STEP)
    await tasks.press("ArrowRight")
    expect(await tasks.width("title")).toBe(title + STEP)
    await tasks.drag("title", -50)
    expect(await tasks.width("title")).toBe(title + STEP + 50)
  })
})

test.describe("the widths outlive what the server sends", () => {
  test.use({ writes: true })

  test("a sort, a filter, another page, a saved cell and an expanded row", async ({ page, tasks }) => {
    await tasks.open()
    const columns = ["title", "status", "priority"]
    await tasks.drag("title", -190)
    await tasks.drag("status", 60)
    const set = await some(tasks, columns)
    const all = await tasks.widths()
    const same = async (after: string) => {
      expect(await some(tasks, columns), after).toEqual(set)
      expect(await tasks.widths(), after).toEqual(all)
      expect((await tasks.cell(await tasks.rowKey(1), "title").boundingBox())!.width, after).toBe(set.title)
      await expect(tasks.resizer("title"), after).toHaveAttribute("aria-valuenow", String(set.title))
    }

    await tasks.reads(() => tasks.header("priority").click({ position: { x: 20, y: 10 } }))
    await expect(tasks.header("priority")).toHaveAttribute("aria-sort", "ascending")
    await same("after a sort")

    await tasks.filterValue("title").fill("the")
    await tasks.reads(() => tasks.filterValue("title").press("Enter"))
    await expect(tasks.clearFilters).toBeVisible()
    await same("after a filter")

    await tasks.reads(() => tasks.next.click())
    await same("on another page")

    const key = await tasks.rowKey(1)
    const title = tasks.cell(key, "title")
    await title.focus()
    await tasks.press("Enter")
    // the editor is as wide as the column lets it be, though it would like more
    const editor = (await tasks.editor(title).boundingBox())!
    const cell = (await title.boundingBox())!
    expect(cell.width).toBeLessThan(96)
    expect(editor.x + editor.width).toBeLessThanOrEqual(cell.x + cell.width)
    await tasks.retype("A title that is a good deal longer than the column is wide")
    await tasks.saves(title, () => tasks.press("Enter"))
    await expect(title).toHaveText("A title that is a good deal longer than the column is wide")
    await same("after a save")

    await tasks.expand(key)
    await same("with a row expanded")
    const comments = await tasks.openLine(key, "comments")
    await same("with a nested table open")

    await tasks.reads(() => tasks.clearFilters.click())
    await same("after the filters were cleared")
    expect(params(page)).toEqual({ "task[sort]": "priority" })
  })

  test("a page that is loaded again has forgotten them", async ({ page, tasks }) => {
    await tasks.open()
    const before = await tasks.widths()
    await tasks.drag("title", -90)
    await tasks.drag("progress", 45)
    expect(await tasks.widths()).not.toEqual(before)

    await page.reload()
    await tasks.ready()
    expect(await tasks.widths()).toEqual(before)
    // one sheet per grid, for what its hook says of scrolling sideways, and
    // none for widths or hidden columns
    expect(await ownedSheets(page)).toEqual({ sheets: 1, grids: 1 })
    expect(await columnRules(page)).toBe(0)
  })

  test("so has a page that was left and come back to", async ({ page, tasks }) => {
    await tasks.open()
    const before = await tasks.widths()
    await tasks.drag("title", -90)

    await page.getByRole("navigation", { name: "Main" }).getByRole("link", { name: "Labels" }).click()
    await new Table(page, "label", "/labels").ready()
    // the rules went with the table
    // one sheet per grid, for what its hook says of scrolling sideways, and
    // none for widths or hidden columns
    expect(await ownedSheets(page)).toEqual({ sheets: 1, grids: 1 })
    expect(await columnRules(page)).toBe(0)
    await page.goBack()
    await tasks.ready()
    expect(await tasks.widths()).toEqual(before)
  })
})

test("the widths stay with their columns when the header gets another column in front", async ({ tasks }) => {
  await tasks.open()
  await tasks.drag("title", -100)
  await tasks.drag("status", 50)
  const set = await some(tasks, ["title", "status", "priority"])

  // What a patch does that takes the column of the boxes away: its cells
  // go, and every cell after them stands one place further to the left.
  await tasks.grid.evaluate((table) => {
    for (const row of Array.from((table as HTMLTableElement).rows)) {
      const first = row.cells[0]
      if (first.colSpan > 1) continue
      first.remove()
      for (const cell of Array.from(row.cells)) {
        cell.setAttribute("aria-colindex", String(Number(cell.getAttribute("aria-colindex")) - 1))
      }
    }
  })

  await expect.poll(() => some(tasks, ["title", "status", "priority"])).toEqual(set)
  expect((await tasks.cell(FIRST, "title").boundingBox())!.width).toBe(set.title)
  expect((await tasks.cell(FIRST, "status").boundingBox())!.width).toBe(set.status)
})

test.describe("each table on its own", () => {
  test("a nested table: its widths are its own, and it looks and works as any table", async ({ tasks }) => {
    await tasks.open()
    const comments = await tasks.openLine(FIRST, "comments")
    const outer = await tasks.widths()
    const body = await comments.width("body")
    const inner = await comments.widths()
    const at = (await comments.headerCells.evaluateAll((cells) => cells.map((cell) => cell.id))).indexOf(
      `${comments.id}-head-body`,
    )

    // the same handle as on the table around it
    const look = (table: Table, column: string) =>
      table.resizer(column).evaluate((handle) => {
        const { position, width, cursor, insetInlineEnd } = getComputedStyle(handle)
        return { position, width, cursor, insetInlineEnd, role: handle.getAttribute("role") }
      })
    expect(await look(comments, "body")).toEqual(await look(tasks, "title"))

    await comments.drag("body", -70)
    expect(await comments.width("body")).toBe(body - 70)
    expect(await comments.widths()).toEqual(inner.map((width, index) => (index === at ? body - 70 : width)))
    // the table around it is as it was: nothing of it has a width yet
    expect(await tasks.widths()).toEqual(outer)

    await comments.header("body").focus()
    await tasks.press("F2", "ArrowRight")
    await expect(comments.resizer("body")).toBeFocused()
    expect(await comments.width("body")).toBe(body - 70 + STEP)
    await tasks.press("Escape")
    await expect(comments.header("body")).toBeFocused()

    // and the other way round
    const title = await tasks.width("title")
    await tasks.drag("title", -80)
    expect(await tasks.width("title")).toBe(title - 80)
    expect(await comments.width("body")).toBe(body - 70 + STEP)
  })

  test("a nested table that is closed and opened again has forgotten its widths", async ({ tasks }) => {
    await tasks.open()
    const comments = await tasks.openLine(FIRST, "comments")
    const body = await comments.width("body")
    await comments.drag("body", -70)
    expect(await comments.width("body")).toBe(body - 70)

    await tasks.line(FIRST, "comments").click()
    await expect(comments.grid).toHaveCount(0)
    await tasks.line(FIRST, "comments").click()
    expect(await comments.width("body")).toBe(body)
  })

  test("the table of a picker", async ({ tasks }) => {
    await tasks.open()
    await tasks.cell(FIRST, "assignee").focus()
    await tasks.press("Enter")
    await expect(tasks.picker).toBeVisible()
    const users = tasks.pickerTable("assignee")
    await users.ready()
    const [column] = await users.columns()
    const width = Math.round(await users.width(column))
    const outer = await tasks.widths()
    const selected = await users.selectedKeys()

    await users.drag(column, -40)
    expect(await users.width(column)).toBe(width - 40)
    await users.header(column).focus()
    await tasks.press("F2", "ArrowRight")
    expect(await users.width(column)).toBe(width - 30)
    // Escape on the handle goes back to the header, and the picker stays
    await tasks.press("Escape")
    await expect(users.header(column)).toBeFocused()
    await expect(tasks.picker).toBeVisible()
    // a drag has selected or chosen no row
    expect(await users.selectedKeys()).toEqual(selected)
    await tasks.pickerCancel.click()
    await expect(tasks.picker).toHaveCount(0)
    expect(await tasks.widths()).toEqual(outer)
  })

  test("two tables in one page", async ({ page }) => {
    const projects = new Table(page, "dashboard-projects", "/dashboard")
    const tasks = new Table(page, "dashboard-tasks", "/dashboard")
    await projects.open()
    await tasks.ready()
    const before = await tasks.widths()
    const name = await projects.width("name")

    await projects.drag("name", -60)
    expect(await projects.width("name")).toBeCloseTo(name - 60, 0)
    expect(await tasks.widths()).toEqual(before)

    const title = await tasks.width("title")
    const set = await projects.widths()
    await tasks.drag("title", 70)
    expect(await tasks.width("title")).toBeCloseTo(title + 70, 0)
    expect(await projects.widths()).toEqual(set)

    // a patch of one leaves the widths of both
    const mine = await tasks.widths()
    await projects.reads(() => projects.header("name").click({ position: { x: 20, y: 10 } }))
    expect(await projects.widths()).toEqual(set)
    expect(await tasks.widths()).toEqual(mine)
  })
})

test("in German the handle is called in German", async ({ page, tasks }) => {
  await tasks.open()
  await switchLocale(page, "de")
  await tasks.ready()
  await expect(tasks.resizer("title")).toHaveAccessibleName("Breite von Titel ändern")
  await expect(tasks.header("title")).toHaveAccessibleName("Titel")
})

for (const theme of ["light", "dark"] as const) {
  test.describe(`axe, in the ${theme} theme`, () => {
    test.beforeEach(async ({ page, tasks }) => {
      await page.addInitScript((theme) => localStorage.setItem("phx:theme", theme), theme)
      await tasks.open()
      await expect(page.locator("html")).toHaveAttribute("data-theme", theme)
    })

    test("as the page opens, and with columns made narrower and wider", async ({ page, tasks }) => {
      // every handle says how wide its column is
      for (const column of await tasks.columns()) {
        await expect(tasks.resizer(column)).toHaveAttribute("aria-valuenow", /^\d+$/)
      }
      await expectNoAxeViolations(page)

      await tasks.drag("title", -600)
      await tasks.drag("status", 120)
      await expectNoAxeViolations(page)
    })

    test("a handle with the focus, in a table and in a nested table", async ({ page, tasks }) => {
      await tasks.header("priority").focus()
      await tasks.press("F2", "ArrowLeft")
      await expect(tasks.resizer("priority")).toBeFocused()
      await expectNoAxeViolations(page)

      const comments = await tasks.openLine(FIRST, "comments")
      await comments.drag("body", -70)
      await comments.header("body").focus()
      await tasks.press("F2")
      await expect(comments.resizer("body")).toBeFocused()
      await expectNoAxeViolations(page)
    })
  })
}
