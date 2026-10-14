import { expect, test } from "./support/fixtures"
import { deleteTask, SEED } from "./support/data"
import { switchLocale } from "./support/locale"
import { Table } from "./support/table"
import { params } from "./support/url"

// The language switcher in the page header (DemoWeb.Locale): the tables look
// their texts up in the locale of the process they run in. In German the
// table's own words are German, the labels a resource's translations have,
// and the messages of the actions; the demo's own pages stay in English. The
// chosen language is in the session cookie, which every test has to itself.

const SECOND = SEED.task.second

test.describe("the switcher", () => {
  test("is in the header, between the actor switcher and the theme toggle; English at first", async ({
    page,
    tasks,
  }) => {
    await tasks.open()
    await expect(page.locator("html")).toHaveAttribute("lang", "en")

    const language = page.getByRole("combobox", { name: "Language" })
    await expect(language).toHaveId("locale-switcher-select")
    await expect(language.locator("option")).toHaveText(["English", "Deutsch"])
    await expect(language.locator("option:checked")).toHaveText("English")
    // each choice is written in its own language, and says so
    await expect(language.getByRole("option", { name: "English" })).toHaveAttribute("lang", "en")
    await expect(language.getByRole("option", { name: "Deutsch" })).toHaveAttribute("lang", "de")

    const header = await page
      .locator("header > *")
      .evaluateAll((parts) => parts.map((part) => part.id || part.tagName))
    expect(header.slice(1, 3)).toEqual(["actor-switcher", "locale-switcher"])
    expect(header).toHaveLength(4)
    await expect(page.locator("header > *").last().getByRole("button")).toHaveCount(3)
  })

  test("comes back to the page it was used on, with the table's state", async ({ page, tasks }) => {
    await tasks.open("/tasks?task[sort]=-title&task[page]=2&task[f][billable?]=yes")
    const keys = await tasks.rowKeys()

    await switchLocale(page, "de")
    await tasks.ready()
    expect(new URL(page.url()).pathname).toBe("/tasks")
    expect(params(page)).toEqual({
      "task[sort]": "-title",
      "task[page]": "2",
      "task[f][billable?]": "yes",
    })
    expect(await tasks.rowKeys()).toEqual(keys)
    await expect(page.getByLabel("Language").locator("option:checked")).toHaveText("Deutsch")
    await expect(tasks.header("title")).toHaveAttribute("aria-sort", "descending")
    await expect(tasks.range).toHaveText("26–50 von 128")
  })

  test("the language stays through reloads and navigation, and English comes back", async ({
    page,
    tasks,
  }) => {
    await tasks.open()
    await switchLocale(page, "de")
    await tasks.ready()
    await expect(tasks.headers.first()).toHaveText("Titel")

    await page.reload()
    await tasks.ready()
    await expect(page.locator("html")).toHaveAttribute("lang", "de")
    await expect(tasks.headers.first()).toHaveText("Titel")

    // a live navigation from the front page: the LiveView has the locale too
    await page.goto("/")
    await page.getByRole("link", { name: "/tasks", exact: true }).click()
    await tasks.ready()
    await expect(tasks.headers.first()).toHaveText("Titel")
    await expect(tasks.next).toHaveCount(0)
    await expect(tasks.pagination.getByRole("button", { name: "Weiter", exact: true })).toBeEnabled()

    await switchLocale(page, "en")
    await tasks.ready()
    await expect(page).toHaveTitle("Tasks · ash_data_table demo")
    await expect(page.getByRole("heading", { level: 1 })).toHaveText("Tasks")
    await expect(tasks.headers.first()).toHaveText("Title")
    await expect(tasks.pagination).toHaveAccessibleName("Pagination: Tasks")
    await expect(tasks.range).toHaveText("1–25 of 320")
    await expect(tasks.next).toBeEnabled()
    await expect(tasks.filterValue("status").locator("option").first()).toHaveText("Any")
  })
})

