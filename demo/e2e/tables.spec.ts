import { expect, test } from "./support/fixtures"
import { SEED } from "./support/data"
import { Table } from "./support/table"

// Every table the demo mounts (DemoWeb.Router) opens, shows its columns and
// rows, and has a working keyboard, as the admin. That nothing is reported
// on the console is checked for every test (support/fixtures.ts).

type Mounted = {
  path: string
  id: string
  /** The page's heading and the grid's name. */
  title: string
  /** What makes this table different from the others. */
  shows: string
  headers: string[]
  rows: number
  pagination: "offset" | "keyset" | "none"
}

const LABELS = { id: "label", title: "Labels", headers: ["ID", "Name", "Colour"], rows: SEED.labels.acme }

const MOUNTED: Mounted[] = [
  {
    path: "/tasks",
    id: "task",
    title: "Tasks",
    shows: "a `table` block: chosen columns, a relabelled one, an aggregate, two calculations, three reference cells",
    headers: [
      "Title",
      "State",
      "Priority",
      "Progress",
      "Estimate hours",
      "Billable?",
      "Due on",
      "Completed at",
      "Overdue?",
      "Comments",
      "Headline",
      "External ref",
      "Description",
      "Inserted at",
      "Project",
      "Assignee",
      "Reported by",
    ],
    rows: 25,
    pagination: "offset",
  },
  {
    path: "/projects",
    id: "project",
    title: "Projects",
    shows: "no column declared: the defaults",
    headers: ["ID", "Name", "Description", "Status", "Starts on", "Budget", "Inserted at"],
    rows: SEED.projects.acme,
    pagination: "offset",
  },
  {
    path: "/comments",
    id: "comment",
    title: "Comments",
    shows: "keyset pagination",
    headers: ["ID", "Body", "Inserted at", "Task ID", "Author ID"],
    rows: 20,
    pagination: "keyset",
  },
  { path: "/labels", shows: "no pagination", pagination: "none", ...LABELS },
  { path: "/bare/labels", shows: "the bare layout", pagination: "none", ...LABELS },
  {
    path: "/task_labels",
    id: "task_label",
    title: "Task labels",
    shows: "a primary key of two attributes",
    headers: ["Note", "Task ID", "Label ID"],
    rows: 25,
    pagination: "offset",
  },
]

for (const mounted of MOUNTED) {
  test(`${mounted.path} opens: ${mounted.shows}`, async ({ page }) => {
    const table = new Table(page, mounted.id, mounted.path)
    const response = await table.open()
    expect(response!.status()).toBe(200)

    await expect(page.getByRole("heading", { level: 1 })).toHaveText(mounted.title)
    await expect(page).toHaveTitle(`${mounted.title} · ash_table demo`)
    await expect(page.getByRole("grid", { name: mounted.title })).toHaveId(`${mounted.id}-table`)

    // each of these tables has relationships to offer: before its columns
    // is the one of the expanders, named for those who cannot see it. And
    // each has row actions the admin can run: after its columns is the one
    // of their buttons (actions.spec.ts)
    await expect(table.headers).toHaveText(mounted.headers)
    await expect(table.headerCells).toHaveText(["Related records", ...mounted.headers, "Actions"])
    await expect(table.grid).toHaveAttribute("aria-colcount", String(mounted.headers.length + 2))
    await expect(table.rows).toHaveCount(mounted.rows)
    await expect(table.expanders).toHaveCount(mounted.rows)
    await expect(table.rows.locator("td")).toHaveCount(mounted.rows * (mounted.headers.length + 2))

    await expect(table.pagination).toHaveCount(mounted.pagination === "none" ? 0 : 1)
    if (mounted.pagination !== "none") {
      await expect(table.pagination).toHaveAccessibleName(`Pagination: ${mounted.title}`)
    }
    await expect(table.pageButton(1)).toHaveCount(mounted.pagination === "offset" ? 1 : 0)

    // the hook has run: one tab stop, and the arrow keys move from it
    const columns = await table.columns()
    const first = await table.rowKey(1)
    expect(await table.tabStops()).toEqual([`${mounted.id}-row-${first}-c-${columns[0]}`])
    await table.tabStop.focus()
    await table.press("ArrowRight", "ArrowDown")
    await expect(table.cell(await table.rowKey(2), columns[1])).toBeFocused()

    // every id in the page is used once
    const ids = await page.locator("[id]").evaluateAll((elements) => elements.map((e) => e.id))
    expect(ids.filter((id, index) => ids.indexOf(id) !== index)).toEqual([])
  })
}

test("every table is reached from the front page by a live navigation", async ({ page }) => {
  for (const mounted of MOUNTED) {
    await page.goto("/")
    await page.getByRole("link", { name: mounted.path, exact: true }).click()

    const table = new Table(page, mounted.id, mounted.path)
    await table.ready()
    await expect(page).toHaveURL(new RegExp(`${mounted.path}$`))
    await expect(table.rows).toHaveCount(mounted.rows)
  }
})

