import { expectNoAxeViolations } from "./support/a11y"
import { SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { Table } from "./support/table"

// Table actions in a browser: the buttons on the line of the table's name,
// by pointer and by keyboard; an action that runs at once, one that asks
// first and one that opens the action panel; what the table says when one
// has run, and where focus is then; a generic action in a row; and the
// same buttons on the line of a nested table.
//
// /labels as the admin, who may run every one of them, unless a test says
// otherwise. Its table has five table actions: "Count unused" runs at one
// click and returns a number, "Recolour" opens the action panel with two
// fields, "Remove unused" asks first and returns nothing, "Merge" takes
// labels that are chosen in the picker, which action_references.spec.ts is
// about, and "Import" takes a file, which files.spec.ts is about. Every row
// has "Copy", a generic action that is given the row's key. In the seed
// every label is on some task, so no label is unused until a test makes
// one. These tests change the data: the database is seeded again after
// each of them (`writes`).

const QUESTION = "Delete every label that no task carries?"

test.use({ writes: true })

let labels: Table

test.beforeEach(async ({ page }) => {
  labels = new Table(page, "label", "/labels")
  await labels.open()
})

/** Makes a label that no task carries, through "New label". */
async function makeUnused(table: Table, name: string): Promise<void> {
  await table.create.click()
  await table.field("name").fill(name)
  await table.panelSubmit.click()
  await expect(table.panel).toHaveCount(0)
  await expect(table.rows).toHaveCount(SEED.labels.acme + 1)
}

test.describe("the buttons", () => {
  test("stand on the line of the table's name after \"New label\", look as it does, and are tab stops of the page before the grid", async ({
    page,
  }) => {
    await expect(labels.tableActions).toHaveText(["Count unused", "Recolour", "Remove unused", "Merge", "Import"])
    await expect(labels.headerLine.getByRole("button")).toHaveText([
      "New label",
      "Count unused",
      "Recolour",
      "Remove unused",
      "Merge",
      "Import",
    ])

    // the same button as the create button: its classes, and so its height
    const classes = await labels.create.getAttribute("class")
    const box = (await labels.create.boundingBox())!
    let right = box.x + box.width
    for (const button of await labels.tableActions.all()) {
      await expect(button).toHaveAttribute("class", classes!)
      await expect(button).toHaveAttribute("type", "button")
      const own = (await button.boundingBox())!
      expect(own.height).toBe(box.height)
      expect(own.y).toBe(box.y)
      // left to right, after the one before
      expect(own.x).toBeGreaterThanOrEqual(right)
      right = own.x + own.width
    }

    // Tab goes through them in that order, and then into the grid
    await labels.create.focus()
    for (const name of ["count_unused", "recolour", "remove_unused", "merge", "import"]) {
      await page.keyboard.press("Tab")
      await expect(labels.tableAction(name)).toBeFocused()
    }
    await page.keyboard.press("Tab")
    expect(await labels.hasFocus()).toBe(true)
  })

  for (const actor of ["member", "viewer"] as const) {
    test.describe(`as the ${actor}`, () => {
      test.use({ actor })

      test("are those of the actions the person may run: counting, and nothing that changes labels", async () => {
        await expect(labels.tableActions).toHaveText(["Count unused"])
        await expect(labels.create).toHaveCount(0)
        await expect(labels.actionsHeader).toHaveCount(0)

        await labels.tableAction("count_unused").click()
        await expect(labels.result).toHaveText("Count unused: 0")
      })
    })
  }
})

test.describe("an action that runs at once", () => {
  for (const theme of ["light", "dark"] as const) {
    test(`says what it returned above the grid, reads it out, and leaves focus on its button (${theme})`, async ({
      page,
      frames,
    }) => {
      await page.addInitScript((theme) => localStorage.setItem("phx:theme", theme), theme)
      await labels.open()
      await expect(page.locator("html")).toHaveAttribute("data-theme", theme)

      const count = labels.tableAction("count_unused")
      const top = (await labels.grid.boundingBox())!.y

      await frames.clear()
      await count.click()

      await expect(labels.result).toHaveText("Count unused: 0")
      await expect(labels.status).toHaveText("Count unused: 0")
      await expect(labels.status).toHaveAttribute("role", "status")
      await expect(labels.panel).toHaveCount(0)
      await expect(labels.question).toBeHidden()
      await expect(count).toBeFocused()
      expect(await frames.count("table_act")).toBe(1)
      expect(await frames.count("table_run")).toBe(0)

      // the table has read again, and shows what it showed
      await expect(labels.rows).toHaveCount(SEED.labels.acme)
      await expectNoAxeViolations(page)

      // what it says takes room above the grid, and nothing else moves
      expect((await labels.grid.boundingBox())!.y).toBeGreaterThanOrEqual(top)
    })
  }

  test("from the keyboard: Enter and Space on its button run it, once each", async ({ page, frames }) => {
    await makeUnused(labels, "spare")
    const count = labels.tableAction("count_unused")

    await count.focus()
    await frames.clear()
    await page.keyboard.press("Enter")
    await expect(labels.result).toHaveText("Count unused: 1")
    await expect(count).toBeFocused()

    await page.keyboard.press("Space")
    await expect(labels.status).toHaveText("Count unused: 1")
    expect(await frames.count("table_act")).toBe(2)
  })
})

test.describe("an action that asks first", () => {
  test("asks in the table's dialog; Cancel runs nothing and puts focus back on the button", async ({
    page,
    frames,
  }) => {
    await makeUnused(labels, "spare")
    const remove = labels.tableAction("remove_unused")

    await frames.clear()
    await remove.click()
    await expect(labels.question).toBeVisible()
    await expect(labels.question).toHaveAccessibleName(QUESTION)
    expect(await labels.question.evaluate((dialog) => dialog.matches(":modal"))).toBe(true)
    // Cancel has the focus: the safe answer
    await expect(labels.question.getByRole("button", { name: "Cancel" })).toBeFocused()
    await expectNoAxeViolations(page)

    await page.keyboard.press("Escape")
    await expect(labels.question).toBeHidden()
    await expect(remove).toBeFocused()
    await expect(labels.result).toHaveCount(0)
    await expect(labels.rows).toHaveCount(SEED.labels.acme + 1)
    expect(await frames.count("table_run")).toBe(0)
  })

  test("Confirm runs it: the table says that it is done, and shows the records as they are now", async ({
    frames,
  }) => {
    await makeUnused(labels, "spare")
    const remove = labels.tableAction("remove_unused")

    await frames.clear()
    await remove.click()
    await labels.question.getByRole("button", { name: "Confirm" }).click()

    await expect(labels.result).toHaveText("Remove unused: done")
    await expect(labels.status).toHaveText("Remove unused: done")
    await expect(labels.rows).toHaveCount(SEED.labels.acme)
    await expect(labels.columnCells("name").filter({ hasText: "spare" })).toHaveCount(0)
    await expect(remove).toBeFocused()
    expect(await frames.count("table_act")).toBe(1)
    expect(await frames.count("table_run")).toBe(1)
  })
})

test.describe("an action with arguments", () => {
  for (const theme of ["light", "dark"] as const) {
    test(`opens the action panel from the keyboard, says what the action refuses at the field, and runs when it is put right (${theme})`, async ({
      page,
    }) => {
      await page.addInitScript((theme) => localStorage.setItem("phx:theme", theme), theme)
      await labels.open()
      await expect(page.locator("html")).toHaveAttribute("data-theme", theme)

      const recolour = labels.tableAction("recolour")
      const colours = await labels.columnCells("colour").allTextContents()
      const from = colours[0]
      const changed = colours.filter((colour) => colour === from).length

      await recolour.focus()
      await page.keyboard.press("Enter")

      await expect(labels.panel).toBeVisible()
      await expect(labels.panel).toHaveAccessibleName("Recolour")
      expect(await labels.panel.evaluate((panel) => panel.matches(":modal"))).toBe(true)
      expect(await labels.fields()).toEqual(["from", "to"])
      await expect(labels.field("from")).toBeFocused()
      await expect(labels.field("from")).toHaveAttribute("aria-required", "true")
      await expect(labels.panelSubmit).toHaveText("Run")
      await expectNoAxeViolations(page)

      // a value the action refuses: at its field, and the panel stays
      await page.keyboard.type("red")
      await page.keyboard.press("Tab")
      await page.keyboard.type("#123456")
      await labels.panelSubmit.click()
      await expect(labels.fieldError("from")).toBeVisible()
      await expect(labels.field("from")).toHaveAttribute("aria-invalid", "true")
      await expect(labels.panel).toBeVisible()
      await expect(labels.result).toHaveCount(0)
      await expectNoAxeViolations(page)

      await labels.field("from").fill(from)
      await labels.panelSubmit.click()

      await expect(labels.panel).toHaveCount(0)
      await expect(labels.result).toHaveText(`Recolour: ${changed}`)
      await expect(labels.status).toHaveText(`Recolour: ${changed}`)
      await expect(labels.columnCells("colour").filter({ hasText: "#123456" })).toHaveCount(changed)
      await expect(recolour, "focus is back on the button that opened the panel").toBeFocused()
      await expectNoAxeViolations(page)
    })
  }

  test("Escape closes the panel, runs nothing, and puts focus back on the button", async ({ page }) => {
    const recolour = labels.tableAction("recolour")
    await recolour.click()
    await expect(labels.panel).toBeVisible()

    await page.keyboard.press("Escape")
    await expect(labels.panel).toHaveCount(0)
    await expect(recolour).toBeFocused()
    await expect(labels.result).toHaveCount(0)
  })
})

test.describe("a generic action in a row", () => {
  test("has its button in the actions cell, asks for what the row does not give, and the table reads again", async ({
    page,
  }) => {
    const key = await labels.rowKey(1)
    const name = (await labels.cell(key, "name").textContent())!
    const colour = (await labels.cell(key, "colour").textContent())!

    await expect(labels.actions(key)).toHaveText(["Destroy", "Copy"])
    // not on the line of the selected rows: its block says `bulk? false`
    await labels.box(key).click()
    await expect(labels.bulkButtons).toHaveText(["Destroy"])
    await labels.clearSelection.click()

    await labels.action(key, "copy").click()
    await expect(labels.panel).toBeVisible()
    await expect(labels.panel).toHaveAccessibleName(`Copy: ${name}`)
    // the label's key is the table's to give: the panel asks for the name alone
    expect(await labels.fields()).toEqual(["name"])
    await expect(labels.field("name")).toBeFocused()

    // a name that is taken: what the action says, at the field
    await labels.field("name").fill(name)
    await labels.panelSubmit.click()
    await expect(labels.fieldError("name")).toHaveText("has already been taken")
    await expectNoAxeViolations(page)

    await labels.field("name").fill("0 first of all")
    await labels.panelSubmit.click()

    await expect(labels.panel).toHaveCount(0)
    await expect(labels.result).toHaveText("Copy: done")
    await expect(labels.status).toHaveText("Copy: done")
    await expect(labels.rows).toHaveCount(SEED.labels.acme + 1)
    // read again: the copy is where the table's sort puts it, the first row
    const copy = await labels.rowKey(1)
    await expect(labels.cell(copy, "name")).toHaveText("0 first of all")
    await expect(labels.cell(copy, "colour")).toHaveText(colour)
    expect(await labels.hasFocus(), "focus is in the grid").toBe(true)
  })
})

test.describe("in a nested table", () => {
  test("the buttons stand on the line that names it once it has read, look as a line's create button does, and are used from the keyboard", async ({
    page,
    tasks,
  }) => {
    const FIRST = SEED.task.first
    await tasks.open()
    await tasks.expand(FIRST)
    await expect(tasks.lineAction(FIRST, "labels", "count_unused"), "a closed line has none").toHaveCount(0)

    const nested = await tasks.openLine(FIRST, "labels")
    const names = ["count_unused", "recolour", "remove_unused", "import"]
    const comments = await tasks.openLine(FIRST, "comments")
    const create = tasks.lineCreate(FIRST, "comments")

    for (const name of names) {
      const button = tasks.lineAction(FIRST, "labels", name)
      await expect(button).toBeVisible()
      await expect(button).toHaveAttribute("tabindex", "-1")
      await expect(button).toHaveAttribute("class", (await create.getAttribute("class"))!)
      expect((await button.boundingBox())!.height).toBe((await create.boundingBox())!.height)
    }
    await expect(tasks.lineCell(FIRST, "labels").getByRole("button")).toHaveText([
      "Labels",
      "Count unused",
      "Recolour",
      "Remove unused",
      "Merge",
      "Import",
    ])
    // the nested table has no line of its own for them
    await expect(nested.headerLine).toHaveCount(0)
    await expect(nested.tableActions).toHaveCount(0)
    // a table without table actions has none on its line
    await expect(tasks.lineCell(FIRST, "comments").getByRole("button")).toHaveText(["Comments", "New comment"])
    await expect(comments.grid).toBeVisible()
    expect(await tasks.tabStops(), "the tree is one tab stop still").toHaveLength(1)

    // from the keyboard: F2 on the line goes into its controls, Right to the next
    await tasks.lineCell(FIRST, "labels").focus()
    await page.keyboard.press("F2")
    await expect(tasks.line(FIRST, "labels")).toBeFocused()
    await page.keyboard.press("ArrowRight")
    await expect(tasks.lineAction(FIRST, "labels", "count_unused")).toBeFocused()
    await page.keyboard.press("Enter")

    // the nested table says it, and the table around it says nothing
    await expect(nested.result).toHaveText("Count unused: 0")
    await expect(nested.status).toHaveText("Count unused: 0")
    await expect(tasks.result).toHaveCount(0)
    await expect(tasks.line(FIRST, "labels"), "the line stays open").toHaveAttribute("aria-expanded", "true")
    await expectNoAxeViolations(page)

    // Escape goes back to the line
    await tasks.lineAction(FIRST, "labels", "count_unused").focus()
    await page.keyboard.press("Escape")
    await expect(tasks.lineCell(FIRST, "labels")).toBeFocused()
  })

  test("an action that asks first asks in the nested table's own dialog, and one with arguments opens its own panel", async ({
    page,
    tasks,
  }) => {
    const FIRST = SEED.task.first
    await tasks.open()
    const nested = await tasks.openLine(FIRST, "labels")

    const remove = tasks.lineAction(FIRST, "labels", "remove_unused")
    await remove.click()
    await expect(nested.question).toBeVisible()
    await expect(nested.question).toHaveAccessibleName(QUESTION)
    await expect(tasks.question).toBeHidden()
    await page.keyboard.press("Escape")
    await expect(nested.question).toBeHidden()
    await expect(remove).toBeFocused()

    const recolour = tasks.lineAction(FIRST, "labels", "recolour")
    await recolour.click()
    await expect(nested.panel).toBeVisible()
    await expect(nested.panel).toHaveAccessibleName("Recolour")
    await expect(tasks.panel).toHaveCount(0)
    await expect(nested.field("from")).toBeFocused()
    await page.keyboard.press("Escape")
    await expect(nested.panel).toHaveCount(0)
    await expect(recolour).toBeFocused()
  })
})
