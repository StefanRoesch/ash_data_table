import path from "node:path"
import type { Page } from "@playwright/test"
import { expect, test } from "./support/fixtures"

// The public contract of the package's browser side, for a kit that draws
// in the browser (the React kit's note, C5 and C7):
//
//   * `assets/js/ids.js` makes every id `AshDataTable.Ids` makes, function
//     by function: /e2e/ids renders a sample of each, with what the server
//     made of it;
//   * `mountGrid` and `liveViewTransport` mount the grid's hook by hand on
//     a grid that has no `phx-hook` (/e2e/markers?mount=1, the demo's hook
//     `MountedGrid`): an edit and its save work from the keyboard, `onEdit`
//     hears the edit begin and end, and the hook mounted again on the same
//     element after `destroy()` (React's StrictMode) acts once per key.

type Ids = Record<string, (...args: unknown[]) => string>

const library = path.resolve(import.meta.dirname, "../../assets/js/ids.js")
const camel = (name: string) => name.replace(/_(\w)/g, (_all, letter: string) => letter.toUpperCase())

test("ids.js makes every id AshDataTable.Ids makes, and has no function it lacks", async ({ page }) => {
  const ids: Ids = await import(library)
  await page.goto("/e2e/ids")

  const samples: { function: string; args: unknown[]; id: string }[] = JSON.parse(
    (await page.locator("#ids").textContent()) ?? "[]",
  )
  const functions: string[] = JSON.parse((await page.locator("#functions").textContent()) ?? "[]")

  expect(samples.length).toBeGreaterThan(0)
  for (const sample of samples) {
    const made = ids[camel(sample.function)]
    expect(made, `ids.js has no ${camel(sample.function)}`).toBeDefined()
    expect(made(...sample.args), `${sample.function}(${JSON.stringify(sample.args)})`).toBe(sample.id)
  }

  // every function of `Ids` has a sample, and ids.js has no other
  const sampled = new Set(samples.map((sample) => sample.function))
  expect(functions.filter((name) => !sampled.has(name))).toEqual([])
  // (the module as Node gives it: its exports, besides what the interop adds)
  const exported = Object.keys(ids).filter((name) => name !== "default" && typeof ids[name] === "function")
  expect(exported.sort()).toEqual([...sampled].map(camel).sort())
})

test.describe("the grid's hook mounted by hand", () => {
  const cell = (page: Page, key: string, column: string) => page.locator(`[id="kit-row-${key}-c-${column}"]`)
  const edits = (page: Page) => page.evaluate(() => (window as unknown as { kitMount: { edits: unknown[] } }).kitMount.edits)
  const call = (page: Page, what: "remount" | "destroy" | "beforeUpdate" | "updated") =>
    page.evaluate((what) => (window as unknown as { kitMount: Record<string, () => void> }).kitMount[what](), what)

  test.beforeEach(async ({ page }) => {
    await page.goto("/e2e/markers?mount=1")
    await expect(page.locator('[id="kit-grid"]')).not.toHaveAttribute("phx-hook")
    // the hooks are mounted by hand (`window.kitMount`, the demo's MountedGrid)
    await page.waitForFunction(() => "kitMount" in window)
  })

  test("edits and saves from the keyboard, and tells onEdit", async ({ page }) => {
    await cell(page, "a", "name").focus()
    await page.keyboard.press("Enter")
    const editor = cell(page, "a", "name").locator("textarea")
    await expect(editor).toBeFocused()
    expect(await edits(page)).toEqual(["kit-row-a-c-name"])

    await page.keyboard.press("Escape")
    await expect(cell(page, "a", "name")).toBeFocused()
    expect(await edits(page)).toEqual(["kit-row-a-c-name", null])

    // a save goes out through the transport (the sender), and its row comes back
    await page.keyboard.press("Enter")
    await editor.fill("Anvil")
    await page.keyboard.press("Enter")
    await expect(cell(page, "a", "name")).toHaveText("Anvil")
    await expect(cell(page, "a", "name")).not.toHaveAttribute("aria-busy")
    expect(await edits(page)).toEqual(["kit-row-a-c-name", null, "kit-row-a-c-name", null])
    await call(page, "beforeUpdate")
    await call(page, "updated")
  })

  test("the pagination keeps the focused control aside before a commit, and gives focus back after", async ({ page }) => {
    // a commit of the kit that takes the focused button out and puts a new
    // one in its place: the browser drops the focus; the kit says it has
    // committed a moment later (a passive effect), once the focus is gone
    const commit = (page: Page, before: boolean) =>
      page.evaluate(async (before) => {
        const { pagination } = (window as unknown as { kitMount: { pagination: { beforeUpdate(): void; updated(): void } } }).kitMount
        if (before) pagination.beforeUpdate()
        const button = document.getElementById("kit-page-2")!
        button.replaceWith(button.cloneNode(true))
        await new Promise((resolve) => setTimeout(resolve, 50))
        pagination.updated()
      }, before)
    const button = page.locator('[id="kit-page-2"]')

    // told only after the commit, it has nothing to give back
    await button.focus()
    await commit(page, false)
    await expect(button).not.toBeFocused()

    // told before it, as the contract asks
    await button.focus()
    await commit(page, true)
    await expect(button).toBeFocused()
  })

  test("mounted again after destroy, it acts once per key; destroyed, not at all", async ({ page }) => {
    // as React's StrictMode does: mount, destroy (twice does nothing more), mount
    await call(page, "remount")
    await call(page, "remount")

    // the note that cuts its text off has one "Show all", and Enter on it
    // shows the whole text: once, not shown and cut off again by a second hook
    const whole = cell(page, "a", "note").locator(":scope > [data-whole]")
    await expect(whole).toHaveCount(1)
    await whole.focus()
    await page.keyboard.press("Enter")
    await expect(whole).toHaveAttribute("aria-expanded", "true")

    await cell(page, "a", "name").focus()
    await page.keyboard.press("Enter")
    await expect(cell(page, "a", "name").locator("textarea")).toHaveCount(1)
    await expect(cell(page, "a", "name").locator("textarea")).toBeFocused()
    await page.keyboard.press("Escape")
    // each edit told once
    expect(await edits(page)).toEqual(["kit-row-a-c-name", null])

    await call(page, "destroy")
    await cell(page, "a", "name").focus()
    await page.keyboard.press("Enter")
    await expect(cell(page, "a", "name")).toBeFocused()
    await expect(cell(page, "a", "name").locator("textarea")).toHaveCount(0)
  })
})
