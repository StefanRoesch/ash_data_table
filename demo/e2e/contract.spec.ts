import path from "node:path"
import type { Page } from "@playwright/test"
import { SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { Table } from "./support/table"

// The public contract of the package's browser side, for a kit that draws
// in the browser:
//
//   * `assets/js/ids.js` makes every id `AshDataTable.Ids` makes, function
//     by function: /e2e/ids renders a sample of each, with what the server
//     made of it;
//   * `assets/js/geometry.js` counts the grid's columns and rows as
//     `AshDataTable.Geometry` does: of real tables' markup (a top table
//     under offset pagination on its first page and on another, one under
//     keyset pagination without columns before its data columns, and a
//     nested table), what the server wrote (`data-lead`, `data-first-row`,
//     each data column's `aria-colindex`, each record's `aria-rowindex`)
//     is what geometry.js counts;
//   * `mountGrid` and `liveViewTransport` mount the grid's hook by hand on
//     a grid that has no `phx-hook` (/e2e/markers?mount=1, the demo's hook
//     `MountedGrid`): an edit and its save work from the keyboard, `onEdit`
//     hears the edit begin and end, and the hook mounted again on the same
//     element after `destroy()` (React's StrictMode) acts once per key.

type Ids = Record<string, (...args: unknown[]) => string>

const library = path.resolve(import.meta.dirname, "../../assets/js/ids.js")
const geometryLibrary = path.resolve(import.meta.dirname, "../../assets/js/geometry.js")
const markersLibrary = path.resolve(import.meta.dirname, "../../assets/js/markers.js")
const camel = (name: string) => name.replace(/_(\w)/g, (_all, letter: string) => letter.toUpperCase())

test("ids.js makes every id AshDataTable.Ids makes, and has no function it lacks", async ({ page }) => {
  const ids: Ids = await import(library)
  await page.goto("/e2e/ids")

  const samples: { function: string; args: unknown[]; id: string }[] = JSON.parse(
    (await page.locator("#ids").textContent()) ?? "[]",
  )
  const functions: string[] = JSON.parse((await page.locator("#functions").textContent()) ?? "[]")

  expect(samples.length).toBeGreaterThan(0)
  for (const sample of samples) {
    const made = ids[camel(sample.function)]
    expect(made, `ids.js has no ${camel(sample.function)}`).toBeDefined()
    expect(made(...sample.args), `${sample.function}(${JSON.stringify(sample.args)})`).toBe(sample.id)
  }

  // every function of `Ids` has a sample, and ids.js has no other
  const sampled = new Set(samples.map((sample) => sample.function))
  expect(functions.filter((name) => !sampled.has(name))).toEqual([])
  // (the module as Node gives it: its exports, besides what the interop adds)
  const exported = Object.keys(ids).filter((name) => name !== "default" && typeof ids[name] === "function")
  expect(exported.sort()).toEqual([...sampled].map(camel).sort())
})

type Grid = { dataset: { lead?: string }; querySelector: (selector: string) => { dataset: { firstRow?: string } } | null }

/**
 * What the server wrote of where a table's columns and rows stand, as its
 * markup has it: the grid's element as the hooks read it (its `data-lead`,
 * and its table's `data-first-row`, found as geometry.js finds it); how many
 * header cells stand before the first data column's; each data column's
 * `aria-colindex`, in order; and each record's `aria-rowindex`, in order.
 */
async function drawn(table: Table, marker: string) {
  const read = await table.hookRoot.evaluate(
    (element, [id, marker]) => {
      const found = element.querySelector(marker) as HTMLElement | null
      const headers = [...document.getElementById(`${id}-head-row`)!.querySelectorAll(":scope > [role=columnheader]")]
      const data = headers.filter((header) => header.id.startsWith(`${id}-head-`))
      const rows = [...document.getElementById(`${id}-table`)!.querySelectorAll(":scope > [role=rowgroup]:not([data-detail]) > [role=row]")]
      return {
        lead: (element as HTMLElement).dataset.lead,
        firstRow: found ? found.dataset.firstRow : undefined,
        before: headers.indexOf(data[0]),
        columns: data.map((header) => Number(header.getAttribute("aria-colindex"))),
        rows: rows.map((row) => Number(row.getAttribute("aria-rowindex"))),
      }
    },
    [table.id, marker],
  )
  const grid: Grid = {
    dataset: { lead: read.lead },
    querySelector: (selector) => (selector === marker && read.firstRow != null ? { dataset: { firstRow: read.firstRow } } : null),
  }
  return { grid, before: read.before, columns: read.columns, rows: read.rows }
}

test("geometry.js counts the columns and rows as AshDataTable.Geometry does, and has no function it lacks", async ({ page }) => {
  const geometry: Record<string, (...args: unknown[]) => number> = await import(geometryLibrary)
  const { TABLE }: { TABLE: string } = await import(markersLibrary)
  const used = new Set<string>()
  const count = (name: string, ...args: unknown[]) => {
    expect(geometry[name], `geometry.js has no ${name}`).toBeDefined()
    used.add(name)
    return geometry[name](...args)
  }

  const compare = async (table: Table, what: string) => {
    const { grid, before, columns, rows } = await drawn(table, TABLE)
    expect(columns.length, `${what} has data columns`).toBeGreaterThan(0)
    expect(rows.length, `${what} has records`).toBeGreaterThan(0)

    const lead = count("lead", grid)
    expect(lead, `${what}: lead, the header cells before the first data column's`).toBe(before)
    columns.forEach((colindex, index) => expect(count("colindex", index, lead), `${what}: colindex(${index}, ${lead})`).toBe(colindex))

    const first = count("firstRow", grid)
    rows.forEach((rowindex, n) => expect(count("rowindex", first, n), `${what}: rowindex(${first}, ${n})`).toBe(rowindex))
    return { lead, first }
  }

  // /tasks: rows selected and expanded, offset pages; its first page and its second
  const tasks = new Table(page, "task", "/tasks")
  await tasks.open()
  const onFirst = await compare(tasks, "/tasks, page 1")
  await tasks.reads(() => tasks.next.click())
  const onSecond = await compare(tasks, "/tasks, page 2")
  expect(onSecond.first, "the second page's rows go on from the first's").toBeGreaterThan(onFirst.first)

  // /comments: keyset pages; before the data columns the boxes (a comment
  // is deleted on several rows) and the expanders (its task, its author)
  const comments = new Table(page, "comment", "/comments")
  await comments.open()
  expect((await compare(comments, "/comments")).lead).toBe(2)

  // /comments/compact: a named table with no action and rows that never
  // expand, so nothing before the data columns
  const compact = new Table(page, "comment_compact", "/comments/compact")
  await compact.open()
  expect((await compare(compact, "/comments/compact")).lead).toBe(0)

  // a nested table: the tasks of a project
  const projects = new Table(page, "project", "/projects")
  await projects.open()
  await compare(await projects.openLine(SEED.project.mobileApp, "tasks"), "the tasks of Mobile App")

  const exported = Object.keys(geometry).filter((name) => name !== "default" && typeof geometry[name] === "function")
  expect(exported.sort()).toEqual([...used].sort())
})

test.describe("the grid's hook mounted by hand", () => {
  const cell = (page: Page, key: string, column: string) => page.locator(`[id="kit-row-${key}-c-${column}"]`)
  const edits = (page: Page) => page.evaluate(() => (window as unknown as { kitMount: { edits: unknown[] } }).kitMount.edits)
  const call = (page: Page, what: "remount" | "destroy" | "beforeUpdate" | "updated") =>
    page.evaluate((what) => (window as unknown as { kitMount: Record<string, () => void> }).kitMount[what](), what)

  test.beforeEach(async ({ page }) => {
    await page.goto("/e2e/markers?mount=1")
    await expect(page.locator('[id="kit-grid"]')).not.toHaveAttribute("phx-hook")
    // the hooks are mounted by hand (`window.kitMount`, the demo's MountedGrid)
    await page.waitForFunction(() => "kitMount" in window)
  })

  test("edits and saves from the keyboard, and tells onEdit", async ({ page }) => {
    await cell(page, "a", "name").focus()
    await page.keyboard.press("Enter")
    const editor = cell(page, "a", "name").locator("textarea")
    await expect(editor).toBeFocused()
    expect(await edits(page)).toEqual(["kit-row-a-c-name"])

    await page.keyboard.press("Escape")
    await expect(cell(page, "a", "name")).toBeFocused()
    expect(await edits(page)).toEqual(["kit-row-a-c-name", null])

    // a save goes out through the transport (the sender), and its row comes back
    await page.keyboard.press("Enter")
    await editor.fill("Anvil")
    await page.keyboard.press("Enter")
    await expect(cell(page, "a", "name")).toHaveText("Anvil")
    await expect(cell(page, "a", "name")).not.toHaveAttribute("aria-busy")
    expect(await edits(page)).toEqual(["kit-row-a-c-name", null, "kit-row-a-c-name", null])
    await call(page, "beforeUpdate")
    await call(page, "updated")
  })

  test("the pagination keeps the focused control aside before a commit, and gives focus back after", async ({ page }) => {
    // a commit of the kit that takes the focused button out and puts a new
    // one in its place: the browser drops the focus; the kit says it has
    // committed a moment later (a passive effect), once the focus is gone
    const commit = (page: Page, before: boolean) =>
      page.evaluate(async (before) => {
        const { pagination } = (window as unknown as { kitMount: { pagination: { beforeUpdate(): void; updated(): void } } }).kitMount
        if (before) pagination.beforeUpdate()
        const button = document.getElementById("kit-page-2")!
        button.replaceWith(button.cloneNode(true))
        await new Promise((resolve) => setTimeout(resolve, 50))
        pagination.updated()
      }, before)
    const button = page.locator('[id="kit-page-2"]')

    // told only after the commit, it has nothing to give back
    await button.focus()
    await commit(page, false)
    await expect(button).not.toBeFocused()

    // told before it, as the contract asks
    await button.focus()
    await commit(page, true)
    await expect(button).toBeFocused()
  })

  test("mounted again after destroy, it acts once per key; destroyed, not at all", async ({ page }) => {
    // as React's StrictMode does: mount, destroy (twice does nothing more), mount
    await call(page, "remount")
    await call(page, "remount")

    // the note that cuts its text off has one "Show all", and Enter on it
    // shows the whole text: once, not shown and cut off again by a second hook
    const whole = cell(page, "a", "note").locator(":scope > [data-whole]")
    await expect(whole).toHaveCount(1)
    await whole.focus()
    await page.keyboard.press("Enter")
    await expect(whole).toHaveAttribute("aria-expanded", "true")

    await cell(page, "a", "name").focus()
    await page.keyboard.press("Enter")
    await expect(cell(page, "a", "name").locator("textarea")).toHaveCount(1)
    await expect(cell(page, "a", "name").locator("textarea")).toBeFocused()
    await page.keyboard.press("Escape")
    // each edit told once
    expect(await edits(page)).toEqual(["kit-row-a-c-name", null])

    await call(page, "destroy")
    await cell(page, "a", "name").focus()
    await page.keyboard.press("Enter")
    await expect(cell(page, "a", "name")).toBeFocused()
    await expect(cell(page, "a", "name").locator("textarea")).toHaveCount(0)
  })
})
