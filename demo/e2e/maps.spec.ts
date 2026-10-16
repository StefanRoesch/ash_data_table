import type { Locator, Page } from "@playwright/test"
import { expectNoAxeViolations } from "./support/a11y"
import { MAPS } from "./support/data"
import { expect, test } from "./support/fixtures"
import { Table } from "./support/table"

// The values made of fields, as the admin: a project's "Client", an embedded
// resource with an address inside it, and its "Milestones", an array of
// embedded resources, at /projects; and a task's "Repeats", a map that
// declares its fields, at /tasks. The cell shows the value on one line; it
// is edited in the side panel, field by field. These tests save: the
// database is seeded again after each of them (`writes`).

const PORTAL = MAPS.project.customerPortal
const TOOLS = MAPS.project.internalTools
const WAREHOUSE = MAPS.project.dataWarehouse
const WEEKLY = MAPS.task.weekly
const ONCE = MAPS.task.once

const TOO_SHORT = "length must be greater than or equal to 2"

test.use({ writes: true })

function projectsOf(page: Page): Table {
  return new Table(page, "project", "/projects")
}

/** A group of the panel: named by its label. */
function group(within: Locator, name: string): Locator {
  return within.getByRole("group", { name, exact: true })
}

/** A field of a group, by its label. */
function box(within: Locator, name: string): Locator {
  return within.getByRole("textbox", { name, exact: true })
}

test.describe("the cell of a value made of fields", () => {
  test("shows the value on one line, as plain text: nothing else is in the cell", async ({ page }) => {
    const projects = projectsOf(page)
    await projects.open()

    const client = projects.cell(PORTAL.id, "client")
    await expect(client).toHaveText(PORTAL.client)
    await expect(client.locator("*")).toHaveCount(0)
    await expect(projects.cell(TOOLS.id, "client")).toHaveText(TOOLS.client)

    // the values of an array, with semicolons between them
    const milestones = projects.cell(WAREHOUSE, "milestones")
    await expect(milestones).toContainText("Title: First release, ")
    await expect(milestones).toContainText("; Title: Review, Reached?: No")
    await expect(milestones.locator("*")).toHaveCount(0)

    // no value is an empty cell
    await expect(projects.cell(WAREHOUSE, "client")).toBeEmpty()
    await expect(projects.cell(PORTAL.id, "milestones")).toBeEmpty()
  })

  test("of a map that declares its fields shows them the same way", async ({ tasks }) => {
    await tasks.open()

    await expect(tasks.cell(WEEKLY.id, "recurrence")).toHaveText(WEEKLY.recurrence)
    await expect(tasks.cell(WEEKLY.id, "recurrence").locator("*")).toHaveCount(0)
    await expect(tasks.cell(ONCE, "recurrence")).toBeEmpty()
  })

  test("has neither a sort nor a filter, and is a cell like any other to the arrow keys, which send nothing", async ({
    page,
    pushed,
  }) => {
    const projects = projectsOf(page)
    await projects.open()

    for (const column of ["client", "milestones"]) {
      await expect(projects.header(column)).not.toHaveAttribute("aria-sort")
      await expect(projects.filterCell(column).locator("input, select, button")).toHaveCount(0)
    }

    await projects.cell(PORTAL.id, "budget").focus()
    await pushed.clear()
    await projects.press("ArrowRight")
    await expect(projects.cell(PORTAL.id, "client")).toBeFocused()
    await projects.press("ArrowRight")
    await expect(projects.cell(PORTAL.id, "milestones")).toBeFocused()
    await projects.press("ArrowLeft", "ArrowDown")
    await expect(projects.cell(WAREHOUSE, "client")).toBeFocused()
    await projects.header("client").click()
    expect(await pushed.all()).toEqual([])
  })
})

