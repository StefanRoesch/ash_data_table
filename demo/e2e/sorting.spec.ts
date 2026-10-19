import { expect, test } from "./support/fixtures"
import { params } from "./support/url"

// Spec section 6.3: one column at a time; the button in a sortable header
// (a click, Enter or Space) cycles ascending, descending, none, and the
// header says which (`aria-sort`). A header that does not sort has no
// button and is no Tab stop. /tasks as the admin.

const numbers = (texts: string[]) => texts.map(Number)
const ascending = (values: number[]) => [...values].sort((a, b) => a - b)
const descending = (values: number[]) => [...values].sort((a, b) => b - a)

test.beforeEach(async ({ tasks }) => {
  await tasks.open()
})

test("a click on a header's sort button cycles ascending, descending, none", async ({ page, tasks }) => {
  const header = tasks.header("progress")
  const button = tasks.sortButton("progress")
  await expect(button).toHaveRole("button")
  await expect(button).toHaveAccessibleName("Progress")
  const unsorted = await tasks.rowKeys()
  await expect(header).toHaveAttribute("aria-sort", "none")

  await tasks.reads(() => button.click())
  await expect(header).toHaveAttribute("aria-sort", "ascending")
  expect(params(page)).toEqual({ "task[sort]": "progress" })
  const up = numbers(await tasks.columnTexts("progress"))
  expect(up).toEqual(ascending(up))
  expect(up.at(-1)).toBe(0)

  await tasks.reads(() => button.click())
  await expect(header).toHaveAttribute("aria-sort", "descending")
  expect(params(page)).toEqual({ "task[sort]": "-progress" })
  const down = numbers(await tasks.columnTexts("progress"))
  expect(down).toEqual(descending(down))
  expect(down[0]).toBe(100)

  await tasks.reads(() => button.click())
  await expect(header).toHaveAttribute("aria-sort", "none")
  expect(params(page)).toEqual({})
  expect(await tasks.rowKeys(), "the read action's own order again").toEqual(unsorted)
})

test("Enter or Space on a sort button cycles its sort, and focus stays on the button", async ({ page, tasks }) => {
  const header = tasks.header("title")
  const button = tasks.sortButton("title")
  await button.focus()

  await tasks.reads(() => tasks.press("Enter"))
  await expect(header).toHaveAttribute("aria-sort", "ascending")
  expect(params(page)).toEqual({ "task[sort]": "title" })
  await expect(button).toBeFocused()

  await tasks.reads(() => tasks.press(" "))
  await expect(header).toHaveAttribute("aria-sort", "descending")
  await expect(button).toBeFocused()

  await tasks.reads(() => tasks.press("Enter"))
  await expect(header).toHaveAttribute("aria-sort", "none")
  expect(params(page)).toEqual({})
  await expect(button).toBeFocused()
})

test("one column at a time: sorting by another column takes the first one's sort away", async ({
  page,
  tasks,
}) => {
  await tasks.sortBy("title")
  await tasks.sortBy("progress")

  await expect(tasks.header("title")).toHaveAttribute("aria-sort", "none")
  await expect(tasks.header("progress")).toHaveAttribute("aria-sort", "ascending")
  expect(params(page)).toEqual({ "task[sort]": "progress" })
  await expect(tasks.grid.locator('[aria-sort="ascending"], [aria-sort="descending"]')).toHaveCount(1)
})

test("without a sort the read action's order applies: newest first", async ({ tasks }) => {
  const inserted = await tasks.columnTexts("inserted_at")
  expect(inserted).toHaveLength(25)
  expect(inserted).toEqual([...inserted].sort().reverse())
})

test("an aggregate and a calculation sort like any column", async ({ tasks }) => {
  await tasks.sortBy("comment_count")
  await tasks.sortBy("comment_count")
  const comments = numbers(await tasks.columnTexts("comment_count"))
  expect(comments).toEqual(descending(comments))
  expect(comments[0]).toBeGreaterThan(comments.at(-1)!)

  // the overdue tasks last, then first
  await tasks.sortBy("overdue?")
  await expect(tasks.columnCells("overdue?").first()).toHaveText(/No/)
  await tasks.sortBy("overdue?")
  await expect(tasks.columnCells("overdue?").first()).toHaveText(/Yes/)
})

test("a column that cannot be sorted has no sort state, no button and no Tab stop; a click sends nothing", async ({
  page,
  tasks,
  pushed,
}) => {
  // `description` is declared `sortable? false`; `headline` is computed in Elixir
  for (const column of ["description", "headline"]) {
    const header = tasks.header(column)
    await expect(header).not.toHaveAttribute("aria-sort")
    await expect(tasks.sortButton(column)).toHaveCount(0)
    await expect(header.locator("button")).toHaveCount(0)
    await expect(header).not.toHaveAttribute("tabindex")

    await pushed.clear()
    await header.click()
    await expect(header).not.toBeFocused()
    expect(await pushed.all()).toEqual([])
    expect(params(page)).toEqual({})
  }

  // every other column says whether it is sorted, the two of the
  // calculation with arguments among them, and has its button
  await expect(tasks.grid.locator("[role=columnheader][aria-sort]")).toHaveCount(14)
  await expect(tasks.grid.locator("[role=columnheader][aria-sort] > button")).toHaveCount(14)
})

test("the sort is in the URL: a link and a reload show it", async ({ page, tasks }) => {
  await tasks.open("/tasks?task[sort]=-progress")
  await expect(tasks.header("progress")).toHaveAttribute("aria-sort", "descending")
  const sorted = await tasks.rowKeys()
  const progress = numbers(await tasks.columnTexts("progress"))
  expect(progress).toEqual(descending(progress))

  await page.reload()
  await tasks.ready()
  expect(await tasks.rowKeys()).toEqual(sorted)
  await expect(tasks.header("progress")).toHaveAttribute("aria-sort", "descending")
})

test("the back button goes back through the sorts", async ({ page, tasks }) => {
  const unsorted = await tasks.rowKeys()
  await tasks.sortBy("progress")
  const sorted = await tasks.rowKeys()
  await tasks.sortBy("title")
  await expect(tasks.header("title")).toHaveAttribute("aria-sort", "ascending")

  await tasks.reads(() => page.goBack())
  await expect(tasks.header("progress")).toHaveAttribute("aria-sort", "ascending")
  await expect(tasks.header("title")).toHaveAttribute("aria-sort", "none")
  expect(await tasks.rowKeys()).toEqual(sorted)

  await tasks.reads(() => page.goBack())
  await expect(tasks.header("progress")).toHaveAttribute("aria-sort", "none")
  expect(params(page)).toEqual({})
  expect(await tasks.rowKeys()).toEqual(unsorted)
})

test("a sort the URL asks for by a column that cannot be sorted is ignored", async ({ tasks }) => {
  const plain = await tasks.rowKeys()

  await tasks.open("/tasks?task[sort]=description")
  expect(await tasks.rowKeys()).toEqual(plain)
  await tasks.open("/tasks?task[sort]=no_such_column")
  expect(await tasks.rowKeys()).toEqual(plain)
})

test("a new sort starts at the first page", async ({ page, tasks }) => {
  await tasks.open("/tasks?task[page]=3")
  await expect(tasks.range).toHaveText("51–75 of 320")

  await tasks.sortBy("progress")
  await expect(tasks.range).toHaveText("1–25 of 320")
  expect(params(page)).toEqual({ "task[sort]": "progress" })
})