test("/bare/labels is the table without the app layout", async ({ page }) => {
  // the app layout: its container around the page, and the flash messages
  const appLayout = page.locator("#app-layout, #flash-group")

  const framed = new Table(page, "label", "/labels")
  await framed.open()
  await expect(appLayout).toHaveCount(2)
  await expect(page.getByRole("main")).toHaveCount(1)
  const rows = await framed.rowKeys()

  const bare = new Table(page, "label", "/bare/labels")
  await bare.open()
  await expect(appLayout, "no app layout around it").toHaveCount(0)
  // the main landmark is the root layout's, so the bare page has it as well
  await expect(page.getByRole("main")).toHaveCount(1)
  await expect(page.getByRole("main").getByRole("heading", { level: 1 })).toHaveText("Labels")
  await expect(page.getByRole("main").getByRole("grid")).toHaveId("label-table")
  expect(await bare.rowKeys()).toEqual(rows)
  // sorting works there as anywhere
  await bare.reads(() => bare.header("name").click())
  await expect(bare.header("name")).toHaveAttribute("aria-sort", "ascending")
})

test.describe("/specimens: one column per built-in type", () => {
  let specimens: Table

  test.beforeEach(async ({ page }) => {
    specimens = new Table(page, "specimen", "/specimens")
    await specimens.open()
  })

  test("opens with every public attribute as a column, in pages of 20", async ({ page }) => {
    await expect(page.getByRole("heading", { level: 1 })).toHaveText("Specimens")
    await expect(specimens.headers).toHaveCount(47)
    await expect(specimens.grid).toHaveAttribute("aria-colcount", "47")
    await expect(specimens.rows).toHaveCount(20)
    await expect(specimens.range).toHaveText(`1–20 of ${SEED.specimens.total}`)

    const first = await specimens.rowKey(1)
    expect(first).toBe(SEED.specimens.first)
    await expect(specimens.cell(first, "label")).toHaveText("Specimen 001")
    await specimens.cell(first, "id").focus()
    await specimens.press("End")
    await expect(specimens.cell(first, "updated_at")).toBeFocused()
    await expect(specimens.cell(first, "updated_at")).toHaveAttribute("aria-colindex", "47")
  })

  test("values are shown by type: a check with its text, a label, plain text, nothing for nil", async () => {
    for (const text of await specimens.columnTexts("a_boolean")) expect(text).toMatch(/^(✓Yes|–No)$/)
    // the mark is for the eye, the word for a screen reader
    const boolean = specimens.columnCells("a_boolean").first()
    await expect(boolean.locator('[aria-hidden="true"]')).toHaveText(/^[✓–]$/)
    await expect(boolean.locator(".sr-only")).toHaveText(/^(Yes|No)$/)

    for (const text of await specimens.columnTexts("a_shade")) expect(text).toMatch(/^[A-Z]/)
    for (const text of await specimens.columnTexts("a_date")) expect(text).toMatch(/^\d{4}-\d\d-\d\d$/)
    for (const text of await specimens.columnTexts("a_utc_datetime")) {
      expect(text).toMatch(/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d$/)
    }
    for (const text of await specimens.columnTexts("an_integer")) expect(text).toMatch(/^-?\d+$/)

    const optional = await specimens.columnTexts("opt_string")
    expect(optional, "a nil is an empty cell").toContain("")
    expect(optional.some((text) => text !== "")).toBe(true)
  })

  test("a type with an editor is editable and filterable; any other is read-only text without a filter", async () => {
    const first = SEED.specimens.first

    for (const column of ["a_string", "an_integer", "a_decimal", "a_boolean", "a_date", "a_shade"]) {
      await expect(specimens.cell(first, column), column).not.toHaveAttribute("aria-readonly")
      await expect(
        specimens.filterCell(column).locator("input, select"),
        `${column} has a filter`,
      ).not.toHaveCount(0)
    }
    for (const column of ["a_map", "strings", "an_address", "a_union", "a_tuple", "a_binary"]) {
      await expect(specimens.cell(first, column), column).toHaveAttribute("aria-readonly", "true")
      await expect(specimens.cell(first, column), column).not.toHaveText("")
      await expect(specimens.filterCell(column).locator("input, select"), column).toHaveCount(0)
    }

    // "is empty" is offered where the attribute can be nil
    await expect(specimens.filterOperator("opt_string").locator("option")).toContainText(["is empty"])
    await expect(specimens.filterOperator("a_string").locator("option")).not.toContainText([
      "is empty",
    ])
  })
})

test("/tasks shows labels for choices and one line per row, whatever the text", async ({ tasks }) => {
  await tasks.open()

  const states = ["Backlog", "To do", "In progress", "In review", "Done", "Archived"]
  for (const state of await tasks.columnTexts("status")) expect(states).toContain(state)
  for (const text of await tasks.columnTexts("billable?")) expect(text).toMatch(/^(✓Yes|–No)$/)
  for (const text of await tasks.columnTexts("headline")) expect(text).not.toBe("")

  // long descriptions are cut off, not wrapped
  const heights = await tasks.grid
    .locator("tbody tr")
    .evaluateAll((rows) => rows.map((row) => Math.round(row.getBoundingClientRect().height)))
  // (the first row is a border higher than the others)
  expect(Math.max(...heights) - Math.min(...heights), `row heights ${heights}`).toBeLessThan(3)
})