test.describe("opening the editor of an embedded resource", () => {
  test("Enter opens the side panel, headed by the column and the record, with focus in its first field; Escape closes it and focus is on the cell again", async ({
    page,
    pushed,
  }) => {
    const projects = projectsOf(page)
    await projects.open()
    const cell = projects.cell(PORTAL.id, "client")

    await cell.focus()
    await pushed.clear()
    await projects.press("Enter")

    await expect(projects.panel).toBeVisible()
    expect(await projects.panel.evaluate((panel) => panel.matches(":modal"))).toBe(true)
    await expect(projects.panel).toHaveAccessibleName("Client: Customer portal")
    await expect(projects.panelSubmit).toHaveText("Save")
    await expect(box(projects.panel, "Name")).toBeFocused()
    expect(await pushed.count("edit")).toBe(1)

    await page.keyboard.press("Escape")
    await expect(projects.panel).toHaveCount(0)
    await expect(cell).toBeFocused()
    await expect(cell).toHaveText(PORTAL.client)
    expect(await pushed.count("panel_submit")).toBe(0)
  })

  test("F2 and a double click open it too; a key that types a character does not", async ({ page, pushed }) => {
    const projects = projectsOf(page)
    await projects.open()
    const cell = projects.cell(PORTAL.id, "client")

    await cell.focus()
    await pushed.clear()
    await projects.press("x", "5")
    await expect(projects.panel).toHaveCount(0)
    await expect(cell).toBeFocused()
    expect(await pushed.all()).toEqual([])

    await projects.press("F2")
    await expect(projects.panel).toBeVisible()
    await projects.panelCancel.click()
    await expect(projects.panel).toHaveCount(0)
    await expect(cell).toBeFocused()

    await cell.dblclick()
    await expect(projects.panel).toBeVisible()
    await expect(box(projects.panel, "Name")).toBeFocused()
  })

  test("the panel is a group of the value's fields, with a group inside it for the address; each field has the control of its type and says what is required", async ({
    page,
  }) => {
    const projects = projectsOf(page)
    await projects.open()
    await projects.cell(PORTAL.id, "client").dblclick()

    const client = group(projects.panel, "Client")
    await expect(client).toBeVisible()
    await expect(box(client, "Name")).toHaveValue("Hafen & Söhne")
    await expect(box(client, "Name")).toHaveAttribute("aria-required", "true")
    await expect(box(client, "Email")).toHaveValue("office@hafensohne.test")
    await expect(box(client, "Email")).not.toHaveAttribute("aria-required")
    await expect(client.getByRole("checkbox", { name: "Key account?" })).toBeChecked()

    const address = group(client, "Address")
    await expect(address).toBeVisible()
    await expect(box(address, "Street")).toHaveValue("Ernstweg 48")
    await expect(box(address, "City")).toHaveValue("München")
    await expect(box(address, "Postcode")).toHaveValue("60948")

    // what is shown of the groups is their names and an indentation: no box around them
    for (const part of [client, address]) {
      expect(
        await part.evaluate((element) => {
          const style = getComputedStyle(element)
          return [style.borderTopWidth, style.backgroundColor, style.boxShadow]
        }),
      ).toEqual(["0px", "rgba(0, 0, 0, 0)", "none"])
    }
    const size = (locator: Locator) => locator.evaluate((element) => getComputedStyle(element).fontSize)
    expect(await size(address.locator("[data-label]").first())).toBe(await size(client.locator("[data-label]").first()))
  })
})

