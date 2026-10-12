import { expect, type Page } from "@playwright/test"
import { storageStateOf, type Actor } from "./actors"
import { reseed } from "./data"
import { test as base } from "./server"
import { Table } from "./table"

/**
 * What the page sent to the server over its WebSocket, heartbeats left out.
 * LiveView sends `[join_ref, ref, topic, event, payload]`; an event a person
 * causes has the event "event" and names itself in the payload.
 */
export class Frames {
  private sent: string[] = []

  constructor(private page: Page) {
    page.on("websocket", (socket) => {
      socket.on("framesent", (frame) => {
        // the parts of an uploaded file are sent as bytes: no event of a person
        if (typeof frame.payload !== "string") return
        const text = String(frame.payload)
        if (!text.includes('"heartbeat"')) this.sent.push(text)
      })
    })
  }

  /** Forgets what was sent so far. */
  async clear(): Promise<void> {
    await this.flush()
    this.sent = []
  }

  /** Everything sent since the last `clear`. */
  async all(): Promise<string[]> {
    await this.flush()
    return [...this.sent]
  }

  /** How many events of this name the page pushed: "save", "sort", "filter", "page", "discard". */
  async count(event: string): Promise<number> {
    await this.flush()
    return this.sent.filter((text) => {
      const [, , , kind, payload] = JSON.parse(text)
      return kind === "event" && payload.event === event
    }).length
  }

  // A frame is sent in the task of the key or click that caused it, or in a
  // timer of 0 ms after it (leaving an editor). A round trip to the page
  // after such a timer comes back behind every frame sent until then.
  private async flush(): Promise<void> {
    await this.page.evaluate(() => new Promise((resolve) => setTimeout(resolve, 20)))
  }
}

/** Collects what the browser reports as an error: console errors and uncaught exceptions. */
export class ConsoleErrors {
  private errors: string[] = []
  private allowed: RegExp[] = []

  constructor(page: Page) {
    page.on("console", (message) => {
      if (message.type() === "error") this.errors.push(message.text())
    })
    page.on("pageerror", (error) => this.errors.push(`uncaught: ${error.message}`))
  }

  /** Errors a test expects, such as the browser's report of a 404 it asked for. */
  allow(pattern: RegExp): void {
    this.allowed.push(pattern)
  }

  unexpected(): string[] {
    return this.errors.filter((error) => !this.allowed.some((pattern) => pattern.test(error)))
  }
}

/**
 * Collects the dialogs of the browser itself: `alert`, `confirm`, `prompt`.
 * A table asks in a dialog of its own, in the page; the browser's would be
 * a second question on top of it. Each is dismissed, as Playwright does with
 * one that nobody listens for, which is why a test would not notice it.
 */
export class NativeDialogs {
  readonly seen: string[] = []

  constructor(page: Page) {
    page.on("dialog", async (dialog) => {
      this.seen.push(`${dialog.type()}: ${dialog.message()}`)
      await dialog.dismiss()
    })
  }
}

type Options = {
  /** Who the test is: one of the demo's five actors. The admin unless a file or test says otherwise. */
  actor: Actor
  /**
   * Whether the test changes the data: `test.use({ writes: true })`. The
   * database is seeded again after such a test, passed or failed, so that
   * every test starts from the seed, in whatever order or selection.
   */
  writes: boolean
}

type Fixtures = {
  seededAgain: void
  frames: Frames
  consoleErrors: ConsoleErrors
  nativeDialogs: NativeDialogs
  /** The table at /tasks. */
  tasks: Table
}

export const test = base.extend<Options & Fixtures>({
  actor: ["admin", { option: true }],

  // the session cookie the setup project made through the actor switcher
  storageState: async ({ actor }, use) => {
    await use(storageStateOf(actor))
  },

  writes: [false, { option: true }],

  seededAgain: [
    async ({ writes, request }, use) => {
      await use()
      if (writes) await reseed(request)
    },
    { auto: true },
  ],

  frames: [
    async ({ page }, use) => {
      await use(new Frames(page))
    },
    { auto: true },
  ],

  // Every test of every file ends with this: nothing unexpected on the console.
  consoleErrors: [
    async ({ page }, use) => {
      const errors = new ConsoleErrors(page)
      await use(errors)
      expect(errors.unexpected(), "console errors and uncaught exceptions").toEqual([])
    },
    { auto: true },
  ],

  // And with this: the browser was never made to ask anything itself.
  nativeDialogs: [
    async ({ page }, use) => {
      const dialogs = new NativeDialogs(page)
      await use(dialogs)
      expect(dialogs.seen, "dialogs of the browser itself").toEqual([])
    },
    { auto: true },
  ],

  tasks: async ({ page }, use) => {
    await use(new Table(page, "task", "/tasks"))
  },
})

export { expect }
