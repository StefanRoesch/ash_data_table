import { expect, type Locator, type Page, type Response } from "@playwright/test"

/**
 * One table of `ash_table` in a page: where its parts are and how to wait
 * for it. The parts are found by the stable ids the library gives them
 * (`ID-head-FIELD`, `ID-filter-FIELD`, `ID-row-KEY`, `ID-row-KEY-c-FIELD`;
 * see AshTable.Live.TableComponent), which is the one place of the suite
 * that knows them.
 */
export class Table {
  constructor(
    readonly page: Page,
    /** The table's id: the last part of its resource's name, underscored. */
    readonly id: string,
    /** Where the demo mounts it. */
    readonly path: string,
  ) {}

  // ---- opening and waiting ------------------------------------------------

  /** Opens the table's page, or `url`, and waits until its keyboard works. */
  async open(url: string = this.path): Promise<Response | null> {
    const response = await this.page.goto(url)
    await this.ready()
    return response
  }

  /**
   * The table is connected and its hook has run: the server renders every
   * cell with tabindex -1, and the hook makes one of them the tab stop.
   */
  async ready(): Promise<void> {
    await expect(this.tabStop).toHaveCount(1)
  }

  /**
   * Runs `action`, which makes the table read again (a sort, a filter, a
   * page change, the back button), and waits for the rows of that read: the
   * grid is `aria-busy` while it reads.
   */
  async reads(action: () => Promise<unknown>): Promise<void> {
    await this.busyThenIdle(this.grid, action)
  }

  /**
   * Runs `action`, which saves `cell`, and waits for the server's answer:
   * the cell is `aria-busy` while its save is on its way.
   */
  async saves(cell: Locator, action: () => Promise<unknown>): Promise<void> {
    await this.busyThenIdle(cell, action)
  }

  private async busyThenIdle(element: Locator, action: () => Promise<unknown>): Promise<void> {
    await element.evaluate((node) => {
      const isBusy = () => node.getAttribute("aria-busy") === "true"
      let wasBusy = isBusy()
      ;(window as any).__ashTableIdle = new Promise<void>((resolve) => {
        const observer = new MutationObserver(() => {
          const busy = isBusy()
          if (wasBusy && !busy) {
            observer.disconnect()
            resolve()
          }
          wasBusy = busy
        })
        observer.observe(node, { attributes: true, attributeFilter: ["aria-busy"] })
      })
    })
    await action()
    await this.page.evaluate(() => (window as any).__ashTableIdle)
  }

  // ---- the parts ----------------------------------------------------------

  private byId(id: string): Locator {
    // ids hold field names, and those may end in a question mark
    return this.page.locator(`[id="${id}"]`)
  }

  /** The component's root element. */
  get root(): Locator {
    return this.byId(this.id)
  }

  /** The `<table role="grid">`. */
  get grid(): Locator {
    return this.byId(`${this.id}-table`)
  }

  /** The element the hook is on: the grid with its editors' templates. */
  get hookRoot(): Locator {
    return this.byId(`${this.id}-grid`)
  }

  /** The one cell of the grid that Tab stops at. */
  get tabStop(): Locator {
    return this.grid.locator('[tabindex="0"]')
  }

  header(column: string): Locator {
    return this.byId(`${this.id}-head-${column}`)
  }

  get headers(): Locator {
    return this.grid.getByRole("columnheader")
  }

  /** The names of the columns, in order. */
  async columns(): Promise<string[]> {
    const prefix = `${this.id}-head-`
    return this.headers.evaluateAll(
      (cells, prefix) => cells.map((cell) => cell.id.slice(prefix.length)),
      prefix,
    )
  }

  /** The `<tbody>` of each row. */
  get rows(): Locator {
    return this.grid.locator("tbody")
  }

  /** The keys of the rows of the page, in order: what follows `ID-row-` in a row's id. */
  async rowKeys(): Promise<string[]> {
    const prefix = `${this.id}-row-`
    return this.rows.evaluateAll(
      (rows, prefix) => rows.map((row) => row.id.slice(prefix.length)),
      prefix,
    )
  }

  /** The key of the row at a position of the page, counted from 1. */
  async rowKey(position: number): Promise<string> {
    const keys = await this.rowKeys()
    expect(keys.length, `the page has a row ${position}`).toBeGreaterThanOrEqual(position)
    return keys[position - 1]
  }