test.describe("saving an embedded resource from the side panel", () => {
  test("with the keyboard: the fields are tab stops in their order, Save saves, the cell shows the new value and has the focus", async ({
    page,
    pushed,
  }) => {
    const projects = projectsOf(page)
    await projects.open()
    const cell = projects.cell(PORTAL.id, "client")
    await cell.focus()
    await projects.press("Enter")

    const client = group(projects.panel, "Client")
    await expect(box(client, "Name")).toBeFocused()
    await page.keyboard.press("ControlOrMeta+a")
    await page.keyboard.type("Hafen AG")
    await page.keyboard.press("Tab")
    await expect(box(client, "Email")).toBeFocused()
    await page.keyboard.press("Tab")
    await expect(client.getByRole("checkbox", { name: "Key account?" })).toBeFocused()
    await page.keyboard.press("Space")
    await page.keyboard.press("Tab")
    await expect(client.getByRole("button", { name: "Remove Address" })).toBeFocused()
    await page.keyboard.press("Tab")
    await expect(box(client, "Street")).toBeFocused()
    await page.keyboard.press("Tab")
    await page.keyboard.press("ControlOrMeta+a")
    await page.keyboard.type("Hamburg")
    await projects.panelSettled()

    await pushed.clear()
    await projects.panelSubmit.focus()
    await page.keyboard.press("Enter")

    await expect(projects.panel).toHaveCount(0)
    await expect(cell).toHaveText(
      "Name: Hafen AG, Email: office@hafensohne.test, Key account?: No, Address: Street: Ernstweg 48, City: Hamburg, Postcode: 60948",
    )
    await expect(cell).toBeFocused()
    expect(await pushed.count("panel_submit")).toBe(1)
    expect(await pushed.count("save")).toBe(0)

    // and it is what the record holds
    await projects.open()
    await expect(projects.cell(PORTAL.id, "client")).toContainText("Name: Hafen AG, ")
  })

  test("what the embedded resource refuses is shown at its field, the panel stays open and the other entries stay", async ({
    page,
  }) => {
    const projects = projectsOf(page)
    await projects.open()
    const cell = projects.cell(PORTAL.id, "client")
    await cell.dblclick()

    const client = group(projects.panel, "Client")
    const address = group(client, "Address")
    await box(client, "Name").fill("H")
    await box(client, "Email").fill("hafen at example")
    await box(address, "City").fill("")
    await box(address, "Street").fill("Am Kai 1")
    await projects.panelSubmit.click()
    await projects.panelSettled()

    await expect(projects.panel).toBeVisible()
    await expect(box(client, "Name")).toHaveAttribute("aria-invalid", "true")
    // the message, and after it the counter of a text with a most it can be long
    await expect(box(client, "Name")).toHaveAccessibleDescription(`${TOO_SHORT} 1/60`)
    await expect(box(client, "Email")).toHaveAccessibleDescription("must be an email address")
    await expect(box(address, "City")).toHaveAccessibleDescription("is required")
    await expect(box(address, "Street")).not.toHaveAttribute("aria-invalid")
    await expect(box(address, "Street")).toHaveValue("Am Kai 1")
    await expect(projects.status).toContainText("Client was not saved: ")
    await expectNoAxeViolations(page)

    // nothing was saved
    await projects.panelCancel.click()
    await expect(cell).toHaveText(PORTAL.client)
    await expect(cell).toBeFocused()
    await expect(cell).not.toHaveAttribute("aria-invalid")
  })

  test("a value inside it is taken away and added again from the keyboard, and focus follows", async ({ page }) => {
    const projects = projectsOf(page)
    await projects.open()
    const cell = projects.cell(PORTAL.id, "client")
    await cell.dblclick()

    const client = group(projects.panel, "Client")
    const address = group(client, "Address")

    await address.getByRole("button", { name: "Remove Address" }).focus()
    await page.keyboard.press("Enter")
    await expect(box(address, "Street")).toHaveCount(0)
    await expect(address.getByRole("button", { name: "Add value" })).toBeFocused()
    // what was typed elsewhere stays
    await expect(box(client, "Name")).toHaveValue("Hafen & Söhne")

    await page.keyboard.press("Enter")
    await expect(box(address, "Street")).toBeFocused()
    await expect(box(address, "Street")).toHaveValue("")
    await address.getByRole("button", { name: "Remove Address" }).click()
    await expect(address.getByRole("button", { name: "Add value" })).toBeFocused()

    await projects.panelSubmit.click()
    await expect(projects.panel).toHaveCount(0)
    await expect(cell).toHaveText("Name: Hafen & Söhne, Email: office@hafensohne.test, Key account?: Yes")
    await expect(cell).toBeFocused()
  })

  test("a project without a client gets one: the group has only its button until the value is added", async ({
    page,
  }) => {
    const projects = projectsOf(page)
    await projects.open()
    const cell = projects.cell(WAREHOUSE, "client")
    await cell.focus()
    await projects.press("Enter")

    const client = group(projects.panel, "Client")
    await expect(client.getByRole("button", { name: "Add value" })).toBeFocused()
    await expect(client.getByRole("textbox")).toHaveCount(0)
    await expectNoAxeViolations(page)

    await page.keyboard.press("Enter")
    await expect(box(client, "Name")).toBeFocused()
    await page.keyboard.type("Lumen")
    await projects.panelSubmit.click()

    await expect(projects.panel).toHaveCount(0)
    await expect(cell).toHaveText("Name: Lumen, Key account?: No")
    await expect(cell).toBeFocused()
  })

  test("Save without a change saves nothing and closes the panel", async ({ page, pushed }) => {
    const projects = projectsOf(page)
    await projects.open()
    const cell = projects.cell(PORTAL.id, "client")
    await cell.dblclick()
    await expect(projects.panel).toBeVisible()

    await projects.panelSubmit.click()
    await expect(projects.panel).toHaveCount(0)
    await expect(cell).toHaveText(PORTAL.client)
    await expect(cell).toBeFocused()
    await expect(projects.status).toBeEmpty()
    expect(await pushed.count("panel_submit")).toBe(1)
  })
})

