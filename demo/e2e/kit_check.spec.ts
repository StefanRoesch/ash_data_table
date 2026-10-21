import type { Page } from "@playwright/test"
import { expect, test } from "./support/fixtures"
import { answered } from "./support/table"

// The kit check in the browser:
// the states and presentations of `AshDataTable.KitCase`, each reached as a
// person reaches it, by the table's controls, on /e2e/kit/states
// (`DemoWeb.E2E.KitStatesLive`: the table `KitCase` draws, with its records
// for the state, drawn with the kit the request asks for: the default kit
// in the `chromium` project, the React kit in the `react` one). At each
// state what the browser drew (`document.body.outerHTML`) goes to
// `AshDataTable.KitCase.problems/4` (`DemoWeb.E2E.KitCheckController`),
// which checks the markers, ids, `data-*` values, element kinds and Tab
// stops `KitCase` checks on the server, on what a kit that draws in the
// browser drew there; it says what is missing, and the test wants nothing.
//
// LiveView's client debug is on (asserted), so the hooks' development
// check runs (`check.js`, which says on the console which marker a part
// lacks), and so does the React kit's own (`props.ts`, which says when a
// bundle names an attribute the hooks own): a console error fails a test
// (the fixture `consoleErrors`).

const STATES = [
  "rows",
  "filtered",
  "empty",
  "error",
  "loading",
  "nested",
  "failed",
  "secret_failed",
  "panel",
  "rekey",
  "create",
  "create_failed",
  "list_panel",
  "map_panel",
  "groups_panel",
  "staff",
  "staff_picker",
  "picker",
  "selected",
  "links",
] as const
const PRESENTATIONS = ["modal", "inline", "mixed", "inside"] as const

type State = (typeof STATES)[number] | "filter_panel" | "row_selected" | "related" | "full_view"
type Presentation = (typeof PRESENTATIONS)[number]

// the sensitive value of the test resource (`AshDataTable.Test.Resource.secret/0`)
const SECRET = "kit-case-secret-4f1d"

class Kit {
  key = ""
  tenant = ""

  constructor(
    readonly page: Page,
    readonly presentation: Presentation,
  ) {}

  async open(state: State): Promise<void> {
    // LiveView's client debug, which it keeps for the tab (its documented
    // `enableDebug()`), on from the page's first patch
    await this.page.goto(`/e2e/kit/states?state=${state}&presentation=${this.presentation}`)
    await this.page.evaluate(() => (window as any).liveSocket.enableDebug())
    await this.page.reload()
    // connected: the join's patch, which mounts the hooks, is in the page
    await expect(this.page.locator(".phx-connected").first()).toBeAttached()
    const page = this.page.locator("#kit-states")
    await expect(page).toHaveAttribute("data-tenant", /^(kit|broken)-/)
    this.key = (await page.getAttribute("data-key")) ?? ""
    this.tenant = (await page.getAttribute("data-tenant")) ?? ""
    expect(await this.page.evaluate(() => (window as any).liveSocket.isDebugEnabled()), "LiveView's client debug").toBe(true)
  }

  byId(id: string) {
    return this.page.locator(`[id="${id}"]`)
  }

  row(key = this.key) {
    return `kit-row-${key}`
  }

  cell(column: string) {
    return this.byId(`${this.row()}-c-${column}`)
  }

  get panel() {
    return this.byId("kit-panel")
  }

  get picker() {
    return this.byId("kit-picker")
  }

  /** The question, as it is asked from where `from` is. */
  question(from: "page" | "panel" | "picker" = "page") {
    const inline = this.presentation !== "modal"
    const over = from !== "page" && (from === "panel" ? true : this.presentation !== "inside")
    return this.byId(inline && over ? `kit-dialog-in-${from}` : "kit-dialog")
  }

  /** What the browser drew, checked by `KitCase` as the state `state`. */
  async check(state: State): Promise<void> {
    await answered(this.page)
    const html = await this.page.evaluate(() => document.body.outerHTML)
    // no state the person did not type the sensitive value into holds it:
    // the server gives it to no kit (`KitCase` checks what React is given,
    // `client: true`)
    if (state !== "secret_failed" && state !== "create_failed") {
      expect(html.includes(SECRET), "the page holds the sensitive value").toBe(false)
    }
    const response = await this.page.request.post("/e2e/kit/check", {
      data: { html, state, presentation: this.presentation, key: this.key },
    })
    expect(response.ok()).toBe(true)
    const { problems } = await response.json()
    expect(problems, `the state ${state}, what opens ${this.presentation}`).toEqual([])
  }

