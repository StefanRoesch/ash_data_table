import AxeBuilder from "@axe-core/playwright"
import { expect, type Page } from "@playwright/test"

/**
 * axe-core finds nothing wrong with the page as it is now: every rule axe
 * runs by default, on the whole document, with no rule switched off and no
 * impact left out (but for one finding, on the grid of a nested table: see
 * below). `within` is a selector that limits the check to a part
 * of the page.
 */
export async function expectNoAxeViolations(page: Page, within?: string): Promise<void> {
  // The demo's progress bar (Phoenix's topbar, a <canvas> on the body) shows
  // when the server takes more than 300 ms. It belongs to no state of a
  // table and is gone a moment later. It is not there yet while a page that
  // has just been opened is still connecting, and would come up in the
  // middle of the check: so the page has to be connected first, which the
  // demo says on the document (`data-loading`, from LiveView's
  // `phx:page-loading-start` until its `phx:page-loading-stop`).
  await expect(page.locator("html[data-loading]")).toHaveCount(0)
  await expect(page.locator("body > canvas")).toBeHidden()

  // Two things keep a check short on a page of 1,500 elements, where it
  // would take five seconds and more. axe runs in the page itself and hands
  // back what it found (`setLegacyMode`), in place of every node's raw result
  // being carried to a second page to be put together there; the demo has no
  // frames of another origin, which is all that mode leaves out. And only the
  // violations come back in full (`resultTypes`): every rule still runs on
  // every node, but the ten thousand nodes that passed are not listed.
  const builder = new AxeBuilder({ page })
    .setLegacyMode(true)
    .options({ resultTypes: ["violations"] })
  const results = await (within ? builder.include(within) : builder).analyze()

  // One finding of one rule is not held against the page: "Scrollable region
  // must have keyboard access", for the grid of a nested table. Every table
  // scrolls sideways in its own area, and axe asks of each such area that Tab
  // stops in it. A tree of grids has one tab stop on purpose (see the guide
  // "Keyboard and accessibility"): a nested table is gone into with Enter
  // and moved through with the arrow keys, and its area scrolls with the
  // focus, which axe cannot know. The grid on the page, and that of a
  // picker, holds the tab stop and is checked as everything else is.
  const ofNestedGrid = async (target: unknown[]): Promise<boolean> =>
    target.length === 1 &&
    typeof target[0] === "string" &&
    (await page
      .locator(target[0])
      .evaluateAll(
        (found) =>
          found.length === 1 && found[0].matches("[role=gridcell][data-nested] [data-ash-data-table]"),
      ))

  const violations = []
  for (const violation of results.violations) {
    const nodes = []
    for (const node of violation.nodes) {
      if (violation.id === "scrollable-region-focusable" && (await ofNestedGrid(node.target))) continue
      nodes.push(node.target.join(" "))
    }
    if (nodes.length > 0) {
      violations.push({ rule: violation.id, impact: violation.impact, help: violation.help, nodes })
    }
  }

  expect(violations).toEqual([])
}