test.describe("an array of embedded resources in the side panel", () => {
  test("is a list of groups, each named by the column and its place; a value is added, typed and taken away from the keyboard, and the list is saved", async ({
    page,
  }) => {
    const projects = projectsOf(page)
    await projects.open()
    const cell = projects.cell(WAREHOUSE, "milestones")
    await cell.focus()
    await projects.press("Enter")

    const list = group(projects.panel, "Milestones")
    const first = group(list, "Milestones 1")
    const second = group(list, "Milestones 2")
    await expect(box(first, "Title")).toBeFocused()
    await expect(box(first, "Title")).toHaveValue("First release")
    await expect(box(second, "Title")).toHaveValue("Review")
    await expect(group(list, "Milestones 3")).toHaveCount(0)

    // a value is added after the others, and focus is in its first field
    await list.getByRole("button", { name: "Add value" }).focus()
    await page.keyboard.press("Enter")
    const third = group(list, "Milestones 3")
    await expect(box(third, "Title")).toBeFocused()
    await page.keyboard.type("Launch")
    await page.keyboard.press("Tab")
    await expect(third.getByLabel("Due on")).toBeFocused()
    await third.getByRole("checkbox", { name: "Reached?" }).focus()
    await page.keyboard.press("Space")
    await projects.panelSettled()

    // the first is taken away: focus goes to the value after it, which is the first now
    await first.getByRole("button", { name: "Remove Milestones 1" }).focus()
    await page.keyboard.press("Enter")
    await expect(box(first, "Title")).toBeFocused()
    await expect(box(first, "Title")).toHaveValue("Review")
    await expect(box(second, "Title")).toHaveValue("Launch")
    await expect(second.getByRole("checkbox", { name: "Reached?" })).toBeChecked()
    await expect(group(list, "Milestones 3")).toHaveCount(0)

    await projects.panelSubmit.click()
    await expect(projects.panel).toHaveCount(0)
    await expect(cell).toHaveText("Title: Review, Reached?: No; Title: Launch, Reached?: Yes")
    await expect(cell).toBeFocused()
  })

  test("the last value is taken away: focus goes to the one before it, and from the only one to the button that adds one", async ({
    page,
  }) => {
    const projects = projectsOf(page)
    await projects.open()
    const cell = projects.cell(WAREHOUSE, "milestones")
    await cell.dblclick()

    const list = group(projects.panel, "Milestones")
    await group(list, "Milestones 2").getByRole("button", { name: "Remove Milestones 2" }).click()
    await expect(box(group(list, "Milestones 1"), "Title")).toBeFocused()
    await group(list, "Milestones 1").getByRole("button", { name: "Remove Milestones 1" }).click()
    await expect(list.getByRole("button", { name: "Add value" })).toBeFocused()
    await expect(list.getByRole("textbox")).toHaveCount(0)

    await projects.panelSubmit.click()
    await expect(projects.panel).toHaveCount(0)
    await expect(cell).toBeEmpty()
  })

  test("what a value is refused for is shown at that value's field", async ({ page }) => {
    const projects = projectsOf(page)
    await projects.open()
    await projects.cell(WAREHOUSE, "milestones").dblclick()

    const list = group(projects.panel, "Milestones")
    const second = group(list, "Milestones 2")
    await box(second, "Title").fill("R")
    await projects.panelSubmit.click()
    await projects.panelSettled()

    await expect(projects.panel).toBeVisible()
    await expect(box(second, "Title")).toHaveAttribute("aria-invalid", "true")
    await expect(box(second, "Title")).toHaveAccessibleDescription(
      "length must be greater than or equal to 3 1/60",
    )
    await expect(box(group(list, "Milestones 1"), "Title")).not.toHaveAttribute("aria-invalid")
    await expectNoAxeViolations(page)
  })
})

