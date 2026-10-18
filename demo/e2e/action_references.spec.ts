import { expectNoAxeViolations } from "./support/a11y"
import { MAPS, SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { switchLocale } from "./support/locale"
import { Table } from "./support/table"

// Arguments of generic actions whose records are chosen in the picker,
// because the `action` of the table block says which resource the argument
// refers to (`reference`). Nothing in Ash says it of a key such as
// `argument :into, :uuid`, and without it the key would be typed.
//
// /labels has "Merge", a table action with one key and a list of keys, both
// of labels: the first is chosen as the record of a reference cell is, the
// second as the labels of a task are. /projects has "Assign open tasks" in
// every row: a generic action that the table gives the row's key, and that
// takes the key of a person besides. As the admin, who may run both. These
// tests change the data.

const PORTAL = MAPS.project.customerPortal.id

/** The labels of the page: their keys and what they are called, in order. */
async function labelsOf(table: Table): Promise<{ key: string; name: string }[]> {
  const keys = await table.rowKeys()
  const names = await table.columnTexts("name")
  return keys.map((key, at) => ({ key, name: names[at].trim() }))
}

test.describe("\"Merge\" at /labels: a table action with a key and a list of keys", () => {
  let labels: Table

  test.beforeEach(async ({ page }) => {
    labels = new Table(page, "label", "/labels")
    await labels.open()
    await labels.tableAction("merge").click()
    await expect(labels.panel).toBeVisible()
  })

  test("its panel has no input a key is typed into: each field says what is chosen, and has a button", async () => {
    await expect(labels.panelTitle).toHaveText("Merge")
    expect(await labels.fields()).toEqual(["into", "labels"])

    // each field is a group, named by its label, with the button in it
    const into = labels.panel.getByRole("group", { name: "Into" })
    const several = labels.panel.getByRole("group", { name: "Labels" })
    await expect(into.getByRole("button", { name: "Choose" })).toBeVisible()
    await expect(several.getByRole("button", { name: "Choose" })).toBeVisible()
    await expect(labels.panel.locator("input:visible, textarea:visible")).toHaveCount(0)
    await expect(labels.fieldKey("into")).toHaveValue("")
    await expect(labels.fieldChosen("into")).toHaveCount(0)
  })

  test("one label is chosen for the key, from the labels' own table, with the pointer and with the keyboard", async ({
    page,
  }) => {
    const [first, second] = await labelsOf(labels)

    await labels.fieldChoose("into").click()
    await expect(labels.picker).toBeVisible()
    await expect(labels.pickerTitle).toHaveText("Into: choose label")
    // the argument cannot be empty: there is no "None"
    await expect(labels.pickerNone).toHaveCount(0)
    const offered = labels.pickerTable("into")
    await offered.ready()
    expect(await offered.rowKeys()).toHaveLength(SEED.labels.acme)
    // a table to choose from: nothing in it is edited, run or created
    await expect(offered.editorTemplates).toHaveCount(0)
    await expect(offered.tableActions).toHaveCount(0)

    await offered.radio(first.key).click()
    await labels.pickerChoose.click()
    await expect(labels.picker).toHaveCount(0)
    await expect(labels.fieldChosen("into")).toHaveText(first.name)
    await expect(labels.fieldKey("into")).toHaveValue(first.key)
    // the field's button has the focus again, and says what is chosen
    await expect(labels.fieldChoose("into")).toBeFocused()
    await expect(labels.fieldChoose("into")).toHaveAccessibleDescription(first.name)

    // again, with the keyboard: Enter opens the picker, on the row that is
    // chosen now; Down Arrow and Enter choose the next
    await page.keyboard.press("Enter")
    await expect(labels.picker).toBeVisible()
    await labels.pickerTable("into").ready()
    await expect(labels.pickerTable("into").radio(first.key)).toBeChecked()
    await page.keyboard.press("ArrowDown")
    await page.keyboard.press("Enter")
    await expect(labels.picker).toHaveCount(0)
    await expect(labels.fieldChosen("into")).toHaveText(second.name)
    await expect(labels.fieldKey("into")).toHaveValue(second.key)
  })

  test("any number of labels is chosen for the list of keys, and one is taken out again", async () => {
    const [, second, third] = await labelsOf(labels)

    await labels.fieldChoose("labels").click()
    await expect(labels.picker).toBeVisible()
    await expect(labels.pickerTitle).toHaveText("Labels: choose label")
    const offered = labels.pickerTable("labels")
    await offered.ready()
    await offered.box(second.key).click()
    await offered.box(third.key).click()
    await labels.pickerChoose.click()
    await expect(labels.picker).toHaveCount(0)

    await expect(labels.fieldChosenItems("labels")).toHaveText([second.name, third.name])
    await labels.fieldRemove("labels", 0).click()
    await expect(labels.fieldChosenItems("labels")).toHaveText([third.name])
    // the server says where focus goes: to the button of the label that stands in its place
    await expect(labels.fieldRemove("labels", 0)).toBeFocused()
  })

  test("\"Run\" merges what was chosen, and the table says what the action returned", async () => {
    const [first, second, third] = await labelsOf(labels)

    await labels.chooseField("into", first.key)
    await labels.fieldChoose("labels").click()
    const offered = labels.pickerTable("labels")
    await offered.ready()
    await offered.box(second.key).click()
    await offered.box(third.key).click()
    await labels.pickerChoose.click()
    await expect(labels.picker).toHaveCount(0)

    await labels.panelSubmit.click()
    await expect(labels.panel).toHaveCount(0)
    await expect(labels.result).toHaveText("Merge: 2")
    await expect(labels.rows).toHaveCount(SEED.labels.acme - 2)
    const left = (await labelsOf(labels)).map((label) => label.name)
    expect(left).toContain(first.name)
    expect(left).not.toContain(second.name)
    expect(left).not.toContain(third.name)
  })

  test("\"Run\" with nothing chosen is the action's to refuse, at the field", async () => {
    await labels.panelSubmit.click()
    await expect(labels.fieldError("into")).toHaveText("is required")
    await expect(labels.panel).toBeVisible()
    await expect(labels.rows).toHaveCount(SEED.labels.acme)
  })

  test("a key that is put into the field by hand and names no label of theirs runs nothing", async () => {
    const [first] = await labelsOf(labels)
    await labels.chooseField("into", first.key)
    // a key of nothing this person could have chosen
    await labels
      .fieldKey("into")
      .evaluate((input) => ((input as HTMLInputElement).value = "00000000-0000-4000-8000-000000000000"))

    await labels.panelSubmit.click()
    await expect(labels.panelErrors).toBeVisible()
    await expect(labels.panel).toBeVisible()
    await expect(labels.rows).toHaveCount(SEED.labels.acme)
  })
})

test.describe("\"Assign open tasks\" at /projects: a generic action in every row", () => {
  let projects: Table

  test.beforeEach(async ({ page }) => {
    projects = new Table(page, "project", "/projects")
    await projects.open()
  })

  test("asks for the person, who is chosen from the table of the people; the row gives the project", async () => {
    await projects.action(PORTAL, "assign_open_tasks").click()
    await expect(projects.panel).toBeVisible()
    await expect(projects.panelTitle).toHaveText("Assign open tasks: Customer portal")
    expect(await projects.fields()).toEqual(["assignee"])
    await expect(projects.panel.getByRole("group", { name: "Assignee" })).toBeVisible()

    await projects.fieldChoose("assignee").click()
    await expect(projects.pickerTitle).toHaveText("Assignee: choose user")
    const people = projects.pickerTable("assignee")
    await people.ready()
    const [person] = await people.rowKeys()
    const name = (await people.cell(person, "name").innerText()).trim()
    await people.radio(person).click()
    await projects.pickerChoose.click()
    await expect(projects.picker).toHaveCount(0)
    await expect(projects.fieldChosen("assignee")).toHaveText(name)

    await projects.panelSubmit.click()
    await expect(projects.panel).toHaveCount(0)
    await expect(projects.result).toHaveText(/^\s*Assign open tasks: \d+\s*$/)
  })

  test("runs on the selected rows, with the person chosen once for all of them", async ({ page }) => {
    const [first, second] = await projects.rowKeys()
    await projects.box(first).click()
    await projects.box(second).click()
    await projects.useBulk("assign_open_tasks")

    await expect(projects.panel).toBeVisible()
    await expect(projects.panelTitle).toHaveText("Assign open tasks: 2 records")
    await projects.fieldChoose("assignee").click()
    const people = projects.pickerTable("assignee")
    await people.ready()
    const [person] = await people.rowKeys()
    await people.radio(person).click()
    await projects.pickerChoose.click()
    await expect(projects.picker).toHaveCount(0)
    // "Run" asks first, as before every action on the selected rows
    await projects.panelSubmit.click()
    await projects.question.getByRole("button", { name: "Confirm" }).click()

    await expect(projects.panel).toHaveCount(0)
    await expect(projects.result).toContainText("Assign open tasks: 2 done.")
    await expect(page.locator("[role=dialog][open]")).toHaveCount(0)
  })
})

test("in German the fields, the picker and the result speak German", async ({ page }) => {
  const labels = new Table(page, "label", "/labels")
  await labels.open()
  await switchLocale(page, "de")
  await labels.ready()

  await labels.tableAction("merge").click()
  await expect(labels.panelTitle).toHaveText("Zusammenführen")
  await expect(labels.panel.locator('[data-field="into"] [data-label]')).toHaveText("In")
  await expect(labels.fieldChoose("into")).toHaveText("Auswählen")
  await labels.fieldChoose("into").click()
  await expect(labels.pickerTitle).toHaveText("In: Label auswählen")
  await labels.pickerCancel.click()
  await labels.panelCancel.click()

  await switchLocale(page, "en")
})

for (const theme of ["light", "dark"] as const) {
  test.describe(`axe, in the ${theme} theme`, () => {
    test("finds nothing wrong with the panel, the picker of one and the picker of several, and the result", async ({
      page,
    }) => {
      await page.addInitScript((theme) => localStorage.setItem("phx:theme", theme), theme)
      const labels = new Table(page, "label", "/labels")
      await labels.open()
      await expect(page.locator("html")).toHaveAttribute("data-theme", theme)
      const [first, second] = await labelsOf(labels)

      await labels.tableAction("merge").click()
      await expect(labels.panel).toBeVisible()
      await expectNoAxeViolations(page)

      await labels.fieldChoose("into").click()
      await labels.pickerTable("into").ready()
      await expectNoAxeViolations(page)
      await labels.pickerTable("into").radio(first.key).click()
      await labels.pickerChoose.click()
      await expect(labels.picker).toHaveCount(0)

      await labels.fieldChoose("labels").click()
      await labels.pickerTable("labels").ready()
      await expectNoAxeViolations(page)
      await labels.pickerTable("labels").box(second.key).click()
      await labels.pickerChoose.click()
      await expect(labels.picker).toHaveCount(0)
      await expectNoAxeViolations(page)

      await labels.panelSubmit.click()
      await expect(labels.result).toHaveText("Merge: 1")
      await expectNoAxeViolations(page)
    })
  })
}
