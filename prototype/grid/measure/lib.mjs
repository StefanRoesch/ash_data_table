// THROWAWAY PROTOTYPE (#11). Shared helpers for the measurement scripts.
import {chromium} from "playwright"

export const BASE = process.env.BASE || "http://localhost:4477"
export const VARIANTS = ["keyed", "streams", "components"]

export const LAYOUT = process.env.LAYOUT || "auto"
export const url = (variant, rows = 25, cols = 10) =>
  `${BASE}/prototype/grid?variant=${variant}&rows=${rows}&cols=${cols}&layout=${LAYOUT}`

export const median = xs => {
  const s = [...xs].sort((a, b) => a - b)
  return s.length ? (s.length % 2 ? s[(s.length - 1) / 2] : (s[s.length / 2 - 1] + s[s.length / 2]) / 2) : NaN
}
export const round = (x, d = 1) => Math.round(x * 10 ** d) / 10 ** d

const isHeartbeat = payload => payload.includes('"phoenix"')
const bytes = payload => Buffer.byteLength(payload, "utf8")

// Opens a page that records every LiveView WebSocket frame, and has in-page
// timing helpers (time of the last input event, time of the last DOM mutation
// in the grid, time the hook reported an event).
export async function open(browser, opts = {}) {
  const context = await browser.newContext({viewport: {width: 1600, height: 900}})
  const page = await context.newPage()
  const frames = {sent: [], received: []}
  page.on("websocket", ws => {
    if (!ws.url().includes("/live/websocket")) return
    ws.on("framesent", f => !isHeartbeat(f.payload) && frames.sent.push({size: bytes(f.payload), payload: f.payload}))
    ws.on("framereceived", f => !isHeartbeat(f.payload) && frames.received.push({size: bytes(f.payload), payload: f.payload}))
  })
  const errors = []
  page.on("pageerror", e => errors.push(String(e)))
  page.on("console", m => m.type() === "error" && errors.push(m.text()))
  await page.addInitScript(noObserver => {
    window.ashTableNoObserver = noObserver
    window.__m = {input: 0, mutation: 0, frame: 0, mounted: null, hook: {}, log: [], nav: []}
    const stamp = e => { window.__m.input = performance.now() }
    window.addEventListener("keydown", stamp, true)
    window.addEventListener("mousedown", stamp, true)
    // navigation latency: keydown to the focus change it caused
    window.addEventListener("focusin", () => window.__m.nav.push(performance.now() - window.__m.input), true)
    window.addEventListener("ash-table:debug", ({detail}) => {
      window.__m.hook[detail.event] = detail.t
      window.__m.last = detail
      window.__m.log.push(detail.event === "focus-restored" ? detail.event : `${detail.event}@${detail.active}`)
      if (detail.event === "mounted" && detail.grid === "g" && window.__m.mounted === null) window.__m.mounted = detail.t
    })
    document.addEventListener("DOMContentLoaded", () => {
      const main = document.querySelector("main")
      if (!main) return
      new MutationObserver(() => {
        window.__m.mutation = performance.now()
        // time until the browser has produced a frame with the patched DOM
        requestAnimationFrame(() => setTimeout(() => { window.__m.frame = performance.now() }, 0))
        // <main> holds the grid; the debug strip is outside it and is not counted
      }).observe(main, {subtree: true, childList: true, attributes: true, characterData: true})
    })
  }, !!opts.noObserver)
  // Chrome's own cumulative counters: where the time on the page went
  const cdp = await context.newCDPSession(page)
  await cdp.send("Performance.enable")
  page.metrics = async () => {
    const {metrics} = await cdp.send("Performance.getMetrics")
    const get = name => metrics.find(m => m.name === name).value * 1000
    return {script: get("ScriptDuration"), layout: get("LayoutDuration"), style: get("RecalcStyleDuration")}
  }
  return {page, frames, errors, context}
}

export const reset = () => fetch(`${BASE}/prototype/grid/reset`).then(r => r.json())

export async function goto(page, variant, rows, cols) {
  await page.goto(url(variant, rows, cols))
  await page.waitForFunction(() => window.__m && window.__m.mounted !== null)
  await settle(page)
}

// Waits until no DOM mutation and no frame happened for `quiet` ms.
export async function settle(page, quiet = 150) {
  await page.waitForFunction(
    q => performance.now() - Math.max(window.__m.mutation, window.__m.frame, window.__m.input) > q,
    quiet,
    {polling: 25}
  )
}

// Runs `action`, waits for the page to settle, and returns what happened:
// frames in both directions and the time from the input event to the last DOM
// mutation (`patch_ms`) and to the frame after it (`frame_ms`).
export async function act(page, frames, action, quiet = 150) {
  const sent0 = frames.sent.length
  const recv0 = frames.received.length
  await page.evaluate(() => { window.__m.mutation = 0; window.__m.frame = 0 })
  const before = await page.metrics()
  await action()
  // every event sent gets a reply: wait for it, however long the server takes
  await page.waitForTimeout(60)
  for (let i = 0; i < 3000 && frames.received.length - recv0 < frames.sent.length - sent0; i++) await page.waitForTimeout(10)
  await settle(page, quiet)
  const after = await page.metrics()
  const m = await page.evaluate(() => ({...window.__m, log: undefined}))
  const sent = frames.sent.slice(sent0)
  const received = frames.received.slice(recv0)
  return {
    sent: sent.length,
    received: received.length,
    recv_bytes: received.reduce((a, f) => a + f.size, 0),
    sent_bytes: sent.reduce((a, f) => a + f.size, 0),
    patch_ms: m.mutation ? m.mutation - m.input : null,
    frame_ms: m.frame ? m.frame - m.input : null,
    script_ms: after.script - before.script,
    layout_ms: after.layout - before.layout,
    style_ms: after.style - before.style,
    payloads: received.map(f => f.payload)
  }
}

export const launch = () => chromium.launch({headless: true})

export async function stats(page, gc = true) {
  return page.evaluate(async gc => {
    const pid = document.getElementById("proto-debug").dataset.pid
    const res = await fetch(`/prototype/grid/stats?pid=${encodeURIComponent(pid)}${gc ? "&gc=1" : ""}`)
    return res.json()
  }, gc)
}

export async function poke(page, index, col, value) {
  return page.evaluate(async ([index, col, value]) => {
    const pid = document.getElementById("proto-debug").dataset.pid
    await fetch(`/prototype/grid/poke?pid=${encodeURIComponent(pid)}&index=${index}&col=${col}&value=${encodeURIComponent(value)}`)
  }, [index, col, value])
}

// Focus the cell of data row `r` (0-based on the page) and column name `col`.
export async function focusCell(page, r, col, grid = "g") {
  await page.evaluate(([r, col, grid]) => {
    const root = document.getElementById(grid)
    const table = root.querySelector(":scope > table")
    const th = table.rows[0].querySelector(`th[data-col="${col}"]`)
    const rows = Array.from(table.rows).filter(tr => tr.dataset.pk)
    rows[r].cells[th.cellIndex].focus()
  }, [r, col, grid])
}

export const active = page =>
  page.evaluate(() => {
    const a = document.activeElement
    return a ? {id: a.id, tag: a.tagName, text: a.tagName === "INPUT" || a.tagName === "SELECT" ? a.value : a.textContent.trim().slice(0, 60)} : null
  })

export const tabStops = page =>
  page.evaluate(() => Array.from(document.querySelectorAll('#g [tabindex="0"]')).map(e => e.id))