test.describe("a map that declares its fields", () => {
  test.beforeEach(async ({ tasks }) => {
    await tasks.open()
  })

  test("is edited in the side panel as an embedded resource is; its column's question is asked when Save is used, and Cancel there comes back to the panel", async ({
    page,
    tasks,
  }) => {
    const cell = tasks.cell(WEEKLY.id, "recurrence")
    await cell.focus()
    await tasks.press("Enter")

    await expect(tasks.panel).toHaveAccessibleName("Repeats: Remove the dashboard charts")
    const repeats = group(tasks.panel, "Repeats")
    const every = repeats.getByRole("spinbutton", { name: "Every" })
    await expect(every).toBeFocused()
    await expect(every).toHaveValue("4")
    await expect(repeats.getByRole("combobox", { name: "Unit" })).toHaveValue("week")
    await expect(repeats.getByLabel("Until")).toHaveValue("")

    await every.fill("2")
    await repeats.getByRole("combobox", { name: "Unit" }).selectOption("month")
    await tasks.panelSettled()
    await tasks.panelSubmit.click()

    await expect(tasks.question).toBeVisible()
    await expect(tasks.question).toContainText("Change how often this task comes round?")
    await tasks.question.getByRole("button", { name: "Cancel" }).click()
    await expect(tasks.question).toBeHidden()
    await expect(tasks.panel).toBeVisible()
    await expect(every).toHaveValue("2")
    await expect(cell).toHaveText(WEEKLY.recurrence)

    await tasks.panelSubmit.click()
    await tasks.question.getByRole("button", { name: "Confirm" }).click()
    await expect(tasks.panel).toHaveCount(0)
    await expect(cell).toHaveText("Every: 2, Unit: Month")
    await expect(cell).toBeFocused()
  })

  test("Save without a change asks nothing", async ({ tasks }) => {
    const cell = tasks.cell(WEEKLY.id, "recurrence")
    await cell.dblclick()
    await expect(tasks.panel).toBeVisible()

    await tasks.panelSubmit.click()
    await expect(tasks.panel).toHaveCount(0)
    await expect(tasks.question).toBeHidden()
    await expect(cell).toHaveText(WEEKLY.recurrence)
    await expect(cell).toBeFocused()
  })

  test("what a field's constraints refuse is shown at that field", async ({ page, tasks }) => {
    await tasks.cell(WEEKLY.id, "recurrence").dblclick()
    const repeats = group(tasks.panel, "Repeats")
    const every = repeats.getByRole("spinbutton", { name: "Every" })

    await every.fill("0")
    await tasks.panelSubmit.click()
    await tasks.question.getByRole("button", { name: "Confirm" }).click()
    await tasks.panelSettled()

    await expect(tasks.panel).toBeVisible()
    await expect(every).toHaveAttribute("aria-invalid", "true")
    await expect(every).toHaveAccessibleDescription("must be greater than or equal to 1")
    await expectNoAxeViolations(page)
  })

  test("is taken away from a task, and added to one that had none", async ({ page, tasks }) => {
    const weekly = tasks.cell(WEEKLY.id, "recurrence")
    await weekly.dblclick()
    await group(tasks.panel, "Repeats").getByRole("button", { name: "Remove Repeats" }).click()
    await tasks.panelSubmit.click()
    await tasks.question.getByRole("button", { name: "Confirm" }).click()
    await expect(tasks.panel).toHaveCount(0)
    await expect(weekly).toBeEmpty()

    const once = tasks.cell(ONCE, "recurrence")
    await once.focus()
    await tasks.press("F2")
    const repeats = group(tasks.panel, "Repeats")
    await expect(repeats.getByRole("button", { name: "Add value" })).toBeFocused()
    await page.keyboard.press("Enter")
    await expect(repeats.getByRole("spinbutton", { name: "Every" })).toBeFocused()
    await page.keyboard.type("3")
    await repeats.getByRole("combobox", { name: "Unit" }).selectOption("day")
    await tasks.panelSubmit.click()
    await tasks.question.getByRole("button", { name: "Confirm" }).click()
    await expect(tasks.panel).toHaveCount(0)
    await expect(once).toHaveText("Every: 3, Unit: Day")
    await expect(once).toBeFocused()
  })
})

