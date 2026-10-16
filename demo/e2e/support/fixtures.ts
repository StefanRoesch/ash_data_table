import { expect, type Page } from "@playwright/test"
import { storageStateOf, type Actor } from "./actors"
import { reseed } from "./data"
import { test as base } from "./server"
import { Table } from "./table"

/** An event the page pushed to its LiveView, as the server heard it. */
export type Pushed = {
  /** A table's event by its own name (`save`), a page's own by its whole name. */
  event: string
  /** The id of the table the event is of; null for a page's own. */
  table: string | null
  /** What the event carried. */
  params: any
}

/**
 * What the page of the test pushed to its LiveViews: every event, as the
 * server heard it, in order (`DemoWeb.E2E.Recorder`, from LiveView's
 * telemetry). The page's session names the test (`POST /e2e/recorder`);
 * the page of another browser in the same test is not heard.
 */
export class Sent {
  private constructor(private page: Page) {}

  /** Names the test in the page's session: what its LiveViews hear from then on is kept. */
  static async start(page: Page): Promise<Sent> {
    const response = await page.request.post("/e2e/recorder", { data: { test: crypto.randomUUID() } })
    expect(response.status(), "POST /e2e/recorder: is the server running in MIX_ENV=e2e?").toBe(200)
    return new Sent(page)
  }

  /** Forgets what was pushed so far. */
  async clear(): Promise<void> {
    await this.flush()
    expect((await this.page.request.delete("/e2e/recorded")).status()).toBe(200)
  }

  /** Everything pushed since the last `clear`. */
  async all(): Promise<Pushed[]> {
    await this.flush()
    const response = await this.page.request.get("/e2e/recorded")
    expect(response.status()).toBe(200)
    return response.json()
  }

  /**
   * Everything pushed since the last `clear` but the events of these names:
   * what is selected is sent on every change (`select`), and nothing else is.
   */
  async besides(...events: string[]): Promise<Pushed[]> {
    return (await this.all()).filter((pushed) => !events.includes(pushed.event))
  }

  /** How many events of this name the page pushed: "save", "sort", "filter", "page", "discard". */
  async count(event: string): Promise<number> {
    return (await this.all()).filter((pushed) => pushed.event === event).length
  }

  /**
   * What the last `select` of the table `id` since the last `clear` said is
   * selected: the rows as the hook names them, or "all"; undefined where it
   * sent none.
   */
  async selected(id: string): Promise<string[] | "all" | undefined> {
    const last = (await this.all()).filter((pushed) => pushed.event === "select" && pushed.table === id).at(-1)
    return last && (last.params.all ? "all" : last.params.rows)
  }

  /**
   * That the last `select` of `table` since the last `clear` said what its
   * hook shows selected: the same rows, in any order (none, where nothing
   * is selected and no `select` was sent).
   */
  async expectSelected(table: Table): Promise<void> {
    const sent = await this.selected(table.id)
    const shown = [...(await table.selectedKeys())].sort()
    expect(sent === "all" ? sent : [...(sent ?? [])].sort(), `what the last select of ${table.id} said`).toEqual(shown)
  }

  // Everything the page pushed before this is heard once this returns. An
  // event is pushed in the task of the key or click that caused it, or in a
  // timer of 0 ms it set (leaving an editor), which runs before the timer
  // of 0 ms set here after it. Then an event of the tests' own goes the way
  // of every event of the page: the LiveView answers it after all that came
  // before it on the socket. It is an event of a table that is not there
  // (`e2e-barrier`), which every table answers alike and the recorder does
  // not keep. A page without a table pushes no table event.
  private async flush(): Promise<void> {
    await this.page.evaluate(async () => {
      await new Promise((resolve) => setTimeout(resolve, 0))
      const grid: any = document.querySelector("[phx-hook='AshDataTable.Grid']")
      if (grid?._ashDataTable) await grid._ashDataTable.pushEventTo(grid, "ash_data_table:e2e-barrier:save", {})
    })
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
  pushed: Sent
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

  pushed: [
    async ({ page }, use) => {
      await use(await Sent.start(page))
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
