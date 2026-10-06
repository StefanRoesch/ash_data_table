import { expect, test } from "./support/fixtures"
import { SEED } from "./support/data"
import { Table } from "./support/table"
import { params } from "./support/url"

// /task_labels: a resource whose primary key is two attributes, the task and
// the label, with one more attribute, the note. No `table` block names its
// columns. Every row is found, shown again and saved by both parts of its
// key together.

// three labels of one task: what tells them apart is the second part of the key
const { first: FIRST, second: SECOND, third: THIRD } = SEED.taskLabel

const UUID = "[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}"

/** The two parts of a row's key. */
function parts(key: string): { task: string; label: string } {
  return { task: key.slice(0, 36), label: key.slice(37) }
}

let table: Table

test.beforeEach(async ({ page }) => {
  table = new Table(page, "task_label", "/task_labels")
  await table.open()
})

/** Types a note into the row's cell and saves it with Enter. */
async function writeNote(key: string, note: string): Promise<void> {
  const cell = table.cell(key, "note")
  await cell.focus()
  await table.press("Enter")
  await expect(table.editor(cell)).toBeFocused()
  await table.retype(note)
  await table.saves(cell, () => table.press("Enter"))
}

test.describe("reading", () => {
  test("a row has both parts of its key in its ids, and its cells show them", async () => {
    for (const key of await table.rowKeys()) expect(key).toMatch(new RegExp(`^${UUID}-${UUID}$`))

    for (const key of [FIRST, SECOND, THIRD]) {
      await expect(table.cell(key, "task_id")).toHaveText(parts(key).task)
      await expect(table.cell(key, "label_id")).toHaveText(parts(key).label)
      await expect(table.cell(key, "note"), "the seed gives no notes").toHaveText("")
    }
    expect(parts(FIRST).task).toBe(parts(THIRD).task)
  })

  test("the rows come by task, then by label, in pages of 25 with a total", async ({ page }) => {
    const first = await table.rowKeys()
    expect(first).toHaveLength(25)
    expect(first.slice(0, 3)).toEqual([FIRST, SECOND, THIRD])
    // both parts are as long in every key, so the keys sort as their parts do
    expect(first).toEqual([...first].sort())
    await expect(table.range).toHaveText(`1–25 of ${SEED.taskLabels.acme}`)
    await expect(table.pagination).toHaveAccessibleName("Pagination: Task labels")
    await expect(table.pageButton(16), "the last page is offered").toBeVisible()
    await expect(table.grid).toHaveAttribute("aria-rowcount", String(SEED.taskLabels.acme + 2))

    await table.reads(() => table.next.click())
    await expect(table.range).toHaveText(`26–50 of ${SEED.taskLabels.acme}`)
    expect(params(page)).toEqual({ "task_label[page]": "2" })
    const second = await table.rowKeys()
    expect(second).toHaveLength(25)
    expect(second.filter((key) => first.includes(key))).toEqual([])
    expect([...first, ...second]).toEqual([...first, ...second].sort())

    await table.reads(() => table.pageButton(16).click())
    await expect(table.range).toHaveText("376–396 of 396")
    await expect(table.rows).toHaveCount(21)
    await expect(table.next).toBeDisabled()

    await page.reload()
    await table.ready()
    await expect(table.range, "a reload shows the same page").toHaveText("376–396 of 396")
  })

  test("each column sorts, and without a sort the action's order is back", async ({ page }) => {
    const unsorted = await table.rowKeys()
    for (const column of ["note", "task_id", "label_id"]) {
      await expect(table.header(column)).toHaveAttribute("aria-sort", "none")
    }

    await table.reads(() => table.header("label_id").click())
    await expect(table.header("label_id")).toHaveAttribute("aria-sort", "ascending")
    expect(params(page)).toEqual({ "task_label[sort]": "label_id" })
    const ascending = await table.columnTexts("label_id")
    expect(ascending).toEqual([...ascending].sort())
    expect(new Set(ascending).size, "one label fills the page: its tasks follow").toBe(1)
    // the cells of a row still show the row's own key
    for (const key of await table.rowKeys()) {
      await expect(table.cell(key, "task_id")).toHaveText(parts(key).task)
      await expect(table.cell(key, "label_id")).toHaveText(parts(key).label)
    }

    await table.reads(() => table.header("label_id").click())
    await expect(table.header("label_id")).toHaveAttribute("aria-sort", "descending")
    expect(params(page)).toEqual({ "task_label[sort]": "-label_id" })
    const descending = await table.columnTexts("label_id")
    expect(descending).toEqual([...descending].sort().reverse())
    expect(descending[0] > ascending[0]).toBe(true)

    await table.reads(() => table.header("label_id").click())
    await expect(table.header("label_id")).toHaveAttribute("aria-sort", "none")
    expect(params(page)).toEqual({})
    expect(await table.rowKeys()).toEqual(unsorted)

    // by keyboard, and by the other part of the key
    await table.header("task_id").focus()
    await table.reads(() => table.press("Enter"))
    await table.reads(() => table.press("Enter"))
    await expect(table.header("task_id")).toHaveAttribute("aria-sort", "descending")
    await expect(table.header("task_id")).toBeFocused()
    const tasks = await table.columnTexts("task_id")
    expect(tasks).toEqual([...tasks].sort().reverse())
    expect(tasks[0] > parts(FIRST).task).toBe(true)
  })

  test("the grid is one tab stop, and the arrow keys walk its three columns", async () => {
    expect(await table.columns()).toEqual(["note", "task_id", "label_id"])
    expect(await table.tabStops()).toEqual([`task_label-row-${FIRST}-c-note`])

    await table.tabStop.focus()
    await table.press("ArrowRight", "ArrowRight", "ArrowRight")
    await expect(table.cell(FIRST, "label_id"), "the last column is where Right ends").toBeFocused()
    await table.press("ArrowDown", "ArrowDown", "Home")
    await expect(table.cell(THIRD, "note")).toBeFocused()
    expect(await table.tabStops()).toEqual([`task_label-row-${THIRD}-c-note`])
  })
})