test.describe("in German", () => {
  test.beforeEach(async ({ page, tasks }) => {
    await tasks.open()
    await switchLocale(page, "de")
    await tasks.ready()
  })

  test("the page, the columns and the grid are named in German; the demo's own header is not", async ({
    page,
    tasks,
  }) => {
    await expect(page).toHaveTitle("Aufgaben · ash_data_table demo")
    await expect(page.getByRole("heading", { level: 1 })).toHaveText("Aufgaben")
    await expect(page.getByRole("grid", { name: "Aufgaben" })).toHaveId("task-table")
    await expect(tasks.headers).toHaveText([
      "Titel",
      "Status",
      "Priorität",
      "Fortschritt",
      "Geschätzte Stunden",
      "Abrechenbar?",
      "Fällig am",
      "Erledigt am",
      "Überfällig?",
      "Kommentare",
      "Überschrift",
      "Fällig binnen 7 Tagen",
      "Fällig binnen",
      "Externe Referenz",
      "Beschreibung",
      "Schlagwörter",
      "Prüfungen",
      "Wiederholung",
      "Angelegt am",
      "Projekt",
      "Zugewiesen an",
      "Gemeldet von",
    ])

    await expect(page.getByRole("navigation", { name: "Main" }).getByRole("link")).toHaveText([
      "ash_data_table demo",
      "Tasks",
      "Deadlines",
      "Projects",
      "Comments",
      "Labels",
      "Specimens",
      "Dashboard",
      "Named tables",
    ])
    await expect(page.getByLabel("Acting as")).toBeVisible()
  })

  test("the cells: choices and booleans in German, the records' own text as it is", async ({
    tasks,
  }) => {
    const states = ["Rückstand", "Zu erledigen", "In Arbeit", "In Prüfung", "Erledigt", "Archiviert"]
    for (const state of await tasks.columnTexts("status")) expect(states).toContain(state)
    const priorities = ["Niedrig", "Mittel", "Hoch", "Dringend"]
    for (const priority of await tasks.columnTexts("priority")) expect(priorities).toContain(priority)
    for (const text of await tasks.columnTexts("billable?")) expect(text).toMatch(/^(✓Ja|–Nein)$/)

    await expect(tasks.cell(SECOND, "status")).toHaveText("Zu erledigen")
    await expect(tasks.cell(SECOND, "priority")).toHaveText("Mittel")
    await expect(tasks.cell(SECOND, "billable?")).toHaveText("–Nein")
    await expect(tasks.cell(SECOND, "title")).toHaveText("Remove the dashboard charts")
    // a calculation's text is the resource's
    await expect(tasks.cell(SECOND, "headline")).toHaveText("Medium: Remove the dashboard charts (5%)")
  })

  test("the pagination: its name, the range, the buttons and the page numbers", async ({
    page,
    tasks,
  }) => {
    await expect(tasks.pagination).toHaveAccessibleName("Seiten: Aufgaben")
    await expect(tasks.pagination.getByRole("button")).toHaveText([
      "Zurück",
      "1",
      "2",
      "3",
      "13",
      "Weiter",
    ])
    await expect(tasks.range).toHaveText("1–25 von 320")
    await expect(page.getByRole("button", { name: "Zu Seite 2", exact: true })).toHaveId("task-page-2")

    const next = tasks.pagination.getByRole("button", { name: "Weiter", exact: true })
    await next.focus()
    await tasks.reads(() => tasks.press("Enter"))
    await expect(tasks.range).toHaveText("26–50 von 320")
    await expect(next).toBeFocused()

    await tasks.open("/tasks?task[page]=99")
    await expect(tasks.range).toHaveText("Seite 99")
    await expect(tasks.empty).toHaveText("Keine Einträge")
  })

  test("the filter row: the names of its controls, the operators and the choices", async ({
    page,
    tasks,
  }) => {
    await expect(page.getByRole("textbox", { name: "Titel filtern", exact: true })).toHaveId(
      "task-filter-title-value",
    )
    await expect(page.getByRole("combobox", { name: "Wie Titel gefiltert wird" })).toHaveId(
      "task-filter-title-operator",
    )
    const operators = (column: string) => tasks.filterOperator(column).locator("option")
    await expect(operators("title")).toHaveText(["enthält", "ist gleich", "beginnt mit"])
    await expect(operators("external_ref")).toHaveText([
      "enthält",
      "ist gleich",
      "beginnt mit",
      "ist leer",
    ])
    await expect(operators("progress")).toHaveText([
      "ist gleich",
      "größer als",
      "kleiner als",
      "mindestens",
      "höchstens",
      "zwischen",
    ])
    await expect(operators("due_on")).toHaveText(["am", "vor", "nach", "zwischen", "ist leer"])
    await expect(operators("status")).toHaveText(["ist", "ist eines von", "ist keines von"])
    await expect(tasks.filterValue("status").locator("option")).toHaveText([
      "Alle",
      "Rückstand",
      "Zu erledigen",
      "In Arbeit",
      "In Prüfung",
      "Erledigt",
      "Archiviert",
    ])
    await expect(tasks.filterValue("billable?").locator("option")).toHaveText(["Alle", "Ja", "Nein"])

    // a value the column cannot hold
    await tasks.filterValue("progress").focus()
    await page.keyboard.type("1.5")
    await tasks.press("Enter")
    await expect(tasks.filterError("progress")).toHaveText("Kein gültiger Wert")
  })

  test("what is read out counts in German: one result, and several", async ({ page, tasks }) => {
    await tasks.filterValue("title").fill("sess")
    await tasks.reads(() => tasks.filterValue("title").press("Enter"))
    await expect(tasks.status).toHaveText("18 Ergebnisse")
    await expect(tasks.range).toHaveText("1–18 von 18")
    await expect(page.getByRole("button", { name: "Filter Titel zurücksetzen" })).toHaveId(
      "task-filter-title-clear",
    )

    await tasks.reads(() => tasks.filterOperator("title").selectOption({ label: "ist gleich" }))
    await expect(tasks.status).toHaveText("0 Ergebnisse")
    await expect(tasks.empty).toHaveText("Keine Einträge")

    await tasks.filterValue("title").fill("Add error messages")
    await tasks.reads(() => tasks.filterValue("title").press("Enter"))
    await expect(tasks.status).toHaveText("1 Ergebnis")
    await expect(tasks.range).toHaveText("1–1 von 1")

    const clear = page.getByRole("button", { name: "Filter zurücksetzen", exact: true })
    await expect(clear).toHaveId("task-clear-filters")
    await tasks.reads(() => clear.click())
    await expect(tasks.status).toHaveText("320 Ergebnisse")
  })

  test("a keyset table says how many records there are, and how many a filter found", async ({
    page,
  }) => {
    const comments = new Table(page, "comment", "/comments")
    await comments.open()
    await expect(comments.pagination).toHaveAccessibleName("Seiten: Kommentare")
    await expect(comments.pagination.getByRole("button")).toHaveText(["Zurück", "Weiter"])
    await expect(comments.range).toHaveText(`${SEED.comments.acme} Einträge`)
    await comments.filterValue("body").fill("sprint")
    await comments.reads(() => comments.filterValue("body").press("Enter"))
    await expect(comments.status).toHaveText(`${SEED.comments.nextSprint} Ergebnisse`)
    await expect(comments.range).toHaveText(`${SEED.comments.nextSprint} Einträge`)
  })

  test.describe("a save that fails", () => {
    test("says so with the action's message in German, on the cell and read out", async ({
      tasks,
    }) => {
      const tooShort = "muss mindestens 3 Zeichen lang sein"
      const title = tasks.cell(SECOND, "title")
      await title.focus()
      await tasks.press("Enter")
      await expect(tasks.editor(title)).toHaveAccessibleName("Titel")
      await tasks.retype("ab")
      await tasks.saves(title, () => tasks.press("Enter"))

      await expect(title).toHaveAttribute("aria-invalid", "true")
      await expect(tasks.failure(title)).toHaveText(tooShort)
      await expect(title).toHaveAccessibleDescription(tooShort)
      await expect(tasks.status).toHaveText(`Titel wurde nicht gespeichert: ${tooShort}`)

      // the estimate has `min: 0`
      const estimate = tasks.cell(SECOND, "estimate_hours")
      await estimate.focus()
      await tasks.press("Enter")
      await tasks.retype("-3")
      await tasks.saves(estimate, () => tasks.press("Enter"))
      await expect(tasks.failure(estimate)).toHaveText("muss mindestens 0 sein")
      await expect(tasks.status).toHaveText(
        "Geschätzte Stunden wurde nicht gespeichert: muss mindestens 0 sein",
      )
    })

    test("an error about another field names that field in German; the question before it is German too", async ({
      page,
      tasks,
    }) => {
      // the menu of the browser would be in the way (see editing.spec.ts)
      await page.evaluate(() => {
        HTMLSelectElement.prototype.showPicker = () => {
          throw new DOMException("no menu in this test", "NotSupportedError")
        }
      })
      // a task can only be done with a progress of 100; this one has 5
      const status = tasks.cell(SECOND, "status")
      await status.focus()
      await tasks.press("Enter")
      await expect(tasks.editor(status).locator("option")).toHaveText([
        "Rückstand",
        "Zu erledigen",
        "In Arbeit",
        "In Prüfung",
        "Erledigt",
        "Archiviert",
      ])
      await tasks.editor(status).selectOption({ label: "Erledigt" })

      await expect(tasks.dialog).toBeVisible()
      await expect(tasks.dialog).toHaveAccessibleName("Den Status dieser Aufgabe ändern?")
      await expect(tasks.dialog.getByRole("button")).toHaveText(["Abbrechen", "Bestätigen"])
      await tasks.saves(status, () =>
        tasks.dialog.getByRole("button", { name: "Bestätigen" }).click(),
      )

      const message = "Fortschritt: muss 100 sein, wenn die Aufgabe erledigt ist"
      await expect(status).toHaveAttribute("aria-invalid", "true")
      await expect(status, "what was chosen").toContainText("Erledigt")
      await expect(tasks.failure(status)).toHaveText(message)
      await expect(tasks.status).toHaveText(`Status wurde nicht gespeichert: ${message}`)

      await status.focus()
      await tasks.press("Escape")
      await expect(status).toHaveText("Zu erledigen")
      await expect(status).not.toHaveAttribute("aria-invalid")
    })

    test.describe("a record that is gone", () => {
      test.use({ writes: true })

      test("says that it is no longer available", async ({ request, tasks }) => {
        const key = await tasks.rowKey(6)
        const title = tasks.cell(key, "title")
        await deleteTask(request, key)

        await title.focus()
        await tasks.press("Enter")
        await tasks.retype("Gone already")
        await tasks.saves(title, () => tasks.press("Enter"))
        await expect(tasks.failure(title)).toHaveText("Dieser Eintrag ist nicht mehr verfügbar.")
        await expect(tasks.status).toHaveText(
          "Titel wurde nicht gespeichert: Dieser Eintrag ist nicht mehr verfügbar.",
        )
      })
    })

    test.describe("as the member", () => {
      test.use({ actor: "member" })

      test("who may not change the task, and may not see a value", async ({ tasks }) => {
        await expect(tasks.cell(SEED.task.first, "estimate_hours")).toHaveText("Nicht verfügbar")

        const title = tasks.cell(SEED.task.first, "title")
        await title.focus()
        await tasks.press("Enter")
        await tasks.retype("Not mine to change")
        await tasks.saves(title, () => tasks.press("Enter"))
        await expect(tasks.failure(title)).toHaveText("Sie dürfen das nicht ändern.")
        await expect(tasks.status).toHaveText(
          "Titel wurde nicht gespeichert: Sie dürfen das nicht ändern.",
        )
      })
    })
  })

  test.describe("a read that fails or is refused", () => {
    test("a cursor that is none", async ({ page }) => {
      const comments = new Table(page, "comment", "/comments")
      await comments.open("/comments?comment[after]=nonsense")
      await expect(comments.error).toHaveText("Die Einträge konnten nicht geladen werden.")
    })

    test.describe("as nobody", () => {
      test.use({ actor: "nobody" })

      test("a table that says it is not allowed", async ({ page }) => {
        const comments = new Table(page, "comment", "/comments")
        await comments.open()
        await expect(comments.error).toHaveText("Sie dürfen diese Einträge nicht sehen.")
      })
    })
  })

  test("another table: its words are German, and its labels where the demo has a translation of them", async ({
    page,
  }) => {
    const projects = new Table(page, "project", "/projects")
    await projects.open()
    // "Description" and "Inserted at" are translated for the tasks, and a
    // label is looked up by its text; the others have no translation
    await expect(page.getByRole("heading", { level: 1 })).toHaveText("Projects")
    await expect(projects.headers).toHaveText([
      "ID",
      "Name",
      "Beschreibung",
      "Status",
      "Starts on",
      "Budget",
      "Kunde",
      "Meilensteine",
      "Angelegt am",
    ])
    await expect(projects.pagination).toHaveAccessibleName("Seiten: Projects")
    await expect(projects.range).toHaveText("1–6 von 6")
    await expect(projects.pagination.getByRole("button")).toHaveText(["Zurück", "1", "Weiter"])
    await expect(page.getByRole("textbox", { name: "Name filtern", exact: true })).toHaveId(
      "project-filter-name-value",
    )
  })

  test("the dashboard: both tables, each pagination with a name of its own", async ({ page }) => {
    const projects = new Table(page, "dashboard-projects", "/dashboard")
    const dashboardTasks = new Table(page, "dashboard-tasks", "/dashboard")
    await projects.open()
    await dashboardTasks.ready()

    // the page is the demo's own, and stays in English
    await expect(page.getByRole("heading", { level: 1 })).toHaveText("Dashboard")
    await expect(projects.pagination).toHaveAccessibleName("Seiten: Projects")
    await expect(dashboardTasks.pagination).toHaveAccessibleName("Seiten: Aufgaben")
    await expect(page.getByRole("grid", { name: "Aufgaben" })).toHaveId("dashboard-tasks-table")
    await expect(dashboardTasks.headers.first()).toHaveText("Titel")
    await expect(dashboardTasks.range).toHaveText("1–25 von 320")
  })
})