  row(key: string): Locator {
    return this.byId(`${this.id}-row-${key}`)
  }

  cell(key: string, column: string): Locator {
    return this.byId(`${this.id}-row-${key}-c-${column}`)
  }

  /** The cells of a column, down the page. */
  columnCells(column: string): Locator {
    return this.grid.locator(`tbody td[id$="-c-${column}"]`)
  }

  /** What the cells of a column show, down the page. */
  async columnTexts(column: string): Promise<string[]> {
    return this.columnCells(column).allTextContents()
  }

  // ---- the filter row -----------------------------------------------------

  filterCell(column: string): Locator {
    return this.byId(`${this.id}-filter-${column}`)
  }

  /** Where a filter's value is typed or chosen. */
  filterValue(column: string): Locator {
    return this.byId(`${this.id}-filter-${column}-value`)
  }

  /** The menu of a filter's operators. */
  filterOperator(column: string): Locator {
    return this.byId(`${this.id}-filter-${column}-operator`)
  }

  filterClear(column: string): Locator {
    return this.byId(`${this.id}-filter-${column}-clear`)
  }

  filterError(column: string): Locator {
    return this.byId(`${this.id}-filter-${column}-error`)
  }

  get clearFilters(): Locator {
    return this.root.getByRole("button", { name: "Clear filters" })
  }

  /** The live region: what is read out after a filter change or a failed save. */
  get status(): Locator {
    return this.root.getByRole("status")
  }

  // ---- states and pagination ----------------------------------------------

  /** "No records". */
  get empty(): Locator {
    return this.byId(`${this.id}-empty`)
  }

  /** The alert of a read that failed or was refused. */
  get error(): Locator {
    return this.root.getByRole("alert")
  }

  get pagination(): Locator {
    return this.root.getByRole("navigation", { name: "Pagination" })
  }

  /** "1–25 of 320". */
  get range(): Locator {
    return this.byId(`${this.id}-range`)
  }

  get previous(): Locator {
    return this.pagination.getByRole("button", { name: "Previous", exact: true })
  }

  get next(): Locator {
    return this.pagination.getByRole("button", { name: "Next", exact: true })
  }

  pageButton(number: number): Locator {
    return this.pagination.getByRole("button", { name: `Go to page ${number}`, exact: true })
  }

  // ---- editing ------------------------------------------------------------

  /** The editor open in a cell. */
  editor(cell: Locator): Locator {
    return cell.locator("textarea, input, select")
  }

  /** Every editor open in the grid: one at most. */
  get openEditors(): Locator {
    return this.grid.locator("tbody textarea, tbody input, tbody select")
  }

  /** The templates the hook copies a column's editor from: one per column the person can edit. */
  get editorTemplates(): Locator {
    return this.root.locator(`template[id^="${this.id}-editor-"]`)
  }

  /** The dialog that asks a column's `confirm` question. */
  get dialog(): Locator {
    return this.page.getByRole("dialog")
  }

  /** The message of a cell whose save failed: what its `aria-describedby` names. */
  failure(cell: Locator): Locator {
    return cell.locator("[popover]")
  }

  // ---- focus --------------------------------------------------------------

  /** The id of the focused element, or its tag name when it has no id. */
  async focused(): Promise<string> {
    return this.page.evaluate(() => {
      const active = document.activeElement
      return active ? active.id || active.tagName : ""
    })
  }

  /** Whether focus is in the grid: on a cell, in a filter or in an editor. */
  async hasFocus(): Promise<boolean> {
    return this.hookRoot.evaluate((root) => root.contains(document.activeElement))
  }

  /** Everything in the grid that Tab stops at. It is one thing: a cell, or the editor open in it. */
  async tabStops(): Promise<string[]> {
    return this.hookRoot.evaluate((root) =>
      Array.from(root.querySelectorAll<HTMLElement>("*"))
        .filter((element) => element.tabIndex >= 0 && !(element as HTMLButtonElement).disabled)
        .map((element) => element.id || element.tagName),
    )
  }

  /** Presses keys one after the other. */
  async press(...keys: string[]): Promise<void> {
    for (const key of keys) await this.page.keyboard.press(key)
  }

  /** Types over what an editor or an input holds. */
  async retype(text: string): Promise<void> {
    await this.page.keyboard.press("ControlOrMeta+A")
    if (text === "") await this.page.keyboard.press("Delete")
    else await this.page.keyboard.type(text)
  }
}