test.describe("the note", () => {
  test("it is the one column with an editor; the parts of the key cannot be edited", async ({
    frames,
  }) => {
    await expect(table.editorTemplates).toHaveCount(1)
    await expect(table.editorTemplates).toHaveId("task_label-editor-note")
    await expect(table.cell(FIRST, "note")).not.toHaveAttribute("aria-readonly")
    await expect(table.grid.locator("[aria-readonly]")).toHaveCount(2 * 25)

    for (const column of ["task_id", "label_id"]) {
      const cell = table.cell(FIRST, column)
      await expect(cell).toHaveAttribute("aria-readonly", "true")
      await cell.focus()
      await frames.clear()
      await table.press("Enter", "F2", "x")
      await cell.dblclick()
      await expect(table.openEditors).toHaveCount(0)
      await expect(cell).toBeFocused()
      expect(await frames.all()).toEqual([])
    }
  })

  test("it has a text filter, and the parts of the key have none", async ({ page }) => {
    await expect(page.getByRole("textbox", { name: "Filter Note", exact: true })).toHaveId(
      "task_label-filter-note-value",
    )
    await expect(table.filterOperator("note").locator("option")).toHaveText([
      "contains",
      "equals",
      "starts with",
      "is empty",
    ])
    for (const column of ["task_id", "label_id"]) {
      await expect(table.filterCell(column).locator("input, select, button")).toHaveCount(0)
    }

    // no row of the seed has a note
    await table.reads(() => table.filterOperator("note").selectOption("is empty"))
    expect(params(page)).toEqual({ "task_label[f][note][is_empty]": "" })
    await expect(table.range).toHaveText(`1–25 of ${SEED.taskLabels.acme}`)
    await expect(table.status).toHaveText(`${SEED.taskLabels.acme} results`)

    await table.reads(() => table.filterOperator("note").selectOption("contains"))
    await table.filterValue("note").fill("anything")
    await table.reads(() => table.filterValue("note").press("Enter"))
    await expect(table.empty).toHaveText("No records")
    await expect(table.status).toHaveText("0 results")
  })

  test.describe("saving", () => {
    test.use({ writes: true })

    test("it is saved on the row that was edited, of three that share a task", async ({
      page,
      frames,
    }) => {
      const keys = await table.rowKeys()
      await frames.clear()
      await writeNote(SECOND, "Because the docs are wrong")

      const note = table.cell(SECOND, "note")
      await expect(note).toHaveText("Because the docs are wrong")
      await expect(note).toBeFocused()
      await expect(note).not.toHaveAttribute("aria-invalid")
      expect(await frames.count("save")).toBe(1)
      // the event names the row by both parts of its key
      const [save] = (await frames.all()).filter((frame) => frame.includes('"save"'))
      expect(JSON.parse(save)[4].value).toMatchObject({
        row: SECOND,
        column: "note",
        value: "Because the docs are wrong",
      })

      // the rows beside it, of the same task, have no note; the row kept its place
      await expect(table.cell(FIRST, "note")).toHaveText("")
      await expect(table.cell(THIRD, "note")).toHaveText("")
      expect(await table.rowKeys()).toEqual(keys)
      expect((await table.columnTexts("note")).filter((text) => text !== "")).toHaveLength(1)

      // and so the database has it
      await page.reload()
      await table.ready()
      await expect(table.cell(SECOND, "note")).toHaveText("Because the docs are wrong")
      await expect(table.cell(FIRST, "note")).toHaveText("")
      await expect(table.cell(THIRD, "note")).toHaveText("")
      await expect(table.cell(SECOND, "task_id")).toHaveText(parts(SECOND).task)
      await expect(table.cell(SECOND, "label_id")).toHaveText(parts(SECOND).label)
    })

    test("a row found by another sort, on another page, is the row that is saved", async ({
      page,
    }) => {
      await table.reads(() => table.header("label_id").click())
      await table.reads(() => table.header("label_id").click())
      await table.reads(() => table.next.click())
      expect(params(page)).toEqual({ "task_label[sort]": "-label_id", "task_label[page]": "2" })

      const key = await table.rowKey(7)
      await writeNote(key, "Found on the second page")
      await expect(table.cell(key, "note")).toHaveText("Found on the second page")

      // the one note there is belongs to that task and that label
      await table.open("/task_labels?task_label[f][note]=second%20page")
      await expect(table.range).toHaveText("1–1 of 1")
      expect(await table.rowKeys()).toEqual([key])
      await expect(table.cell(key, "task_id")).toHaveText(parts(key).task)
      await expect(table.cell(key, "label_id")).toHaveText(parts(key).label)
    })

    test("notes filter and sort like any text; a note taken away is empty again", async ({
      page,
    }) => {
      await writeNote(FIRST, "Urgent: security review")
      await writeNote(SECOND, "Because the docs are wrong")
      await writeNote(THIRD, "Because it was asked for")

      await table.filterValue("note").fill("Because")
      await table.reads(() => table.filterValue("note").press("Enter"))
      expect(params(page)).toEqual({ "task_label[f][note]": "Because" })
      await expect(table.range).toHaveText("1–2 of 2")
      await expect(table.status).toHaveText("2 results")
      expect(await table.rowKeys(), "by task, then by label").toEqual([SECOND, THIRD])

      await table.reads(() => table.header("note").click())
      await expect(table.header("note")).toHaveAttribute("aria-sort", "ascending")
      expect(await table.columnTexts("note")).toEqual([
        "Because it was asked for",
        "Because the docs are wrong",
      ])
      expect(await table.rowKeys()).toEqual([THIRD, SECOND])
      await table.reads(() => table.header("note").click())
      expect(await table.rowKeys()).toEqual([SECOND, THIRD])

      await table.reads(() => table.filterOperator("note").selectOption("starts with"))
      await table.filterValue("note").fill("Urgent")
      await table.reads(() => table.filterValue("note").press("Enter"))
      expect(await table.rowKeys()).toEqual([FIRST])

      // emptied, the note is nil again: "is empty" finds every row
      await writeNote(FIRST, "")
      await expect(table.cell(FIRST, "note"), "the row stays until the table reads again").toHaveText("")
      await table.reads(() => table.filterOperator("note").selectOption("is empty"))
      await expect(table.range).toHaveText(`1–25 of ${SEED.taskLabels.acme - 2}`)
    })

    test("Escape gives the edit up, and nothing is saved", async ({ frames }) => {
      const note = table.cell(THIRD, "note")
      await note.focus()
      await frames.clear()
      await table.press("Enter")
      await table.retype("Not meant")
      await table.press("Escape")

      await expect(table.openEditors).toHaveCount(0)
      await expect(note).toHaveText("")
      await expect(note).toBeFocused()
      expect(await frames.all()).toEqual([])
    })
  })

  test.describe("for the viewer", () => {
    test.use({ actor: "viewer" })

    test("who may change nothing: no editor, and nothing marked read-only", async () => {
      await expect(table.rows).toHaveCount(25)
      await expect(table.editorTemplates).toHaveCount(0)
      await expect(table.grid.locator("[aria-readonly]")).toHaveCount(0)
    })
  })
})
