import AxeBuilder from "@axe-core/playwright"
import { expect, type Page } from "@playwright/test"

/**
 * axe-core finds nothing wrong with the page as it is now: every rule axe
 * runs by default, on the whole document, with no rule switched off, no
 * impact left out and no finding excepted. `within` is a selector that
 * limits the check to a part of the page.
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

  // What opens or closes with a transition is checked once it stands: the
  // list of the columns is daisyUI's dropdown, which fades in and out, and
  // its text measured halfway is paler than it is.
  await page.evaluate(() =>
    Promise.all(
      document
        .getAnimations()
        .filter((animation) => animation.effect?.getComputedTiming().endTime !== Infinity)
        .map((animation) => animation.finished.catch(() => undefined)),
    ),
  )

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

  const violations = results.violations.map((violation) => ({
    rule: violation.id,
    impact: violation.impact,
    help: violation.help,
    nodes: violation.nodes.map((node) => node.target.join(" ")),
  }))

  expect(violations).toEqual([])
}
