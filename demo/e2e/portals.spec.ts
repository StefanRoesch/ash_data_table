import type { Browser, Page } from "@playwright/test"
import { storageStateOf, type Actor } from "./support/actors"
import { SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { ownedSheets, Table } from "./support/table"

// Nested tables drawn by the table on the page and moved into their rows by
// LiveView's `<.portal>` (stage 5 of the refactor): the cell of a row of a
// stream is the portal's target, and the nested table has a stream of its
// own. Upstream has no test of that combination; these are ours.
//
// And every way a nested table leaves the page: each must close it in the
// render that takes its row or line away. A portal left without its target
// makes LiveView throw ("portal target … not found"), and every test fails
// on an error in the console (support/fixtures.ts).
//
// /tasks and /projects as the admin.

const FIRST = SEED.task.first
const MOBILE_APP = SEED.project.mobileApp

/** A second person with a page of their own, in a browser context of their own. */
async function another(browser: Browser, page: Page, actor: Actor): Promise<{ page: Page; close: () => Promise<void> }> {
  const context = await browser.newContext({
    storageState: storageStateOf(actor),
    baseURL: new URL(page.url()).origin,
    viewport: page.viewportSize(),
  })
  const theirs = await context.newPage()
  return { page: theirs, close: () => context.close() }
}

/** Changes a text cell as a person does: Enter, type over it, Enter. */
async function retype(table: Table, key: string, column: string, text: string): Promise<void> {
  const cell = table.cell(key, column)
  await cell.focus()
  await table.press("Enter")
  await expect(table.editor(cell)).toBeFocused()
  await table.retype(text)
  await table.saves(cell, () => table.press("Enter"))
  await expect(cell).toHaveText(text)
}

/** Deletes a row: the action's button, and Confirm in the table's dialog. */
async function destroy(table: Table, key: string): Promise<void> {
  await table.action(key, "destroy").click()
  await table.question.getByRole("button", { name: "Confirm" }).click()
  await expect(table.row(key)).toHaveCount(0)
}

/**
 * How many nested tables the page shows through portals, by the table's own
 * marker of each (`data-ash-data-table-portal`, which names the cell it goes
 * into), and how many of them are not in that cell.
 */
async function portals(page: Page): Promise<{ portals: number; loose: number }> {
  return page.evaluate(() => {
    const marked = Array.from(document.querySelectorAll<HTMLElement>("[data-ash-data-table-portal]"))
    return {
      portals: marked.length,
      loose: marked.filter(
        (marker) => marker.closest("td[data-nested]")?.id !== marker.dataset.ashDataTablePortal,
      ).length,
    }
  })
}

/** The first row of a table whose comments are not none, with its comments open. */
async function withComments(table: Table): Promise<{ key: string; comments: Table }> {
  for (const key of await table.rowKeys()) {
    const comments = await table.openLine(key, "comments")
    if ((await comments.rows.count()) > 0) return { key, comments }
    await table.line(key, "comments").click()
    await expect(comments.root).toHaveCount(0)
  }
  throw new Error(`no row of ${table.id} has comments`)
}

test.describe("the portal of a nested table", () => {
  test("is moved into the cell of its row, a row of the parent's stream, with its own stream inside", async ({
    page,
    tasks,
  }) => {
    await tasks.open()
    const comments = await tasks.openLine(FIRST, "comments")

    // the nested table is in its cell, in the element that marks its portal,
    // which is laid out in the cell, whatever the portal wraps it in
    const cell = tasks.nestedCell(FIRST, "comments")
    const marker = cell.locator(`[data-ash-data-table-portal="${await cell.getAttribute("id")}"]`)
    await expect(marker).toHaveCount(1)
    await expect(marker.locator(":scope > div > [data-read]")).toHaveAttribute("id", comments.id)
    const [inner, outer] = [(await marker.boundingBox())!, (await cell.boundingBox())!]
    expect(inner.x).toBeGreaterThanOrEqual(outer.x)
    expect(inner.y).toBeGreaterThanOrEqual(outer.y)
    expect(inner.y).toBeLessThan(outer.y + outer.height)
    expect(await portals(page)).toEqual({ portals: 1, loose: 0 })

    // its rows are its stream's: a sort reads them again, in their place
    await expect(comments.rows).not.toHaveCount(0)
    await comments.reads(() => comments.header("body").click())
    await expect(tasks.nestedCell(FIRST, "comments").locator(`[id="${comments.id}-grid"]`)).toHaveCount(1)
    await expect(comments.rows).not.toHaveCount(0)

    // closed: nothing of it is left
    await tasks.line(FIRST, "comments").click()
    await expect(comments.root).toHaveCount(0)
    expect(await portals(page)).toEqual({ portals: 0, loose: 0 })
  })

  test("goes three levels down, each table in the row of the one above it, and back up", async ({ page }) => {
    const projects = new Table(page, "project", "/projects")
    await projects.open()
    const tasks = await projects.openLine(MOBILE_APP, "tasks")
    const { key, comments } = await withComments(tasks)
    const comment = await comments.rowKey(1)
    const author = await comments.openLine(comment, "author")

    await expect(author.rows).toHaveCount(1)
    await expect(
      comments.nestedCell(comment, "author").locator(`[id="${author.id}-grid"]`),
    ).toHaveCount(1)
    await expect(tasks.nestedCell(key, "comments").locator(`[id="${comments.id}-grid"]`)).toHaveCount(1)
    expect(await portals(page)).toEqual({ portals: 3, loose: 0 })

    // closing the middle one closes the one under it as well
    await tasks.line(key, "comments").click()
    await expect(comments.root).toHaveCount(0)
    await expect(author.root).toHaveCount(0)
    expect(await portals(page)).toEqual({ portals: 1, loose: 0 })
  })

  test("a teleported grid's hook mounts once: one style sheet per grid, also when its row is put again", async ({
    browser,
    page,
    tasks,
  }) => {
    await tasks.open()
    const before = await ownedSheets(page)
    expect(before.sheets).toBe(before.grids)

    await tasks.openLine(FIRST, "comments")
    const opened = await ownedSheets(page)
    expect(opened.grids).toBe(before.grids + 1)
    expect(opened.sheets).toBe(opened.grids)

    // the row is put again by another person's change
    const other = await another(browser, page, "admin")
    try {
      const theirs = new Table(other.page, "task", "/tasks")
      await theirs.open()
      const title = await theirs.cell(FIRST, "title").textContent()
      await retype(theirs, FIRST, "title", "Put again")
      await expect(tasks.cell(FIRST, "title")).toHaveText("Put again")
      expect(await ownedSheets(page)).toEqual(opened)
      await retype(theirs, FIRST, "title", (title ?? "").trim())
    } finally {
      await other.close()
    }
  })
})

test.describe("a row put again under an open nested table", () => {
  test.use({ writes: true })

  test("keeps the tables three levels down, the focus in the deepest, and what is typed into a nested filter", async ({
    browser,
    page,
    tasks,
  }) => {
    await tasks.open()
    const project = await tasks.openLine(FIRST, "project")
    const [projectKey] = await project.rowKeys()
    const projectTasks = await project.openLine(projectKey, "tasks")
    const { key, comments } = await withComments(projectTasks)
    const deep = comments.cell(await comments.rowKey(1), "body")

    const other = await another(browser, page, "admin")
    try {
      const theirs = new Table(other.page, "task", "/tasks")
      await theirs.open()

      // focus three levels down: the row of the table on the page is put again
      await deep.focus()
      await retype(theirs, FIRST, "title", "Put again with focus below")
      await expect(tasks.cell(FIRST, "title")).toHaveText("Put again with focus below")
      await expect(deep).toBeFocused()
      await expect(projectTasks.nestedCell(key, "comments").locator(`[id="${comments.id}-grid"]`)).toHaveCount(1)
      expect(await portals(page)).toEqual({ portals: 3, loose: 0 })

      // text typed into the filter of a nested table, not yet sent
      await projectTasks.filterCell("title").focus()
      await tasks.press("Enter")
      await expect(projectTasks.filterValue("title")).toBeFocused()
      await page.keyboard.type("Half a filter")
      await retype(theirs, FIRST, "title", "Put again with a filter typed")
      await expect(tasks.cell(FIRST, "title")).toHaveText("Put again with a filter typed")
      await expect(projectTasks.filterValue("title")).toBeFocused()
      await expect(projectTasks.filterValue("title")).toHaveValue("Half a filter")
    } finally {
      await other.close()
    }
  })
})

test.describe("a nested table leaves with what takes its row or line away", () => {
  test.use({ writes: true })

  test("a live delete of its row", async ({ browser, page, tasks }) => {
    await tasks.open()
    const comments = await tasks.openLine(FIRST, "comments")
    await comments.cell(await comments.rowKey(1), "body").focus()

    const other = await another(browser, page, "admin")
    try {
      const theirs = new Table(other.page, "task", "/tasks")
      await theirs.open()
      await destroy(theirs, FIRST)
    } finally {
      await other.close()
    }

    await expect(tasks.row(FIRST)).toHaveCount(0)
    await expect(comments.root).toHaveCount(0)
    expect(await portals(page)).toEqual({ portals: 0, loose: 0 })
  })

  test("a page change", async ({ page, tasks }) => {
    await tasks.open()
    const comments = await tasks.openLine(FIRST, "comments")
    await tasks.reads(() => tasks.next.click())
    await expect(comments.root).toHaveCount(0)
    await expect(tasks.next).toBeFocused()
    expect(await portals(page)).toEqual({ portals: 0, loose: 0 })
  })

  test("a sort", async ({ page, tasks }) => {
    await tasks.open()
    const comments = await tasks.openLine(FIRST, "comments")
    await tasks.reads(() => tasks.header("title").click())
    await expect(comments.root).toHaveCount(0)
    expect(await portals(page)).toEqual({ portals: 0, loose: 0 })
  })

  test("a filter", async ({ page, tasks }) => {
    await tasks.open()
    const comments = await tasks.openLine(FIRST, "comments")
    await tasks.filterCell("title").focus()
    await tasks.press("Enter")
    await page.keyboard.type("a")
    await tasks.reads(() => tasks.press("Enter"))
    await expect(comments.root).toHaveCount(0)
    await expect(tasks.filterValue("title")).toBeFocused()
    expect(await portals(page)).toEqual({ portals: 0, loose: 0 })
  })

  test("another person asking: the tables under the rows close at once, and the rows are read again", async ({
    page,
  }) => {
    const tasks = new Table(page, "task", "/e2e/switch")
    await tasks.open()
    const comments = await tasks.openLine(FIRST, "comments")
    await expect(tasks.lineCreate(FIRST, "comments")).toBeVisible()

    await tasks.reads(() => page.locator("#become").click())
    await expect(comments.root).toHaveCount(0)
    await expect(tasks.expander(FIRST)).toHaveAttribute("aria-expanded", "false")
    expect(await portals(page)).toEqual({ portals: 0, loose: 0 })

    // opened again, it is the viewer's: they may write no comment
    const again = await tasks.openLine(FIRST, "comments")
    await expect(again.rows).not.toHaveCount(0)
    await expect(tasks.lineCreate(FIRST, "comments")).toHaveCount(0)
  })

  test("a live delete of a row two levels down, with the table under it open", async ({ browser, page }) => {
    const projects = new Table(page, "project", "/projects")
    await projects.open()
    const tasks = await projects.openLine(MOBILE_APP, "tasks")
    const { key, comments } = await withComments(tasks)
    const comment = await comments.rowKey(1)
    const author = await comments.openLine(comment, "author")
    await author.cell(await author.rowKey(1), "name").focus()

    const other = await another(browser, page, "admin")
    try {
      const theirProjects = new Table(other.page, "project", "/projects")
      await theirProjects.open()
      const theirTasks = await theirProjects.openLine(MOBILE_APP, "tasks")
      const theirComments = await theirTasks.openLine(key, "comments")
      await destroy(theirComments, comment)
    } finally {
      await other.close()
    }

    await expect(comments.row(comment)).toHaveCount(0)
    await expect(author.root).toHaveCount(0)
    await expect(comments.root).toHaveCount(1)
    expect(await portals(page)).toEqual({ portals: 2, loose: 0 })
  })
})

// A picker's table is an entry of the table it is opened from too, drawn in
// the picker's dialog, which needs no portal. It closes with the picker.
test.describe("the table of a picker leaves with its picker", () => {
  test.use({ writes: true })

  /** Opens the picker of a reference cell from the keyboard, and waits for its table. */
  async function openPicker(tasks: Table, key: string, column: string): Promise<Table> {
    await tasks.cell(key, column).focus()
    await tasks.press("Enter")
    await expect(tasks.picker).toBeVisible()
    const table = tasks.pickerTable(column)
    await table.ready()
    return table
  }

  test("by Cancel", async ({ tasks }) => {
    await tasks.open()
    const people = await openPicker(tasks, FIRST, "assignee")
    await tasks.pickerCancel.click()
    await expect(tasks.picker).toHaveCount(0)
    await expect(people.root).toHaveCount(0)
    await expect(tasks.cell(FIRST, "assignee")).toBeFocused()
  })

  test("by a choice", async ({ tasks }) => {
    await tasks.open()
    const people = await openPicker(tasks, FIRST, "assignee")
    // someone other than the one the cell points at
    let choice: string | null = null
    for (const key of await people.rowKeys()) {
      if (!(await people.radio(key).isChecked())) {
        choice = key
        break
      }
    }
    await people.radio(choice!).click()
    await tasks.saves(tasks.cell(FIRST, "assignee"), () => tasks.pickerChoose.click())
    await expect(tasks.picker).toHaveCount(0)
    await expect(people.root).toHaveCount(0)
  })

  test("by a new read of the table it is opened from, and in a nested table as well", async ({ page }) => {
    const projects = new Table(page, "project", "/projects")
    await projects.open()
    const tasks = await projects.openLine(MOBILE_APP, "tasks")
    const [key] = await tasks.rowKeys()
    const people = await openPicker(tasks, key, "assignee")
    await expect(tasks.picker).toBeVisible()

    // the nested table reads again (as a sort does): its rows are other
    // rows, and the picker goes with them
    await tasks.reads(() => tasks.forge("sort", { column: "title" }))
    await expect(tasks.picker).toHaveCount(0)
    await expect(people.root).toHaveCount(0)
    expect(await portals(page)).toEqual({ portals: 1, loose: 0 })
  })
})
