import { expectNoAxeViolations } from "./support/a11y"
import { SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { switchLocale } from "./support/locale"
import { Table } from "./support/table"

// An argument that takes a file, in a browser: "Import" at /labels makes a
// label of each line of a CSV file. Its panel has a file input, which the
// block limits to one CSV file of 100 kB at most. The file is sent when
// "Run" is used, and the action reads it. As the admin, who may run it.
// These tests change the data: the database is seeded again after each of
// them (`writes`).

test.use({ writes: true })

let labels: Table

test.beforeEach(async ({ page }) => {
  labels = new Table(page, "label", "/labels")
  await labels.open()
})

function csv(name: string, text: string) {
  return { name, mimeType: "text/csv", buffer: Buffer.from(text, "utf8") }
}

/** The file input of the open panel. */
function fileInput(table: Table) {
  return table.panel.locator('input[type="file"]')
}

async function openImport(table: Table): Promise<void> {
  await table.tableAction("import").click()
  await expect(table.panel).toBeVisible()
}

test.describe("the panel of an action with a file argument", () => {
  for (const theme of ["light", "dark"] as const) {
    test(`has a file input for it: labelled, required, limited as the block says, and the first stop of the keyboard (${theme})`, async ({
      page,
    }) => {
      await page.addInitScript((theme) => localStorage.setItem("phx:theme", theme), theme)
      await labels.open()
      await expect(page.locator("html")).toHaveAttribute("data-theme", theme)

      await expect(labels.tableActions).toHaveText(["Count unused", "Recolour", "Remove unused", "Merge", "Import"])
      await labels.tableAction("import").focus()
      await page.keyboard.press("Enter")

      await expect(labels.panel).toBeVisible()
      await expect(labels.panel).toHaveAccessibleName("Import")
      await expect(labels.panelSubmit).toHaveText("Run")
      expect(await labels.fields()).toEqual(["file"])

      const input = fileInput(labels)
      await expect(input).toHaveCount(1)
      await expect(input).toHaveAccessibleName("File")
      await expect(input).toHaveAttribute("accept", ".csv")
      await expect(input).toHaveAttribute("aria-required", "true")
      await expect(input).not.toHaveAttribute("multiple")
      await expect(input).toBeFocused()
      await expectNoAxeViolations(page)

      // Tab goes on to the panel's buttons
      await page.keyboard.press("Tab")
      await expect(labels.panelCancel).toBeFocused()
      await page.keyboard.press("Tab")
      await expect(labels.panelSubmit).toBeFocused()

      await page.keyboard.press("Escape")
      await expect(labels.panel).toHaveCount(0)
      await expect(labels.tableAction("import")).toBeFocused()
    })
  }

  test.describe("as the member", () => {
    test.use({ actor: "member" })

    test("is not offered: the action is an admin's", async () => {
      await expect(labels.tableActions).toHaveText(["Count unused"])
    })
  })
})

test.describe("Run", () => {
  test("sends the file and gives it to the action, which reads it: a label per line", async ({ page, frames }) => {
    await openImport(labels)
    await fileInput(labels).setInputFiles(csv("labels.csv", "zebra,#00aa00\nyak\n"))
    await labels.panelSettled()
    await frames.clear()

    // by keyboard: Enter on "Run"
    await labels.panelSubmit.focus()
    await page.keyboard.press("Enter")

    await expect(labels.panel).toHaveCount(0)
    await expect(labels.result).toHaveText("Import: 2")
    await expect(labels.rows).toHaveCount(SEED.labels.acme + 2)
    expect(await labels.columnTexts("name")).toEqual(expect.arrayContaining(["yak", "zebra"]))
    expect(await frames.count("panel_submit")).toBe(1)

    const zebra = labels.rows.filter({ hasText: "zebra" })
    await expect(zebra.locator('td[id$="-c-colour"]')).toHaveText("#00aa00")
  })

  test("a bar under the input says how far the file has come while it is sent", async ({ page }) => {
    await openImport(labels)
    // one label, and 90 kB of empty lines after it: sent in two parts
    await fileInput(labels).setInputFiles(csv("labels.csv", "zebra\n" + "\n".repeat(90_000)))
    await labels.panelSettled()
    await expect(labels.panel.locator("progress")).toHaveCount(0)

    // every bar the page shows from here on, with what it says
    await page.evaluate(() => {
      const seen: string[] = []
      ;(window as any).__bars = seen
      new MutationObserver(() => {
        for (const bar of document.querySelectorAll("progress")) {
          seen.push(`${bar.getAttribute("aria-label")}: ${bar.getAttribute("value")} of ${bar.getAttribute("max")}`)
        }
      }).observe(document.body, { childList: true, subtree: true, attributes: true })
    })

    await labels.panelSubmit.click()
    await expect(labels.panel).toHaveCount(0)
    await expect(labels.result).toHaveText("Import: 1")

    const bars: string[] = await page.evaluate(() => (window as any).__bars)
    expect(bars.length).toBeGreaterThan(0)
    for (const bar of bars) expect(bar).toMatch(/^labels\.csv: [1-9][0-9]? of 100$/)
  })

  test("without a file says at the field what the action says of an empty argument", async ({ page }) => {
    await openImport(labels)
    await labels.panelSubmit.click()
    await labels.panelSettled()

    await expect(labels.panel).toBeVisible()
    const input = fileInput(labels)
    await expect(input).toHaveAttribute("aria-invalid", "true")
    await expect(input).toHaveAccessibleDescription("is required")
    await expect(labels.root.locator('[id="label-status"]')).toHaveText("Import failed: File: is required")
    await expectNoAxeViolations(page)
    await expect(labels.rows).toHaveCount(SEED.labels.acme)
  })

  test("what the action says of the file is shown at the field; another file takes its place, and runs", async ({
    page,
  }) => {
    await openImport(labels)
    const input = fileInput(labels)

    await input.setInputFiles(csv("labels.csv", "zebra,#00aa00\nyak,red\n"))
    await labels.panelSubmit.click()
    await labels.panelSettled()

    await expect(labels.panel).toBeVisible()
    await expect(input).toHaveAttribute("aria-invalid", "true")
    await expect(input).toHaveAccessibleDescription(/^line 2: colour must match/)
    // nothing of the file was made
    await expect(labels.rows).toHaveCount(SEED.labels.acme)
    // a file is given once: the input is empty again, as the server's is
    expect(await input.evaluate((element) => (element as HTMLInputElement).files!.length)).toBe(0)
    await expectNoAxeViolations(page)

    // another file: what was said of the first is said no longer
    await input.setInputFiles(csv("better.csv", "zebra,#00aa00\nyak,#aa0000\n"))
    await labels.panelSettled()
    await expect(input).not.toHaveAttribute("aria-invalid")
    await expect(labels.panel.locator("[data-error]")).toHaveCount(0)

    await labels.panelSubmit.click()
    await expect(labels.panel).toHaveCount(0)
    await expect(labels.result).toHaveText("Import: 2")
    await expect(labels.rows).toHaveCount(SEED.labels.acme + 2)
  })

  test("\"Run\" again without choosing a file runs without one: the action says that it is required", async () => {
    await openImport(labels)
    const input = fileInput(labels)

    await input.setInputFiles(csv("labels.csv", "yak,red\n"))
    await labels.panelSubmit.click()
    await labels.panelSettled()
    await expect(input).toHaveAccessibleDescription(/^line 1: colour must match/)

    await labels.panelSubmit.click()
    await labels.panelSettled()
    await expect(input).toHaveAccessibleDescription("is required")
    await expect(labels.rows).toHaveCount(SEED.labels.acme)
  })
})

test.describe("a file the upload does not take", () => {
  test("too large: said at the field as it is chosen, read out, and nothing runs", async ({ page, frames }) => {
    await openImport(labels)
    const input = fileInput(labels)

    await input.setInputFiles(csv("large.csv", "a,#000000\n".repeat(12_000)))
    await labels.panelSettled()

    await expect(input).toHaveAttribute("aria-invalid", "true")
    await expect(input).toHaveAccessibleDescription("The file is too large. The limit is 100 kB.")
    await expect(labels.root.locator('[id="label-status"]')).toHaveText(
      "File: The file is too large. The limit is 100 kB.",
    )
    await expectNoAxeViolations(page)

    await labels.panelSubmit.click()
    await labels.panelSettled()
    await expect(labels.panel).toBeVisible()
    await expect(labels.rows).toHaveCount(SEED.labels.acme)

    // a file that fits takes its place
    await input.setInputFiles(csv("small.csv", "zebra\n"))
    await labels.panelSettled()
    await expect(input).not.toHaveAttribute("aria-invalid")
    await frames.clear()
    await labels.panelSubmit.click()
    await expect(labels.panel).toHaveCount(0)
    await expect(labels.result).toHaveText("Import: 1")
  })

  test("of another kind than the block accepts", async () => {
    await openImport(labels)
    const input = fileInput(labels)

    await input.setInputFiles({ name: "labels.txt", mimeType: "text/plain", buffer: Buffer.from("zebra\n") })
    await labels.panelSettled()

    await expect(input).toHaveAttribute("aria-invalid", "true")
    await expect(input).toHaveAccessibleDescription("This type of file is not accepted.")
  })
})

test.describe("in German", () => {
  test("the button, the field and what it says of a file are in the table's language", async ({ page }) => {
    await switchLocale(page, "de")
    await labels.ready()

    await expect(labels.tableAction("import")).toHaveText("Importieren")
    await labels.tableAction("import").click()
    const input = fileInput(labels)
    await expect(input).toHaveAccessibleName("Datei")

    await input.setInputFiles(csv("large.csv", "a,#000000\n".repeat(12_000)))
    await labels.panelSettled()
    await expect(input).toHaveAccessibleDescription("Die Datei ist zu groß. Die Grenze liegt bei 100 kB.")
  })
})

test.describe("in a nested table", () => {
  // The labels under a task: "Import" is on their line, and the panel it
  // opens is the nested table's, drawn into the task's row by a portal
  // (stage 5). Its file input is that table's upload: the file reaches the
  // action, and a label is made of it. (Moved here from the demo test
  // "the labels under a task have the action on their line…", whose
  // LiveView test cannot reach a file input inside a portal.)
  test("its panel has the upload of the nested table, which sends the file to the action", async ({ page }) => {
    const tasks = new Table(page, "task", "/tasks")
    await tasks.open()
    const nested = await tasks.openLine(SEED.task.second, "labels")

    await tasks.lineAction(SEED.task.second, "labels", "import").click()
    await expect(nested.panel).toBeVisible()
    expect(await nested.fields()).toEqual(["file"])

    await fileInput(nested).setInputFiles(csv("labels.csv", "idea\n"))
    await nested.panelSettled()
    await nested.panelSubmit.click()

    await expect(nested.panel).toHaveCount(0)
    await expect(nested.result).toHaveText("Import: 1")

    await labels.open()
    expect(await labels.columnTexts("name")).toEqual(expect.arrayContaining(["idea"]))
  })
})
