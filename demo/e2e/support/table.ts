import { expect, type Locator, type Page, type Response } from "@playwright/test"

/**
 * One table of `ash_data_table` in a page: where its parts are and how to wait
 * for it. The parts are found by the stable ids the library gives them
 * (`ID-head-FIELD`, `ID-filter-FIELD`, `ID-row-KEY`, `ID-row-KEY-c-FIELD`;
 * see the markup contract in lib/ash_data_table.ex), which is the one place of the suite
 * that knows them.
 *
 * A nested table is a table like any other, under an id of its own
 * (`ID-row-KEY-t-RELATIONSHIP`): `nested()` gives it. What is asked of a
 * table here is about that table alone, not about the tables nested in it,
 * with one exception that is about the whole tree on purpose: `stops()`,
 * the stops in page order, which a nested table is part of.
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
   * The table is connected and its hook has run: LiveView marks its element
   * `phx-connected` (a documented class) once the join's patch, which mounts
   * the hooks, is in the page.
   */
  async ready(): Promise<void> {
    await expect(this.page.locator(".phx-connected").first()).toBeAttached()
    await expect(this.grid).toBeAttached()
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
      ;(window as any).__ashDataTableIdle = new Promise<void>((resolve) => {
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
    await this.page.evaluate(() => (window as any).__ashDataTableIdle)
  }

  /**
   * Runs `action`, and waits until the server has told this table's hooks
   * `event` with `details` (`ash_data_table:leaving` of a row, which a live
   * update pushes) and has answered whatever the hooks pushed back. LiveView
   * dispatches what the server pushes on `window` as `phx:EVENT`
   * (`Phoenix.LiveView.push_event/3`), where the hooks hear it too
   * (`handleEvent`); they listen from their mount, so their handlers have
   * run by the time this one does. What a test then finds is what the hooks
   * made of the event, and of their answer: for a check that something does
   * not happen.
   */
  async told(event: string, details: Record<string, unknown>, action: () => Promise<unknown>): Promise<void> {
    await this.page.evaluate(
      ([event, details]) => {
        ;(window as any).__ashDataTableTold = new Promise<void>((resolve) => {
          const heard = ({ detail }: any) => {
            if (Object.entries(details).every(([key, value]) => detail[key] === value)) {
              window.removeEventListener(`phx:${event}`, heard)
              resolve()
            }
          }
          window.addEventListener(`phx:${event}`, heard)
        })
      },
      [event, { ...details, table: this.id }] as const,
    )
    await action()
    await this.page.evaluate(() => (window as any).__ashDataTableTold)
    await answered(this.page)
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

  /** The `<table role="table">`. */
  get grid(): Locator {
    return this.byId(`${this.id}-table`)
  }

  /** The element the hook is on: the grid with its editors' templates. */
  get hookRoot(): Locator {
    return this.byId(`${this.id}-grid`)
  }

  // ---- what a person could only send by hand -------------------------------

  /**
   * Sends the table `event` with exactly `payload`, as the grid's hook sends
   * its events: for what no control of the page sends at that moment (a
   * sort without a click, which would move the focus). The one place the
   * browser tests reach into the hook to send an event.
   */
  async forge(event: string, payload: Record<string, unknown>): Promise<void> {
    await this.hookRoot.evaluate(
      // named with the table, as the hooks' transport names it
      (grid: any, [event, payload]) =>
        grid._ashDataTable.pushEventTo(grid, `ash_data_table:${grid._ashDataTable.id}:${event}`, payload),
      [event, payload] as const,
    )
  }

  /**
   * Has the grid's hook ask `question` in the table's dialog, as it does
   * before an action that asks first (`danger`: the action destroys).
   * Resolves with the answer: true for Confirm.
   */
  ask(question: string, danger = false): Promise<boolean> {
    return this.hookRoot.evaluate(
      (grid: any, [question, danger]) => grid._ashDataTable.ask(question, danger),
      [question, danger] as const,
    )
  }

  // ---- scrolling sideways ---------------------------------------------------

  /** The table's scrollbar at the bottom edge of the window, shown while its own is below it. */
  get scrollbar(): Locator {
    return this.byId(`${this.id}-scrollbar`)
  }

  /** How far the table is scrolled sideways in its own area, in whole pixels. */
  async scrollLeft(): Promise<number> {
    return this.hookRoot.evaluate((grid) => Math.round(grid.scrollLeft))
  }

  /** Scrolls the table sideways in its own area, as far as it goes, and waits until it is there. */
  async scrollTo(left: number): Promise<void> {
    await this.hookRoot.evaluate((grid, left) => {
      grid.scrollLeft = left
    }, left)
    await expect
      .poll(() =>
        this.hookRoot.evaluate(
          (grid, left) =>
            Math.abs(grid.scrollLeft - Math.min(left, grid.scrollWidth - grid.clientWidth)) < 1,
          left,
        ),
      )
      .toBe(true)
  }

  /** How wide what is seen of the table's own scroll area is, and how wide what scrolls in it. */
  async area(): Promise<{ left: number; seen: number; all: number }> {
    return this.hookRoot.evaluate((grid) => ({
      left: Math.round(grid.getBoundingClientRect().left),
      seen: grid.clientWidth,
      all: grid.scrollWidth,
    }))
  }

  header(column: string): Locator {
    return this.byId(`${this.id}-head-${column}`)
  }

  /**
   * The button in a sortable column's header: the stop that sorts
   * (ascending, descending, none). The header says the direction
   * (`aria-sort`). A header that does not sort has none.
   */
  sortButton(column: string): Locator {
    return this.byId(`${this.id}-sort-${column}`)
  }

  /** Sorts by a column with the pointer, a click on its header's button, and waits for the rows. */
  async sortBy(column: string): Promise<void> {
    await this.reads(() => this.sortButton(column).click())
  }

  // ---- skipping the table ---------------------------------------------------

  /**
   * "Skip table …": a link at the start of the table, before its header
   * row, out of sight until it has focus. It jumps to `skipTarget`.
   */
  get skip(): Locator {
    return this.byId(`${this.id}-skip`)
  }

  /** Where "Skip table" jumps to: an empty element after the table's pagination (and its full-view link). */
  get skipTarget(): Locator {
    return this.byId(`${this.id}-end`)
  }

  /** The headers of the table's columns: not the one of the expanders. */
  get headers(): Locator {
    return this.grid.locator(`:scope > [id="${this.id}-head"] [role=columnheader][id^="${this.id}-head-"]`)
  }

  /** Every cell of the header row, the one above the expanders among them. */
  get headerCells(): Locator {
    return this.grid.locator(`:scope > [id="${this.id}-head"] > [id="${this.id}-head-row"] > [role=columnheader]`)
  }

  /** The names of the columns, in order. */
  async columns(): Promise<string[]> {
    const prefix = `${this.id}-head-`
    return this.headers.evaluateAll(
      (cells, prefix) => cells.map((cell) => cell.id.slice(prefix.length)),
      prefix,
    )
  }

  /** The handle at the end of a column's header: the pointer drags it to change the column's width. No Tab stop. */
  resizer(column: string): Locator {
    return this.byId(`${this.id}-resize-${column}`)
  }

  /**
   * The width field of a column in the list of "Columns" ("Width of Title",
   * in pixels): the keyboard's way to a column's width. The label column has
   * one too, in an entry of its own first in the list.
   */
  widthField(column: string): Locator {
    return this.byId(`${this.id}-column-${column}-width`)
  }

  /** "Reset widths", after the columns in that list. */
  get resetWidths(): Locator {
    return this.byId(`${this.id}-reset-widths`)
  }

  /**
   * Makes a column `width` pixels wide from the keyboard: opens "Columns",
   * types the number into the column's width field and leaves it with Tab,
   * which clamps it to what a column may be (48 to 1000).
   */
  async typeWidth(column: string, width: number): Promise<void> {
    await this.openColumns()
    await this.widthField(column).focus()
    await this.retype(String(width))
    await this.page.keyboard.press("Tab")
  }

  // ---- hiding columns -----------------------------------------------------

  /** "Columns": the button above the grid that opens the list of the columns. */
  get columnsButton(): Locator {
    return this.byId(`${this.id}-columns-button`)
  }

  /**
   * What "Columns" is called, which the hook writes out of sight: "Columns
   * (2 hidden)", of a nested table "Columns of Comments (2 hidden)".
   */
  get columnsText(): Locator {
    return this.byId(`${this.id}-columns-text`)
  }

  /** The badge on "Columns" with how many columns are hidden: empty while none is. */
  get columnsCount(): Locator {
    return this.byId(`${this.id}-columns-count`)
  }

  /** The list it opens, the browser's popover: a box for every column that can be hidden. */
  get columnsList(): Locator {
    return this.byId(`${this.id}-columns`)
  }

  /** The box of one column in that list: ticked while the column is shown. */
  columnBox(column: string): Locator {
    return this.byId(`${this.id}-column-${column}`)
  }

  /** The line of one column in the list: its box, its name, and what is said of it while it is hidden. */
  columnEntry(column: string): Locator {
    return this.byId(`${this.id}-column-${column}-entry`)
  }

  /** What the line of a column says of it besides its name, while it is hidden: "(filtered)". */
  columnFlag(column: string): Locator {
    return this.columnEntry(column).locator("[data-flag]")
  }

  /** What is read out when a column is hidden or shown again. */
  get columnsStatus(): Locator {
    return this.byId(`${this.id}-columns-status`)
  }

  /** The columns the list offers, in order. */
  async listedColumns(): Promise<string[]> {
    const prefix = `${this.id}-column-`
    return this.columnsList
      .locator("input[type=checkbox]")
      .evaluateAll((boxes, prefix) => boxes.map((box) => box.id.slice(prefix.length)), prefix)
  }

  /** Whether the list of the columns is open: the browser's popover state. */
  async columnsOpen(): Promise<boolean> {
    return this.columnsList.evaluate((list) => list.matches(":popover-open"))
  }

  /**
   * Opens the list of the columns, if it is not open, and waits until it
   * stands where it opens: daisyUI's dropdown grows into place as it opens.
   */
  async openColumns(): Promise<void> {
    if (!(await this.columnsOpen())) await this.columnsButton.click()
    await expect(this.columnsList).toBeVisible()
    await this.columnsList.evaluate((list) =>
      Promise.all(list.getAnimations().map((animation) => animation.finished)),
    )
  }

  /** Hides columns with the pointer: opens the list and takes the tick out of each one's box. */
  async hide(...columns: string[]): Promise<void> {
    await this.openColumns()
    for (const column of columns) {
      await this.columnBox(column).uncheck()
      await expect(this.header(column)).toBeHidden()
    }
  }

  /** Shows hidden columns again with the pointer. */
  async unhide(...columns: string[]): Promise<void> {
    await this.openColumns()
    for (const column of columns) {
      await this.columnBox(column).check()
      await expect(this.header(column)).toBeVisible()
    }
  }

  /** The names of the columns that are shown, in order. */
  async shownColumns(): Promise<string[]> {
    const prefix = `${this.id}-head-`
    return this.headers.evaluateAll(
      (cells, prefix) =>
        cells.filter((cell) => cell.getClientRects().length > 0).map((cell) => cell.id.slice(prefix.length)),
      prefix,
    )
  }

  /** How wide a column's header is, in pixels. */
  async width(column: string): Promise<number> {
    return this.header(column).evaluate((cell) => cell.getBoundingClientRect().width)
  }

  /** How wide every cell of the header row is, the ones before and after the columns among them. */
  async widths(): Promise<number[]> {
    return this.headerCells.evaluateAll((cells) => cells.map((cell) => cell.getBoundingClientRect().width))
  }

  /**
   * Drags a column's handle `by` pixels with the mouse: to the right when
   * positive, and a little down, so that it is let go over another element
   * than the handle.
   */
  async drag(column: string, by: number, steps = 4): Promise<void> {
    const box = (await this.resizer(column).boundingBox())!
    const x = box.x + box.width / 2
    const y = box.y + box.height / 2
    await this.page.mouse.move(x, y)
    await this.page.mouse.down()
    await this.page.mouse.move(x + by, y + 3, { steps })
    await this.page.mouse.up()
  }

  /** The `<tbody>` of each row: not the one under it, which holds what the row expands into. */
  get rows(): Locator {
    return this.grid.locator(":scope > [role=rowgroup]:not([data-detail])")
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
    return this.grid.locator(`:scope > [role=rowgroup] > [role=row] > :is([role=cell],[role=rowheader])[id$="-c-${column}"]`)
  }

  /** The cells of a row, left to right, the expander and the label column's row header among them. */
  rowCells(key: string): Locator {
    return this.row(key).locator(":scope > [role=row] > :is([role=cell],[role=rowheader])")
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

  /** The last end of a filter that is a range; its first end is `filterValue`. */
  filterTo(column: string): Locator {
    return this.byId(`${this.id}-filter-${column}-to`)
  }

  /**
   * The field of the side panel that the button of a filter for several
   * values (`filterValue`) opens: a box per value of the column.
   */
  filterChoices(column: string): Locator {
    return this.field(column)
  }

  /**
   * Filters by several of a column's values with the pointer: the filter's
   * button opens the side panel, the boxes of `labels` are ticked and the
   * others not, and "Apply" filters. The operator ("is any of", "is none
   * of") is chosen first.
   */
  async chooseValues(column: string, labels: string[]): Promise<void> {
    await this.filterValue(column).click()
    await expect(this.panel).toBeVisible()
    const boxes = this.filterChoices(column).locator("input[type=checkbox]")
    for (const box of await boxes.all()) {
      const label = (await box.locator("xpath=..").innerText()).trim()
      if (labels.includes(label)) await box.check()
      else await box.uncheck()
    }
    await this.reads(() => this.panelSubmit.click())
    await expect(this.panel).toHaveCount(0)
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

  // ---- the argument line ---------------------------------------------------

  /** The line of inputs above the grid: the form of the table's arguments. */
  get argumentLine(): Locator {
    return this.byId(`${this.id}-arguments`)
  }

  /**
   * The input of an argument: of the read action by its name ("search"), of
   * one a column asks for by the column and its name ("due_within-days").
   */
  argument(name: string): Locator {
    return this.byId(`${this.id}-arg-${name}`)
  }

  /** What Ash says of a value it refuses, under the argument's input. */
  argumentError(name: string): Locator {
    return this.byId(`${this.id}-arg-${name}-error`)
  }

  /** "Fill in … to see records.", in place of the rows. */
  get fill(): Locator {
    return this.byId(`${this.id}-fill`)
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

  /** "Rows per page": the menu of a table that offers page sizes, after its buttons. */
  get pageSize(): Locator {
    return this.byId(`${this.id}-page-size`)
  }

  // ---- editing ------------------------------------------------------------

  /** The editor open in a cell. */
  editor(cell: Locator): Locator {
    return cell.locator("textarea, input, select")
  }

  /** Every editor open in the grid: one at most. The box that selects a row is no editor. */
  get openEditors(): Locator {
    return this.grid.locator(
      ":scope > [role=rowgroup] > [role=row] > :is([role=cell],[role=rowheader]):not([colspan], [data-selector]) :is(textarea, input, select)",
    )
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

  /**
   * The message of a cell whose save failed: what its `aria-describedby`
   * names, in the cell under what it shows.
   */
  failure(cell: Locator): Locator {
    return cell.locator(":scope > [id$='-error']")
  }

  /**
   * "Show all": the button the hook puts into every cell that cuts some of
   * its text off, read-only or editable, a Tab stop named after its column
   * ("Show all of Title"): it shows all of the text in place
   * (`aria-expanded`), and cuts it off again.
   */
  whole(cell: Locator): Locator {
    return cell.locator(":scope > [data-whole]")
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

  // ---- table actions ------------------------------------------------------

  /** The button of one table action, on the line of the table's name. */
  tableAction(name: string): Locator {
    return this.byId(`${this.id}-do-${name}`)
  }

  /** The buttons of the table actions on the line of the table's name, left to right. */
  get tableActions(): Locator {
    return this.root.locator(`:scope > div button[data-table-action][id^="${this.id}-do-"]`)
  }

  /** The button of a table action of a line's nested table: on the line, after its label. */
  lineAction(key: string, relationship: string, name: string): Locator {
    return this.byId(`${this.id}-row-${key}-t-${relationship}-do-${name}`)
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

  // ---- selecting rows, and acting on the selection ---------------------------

  /** The first cell of a row, where rows can be selected: it holds the row's box. */
  boxCell(key: string): Locator {
    return this.byId(`${this.id}-row-${key}-s`)
  }

  /** The box that selects a row. */
  box(key: string): Locator {
    return this.boxCell(key).locator("input[type=checkbox]")
  }

  /** The boxes of the rows of the page, top to bottom. */
  get boxes(): Locator {
    return this.grid.locator(":scope > [role=rowgroup] > [role=row] > :is([role=cell],[role=rowheader])[data-selector] > input[type=checkbox]")
  }

  /** The cell of the header above the boxes. */
  get pageBoxCell(): Locator {
    return this.byId(`${this.id}-select-head`)
  }

  /** The box in the header, which stands for the rows of the page. */
  get pageBox(): Locator {
    return this.pageBoxCell.locator("input[type=checkbox]")
  }

  /** The keys of the rows of the page whose box (or radio button) is checked, top to bottom. */
  async selectedKeys(): Promise<string[]> {
    const prefix = `${this.id}-row-`
    return this.rows.evaluateAll(
      (rows, prefix) =>
        rows
          .filter((row) => row.querySelector<HTMLInputElement>(":scope > [role=row] > [data-selector] > input")?.checked)
          .map((row) => row.id.slice(prefix.length)),
      prefix,
    )
  }

  /** The line above the grid: what is selected, and what can be done with it. */
  get selectionLine(): Locator {
    return this.byId(`${this.id}-selection`)
  }

  /** "3 selected": the live region of that line. Empty while nothing is selected. */
  get selectedCount(): Locator {
    return this.byId(`${this.id}-selected`)
  }

  /** "Select all 320 that match". */
  get selectAll(): Locator {
    return this.byId(`${this.id}-select-all`)
  }

  get clearSelection(): Locator {
    return this.byId(`${this.id}-clear-selection`)
  }

  /** The button of one action on the selected rows. */
  bulk(name: string): Locator {
    return this.byId(`${this.id}-bulk-${name}`)
  }

  /** "More": the button of the menu of the actions after the first two, where there are more than three. */
  get bulkMore(): Locator {
    return this.byId(`${this.id}-bulk-more-button`)
  }

  /** Uses an action on the selected rows as a person does: through "More" where it is in its menu. */
  async useBulk(name: string): Promise<void> {
    const button = this.bulk(name)
    const menu = this.byId(`${this.id}-bulk-more`)
    if ((await menu.count()) > 0 && (await menu.locator(`[data-bulk="${name}"]`).count()) > 0) {
      if (!(await menu.evaluate((m) => m.matches(":popover-open")))) await this.bulkMore.click()
      await expect(button).toBeVisible()
    }
    await button.click()
  }

  /** The buttons of the actions on the selected rows, left to right. */
  get bulkButtons(): Locator {
    return this.selectionLine.locator("button[data-bulk]")
  }

  /** What the last action on the selected rows came to. */
  get result(): Locator {
    return this.byId(`${this.id}-result`)
  }

  /** The radio button that selects a row, where one row at a time is selected. */
  radio(key: string): Locator {
    return this.boxCell(key).locator("input[type=radio]")
  }

  /** The radio buttons of the rows of the page, top to bottom. */
  get radios(): Locator {
    return this.grid.locator(":scope > [role=rowgroup] > [role=row] > :is([role=cell],[role=rowheader])[data-selector] > input[type=radio]")
  }

  // ---- the picker ---------------------------------------------------------

  /** The picker: a modal dialog with the table to choose a related record from, in the page only while it is open. */
  get picker(): Locator {
    return this.byId(`${this.id}-picker`)
  }

  /** Its heading: the column, and what is chosen. */
  get pickerTitle(): Locator {
    return this.byId(`${this.id}-picker-title`)
  }

  /** What it says when a choice was not taken. */
  get pickerError(): Locator {
    return this.byId(`${this.id}-picker-error`)
  }

  get pickerCancel(): Locator {
    return this.byId(`${this.id}-picker-cancel`)
  }

  /** "None": there only where the key can be empty. */
  get pickerNone(): Locator {
    return this.byId(`${this.id}-picker-none`)
  }

  /**
   * "Choose": takes the selected row, as the server holds it; says
   * `aria-disabled` while there is none.
   */
  get pickerChoose(): Locator {
    return this.byId(`${this.id}-picker-choose`)
  }

  /**
   * The table in the picker: a table like any other, under an id of its
   * own. `name` is the column the picker was opened for ("assignee"), or
   * the field of the action panel ("assignee_id").
   */
  pickerTable(name: string): Table {
    return new Table(this.page, `${this.id}-pick-${name}`, this.path)
  }

  /** The button of a field of the action panel that opens the picker. */
  fieldChoose(name: string): Locator {
    return this.byId(`${this.id}-panel-f-${name}-choose`)
  }

  /** What such a field says the chosen record is called; not there while it holds none. */
  fieldChosen(name: string): Locator {
    return this.byId(`${this.id}-panel-f-${name}-chosen`)
  }

  /** The input of such a field that holds the key: not shown. */
  fieldKey(name: string): Locator {
    return this.field(name).locator("input[data-key]")
  }

  /**
   * What a field that holds several related records says each of them is
   * called, in their order.
   */
  fieldChosenItems(name: string): Locator {
    return this.field(name).locator("[data-chosen]")
  }

  /** The button of such a field that takes one of its records out again, by its place, counted from 0. */
  fieldRemove(name: string, index: number): Locator {
    return this.byId(`${this.id}-panel-f-${name}-r-${index}`)
  }

  /**
   * Chooses a record for a field of the open action panel, with the
   * pointer: the field's button, the row with that key, "Choose". `null`
   * uses "None".
   */
  async chooseField(name: string, key: string | null): Promise<void> {
    await this.fieldChoose(name).click()
    await expect(this.picker).toBeVisible()
    if (key === null) await this.pickerNone.click()
    else {
      await this.pickerTable(name).radio(key).click()
      await this.pickerChoose.click()
    }
    await expect(this.picker).toHaveCount(0)
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
    return this.grid.locator(":scope > [role=rowgroup] > [role=row] > :is([role=cell],[role=rowheader])[data-expander]")
  }

  /** The lines under an expanded row, one per relationship: their cells. */
  lines(key: string): Locator {
    return this.byId(`${this.id}-row-${key}-x`).locator(":scope > [role=row] > [data-line]")
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
    return this.byId(`${this.id}-row-${key}-t-${relationship}-create`)
  }

  /** The cell under an open line that holds the nested table. */
  nestedCell(key: string, relationship: string): Locator {
    return this.byId(`${this.id}-row-${key}-n-${relationship}-c`)
  }

  /** The nested table under an open line: a table like any other. */
  nested(key: string, relationship: string): Table {
    return new Table(this.page, `${this.id}-row-${key}-t-${relationship}`, this.path)
  }

  /** The footer row of the summaries: the row after the last record. */
  get summaries(): Locator {
    return this.byId(`${this.id}-summaries`)
  }

  /** The cell of that row under a column: its summary, or nothing. */
  summary(column: string): Locator {
    return this.byId(`${this.id}-summary-${column}`)
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
   * The stops of the grid, and of the tables nested in it, in page
   * order: every element Tab can reach there (`tabIndex` 0 or more, shown,
   * not disabled, not in a closed dialog or popover), by its id, else
   * `id-of-its-cell>tag`. The controls of a nested table's heading line
   * stand on its line in the grid around it, and are among them.
   */
  async stops(): Promise<string[]> {
    return this.hookRoot.evaluate((root) =>
      Array.from(root.querySelectorAll<HTMLElement>("*"))
        .filter(
          (element) =>
            element.tabIndex >= 0 &&
            !(element as HTMLButtonElement).disabled &&
            !element.closest("dialog:not([open]), [popover]:not(:popover-open)") &&
            element.getClientRects().length > 0,
        )
        .map((element) => element.id || `${element.closest("[id]")?.id}>${element.tagName.toLowerCase()}`),
    )
  }

  /** The stops of a row, left to right, named as `stops()` names them: its box, expander, editable cells, buttons. */
  async rowStops(key: string): Promise<string[]> {
    return this.rowLine(key).evaluate((row) =>
      Array.from(row.querySelectorAll<HTMLElement>("*"))
        .filter(
          (element) =>
            element.tabIndex >= 0 && !(element as HTMLButtonElement).disabled && element.getClientRects().length > 0,
        )
        .map((element) => element.id || `${element.closest("[id]")?.id}>${element.tagName.toLowerCase()}`),
    )
  }

  /** What has focus, named as `stops()` names a stop; `BODY` where nothing has. */
  async focusedStop(): Promise<string> {
    return this.page.evaluate(() => {
      const active = document.activeElement as HTMLElement | null
      if (!active || active === document.body) return "BODY"
      return active.id || `${active.closest("[id]")?.id}>${active.tagName.toLowerCase()}`
    })
  }

  /**
   * Presses Tab (Shift+Tab with `back`) `count` times from where focus is,
   * and gives what has focus after each press, as `stops()` names it.
   */
  async walk(count: number, back = false): Promise<string[]> {
    const seen: string[] = []
    for (let i = 0; i < count; i++) {
      await this.page.keyboard.press(back ? "Shift+Tab" : "Tab")
      seen.push(await this.focusedStop())
    }
    return seen
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

/**
 * How many rules the tables of a page have written for the widths of columns
 * and for hidden columns, in the style sheets their hooks own. Every grid has
 * one such sheet from the start, for what its hook says of scrolling
 * sideways; a width or a hidden column is a rule in a second one.
 */
export async function columnRules(page: Page): Promise<number> {
  return page.evaluate(
    () =>
      document.adoptedStyleSheets
        .flatMap((sheet) => Array.from(sheet.cssRules))
        .filter((rule) => /max-width|display: none/.test(rule.cssText)).length,
  )
}

/** How many style sheets the hooks of a page own, and how many grids the page has. */
export async function ownedSheets(page: Page): Promise<{ sheets: number; grids: number }> {
  return page.evaluate(() => ({
    sheets: document.adoptedStyleSheets.length,
    grids: document.querySelectorAll("[data-ash-data-table]").length,
  }))
}

// Everything the page pushed before this is heard once this returns. An
// event is pushed in the task of the key or click that caused it, or in a
// timer of 0 ms it set (leaving an editor), which runs before the timer of
// 0 ms set here after it. Then an event of the tests' own goes the way of
// every event of the page: the LiveView answers it after all that came
// before it on the socket, and its answer comes after theirs, patches and
// all. It is an event of a table that is not there (`e2e-barrier`), which
// every table answers alike and the recorder does not keep. A page without
// a table pushes no table event.
export async function answered(page: Page): Promise<void> {
  await page.evaluate(async () => {
    await new Promise((resolve) => setTimeout(resolve, 0))
    const grid: any = document.querySelector("[phx-hook='AshDataTable.Grid']")
    if (grid?._ashDataTable) await grid._ashDataTable.pushEventTo(grid, "ash_data_table:e2e-barrier:save", {})
  })
}
