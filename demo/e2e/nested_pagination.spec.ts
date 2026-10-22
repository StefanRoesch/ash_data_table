import type { Locator, Page } from "@playwright/test"
import { SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { Table } from "./support/table"

// A nested table's pages stand where a table's on the page do (#68): the
// range at the left of the table's scroll area, the controls at the right
// end of what is seen of it, in every kit, in both themes and at phone
// width. /projects: the projects on the page, and the tasks of Mobile App
// nested under it, which have pages. The project `chromium` draws them with
// the default kit, `react` with the React kit; the kit of `div`s
// (`DemoWeb.DivKit`) is asked for by request (`x-demo-kit: div`).

const MOBILE_APP = SEED.project.mobileApp

/** Where a table's pages stand in its scroll area, in pixels. */
type Place = {
  /** From the left edge of the scroll area to the range. */
  left: number
  /** From the last control (the buttons, or "Rows per page") to the right edge of what is seen. */
  right: number
  /** The pages, as the window has them. */
  box: { left: number; right: number; top: number }
  /** The scroll area, as the window has it: its left edge and how wide is seen of it. */
  area: { left: number; seen: number }
}

async function place(table: Table): Promise<Place> {
  await expect(table.pagination).toBeVisible()
  const area = await table.hookRoot.evaluate((grid) => {
    const box = grid.getBoundingClientRect()
    return { left: box.left + grid.clientLeft, seen: grid.clientWidth }
  })
  const range = await box(table.range)
  const last = await table.pagination.evaluate((element) => {
    const box = element.lastElementChild!.getBoundingClientRect()
    return { right: box.right }
  })
  const pages = await box(table.pagination)
  return {
    left: Math.round(range.left - area.left),
    right: Math.round(area.left + area.seen - last.right),
    box: { left: Math.round(pages.left), right: Math.round(pages.right), top: Math.round(pages.top) },
    area: { left: Math.round(area.left), seen: area.seen },
  }
}

async function box(locator: Locator): Promise<{ left: number; right: number; top: number }> {
  const box = await locator.evaluate((element) => element.getBoundingClientRect())
  return { left: box.left, right: box.right, top: box.top }
}

/** The projects with the tasks of Mobile App open under it, in `theme`. */
async function opened(page: Page, theme: "light" | "dark") {
  await page.addInitScript((theme) => localStorage.setItem("phx:theme", theme), theme)
  const projects = new Table(page, "project", "/projects")
  await projects.open()
  await expect(page.locator("html")).toHaveAttribute("data-theme", theme)
  const tasks = await projects.openLine(MOBILE_APP, "tasks")
  return { projects, tasks }
}

/**
 * The inset of a nested table's pages is its cell's (about 1rem, as its
 * link to the full view); a table's on the page has none: a little more
 * than that is the same place.
 */
const SAME = 24

function kits(name: string, header: Record<string, string> | null) {
  test.describe(`in the ${name}`, () => {
    if (header) test.use({ extraHTTPHeaders: header })

    for (const theme of ["light", "dark"] as const) {
      test(`a nested table's pages stand where the table's on the page do, in the ${theme} theme`, async ({
        page,
      }, testInfo) => {
        test.skip(!!header && testInfo.project.name === "react", "the kit of divs once, under chromium")
        const { projects, tasks } = await opened(page, theme)

        const top = await place(projects)
        const nested = await place(tasks)
        expect(Math.abs(nested.left - top.left), "the range at the left").toBeLessThanOrEqual(SAME)
        expect(Math.abs(nested.right - top.right), "the controls at the right end").toBeLessThanOrEqual(SAME)
        // the range and the controls on one line, as on the page
        const range = await box(tasks.range)
        const next = await box(tasks.next)
        expect(Math.abs(next.top - range.top)).toBeLessThanOrEqual(SAME)
      })
    }

    test("at phone width the nested pages stay in view as the nested table scrolls sideways", async ({
      page,
    }, testInfo) => {
      test.skip(!!header && testInfo.project.name === "react", "the kit of divs once, under chromium")
      await page.setViewportSize({ width: 390, height: 844 })
      const { projects, tasks } = await opened(page, "light")

      const top = await place(projects)
      const nested = await place(tasks)
      expect(Math.abs(nested.left - top.left), "the range at the left").toBeLessThanOrEqual(SAME)
      // nothing of the pages is cut off at either end of what is seen
      expect(nested.box.left).toBeGreaterThanOrEqual(nested.area.left)
      expect(nested.box.right).toBeLessThanOrEqual(nested.area.left + nested.area.seen)

      // scrolled to its end, the nested table's pages stand where they stood:
      // the tasks' columns are far wider than a phone, so there is always
      // something to scroll
      const { all, seen } = await tasks.area()
      expect(all, "the nested table scrolls sideways at this width").toBeGreaterThan(seen)
      await tasks.scrollTo(all)
      const scrolled = await place(tasks)
      expect(scrolled.box).toEqual(nested.box)
      expect(scrolled.right).toBe(nested.right)
    })
  })
}

kits("kit of the run (the default kit, or the React kit)", null)
kits("kit of divs", { "x-demo-kit": "div" })
