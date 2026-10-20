import type { Browser, Locator, Page } from "@playwright/test"
import { expectNoAxeViolations } from "./support/a11y"
import { storageStateOf, type Actor } from "./support/actors"
import { SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { Table } from "./support/table"

// The demo's React kit (`DemoWeb.ReactKit`, stage 8, R2) on /react/tasks:
// the tasks attached to a LiveView, their grid, "Columns", the line above
// the grid, the live region and the pagination React islands drawn with
// shadcn/ui through live_react, on the table's own hooks. Its grid specs
// run against it in the project `react` (playwright.config.ts); these are
// what only the React kit has: its islands under React's StrictMode, a save
// while a live update changes the row, the hooks of a nested table that
// goes destroyed at once, a table placed with the tag, and shadcn's
// colours inside the table in both themes and in the system's.

const FIRST = SEED.task.first
const OWN = SEED.task.membersOwn

const SHADCN = {
  light: { background: "oklch(1 0 0)", foreground: "oklch(0.145 0 0)" },
  dark: { background: "oklch(0.145 0 0)", foreground: "oklch(0.985 0 0)" },
}

/** A second person with /react/tasks open, in a browser context of their own. */
async function another(browser: Browser, page: Page, actor: Actor): Promise<{ page: Page; close: () => Promise<void> }> {
  const context = await browser.newContext({
    storageState: storageStateOf(actor),
    baseURL: new URL(page.url()).origin,
    viewport: page.viewportSize(),
  })
  return { page: await context.newPage(), close: () => context.close() }
}

/** Changes a text cell as a person does: Enter, type over it, Enter. */
async function retype(table: Table, key: string, column: string, text: string): Promise<void> {
  const cell = table.cell(key, column)
  await cell.focus()
  await table.press("Enter")
  await expect(table.editor(cell)).toBeFocused()
  await table.retype(text)
  await table.saves(cell, () => table.press("Enter"))
  await expect(cell).toHaveText(text)
}

const color = (locator: Locator, property: "backgroundColor" | "color") =>
  locator.evaluate((element, property) => getComputedStyle(element)[property], property)

test.describe("the React kit on /react/tasks", () => {
  test("the grid is React's, on the table's hook: it sorts, and a save goes through it", async ({ page, pushed }) => {
    const tasks = new Table(page, "task", "/react/tasks")
    await tasks.open()
    // drawn by the island, beside the sender LiveView draws
    await expect(page.locator("#task-grid-island #task-grid")).toBeAttached()
    await expect(page.locator("#task-sender")).toBeAttached()
    await expect(page.locator("#task-grid-island #task-sender")).toHaveCount(0)

    await tasks.reads(() => tasks.sortButton("title").click())
    await expect(tasks.header("title")).toHaveAttribute("aria-sort", "ascending")

    await retype(tasks, await tasks.rowKey(1), "title", "Saved through React")
    expect(await pushed.count("save")).toBe(1)
  })

  test("under StrictMode every hook is mounted once: a box sends one change of the selection", async ({ page, pushed }) => {
    const tasks = new Table(page, "task", "/react/tasks")
    await tasks.open()
    await pushed.clear()
    await tasks.box(FIRST).check()
    await expect(page.locator("#task-selected")).toHaveText("1 selected")
    expect(await pushed.count("select")).toBe(1)
  })

  test("a save while a live update changes the row: the editor keeps what is typed, and both changes show", async ({
    browser,
    page,
  }) => {
    const tasks = new Table(page, "task", "/react/tasks")
    await tasks.open()
    const other = await another(browser, page, "member")

    try {
      const theirs = new Table(other.page, "task", "/react/tasks")
      await theirs.open()
      const title = theirs.cell(OWN, "title")
      await title.focus()
      await theirs.press("Enter")
      await expect(theirs.editor(title)).toBeFocused()
      await theirs.retype("Saved by the member")

      // the admin changes another cell of the row meanwhile
      await retype(tasks, OWN, "description", "Described meanwhile")
      await expect(theirs.cell(OWN, "description")).toHaveText("Described meanwhile")
      await expect(theirs.editor(title)).toHaveValue("Saved by the member")
      await expect(theirs.editor(title)).toBeFocused()

      // the member's save goes through, and the row holds both
      await theirs.saves(title, () => theirs.press("Enter"))
      await expect(title).toHaveText("Saved by the member")
      await expect(title).toBeFocused()
      await expect(theirs.cell(OWN, "description")).toHaveText("Described meanwhile")
      await expect(tasks.cell(OWN, "title")).toHaveText("Saved by the member")
    } finally {
      await other.close()
    }
  })

  test("the hooks of a nested table that goes are destroyed as it goes, not at the next navigation", async ({ page, pushed }) => {
    const tasks = new Table(page, "task", "/react/tasks")
    await tasks.open()
    await page.evaluate(() => {
      ;(window as any).__gone = []
      window.addEventListener("ash-react:gone", (e: any) => (window as any).__gone.push(e.detail.island))
    })
    const nested = `task-row-${FIRST}-t-comments`
    const line = page.locator(`[id="task-row-${FIRST}-l-comments-b"]`)

    await tasks.expand(FIRST)
    await line.click()
    await expect(page.locator(`[id="${nested}-grid"]`)).toBeAttached()
    await expect(page.locator(`[id="${nested}"]`)).toHaveAttribute("data-read", "")

    await line.click()
    await expect(page.locator(`[id="${nested}-grid"]`)).toHaveCount(0)
    const gone = await page.evaluate(() => (window as any).__gone as string[])
    expect(gone).toContain(`${nested}-grid-island`)

    // opened again, it is one table with one hook: a box sends one change
    await line.click()
    const box = page.locator(`[id="${nested}-grid"] [data-selector] input`).first()
    await expect(box).toBeVisible()
    await pushed.clear()
    await box.check()
    await expect(page.locator(`[id="${nested}-selected"]`)).not.toBeEmpty()
    expect((await pushed.all()).filter((sent) => sent.event === "select")).toHaveLength(1)
  })

  test("a table placed with the tag: its events go to its component", async ({ page, pushed }) => {
    const tagged = new Table(page, "tagged", "/e2e/react/tag")
    await tagged.open()
    await expect(page.locator("#tagged-grid-island #tagged-grid")).toBeAttached()
    await expect(tagged.sortButton("title")).toHaveAttribute("phx-target", /^\d+$/)

    await tagged.reads(() => tagged.sortButton("title").click())
    await expect(tagged.header("title")).toHaveAttribute("aria-sort", "ascending")
    await retype(tagged, await tagged.rowKey(1), "title", "Saved in a component")
    expect(await pushed.count("save")).toBe(1)
  })

  for (const theme of ["light", "dark"] as const) {
    test(`shadcn's colours inside the table, daisyUI's outside it, in the ${theme} theme`, async ({ page }) => {
      await page.addInitScript((theme) => localStorage.setItem("phx:theme", theme), theme)
      const tasks = new Table(page, "task", "/react/tasks")
      await tasks.open()
      await expect(page.locator("html")).toHaveAttribute("data-theme", theme)
      expect(await color(page.locator("#task"), "color")).toBe(SHADCN[theme].foreground)
      // daisyUI's button outside the table paints the page's primary
      const daisy = await page.evaluate(() => {
        const probe = document.createElement("span")
        probe.style.backgroundColor = "var(--color-primary)"
        document.body.append(probe)
        const primary = getComputedStyle(probe).backgroundColor
        probe.remove()
        return primary
      })
      expect(daisy).not.toBe("rgba(0, 0, 0, 0)")
      await expectNoAxeViolations(page)
    })
  }

  test("with no theme chosen, the table follows the system's dark preference", async ({ page }) => {
    await page.emulateMedia({ colorScheme: "dark" })
    await page.addInitScript(() => localStorage.removeItem("phx:theme"))
    const tasks = new Table(page, "task", "/react/tasks")
    await tasks.open()
    await expect(page.locator("html")).not.toHaveAttribute("data-theme")
    expect(await color(page.locator("#task"), "color")).toBe(SHADCN.dark.foreground)
    await page.emulateMedia({ colorScheme: "light" })
    expect(await color(page.locator("#task"), "color")).toBe(SHADCN.light.foreground)
  })
})
