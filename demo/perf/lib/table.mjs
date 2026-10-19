// One browser page on one table, and how each thing a person does on it is
// timed. Times are taken in the page with performance.now(): from the event
// a person causes (the key or the click) to the moment the DOM has been
// patched with the server's answer, which a MutationObserver sees. Painting
// is not included. Frame sizes are those of the WebSocket text frames the
// server sent, uncompressed.

import { BASE, drainEvents, sleep, wireReceived } from "./server.mjs"

const ADMIN = "Ada Admin · admin · acme"

/** Becomes the admin through the demo's actor switcher. */
export async function logIn(context) {
  const page = await context.newPage()
  await page.goto(BASE + "/")
  await page.getByLabel("Acting as").selectOption({ label: ADMIN })
  await page.getByText("You are now Ada Admin (admin).").waitFor()
  await page.close()
}

/**
 * Opens a table in a new page and measures the load. "Interactive" is the
 * moment the LiveView has joined and its hooks are mounted: LiveView marks
 * its element `phx-connected` (a documented class) once the join's patch,
 * which mounts the hooks, is in the page.
 */
export async function open(context, path, id) {
  const page = await context.newPage()
  const received = []
  const sent = []
  page.on("websocket", (socket) => {
    if (!socket.url().includes("/live/websocket")) return
    socket.on("framereceived", (frame) => received.push(String(frame.payload)))
    socket.on("framesent", (frame) => sent.push(String(frame.payload)))
  })

  await page.addInitScript(() => {
    window.__interactive = new Promise((resolve) => {
      const check = () => {
        if (!document.querySelector('.phx-connected [role="table"]')) return false
        resolve(performance.now())
        return true
      }
      const observer = new MutationObserver(() => check() && observer.disconnect())
      observer.observe(document, {
        subtree: true,
        childList: true,
        attributes: true,
        attributeFilter: ["class"],
      })
    })
  })

  const response = await page.goto(BASE + path)
  const html = await response.body()
  const interactive = await page.evaluate(() => window.__interactive)
  const navigation = await page.evaluate(() => {
    const [entry] = performance.getEntriesByType("navigation")
    return {
      response_end_ms: entry.responseEnd,
      dom_content_loaded_ms: entry.domContentLoadedEventEnd,
      html_transferred_bytes: entry.encodedBodySize,
    }
  })
  // the answer to the join: the whole page once more, as LiveView's parts
  const join = received.find((text) => JSON.parse(text)[3] === "phx_reply")

  const table = new Table(page, id, received, sent)
  table.load = {
    interactive_ms: interactive,
    ...navigation,
    html_bytes: html.length,
    join_frame_bytes: Buffer.byteLength(join ?? ""),
    // the rows and the columns of the table itself: not the detail under a
    // row, which is empty until the row is expanded, nor the expanders
    rows: await page.locator(`#${id}-table > tbody:not([data-detail])`).count(),
    columns: await page.locator(`#${id}-table > thead th[id^="${id}-head-"]`).count(),
  }
  return table
}

export class Table {
  constructor(page, id, received, sent) {
    this.page = page
    this.id = id
    this.received = received
    this.sent = sent
  }

  close() {
    return this.page.close()
  }

  cell(key, column) {
    return this.page.locator(`[id="${this.id}-row-${key}-c-${column}"]`)
  }

  async rowKeys() {
    const prefix = `${this.id}-row-`
    return this.page
      .locator(`#${this.id}-table > tbody:not([data-detail])`)
      .evaluateAll((rows, prefix) => rows.map((row) => row.id.slice(prefix.length)), prefix)
  }

  /**
   * Runs one measured thing. `arm` is evaluated in the page and leaves a
   * promise in `window.__measured` that resolves to the milliseconds;
   * `act` then does what a person does. Returns the time with the frames
   * that went over the socket meanwhile and what the server recorded.
   */
  async measure(arm, argument, act) {
    await drainEvents()
    const receivedBefore = this.received.length
    const sentBefore = this.sent.length
    const wireBefore = wireReceived()

    await this.page.evaluate(arm, argument)
    await act()
    const ms = await Promise.race([
      this.page.evaluate(() => window.__measured),
      sleep(30_000).then(() => {
        throw new Error("nothing came back within 30 s of what was measured")
      }),
    ])
    // lets the server finish what it records after it has answered
    await sleep(30)

    const frames = this.received.slice(receivedBefore).map((text) => Buffer.byteLength(text))
    return {
      ms,
      frames_received: frames.length,
      bytes_received: frames.reduce((sum, bytes) => sum + bytes, 0),
      largest_frame_bytes: Math.max(0, ...frames),
      // PERF_WIRE=1: the same frames as they went over the wire
      wire_bytes_received: wireBefore === null ? null : wireReceived() - wireBefore,
      frames_sent: this.sent.length - sentBefore,
      server: await drainEvents(),
    }
  }