  /** Opens a cell's editor and types into it, as a person does. */
  async typeInto(column: string, value: string): Promise<void> {
    const cell = this.cell(column)
    await cell.focus()
    await this.page.keyboard.press("Enter")
    const control = cell.locator("textarea, input:not([type=hidden])").first()
    await control.fill(value)
    await this.page.keyboard.press("Enter")
  }

  async expand(): Promise<void> {
    await this.byId(`${this.row()}-e`).locator("button").click()
    await expect(this.byId(`${this.row()}-l-parts-b`)).toBeVisible()
  }

  get nested() {
    return `${this.row()}-t-parts`
  }
}

for (const presentation of PRESENTATIONS) {
  test.describe(`what opens ${presentation}`, () => {
    for (const state of STATES) {
      test(`the state ${state}`, async ({ page }) => {
        const kit = new Kit(page, presentation)
        await kit.open(state)
        await reach[state](kit)
      })
    }
  })
}

// How each state is reached, and the states on the way that `KitCase`
// checks besides.
const reach: Record<(typeof STATES)[number], (kit: Kit) => Promise<void>> = {
  rows: async (kit) => {
    await expect(kit.byId(kit.row())).toBeVisible()
    await kit.check("rows")
  },

  filtered: async (kit) => {
    await kit.byId("kit-sort-size").click()
    await expect(kit.byId("kit-head-size")).toHaveAttribute("aria-sort", "ascending")
    await kit.page.locator('select[name="filter[tier][o]"]').selectOption("any_of")
    const values = kit.page.locator('[phx-click="ash_data_table:kit:filter_values"]')
    await values.click()
    await expect(kit.panel).toBeVisible()
    await kit.check("filter_panel")
    await kit.panel.getByRole("checkbox", { name: "Low", exact: true }).check()
    await kit.byId("kit-panel-submit").click()
    await expect(kit.panel).toHaveCount(0)
    await expect(kit.page.locator('[id^="kit-row-"][role=rowgroup]').filter({ hasText: "Anchor" })).toHaveCount(0)
    await kit.check("filtered")
  },

  empty: async (kit) => {
    await expect(kit.byId("kit-empty")).toBeVisible()
    await kit.check("empty")
  },

  error: async (kit) => {
    await expect(kit.byId("kit-error")).toBeVisible()
    await kit.check("error")
  },

  // The nested table's first read is on its way: what the browser drew in
  // the patch that says so (its "Loading…"), taken in that patch, before
  // the read's answer can come (a `MutationObserver`'s callback runs once
  // the patch, and the islands it drew, are in the page, before the page
  // takes the next message).
  loading: async (kit) => {
    await kit.expand()
    const nested = kit.nested
    await kit.page.evaluate((nested) => {
      ;(window as any).__kitLoading = new Promise<string>((resolve) => {
        const observer = new MutationObserver(() => {
          if (document.getElementById(`${nested}-loading`)) {
            observer.disconnect()
            resolve(document.body.outerHTML)
          }
        })
        observer.observe(document.body, { subtree: true, childList: true })
      })
    }, nested)
    await kit.byId(`${kit.row()}-l-parts-b`).click()
    const html: string = await kit.page.evaluate(() => (window as any).__kitLoading)
    const response = await kit.page.request.post("/e2e/kit/check", {
      data: { html, state: "loading", presentation: kit.presentation, key: kit.key },
    })
    expect((await response.json()).problems, `the state loading, what opens ${kit.presentation}`).toEqual([])
  },

  nested: async (kit) => {
    await kit.expand()
    await kit.byId(`${kit.row()}-l-parts-b`).click()
    await expect(kit.page.locator(`[id^="${kit.nested}-row-"][role=rowgroup]`).filter({ hasText: "Pin" })).toHaveCount(1)
    await kit.check("nested")
  },

  failed: async (kit) => {
    await kit.typeInto("name", "")
    await expect(kit.cell("name")).toHaveAttribute("data-failed", "")
    await kit.check("failed")
  },

  // longer than the column takes, with the sensitive value in it; the
  // column asks first
  secret_failed: async (kit) => {
    await kit.typeInto("secret", SECRET + "x".repeat(20))
    const question = kit.question()
    await expect(question).toBeVisible()
    await question.locator("button[value=confirm]").click()
    await expect(kit.cell("secret")).toHaveAttribute("data-failed", "")
    await kit.check("secret_failed")
  },

  panel: async (kit) => {
    await kit.byId(`${kit.row()}-a-stamp`).click()
    await expect(kit.panel).toBeVisible()
    await kit.check("panel")
  },

  rekey: async (kit) => {
    await kit.byId(`${kit.row()}-a-rekey`).click()
    await expect(kit.panel).toBeVisible()
    await kit.check("rekey")
  },

  create: async (kit) => {
    await kit.byId("kit-create").click()
    await expect(kit.panel).toBeVisible()
    await kit.check("create")
  },

  // what the action refuses (a value too long in the list) is said at its
  // place, with the sensitive value typed into the panel
  create_failed: async (kit) => {
    await kit.byId("kit-create").click()
    await expect(kit.panel).toBeVisible()
    await kit.byId("kit-panel-f-name").fill("New")
    await kit.byId("kit-panel-f-secret").fill(SECRET)
    const tags = kit.byId("kit-panel-f-tags")
    for (const tag of ["ok", "much-too-long"]) {
      await tags.getByRole("button", { name: "Add value", exact: true }).click()
      await tags.locator("textarea").last().fill(tag)
    }
    await kit.byId("kit-panel-submit").click()
    await expect(kit.byId("kit-panel-f-tags-error")).toBeVisible()
    await kit.check("create_failed")
  },

  list_panel: async (kit) => {
    await kit.cell("tags").focus()
    await kit.page.keyboard.press("Enter")
    await expect(kit.panel).toBeVisible()
    await kit.check("list_panel")
  },

  map_panel: async (kit) => {
    await kit.cell("place").focus()
    await kit.page.keyboard.press("Enter")
    await expect(kit.panel).toBeVisible()
    await kit.check("map_panel")
  },

  groups_panel: async (kit) => {
    await kit.cell("stops").focus()
    await kit.page.keyboard.press("Enter")
    await expect(kit.panel).toBeVisible()
    await kit.check("groups_panel")
  },

  staff: async (kit) => {
    await kit.byId(`${kit.row()}-a-staff`).click()
    await expect(kit.panel).toBeVisible()
    await kit.check("staff")
  },

  staff_picker: async (kit) => {
    await kit.byId(`${kit.row()}-a-staff`).click()
    await expect(kit.panel).toBeVisible()
    await kit.byId("kit-panel-f-helpers-choose").click()
    await expect(kit.picker).toBeVisible()
    await expect(kit.picker.locator('[id^="kit-pick-"][role=rowgroup]').first()).toBeVisible()
    await kit.check("staff_picker")
  },

  picker: async (kit) => {
    await kit.cell("owner").focus()
    await kit.page.keyboard.press("Enter")
    await expect(kit.picker).toBeVisible()
    await expect(kit.picker.locator('[id^="kit-pick-"][role=rowgroup]').first()).toBeVisible()
    await kit.check("picker")
  },

  // one row selected, then the action on the selection, which asks first
  selected: async (kit) => {
    await kit.byId(`${kit.row()}-s`).locator("input").check()
    await expect(kit.byId("kit-selected")).toHaveText("1 selected")
    await kit.check("row_selected")
    // of more than three actions on the selection, the others are in "More"
    const destroy = kit.byId("kit-bulk-destroy")
    if (!(await destroy.isVisible())) await kit.byId("kit-bulk-more-button").click()
    await destroy.click()
    const question = kit.question()
    await expect(question).toBeVisible()
    await question.locator("button[value=confirm]").click()
    await expect(kit.byId("kit-result")).toBeVisible()
    await kit.check("selected")
  },

  // the link of a nested table to its full view, and that view: the parts
  // of one record (`/e2e/kit/parts`, in the page's tenant)
  links: async (kit) => {
    await kit.expand()
    await kit.byId(`${kit.row()}-l-parts-b`).click()
    const link = kit.byId(`${kit.nested}-full-view`)
    await expect(link).toBeVisible()
    await kit.check("full_view")
    const href = await link.getAttribute("href")
    await kit.page.goto(`${href}&tenant=${kit.tenant}`)
    await expect(kit.page.locator(".phx-connected").first()).toBeAttached()
    await expect(kit.byId("kit-related")).toBeVisible()
    await kit.check("related")
  },
}
