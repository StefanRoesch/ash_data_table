import type { Browser, Page } from "@playwright/test"
import { expectNoAxeViolations } from "./support/a11y"
import { storageStateOf, type Actor } from "./support/actors"
import { SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { Table } from "./support/table"

// Live updates, in a browser. The tasks and the comments announce their
// changes, and every table of them follows.
//
// With two people: the admin, who is the test's own page, and the member
// in a second browser context, both on /tasks. What the admin changes
// shows on the member's page without a reload.
//
// And in one window: /named has two tables of the comments, and what is
// changed in the first shows in the second.

const NOTICE = "There are new or changed records."

/** A task of the first page that the member may change: it is assigned to them. */
const OWN = SEED.task.membersOwn
const FIRST = SEED.task.first

/** A second person with the same page open, in a browser context of their own. */
async function another(
  browser: Browser,
  page: Page,
  actor: Actor,
  theme?: "light" | "dark",
): Promise<{ page: Page; close: () => Promise<void> }> {
  const context = await browser.newContext({
    storageState: storageStateOf(actor),
    baseURL: new URL(page.url()).origin,
    viewport: page.viewportSize(),
  })
  const theirs = await context.newPage()
  if (theme) await theirs.addInitScript((chosen) => localStorage.setItem("phx:theme", chosen), theme)
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

const notice = (table: Table) => table.page.locator(`[id="${table.id}-notice"]`)
const readAgain = (table: Table) => table.page.locator(`[id="${table.id}-read-again"]`)

test.describe("an action panel in the page", () => {
  test("keeps its row as it is while a live update changes it, and the row follows once the panel is gone", async ({
    browser,
    page,
  }) => {
    const inline = new Table(page, "task", "/e2e/inline/tasks")
    await inline.open()
    const other = await another(browser, page, "admin")

    try {
      const theirs = new Table(other.page, "task", "/tasks")
      await theirs.open()
      const title = await inline.cell(OWN, "title").innerText()

      await inline.acts(OWN, () => inline.action(OWN, "reassign").click())
      await expect(inline.panel).toHaveAttribute("data-presentation", "inline")
      await expect.poll(() => page.evaluate(() => !!document.getElementById("task-panel")?.contains(document.activeElement))).toBe(true)

      await retype(theirs, OWN, "title", "Changed under the panel")
      await retype(theirs, FIRST, "title", "Changed beside the panel")

      // the row the panel is open for stays as it is; the other follows
      await expect(inline.cell(FIRST, "title")).toHaveText("Changed beside the panel")
      await expect(inline.cell(OWN, "title")).toHaveText(title)
      await expect(inline.panel).toBeVisible()

      await inline.panelCancel.click()
      await expect(inline.panel).toHaveCount(0)
      await expect(inline.cell(OWN, "title")).toHaveText("Changed under the panel")
    } finally {
      await other.close()
    }
  })
})

test.describe("two people on /tasks", () => {
  test("a row the admin changes is updated on the member's page, without a reload", async ({
    browser,
    page,
    tasks,
  }) => {
    await tasks.open()
    const other = await another(browser, page, "member")

    try {
      const theirs = new Table(other.page, "task", "/tasks")
      await theirs.open()
      const before = await theirs.rowKeys()

      await retype(tasks, FIRST, "title", "Renamed by the admin")

      await expect(theirs.cell(FIRST, "title")).toHaveText("Renamed by the admin")
      // in its place, and nothing else of the page has moved or is said
      expect(await theirs.rowKeys()).toEqual(before)
      await expect(notice(theirs)).toHaveCount(0)
      // the member still does not see what a field policy hides on this task
      await expect(theirs.cell(FIRST, "estimate_hours")).toHaveText("Not available")

      // and the admin is told nothing about their own change
      await expect(notice(tasks)).toHaveCount(0)
    } finally {
      await other.close()
    }
  })

  test("a cell the member is editing keeps what they typed, and shows the change once the editor is gone", async ({
    browser,
    page,
    tasks,
  }) => {
    await tasks.open()
    const other = await another(browser, page, "member")

    try {
      const theirs = new Table(other.page, "task", "/tasks")
      await theirs.open()

      const title = theirs.cell(OWN, "title")
      await title.focus()
      await theirs.press("Enter")
      const editor = theirs.editor(title)
      await expect(editor).toBeFocused()
      await theirs.retype("Half typed")

      // the admin changes the same cell, and another cell of the row
      await retype(tasks, OWN, "title", "Changed by the admin")
      await retype(tasks, OWN, "description", "Described by the admin")

      // the rest of the row follows; the editor is as the member left it
      await expect(theirs.cell(OWN, "description")).toHaveText("Described by the admin")
      await expect(editor).toBeFocused()
      await expect(editor).toHaveValue("Half typed")
      await expect(theirs.openEditors).toHaveCount(1)

      // given up: the cell shows what the admin saved
      await theirs.press("Escape")
      await expect(theirs.openEditors).toHaveCount(0)
      await expect(title).toHaveText("Changed by the admin")
      await expect(title).toBeFocused()
    } finally {
      await other.close()
    }
  })

  test("a nested table stays open and goes on following when its row is changed", async ({
    browser,
    page,
    tasks,
  }) => {
    await tasks.open()
    const other = await another(browser, page, "member")

    try {
      const theirs = new Table(other.page, "task", "/tasks")
      await theirs.open()
      await theirs.expand(FIRST)
      const comments = await theirs.openLine(FIRST, "comments")
      const comment = await comments.rowKey(1)

      // the admin changes the row the nested table is under
      await retype(tasks, FIRST, "title", "Renamed over an open table")
      await expect(theirs.cell(FIRST, "title")).toHaveText("Renamed over an open table")
      await expect(comments.rows).toHaveCount(1)

      // and then a comment in it, in the admin's own nested table
      await tasks.expand(FIRST)
      const own = await tasks.openLine(FIRST, "comments")
      await retype(own, comment, "body", "Edited under the renamed task")

      await expect(comments.cell(comment, "body")).toHaveText("Edited under the renamed task")
      await expect(theirs.cell(FIRST, "title")).toHaveText("Renamed over an open table")
    } finally {
      await other.close()
    }
  })

  /** The admin deletes a task: the button, and Confirm in the table's dialog. */
  async function destroy(table: Table, key: string): Promise<void> {
    await table.action(key, "destroy").click()
    await table.question.getByRole("button", { name: "Confirm" }).click()
    await expect(table.row(key)).toHaveCount(0)
  }

  test("a row that is deleted stays while the member edits a cell of it, and goes when they give up", async ({
    browser,
    page,
    tasks,
  }) => {
    await tasks.open()
    const other = await another(browser, page, "member")

    try {
      const theirs = new Table(other.page, "task", "/tasks")
      await theirs.open()
      const keys = await theirs.rowKeys()
      const after = keys[keys.indexOf(OWN) + 1]

      const title = theirs.cell(OWN, "title")
      await title.focus()
      await theirs.press("Enter")
      const editor = theirs.editor(title)
      await theirs.retype("Typed into a task that is going")

      // another row goes at once; the one with the editor stays
      await destroy(tasks, FIRST)
      await expect(theirs.row(FIRST)).toHaveCount(0)
      await destroy(tasks, OWN)
      await expect(theirs.row(SEED.task.second)).toHaveCount(1)
      await other.page.waitForTimeout(500)
      await expect(theirs.row(OWN)).toHaveCount(1)
      await expect(editor).toBeFocused()
      await expect(editor).toHaveValue("Typed into a task that is going")

      await theirs.press("Escape")
      await expect(theirs.row(OWN)).toHaveCount(0)
      // focus was on the row that went: it is on the same stop of the row after it
      await expect(theirs.cell(after, "title")).toBeFocused()
    } finally {
      await other.close()
    }
  })

  test("a row that is deleted while it has the focus takes it to the same stop of the row after it, else of the row before", async ({
    browser,
    page,
    tasks,
  }) => {
    await tasks.open()
    const other = await another(browser, page, "member")

    try {
      const theirs = new Table(other.page, "task", "/tasks")
      await theirs.open()
      const keys = await theirs.rowKeys()

      // a cell of the row: the same cell of the row after it
      await theirs.cell(OWN, "title").focus()
      await destroy(tasks, OWN)
      await expect(theirs.row(OWN)).toHaveCount(0)
      await expect(theirs.cell(keys[keys.indexOf(OWN) + 1], "title")).toBeFocused()

      // a row's box, in the last row of the page: the box of the row before it
      const last = keys.at(-1)!
      const before = keys.at(-2)!
      await theirs.box(last).focus()
      await destroy(tasks, last)
      await expect(theirs.row(last)).toHaveCount(0)
      await expect(theirs.box(before)).toBeFocused()
      // a row that went is not announced
      await expect(notice(theirs)).toHaveCount(0)
    } finally {
      await other.close()
    }
  })

  test("a save into a row that was deleted meanwhile says that the record is gone, and loses nothing silently", async ({
    browser,
    page,
    tasks,
  }) => {
    await tasks.open()
    const other = await another(browser, page, "member")

    try {
      const theirs = new Table(other.page, "task", "/tasks")
      await theirs.open()

      const title = theirs.cell(OWN, "title")
      await title.focus()
      await theirs.press("Enter")
      await theirs.retype("Typed into a task that is going")

      await destroy(tasks, OWN)
      await other.page.waitForTimeout(500)
      await expect(theirs.row(OWN)).toHaveCount(1)

      await theirs.press("Enter")
      await expect(title).toHaveAttribute("data-failed")
      await expect(theirs.failure(title)).toHaveText("This record is no longer available.")
      await expect(theirs.status).toContainText("This record is no longer available.")
      // the row stays for the answer to be read
      await expect(theirs.row(OWN)).toHaveCount(1)
    } finally {
      await other.close()
    }
  })

  for (const theme of ["light", "dark"] as const) {
    test(`a task the admin creates is announced to the member, who reads again (${theme} theme)`, async ({
      browser,
      page,
      tasks,
    }) => {
      await tasks.open()
      const other = await another(browser, page, "member", theme)

      try {
        const theirs = new Table(other.page, "task", "/tasks")
        await theirs.open()
        await expect(other.page.locator("html")).toHaveAttribute("data-theme", theme)
        const before = await theirs.rowKeys()

        await tasks.create.click()
        await tasks.field("title").fill("Made by the admin")
        await tasks.chooseField("project_id", SEED.project.mobileApp)
        await tasks.panelSubmit.click()
        await expect(tasks.panel).toHaveCount(0)
        const created = await tasks.rowKey(1)
        await expect(tasks.cell(created, "title")).toHaveText("Made by the admin")
        // the one who made it is told nothing
        await expect(notice(tasks)).toHaveCount(0)

        // no row is put into the member's page: it says that there is something
        await expect(notice(theirs)).toHaveText(new RegExp(`^\\s*${NOTICE.replace(".", "\\.")}\\s*Read again\\s*$`))
        await expect(theirs.status).toHaveText(NOTICE)
        await expect(theirs.status).toHaveAttribute("aria-live", "polite")
        await expect(readAgain(theirs)).toHaveRole("button")
        expect(await theirs.rowKeys()).toEqual(before)
        await expectNoAxeViolations(other.page)

        // by keyboard: the button is a Tab stop before the table
        await readAgain(theirs).focus()
        await theirs.reads(() => other.page.keyboard.press("Enter"))

        await expect(theirs.cell(created, "title")).toHaveText("Made by the admin")
        expect(await theirs.rowKey(1)).toBe(created)
        await expect(notice(theirs)).toHaveCount(0)
        // the button is gone, and focus is in the grid
        expect(await theirs.hasFocus()).toBe(true)
      } finally {
        await other.close()
      }
    })
  }
})

test.describe("two tables of the comments in one window (/named)", () => {
  test("what is changed in the first shows in the second", async ({ page }) => {
    const first = new Table(page, "comment", "/named")
    const second = new Table(page, "comment_compact", "/named")
    await first.open()
    await second.ready()

    await expect(page.locator("#named-live")).toContainText("Change a comment's text in the first table")

    // an edit: the same row of the second table follows
    const edited = await first.rowKey(1)
    await retype(first, edited, "body", "Edited in the first table")
    await expect(second.cell(edited, "body")).toHaveText("Edited in the first table")
    await expect(notice(second)).toHaveCount(0)
    await expect(notice(first)).toHaveCount(0)

    // a new comment: a row at the top of the first, a notice in the second
    const before = await second.rowKeys()
    await first.create.click()
    await first.field("body").fill("Created in the first table")
    await first.chooseField("task_id", FIRST)
    await first.panelSubmit.click()
    await expect(first.panel).toHaveCount(0)
    const created = await first.rowKey(1)
    await expect(first.cell(created, "body")).toHaveText("Created in the first table")
    await expect(notice(first)).toHaveCount(0)

    await expect(notice(second)).toContainText(NOTICE)
    await expect(second.status).toHaveText(NOTICE)
    expect(await second.rowKeys()).toEqual(before)
    await expectNoAxeViolations(page)

    await second.reads(() => readAgain(second).click())
    expect(await second.rowKey(1)).toBe(created)
    await expect(second.cell(created, "body")).toHaveText("Created in the first table")
    await expect(notice(second)).toHaveCount(0)

    // a delete: the row goes from both
    await first.action(created, "destroy").click()
    await first.question.getByRole("button", { name: "Confirm" }).click()
    await expect(first.row(created)).toHaveCount(0)
    await expect(second.row(created)).toHaveCount(0)
    await expect(second.cell(edited, "body")).toHaveText("Edited in the first table")
  })
})
