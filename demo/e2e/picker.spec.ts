import type { Page } from "@playwright/test"
import { expectNoAxeViolations } from "./support/a11y"
import { contrastOf } from "./support/contrast"
import { SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { switchLocale } from "./support/locale"
import { Table } from "./support/table"

// The picker in a browser: a reference cell of /tasks ("Project",
// "Assignee") is edited by choosing a record of the related resource's own
// table, in a dialog at the right edge of the window; and a field of the
// action panel that holds such a key is given the same way, with the picker
// on top of the panel.

// "Rename the onboarding email": assigned to Kim Ernst, in "Data warehouse"
const FIRST = SEED.task.first
const SECOND = SEED.task.second

const GONE = "This record is no longer available."

/** The key of the row of a table whose cell of a column reads `text`. */
async function keyOf(table: Table, column: string, text: string): Promise<string> {
  const keys = await table.rowKeys()
  const texts = await table.columnTexts(column)
  const index = texts.findIndex((shown) => shown.trim() === text)
  expect(index, `a row whose ${column} is ${text}`).toBeGreaterThanOrEqual(0)
  return keys[index]
}

/** Opens the picker of a reference cell from the keyboard, and waits for its table. */
async function openPicker(tasks: Table, key: string, column: string): Promise<Table> {
  await tasks.cell(key, column).focus()
  await tasks.press("Enter")
  await expect(tasks.picker).toBeVisible()
  const table = tasks.pickerTable(column)
  await table.ready()
  return table
}

/** The modal dialogs that are open, as they stand in the page, and the one focus is in. */
async function modals(page: Page): Promise<{ open: string[]; focusIn: string | null }> {
  return page.evaluate(() => {
    const open = Array.from(document.querySelectorAll("dialog:modal")).map((dialog) => dialog.id)
    const active = document.activeElement
    const within = active && active.closest("dialog")
    return { open, focusIn: within ? within.id : null }
  })
}

test.beforeEach(async ({ tasks }) => {
  await tasks.open()
})

test.describe("which reference cells are edited", () => {
  test("those whose key the column's update action accepts: the project and the assignee, and not the reporter", async ({
    tasks,
    pushed,
  }) => {
    await expect(tasks.cell(FIRST, "project")).not.toHaveAttribute("aria-readonly")
    await expect(tasks.cell(FIRST, "assignee")).not.toHaveAttribute("aria-readonly")
    await expect(tasks.cell(FIRST, "reporter")).toHaveAttribute("aria-readonly", "true")

    // nothing of a picker is in the page until one is opened
    await expect(tasks.picker).toHaveCount(0)
    await expect(tasks.page.locator("[id^='task-pick-']")).toHaveCount(0)

    // no key opens one for the reporter
    await tasks.cell(FIRST, "reporter").focus()
    await pushed.clear()
    await tasks.press("Enter", "F2", "x")
    await tasks.cell(FIRST, "reporter").dblclick()
    await expect(tasks.picker).toHaveCount(0)
    expect(await pushed.all()).toEqual([])
  })

  test.describe("as the viewer, who can run no update action", () => {
    test.use({ actor: "viewer" })

    test("none: no key opens a picker", async ({ tasks, pushed }) => {
      const key = await tasks.rowKey(1)
      await tasks.cell(key, "project").focus()
      await pushed.clear()
      await tasks.press("Enter", "F2")
      await tasks.cell(key, "project").dblclick()
      await expect(tasks.picker).toHaveCount(0)
      expect(await pushed.all()).toEqual([])
    })
  })
})

test.describe("opening the picker", () => {
  test("Enter opens a modal dialog at the right edge, named by its heading, with the related resource's table; focus is on the row of the record chosen now", async ({
    page,
    tasks,
    pushed,
  }) => {
    await tasks.cell(FIRST, "assignee").focus()
    await expect(tasks.cell(FIRST, "assignee")).toHaveText("Kim Ernst")
    await pushed.clear()
    await tasks.press("Enter")

    await expect(tasks.picker).toBeVisible()
    await expect(tasks.picker).toHaveRole("dialog")
    await expect(tasks.picker).toHaveAccessibleName("Assignee: choose user")
    await expect(tasks.pickerTitle).toHaveRole("heading")
    expect(await tasks.picker.evaluate((picker) => picker.matches(":modal"))).toBe(true)
    expect(await pushed.count("pick")).toBe(1)
    expect(await pushed.count("save")).toBe(0)

    // the people's table as it is declared, named as that table is
    const people = tasks.pickerTable("assignee")
    await people.ready()
    await expect(people.grid).toHaveRole("grid")
    await expect(people.grid).toHaveAccessibleName("User")
    expect(await people.columns()).toEqual(["name", "email", "role", "assigned_hours"])
    await expect(people.rows).toHaveCount(9)
    await expect(people.filterValue("name")).toHaveCount(1)
    await expect(people.header("name")).toHaveAttribute("aria-sort", "none")
    await expect(people.range).toHaveText("1–9 of 9")

    // the record the cell points at is selected, and has the focus
    const kim = await keyOf(people, "name", "Kim Ernst")
    expect(await people.selectedKeys()).toEqual([kim])
    await expect(people.radio(kim)).toBeChecked()
    await expect(people.cell(kim, "name")).toBeFocused()
    await expect(tasks.pickerChoose).toHaveAttribute("aria-disabled", "false")
    await expect(tasks.picker.getByRole("button")).toHaveText([
      "Columns",
      "Previous",
      "1",
      "Next",
      "Cancel",
      "None",
      "Choose",
    ])

    // at the right edge, as high as the window, and wide enough for a table
    const viewport = page.viewportSize()!
    const box = (await tasks.picker.boundingBox())!
    expect(box.x + box.width).toBeCloseTo(viewport.width, 0)
    expect(box.y).toBeCloseTo(0, 0)
    expect(box.height).toBeCloseTo(viewport.height, 0)
    expect(box.width).toBeCloseTo(768, 0)
  })

  test("F2 and a double click open it too; a printable key does not", async ({ tasks, pushed }) => {
    const cell = tasks.cell(FIRST, "assignee")
    await cell.focus()
    await pushed.clear()
    await tasks.press("x", "5", "Space")
    await expect(tasks.picker).toHaveCount(0)
    expect(await pushed.count("pick")).toBe(0)
    // Space selected the row, as on any cell
    await tasks.press("Space")

    await tasks.press("F2")
    await expect(tasks.picker).toBeVisible()
    await tasks.pickerTable("assignee").ready()
    await tasks.press("Escape")
    await expect(tasks.picker).toHaveCount(0)
    await expect(cell).toBeFocused()

    await cell.dblclick()
    await expect(tasks.picker).toBeVisible()
    await tasks.pickerCancel.click()
    await expect(tasks.picker).toHaveCount(0)
    await expect(cell).toBeFocused()
  })

  test("a cell that points at no record opens with nothing selected: focus is on the first row, and Choose is not to be used yet", async ({
    tasks,
    pushed,
  }) => {
    const texts = await tasks.columnTexts("assignee")
    const keys = await tasks.rowKeys()
    const unassigned = keys[texts.findIndex((text) => text.trim() === "")]
    expect(unassigned, "the first page has a task without an assignee").toBeTruthy()

    const people = await openPicker(tasks, unassigned, "assignee")
    expect(await people.selectedKeys()).toEqual([])
    await expect(people.cell(await people.rowKey(1), "name")).toBeFocused()
    await expect(tasks.pickerChoose).toHaveAttribute("aria-disabled", "true")

    // used all the same, it sends nothing
    await pushed.clear()
    await tasks.pickerChoose.click({ force: true })
    await expect(tasks.picker).toBeVisible()
    expect(await pushed.count("picked")).toBe(0)

    // `aria-disabled` is what its look follows: once a row is selected it
    // looks otherwise
    const look = () =>
      tasks.pickerChoose.evaluate((node) => {
        const style = getComputedStyle(node)
        return [style.backgroundColor, style.color, style.opacity, style.pointerEvents].join(" ")
      })
    const unusable = await look()
    await people.cell(await people.rowKey(1), "name").focus()
    await tasks.press(" ")
    await expect(tasks.pickerChoose).toHaveAttribute("aria-disabled", "false")
    await expect.poll(look).not.toBe(unusable)
  })

  test("the project has no \"None\": a task has to have one", async ({ tasks }) => {
    const projects = await openPicker(tasks, FIRST, "project")
    await expect(tasks.picker).toHaveAccessibleName("Project: choose project")
    await expect(projects.grid).toHaveAccessibleName("Projects")
    await expect(tasks.pickerNone).toHaveCount(0)
    await expect(tasks.pickerCancel).toBeVisible()
    await expect(tasks.pickerChoose).toBeVisible()
    expect(await projects.selectedKeys()).toEqual([await keyOf(projects, "name", "Data warehouse")])
  })

  test("the table in it is for choosing only: radio buttons, and nothing to edit, run, create or expand", async ({
    page,
    tasks,
    pushed,
  }) => {
    const projects = await openPicker(tasks, FIRST, "project")
    const key = await projects.rowKey(1)

    await expect(projects.grid).toHaveAttribute("aria-multiselectable", "false")
    await expect(projects.radios).toHaveCount(SEED.projects.acme)
    await expect(projects.boxes).toHaveCount(0)
    await expect(projects.radio(key)).toHaveAccessibleName("Select row")
    await expect(projects.create).toHaveCount(0)
    await expect(projects.actionsHeader).toHaveCount(0)
    await expect(projects.expanders).toHaveCount(0)
    await expect(projects.editorTemplates).toHaveCount(0)
    await expect(projects.selectionLine).toHaveCount(0)
    await expect(projects.name).toHaveCount(0)

    // the page of the projects itself has all of them
    const other = await page.context().newPage()
    const own = new Table(other, "project", "/projects")
    await own.open()
    await expect(own.create).toBeVisible()
    await expect(own.actionsHeader).toBeVisible()
    await expect(own.editorTemplates).not.toHaveCount(0)
    await other.close()

    // typing and F2 on a cell of the picker's table edit nothing
    await projects.cell(key, "name").focus()
    await pushed.clear()
    await tasks.press("F2", "x")
    await expect(projects.openEditors).toHaveCount(0)
    expect(await pushed.all()).toEqual([])
  })
})

test.describe("the grid in the picker", () => {
  test("keeps its keyboard contract: the arrow keys move and send nothing, Space selects, and the selected row stays selected", async ({
    tasks,
    pushed,
  }) => {
    const people = await openPicker(tasks, FIRST, "assignee")
    const keys = await people.rowKeys()
    const kim = await keyOf(people, "name", "Kim Ernst")
    const at = keys.indexOf(kim)
    await pushed.clear()

    await tasks.press("ArrowDown")
    await expect(people.cell(keys[at + 1], "name")).toBeFocused()
    await tasks.press("ArrowRight")
    await expect(people.cell(keys[at + 1], "email")).toBeFocused()
    await tasks.press("Home")
    await expect(people.boxCell(keys[at + 1])).toBeFocused()
    await tasks.press("End")
    await expect(people.cell(keys[at + 1], "assigned_hours")).toBeFocused()
    await tasks.press("Control+Home")
    await expect(people.boxCell(keys[0])).toBeFocused()
    await tasks.press("ArrowRight", "ArrowUp")
    await expect(people.filterCell("name")).toBeFocused()
    await tasks.press("ArrowUp")
    await expect(people.header("name")).toBeFocused()
    await tasks.press("ArrowDown", "ArrowDown", "ArrowDown")
    await expect(people.cell(keys[1], "name")).toBeFocused()

    // one tab stop, in the picker's own grid
    expect(await people.tabStops()).toEqual([`${people.id}-row-${keys[1]}-c-name`])

    // Space selects the row in the other's place
    await tasks.press("Space")
    expect(await people.selectedKeys()).toEqual([keys[1]])
    await expect(people.radio(keys[1])).toBeChecked()
    await expect(people.radio(kim)).not.toBeChecked()
    await expect(people.rowLine(kim)).toHaveAttribute("aria-selected", "false")
    // and once more leaves it selected: one of a set
    await tasks.press("Space")
    expect(await people.selectedKeys()).toEqual([keys[1]])
    // Shift selects no range
    await tasks.press("Shift+ArrowDown")
    expect(await people.selectedKeys()).toEqual([keys[1]])

    await pushed.expectSelected(people)
    expect(await pushed.besides("select"), "none of it talks to the server but to say what is selected").toEqual([])
    await expect(tasks.picker).toBeVisible()
  })

  test("Tab leaves the grid for the picker's buttons and never reaches the page; Shift+Tab comes back", async ({
    page,
    tasks,
  }) => {
    const people = await openPicker(tasks, FIRST, "assignee")
    const kim = await keyOf(people, "name", "Kim Ernst")

    // the pages of the people have nowhere to go: their buttons are disabled
    await tasks.press("Tab")
    await expect(people.pageButton(1)).toBeFocused()
    await tasks.press("Tab")
    await expect(tasks.pickerCancel).toBeFocused()
    await tasks.press("Tab")
    await expect(tasks.pickerNone).toBeFocused()
    await tasks.press("Tab")
    await expect(tasks.pickerChoose).toBeFocused()

    for (const key of ["Tab", "Tab", "Shift+Tab", "Shift+Tab", "Shift+Tab", "Shift+Tab", "Shift+Tab", "Shift+Tab"]) {
      await tasks.press(key)
      expect(await tasks.hasFocus(), `${key}: the grid of the page is out of reach`).toBe(false)
      expect(
        await page.evaluate(() => {
          const active = document.activeElement
          return !active || active === document.body || !!active.closest("dialog")
        }),
        `${key}: focus is in the picker, or with the browser`,
      ).toBe(true)
    }

    // back in the grid, on the cell it was left at
    await people.cell(kim, "name").focus()
    await tasks.press("Tab", "Shift+Tab")
    await expect(people.cell(kim, "name")).toBeFocused()

    // the pointer does not reach the page either
    const cell = (await tasks.cell(SECOND, "title").boundingBox())!
    await page.mouse.click(cell.x + 10, cell.y + cell.height / 2)
    await expect(tasks.cell(SECOND, "title")).not.toBeFocused()
    await expect(tasks.picker, "a click beside the picker leaves it open").toBeVisible()
  })

  test("filters and sorts by itself, as the people's table does; Escape in a filter comes back to its cell and leaves the picker open", async ({
    tasks,
  }) => {
    const people = await openPicker(tasks, FIRST, "assignee")
    const url = tasks.page.url()

    await people.filterCell("name").focus()
    await tasks.press("Enter")
    await expect(people.filterValue("name")).toBeFocused()
    await tasks.page.keyboard.type("Pia")
    await people.reads(() => tasks.press("Enter"))
    expect(await people.columnTexts("name")).toEqual(["Pia Graf", "Pia Lang"])
    await expect(people.status).toHaveText("2 results")

    // the record the cell points at is not on this page: nothing is selected,
    // and "Choose" has nothing to take
    expect(await people.selectedKeys()).toEqual([])
    await expect(tasks.pickerChoose).toHaveAttribute("aria-disabled", "true")

    await tasks.press("Escape")
    await expect(people.filterCell("name")).toBeFocused()
    await expect(tasks.picker).toBeVisible()

    // Enter on a heading sorts
    await tasks.press("ArrowUp", "ArrowRight")
    await expect(people.header("email")).toBeFocused()
    await people.reads(() => tasks.press("Enter"))
    await expect(people.header("email")).toHaveAttribute("aria-sort", "ascending")
    await people.reads(() => tasks.press("Enter"))
    expect(await people.columnTexts("name")).toEqual(["Pia Lang", "Pia Graf"])

    // "Clear filters" brings everybody back, with the cell's record selected again
    await people.reads(() => people.clearFilters.click())
    await expect(people.rows).toHaveCount(9)
    expect(await people.selectedKeys()).toEqual([await keyOf(people, "name", "Kim Ernst")])
    await expect(tasks.pickerChoose).toHaveAttribute("aria-disabled", "false")

    // nothing of it is in the page's URL
    expect(tasks.page.url()).toBe(url)
  })
})

test.describe("choosing", () => {
  test("Space selects and \"Choose\" saves: the cell shows the new record's label, and has the focus again", async ({
    tasks,
    pushed,
  }) => {
    const cell = tasks.cell(FIRST, "assignee")
    const people = await openPicker(tasks, FIRST, "assignee")
    const max = await keyOf(people, "name", "Max Member")
    await people.cell(max, "name").focus()
    await tasks.press("Space")
    await pushed.clear()

    await tasks.press("Tab", "Tab", "Tab", "Tab")
    await expect(tasks.pickerChoose).toBeFocused()
    await tasks.saves(cell, () => tasks.press("Enter"))

    await expect(tasks.picker).toHaveCount(0)
    await expect(cell).toHaveText("Max Member")
    await expect(cell).not.toHaveAttribute("aria-invalid")
    await expect(cell).toBeFocused()
    expect(await pushed.count("picked")).toBe(1)
    expect(await pushed.count("save")).toBe(0)
    expect(await tasks.tabStops()).toEqual([`task-row-${FIRST}-c-assignee`])

    // the arrow keys go on from the cell, and the choice has outlived a reload
    await tasks.press("ArrowLeft")
    await expect(tasks.cell(FIRST, "project")).toBeFocused()
    await tasks.open()
    await expect(cell).toHaveText("Max Member")
  })

  test("Enter on a row chooses it at once, and so does a double click", async ({ tasks, pushed }) => {
    const cell = tasks.cell(FIRST, "assignee")
    let people = await openPicker(tasks, FIRST, "assignee")
    await people.cell(await keyOf(people, "name", "Pia Lang"), "email").focus()
    await pushed.clear()
    await tasks.saves(cell, () => tasks.press("Enter"))

    await expect(tasks.picker).toHaveCount(0)
    await expect(cell).toHaveText("Pia Lang")
    await expect(cell).toBeFocused()
    expect(await pushed.count("picked")).toBe(1)

    people = await openPicker(tasks, FIRST, "assignee")
    await tasks.saves(cell, async () => {
      await people.cell(await keyOf(people, "name", "Fay Maier"), "role").dblclick()
    })
    await expect(tasks.picker).toHaveCount(0)
    await expect(cell).toHaveText("Fay Maier")
    await expect(cell).toBeFocused()
  })

  test("a click anywhere on a row selects it, and \"Choose\" takes it", async ({ tasks, pushed }) => {
    const cell = tasks.cell(FIRST, "assignee")
    const people = await openPicker(tasks, FIRST, "assignee")
    const kim = await keyOf(people, "name", "Kim Ernst")
    const mia = await keyOf(people, "name", "Mia Arnold")
    await pushed.clear()

    await people.cell(mia, "email").click()
    expect(await people.selectedKeys()).toEqual([mia])
    await expect(people.radio(mia)).toBeChecked()
    await expect(people.cell(mia, "email")).toBeFocused()
    // again, and on its radio button: it stays selected
    await people.cell(mia, "name").click()
    await people.radio(mia).click()
    expect(await people.selectedKeys()).toEqual([mia])
    // another row's radio button takes its place, and back
    await people.radio(kim).click()
    expect(await people.selectedKeys()).toEqual([kim])
    await people.radio(mia).click()
    await expect(people.radio(mia)).toBeChecked()
    await pushed.expectSelected(people)
    expect(await pushed.besides("select"), "selecting sends nothing but what is selected").toEqual([])

    await tasks.saves(cell, () => tasks.pickerChoose.click())
    await expect(tasks.picker).toHaveCount(0)
    await expect(cell).toHaveText("Mia Arnold")
    await expect(cell).toBeFocused()
  })

  test("\"None\" empties the cell", async ({ tasks }) => {
    const cell = tasks.cell(FIRST, "assignee")
    await openPicker(tasks, FIRST, "assignee")

    await tasks.saves(cell, () => tasks.pickerNone.click())
    await expect(tasks.picker).toHaveCount(0)
    await expect(cell).toHaveText("")
    await expect(cell).toBeFocused()

    // and the picker opens again with nothing selected
    const people = await openPicker(tasks, FIRST, "assignee")
    expect(await people.selectedKeys()).toEqual([])
  })

  test("the record the cell points at already saves nothing", async ({ tasks, pushed }) => {
    const cell = tasks.cell(FIRST, "assignee")
    await openPicker(tasks, FIRST, "assignee")
    await pushed.clear()

    // it is selected as the picker opens
    await tasks.pickerChoose.click()
    await expect(tasks.picker).toHaveCount(0)
    await expect(cell).toHaveText("Kim Ernst")
    await expect(cell).toBeFocused()
    await expect(tasks.status).toHaveText("")
    expect(await pushed.count("picked")).toBe(1)
  })

  test("Escape and Cancel save nothing, and put focus back on the cell", async ({ tasks, pushed }) => {
    const cell = tasks.cell(FIRST, "assignee")
    let people = await openPicker(tasks, FIRST, "assignee")
    await people.cell(await keyOf(people, "name", "Max Member"), "name").click()
    await pushed.clear()

    await tasks.press("Escape")
    await expect(tasks.picker).toHaveCount(0)
    await expect(cell).toBeFocused()
    await expect(cell).toHaveText("Kim Ernst")
    expect(await pushed.count("picker_cancel")).toBe(1)
    expect(await pushed.count("picked")).toBe(0)

    // what was selected there is forgotten
    people = await openPicker(tasks, FIRST, "assignee")
    expect(await people.selectedKeys()).toEqual([await keyOf(people, "name", "Kim Ernst")])
    await tasks.pickerCancel.click()
    await expect(tasks.picker).toHaveCount(0)
    await expect(cell).toBeFocused()
    await expect(cell).toHaveText("Kim Ernst")
  })

  test("a column with a question asks on top of the picker: Cancel comes back to the picker, Confirm saves", async ({
    page,
    tasks,
    pushed,
  }) => {
    const cell = tasks.cell(FIRST, "project")
    const projects = await openPicker(tasks, FIRST, "project")
    const mobile = SEED.project.mobileApp
    await projects.cell(mobile, "name").click()
    await pushed.clear()

    await tasks.pickerChoose.click()
    await expect(tasks.question).toBeVisible()
    await expect(tasks.question.locator("p")).toHaveText("Move this task to another project?")
    // both are modal, the question on top: focus is in it
    expect(await modals(page)).toEqual({ open: ["task-dialog", "task-picker"], focusIn: "task-dialog" })
    await expect(tasks.question.getByRole("button", { name: "Cancel" })).toBeFocused()
    await expect(cell, "nothing is saved yet").toHaveText("Data warehouse")

    // Escape answers Cancel: back in the picker, with the row still selected
    await tasks.press("Escape")
    await expect(tasks.question).toBeHidden()
    await expect(tasks.picker).toBeVisible()
    await expect(tasks.pickerChoose).toBeFocused()
    expect(await projects.selectedKeys()).toEqual([mobile])
    await expect(cell).toHaveText("Data warehouse")

    await tasks.pickerChoose.click()
    await tasks.saves(cell, () => tasks.question.getByRole("button", { name: "Confirm" }).click())
    await expect(tasks.picker).toHaveCount(0)
    await expect(cell).toHaveText("Mobile app")
    await expect(cell).toBeFocused()
    // asked twice, saved once
    expect(await pushed.count("picked")).toBe(3)
  })

  test("and asks nothing for the project the task is in already", async ({ tasks }) => {
    await openPicker(tasks, FIRST, "project")
    await tasks.pickerChoose.click()
    await expect(tasks.picker).toHaveCount(0)
    await expect(tasks.question).toBeHidden()
    await expect(tasks.cell(FIRST, "project")).toBeFocused()
  })

  test.describe("as the member, on a task that is not theirs", () => {
    test.use({ actor: "member" })

    test("the refusal is shown on the cell, with what was chosen; Escape gives it up", async ({ page, tasks }) => {
      const cell = tasks.cell(FIRST, "assignee")
      const people = await openPicker(tasks, FIRST, "assignee")
      // the member is offered no column of what they never see
      expect(await people.columns()).toEqual(["name", "email", "role"])
      await people.cell(await keyOf(people, "name", "Max Member"), "name").click()
      await tasks.saves(cell, () => tasks.pickerChoose.click())

      await expect(tasks.picker).toHaveCount(0)
      await expect(cell).toHaveAttribute("aria-invalid", "true")
      await expect(cell).toContainText("Max Member")
      await expect(cell).toBeFocused()
      await expect(tasks.failure(cell)).toBeVisible()
      await expect(tasks.failure(cell)).toHaveText("You are not allowed to change this.")
      await expect(cell).toHaveAccessibleDescription("You are not allowed to change this.")
      await expect(tasks.status).toHaveText("Assignee was not saved: You are not allowed to change this.")
      await expectNoAxeViolations(page)

      // the picker opens again on the record the row has
      const again = await openPicker(tasks, FIRST, "assignee")
      expect(await again.selectedKeys()).toEqual([await keyOf(again, "name", "Kim Ernst")])
      await tasks.press("Escape")
      await expect(cell).toBeFocused()
      await expect(cell).toHaveAttribute("aria-invalid", "true")

      await tasks.press("Escape")
      await expect(cell).not.toHaveAttribute("aria-invalid")
      await expect(cell).toHaveText("Kim Ernst")
      await expect(cell).toBeFocused()
    })

    test("on a task of their own it saves", async ({ tasks }) => {
      const own = SEED.task.membersOwn
      const cell = tasks.cell(own, "assignee")
      await expect(cell).toHaveText("Max Member")
      const people = await openPicker(tasks, own, "assignee")
      await people.cell(await keyOf(people, "name", "Ada Admin"), "name").click()
      await tasks.saves(cell, () => tasks.pickerChoose.click())
      await expect(cell).toHaveText("Ada Admin")
      await expect(cell).not.toHaveAttribute("aria-invalid")
    })
  })

  test.describe("as the outsider", () => {
    test.use({ actor: "outsider" })

    test("the people and the projects on offer are those of their own organization", async ({ tasks }) => {
      const key = await tasks.rowKey(1)
      const people = await openPicker(tasks, key, "assignee")
      const names = await people.columnTexts("name")
      expect(names).toContain("Olga Outsider")
      for (const acme of ["Ada Admin", "Max Member", "Vera Viewer", "Kim Ernst"]) expect(names).not.toContain(acme)
      await tasks.press("Escape")
      // the picker is gone, and has given the focus back to its cell, before
      // another cell is used: it would take the focus back from there
      await expect(tasks.picker).toHaveCount(0)
      await expect(tasks.cell(key, "assignee")).toBeFocused()

      const projects = await openPicker(tasks, key, "project")
      // Globex has a "Mobile app" of its own: not the one of Acme
      expect((await projects.rowKeys()).length).toBeGreaterThan(0)
      expect(await projects.rowKeys()).not.toContain(SEED.project.mobileApp)
      expect((await projects.rowKeys()).length).toBeLessThan(SEED.projects.acme)
    })
  })
})

test.describe("in a nested table", () => {
  test("a reference cell of the tasks under a project has its own picker; focus goes into it and comes back to the cell", async ({
    page,
  }) => {
    const projects = new Table(page, "project", "/projects")
    await projects.open()
    const nested = await projects.openLine(SEED.project.mobileApp, "tasks")
    const key = await nested.rowKey(1)
    const cell = nested.cell(key, "assignee")
    const before = (await cell.textContent())!.trim()

    await cell.focus()
    await nested.press("Enter")
    await expect(nested.picker).toBeVisible()
    await expect(nested.picker).toHaveAccessibleName("Assignee: choose user")
    const people = nested.pickerTable("assignee")
    await people.ready()

    // the picker's grid is a tree of its own: its tab stop is in it, and
    // the arrow keys stay in it
    expect(await people.hasFocus()).toBe(true)
    expect(await people.tabStops()).toHaveLength(1)
    await nested.press("ArrowDown", "ArrowUp")
    expect(await people.hasFocus()).toBe(true)

    // Escape closes the picker, and does not leave the nested table
    await nested.press("Escape")
    await expect(nested.picker).toHaveCount(0)
    await expect(cell).toBeFocused()

    await nested.press("Enter")
    await expect(nested.picker).toBeVisible()
    await people.ready()
    const name = before === "Pia Graf" ? "Pia Lang" : "Pia Graf"
    await people.cell(await keyOf(people, "name", name), "name").focus()
    await nested.saves(cell, () => nested.press("Enter"))

    await expect(nested.picker).toHaveCount(0)
    await expect(cell).toHaveText(name)
    await expect(cell).toBeFocused()
    // one tab stop for the page's tree of grids, as before
    expect(await projects.tabStops()).toEqual([`${nested.id}-row-${key}-c-assignee`])
    await expectNoAxeViolations(page)
  })
})

test.describe("in the action panel", () => {
  test("the field of a key says what the record is called, and its button opens the picker on top of the panel", async ({
    page,
    tasks,
    pushed,
  }) => {
    await tasks.acts(FIRST, () => tasks.action(FIRST, "reassign").click())
    await expect(tasks.field("assignee_id")).toHaveRole("group")
    await expect(tasks.field("assignee_id")).toHaveAccessibleName("Assignee")
    await expect(tasks.fieldChosen("assignee_id")).toHaveText("Kim Ernst")
    await expect(tasks.fieldChoose("assignee_id")).toHaveText("Choose")
    await expect(tasks.fieldChoose("assignee_id")).toHaveAccessibleDescription("Kim Ernst")
    await expect(tasks.fieldChoose("assignee_id")).toBeFocused()
    await tasks.field("reason").fill("Back from leave")
    await tasks.panelSettled()
    await pushed.clear()

    await tasks.fieldChoose("assignee_id").focus()
    await tasks.press("Enter")
    await expect(tasks.picker).toBeVisible()
    await expect(tasks.picker).toHaveAccessibleName("Assignee: choose user")
    const people = tasks.pickerTable("assignee_id")
    await people.ready()
    expect(await pushed.count("pick_input")).toBe(1)

    // both are modal, the picker on top: focus is in it, on the record the field holds
    expect(await modals(page)).toEqual({ open: ["task-panel", "task-picker"], focusIn: "task-picker" })
    const kim = await keyOf(people, "name", "Kim Ernst")
    await expect(people.cell(kim, "name")).toBeFocused()
    expect(await people.selectedKeys()).toEqual([kim])
    // as wide as a table needs, over the panel
    expect((await tasks.picker.boundingBox())!.width).toBeGreaterThan((await tasks.panel.boundingBox())!.width)

    // Escape closes the picker alone: the panel is as it was, with focus on the button
    await tasks.press("Escape")
    await expect(tasks.picker).toHaveCount(0)
    await expect(tasks.panel).toBeVisible()
    await expect(tasks.fieldChoose("assignee_id")).toBeFocused()
    await expect(tasks.field("reason")).toHaveValue("Back from leave")
    await expect(tasks.fieldChosen("assignee_id")).toHaveText("Kim Ernst")
    expect(await pushed.count("panel_cancel")).toBe(0)

    // chosen from the keyboard: Enter on the button, down to a row, Enter
    await tasks.press("Enter")
    await expect(tasks.picker).toBeVisible()
    await people.ready()
    await tasks.press("ArrowDown")
    const max = await keyOf(people, "name", "Max Member")
    await expect(people.cell(max, "name")).toBeFocused()
    await tasks.press("Enter")

    await expect(tasks.picker).toHaveCount(0)
    await expect(tasks.fieldChosen("assignee_id")).toHaveText("Max Member")
    await expect(tasks.fieldKey("assignee_id")).toHaveValue(max)
    await expect(tasks.fieldChoose("assignee_id")).toBeFocused()
    await expect(tasks.field("reason"), "what else was typed is still there").toHaveValue("Back from leave")
    await expect(tasks.cell(FIRST, "assignee"), "nothing has run").toHaveText("Kim Ernst")

    // the panel's own button runs the action
    await tasks.panelSubmit.click()
    await expect(tasks.panel).toHaveCount(0)
    await expect(tasks.cell(FIRST, "assignee")).toHaveText("Max Member")
    await expect(tasks.status).toHaveText("Reassign: done")
  })

  test("\"None\" empties the field; what is typed after a choice is kept with it", async ({ tasks }) => {
    await tasks.acts(FIRST, () => tasks.action(FIRST, "reassign").click())
    await tasks.fieldChoose("assignee_id").click()
    await expect(tasks.picker).toBeVisible()
    await tasks.pickerNone.click()

    await expect(tasks.picker).toHaveCount(0)
    await expect(tasks.fieldChosen("assignee_id")).toHaveCount(0)
    await expect(tasks.fieldKey("assignee_id")).toHaveValue("")
    await expect(tasks.fieldChoose("assignee_id")).toBeFocused()

    await tasks.field("reason").fill("Nobody has the time")
    await tasks.panelSettled()
    await expect(tasks.fieldKey("assignee_id")).toHaveValue("")
    await tasks.panelSubmit.click()
    await expect(tasks.panel).toHaveCount(0)
    await expect(tasks.cell(FIRST, "assignee")).toHaveText("")
  })

  test("the create panel: a required key has no \"None\"; a task is created with what was chosen, and array values typed before are kept", async ({
    page,
    tasks,
  }) => {
    await tasks.create.click()
    await tasks.field("title").fill("Made with the picker")
    const tags = tasks.field("tags")
    await tags.getByRole("button", { name: "Add value" }).click()
    await page.keyboard.type("picked")
    await tasks.panelSettled()

    await tasks.fieldChoose("project_id").click()
    await expect(tasks.picker).toHaveAccessibleName("Project: choose project")
    await expect(tasks.pickerNone).toHaveCount(0)
    const projects = tasks.pickerTable("project_id")
    await projects.ready()
    expect(await projects.selectedKeys()).toEqual([])
    await expect(tasks.pickerChoose).toHaveAttribute("aria-disabled", "true")
    await projects.cell(SEED.project.mobileApp, "name").dblclick()
    await expect(tasks.picker).toHaveCount(0)
    await expect(tasks.fieldChosen("project_id")).toHaveText("Mobile app")

    await tasks.chooseField("assignee_id", await pickKey(tasks, "assignee_id", "Pia Lang"))
    await expect(tasks.fieldChosen("assignee_id")).toHaveText("Pia Lang")
    // the first choice, the title and the tag are still there
    await expect(tasks.fieldChosen("project_id")).toHaveText("Mobile app")
    await expect(tasks.field("title")).toHaveValue("Made with the picker")
    await expect(tags.getByRole("textbox", { name: "Tags 1", exact: true })).toHaveValue("picked")

    await tasks.panelSubmit.click()
    await expect(tasks.panel).toHaveCount(0)
    const created = await tasks.rowKey(1)
    await expect(tasks.cell(created, "title")).toHaveText("Made with the picker")
    await expect(tasks.cell(created, "project")).toHaveText("Mobile app")
    await expect(tasks.cell(created, "assignee")).toHaveText("Pia Lang")
    await expect(tasks.cell(created, "tags")).toHaveText("picked")
  })

  test("the panel of an action on the selected rows chooses once for all of them", async ({ tasks }) => {
    await tasks.box(FIRST).click()
    await tasks.box(SECOND).click()
    await tasks.bulk("reassign").click()
    await expect(tasks.panel).toBeVisible()
    await expect(tasks.fieldChosen("assignee_id")).toHaveCount(0)

    await tasks.chooseField("assignee_id", await pickKey(tasks, "assignee_id", "Fay Maier"))
    await expect(tasks.fieldChosen("assignee_id")).toHaveText("Fay Maier")
    await tasks.field("reason").fill("Spring cleaning")
    await tasks.panelSettled()
    await tasks.panelSubmit.click()
    await tasks.question.getByRole("button", { name: "Confirm" }).click()

    await expect(tasks.result).toHaveText("Reassign: 2 done.")
    await expect(tasks.cell(FIRST, "assignee")).toHaveText("Fay Maier")
    await expect(tasks.cell(SECOND, "assignee")).toHaveText("Fay Maier")
  })
})

/** Opens the picker of a field of the panel, reads the key of a row by its name, and closes it again. */
async function pickKey(tasks: Table, field: string, name: string): Promise<string> {
  await tasks.fieldChoose(field).click()
  await expect(tasks.picker).toBeVisible()
  const table = tasks.pickerTable(field)
  await table.ready()
  const key = await keyOf(table, "name", name)
  await tasks.pickerCancel.click()
  await expect(tasks.picker).toHaveCount(0)
  return key
}

test.describe("on a narrow window", () => {
  test("the picker is as wide as the window, and its table scrolls in it", async ({ page, tasks }) => {
    await page.setViewportSize({ width: 390, height: 700 })
    await tasks.open()
    const people = await openPicker(tasks, FIRST, "assignee")

    const box = (await tasks.picker.boundingBox())!
    expect(box.x).toBeCloseTo(0, 0)
    expect(box.width).toBeCloseTo(390, 0)
    expect(await people.hookRoot.evaluate((grid) => grid.scrollWidth > grid.clientWidth)).toBe(true)
    await tasks.pickerChoose.scrollIntoViewIfNeeded()
    await expect(tasks.pickerChoose).toBeInViewport()
    await expectNoAxeViolations(page)
  })
})

test.describe("in German", () => {
  test("the picker and the field of the panel", async ({ page, tasks }) => {
    await switchLocale(page, "de")
    await tasks.ready()

    const people = await openPicker(tasks, FIRST, "assignee")
    await expect(tasks.picker).toHaveAccessibleName("Zugewiesen an: Person auswählen")
    await expect(people.grid).toHaveAccessibleName("Personen")
    await expect(tasks.pickerCancel).toHaveText("Abbrechen")
    await expect(tasks.pickerNone).toHaveText("Keine Auswahl")
    await expect(tasks.pickerChoose).toHaveText("Auswählen")
    await expect(people.radio(await people.rowKey(1))).toHaveAccessibleName("Zeile auswählen")
    await expectNoAxeViolations(page)
    await tasks.press("Escape")

    await tasks.create.click()
    await expect(tasks.field("project_id")).toHaveAccessibleName(/^Projekt\s+erforderlich$/)
    await expect(tasks.fieldChoose("project_id")).toHaveText("Auswählen")
    await tasks.fieldChoose("project_id").click()
    await expect(tasks.picker).toHaveAccessibleName("Projekt: Projekt auswählen")
    await expectNoAxeViolations(page)
    await tasks.press("Escape")
    await tasks.press("Escape")

    await switchLocale(page, "en")
  })
})

// axe-core on every state this file brings a table into, in both themes.
for (const theme of ["light", "dark"] as const) {
  test.describe(`axe, in the ${theme} theme`, () => {
    test.beforeEach(async ({ page, tasks }) => {
      await page.addInitScript((theme) => localStorage.setItem("phx:theme", theme), theme)
      await tasks.open()
      await expect(page.locator("html")).toHaveAttribute("data-theme", theme)
    })

    test("the picker open, with a row selected, and with focus on its buttons", async ({ page, tasks }) => {
      const people = await openPicker(tasks, FIRST, "assignee")
      await expectNoAxeViolations(page)

      await people.cell(await keyOf(people, "name", "Max Member"), "name").click()
      await expectNoAxeViolations(page)

      await tasks.pickerChoose.focus()
      await expectNoAxeViolations(page)
    })

    test("the picker with nothing selected, with a filter that finds nothing, and with the column's question on top", async ({
      page,
      tasks,
    }) => {
      const projects = await openPicker(tasks, FIRST, "project")
      await projects.reads(async () => {
        await projects.filterValue("name").fill("no such project")
        await projects.filterValue("name").press("Enter")
      })
      await expect(projects.empty).toBeVisible()
      await expectNoAxeViolations(page)

      await projects.reads(() => projects.clearFilters.click())
      await projects.cell(SEED.project.mobileApp, "name").click()
      await tasks.pickerChoose.click()
      await expect(tasks.question).toBeVisible()
      await expectNoAxeViolations(page)
    })

    test("the panel with the fields of keys, with a record chosen, and the picker on top of it", async ({
      page,
      tasks,
    }) => {
      await tasks.create.click()
      await expect(tasks.field("title")).toBeFocused()
      await expectNoAxeViolations(page)

      await tasks.chooseField("project_id", SEED.project.mobileApp)
      await expect(tasks.fieldChosen("project_id")).toHaveText("Mobile app")
      await expectNoAxeViolations(page)

      await tasks.fieldChoose("assignee_id").click()
      await expect(tasks.picker).toBeVisible()
      await tasks.pickerTable("assignee_id").ready()
      await expectNoAxeViolations(page)
    })

    test("the panel after Create with the required key left empty", async ({ page, tasks }) => {
      await tasks.create.click()
      await tasks.field("title").fill("Without a project")
      await tasks.panelSubmit.click()
      await expect(tasks.fieldError("project_id")).toBeVisible()
      await expectNoAxeViolations(page)
    })

    test.describe("as the member", () => {
      test.use({ actor: "member" })

      test("a cell whose choice was refused, with its message showing", async ({ page, tasks }) => {
        const cell = tasks.cell(FIRST, "assignee")
        const people = await openPicker(tasks, FIRST, "assignee")
        await people.cell(await keyOf(people, "name", "Max Member"), "name").click()
        await tasks.saves(cell, () => tasks.pickerChoose.click())
        await expect(tasks.failure(cell)).toBeVisible()
        await expectNoAxeViolations(page)
      })
    })
  })
}

test("the radio button of a row has an edge of enough contrast, in both themes", async ({ page, tasks }) => {
  const people = await openPicker(tasks, FIRST, "assignee")
  const unselected = await keyOf(people, "name", "Ada Admin")
  for (const theme of ["light", "dark"] as const) {
    await page.evaluate((theme) => {
      localStorage.setItem("phx:theme", theme)
      document.documentElement.setAttribute("data-theme", theme)
    }, theme)
    expect(await contrastOf(people.radio(unselected), "border"), `a row's radio button, ${theme}`).toBeGreaterThanOrEqual(3)
  }
  await page.evaluate(() => localStorage.removeItem("phx:theme"))
})

test("a row that names no record this person may read is not taken: nothing is saved, and the picker says so", async ({
  page,
  tasks,
  pushed,
}) => {
  const cell = tasks.cell(FIRST, "assignee")
  const people = await openPicker(tasks, FIRST, "assignee")
  const max = await keyOf(people, "name", "Max Member")

  // as somebody does who alters the page: the row is given the key of a
  // record that is none of the people on offer
  await people.row(max).evaluate((row, id) => {
    row.id = `${id}-row-4f0e6f66-0000-4000-8000-000000000000`
  }, people.id)
  await page.locator(`[id="${people.id}-row-4f0e6f66-0000-4000-8000-000000000000"] input[type=radio]`).click()
  await pushed.clear()
  await tasks.pickerChoose.click()

  await expect(tasks.pickerError).toHaveText(GONE)
  await expect(tasks.pickerError).toHaveRole("alert")
  await expect(tasks.picker).toBeVisible()
  expect(await pushed.count("picked")).toBe(1)
  await expectNoAxeViolations(page)

  await tasks.press("Escape")
  await expect(tasks.picker).toHaveCount(0)
  await expect(cell).toHaveText("Kim Ernst")
  await expect(cell).not.toHaveAttribute("aria-invalid")
  await tasks.open()
  await expect(cell).toHaveText("Kim Ernst")
})
