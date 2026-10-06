import { expect, test } from "./support/fixtures"
import { storageStateOf } from "./support/actors"
import { SEED } from "./support/data"
import { Table } from "./support/table"
import { params } from "./support/url"

// Spec sections 6.2 and 6.5: offset pages with numbers and a total, keyset
// pages with next and previous only, no pages at all; the page in the URL.

test.describe("offset pages: /tasks", () => {
  test.beforeEach(async ({ tasks }) => {
    await tasks.open()
  })

  test("the first page: the range with the total, the page numbers, no way back", async ({
    tasks,
  }) => {
    await expect(tasks.rows).toHaveCount(25)
    await expect(tasks.range).toHaveText(`1–25 of ${SEED.tasks.acme}`)
    await expect(tasks.previous).toBeDisabled()
    await expect(tasks.next).toBeEnabled()
    await expect(tasks.pageButton(1)).toHaveAttribute("aria-current", "page")
    await expect(tasks.pageButton(2)).not.toHaveAttribute("aria-current")
    await expect(tasks.pageButton(13), "the last page is offered").toBeVisible()

    // the rows are numbered with the two header rows counted
    await expect(tasks.grid).toHaveAttribute("aria-rowcount", String(SEED.tasks.acme + 2))
    await expect(tasks.rows.first().getByRole("row")).toHaveAttribute("aria-rowindex", "3")
  })

  test("Next, a page number and Previous change the rows, the range and the URL", async ({
    page,
    tasks,
  }) => {
    const first = await tasks.rowKeys()

    await tasks.reads(() => tasks.next.click())
    await expect(tasks.range).toHaveText("26–50 of 320")
    expect(params(page)).toEqual({ "task[page]": "2" })
    await expect(tasks.pageButton(2)).toHaveAttribute("aria-current", "page")
    await expect(tasks.previous).toBeEnabled()
    await expect(tasks.rows.first().getByRole("row")).toHaveAttribute("aria-rowindex", "28")
    const second = await tasks.rowKeys()
    expect(second).toHaveLength(25)
    expect(second.filter((key) => first.includes(key))).toEqual([])

    await tasks.reads(() => tasks.pageButton(13).click())
    await expect(tasks.range).toHaveText("301–320 of 320")
    await expect(tasks.rows).toHaveCount(20)
    await expect(tasks.next).toBeDisabled()
    expect(params(page)).toEqual({ "task[page]": "13" })

    await tasks.reads(() => tasks.previous.click())
    await expect(tasks.range).toHaveText("276–300 of 320")

    await tasks.reads(() => tasks.pageButton(1).click())
    expect(params(page), "the first page needs no parameter").toEqual({})
    expect(await tasks.rowKeys()).toEqual(first)
  })

  test("the pagination is outside the grid: ordinary tab stops, used by keyboard", async ({
    page,
    tasks,
  }) => {
    await tasks.tabStop.focus()
    await tasks.press("Tab")
    await expect(tasks.pageButton(1)).toBeFocused()
    await tasks.press("Tab")
    await expect(tasks.pageButton(2)).toBeFocused()

    await tasks.reads(() => tasks.press("Enter"))
    await expect(tasks.range).toHaveText("26–50 of 320")
    expect(params(page)).toEqual({ "task[page]": "2" })
    await expect(tasks.pageButton(2), "the button that was used keeps the focus").toBeFocused()
  })

  test("Next keeps the focus when it is used by keyboard", async ({ tasks }) => {
    test.fail(
      true,
      "DEFECT (library): on a table with page numbers, using Next or Previous drops focus to " +
        "<body> whenever the set of page-number buttons changes (page 1 to 2 adds the button " +
        "for page 4): the patch takes #task-next out of the DOM and puts it back. A keyboard " +
        "user has to Tab through the page again. Keyset tables, without numbers, keep it.",
    )

    await tasks.next.focus()
    await tasks.reads(() => tasks.press("Enter"))
    await expect(tasks.range).toHaveText("26–50 of 320")
    await expect(tasks.next).toBeFocused({ timeout: 1000 })
  })

  test("the page is in the URL: a link, a reload and the back button show it", async ({
    page,
    tasks,
    browser,
    actor,
  }) => {
    await tasks.reads(() => tasks.next.click())
    await tasks.reads(() => tasks.next.click())
    await expect(tasks.range).toHaveText("51–75 of 320")
    const third = await tasks.rowKeys()
    const link = page.url()

    await tasks.reads(() => page.goBack())
    await expect(tasks.range).toHaveText("26–50 of 320")
    await tasks.reads(() => page.goForward())
    expect(await tasks.rowKeys()).toEqual(third)

    await page.reload()
    await tasks.ready()
    await expect(tasks.range).toHaveText("51–75 of 320")
    expect(await tasks.rowKeys()).toEqual(third)

    // the link, opened by the same person in another window
    const context = await browser.newContext({
      storageState: storageStateOf(actor),
    })
    const shared = new Table(await context.newPage(), "task", "/tasks")
    await shared.open(link)
    await expect(shared.range).toHaveText("51–75 of 320")
    expect(await shared.rowKeys()).toEqual(third)
    await context.close()
  })

  test("sort and page are kept together", async ({ page, tasks }) => {
    await tasks.reads(() => tasks.header("progress").click())
    await tasks.reads(() => tasks.next.click())
    expect(params(page)).toEqual({ "task[sort]": "progress", "task[page]": "2" })
    await expect(tasks.header("progress")).toHaveAttribute("aria-sort", "ascending")
    await expect(tasks.range).toHaveText("26–50 of 320")
  })

  test("a page beyond the last has no records and a way back", async ({ tasks }) => {
    await tasks.open("/tasks?task[page]=99")
    await expect(tasks.rows).toHaveCount(0)
    await expect(tasks.empty).toHaveText("No records")
    await expect(tasks.range).toHaveText("Page 99")
    await expect(tasks.next).toBeDisabled()

    await tasks.reads(() => tasks.pageButton(13).click())
    await expect(tasks.range).toHaveText("301–320 of 320")
  })

  test("a page the URL asks for that is no page number shows the first page", async ({ tasks }) => {
    const first = await tasks.rowKeys()
    await tasks.open("/tasks?task[page]=abc")
    expect(await tasks.rowKeys()).toEqual(first)
    await tasks.open("/tasks?task[page]=-2")
    expect(await tasks.rowKeys()).toEqual(first)
  })
})

