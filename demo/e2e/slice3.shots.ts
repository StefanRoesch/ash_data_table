import { mkdirSync } from "node:fs"
import path from "node:path"
import type { Page } from "@playwright/test"
import { SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { switchLocale } from "./support/locale"
import { Table } from "./support/table"

// Pictures of the components of a column, for a person to look at: the
// badges, the bar and the unit at rest, the slider open in a cell and in
// the action panel, a save through it that failed, in the light and the
// dark theme, at 1500 and 900 px, nested, in forced colours and in German.
// `npm run shots` takes them (playwright.shots.config.ts); they assert
// nothing but that the state they show was reached.

const DIR = process.env.SHOTS_DIR ?? path.join(import.meta.dirname, "test-results", "shots")
const FIRST = SEED.task.first
const SECOND = SEED.task.second

mkdirSync(DIR, { recursive: true })

async function shot(page: Page, name: string): Promise<void> {
  // the demo's progress bar belongs to no state of a table
  await expect(page.locator("body > canvas")).toBeHidden()
  await page.mouse.move(5, 5)
  await page.screenshot({ path: path.join(DIR, `${name}.png`) })
}

for (const theme of ["light", "dark"] as const) {
  for (const width of [1500, 900]) {
    test.describe(`${theme}, ${width} px`, () => {
      test.use({ viewport: { width, height: 900 } })

      test.beforeEach(async ({ page }) => {
        await page.addInitScript((theme) => localStorage.setItem("phx:theme", theme), theme)
      })

      test("the components at rest, the slider open, and the editor of the demo's own", async ({
        page,
        tasks,
      }) => {
        await tasks.open()
        await expect(page.locator("html")).toHaveAttribute("data-theme", theme)
        await shot(page, `final-tasks-${width}-${theme}`)

        const progress = tasks.cell(SECOND, "progress")
        await progress.dblclick()
        const slider = tasks.editor(progress)
        const box = (await slider.boundingBox())!
        await page.mouse.move(box.x + box.width * 0.6, box.y + box.height / 2)
        await page.mouse.down()
        await tasks.saves(progress, () => page.mouse.up())
        await expect(slider).toBeFocused()
        await shot(page, `final-slider-open-${width}-${theme}`)
        await tasks.press("Escape")

        const estimate = tasks.cell(FIRST, "estimate_hours")
        await estimate.focus()
        await tasks.press("Enter")
        await expect(tasks.editor(estimate)).toBeFocused()
        await shot(page, `final-hours-editor-${width}-${theme}`)
      })

      test("the slider in the action panel, and the create panel", async ({ page, tasks }) => {
        await tasks.open()
        await tasks.acts(SECOND, () => tasks.action(SECOND, "set_progress").click())
        await expect(tasks.field("progress")).toBeFocused()
        await tasks.press("ArrowRight", "ArrowRight", "ArrowRight")
        await tasks.panelSettled()
        await shot(page, `final-panel-slider-${width}-${theme}`)
        await tasks.press("Escape")
        await expect(tasks.panel).toHaveCount(0)

        await tasks.create.click()
        await expect(tasks.field("title")).toBeFocused()
        await shot(page, `final-panel-create-${width}-${theme}`)
      })
    })
  }
}

test.describe("at 1500 px", () => {
  test.use({ viewport: { width: 1500, height: 900 } })

  test("a save through the slider that failed, with its message", async ({ page, tasks }) => {
    await tasks.open()
    const states = await tasks.columnTexts("status")
    const key = await tasks.rowKey(states.indexOf("Done") + 1)
    const progress = tasks.cell(key, "progress")
    await progress.focus()
    await tasks.press("Enter", "PageDown")
    await tasks.saves(progress, () => tasks.press("Enter"))
    await expect(tasks.failure(progress)).toBeVisible()
    await page.screenshot({ path: path.join(DIR, "final-slider-failed.png") })
  })

  test("the tasks nested under a project", async ({ page }) => {
    const projects = new Table(page, "project", "/projects")
    await projects.open()
    const nested = await projects.openLine(SEED.project.mobileApp, "tasks")
    await nested.cell(await nested.rowKey(1), "progress").focus()
    await shot(page, "final-nested-components")
  })

  test("in German", async ({ page, tasks }) => {
    await page.goto("/")
    await switchLocale(page, "de")
    await tasks.open()
    await shot(page, "final-tasks-german")
  })

  test("as the member, whose hidden estimates are not shown", async ({ browser }) => {
    // a page of its own, as the member
    const context = await browser.newContext({
      storageState: path.join(import.meta.dirname, ".auth", "member.json"),
      viewport: { width: 1500, height: 900 },
    })
    const page = await context.newPage()
    const tasks = new Table(page, "task", "/tasks")
    await tasks.open()
    await shot(page, "final-tasks-member")
    await context.close()
  })

  test.describe("in forced colours", () => {
    test.use({ forcedColors: "active" })

    test("the components, and the slider open", async ({ page, tasks }) => {
      await tasks.open()
      const progress = tasks.cell(await tasks.rowKey(7), "progress")
      await progress.focus()
      await tasks.press("Enter")
      await expect(tasks.editor(progress)).toBeFocused()
      await shot(page, "final-forced-colours")
    })
  })
})
