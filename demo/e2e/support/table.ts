import { expect, type Locator, type Page, type Response } from "@playwright/test"

/**
 * One table of `ash_table` in a page: where its parts are and how to wait
 * for it. The parts are found by the stable ids the library gives them
 * (`ID-head-FIELD`, `ID-filter-FIELD`, `ID-row-KEY`, `ID-row-KEY-c-FIELD`;
 * see AshTable.Live.TableComponent), which is the one place of the suite
 * that knows them.
 *
 * A nested table is a table like any other, under an id of its own
 * (`ID-row-KEY-t-RELATIONSHIP`): `nested()` gives it. What is asked of a
 * table here is about that table alone, not about the tables nested in it,
 * with two exceptions that are about the whole tree on purpose: `tabStop`
 * and `tabStops()`.
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

  /** The one cell that Tab stops at, of the grid and of every grid nested in it. */
  get tabStop(): Locator {
    return this.grid.locator('[tabindex="0"]')
  }

  header(column: string): Locator {
    return this.byId(`${this.id}-head-${column}`)
  }

  /** The headers of the table's columns: not the one of the expanders. */
  get headers(): Locator {
    return this.grid.locator(`:scope > thead th[id^="${this.id}-head-"]`)
  }

  /** Every cell of the header row, the one above the expanders among them. */
  get headerCells(): Locator {
    return this.grid.locator(":scope > thead > tr:first-child > th")
  }

  /** The names of the columns, in order. */
  async columns(): Promise<string[]> {
    const prefix = `${this.id}-head-`
    return this.headers.evaluateAll(
      (cells, prefix) => cells.map((cell) => cell.id.slice(prefix.length)),
      prefix,
    )
  }

  /** The `<tbody>` of each row: not the one under it, which holds what the row expands into. */
  get rows(): Locator {
    return this.grid.locator(":scope > tbody:not([data-detail])")
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

  /** The `<tr>` of a row: what its height is measured on. */
  rowLine(key: string): Locator {
    return this.byId(`${this.id}-row-${key}-r`)
  }

  cell(key: string, column: string): Locator {
    return this.byId(`${this.id}-row-${key}-c-${column}`)
  }

  /** The cells of a column, down the page. */
  columnCells(column: string): Locator {
    return this.grid.locator(`:scope > tbody > tr > td[id$="-c-${column}"]`)
  }

  /** The cells of a row, left to right, the expander among them. */
  rowCells(key: string): Locator {
    return this.row(key).locator(":scope > tr > td")
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
    return this.byId(`${this.id}-clear-filters`)
  }

  /** The live region: what is read out after a filter change or a failed save. */
  get status(): Locator {
    return this.byId(`${this.id}-status`)
  }

  // ---- states and pagination ----------------------------------------------

  /** "No records". */
  get empty(): Locator {
    return this.byId(`${this.id}-empty`)
  }

  /** The alert of a read that failed or was refused. */
  get error(): Locator {
    return this.byId(`${this.id}-error`)
  }

  /**
   * The table's pages, named "Pagination: " and the table's name: a
   * navigation landmark under a table of its own, a group in the last row
   * of a nested table's grid.
   */
  get pagination(): Locator {
    return this.byId(`${this.id}-pagination`)
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
    return this.grid.locator(":scope > tbody > tr > td:not([colspan]) :is(textarea, input, select)")
  }

  /** The templates the hook copies a column's editor from: one per column the person can edit. */
  get editorTemplates(): Locator {
    return this.hookRoot.locator(`:scope > template[id^="${this.id}-editor-"]`)
  }

  /** The dialog that asks a column's `confirm` question. */
  get dialog(): Locator {
    return this.page.getByRole("dialog")
  }

  /**
   * The table's own dialog for questions, by its id: where another dialog
   * may be open as well (the action panel), or a nested table has its own.
   */
  get question(): Locator {
    return this.byId(`${this.id}-dialog`)
  }

  /** The message of a cell whose save failed: what its `aria-describedby` names. */
  failure(cell: Locator): Locator {
    return cell.locator("[popover]")
  }

  // ---- the line of the table's name, and creating ---------------------------

  /** The line above the table: its name at one end, its create button at the other. */
  get headerLine(): Locator {
    return this.byId(`${this.id}-header`)
  }

  /** The table's name on that line: a heading of the page. */
  get name(): Locator {
    return this.byId(`${this.id}-name`)
  }

  /** "New task": it opens the action panel with the inputs of the create action. */
  get create(): Locator {
    return this.byId(`${this.id}-create`)
  }

  // ---- row actions --------------------------------------------------------

  /** The header of the actions column, the last of the grid. */
  get actionsHeader(): Locator {
    return this.byId(`${this.id}-actions-head`)
  }

  /** The cell under it in the filter row, which is empty. */
  get actionsFilter(): Locator {
    return this.byId(`${this.id}-actions-filter`)
  }

  /** The last cell of a row: it holds a button per row action. */
  actionsCell(key: string): Locator {
    return this.byId(`${this.id}-row-${key}-a`)
  }

  /** The button of one row action in a row. */
  action(key: string, name: string): Locator {
    return this.byId(`${this.id}-row-${key}-a-${name}`)
  }

  /** The buttons of a row's actions cell, left to right. */
  actions(key: string): Locator {
    return this.actionsCell(key).locator("button[data-action]")
  }

  /**
   * Runs `action`, which uses a button of a row's actions cell, and waits
   * for the server's answer: the cell is `aria-busy` while its action is on
   * its way. Not for an action that takes the row away.
   */
  async acts(key: string, action: () => Promise<unknown>): Promise<void> {
    await this.busyThenIdle(this.actionsCell(key), action)
  }

  /** Where each row says it stands among all rows (`aria-rowindex`), down the page. */
  async rowIndexes(): Promise<number[]> {
    return this.rows.evaluateAll((rows) =>
      rows.map((row) => Number((row as HTMLTableSectionElement).rows[0].getAttribute("aria-rowindex"))),
    )
  }

  // ---- the action panel ---------------------------------------------------

  /** The action panel: a modal dialog, in the page only while it is open. */
  get panel(): Locator {
    return this.byId(`${this.id}-panel`)
  }

  /** Its heading: the action, and the record it runs on. */
  get panelTitle(): Locator {
    return this.byId(`${this.id}-panel-title`)
  }

  /** The panel's form. */
  get panelForm(): Locator {
    return this.byId(`${this.id}-panel-form`)
  }

  /**
   * The server has answered everything that was typed into the panel so
   * far: LiveView marks a form from the moment it sends what the form holds
   * until the answer is in the page.
   */
  async panelSettled(): Promise<void> {
    await expect(this.panelForm).not.toHaveClass(/phx-change-loading|phx-submit-loading/)
  }

  /** The control of one input of the action, by the input's name. */
  field(name: string): Locator {
    return this.byId(`${this.id}-panel-f-${name}`)
  }

  /** What the action says about one input. */
  fieldError(name: string): Locator {
    return this.byId(`${this.id}-panel-f-${name}-error`)
  }

  /** The names of the panel's fields, top to bottom. */
  async fields(): Promise<string[]> {
    return this.panel
      .locator("[data-field]")
      .evaluateAll((fields) => fields.map((field) => (field as HTMLElement).dataset.field!))
  }

  /** What the action says that is about none of its inputs: an alert above the fields. */
  get panelErrors(): Locator {
    return this.byId(`${this.id}-panel-errors`)
  }

  get panelCancel(): Locator {
    return this.byId(`${this.id}-panel-cancel`)
  }

  /** "Run", or "Create". */
  get panelSubmit(): Locator {
    return this.byId(`${this.id}-panel-submit`)
  }

  // ---- what a row expands into ---------------------------------------------

  /** The first cell of a row, when the table's rows expand: it holds the expander. */
  expanderCell(key: string): Locator {
    return this.byId(`${this.id}-row-${key}-e`)
  }

  /** The button that expands a row and says whether it is expanded. */
  expander(key: string): Locator {
    return this.expanderCell(key).locator("button")
  }

  /** Every expander of the table. */
  get expanders(): Locator {
    return this.grid.locator(":scope > tbody > tr > td[data-expander]")
  }

  /** The lines under an expanded row, one per relationship: their cells. */
  lines(key: string): Locator {
    return this.byId(`${this.id}-row-${key}-x`).locator(":scope > tr > td[data-line]")
  }

  /** The cell of one line under a row. */
  lineCell(key: string, relationship: string): Locator {
    return this.byId(`${this.id}-row-${key}-l-${relationship}-c`)
  }

  /** The button of a line: it opens the nested table and says whether it is open. */
  line(key: string, relationship: string): Locator {
    return this.byId(`${this.id}-row-${key}-l-${relationship}-b`)
  }

  /** The create button of a line's nested table: on the line, after its label. */
  lineCreate(key: string, relationship: string): Locator {
    return this.byId(`${this.id}-row-${key}-l-${relationship}-create`)
  }

  /** The cell under an open line that holds the nested table. */
  nestedCell(key: string, relationship: string): Locator {
    return this.byId(`${this.id}-row-${key}-n-${relationship}-c`)
  }

  /** The nested table under an open line: a table like any other. */
  nested(key: string, relationship: string): Table {
    return new Table(this.page, `${this.id}-row-${key}-t-${relationship}`, this.path)
  }

  /** The cell in the last row of a nested table's grid that holds its pages. */
  get pagerCell(): Locator {
    return this.byId(`${this.id}-pager`)
  }

  /** The cell in the last row of a nested table's grid that holds its link to the full view. */
  get viewCell(): Locator {
    return this.byId(`${this.id}-view`)
  }

  /** "Open in full view": the link of a nested table to the page of its records. */
  get fullView(): Locator {
    return this.byId(`${this.id}-full-view`)
  }

  /** Above a table that is limited to the records of one parent: what it shows. */
  get relatedHeading(): Locator {
    return this.byId(`${this.id}-related-heading`)
  }

  /** The parent in that heading: a link where its own table has a page. */
  get relatedParent(): Locator {
    return this.byId(`${this.id}-related-parent`)
  }

  /** "Show all records": the way back from a limited table to all of its records. */
  get relatedClear(): Locator {
    return this.byId(`${this.id}-related-clear`)
  }

  /** "Loading…", in a nested table whose first rows are on their way. */
  get loading(): Locator {
    return this.byId(`${this.id}-loading`)
  }

  /** Expands a row with the pointer and waits for its lines. */
  async expand(key: string): Promise<void> {
    await this.expander(key).click()
    await expect(this.expander(key)).toHaveAttribute("aria-expanded", "true")
  }

  /**
   * Expands a row if need be, opens one of its lines with the pointer, and
   * waits for the nested table's first rows. Returns the nested table.
   */
  async openLine(key: string, relationship: string): Promise<Table> {
    if ((await this.expander(key).getAttribute("aria-expanded")) !== "true") await this.expand(key)
    await this.line(key, relationship).click()
    const nested = this.nested(key, relationship)
    await nested.loaded()
    return nested
  }

  /** A nested table has its first read behind it: rows, "No records" or a message. */
  async loaded(): Promise<void> {
    await expect(this.grid).toBeVisible()
    await expect(this.loading).toHaveCount(0)
    await expect(this.grid).not.toHaveAttribute("aria-busy", "true")
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

  /**
   * Everything in the grid, and in the tables nested in it, that Tab stops
   * at. It is one thing: a cell, or the editor open in it.
   */
  async tabStops(): Promise<string[]> {
    return this.hookRoot.evaluate((root) =>
      Array.from(root.querySelectorAll<HTMLElement>("*"))
        // the buttons of a nested table's dialog are in the grid around it,
        // and are nothing Tab can reach while the dialog is closed
        .filter(
          (element) =>
            element.tabIndex >= 0 &&
            !(element as HTMLButtonElement).disabled &&
            !element.closest("dialog:not([open])"),
        )
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
