import { expectNoAxeViolations } from "./support/a11y"
import { SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { Table } from "./support/table"

// The table's keyboard model (docs/architecture/tab-model-design.md,
// sections 2 and 3; ADR 0003): a table is a table, and every control in it
// is a Tab stop of its own, in the order it stands in the page: the heading
// line, the selection line, "Skip table", the header's box and sort
// buttons, the filters, each row left to right (its box, its expander, its
// editable cells, the "Show all" of a cell that cuts its text off, its
// actions), the lines under an expanded row with their nested tables in
// place, the pagination. A read-only cell is no stop, nor is a header that
// does not sort. A nested table is a table like any other, further down the
// page: nothing goes "into" or "out of" it. The table moves focus on no key
// of its own: Tab is the browser's.
//
// /tasks as the admin: 25 rows of tasks, newest first.

const FIRST = SEED.task.first
const SECOND = SEED.task.second

/**
 * A walk as a person sees it: a date or a datetime input is one control of
 * several parts, each a stop of the browser's, so the same id comes again
 * at once for each part.
 */
const controls = (ids: string[]) => ids.filter((id, at) => id !== ids[at - 1])

/** The sortable columns of /tasks, left to right: each header holds a sort button. */
const SORTED = [
  "title",
  "status",
  "priority",
  "progress",
  "estimate_hours",
  "billable?",
  "due_on",
  "completed_at",
  "overdue?",
  "comment_count",
  "due_within?",
  "due_within",
  "external_ref",
  "inserted_at",
]

/** The controls of the filter row of /tasks, left to right. */
const FILTERS = [
  "title-operator",
  "title-value",
  "status-operator",
  "status-value",
  "priority-operator",
  "priority-value",
  "progress-operator",
  "progress-value",
  "estimate_hours-operator",
  "estimate_hours-value",
  "billable?-value",
  "due_on-operator",
  "due_on-value",
  "completed_at-operator",
  "completed_at-value",
  "overdue?-value",
  "comment_count-operator",
  "comment_count-value",
  "due_within?-value",
  "due_within-value",
  "external_ref-operator",
  "external_ref-value",
  "inserted_at-operator",
  "inserted_at-value",
]

/** The columns of /tasks the admin edits, left to right: each of their cells is a stop. */
const EDITABLE = [
  "title",
  "status",
  "priority",
  "progress",
  "estimate_hours",
  "billable?",
  "due_on",
  "completed_at",
  "description",
  "tags",
  "checks",
  "recurrence",
  "project",
  "assignee",
]

/** The columns of /tasks that are read-only, for the admin too: no cell of theirs is a stop. */
const READ_ONLY = ["headline", "overdue?", "comment_count", "due_within?", "due_within", "external_ref", "inserted_at", "reporter"]

const ACTIONS = ["archive", "reassign", "set_progress", "destroy", "set_labels"]

/**
 * What the stops of a row of /tasks are, as the admin has them: the box, the
 * expander, each editable cell and, after a cell that cuts its text off,
 * its "Show all" (in `cut`, by column), the action buttons.
 */
function expectedRowStops(table: Table, key: string, cut: string[]): string[] {
  const row = `${table.id}-row-${key}`
  return [
    `${row}-s>input`,
    `${row}-e>button`,
    ...[...EDITABLE.slice(0, 8), "headline", ...EDITABLE.slice(8)].flatMap((column) => [
      ...(column !== "headline" ? [`${row}-c-${column}`] : []),
      ...(cut.includes(column) ? [`${row}-c-${column}>button`] : []),
    ]),
    ...ACTIONS.map((action) => `${row}-a-${action}`),
  ]
}

test.describe("the Tab order of /tasks", () => {
  test.beforeEach(async ({ tasks }) => {
    await tasks.open()
  })

  test("the heading line, Skip table, the header's sort buttons, the filters, then each row left to right; nothing is sent", async ({
    tasks,
    pushed,
  }) => {
    // the first row cuts its description off: its "Show all" is a stop after the cell
    await expect(tasks.whole(tasks.cell(FIRST, "description"))).toBeAttached()
    await expect(tasks.whole(tasks.cell(SECOND, "description"))).toHaveCount(0)
    await pushed.clear()

    await tasks.columnsButton.focus()
    const head = [
      // the heading line: the argument line's inputs, then create
      "task-arg-search",
      "task-arg-due_within-days",
      "task-create",
      // where nothing is selected, no selection line; then the skip link
      "task-skip",
      // the header row: the box of the page, then a sort button per column that sorts
      "task-select-head>input",
      ...SORTED.map((column) => `task-sort-${column}`),
      // the filter row: per filter its operator menu and its value
      ...FILTERS.map((control) => `task-filter-${control}`),
    ]
    const first = expectedRowStops(tasks, FIRST, ["description"])
    const second = expectedRowStops(tasks, SECOND, [])
    const all = [...head, ...first, ...second]
    // a date and a datetime filter are several stops of the browser's each
    expect(controls(await tasks.walk(all.length + 40)).slice(0, all.length)).toEqual(all)

    // Shift+Tab walks the same way back
    await tasks.box(SECOND).focus()
    expect(await tasks.walk(first.length, true)).toEqual([...first].reverse())
    // a Tab walk says nothing to the server
    expect(await pushed.all()).toEqual([])
  })

  test("no read-only cell and no header that does not sort is a stop; the label column's cells are row headers", async ({
    tasks,
  }) => {
    for (const column of READ_ONLY) {
      await expect(tasks.cell(FIRST, column), column).not.toHaveAttribute("tabindex")
    }
    for (const column of EDITABLE) {
      await expect(tasks.cell(FIRST, column), column).toHaveAttribute("tabindex", "0")
    }
    for (const column of ["headline", "description", "tags", "checks", "recurrence", "project", "assignee", "reporter"]) {
      await expect(tasks.header(column).locator("button"), column).toHaveCount(0)
      await expect(tasks.header(column), column).not.toHaveAttribute("tabindex")
    }
    await expect(tasks.cell(FIRST, "title")).toHaveRole("rowheader")
    await expect(tasks.cell(FIRST, "status")).toHaveRole("cell")
    await expect(tasks.grid).toHaveRole("table")
    // nothing in the table says it is a grid, selected, read-only or invalid
    await expect(
      tasks.root.locator("[aria-selected], [aria-readonly], [role=cell][aria-invalid]"),
    ).toHaveCount(0)
  })

  test("a click on an editable cell gives it focus; a click on a read-only one gives focus to no cell", async ({
    tasks,
    pushed,
  }) => {
    await pushed.clear()
    await tasks.cell(SECOND, "status").click()
    await expect(tasks.cell(SECOND, "status")).toBeFocused()
    await tasks.cell(SECOND, "headline").click()
    await expect(tasks.cell(SECOND, "headline")).not.toBeFocused()
    expect(await tasks.focused()).not.toMatch(/-c-/)
    await expect(tasks.openEditors).toHaveCount(0)
    expect(await pushed.besides("select")).toEqual([])
  })

  test("the last row, then the footer, which has no stops, then the pagination", async ({ tasks }) => {
    const last = (await tasks.rowKeys()).at(-1)!
    await tasks.action(last, "set_labels").focus()
    // "Previous" is disabled on the first page
    expect(await tasks.walk(6)).toEqual([
      "task-page-1",
      "task-page-2",
      "task-page-3",
      "task-page-13",
      "task-next",
      "task-page-size",
    ])
  })

  test("the selection line comes after the heading line and before Skip table, while rows are selected", async ({
    page,
    tasks,
  }) => {
    await tasks.box(FIRST).focus()
    await page.keyboard.press("Space")
    await expect(tasks.selectionLine).toBeVisible()
    await tasks.create.focus()
    // "Clear selection", two of the actions on the selection and the menu "More" of the others
    expect(await tasks.walk(5)).toEqual([
      "task-clear-selection",
      "task-bulk-archive",
      "task-bulk-reassign",
      "task-bulk-more-button",
      "task-skip",
    ])
  })

})

test.describe("for the viewer, who may change nothing", () => {
  test.use({ actor: "viewer" })

  test("a row's only stops are its expander and the buttons of the texts it cuts off", async ({ tasks }) => {
    await tasks.open()
    await expect(tasks.whole(tasks.cell(FIRST, "description"))).toBeAttached()
    await expect(tasks.box(FIRST)).toHaveCount(0)
    // no cell is a stop: the viewer edits none
    await expect(tasks.row(FIRST).locator("[tabindex]")).toHaveCount(0)
    await tasks.expander(FIRST).focus()
    expect(await tasks.walk(2)).toEqual([`task-row-${FIRST}-c-description>button`, `task-row-${SECOND}-e>button`])
  })
})

test.describe("nested tables in the Tab order", () => {
  test.beforeEach(async ({ tasks }) => {
    await tasks.open()
  })

  test("into a nested table two levels deep and back out, after the line's button, then the parent's next line and row", async ({
    tasks,
  }) => {
    const comments = await tasks.openLine(FIRST, "comments")
    const comment = await comments.rowKey(1)
    const author = await comments.openLine(comment, "author")
    const people = await author.rowKeys()

    const c = comments.id
    const a = author.id
    await tasks.action(FIRST, "set_labels").focus()
    const walked = controls(await tasks.walk(80))
    const path = [
      // the task's lines: its first, open, then its nested table in place
      `task-row-${FIRST}-l-comments-b`,
      `${c}-columns-button`,
      `${c}-create`,
      `${c}-skip`,
      `${c}-select-head>input`,
    ]
    expect(walked.slice(0, path.length)).toEqual(path)

    // the comment's row, its lines, the second level in place under its open line
    const row = walked.indexOf(`${c}-row-${comment}-s>input`)
    expect(row, "the first comment's box").toBeGreaterThan(path.length)
    const authorLine = walked.indexOf(`${c}-row-${comment}-l-author-b`)
    expect(authorLine).toBeGreaterThan(row)
    expect(walked[authorLine + 1], "the second level's heading line, after its line's button").toBe(`${a}-columns-button`)
    expect(walked.indexOf(`${a}-skip`)).toBeGreaterThan(authorLine)
    expect(people.length, "the comment's author").toBe(1)

    // out of the second level to the comment's next line or row, out of
    // the first to the task's next line, then the next task's box
    const outOfComments = walked.indexOf(`task-row-${FIRST}-l-first_comment-b`)
    expect(outOfComments, "the task's next line").toBeGreaterThan(authorLine)
    expect(walked.slice(outOfComments, outOfComments + 6)).toEqual([
      `task-row-${FIRST}-l-first_comment-b`,
      `task-row-${FIRST}-l-latest_comment-b`,
      `task-row-${FIRST}-l-labels-b`,
      `task-row-${FIRST}-l-project-b`,
      `task-row-${FIRST}-l-assignee-b`,
      `task-row-${FIRST}-l-reporter-b`,
    ])
    expect(walked[outOfComments + 6]).toBe(`task-row-${SECOND}-s>input`)
    // every stop of the second level comes before the first level's end
    const lastOfAuthor = walked.findLastIndex((id) => id.startsWith(`${a}-`))
    expect(lastOfAuthor).toBeLessThan(outOfComments)
    expect(lastOfAuthor).toBeGreaterThan(authorLine)

    // and back with Shift+Tab: from the task's next line into the end of the comments
    await tasks.line(FIRST, "first_comment").focus()
    const back = controls(await tasks.walk(1, true))
    expect(back[0].startsWith(`${c}-`), "the last stop of the comments").toBe(true)
  })

  test("several nested tables open at once: each in its own place, one after the other in page order", async ({
    tasks,
  }) => {
    const comments = await tasks.openLine(FIRST, "comments")
    const reporter = await tasks.openLine(FIRST, "reporter")
    const other = await tasks.openLine(SECOND, "comments")

    await tasks.line(FIRST, "comments").focus()
    const walked = controls(await tasks.walk(160))
    const at = (id: string) => {
      const index = walked.indexOf(id)
      expect(index, id).toBeGreaterThanOrEqual(0)
      return index
    }
    // the first row's comments, then its next lines, then its reporter's
    // table, then the next row and the comments under it
    const order = [
      at(`${comments.id}-skip`),
      at(`task-row-${FIRST}-l-first_comment-b`),
      at(`task-row-${FIRST}-l-reporter-b`),
      at(`${reporter.id}-skip`),
      at(`task-row-${SECOND}-s>input`),
      at(`task-row-${SECOND}-l-comments-b`),
      at(`${other.id}-skip`),
    ]
    expect([...order].sort((x, y) => x - y)).toEqual(order)
    // no stop of one nested table stands among another's
    const of = (table: Table) => walked.map((id, index) => (id.startsWith(`${table.id}-`) ? index : -1)).filter((index) => index >= 0)
    const spans = [comments, reporter, other].map(of).map((indexes) => [indexes[0], indexes.at(-1)!])
    for (const [i, [start, end]] of spans.entries()) {
      for (const [j, [otherStart]] of spans.entries()) {
        if (i !== j) expect(otherStart < start || otherStart > end, `${i} and ${j} do not interleave`).toBe(true)
      }
    }
  })
})

test.describe("Skip table", () => {
  test.beforeEach(async ({ tasks }) => {
    await tasks.open()
  })

  test("is hidden until it has focus; Enter jumps past the table, after its pagination", async ({ page, tasks }) => {
    await expect(tasks.skip).toHaveText("Skip table Tasks")
    await expect(tasks.skip).toHaveAttribute("href", "#task-end")
    expect((await tasks.skip.boundingBox())?.width ?? 0, "out of sight").toBeLessThanOrEqual(1)
    await tasks.skip.focus()
    await expect(tasks.skip).toBeVisible()
    expect((await tasks.skip.boundingBox())!.width).toBeGreaterThan(1)

    await page.keyboard.press("Enter")
    await expect(tasks.skipTarget).toBeFocused()
    // the target stands right after the pagination: Shift+Tab is its last control
    expect(await tasks.walk(1, true)).toEqual(["task-page-size"])
    await tasks.skip.focus()
    await page.keyboard.press("Enter")
    await expect(tasks.skipTarget).toBeFocused()
    // and Tab goes on past the table
    await page.keyboard.press("Tab")
    expect(await tasks.root.evaluate((root) => root.contains(document.activeElement))).toBe(false)
  })

  test("of a nested table skips that table only: the next Tab is the parent row's next line", async ({ page, tasks }) => {
    const comments = await tasks.openLine(FIRST, "comments")
    await expect(comments.skip).toHaveText("Skip table Comments")
    await comments.skip.focus()
    await page.keyboard.press("Enter")
    await expect(comments.skipTarget).toBeFocused()
    // after the nested table's pagination and its link to the full view
    expect(await tasks.walk(1, true)).toEqual([`${comments.id}-full-view`])
    await comments.skip.focus()
    await page.keyboard.press("Enter")
    expect(await tasks.walk(1)).toEqual([`task-row-${FIRST}-l-first_comment-b`])

    // the table around it skips it with everything nested in it
    await tasks.skip.focus()
    await page.keyboard.press("Enter")
    await expect(tasks.skipTarget).toBeFocused()
  })

  test("of the picker's table skips that table only: the next Tab is the picker's own buttons", async ({ page, tasks }) => {
    await tasks.cell(FIRST, "project").focus()
    await page.keyboard.press("Enter")
    await expect(tasks.picker).toBeVisible()
    const picked = tasks.pickerTable("project")
    await picked.loaded()
    await expect(picked.skip).toHaveText("Skip table Projects")
    await picked.skip.focus()
    await page.keyboard.press("Enter")
    await expect(picked.skipTarget).toBeFocused()
    await page.keyboard.press("Tab")
    const focus = await page.evaluate(() => document.activeElement!.id)
    expect(await tasks.picker.evaluate((picker) => picker.contains(document.activeElement))).toBe(true)
    expect(await picked.root.evaluate((root) => root.contains(document.activeElement)), focus).toBe(false)
    await page.keyboard.press("Escape")
    await expect(tasks.picker).toHaveCount(0)
    await expect(tasks.cell(FIRST, "project")).toBeFocused()
  })
})

test.describe("the header before the rows", () => {
  test("after a create at the top: Tab reaches the sort buttons and the filters before the new row", async ({
    page,
    tasks,
  }) => {
    await tasks.open()
    await tasks.create.click()
    await expect(tasks.field("title")).toBeFocused()
    await page.keyboard.type("Made for the Tab order")
    await tasks.chooseField("project_id", SEED.project.mobileApp)
    await tasks.panelSubmit.click()
    await expect(tasks.panel).toHaveCount(0)
    await expect(tasks.rows).toHaveCount(26)
    const created = await tasks.rowKey(1)
    await expect(tasks.cell(created, "title")).toHaveText("Made for the Tab order")

    // the header stands before every record's row group in the page
    expect(
      await tasks.grid.evaluate((table) => {
        const head = table.querySelector(":scope > [id='task-head']")!
        return Array.from(table.querySelectorAll(":scope > [role=rowgroup]")).every(
          (group) => group === head || head.compareDocumentPosition(group) & Node.DOCUMENT_POSITION_FOLLOWING,
        )
      }),
    ).toBe(true)
    await tasks.filterOperator("inserted_at").focus()
    // past the parts of the datetime filter's value, the new row's box and expander
    expect(controls(await tasks.walk(12)).slice(0, 3)).toEqual([
      "task-filter-inserted_at-value",
      `task-row-${created}-s>input`,
      `task-row-${created}-e>button`,
    ])
    await tasks.skip.focus()
    expect(await tasks.walk(2)).toEqual(["task-select-head>input", "task-sort-title"])
  })
})

test.describe("focus after the rows change", () => {
  test.beforeEach(async ({ tasks }) => {
    await tasks.open()
  })

  test("a sort keeps focus on its button", async ({ page, tasks }) => {
    await tasks.sortButton("title").focus()
    await tasks.reads(() => page.keyboard.press("Enter"))
    await expect(tasks.header("title")).toHaveAttribute("aria-sort", "ascending")
    await expect(tasks.sortButton("title")).toBeFocused()
  })

  test("a stop that is still there when the rows are replaced keeps focus, and else the same stop of the row at the same place has it", async ({
    page,
    tasks,
  }) => {
    const unsorted = await tasks.rowKeys()
    await tasks.sortBy("progress")
    const sorted = await tasks.rowKeys()
    const kept = sorted.find((key) => unsorted.includes(key))!
    const gone = sorted.findIndex((key) => !unsorted.includes(key))
    expect(kept, "a row on both pages").toBeDefined()
    expect(gone, "a row on the sorted page only").toBeGreaterThan(-1)

    // the back button undoes the sort: the row is on the page again, elsewhere
    await tasks.cell(kept, "progress").focus()
    await tasks.reads(() => page.goBack())
    expect(await tasks.rowKeys()).toEqual(unsorted)
    await expect(tasks.cell(kept, "progress")).toBeFocused()

    // the row is not on the page any more: the same stop of the row where it was
    await tasks.reads(() => page.goForward())
    await tasks.cell(sorted[gone], "priority").focus()
    await tasks.reads(() => page.goBack())
    await expect(tasks.cell(unsorted[gone], "priority")).toBeFocused()
  })

  test("a page change from inside the rows: the same stop of the row at the same place", async ({ page, tasks }) => {
    const pageOne = await tasks.rowKeys()
    await tasks.reads(() => tasks.next.click())
    await expect(tasks.range).toHaveText(`26–50 of ${SEED.tasks.acme}`)
    const pageTwo = await tasks.rowKeys()
    expect(pageTwo).not.toEqual(pageOne)

    // Focus into the rows without scrolling the window: the click on "Next"
    // scrolled it to the button, and LiveView puts the window back where
    // its first page was scrolled to as the back button returns to it (its
    // scroll restoration), which is where the window is then, whenever the
    // browser told LiveView of that scroll. A focus that scrolled the window
    // too would leave it elsewhere, so that what the table does to the
    // scroll could not be told from what LiveView does.
    await tasks.cell(pageTwo[4], "status").evaluate((cell) => (cell as HTMLElement).focus({ preventScroll: true }))
    await expect(tasks.cell(pageTwo[4], "status")).toBeFocused()
    const scrolled = await page.evaluate(() => window.scrollY)
    await tasks.reads(() => page.goBack())
    await expect(tasks.range).toHaveText(`1–25 of ${SEED.tasks.acme}`)
    await expect(tasks.cell(pageOne[4], "status")).toBeFocused()
    // the page did not scroll for it
    expect(await page.evaluate(() => window.scrollY)).toBe(scrolled)
  })
})

for (const theme of ["light", "dark"] as const) {
  test.describe(`axe, in the ${theme} theme`, () => {
    test.beforeEach(async ({ page }) => {
      await page.addInitScript((theme) => localStorage.setItem("phx:theme", theme), theme)
    })

    test("finds nothing wrong with /tasks with nested tables open, two levels deep, and focus on a stop of each", async ({
      page,
      tasks,
    }) => {
      await tasks.open()
      await expect(page.locator("html")).toHaveAttribute("data-theme", theme)
      const comments = await tasks.openLine(FIRST, "comments")
      await tasks.openLine(FIRST, "reporter")
      await tasks.openLine(SECOND, "comments")
      const comment = await comments.rowKey(1)
      const author = await comments.openLine(comment, "author")
      await expectNoAxeViolations(page)

      await comments.skip.focus()
      await expectNoAxeViolations(page)
      await author.skip.focus()
      await expectNoAxeViolations(page)
      await tasks.whole(tasks.cell(FIRST, "description")).focus()
      await expectNoAxeViolations(page)
    })
  })
}