test.describe("offset pages of the action's own size: /projects", () => {
  test("everything on one page: neither Next nor Previous", async ({ page }) => {
    const projects = new Table(page, "project", "/projects")
    await projects.open()

    await expect(projects.rows).toHaveCount(SEED.projects.acme)
    await expect(projects.range).toHaveText("1–6 of 6")
    await expect(projects.previous).toBeDisabled()
    await expect(projects.next).toBeDisabled()
    await expect(projects.pagination.getByRole("button")).toHaveCount(3)
  })
})

test.describe("keyset pages: /comments", () => {
  let comments: Table

  test.beforeEach(async ({ page }) => {
    comments = new Table(page, "comment", "/comments")
    await comments.open()
  })

  test("next and previous only: no numbers, no total", async () => {
    await expect(comments.rows).toHaveCount(20)
    await expect(comments.pagination.getByRole("button")).toHaveText(["Previous", "Next"])
    await expect(comments.previous).toBeDisabled()
    await expect(comments.next).toBeEnabled()
    await expect(comments.range).toHaveText("")
    await expect(comments.grid, "the number of rows is not known").toHaveAttribute(
      "aria-rowcount",
      "-1",
    )
  })

  test("Next and Previous move through the records; the cursor is in the URL", async ({ page }) => {
    const first = await comments.rowKeys()

    await comments.reads(() => comments.next.click())
    const second = await comments.rowKeys()
    expect(second).toHaveLength(20)
    expect(second.filter((key) => first.includes(key))).toEqual([])
    expect(Object.keys(params(page))).toEqual(["comment[after]"])
    await expect(comments.previous).toBeEnabled()

    await comments.reads(() => comments.next.click())
    const third = await comments.rowKeys()
    expect(third.filter((key) => [...first, ...second].includes(key))).toEqual([])

    await comments.reads(() => comments.previous.click())
    expect(Object.keys(params(page))).toEqual(["comment[before]"])
    expect(await comments.rowKeys()).toEqual(second)

    await page.reload()
    await comments.ready()
    expect(await comments.rowKeys(), "a reload shows the same page").toEqual(second)
  })

  test("Next keeps the focus when it is used by keyboard", async () => {
    await comments.next.focus()
    await comments.reads(() => comments.press("Enter"))
    await expect(comments.next).toBeFocused()
  })

  test("the back button goes back through the pages", async ({ page }) => {
    const first = await comments.rowKeys()
    await comments.reads(() => comments.next.click())
    const second = await comments.rowKeys()
    await comments.reads(() => comments.next.click())

    await comments.reads(() => page.goBack())
    expect(await comments.rowKeys()).toEqual(second)
    await comments.reads(() => page.goBack())
    expect(await comments.rowKeys()).toEqual(first)
    expect(params(page)).toEqual({})
  })

  test("a cursor that is none says that the records could not be loaded", async () => {
    await comments.open("/comments?comment[after]=nonsense")
    await expect(comments.error).toHaveText("The records could not be loaded.")
    await expect(comments.rows).toHaveCount(0)
    await expect(comments.empty, "an error is not an empty table").toHaveCount(0)
  })
})

test.describe("no pages: /labels", () => {
  test("every record, and no pagination", async ({ page }) => {
    const labels = new Table(page, "label", "/labels")
    await labels.open()

    await expect(labels.rows).toHaveCount(SEED.labels.acme)
    await expect(labels.pagination).toHaveCount(0)
    await expect(labels.grid).toHaveAttribute("aria-rowcount", String(SEED.labels.acme + 2))
  })
})