  /**
   * A cell edit: the editor is opened and the text typed before the clock
   * starts; it runs from the Enter that saves to the patch that takes
   * `aria-busy` off the cell again.
   */
  async edit(key, column, text) {
    const cell = this.cell(key, column)
    await cell.focus()
    await this.page.keyboard.press("Enter")
    await this.page.keyboard.press("ControlOrMeta+A")
    await this.page.keyboard.type(text)

    const result = await this.measure(
      (id) => {
        const cell = document.getElementById(id)
        window.__measured = new Promise((resolve) => {
          let started = null
          let busy = false
          const onKey = (event) => {
            if (event.key !== "Enter") return
            started = performance.now()
            document.removeEventListener("keydown", onKey, true)
          }
          document.addEventListener("keydown", onKey, true)
          const observer = new MutationObserver(() => {
            const now = cell.hasAttribute("aria-busy")
            if (busy && !now) {
              observer.disconnect()
              resolve(performance.now() - started)
            }
            busy = now
          })
          observer.observe(cell, { attributes: true, attributeFilter: ["aria-busy"] })
        })
      },
      await cell.getAttribute("id"),
      () => this.page.keyboard.press("Enter"),
    )

    if ((await cell.getAttribute("data-failed")) !== null) {
      throw new Error(`the edit of ${column} failed: ${await cell.textContent()}`)
    }
    return { ...result, server: saveOnServer(result.server) }
  }

  /**
   * Something that makes the table read again. The clock runs from `act`,
   * which is called in the page, to the patch that takes `aria-busy` off
   * the grid again, with the rows of the read.
   */
  async read(selector, how = "click") {
    const result = await this.measure(
      ({ table, selector, how }) => {
        const grid = document.getElementById(table)
        const target = document.querySelector(selector)
        window.__measured = new Promise((resolve) => {
          let started = null
          let busy = false
          const observer = new MutationObserver(() => {
            const now = grid.getAttribute("aria-busy") === "true"
            if (busy && !now) {
              observer.disconnect()
              resolve(performance.now() - started)
            }
            busy = now
          })
          observer.observe(grid, { attributes: true, attributeFilter: ["aria-busy"] })
          window.__act = () => {
            started = performance.now()
            if (how === "click") target.click()
            // a filter is applied by Enter in its input: the hook submits the form
            else target.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true }))
          }
        })
      },
      { table: `${this.id}-table`, selector, how },
      () => this.page.evaluate(() => window.__act()),
    )

    return { ...result, server: readOnServer(result.server) }
  }

  sort(column) {
    return this.read(`[id="${this.id}-head-${column}"]`)
  }

  nextPage() {
    return this.read(`#${this.id}-next`)
  }

  toPage(number) {
    return this.read(`#${this.id}-page-${number}`)
  }

  async filter(column, value) {
    await this.page.locator(`[id="${this.id}-filter-${column}-value"]`).fill(value)
    return this.read(`[id="${this.id}-filter-${column}-value"]`, "enter")
  }

  clearFilters() {
    return this.read(`#${this.id}-clear-filters`)
  }

  /**
   * Arrow keys. Real key presses first, to see that nothing is sent; then
   * the hook's own work per key, timed in the page over many keys, as one
   * key is too short to time.
   */
  async arrowKeys(key, column) {
    await this.cell(key, column).focus()
    const sentBefore = this.sent.length
    const pressed = ["ArrowRight", "ArrowDown", "ArrowLeft", "ArrowUp", "End", "Home", "PageDown", "PageUp"]
    for (let round = 0; round < 10; round++) {
      for (const name of pressed) await this.page.keyboard.press(name)
    }
    await sleep(100)
    const frames = this.sent.length - sentBefore

    const perKey = await this.page.evaluate(() => {
      const keys = ["ArrowRight", "ArrowDown", "ArrowLeft", "ArrowUp"]
      const presses = 2000
      const started = performance.now()
      for (let i = 0; i < presses; i++) {
        document.activeElement.dispatchEvent(
          new KeyboardEvent("keydown", { key: keys[i % 4], bubbles: true, cancelable: true }),
        )
      }
      return (performance.now() - started) / presses
    })

    return { keys_pressed: 10 * pressed.length, frames_sent: frames, ms_per_key: perKey }
  }
}

const sum = (entries) => entries.reduce((total, entry) => total + entry.us, 0)
const named = (events, name) => events.filter((event) => event.name === name)

/**
 * What the server did for one save, from the telemetry of LiveView, Ash and
 * Ecto: the `save` event's callback as a whole; in it the read that fetches
 * the record again (the first Ash read) and the update action, which also
 * loads the row's calculations and aggregates for the answer; and the time
 * the database took for all of it.
 */
function saveOnServer(events) {
  const handle = named(events, "live_component.handle_event").find((e) => e.event === "save")
  if (!handle) return null
  const within = events.filter((e) => e.at <= handle.at && e.at >= handle.at - handle.us)
  const refetch = named(within, "ash.read")[0]
  const update = within.find((e) => e.name === "ash.update" || e.name === "ash.action")
  const queries = named(within, "query")

  return {
    handle_event_us: handle.us,
    refetch_us: refetch?.us ?? null,
    update_us: update?.us ?? null,
    queries: queries.length,
    database_us: sum(queries),
  }
}

/**
 * What the server did for one read: the queries of the page and, where the
 * action counts, of the count.
 */
function readOnServer(events) {
  const queries = named(events, "query")
  const counts = queries.filter((query) => /^SELECT (coalesce\()?count\(/i.test(query.sql))
  const read = named(events, "ash.read").sort((a, b) => b.us - a.us)[0]

  return {
    read_us: read?.us ?? null,
    queries: queries.length,
    database_us: sum(queries),
    count_us: sum(counts),
    rows_us: sum(queries) - sum(counts),
  }
}
