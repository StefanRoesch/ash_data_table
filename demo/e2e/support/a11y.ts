import AxeBuilder from "@axe-core/playwright"
import { expect, type Page } from "@playwright/test"

/**
 * axe-core finds nothing wrong with the page as it is now: every rule axe
 * runs by default, on the whole document, with no rule switched off and no
 * impact left out. `within` is a selector that limits the check to a part
 * of the page.
 */
export async function expectNoAxeViolations(page: Page, within?: string): Promise<void> {
  // The demo's progress bar (Phoenix's topbar, a <canvas> on the body) shows
  // when the server takes more than 300 ms. It belongs to no state of a
  // table and is gone a moment later.
  await expect(page.locator("body > canvas")).toBeHidden()

  const builder = new AxeBuilder({ page })
  const results = await (within ? builder.include(within) : builder).analyze()

  const violations = results.violations.map((violation) => ({
    rule: violation.id,
    impact: violation.impact,
    help: violation.help,
    nodes: violation.nodes.map((node) => node.target.join(" ")),
  }))

  expect(violations).toEqual([])
}