test.describe("in the action panel", () => {
  test("New project: the client is a group under its label, added with its button, and the project is created with it", async ({
    page,
  }) => {
    const projects = projectsOf(page)
    await projects.open()
    await projects.create.click()
    await expect(projects.panel).toBeVisible()

    const client = group(projects.panel, "Client")
    const milestones = group(projects.panel, "Milestones")
    await expect(client.getByRole("textbox")).toHaveCount(0)
    await expect(milestones.getByRole("textbox")).toHaveCount(0)

    await projects.field("name").fill("Portal relaunch")
    await client.getByRole("button", { name: "Add value" }).click()
    await expect(box(client, "Name")).toBeFocused()
    await page.keyboard.type("Lumen")
    const address = group(client, "Address")
    await address.getByRole("button", { name: "Add value" }).click()
    await expect(box(address, "Street")).toBeFocused()
    await page.keyboard.type("Ring 3")
    await box(address, "City").fill("Bonn")
    await milestones.getByRole("button", { name: "Add value" }).click()
    await expect(box(group(milestones, "Milestones 1"), "Title")).toBeFocused()
    await page.keyboard.type("Start")
    await projects.panelSettled()
    // what was typed before a group was added is still there
    await expect(projects.field("name")).toHaveValue("Portal relaunch")
    await expect(box(client, "Name")).toHaveValue("Lumen")
    await expectNoAxeViolations(page)

    await projects.panelSubmit.click()
    await expect(projects.panel).toHaveCount(0)

    const key = await projects.rowKey(1)
    await expect(projects.cell(key, "name")).toHaveText("Portal relaunch")
    await expect(projects.cell(key, "client")).toHaveText(
      "Name: Lumen, Key account?: No, Address: Street: Ring 3, City: Bonn",
    )
    await expect(projects.cell(key, "milestones")).toHaveText("Title: Start, Reached?: No")
  })

  test("New task: the recurrence is a group that is not there until it is added", async ({ page, tasks }) => {
    await tasks.open()
    await tasks.create.click()
    await expect(tasks.panel).toBeVisible()

    const repeats = group(tasks.panel, "Repeats")
    await expect(repeats.getByRole("spinbutton")).toHaveCount(0)
    await repeats.getByRole("button", { name: "Add value" }).click()
    await expect(repeats.getByRole("spinbutton", { name: "Every" })).toBeFocused()
    await expect(repeats.getByRole("spinbutton", { name: "Every" })).toHaveAttribute("aria-required", "true")
    await expectNoAxeViolations(page)
  })
})

