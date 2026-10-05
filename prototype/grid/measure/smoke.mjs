// THROWAWAY PROTOTYPE (#11). Does every variant render at all? Takes screenshots.
import {launch, open, goto, VARIANTS} from "./lib.mjs"

const browser = await launch()
for (const variant of VARIANTS) {
  const {page, frames, errors} = await open(browser)
  await goto(page, variant, 25, 10)
  const info = await page.evaluate(() => ({
    rows: document.querySelectorAll("#g > table tr[data-pk]").length,
    cells: document.querySelectorAll("#g > table td").length,
    tab0: Array.from(document.querySelectorAll('#g [tabindex="0"]')).map(e => e.id),
    debug: document.getElementById("proto-debug-client").textContent
  }))
  console.log(variant, JSON.stringify(info), "join frame bytes", frames.received[0]?.size, "errors", errors)
  if (process.argv[2]) (await import("node:fs")).writeFileSync(`shots/${variant}-join.json`, frames.received[0].payload)
  await page.screenshot({path: `shots/${variant}.png`})
  await page.close()
}
await browser.close()
