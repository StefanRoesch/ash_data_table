// The grid's hook: the tree of grids.
//
// These methods are part of the one hook object that grid/index.js
// puts together, and share its state through `this`.

import {filterRow as filterRowId, filters as filtersId, head as headId} from "../ids.js"
import {ACTION, ACTIONS, EXPANDER, FILTER, GRID, HANDLE, LINE, NESTED, OPEN, PAGER, REVEAL, ROW, ROWGROUP, SELECTOR, SELECT_PAGE, SUMMARIES, TABLE, WHOLE} from "../markers.js"
import {AROUND, CELL, SPANNING, cellsOf, firstRow, is, page, place, rowsOf} from "./shared.js"

export default {
  // The grid on the page that this one is nested in, at whatever
  // depth; itself when it is nested in none.
  top() {
    let top = this.el
    for (let up; (up = AROUND(top, GRID));) top = up
    return top
  },

  // What the grids of one tree share: the one cell that is the tab
  // stop (`activeId`) with the grid it is in (`owner`), where focus
  // falls back to when that cell goes away (`trail`), and whether
  // focus is in the tree.
  tree() {
    const top = this.top()
    return top._ashDataTableTree || (top._ashDataTableTree = {activeId: null, owner: null, trail: [], hadFocus: false})
  },

  // Whether a node is in this grid, and not in a table nested in it:
  // neither in that table's grid, which has its own hook, nor in what
  // that table has around its grid (its dialog, its "Clear filters").
  owns(node) {
    if (!node || !node.closest || node.closest(GRID) !== this.el) return false
    const holder = node.closest(NESTED)
    return !holder || holder === node || !this.el.contains(holder)
  },

  // The cell of the grid around this one that holds it, if any.
  holder() { return AROUND(this.el, NESTED) },

  // The number of columns before the first data column.
  lead() { return Number(this.el.dataset.lead || 0) },

  // Where focus goes when a cell goes away with what is around it,
  // nearest first: out of each nested table to the cell that held it,
  // then to its line, then to the expander of its row.
  trailOf(cell) {
    const trail = []
    for (let node = cell; node;) {
      if (is(node, NESTED)) trail.push(node.dataset.lineCell, node.dataset.expanderCell)
      else if (is(node, LINE)) trail.push(node.id.replace(/-l-[^-]+-c$/, "-e"))
      const grid = node.closest(GRID)
      node = grid ? AROUND(grid, NESTED) : null
      if (node) trail.push(node.id)
    }
    return trail
  },

  // The grid itself: the first in this element, as the grids nested
  // in it stand in its cells.
  table() { return this.el.querySelector(TABLE) },

  // The rows of the grid: the header rows first, wherever the header
  // sits among the stream's rows in the page, then the rows of the
  // records and what is under them, as they stand, and the footer's
  // rows last.
  rows() {
    const rows = rowsOf(this.table())
    const head = document.getElementById(headId(this.id))
    const foot = this.part("foot")
    const of = part => part ? rows.filter(row => part.contains(row)) : []
    const rest = rows.filter(row => !(head && head.contains(row)) && !(foot && foot.contains(row)))
    return of(head).concat(rest, of(foot))
  },

  // Where a row stands among them.
  rowAt(row) { return this.rows().indexOf(row) },

  // The rows above the data rows: the header, and the filter row where
  // a column filters.
  headRows() {
    const head = document.getElementById(headId(this.id))
    return head ? head.querySelectorAll(ROW).length : 1
  },

  // The input, menu or button of a filter, or the editor of a cell,
  // that a node is or is in.
  controlOf(node) {
    const control = node && node.closest ? node.closest("input,select,textarea,button") : null
    return control && this.el.contains(control) ? control : null
  },

  cellOf(node) {
    const cell = node && node.closest ? node.closest(CELL) : null
    return cell && this.owns(cell) ? cell : null
  },

  // The last row that is not the footer row of the summaries: the
  // last record, or in a nested table the row of its pages or of
  // its link.
  lastRow(rows) {
    const foot = rows.length - 1
    return foot > 0 && is(rows[foot], SUMMARIES) ? foot - 1 : foot
  },

  // The cell at the place of one that is gone, as `cellAt`, but
  // never in the footer row of the summaries: where the last record
  // went, focus goes to the row before it, and to the filter row
  // when no record is left.
  cellBack(r, c) { return this.cellAt(Math.min(r, this.lastRow(this.rows())), c) },

  cellAt(r, c) {
    const rows = this.rows()
    if (rows.length === 0) return null
    const cells = cellsOf(rows[Math.max(0, Math.min(r, rows.length - 1))])
    const cell = cells[Math.max(0, Math.min(c, cells.length - 1))]
    // never a cell of a hidden column: the one beside it
    return cell ? this.seenNear(cell) : null
  },

  setActive(cell) {
    const tree = this.tree()
    const previous = tree.activeId && document.getElementById(tree.activeId)
    if (previous && previous !== cell && previous.tabIndex !== -1) previous.tabIndex = -1
    tree.activeId = cell.id
    tree.owner = this.el
    tree.trail = this.trailOf(cell)
    this.pos = {r: this.rowAt(cell.closest(ROW)), c: place(cell)}
    // while a cell is edited its editor is the tab stop, so that
    // Shift+Tab from the editor leaves the grid as Tab does
    const tabIndex = this.editing && this.editing.cell === cell ? -1 : 0
    if (cell.tabIndex !== tabIndex) cell.tabIndex = tabIndex
  },

  // After every patch: the server renders each cell with tabindex -1,
  // so the one tab stop has to be put back, and so has focus when the
  // focused cell did not survive the patch.
  //
  // The tab stop is one for the whole tree of grids. When its cell is
  // gone, the next best takes its place: the cell at the same place
  // of the same grid (after a sort, a filter or another page); when
  // that grid is gone too, the nearest cell that held it (a line
  // that was closed, a row that was closed); and at last the cell
  // the grid on the page had before.
  //
  // `records` are the changes that were seen, when it was those
  // that called. The rows are marked as selected again unless all
  // that changed is the tab stop, which is every move of the focus.
  sync(records) {
    if (!records || records.some(record => record.attributeName !== "tabindex")) {
      this.paint()
      this.watchColumns()
      this.fitColumns()
      this.measure()
    }
    // a patch has brought the cell whose value was shown as the
    // server renders it, or taken it away: nothing is shown any more
    if (this.revealed && !this.shows(this.revealed.cell)) this.revealed = null
    // or a cell that waits for the host's answer: it waits still
    if (this.holds && this.holds.size) this.rehold()
    const tree = this.tree()
    const top = this.top()
    const hook = top._ashDataTable
    // the hook of the grid on the page mounts first
    if (!hook) return
    let cell = tree.activeId && document.getElementById(tree.activeId)
    if (cell && !top.contains(cell)) cell = null
    if (!cell && tree.owner && tree.owner.isConnected && top.contains(tree.owner) && tree.owner._ashDataTable) {
      const owner = tree.owner._ashDataTable
      cell = owner.cellBack(owner.pos.r, owner.pos.c)
    }
    if (!cell) {
      const id = tree.trail.find(id => id && document.getElementById(id) && top.contains(document.getElementById(id)))
      cell = id ? document.getElementById(id) : hook.cellBack(hook.pos.r, hook.pos.c)
    }
    const owner = cell && cell.closest(GRID)._ashDataTable
    if (!owner) return
    owner.setActive(cell)
    this.renumber()
    // while the dialog asks, focus is in the dialog and stays there
    if (owner.editing && owner.editing.asking) return
    if (tree.hadFocus && !top.contains(document.activeElement)) {
      cell.focus({preventScroll: true})
    }
    // a patch may have brought a cell whose whole text showed, or cut off
    this.offerWhole()
  },

  move(r, c) {
    const cell = this.cellAt(r, c)
    if (!cell) return
    cell.focus()
    this.intoView(cell)
  },

  // Whether the arrow keys stop at a cell: at every cell but a cell of
  // the filter row that holds no filter (`data-filter`), which they pass
  // over: Up Arrow from a row goes on to the column's header.
  stops(cell) {
    const row = cell.closest(ROW)
    return !(row && row.id === filterRowId(this.id) && !is(cell, FILTER))
  },

  // Up Arrow and Down Arrow: to the row above or below, in the column,
  // past a row whose cell there is no stop (never sideways to another).
  vertical(r, by) {
    const rows = this.rows()
    let to = r + by
    while (to >= 0 && to < rows.length && !this.stops(this.inColumn(rows[to], this.col))) to += by
    if (to >= 0 && to < rows.length) this.move(to, this.col)
  },

  // The cell of a row in a column, or its last: a cell that spans the
  // grid stands in every column.
  inColumn(row, c) {
    const cells = cellsOf(row)
    return cells[Math.max(0, Math.min(c, cells.length - 1))]
  },

  // The rows say where they stand among all rows (`aria-rowindex`).
  // The server numbers them when it reads a page, and sends a row
  // again only when that row changes: after a row was added at the
  // top or taken out, the others are numbered here, from the first
  // row's index on, in the order they stand in. The server counts
  // the same way for the rows it sends later.
  renumber() {
    const table = this.table()
    let index = table && Number(table.dataset.firstRow)
    if (!index) return
    for (const body of this.records()) {
      const row = firstRow(body)
      if (row.getAttribute("aria-rowindex") !== String(index)) row.setAttribute("aria-rowindex", String(index))
      index++
    }
  },

  // A cell that spans the table: a line, the cell of a nested table,
  // the cell of a nested table's pages. Moving up and down through
  // one keeps the column the person was in.
  spans(cell) { return SPANNING(cell) },

  onFocusin(e) {
    const tree = this.tree()
    const cell = this.cellOf(e.target)
    if (!cell) { tree.hadFocus = false; return }
    tree.hadFocus = true
    // an input of a nested table's heading line, which stands on its
    // line, is a tab stop of its own (its argument line): the tree's tab
    // stop stays where it is, so that Tab from it goes on into the grid
    if (is(cell, LINE) && e.target !== cell && e.target.tabIndex >= 0) return
    if (!this.spans(cell)) this.col = place(cell)
    this.setActive(cell)
    this.offerWhole()
    if (page.tabbing) this.intoView(cell)
  },

  onFocusout(e) {
    const tree = this.tree()
    const top = this.top()
    // focus leaves the cell whose value is shown: it is hidden again
    const shown = this.revealed && this.revealed.cell
    if (shown && shown.contains(e.target) && !(e.relatedTarget && shown.contains(e.relatedTarget))) this.hide()
    if (e.relatedTarget) {
      if (!top.contains(e.relatedTarget)) tree.hadFocus = false
    } else {
      // No new target: either focus really left (a click on nothing),
      // or a patch removed the focused cell and sync() puts it back.
      const target = e.target
      setTimeout(() => {
        if (target.isConnected && !top.contains(document.activeElement)) tree.hadFocus = false
      }, 0)
    }
    setTimeout(() => this.offerWhole(), 0)
  },

  onClick(e) {
    // a click on the handle of a column is no click on its header:
    // it does not sort
    if (e.target.closest(HANDLE)) { e.stopPropagation(); return }
    const cell = this.cellOf(e.target)
    if (!cell) return
    if (!this.spans(cell)) this.col = place(cell)
    this.selection.range = null
    // the box of a row, and the one of the page: a click on it or
    // beside it in its cell uses it, with focus on the cell
    if (this.selects() && (is(cell, SELECTOR) || is(cell, SELECT_PAGE))) {
      if (is(cell, SELECT_PAGE)) this.togglePage()
      else if (e.shiftKey && this.selects() === "multi") this.selectTo(cell.closest(ROWGROUP))
      else this.toggleRow(cell.closest(ROWGROUP))
      if (document.activeElement !== cell) cell.focus()
      return
    }
    // the expander of a row and the button of a line: used, with
    // focus on their cell
    if (is(cell, EXPANDER) || is(cell, LINE)) {
      const button = e.target.closest("button")
      // another control of a line (of its nested table's heading line:
      // "Columns" and its list, an input, create) is used as it is, and
      // keeps the focus: a panel gives it back
      if (button && !button.hasAttribute("aria-expanded")) return
      if (!button && e.target.closest("input,select,textarea,label,[popover]")) return
      if (button) this.open(cell)
      // a button that was used from the keyboard keeps the focus
      if (document.activeElement !== cell && !(button && e.detail === 0)) cell.focus()
      return
    }
    // a button of the actions cell: used, and it keeps the focus. A
    // click beside the buttons is a click on the cell.
    if (is(cell, ACTIONS)) {
      const opener = e.target.closest(OPEN)
      if (opener) return this.openRow(cell)
      const button = e.target.closest(ACTION)
      if (button) return this.act(button)
    }
    // the button of a cell that cuts its text off: shows all of it, or
    // cuts it off again, with focus on the cell
    if (e.target.closest(WHOLE)) {
      this.toggleWhole(cell)
      if (document.activeElement !== cell) cell.focus()
      return
    }
    // the button of a sensitive cell: shows the value, or hides it
    // again, with focus on the cell, which the value is shown for
    // as long as it has
    if (e.target.closest(REVEAL)) {
      if (document.activeElement !== cell) cell.focus()
      this.reveal(cell)
      return
    }
    // a click on a filter's control or in an editor leaves focus there
    if (this.controlOf(e.target)) return
    if (this.editing && this.editing.cell === cell) return
    // with Shift, on a row of records: the rows from the one that
    // was selected last to this one
    if (e.shiftKey && this.selects() === "multi" && this.record(cell)) this.selectTo(this.record(cell))
    // in a table to choose from, a click anywhere on a row selects
    // it; where several are chosen, or takes it out again
    else if (this.chooses() && this.record(cell)) this.toggleRow(this.record(cell))
    if (document.activeElement !== cell) cell.focus()
  },

  // A click with Shift selects rows, and is not to select the text
  // between the two clicks as well.
  onMousedown(e) {
    const cell = this.cellOf(e.target)
    if (!cell || !e.shiftKey || this.selects() !== "multi" || !this.record(cell)) return
    if (this.controlOf(e.target) && !is(cell, SELECTOR)) return
    if (this.editing && this.editing.cell === cell) return
    e.preventDefault()
  },

  onDblclick(e) {
    // on the handle of a column: the column is as wide again as
    // it was
    const handle = e.target.closest(HANDLE)
    if (handle) {
      e.stopPropagation()
      this.resetWidth(handle.closest(CELL))
      return
    }
    const cell = this.cellOf(e.target)
    // In a table to choose from, a double click chooses the row.
    // Not where several are chosen: its two clicks have selected
    // the row and taken it out again, and there is no one row to take.
    if (cell && this.chooses() && this.record(cell)) {
      if (this.selects() === "single") this.chooseRow(this.record(cell))
      return
    }
    if (!cell || this.controlOf(e.target) || !this.canEdit(cell)) return
    // beside the control of an editor that is open already: nothing to open
    if (this.editing && this.editing.cell === cell) return
    this.startEdit(cell, null)
  },

  // Into a filter cell: to where its value is typed or chosen, or to
  // its menu when the operator needs no value. Into a cell that
  // holds buttons (the actions of a row, the pages of a nested
  // table): to the first of them. Returns the control.
  enter(cell) {
    const control = cell.querySelector("[id$='-value']") ||
      Array.from(cell.querySelectorAll("select,button")).find(control => this.usable(control))
    if (!control) return null
    control.focus()
    if (control.select) control.select()
    return control
  },

  // Inside a filter the keys belong to its controls, the arrow keys
  // among them. The grid keeps three.
  onControlKeydown(e, control) {
    const cell = this.cellOf(control)
    const input = control.tagName === "INPUT"
    switch (e.key) {
      // back to the cell, giving up what was typed and not applied
      case "Escape":
        if (input) control.value = control.defaultValue
        cell.focus()
        e.preventDefault()
        break
      // applies the filter now; focus stays where the person is typing.
      // A patch leaves the value attribute of a focused input alone,
      // so what Escape restores is noted here.
      // this table's filters only: the argument line of a nested table
      // on a line is that table's (its hook sends it)
      case "Enter":
        if (input && control.form && control.form.id === filtersId(this.id)) {
          e.preventDefault()
          if (control.form.reportValidity()) {
            control.defaultValue = control.value
            control.form.requestSubmit()
          }
        }
        break
      // through the controls of this filter; from its last one Tab
      // leaves the grid, as it does from a cell
      // (but from an input of a nested table's heading line on a line, a
      // tab stop of its own: Tab is the browser's, from tab stop to tab stop)
      case "Tab":
        if (is(cell, LINE) && control.tabIndex >= 0) break
        if (this.toControl(cell, control, e.shiftKey ? -1 : 1)) e.preventDefault()
        break
      // through the buttons of a cell that holds several: the pages
      // of a nested table, the actions of a row, a line's controls
      case "ArrowLeft":
      case "ArrowRight":
        // not in what is typed into, where they move in the text
        if (is(cell, PAGER) || is(cell, ACTIONS) || (is(cell, LINE) && !this.typedInto(control))) {
          this.toControl(cell, control, e.key === "ArrowLeft" ? -1 : 1)
          e.preventDefault()
        }
        break
    }
  },

  // Whether a control is one a person types into, where the arrow keys
  // move in the text.
  typedInto(control) {
    return control.tagName === "TEXTAREA" || (control.tagName === "INPUT" && !["checkbox", "radio", "button", "submit"].includes(control.type))
  },

  // To the control before or after this one in its cell, if there is one.
  // A control a person can use: not disabled, and not hidden.
  usable(control) { return !control.disabled && control.getClientRects().length > 0 },

  toControl(cell, control, step) {
    const controls = Array.from(cell.querySelectorAll("input,select,button")).filter(control => this.usable(control))
    const next = controls[controls.indexOf(control) + step]
    if (next) next.focus()
    return !!next
  },
}