test.describe("accessibility in the dark theme", () => {
  test.beforeEach(async ({ page }) => {
    await page.addInitScript(() => localStorage.setItem("phx:theme", "dark"))
  })

  test("the side panel of an embedded resource, as it opens and with errors shown", async ({ page }) => {
    const projects = projectsOf(page)
    await projects.open()
    await expect(page.locator("html")).toHaveAttribute("data-theme", "dark")

    await projects.cell(PORTAL.id, "client").dblclick()
    await expect(projects.panel).toBeVisible()
    await expectNoAxeViolations(page)

    const client = group(projects.panel, "Client")
    await box(client, "Name").fill("H")
    await box(group(client, "Address"), "City").fill("")
    await projects.panelSubmit.click()
    await projects.panelSettled()
    await expect(box(client, "Name")).toHaveAttribute("aria-invalid", "true")
    await expectNoAxeViolations(page)
  })

  test("the list of groups of an array of embedded resources, with a value added and one refused", async ({ page }) => {
    const projects = projectsOf(page)
    await projects.open()
    await projects.cell(WAREHOUSE, "milestones").dblclick()

    const list = group(projects.panel, "Milestones")
    await list.getByRole("button", { name: "Add value" }).click()
    await expect(box(group(list, "Milestones 3"), "Title")).toBeFocused()
    await expectNoAxeViolations(page)

    await projects.panelSubmit.click()
    await projects.panelSettled()
    await expect(box(group(list, "Milestones 3"), "Title")).toHaveAttribute("aria-invalid", "true")
    await expectNoAxeViolations(page)
  })
})

test.describe("accessibility in the light theme", () => {
  test("the side panel of an embedded resource and the list of an array of them, as they open", async ({ page }) => {
    const projects = projectsOf(page)
    await projects.open()

    await projects.cell(PORTAL.id, "client").dblclick()
    await expect(projects.panel).toBeVisible()
    await expectNoAxeViolations(page)
    await projects.panelCancel.click()
    await expect(projects.panel).toHaveCount(0)

    await projects.cell(WAREHOUSE, "milestones").dblclick()
    await expect(projects.panel).toBeVisible()
    await expectNoAxeViolations(page)
  })
})

test.describe("a person who may not change a record", () => {
  test.use({ actor: "member" })

  test("is told so in the panel, which stays open", async ({ page, tasks }) => {
    await tasks.open()
    // not the member's own task: the action is theirs to run on some records only
    const cell = tasks.cell(WEEKLY.id, "recurrence")
    await cell.dblclick()
    const repeats = group(tasks.panel, "Repeats")
    await repeats.getByRole("spinbutton", { name: "Every" }).fill("9")
    await tasks.panelSubmit.click()
    await tasks.question.getByRole("button", { name: "Confirm" }).click()
    await tasks.panelSettled()

    await expect(tasks.panel).toBeVisible()
    await expect(tasks.panelErrors).toHaveText("You are not allowed to change this.")
    await expectNoAxeViolations(page)

    await page.keyboard.press("Escape")
    await expect(tasks.panel).toHaveCount(0)
    await expect(cell).toHaveText(WEEKLY.recurrence)
    await expect(cell).toBeFocused()
  })
})
