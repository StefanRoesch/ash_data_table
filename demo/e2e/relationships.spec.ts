import type { Page } from "@playwright/test"
import { expectNoAxeViolations } from "./support/a11y"
import { SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { switchLocale } from "./support/locale"
import { Table } from "./support/table"

// Relationships an action manages, in a browser. "Set labels" of /tasks
// takes the labels of a task as an argument, which its action hands to the
// relationship: the panel lists the task's labels, each with a button that
// takes it out again, and "Choose" opens the picker, the table of the labels,
// in which any number of rows is selected. And "Assignee" of /deadlines is a
// reference cell that is edited through an argument.

const FIRST = SEED.task.first
const SECOND = SEED.task.second

/** The modal dialogs that are open, as they stand in the page, and the one focus is in. */
async function modals(page: Page): Promise<{ open: string[]; focusIn: string | null }> {
  return page.evaluate(() => {
    const open = Array.from(document.querySelectorAll("dialog:modal")).map((dialog) => dialog.id)
    const active = document.activeElement
    const within = active && active.closest("dialog")
    return { open, focusIn: within ? within.id : null }
  })
}

/** The key of the row of a table whose cell of a column reads `text`. */
async function keyOf(table: Table, column: string, text: string): Promise<string> {
  const keys = await table.rowKeys()
  const texts = await table.columnTexts(column)
  const index = texts.findIndex((shown) => shown.trim() === text)
  expect(index, `a row whose ${column} is ${text}`).toBeGreaterThanOrEqual(0)
  return keys[index]
}

/** Opens the panel of "Set labels" for a task, and says what its field lists. */
async function openSetLabels(tasks: Table, key: string): Promise<string[]> {
  await tasks.acts(key, () => tasks.action(key, "set_labels").click())
  await expect(tasks.panel).toBeVisible()
  return (await tasks.fieldChosenItems("labels").allTextContents()).map((text) => text.trim())
}

/** Opens the picker of the panel's labels, and waits for its table. */
async function openLabels(tasks: Table): Promise<Table> {
  await tasks.fieldChoose("labels").click()
  await expect(tasks.picker).toBeVisible()
  const labels = tasks.pickerTable("labels")
  await labels.ready()
  return labels
}

/** A label of the picker's table that the field does not hold yet. */
async function another(labels: Table, held: string[]): Promise<{ key: string; name: string }> {
  const names = (await labels.columnTexts("name")).map((text) => text.trim())
  const name = names.find((name) => !held.includes(name))
  expect(name, "a label the task does not carry").toBeTruthy()
  return { key: await keyOf(labels, "name", name!), name: name! }
}

test.beforeEach(async ({ tasks }) => {
  await tasks.open()
})

test.describe("the field of an argument that holds several related records", () => {
  test.use({ writes: true })

  test("lists the task's labels in a group named by the argument, each with a button that takes it out, and a button that opens the picker", async ({
    tasks,
  }) => {
    const held = await openSetLabels(tasks, FIRST)

    await expect(tasks.panelTitle).toHaveText(/^Set labels: /)
    await expect(tasks.field("labels")).toHaveRole("group")
    await expect(tasks.field("labels")).toHaveAccessibleName("Labels")
    await expect(tasks.fieldChoose("labels")).toHaveText("Choose")
    await expect(tasks.fieldKey("labels")).toHaveCount(held.length)

    for (const [index, name] of held.entries()) {
      await expect(tasks.fieldRemove("labels", index)).toHaveAccessibleName(`Remove ${name}`)
    }

    // nothing of a picker is in the page until one is opened
    await expect(tasks.picker).toHaveCount(0)
  })

  test("\"Choose\" opens the table of the labels on top of the panel, with the rows of the task's labels selected; a choice is listed, and \"Run\" saves it", async ({
    page,
    tasks,
    pushed,
  }) => {
    const held = await openSetLabels(tasks, FIRST)
    await pushed.clear()

    const labels = await openLabels(tasks)
    expect(await pushed.count("pick_input")).toBe(1)
    await expect(tasks.picker).toHaveAccessibleName("Labels: choose label")
    expect(await modals(page)).toEqual({ open: ["task-panel", "task-picker"], focusIn: "task-picker" })

    // any number of rows: a box per row, and no "None"
    await expect(labels.grid).toHaveAttribute("aria-multiselectable", "true")
    await expect(labels.boxes).toHaveCount(SEED.labels.acme)
    await expect(tasks.pickerNone).toHaveCount(0)
    await expect(tasks.pickerChoose).toHaveAttribute("aria-disabled", "false")

    // the rows of the labels the task carries are selected, and counted
    const selected = await labels.selectedKeys()
    expect(selected).toHaveLength(held.length)
    const names = (await labels.columnTexts("name")).map((text) => text.trim())
    const keys = await labels.rowKeys()
    expect(selected.map((key) => names[keys.indexOf(key)]).sort()).toEqual([...held].sort())
    if (held.length > 0) await expect(labels.selectedCount).toHaveText(`${held.length} selected`)

    // one more, with a click anywhere on its row
    const added = await another(labels, held)
    await pushed.clear()
    await labels.cell(added.key, "name").click()
    await expect(labels.box(added.key)).toBeChecked()
    await expect(labels.selectedCount).toHaveText(`${held.length + 1} selected`)
    await pushed.expectSelected(labels)
    expect(await pushed.besides("select"), "selecting sends nothing but what is selected").toEqual([])

    await tasks.pickerChoose.click()
    await expect(tasks.picker).toHaveCount(0)
    expect(await pushed.count("picked")).toBe(1)
    await expect(tasks.fieldChoose("labels")).toBeFocused()
    await expect(tasks.fieldChosenItems("labels")).toHaveText([...held, added.name])

    // nothing has run: the panel's own button does
    await tasks.panelSubmit.click()
    await expect(tasks.panel).toHaveCount(0)
    await expect(tasks.status).toHaveText("Set labels: done")

    expect((await openSetLabels(tasks, FIRST)).sort()).toEqual([...held, added.name].sort())
  })

  test("the button of a label takes it out, and focus goes to what stands in its place; \"Run\" takes it off the task", async ({
    tasks,
    pushed,
  }) => {
    // a task with two labels at least: the first gets one more first
    let held = await openSetLabels(tasks, FIRST)
    while (held.length < 2) {
      const labels = await openLabels(tasks)
      await labels.cell((await another(labels, held)).key, "name").click()
      await tasks.pickerChoose.click()
      await expect(tasks.picker).toHaveCount(0)
      held = (await tasks.fieldChosenItems("labels").allTextContents()).map((text) => text.trim())
    }
    await pushed.clear()

    // from the keyboard: the button is a button
    await tasks.fieldRemove("labels", 0).focus()
    await tasks.press("Enter")
    await expect(tasks.fieldChosenItems("labels")).toHaveText(held.slice(1))
    expect(await pushed.count("panel_unpick")).toBe(1)
    // the label that stood after it stands in its place
    await expect(tasks.fieldRemove("labels", 0)).toBeFocused()
    await expect(tasks.fieldRemove("labels", 0)).toHaveAccessibleName(`Remove ${held[1]}`)

    // the last of them: focus goes to the one before it
    await tasks.fieldRemove("labels", held.length - 2).click()
    await expect(tasks.fieldChosenItems("labels")).toHaveText(held.slice(1, -1))
    if (held.length > 2) await expect(tasks.fieldRemove("labels", held.length - 3)).toBeFocused()
    else await expect(tasks.fieldChoose("labels")).toBeFocused()

    await tasks.panelSubmit.click()
    await expect(tasks.panel).toHaveCount(0)
    expect((await openSetLabels(tasks, FIRST)).sort()).toEqual(held.slice(1, -1).sort())
  })

  test("with every label taken out, \"Run\" leaves the task without labels", async ({ tasks }) => {
    const held = await openSetLabels(tasks, FIRST)
    const labels = await openLabels(tasks)
    if (held.length === 0) await labels.cell(await labels.rowKey(1), "name").click()
    else await labels.clearSelection.click()
    expect(await labels.selectedKeys()).toHaveLength(held.length === 0 ? 1 : 0)
    await tasks.pickerChoose.click()
    await expect(tasks.picker).toHaveCount(0)

    if (held.length === 0) {
      await tasks.fieldRemove("labels", 0).click()
    }
    await expect(tasks.fieldChosenItems("labels")).toHaveCount(0)
    await expect(tasks.fieldKey("labels")).toHaveCount(0)

    await tasks.panelSubmit.click()
    await expect(tasks.panel).toHaveCount(0)
    expect(await openSetLabels(tasks, FIRST)).toEqual([])
  })
})

test.describe("the picker for several records, from the keyboard", () => {
  test.use({ writes: true })

  test("Enter on the field's button opens it; Space selects a row and takes it out; Enter on a row chooses nothing; \"Choose\" takes what is selected", async ({
    tasks,
    pushed,
  }) => {
    const held = await openSetLabels(tasks, SECOND)
    await tasks.fieldChoose("labels").focus()
    await tasks.press("Enter")
    await expect(tasks.picker).toBeVisible()
    const labels = tasks.pickerTable("labels")
    await labels.ready()
    expect(await labels.hasFocus()).toBe(true)

    // to a row that is not selected, by the arrow keys
    const added = await another(labels, held)
    await labels.cell(added.key, "name").focus()
    await pushed.clear()

    await tasks.press("Space")
    await expect(labels.box(added.key)).toBeChecked()
    await tasks.press("Space")
    await expect(labels.box(added.key)).not.toBeChecked()
    await tasks.press("Space")
    await expect(labels.box(added.key)).toBeChecked()

    // where several are chosen there is no one row to take at once
    await tasks.press("Enter")
    await expect(tasks.picker).toBeVisible()
    await expect(labels.box(added.key)).toBeChecked()
    await pushed.expectSelected(labels)
    expect(await pushed.besides("select"), "nothing was sent but what is selected").toEqual([])

    // Tab leaves the grid for the picker's buttons
    await tasks.pickerChoose.focus()
    await tasks.press("Enter")
    await expect(tasks.picker).toHaveCount(0)
    await expect(tasks.fieldChoose("labels")).toBeFocused()
    await expect(tasks.fieldChosenItems("labels")).toHaveText([...held, added.name])
  })

  test("Escape closes the picker alone, and the field is as it was; a double click on a row chooses nothing", async ({
    tasks,
  }) => {
    const held = await openSetLabels(tasks, SECOND)
    const labels = await openLabels(tasks)
    const added = await another(labels, held)

    await labels.cell(added.key, "name").dblclick()
    await expect(tasks.picker).toBeVisible()
    // two clicks: selected, and taken out again
    await expect(labels.box(added.key)).not.toBeChecked()

    await labels.cell(added.key, "name").click()
    await expect(labels.box(added.key)).toBeChecked()
    await tasks.press("Escape")

    await expect(tasks.picker).toHaveCount(0)
    await expect(tasks.panel).toBeVisible()
    await expect(tasks.fieldChoose("labels")).toBeFocused()
    await expect(tasks.fieldChosenItems("labels")).toHaveText(held)
  })

  test("Shift with Down Arrow selects the rows it passes, and the box of the header all rows of the page, as in any table with boxes", async ({
    tasks,
    pushed,
  }) => {
    const held = await openSetLabels(tasks, SECOND)
    const labels = await openLabels(tasks)
    if (held.length > 0) await labels.clearSelection.click()
    expect(await labels.selectedKeys()).toEqual([])
    const keys = await labels.rowKeys()
    await pushed.clear()

    await labels.cell(keys[0], "name").focus()
    await tasks.press("Shift+ArrowDown", "Shift+ArrowDown")
    expect(await labels.selectedKeys()).toEqual(keys.slice(0, 3))
    await pushed.expectSelected(labels)
    await expect(labels.selectedCount).toHaveText("3 selected")

    await labels.pageBox.click()
    expect(await labels.selectedKeys()).toEqual(keys)
    await labels.pageBox.click()
    expect(await labels.selectedKeys()).toEqual([])

    // a click on a row, and Shift with a click on another: the rows between them too
    await labels.cell(keys[1], "name").click()
    await labels.cell(keys[3], "name").click({ modifiers: ["Shift"] })
    expect(await labels.selectedKeys()).toEqual(keys.slice(1, 4))
    await labels.clearSelection.click()
    expect(await labels.selectedKeys()).toEqual([])
    await pushed.expectSelected(labels)
    expect(await pushed.besides("select"), "selecting sends nothing but what is selected").toEqual([])

    // nothing selected is a choice: of no label
    await tasks.pickerChoose.click()
    await expect(tasks.picker).toHaveCount(0)
    await expect(tasks.fieldChosenItems("labels")).toHaveCount(0)
  })

  test("what is selected is kept while the table is filtered, and taken with what the filter hides", async ({
    tasks,
  }) => {
    const held = await openSetLabels(tasks, FIRST)
    const labels = await openLabels(tasks)
    const added = await another(labels, held)
    await labels.cell(added.key, "name").click()
    await expect(labels.selectedCount).toHaveText(`${held.length + 1} selected`)

    // a filter that finds one label, and not the one that was added
    const names = (await labels.columnTexts("name")).map((text) => text.trim())
    const other = names.find((name) => name !== added.name)!
    await labels.reads(async () => {
      await labels.filterValue("name").fill(other)
      await labels.filterValue("name").press("Enter")
    })
    await expect(labels.rows).toHaveCount(1)
    await expect(labels.selectedCount).toHaveText(`${held.length + 1} selected`)
    // never "all that match"
    await expect(labels.selectAll).toBeHidden()

    await tasks.pickerChoose.click()
    await expect(tasks.picker).toHaveCount(0)
    await expect(tasks.fieldChosenItems("labels")).toHaveText([...held, added.name])
  })
})

test.describe("on the selected rows", () => {
  test.use({ writes: true })

  test("\"Set labels\" starts with an empty field, and gives every selected task the labels that are chosen", async ({
    tasks,
  }) => {
    await tasks.box(FIRST).click()
    await tasks.box(SECOND).click()
    await tasks.bulk("set_labels").click()

    await expect(tasks.panelTitle).toHaveText("Set labels: 2 records")
    await expect(tasks.fieldChosenItems("labels")).toHaveCount(0)

    const labels = await openLabels(tasks)
    expect(await labels.selectedKeys()).toEqual([])
    const first = await labels.rowKey(1)
    const name = (await labels.cell(first, "name").textContent())!.trim()
    await labels.box(first).click()
    await tasks.pickerChoose.click()
    await expect(tasks.fieldChosenItems("labels")).toHaveText([name])

    await tasks.panelSubmit.click()
    await expect(tasks.question).toBeVisible()
    await expect(tasks.question.locator("p")).toHaveText("Run “Set labels” on 2 records?")
    await tasks.question.getByRole("button", { name: "Confirm" }).click()
    await expect(tasks.result).toContainText("Set labels: 2 done.")

    expect(await openSetLabels(tasks, FIRST)).toEqual([name])
    await tasks.press("Escape")
    await expect(tasks.panel).toHaveCount(0)
    expect(await openSetLabels(tasks, SECOND)).toEqual([name])
  })
})

test.describe("as the member, on a task that is not theirs", () => {
  test.use({ actor: "member" })

  test("the panel shows the labels, and \"Run\" is refused: the panel says so and stays open", async ({
    page,
    tasks,
  }) => {
    const held = await openSetLabels(tasks, FIRST)
    const labels = await openLabels(tasks)
    await labels.cell((await another(labels, held)).key, "name").click()
    await tasks.pickerChoose.click()
    await expect(tasks.picker).toHaveCount(0)

    await tasks.panelSubmit.click()
    await expect(tasks.panelErrors).toHaveText("You are not allowed to do this.")
    await expect(tasks.panelErrors).toHaveRole("alert")
    await expect(tasks.panel).toBeVisible()
    await expectNoAxeViolations(page)
  })
})

test.describe("a reference cell that is edited through an argument: the assignee of /deadlines", () => {
  test.use({ writes: true })

  const inDays = (days: number) => new Date(Date.now() + days * 86_400_000).toISOString().slice(0, 10)

  test("Enter opens the picker on the person the task is assigned to; a choice saves through the column's action", async ({
    page,
    pushed,
  }) => {
    const deadlines = new Table(page, "deadline", "/deadlines")
    await deadlines.open(`/deadlines?deadline[a][by]=${inDays(60)}`)

    // a task that is assigned to somebody
    const keys = await deadlines.rowKeys()
    const assignees = (await deadlines.columnTexts("assignee")).map((text) => text.trim())
    const index = assignees.findIndex((name) => name !== "")
    expect(index).toBeGreaterThanOrEqual(0)
    const key = keys[index]
    const cell = deadlines.cell(key, "assignee")
    await expect(cell).not.toHaveAttribute("aria-readonly")

    await cell.focus()
    await pushed.clear()
    await deadlines.press("Enter")
    await expect(deadlines.picker).toBeVisible()
    await expect(deadlines.picker).toHaveAccessibleName("Assignee: choose user")
    expect(await pushed.count("pick")).toBe(1)

    const people = deadlines.pickerTable("assignee")
    await people.ready()
    // one row at a time, opened on the assignee
    await expect(people.grid).toHaveAttribute("aria-multiselectable", "false")
    const current = await keyOf(people, "name", assignees[index])
    expect(await people.selectedKeys()).toEqual([current])
    await expect(deadlines.pickerNone).toBeVisible()
    await expectNoAxeViolations(page)

    const names = (await people.columnTexts("name")).map((text) => text.trim())
    const other = names.find((name) => name !== assignees[index])!
    await people.cell(await keyOf(people, "name", other), "name").click()
    await deadlines.saves(cell, () => deadlines.pickerChoose.click())

    await expect(deadlines.picker).toHaveCount(0)
    await expect(cell).toHaveText(other)
    await expect(cell).not.toHaveAttribute("aria-invalid")
    await expect(cell).toBeFocused()

    // and it is saved: the page says the same after a reload
    await deadlines.open(`/deadlines?deadline[a][by]=${inDays(60)}`)
    await expect(deadlines.cell(key, "assignee")).toHaveText(other)

    // "None" takes the assignee away
    await deadlines.cell(key, "assignee").focus()
    await deadlines.press("Enter")
    await expect(deadlines.picker).toBeVisible()
    await deadlines.saves(deadlines.cell(key, "assignee"), () => deadlines.pickerNone.click())
    await expect(deadlines.cell(key, "assignee")).toHaveText("")
  })
})

test.describe("in German", () => {
  test("the field, its buttons and the picker", async ({ page, tasks }) => {
    await switchLocale(page, "de")
    await tasks.ready()

    await tasks.acts(FIRST, () => tasks.action(FIRST, "set_labels").click())
    await expect(tasks.panelTitle).toHaveText(/^Labels setzen: /)
    await expect(tasks.field("labels")).toHaveAccessibleName("Labels")
    await expect(tasks.fieldChoose("labels")).toHaveText("Auswählen")

    const labels = await openLabels(tasks)
    await expect(tasks.picker).toHaveAccessibleName("Labels: Label auswählen")
    await expect(tasks.pickerCancel).toHaveText("Abbrechen")
    await expect(tasks.pickerChoose).toHaveText("Auswählen")
    await expect(labels.box(await labels.rowKey(1))).toHaveAccessibleName("Zeile auswählen")

    // a label that is in the field has a button that says so in German
    const first = await labels.rowKey(1)
    const name = (await labels.cell(first, "name").textContent())!.trim()
    if (!(await labels.box(first).isChecked())) await labels.box(first).click()
    await tasks.pickerChoose.click()
    await expect(tasks.picker).toHaveCount(0)
    const items = (await tasks.fieldChosenItems("labels").allTextContents()).map((text) => text.trim())
    await expect(tasks.fieldRemove("labels", items.indexOf(name))).toHaveAccessibleName(`${name} entfernen`)
    await expectNoAxeViolations(page)

    await tasks.press("Escape")
    await switchLocale(page, "en")
  })
})

// axe-core on every state this file brings a table into, in both themes.
for (const theme of ["light", "dark"] as const) {
  test.describe(`axe, in the ${theme} theme`, () => {
    test.use({ writes: true })

    test.beforeEach(async ({ page, tasks }) => {
      await page.addInitScript((theme) => localStorage.setItem("phx:theme", theme), theme)
      await tasks.open()
      await expect(page.locator("html")).toHaveAttribute("data-theme", theme)
    })

    test("the panel with the field of the labels, with focus on its buttons, and with a label taken out", async ({
      page,
      tasks,
    }) => {
      let held = await openSetLabels(tasks, FIRST)
      if (held.length === 0) {
        const labels = await openLabels(tasks)
        await labels.cell(await labels.rowKey(1), "name").click()
        await tasks.pickerChoose.click()
        await expect(tasks.picker).toHaveCount(0)
        held = (await tasks.fieldChosenItems("labels").allTextContents()).map((text) => text.trim())
      }
      await expectNoAxeViolations(page)

      await tasks.fieldRemove("labels", 0).focus()
      await expectNoAxeViolations(page)

      await tasks.fieldRemove("labels", 0).click()
      await expect(tasks.fieldChosenItems("labels")).toHaveCount(held.length - 1)
      await expectNoAxeViolations(page)
    })

    test("the picker for several on top of the panel: as it opens, with another row selected, with a filter that finds nothing, and with focus on \"Choose\"", async ({
      page,
      tasks,
    }) => {
      const held = await openSetLabels(tasks, FIRST)
      const labels = await openLabels(tasks)
      await expectNoAxeViolations(page)

      await labels.cell((await another(labels, held)).key, "name").click()
      await expectNoAxeViolations(page)

      await labels.reads(async () => {
        await labels.filterValue("name").fill("no such label")
        await labels.filterValue("name").press("Enter")
      })
      await expect(labels.empty).toBeVisible()
      await expectNoAxeViolations(page)

      await tasks.pickerChoose.focus()
      await expectNoAxeViolations(page)
    })
  })
}

test("a row that names no label this person may read is not taken: nothing is chosen, and the picker says so", async ({
  page,
  tasks,
  pushed,
}) => {
  const held = await openSetLabels(tasks, FIRST)
  const labels = await openLabels(tasks)
  const added = await another(labels, held)

  // as somebody does who alters the page: the row is given the key of a
  // record that is none of the labels on offer
  await labels.row(added.key).evaluate((row, id) => {
    row.id = `${id}-row-4f0e6f66-0000-4000-8000-000000000000`
  }, labels.id)
  await page.locator(`[id="${labels.id}-row-4f0e6f66-0000-4000-8000-000000000000"] input[type=checkbox]`).click()
  await pushed.clear()
  await tasks.pickerChoose.click()

  await expect(tasks.pickerError).toHaveText("This record is no longer available.")
  await expect(tasks.pickerError).toHaveRole("alert")
  await expect(tasks.picker).toBeVisible()
  expect(await pushed.count("picked")).toBe(1)
  await expectNoAxeViolations(page)

  await tasks.press("Escape")
  await expect(tasks.picker).toHaveCount(0)
  await expect(tasks.fieldChosenItems("labels")).toHaveText(held)
})
