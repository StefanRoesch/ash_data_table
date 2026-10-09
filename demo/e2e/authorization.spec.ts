import { ACTOR_KEYS, switchActor, type Actor } from "./support/actors"
import { SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { Table } from "./support/table"
import { params } from "./support/url"

// Spec section 10: the table has no rules of its own. It asks Ash as the
// person who opened the page and shows the answer. The demo's five actors
// get five different tables at /tasks (demo/README.md, "/tasks, actor by
// actor").

/** The columns the admin can edit; the member and the outsider can edit them on their own tasks. */
const EDITABLE = [
  "title",
  "status",
  "priority",
  "progress",
  "estimate_hours",
  "billable?",
  "due_on",
  "completed_at",
  "description",
  "tags",
  "checks",
]

// `actions` says whether the grid has the column of the row actions: the
// person can run one of them on some record (actions.spec.ts).
const TASKS: Record<Actor, { columns: number; editors: number; actions: boolean; range: string | null }> = {
  admin: { columns: 19, editors: 11, actions: true, range: "1–25 of 320" },
  member: { columns: 18, editors: 11, actions: true, range: "1–25 of 320" },
  // may not read people: no assignee, no reporter
  viewer: { columns: 16, editors: 0, actions: false, range: "1–25 of 320" },
  outsider: { columns: 18, editors: 11, actions: true, range: "1–25 of 80" },
  // may not read projects, and sees no estimate
  nobody: { columns: 16, editors: 0, actions: false, range: null },
}

for (const actor of ACTOR_KEYS) {
  test.describe(`/tasks as the ${actor}`, () => {
    test.use({ actor })

    test("the columns, the editors and the records are this person's", async ({ page, tasks }) => {
      const expected = TASKS[actor]
      await tasks.open()
      const columns = await tasks.columns()

      expect(columns).toHaveLength(expected.columns)
      // The columns, before them the one of the expanders, and for a person
      // who can run any action two more: the boxes that select a row in
      // front of everything, and the actions after everything.
      const all = expected.columns + 1 + (expected.actions ? 2 : 0)
      await expect(tasks.grid).toHaveAttribute("aria-colcount", String(all))
      await expect(tasks.headerCells).toHaveCount(all)
      await expect(tasks.actionsHeader).toHaveCount(expected.actions ? 1 : 0)
      await expect(tasks.editorTemplates).toHaveCount(expected.editors)

      if (expected.range) {
        await expect(tasks.range).toHaveText(expected.range)
        await expect(tasks.rows).toHaveCount(25)
      } else {
        await expect(tasks.rows).toHaveCount(0)
        await expect(tasks.empty).toHaveText("No records")
        await expect(tasks.error, "nothing was refused: there is nothing to see").toHaveCount(0)
      }

      // `external_ref` is the admins' alone; `estimate_hours` is the admins'
      // and each task's assignee's, and nobody is no task's assignee
      expect(columns.includes("external_ref")).toBe(actor === "admin")
      expect(columns.includes("estimate_hours")).toBe(actor !== "nobody")
    })

    if (actor !== "admin") {
      test("nothing in the page mentions the column that was left out", async ({ page, tasks }) => {
        await tasks.open()
        const html = await page.content()

        expect(html).not.toMatch(/external/i)
        // what the seed puts into the field
        expect(html).not.toContain("EXT-")
        await expect(tasks.header("external_ref")).toHaveCount(0)
        await expect(tasks.filterCell("external_ref")).toHaveCount(0)
        await expect(tasks.grid.locator('[id$="-c-external_ref"]')).toHaveCount(0)
      })

      test("a URL that sorts and filters by that column shows the plain page", async ({ tasks }) => {
        await tasks.open()
        const plain = await tasks.rowKeys()

        await tasks.open("/tasks?task[sort]=external_ref&task[f][external_ref]=EXT")
        expect(await tasks.rowKeys()).toEqual(plain)
        await expect(tasks.clearFilters).toHaveCount(0)
        await expect(tasks.grid.locator('[aria-sort="ascending"]')).toHaveCount(0)
      })
    }
  })
}

test.describe("the member, whose rights depend on the record", () => {
  test.use({ actor: "member" })

  test("the smaller grid is whole: the boxes, the expanders, 18 columns and the actions, numbered 1 to 21, walked without a gap", async ({
    tasks,
    frames,
  }) => {
    await tasks.open()
    const first = await tasks.rowKey(1)
    const numbering = (selector: string) =>
      tasks.grid
        .locator(selector)
        .evaluateAll((cells) =>
          cells.map((cell) => [
            (cell as HTMLTableCellElement).cellIndex + 1,
            Number(cell.getAttribute("aria-colindex")),
          ]),
        )
    const oneToTwentyOne = Array.from({ length: 21 }, (_, index) => [index + 1, index + 1])

    expect(await numbering(`[id="task-row-${first}"] td`)).toEqual(oneToTwentyOne)
    expect(await numbering("#task-head-row th")).toEqual(oneToTwentyOne)
    expect(await numbering("#task-filter-row td")).toEqual(oneToTwentyOne)

    await tasks.cell(first, "title").focus()
    await frames.clear()
    const walked = [await tasks.focused()]
    for (let step = 0; step < 22; step++) {
      await tasks.press("ArrowRight")
      const focused = await tasks.focused()
      if (focused === walked.at(-1)) break
      walked.push(focused)
    }
    const columns = await tasks.columns()
    // every column, and after the last the cell of the row's actions
    expect(walked).toEqual([
      ...columns.map((column) => `task-row-${first}-c-${column}`),
      `task-row-${first}-a`,
    ])
    // where the admin has `external_ref` between these two
    expect(columns.slice(10)).toEqual([
      "headline",
      "description",
      "tags",
      "checks",
      "inserted_at",
      "project",
      "assignee",
      "reporter",
    ])

    await tasks.press("Home", "End", "ArrowUp", "ArrowUp", "ArrowUp")
    await expect(tasks.actionsHeader).toBeFocused()
    await tasks.press("ArrowLeft")
    await expect(tasks.header("reporter")).toBeFocused()
    expect(await frames.all()).toEqual([])
    expect(await tasks.tabStops()).toHaveLength(1)
  })

  test("a field hidden on some records keeps its column: the hidden cells say so and cannot be edited", async ({
    tasks,
    frames,
  }) => {
    await tasks.open()
    // the member sees the estimate of the tasks assigned to them
    const own = tasks.cell(SEED.task.membersOwn, "estimate_hours")
    const hidden = tasks.cell(SEED.task.first, "estimate_hours")

    await expect(own).toHaveText("11.25 h")
    await expect(own).not.toHaveAttribute("aria-readonly")

    await expect(hidden, "read out, and nothing to see").toHaveText("Not available")
    await expect(hidden.locator(".sr-only")).toHaveText("Not available")
    await expect(hidden).toHaveAttribute("aria-readonly", "true")

    await hidden.focus()
    await frames.clear()
    await tasks.press("Enter", "F2", "7", "x")
    await hidden.dblclick()
    await expect(tasks.openEditors).toHaveCount(0)
    await expect(hidden).toBeFocused()
    expect(await frames.all()).toEqual([])
  })

  test("a filter on a field hidden on some records finds only what the member may see of it", async ({
    tasks,
  }) => {
    await tasks.open()

    await tasks.filterOperator("estimate_hours").selectOption("greater_than")
    await tasks.filterValue("estimate_hours").fill("10")
    await tasks.reads(() => tasks.filterValue("estimate_hours").press("Enter"))
    const found = await tasks.columnTexts("estimate_hours")
    expect(found.length).toBeGreaterThan(0)
    // "12.5 h": the number, and the unit of the column's component
    for (const estimate of found) expect(Number.parseFloat(estimate)).toBeGreaterThan(10)

    // a hidden estimate looks empty to the member, whatever it holds
    await tasks.reads(() => tasks.filterOperator("estimate_hours").selectOption("is_empty"))
    expect(await tasks.columnTexts("estimate_hours")).toContain("Not available")
  })

  test.describe("saving", () => {
    test.use({ writes: true })

    test.beforeEach(async ({ tasks }) => {
      await tasks.open()
    })

    test("a task of their own is theirs to change", async ({ page, tasks }) => {
      const title = tasks.cell(SEED.task.membersOwn, "title")
      const estimate = tasks.cell(SEED.task.membersOwn, "estimate_hours")

      await title.focus()
      await tasks.press("Enter")
      await tasks.retype("Changed by the member")
      await tasks.saves(title, () => tasks.press("Enter"))
      await expect(title).toHaveText("Changed by the member")
      await expect(title).not.toHaveAttribute("aria-invalid")

      await estimate.focus()
      await tasks.press("Enter")
      await tasks.retype("12")
      await tasks.saves(estimate, () => tasks.press("Enter"))
      await expect(estimate).toHaveText("12 h")

      await page.reload()
      await tasks.ready()
      await expect(title).toHaveText("Changed by the member")
      await expect(estimate).toHaveText("12 h")
    })

    test("someone else's task looks editable and refuses on the cell when it is saved", async ({
      page,
      tasks,
    }) => {
      const title = tasks.cell(SEED.task.first, "title")
      await expect(title).not.toHaveAttribute("aria-readonly")

      await title.focus()
      await tasks.press("Enter")
      await expect(tasks.editor(title)).toBeFocused()
      await tasks.retype("Not mine to change")
      await tasks.saves(title, () => tasks.press("Enter"))

      await expect(title).toHaveAttribute("aria-invalid", "true")
      await expect(title).toContainText("Not mine to change")
      await expect(tasks.failure(title)).toHaveText("You are not allowed to change this.")
      await expect(tasks.failure(title)).toBeVisible()
      await expect(tasks.status).toHaveText(
        "Title was not saved: You are not allowed to change this.",
      )
      // the row was shown again as this person may see it
      await expect(tasks.cell(SEED.task.first, "estimate_hours")).toHaveText("Not available")

      await tasks.press("Escape")
      await expect(title).toHaveText("Rename the onboarding email")
      await expect(title).not.toHaveAttribute("aria-invalid")

      await page.reload()
      await tasks.ready()
      await expect(title, "nothing was saved").toHaveText("Rename the onboarding email")
    })
  })
})

test.describe("the viewer, who may change nothing", () => {
  test.use({ actor: "viewer" })

  test("the table offers no editing: nothing is marked read-only, and there are no editors in the page", async ({
    tasks,
  }) => {
    await tasks.open()

    await expect(tasks.grid.locator("[aria-readonly]")).toHaveCount(0)
    await expect(tasks.root.locator("template")).toHaveCount(0)
    await expect(tasks.root.locator("dialog")).toHaveCount(0)
    await expect(tasks.grid.locator("[data-value]")).toHaveCount(0)
  })

  test("no gesture opens an editor in any column", async ({ tasks, frames }) => {
    await tasks.open()
    const first = await tasks.rowKey(1)
    await frames.clear()

    for (const column of EDITABLE) {
      const cell = tasks.cell(first, column)
      await cell.focus()
      for (const key of ["Enter", "F2", "x", "5"]) {
        await tasks.press(key)
        await expect(tasks.openEditors, `${key} on ${column}`).toHaveCount(0)
        await expect(cell, `${key} on ${column}`).toBeFocused()
      }
      await cell.dblclick()
      await expect(tasks.openEditors, `a double click on ${column}`).toHaveCount(0)
    }

    expect(await frames.all(), "and the server was asked nothing").toEqual([])
  })

  test("reading works as for anyone: moving, sorting, filtering", async ({ page, tasks }) => {
    await tasks.open()
    const first = await tasks.rowKey(1)

    await tasks.cell(first, "title").focus()
    await tasks.press("ArrowRight")
    await expect(tasks.cell(first, "status")).toBeFocused()

    await tasks.reads(() => tasks.header("title").click())
    await expect(tasks.header("title")).toHaveAttribute("aria-sort", "ascending")
    await tasks.reads(() => tasks.filterValue("billable?").selectOption("yes"))
    expect(params(page)).toEqual({ "task[sort]": "title", "task[f][billable?]": "yes" })
    await expect(tasks.range).toHaveText("1–25 of 128")
  })
})

test.describe("the outsider, of the other organization", () => {
  test.use({ actor: "outsider" })

  test("sees their organization's tasks, and none of the other's", async ({ tasks }) => {
    await tasks.open()

    await expect(tasks.range).toHaveText(`1–25 of ${SEED.tasks.globex}`)
    const keys = await tasks.rowKeys()
    for (const acme of Object.values(SEED.task)) expect(keys).not.toContain(acme)

    // nor by a filter that would find them
    await tasks.filterValue("title").fill("Rename the onboarding email")
    await tasks.reads(() => tasks.filterValue("title").press("Enter"))
    for (const key of await tasks.rowKeys()) expect(key).not.toBe(SEED.task.first)
  })
})

test.describe("switching the actor", () => {
  test("the same page becomes the next person's table", async ({ page, tasks }) => {
    await tasks.open()
    const shape = async () => ({
      columns: (await tasks.columns()).length,
      editors: await tasks.editorTemplates.count(),
      records: (await tasks.rows.count()) > 0,
    })
    const of = (actor: Actor) => ({
      columns: TASKS[actor].columns,
      editors: TASKS[actor].editors,
      records: TASKS[actor].range !== null,
    })
    expect(await shape()).toEqual(of("admin"))

    for (const actor of ["viewer", "member", "nobody", "outsider", "admin"] as const) {
      await switchActor(page, actor)
      await tasks.ready()
      expect(new URL(page.url()).pathname, "the switcher comes back to the page").toBe("/tasks")
      expect(await shape(), actor).toEqual(of(actor))
    }
  })

  test("the switcher keeps the table's state, as far as the next person may have it", async ({
    page,
    tasks,
  }) => {
    await tasks.open("/tasks?task[sort]=-progress&task[f][external_ref]=EXT")
    await expect(tasks.filterValue("external_ref")).toHaveValue("EXT")
    const filtered = await tasks.range.textContent()

    await switchActor(page, "member")
    await tasks.ready()
    await expect(tasks.header("progress")).toHaveAttribute("aria-sort", "descending")
    await expect(tasks.range, "the filter on the column they cannot see is dropped").toHaveText(
      "1–25 of 320",
    )
    expect(filtered).not.toBe("1–25 of 320")
    await expect(tasks.clearFilters).toHaveCount(0)
  })
})

test.describe("a read that is refused outright", () => {
  test.use({ actor: "nobody" })

  test("/projects answers as a page that does not exist", async ({ page, consoleErrors }) => {
    // the browser's own report of the answer it got
    consoleErrors.allow(/404 \(Not Found\)/)

    const response = await page.goto("/projects")
    expect(response!.status()).toBe(404)

    const html = await page.content()
    expect(html).not.toContain("project-table")
    expect(html).not.toContain("No records")
    expect(html).not.toContain("not allowed")
    await expect(page.getByRole("grid")).toHaveCount(0)
  })

  test("a live navigation to /projects ends at the same answer", async ({ page, consoleErrors }) => {
    // LiveView's reports of the mount that was refused, and the browser's of the 404
    consoleErrors.allow(/404|Not Found|failed mount|unable to join/i)

    await page.goto("/")
    await expect(page.locator(".phx-connected").first()).toBeVisible()

    const answer = page.waitForResponse(
      (response) =>
        new URL(response.url()).pathname === "/projects" &&
        response.request().resourceType() === "document",
    )
    await page.getByRole("link", { name: "/projects" }).click()

    expect((await answer).status()).toBe(404)
    await expect(page).toHaveURL(/\/projects$/)
    await expect(page.getByRole("grid")).toHaveCount(0)
    expect(await page.content()).not.toContain("No records")
  })

  test("/comments, declared with `on_forbidden :message`, stays and says so", async ({ page }) => {
    const comments = new Table(page, "comment", "/comments")
    const response = await page.goto("/comments")
    expect(response!.status()).toBe(200)
    await comments.ready()

    await expect(comments.error).toHaveText("You are not allowed to see these records.")
    await expect(comments.rows).toHaveCount(0)
    await expect(comments.empty, "a refusal is not an empty table").toHaveCount(0)
    await expect(comments.pagination).toHaveCount(0)
    expect(await page.content()).not.toContain("No records")
  })

  test("a read that is only filtered shows an empty table", async ({ page }) => {
    for (const [path, id] of [
      ["/labels", "label"],
      ["/bare/labels", "label"],
      ["/task_labels", "task_label"],
    ]) {
      const table = new Table(page, id, path)
      const response = await table.open()
      expect(response!.status(), path).toBe(200)
      await expect(table.empty, path).toHaveText("No records")
      await expect(table.error, path).toHaveCount(0)
    }
  })

  test("/specimens has no policy: its records are anyone's to see and to edit", async ({ page }) => {
    const specimens = new Table(page, "specimen", "/specimens")
    await specimens.open()

    await expect(specimens.rows).toHaveCount(20)
    expect(await specimens.editorTemplates.count()).toBeGreaterThan(0)
  })
})

test.describe("a read that is allowed", () => {
  test.use({ actor: "viewer" })

  test("/projects is there for the viewer", async ({ page }) => {
    const projects = new Table(page, "project", "/projects")
    const response = await projects.open()

    expect(response!.status()).toBe(200)
    await expect(projects.rows).toHaveCount(SEED.projects.acme)
  })
})
