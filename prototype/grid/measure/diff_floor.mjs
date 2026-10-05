// THROWAWAY PROTOTYPE (#11). What is in the diff of ONE cell edit in the
// streams variant, and how small could it get? Captures the real frame and
// takes it apart. The "without ..." rows are computed from that frame, not run.
import zlib from "node:zlib"
import {launch, open, goto, reset, act, focusCell} from "./lib.mjs"

const browser = await launch()
const rows = []
for (const cols of [10, 30]) {
  await reset()
  const {page, frames} = await open(browser)
  await goto(page, "streams", 25, cols)
  await focusCell(page, 3, "title")
  await page.keyboard.press("Enter")
  await page.keyboard.press("Control+a")
  await page.keyboard.type("Edited title")
  const r = await act(page, frames, () => page.keyboard.press("Enter"))
  const payload = r.payloads[0]
  const bytes = s => Buffer.byteLength(s, "utf8")
  const total = bytes(payload)
  // the per-cell attribute string: id, aria-colindex and (rarely) aria-readonly
  const attrs = payload.match(/" id=\\"g-\d+-\d+\\" aria-colindex=\\"\d+\\"( aria-readonly=\\"true\\")?"/g) || []
  const attrBytes = attrs.reduce((a, s) => a + bytes(s), 0)
  const idOnly = (payload.match(/ id=\\"g-\d+-\d+\\"/g) || []).reduce((a, s) => a + bytes(s), 0)
  const colindexOnly = (payload.match(/ aria-colindex=\\"\d+\\"/g) || []).reduce((a, s) => a + bytes(s), 0)
  const values = await page.evaluate(() => {
    const tr = document.querySelector("#g-4-r")
    return Array.from(tr.cells).slice(1).map(td => td.textContent.trim())
  })
  // the static template parts, which a stream insert sends again every time
  const findP = o => o && typeof o === "object" ? (o.p ? o.p : Object.values(o).map(findP).find(Boolean)) : null
  const statics = bytes(JSON.stringify(findP(JSON.parse(payload))))
  const valueBytes = values.reduce((a, v) => a + bytes(JSON.stringify(v)), 0)
  rows.push({
    cols, total, gzip: zlib.gzipSync(payload).length, deflate: zlib.deflateRawSync(payload).length,
    statics, cells: attrs.length, attrBytes, idOnly, colindexOnly, valueBytes,
    without_colindex: total - colindexOnly,
    without_cell_ids_and_colindex: total - attrBytes + attrs.length * 2,
    without_those_and_with_30_byte_class_names: total - attrBytes + attrs.length * 2 - Math.max(0, statics - 550),
    values_plus_json_keys: valueBytes + values.length * 6
  })
  if (cols === 10) console.log("the frame at 10 columns:\n" + payload + "\n")
  await page.context().close()
}
await browser.close()
console.table(rows)
