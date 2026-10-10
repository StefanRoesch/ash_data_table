import { expectNoAxeViolations } from "./support/a11y"
import { SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { Table } from "./support/table"

// Reference cells in a browser: the columns "Project", "Assignee" and
// "Reported by" of /tasks show a related record by its label. They are
// cells like any other for the keyboard, and nothing a person can sort by
// or filter by. How the first two are edited is in picker.spec.ts; the
// third is read-only.

const FIRST = SEED.task.first

test.describe("as the admin", () => {
  test.beforeEach(async ({ tasks }) => {
    await tasks.open()
  })

  test("a reference cell shows what the related record is called: its name in its own table", async ({
    tasks,
  }) => {
    await expect(tasks.header("project")).toHaveText("Project")
    await expect(tasks.header("reporter")).toHaveText("Reported by")
    const shown = {
      project: (await tasks.cell(FIRST, "project").textContent())!,
      reporter: (await tasks.cell(FIRST, "reporter").textContent())!,
    }
    expect(shown.project).not.toBe("")
    expect(shown.reporter).not.toBe("")
    // not keys
    expect(shown.project).not.toMatch(/^[0-9a-f-]{36}$/)

    // the related records themselves, under the row
    const project = await tasks.openLine(FIRST, "project")
    expect(await project.columnTexts("name")).toEqual([shown.project])
    const reporter = await tasks.openLine(FIRST, "reporter")
    expect(await reporter.columnTexts("name")).toEqual([shown.reporter])
  })

  test("is a cell the arrow keys stop at, with nothing to sort or to filter; one whose key no action accepts has nothing to edit", async ({
    tasks,
    frames,
  }) => {
    for (const column of ["project", "assignee", "reporter"]) {
      await expect(tasks.header(column)).not.toHaveAttribute("aria-sort")
      await expect(tasks.filterCell(column).locator("input, select")).toHaveCount(0)
    }
    await expect(tasks.cell(FIRST, "reporter")).toHaveAttribute("aria-readonly", "true")

    await tasks.cell(FIRST, "inserted_at").focus()
    await tasks.press("ArrowRight")
    await expect(tasks.cell(FIRST, "project")).toBeFocused()
    await tasks.press("ArrowRight", "ArrowRight")
    await expect(tasks.cell(FIRST, "reporter")).toBeFocused()
    // the last column; the cell after it holds the row's actions
    await tasks.press("ArrowRight")
    await expect(tasks.actionsCell(FIRST)).toBeFocused()
    await tasks.press("ArrowLeft")
    await expect(tasks.cell(FIRST, "reporter")).toBeFocused()

    await frames.clear()
    const before = await tasks.cell(FIRST, "reporter").textContent()
    await tasks.press("Enter", "F2", "x")
    await expect(tasks.openEditors).toHaveCount(0)
    await expect(tasks.cell(FIRST, "reporter")).toHaveText(before!)

    // Enter on its heading and in its filter cell do nothing either
    await tasks.press("ArrowUp", "Enter", "ArrowUp", "Enter")
    await expect(tasks.header("reporter")).toBeFocused()
    expect(await frames.all()).toEqual([])
    expect(new URL(tasks.page.url()).search).toBe("")
  })

  test.describe("saving", () => {
    test.use({ writes: true })

    test("a row keeps its reference cells when another of its cells is saved", async ({ tasks }) => {
      const project = await tasks.cell(FIRST, "project").textContent()
      const reporter = await tasks.cell(FIRST, "reporter").textContent()
      const cell = tasks.cell(FIRST, "title")

      await cell.focus()
      await tasks.press("Enter")
      await tasks.retype("Renamed beside its reference cells")
      await tasks.saves(cell, () => tasks.press("Enter"))

      await expect(cell).toHaveText("Renamed beside its reference cells")
      await expect(tasks.cell(FIRST, "project")).toHaveText(project!)
      await expect(tasks.cell(FIRST, "reporter")).toHaveText(reporter!)
    })
  })

  test("the tasks nested under a project show their reference cells too", async ({ page }) => {
    const projects = new Table(page, "project", "/projects")
    await projects.open()
    const nested = await projects.openLine(SEED.project.mobileApp, "tasks")

    expect(new Set(await nested.columnTexts("project"))).toEqual(new Set(["Mobile app"]))
    const reporters = await nested.columnTexts("reporter")
    expect(reporters).toHaveLength(25)
    expect(reporters.every((name) => name !== "")).toBe(true)
    await expectNoAxeViolations(page)
  })
})

test.describe("as the viewer, who may not read people", () => {
  test.use({ actor: "viewer" })

  test("the project is shown and the people are not: no column, no line", async ({ page, tasks }) => {
    await tasks.open()
    const columns = await tasks.columns()

    expect(columns).toContain("project")
    expect(columns).not.toContain("assignee")
    expect(columns).not.toContain("reporter")
    expect(columns.at(-1)).toBe("project")
    await expect(tasks.cell(await tasks.rowKey(1), "project")).not.toHaveText("")

    await tasks.expand(await tasks.rowKey(1))
    await expect(tasks.lines(await tasks.rowKey(1))).toHaveText([
      /Comments/,
      /First comment/,
      /Newest comment/,
      /Labels/,
      /Project/,
    ])
    await expectNoAxeViolations(page)
  })
})
