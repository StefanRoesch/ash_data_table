// THROWAWAY PROTOTYPE (#11). axe-core on the grid in every variant: plain, with
// a nested table open, with an editor open and with a failed save showing.
import {AxeBuilder} from "@axe-core/playwright"
import {launch, open, goto, reset, act, settle, focusCell, VARIANTS} from "./lib.mjs"

const browser = await launch()
const report = async (page, label, scope = "#g") => {
  const results = await new AxeBuilder({page}).include(scope).analyze()
  const v = results.violations.map(x => `${x.id} [${x.impact}] x${x.nodes.length}: ${x.help} (e.g. ${x.nodes[0].target.join(" ")})`)
  console.log(`${label.padEnd(44)} violations: ${v.length}  passes: ${results.passes.length}  incomplete: ${results.incomplete.map(i => i.id).join(",") || "-"}`)
  v.forEach(line => console.log("    " + line))
}

for (const variant of VARIANTS) {
  await reset()
  const {page, frames} = await open(browser)
  await goto(page, variant, 25, 10)
  await report(page, `${variant}: plain grid`)

  await focusCell(page, 0, "title")
  await page.keyboard.press("Enter")
  await report(page, `${variant}: text editor open`)
  await page.keyboard.press("Control+a")
  await page.keyboard.type("ab")
  await act(page, frames, () => page.keyboard.press("Enter"))
  await report(page, `${variant}: failed save showing`)
  await page.keyboard.press("Escape")
  await settle(page)

  await focusCell(page, 0, "status")
  await page.keyboard.press("Enter")
  await report(page, `${variant}: select editor open`)
  await page.keyboard.press("Escape")

  await act(page, frames, () => page.click("#open-first-10"), 300)
  await report(page, `${variant}: 10 nested tables open`)
  await report(page, `${variant}: whole page, nested open`, "body")
  await page.context().close()
}
await browser.close()
