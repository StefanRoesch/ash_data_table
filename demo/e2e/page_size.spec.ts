import { expectNoAxeViolations } from "./support/a11y"
import { SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { Table } from "./support/table"
import { params } from "./support/url"

// "Rows per page": the menu of a table that declares `page_sizes`. The
// tasks offer 10, 25 and 50 and open with 25; the comments, read by keyset,
// offer 10, 20 and 50 and open with 20; the projects offer none.
//
// Nothing here writes a record.

const MOBILE_APP = SEED.project.mobileApp

test.describe("/tasks, by offset", () => {
  test.beforeEach(async ({ tasks }) => {
    await tasks.open()
  })

  test("the menu: its label, its sizes, and where it is among the controls", async ({
    page,
    tasks,
  }) => {
    await expect(tasks.pageSize).toHaveRole("combobox")
    await expect(tasks.pageSize).toHaveAccessibleName("Rows per page")
    await expect(tasks.pagination.getByText("Rows per page", { exact: true })).toBeVisible()
    await expect(tasks.pageSize.locator("option")).toHaveText(["10", "25", "50"])
    await expect(tasks.pageSize).toHaveValue("25")

    // one more tab stop, after Next
    await tasks.next.focus()
    await page.keyboard.press("Tab")
    await expect(tasks.pageSize).toBeFocused()

    // on the line of the buttons, to their right
    const next = (await tasks.next.boundingBox())!
    const menu = (await tasks.pageSize.boundingBox())!
    expect(menu.x).toBeGreaterThan(next.x + next.width)
    expect(Math.abs(menu.y + menu.height / 2 - (next.y + next.height / 2))).toBeLessThan(2)
  })

  test("chosen with the mouse: the first page with that many rows, the range, the URL", async ({
    page,
    tasks,
  }) => {
    await tasks.reads(() => tasks.pageSize.selectOption("50"))

    await expect(tasks.rows).toHaveCount(50)
    await expect(tasks.range).toHaveText(`1–50 of ${SEED.tasks.acme}`)
    await expect(tasks.pageSize).toHaveValue("50")
    expect(params(page)).toEqual({ "task[per]": "50" })
    // 320 tasks in pages of 50
    await expect(tasks.pageButton(7)).toBeVisible()
    await expect(tasks.pageButton(8)).toHaveCount(0)

    await tasks.reads(() => tasks.pageSize.selectOption("10"))

    await expect(tasks.rows).toHaveCount(10)
    await expect(tasks.range).toHaveText(`1–10 of ${SEED.tasks.acme}`)
    expect(params(page)).toEqual({ "task[per]": "10" })

    // the size the table opens with needs no parameter
    await tasks.reads(() => tasks.pageSize.selectOption("25"))

    await expect(tasks.rows).toHaveCount(25)
    expect(params(page)).toEqual({})
  })

  test("chosen with the keyboard: applies at once, and the menu keeps the focus", async ({
    page,
    tasks,
  }) => {
    await tasks.pageSize.focus()
    // the arrow keys are the menu's own (a <select>), not the table's
    await tasks.reads(() => page.keyboard.press("ArrowDown"))

    await expect(tasks.pageSize).toHaveValue("50")
    await expect(tasks.rows).toHaveCount(50)
    await expect(tasks.range).toHaveText(`1–50 of ${SEED.tasks.acme}`)
    await expect(tasks.pageSize).toBeFocused()

    await tasks.reads(() => page.keyboard.press("ArrowUp"))

    await expect(tasks.pageSize).toHaveValue("25")
    await expect(tasks.rows).toHaveCount(25)
    await expect(tasks.pageSize).toBeFocused()

    // and back among the buttons
    await page.keyboard.press("Shift+Tab")
    await expect(tasks.next).toBeFocused()
  })

  test("from a later page it goes to the first; the sort and the filter stay", async ({
    page,
    tasks,
  }) => {
    await tasks.sortBy("title")
    await tasks.reads(async () => {
      await tasks.filterValue("title").fill("a")
      await tasks.filterValue("title").press("Enter")
    })
    await tasks.reads(() => tasks.pageButton(3).click())
    expect(params(page)).toEqual({
      "task[f][title]": "a",
      "task[page]": "3",
      "task[sort]": "title",
    })
    const total = (await tasks.range.innerText()).split(" of ")[1]

    await tasks.reads(() => tasks.pageSize.selectOption("10"))

    expect(params(page)).toEqual({
      "task[f][title]": "a",
      "task[per]": "10",
      "task[sort]": "title",
    })
    await expect(tasks.range).toHaveText(`1–10 of ${total}`)
    await expect(tasks.pageButton(1)).toHaveAttribute("aria-current", "page")
    await expect(tasks.header("title")).toHaveAttribute("aria-sort", "ascending")
    await expect(tasks.filterValue("title")).toHaveValue("a")
  })

  test("the size is in the URL: a reload, the back button and the forward button show it", async ({
    page,
    tasks,
  }) => {
    await tasks.reads(() => tasks.pageSize.selectOption("50"))
    await tasks.reads(() => tasks.pageSize.selectOption("10"))
    await tasks.reads(() => tasks.next.click())
    expect(params(page)).toEqual({ "task[page]": "2", "task[per]": "10" })
    const keys = await tasks.rowKeys()

    await tasks.reads(() => page.goBack())
    await expect(tasks.range).toHaveText(`1–10 of ${SEED.tasks.acme}`)
    await expect(tasks.pageSize).toHaveValue("10")

    await tasks.reads(() => page.goBack())
    await expect(tasks.rows).toHaveCount(50)
    await expect(tasks.pageSize).toHaveValue("50")
    expect(params(page)).toEqual({ "task[per]": "50" })

    await tasks.reads(() => page.goBack())
    await expect(tasks.rows).toHaveCount(25)
    await expect(tasks.pageSize).toHaveValue("25")
    expect(params(page)).toEqual({})

    await tasks.reads(() => page.goForward())
    await expect(tasks.rows).toHaveCount(50)
    await expect(tasks.pageSize).toHaveValue("50")
    await tasks.reads(() => page.goForward())
    await tasks.reads(() => page.goForward())
    expect(params(page)).toEqual({ "task[page]": "2", "task[per]": "10" })

    await page.reload()
    await tasks.ready()
    await expect(tasks.rows).toHaveCount(10)
    await expect(tasks.range).toHaveText(`11–20 of ${SEED.tasks.acme}`)
    await expect(tasks.pageSize).toHaveValue("10")
    expect(await tasks.rowKeys()).toEqual(keys)
  })

  test("a size in the URL that the table does not offer is ignored", async ({ tasks }) => {
    // 100 is what the read action itself would allow
    for (const claim of ["100", "1000", "0", "all"]) {
      await tasks.open(`/tasks?task[per]=${claim}`)

      await expect(tasks.rows, claim).toHaveCount(25)
      await expect(tasks.range, claim).toHaveText(`1–25 of ${SEED.tasks.acme}`)
      await expect(tasks.pageSize, claim).toHaveValue("25")
    }
  })

  test("the scrollbar at the bottom of the window follows a longer page", async ({ tasks }) => {
    await tasks.reads(() => tasks.pageSize.selectOption("50"))

    // the table is longer than the window now, and scrolls sideways as before
    await expect(tasks.scrollbar).toBeVisible()
    const { seen, all } = await tasks.area()
    expect(all).toBeGreaterThan(seen)
  })
})

test.describe("/comments, by keyset", () => {
  let comments: Table

  test.beforeEach(async ({ page }) => {
    comments = new Table(page, "comment", "/comments")
    await comments.open()
  })

  test("a new size starts at the first page, and gives up the cursor", async ({ page }) => {
    await expect(comments.pageSize.locator("option")).toHaveText(["10", "20", "50"])
    await expect(comments.pageSize).toHaveValue("20")
    const first = await comments.rowKeys()
    expect(first).toHaveLength(20)

    await comments.reads(() => comments.pageSize.selectOption("10"))

    expect(await comments.rowKeys()).toEqual(first.slice(0, 10))
    await expect(comments.range).toHaveText(`${SEED.comments.acme} records`)
    expect(params(page)).toEqual({ "comment[per]": "10" })

    await comments.reads(() => comments.next.click())

    expect(await comments.rowKeys()).toEqual(first.slice(10, 20))
    expect(Object.keys(params(page)).sort()).toEqual(["comment[after]", "comment[per]"])

    await comments.reads(() => comments.pageSize.selectOption("50"))

    await expect(comments.rows).toHaveCount(50)
    expect((await comments.rowKeys()).slice(0, 20)).toEqual(first)
    expect(params(page)).toEqual({ "comment[per]": "50" })
    await expect(comments.previous).toBeDisabled()
  })
})

test.describe("tables that keep their state themselves", () => {
  test("a nested table: the menu is a Tab stop after its Next, and the choice is not in the URL", async ({
    page,
  }) => {
    const projects = new Table(page, "project", "/projects")
    await projects.open()
    // the projects declare no sizes
    await expect(projects.pageSize).toHaveCount(0)

    const nested = await projects.openLine(MOBILE_APP, "tasks")
    await expect(nested.range).toHaveText("1–25 of 57")
    await expect(nested.pageSize).toHaveAccessibleName("Rows per page")
    await expect(nested.pageSize).toHaveValue("25")

    // a stop of its own, after the nested table's Next
    await nested.next.focus()
    await projects.press("Tab")
    await expect(nested.pageSize).toBeFocused()

    // the arrow keys are the menu's own (a <select>), not the table's
    await nested.reads(() => projects.press("ArrowDown"))

    await expect(nested.pageSize).toHaveValue("50")
    await expect(nested.rows).toHaveCount(50)
    await expect(nested.range).toHaveText("1–50 of 57")
    await expect(nested.pageSize).toBeFocused()
    expect(params(page)).toEqual({})

    // and with the mouse
    await nested.reads(() => nested.pageSize.selectOption("10"))

    await expect(nested.rows).toHaveCount(10)
    await expect(nested.range).toHaveText("1–10 of 57")
    await expect(projects.range, "the projects around it are as they were").toHaveText("1–6 of 6")
  })

  test("the tables of the dashboard: each its own, and nothing in the URL", async ({ page }) => {
    const projects = new Table(page, "dashboard-projects", "/dashboard")
    const tasks = new Table(page, "dashboard-tasks", "/dashboard")
    await projects.open()
    await tasks.ready()

    await expect(projects.pageSize).toHaveCount(0)
    await tasks.reads(() => tasks.pageSize.selectOption("10"))

    await expect(tasks.rows).toHaveCount(10)
    await expect(tasks.range).toHaveText(`1–10 of ${SEED.tasks.acme}`)
    expect(params(page)).toEqual({})
  })
})

for (const theme of ["light", "dark"] as const) {
  test.describe(`axe, in the ${theme} theme`, () => {
    test.beforeEach(async ({ page }) => {
      await page.addInitScript((theme) => localStorage.setItem("phx:theme", theme), theme)
    })

    test("a table with the menu, and the menu with the focus", async ({ page, tasks }) => {
      await tasks.open()
      await expect(page.locator("html")).toHaveAttribute("data-theme", theme)
      await tasks.reads(() => tasks.pageSize.selectOption("10"))
      await tasks.pageSize.focus()

      await expectNoAxeViolations(page)
    })

    test("a nested table with the menu", async ({ page }) => {
      const projects = new Table(page, "project", "/projects")
      await projects.open()
      await expect(page.locator("html")).toHaveAttribute("data-theme", theme)
      const nested = await projects.openLine(MOBILE_APP, "tasks")
      await nested.reads(() => nested.pageSize.selectOption("10"))

      await expectNoAxeViolations(page)
    })
  })
}
