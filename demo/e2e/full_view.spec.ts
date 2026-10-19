import { expectNoAxeViolations } from "./support/a11y"
import { SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { switchLocale } from "./support/locale"
import { Table } from "./support/table"
import { params } from "./support/url"

// The full view of a nested table, in a browser: the link in the last row
// of a nested table's grid by pointer and by keyboard, the page it leads
// to (the destination's own table, limited to the records of the same row
// by the parameter `of`), the way back to all records, and the browser's
// back button.
//
// /tasks and /projects as the admin, unless a test says otherwise.

/** The first row of /tasks: a task of "Data warehouse" with one comment. */
const FIRST = SEED.task.first

/** Acme's "Mobile app": 57 tasks. */
const MOBILE_APP = SEED.project.mobileApp

const comments = (page: import("@playwright/test").Page) => new Table(page, "comment", "/comments")

test.describe("the link of a nested table", () => {
  test("with the pointer: opens the same records on the page of their own table, under a heading that says whose they are", async ({
    page,
    tasks,
  }) => {
    await tasks.open()
    const title = (await tasks.cell(FIRST, "title").textContent())!
    const nested = await tasks.openLine(FIRST, "comments")
    const bodies = await nested.columnTexts("body")
    expect(bodies.length).toBeGreaterThan(0)

    await expect(nested.fullView).toHaveText("Open in full view")
    await expect(nested.fullView).toHaveAccessibleName("Open in full view: Comments")
    // a live navigation: the page is not loaded afresh, and keeps what it held
    await page.evaluate(() => ((window as any).beforeFullView = true))
    await nested.fullView.click()

    const full = comments(page)
    await full.ready()
    expect(new URL(page.url()).pathname).toBe("/comments")
    expect(await page.evaluate(() => (window as any).beforeFullView)).toBe(true)
    expect(params(page)).toEqual({ "comment[of][task][comments]": FIRST })

    await expect(page.getByRole("heading", { level: 1 })).toHaveText("Comments")
    await expect(full.relatedHeading).toHaveText(`${title}: Comments`)
    await expect(full.relatedHeading).toHaveRole("heading")
    expect(await full.columnTexts("body")).toEqual(bodies)
    await expect(full.range).toHaveText(`${bodies.length} record${bodies.length === 1 ? "" : "s"}`)
    // a table of its own: its pages are a landmark after the grid, and it has no such link
    await expect(full.pagination).toHaveRole("navigation")
    await expect(full.fullView).toHaveCount(0)
  })

  test("with the keyboard: a link of its own, the nested table's last stop, just before where its \"Skip table\" goes; Enter follows it", async ({
    page,
    tasks,
  }) => {
    await tasks.open()
    const nested = await tasks.openLine(FIRST, "comments")

    // "Skip table Comments" jumps past the table: one stop back is the link
    await nested.skip.focus()
    await tasks.press("Enter")
    await expect(nested.skipTarget).toBeFocused()
    await tasks.press("Shift+Tab")
    await expect(nested.fullView).toBeFocused()
    // and Tab from it leaves the nested table for the next line of the row
    await tasks.press("Tab")
    expect(await nested.hasFocus()).toBe(false)
    await expect(tasks.line(FIRST, "first_comment")).toBeFocused()

    await nested.fullView.focus()
    await tasks.press("Enter")
    const full = comments(page)
    await full.ready()
    expect(params(page)).toEqual({ "comment[of][task][comments]": FIRST })
    await expect(full.relatedHeading).toContainText(": Comments")
  })

  test("is on the tables of every kind of relationship whose destination has a page, and on no other", async ({
    tasks,
  }) => {
    await tasks.open()

    for (const [relationship, path] of [
      ["latest_comment", "/comments"],
      ["labels", "/labels"],
      ["project", "/projects"],
    ] as const) {
      const nested = await tasks.openLine(FIRST, relationship)
      await expect(nested.fullView).toHaveAttribute("href", new RegExp(`^${path}\\?`))
    }

    // people have a table and no page
    const reporter = await tasks.openLine(FIRST, "reporter")
    await expect(reporter.rows).toHaveCount(1)
    await expect(reporter.fullView).toHaveCount(0)
    await expect(reporter.viewCell).toHaveCount(0)
  })

  test("is on a table nested in a table that a page of the demo's own holds", async ({ page }) => {
    const tasks = new Table(page, "dashboard-tasks", "/dashboard")
    await tasks.open()
    const key = await tasks.rowKey(1)
    const nested = await tasks.openLine(key, "comments")

    await nested.fullView.click()
    await comments(page).ready()
    expect(params(page)).toEqual({ "comment[of][task][comments]": key })
  })

  test("in German", async ({ page, tasks }) => {
    await tasks.open()
    await switchLocale(page, "de")
    await tasks.ready()
    const title = (await tasks.cell(FIRST, "title").textContent())!
    const nested = await tasks.openLine(FIRST, "comments")

    await expect(nested.fullView).toHaveText("In voller Ansicht öffnen")
    await expect(nested.fullView).toHaveAccessibleName("In voller Ansicht öffnen: Kommentare")
    await nested.fullView.click()

    const full = comments(page)
    await full.ready()
    await expect(full.relatedHeading).toHaveText(`${title}: Kommentare`)
    await expect(full.relatedClear).toHaveText("Alle Einträge anzeigen")
    await expectNoAxeViolations(page)
  })
})

test.describe("the page a link leads to", () => {
  test("sorts, filters and pages as any page does, with the limit in the address through all of it, and a reload shows it again", async ({
    page,
  }) => {
    const projects = new Table(page, "project", "/projects")
    await projects.open()
    const nested = await projects.openLine(MOBILE_APP, "tasks")
    await expect(nested.range).toHaveText("1–25 of 57")
    await nested.fullView.click()

    const tasks = new Table(page, "task", "/tasks")
    await tasks.ready()
    const limit = { "task[of][project][tasks]": MOBILE_APP }
    expect(params(page)).toEqual(limit)
    await expect(tasks.relatedHeading).toHaveText("Mobile app: Tasks")
    await expect(tasks.range).toHaveText("1–25 of 57")
    // every row is of that project
    expect(new Set(await tasks.columnTexts("project"))).toEqual(new Set(["Mobile app"]))

    await tasks.sortBy("title")
    expect(params(page)).toEqual({ ...limit, "task[sort]": "title" })
    await expect(tasks.header("title")).toHaveAttribute("aria-sort", "ascending")

    await tasks.reads(() => tasks.next.click())
    expect(params(page)).toEqual({ ...limit, "task[sort]": "title", "task[page]": "2" })
    await expect(tasks.range).toHaveText("26–50 of 57")
    const page2 = await tasks.columnTexts("title")

    await page.reload()
    await tasks.ready()
    await expect(tasks.relatedHeading).toHaveText("Mobile app: Tasks")
    await expect(tasks.range).toHaveText("26–50 of 57")
    expect(await tasks.columnTexts("title")).toEqual(page2)

    await tasks.filterValue("title").fill("Fix")
    await tasks.reads(() => tasks.filterValue("title").press("Enter"))
    expect(params(page)).toEqual({ ...limit, "task[sort]": "title", "task[f][title]": "Fix" })
    await expect(tasks.range).toHaveText("1–7 of 7")
    await expect(tasks.relatedHeading).toHaveText("Mobile app: Tasks")
  })

  test("names the parent as a link to the page of its own table, and has a way back to all records; both are ordinary tab stops", async ({
    page,
  }) => {
    const tasks = new Table(page, "task", "/tasks")
    await tasks.open(`/tasks?task[of][project][tasks]=${MOBILE_APP}&task[sort]=title`)
    await expect(tasks.range).toHaveText("1–25 of 57")

    await expect(tasks.relatedParent).toHaveRole("link")
    await expect(tasks.relatedParent).toHaveText("Mobile app")
    await expect(tasks.relatedParent).toHaveAttribute("href", "/projects")
    await expect(tasks.relatedClear).toHaveRole("link")
    await expect(tasks.relatedClear).toHaveText("Show all records")

    // from the table's "Skip table" backwards: "Show all records", the
    // create button before it on the same line (actions.spec.ts), the
    // parent; then the heading line above it: the two inputs of the
    // argument line (arguments.spec.ts) and "Columns" (hiding.spec.ts)
    await tasks.skip.focus()
    await page.keyboard.press("Shift+Tab")
    await expect(tasks.relatedClear).toBeFocused()
    await page.keyboard.press("Shift+Tab")
    await expect(tasks.create).toBeFocused()
    await page.keyboard.press("Shift+Tab")
    await expect(tasks.relatedParent).toBeFocused()
    await page.keyboard.press("Shift+Tab")
    await expect(tasks.argument("due_within-days")).toBeFocused()
    await page.keyboard.press("Shift+Tab")
    await expect(tasks.argument("search")).toBeFocused()
    await page.keyboard.press("Shift+Tab")
    await expect(tasks.columnsButton).toBeFocused()
    await tasks.relatedParent.focus()
    await page.keyboard.press("Tab")
    await page.keyboard.press("Tab")
    await expect(tasks.relatedClear).toBeFocused()

    // the way back takes the limit away, and the sort that was chosen under it
    await tasks.reads(() => page.keyboard.press("Enter"))
    expect(new URL(page.url()).pathname).toBe("/tasks")
    expect(params(page)).toEqual({})
    await expect(tasks.range).toHaveText("1–25 of 320")
    await expect(tasks.relatedHeading).toHaveCount(0)
    await expect(tasks.relatedClear).toHaveCount(0)
    await expect(tasks.header("title")).toHaveAttribute("aria-sort", "none")
  })

  test("is edited and expanded as any page: a cell saves, and a row opens its own nested tables with their own links", async ({
    page,
  }) => {
    const tasks = new Table(page, "task", "/tasks")
    await tasks.open(`/tasks?task[of][project][tasks]=${MOBILE_APP}`)
    const key = await tasks.rowKey(1)

    const nested = await tasks.openLine(key, "comments")
    await expect(nested.grid).toBeVisible()
    await expect(nested.fullView).toHaveAttribute("href", new RegExp(`comment\\[of\\]\\[task\\]\\[comments\\]=${key}`))
    await expectNoAxeViolations(page)
  })

  test.describe("saving", () => {
    test("a cell is saved under the limit, and the row keeps its reference cells", async ({ page }) => {
      const tasks = new Table(page, "task", "/tasks")
      await tasks.open(`/tasks?task[of][project][tasks]=${MOBILE_APP}`)
      const key = await tasks.rowKey(1)
      const cell = tasks.cell(key, "title")
      const reporter = await tasks.cell(key, "reporter").textContent()

      await cell.focus()
      await tasks.press("Enter")
      await tasks.retype("Renamed under the limit")
      await tasks.saves(cell, () => tasks.press("Enter"))

      await expect(cell).toHaveText("Renamed under the limit")
      await expect(cell).toBeFocused()
      await expect(tasks.cell(key, "project")).toHaveText("Mobile app")
      await expect(tasks.cell(key, "reporter")).toHaveText(reporter!)
      await expect(tasks.relatedHeading).toHaveText("Mobile app: Tasks")
    })
  })
})

test.describe("the back button", () => {
  test("returns to the page the link was on, with the state in its address; what was expanded there is closed", async ({
    page,
    tasks,
  }) => {
    await tasks.open("/tasks?task[sort]=title")
    const key = await tasks.rowKey(1)
    const nested = await tasks.openLine(key, "comments")
    await nested.fullView.click()
    const full = comments(page)
    await full.ready()
    await expect(full.relatedHeading).toBeVisible()

    await page.goBack()
    await tasks.ready()
    expect(new URL(page.url()).pathname).toBe("/tasks")
    expect(params(page)).toEqual({ "task[sort]": "title" })
    await expect(tasks.header("title")).toHaveAttribute("aria-sort", "ascending")
    expect(await tasks.rowKey(1)).toBe(key)
    // nothing of what was expanded is in an address
    await expect(tasks.expander(key)).toHaveAttribute("aria-expanded", "false")
    await expect(tasks.lines(key)).toHaveCount(0)

    await page.goForward()
    await full.ready()
    expect(params(page)).toEqual({ "comment[of][task][comments]": key })
    await expect(full.relatedHeading).toBeVisible()
  })
})

test.describe("as other actors", () => {
  for (const actor of ["member", "viewer"] as const) {
    test.describe(() => {
      test.use({ actor })

      test(`as the ${actor}: the tasks of a project in the full view, as this person's table`, async ({
        page,
      }) => {
        const projects = new Table(page, "project", "/projects")
        await projects.open()
        const nested = await projects.openLine(MOBILE_APP, "tasks")
        await nested.fullView.click()

        const tasks = new Table(page, "task", "/tasks")
        await tasks.ready()
        await expect(tasks.relatedHeading).toHaveText("Mobile app: Tasks")
        await expect(tasks.range).toHaveText("1–25 of 57")
        expect(await tasks.columns()).not.toContain("external_ref")
        expect(await tasks.columns()).toContain("project")
        expect((await tasks.columns()).includes("assignee")).toBe(actor === "member")
        await expectNoAxeViolations(page)
      })
    })
  }

  test.describe(() => {
    test.use({ actor: "outsider" })

    test("as the outsider: a link to the records of another organization's task shows nothing of them, and names nothing", async ({
      page,
    }) => {
      const full = comments(page)
      await page.goto(`/comments?comment[of][task][comments]=${FIRST}`)

      await expect(full.error).toHaveText("This record is no longer available.")
      await expect(full.rows).toHaveCount(0)
      await expect(full.empty).toHaveCount(0)
      await expect(full.relatedHeading).toHaveText("Comments")
      await expect(full.relatedParent).toHaveCount(0)
      await expectNoAxeViolations(page)

      // the way back works
      await full.relatedClear.click()
      await full.ready()
      await expect(full.relatedHeading).toHaveCount(0)
      await expect(full.rows.first()).toBeVisible()
    })
  })

  test("a limit that names nothing the table has is ignored: the page is the table", async ({ page }) => {
    const full = comments(page)
    await full.open(`/comments?comment[of][Elixir.Demo.Tracker.Task][comments]=${FIRST}`)

    await expect(full.relatedHeading).toHaveCount(0)
    await expect(full.error).toHaveCount(0)
    await expect(full.rows).toHaveCount(20)
  })
})
