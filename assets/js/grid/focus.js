// The grid's hook: focus and the pointer.
//
// These methods are part of the one hook object that grid/index.js
// puts together, and share its state through `this`.

import {filterRow as filterRowId, head as headId, row as rowId} from "../ids.js"
import {FOCUSABLE} from "../panel.js"
import {ACTION, ACTIONS, DIALOG, EXPANDER, GRID, HANDLE, LINE, NESTED, OPEN, OPENED, REVEAL, ROWGROUP, SELECTOR, SELECT_PAGE, TABLE, WHOLE} from "../markers.js"
import {ANYCELL, SPANNING, firstRow, is, page, rowsOf} from "./shared.js"

export default {
  // Whether a node is in this grid, and not in a table nested in it:
  // neither in that table's grid, which has its own hook, nor in what
  // that table has around its grid (its dialog, its "Clear filters").
  owns(node) {
    if (!node || !node.closest || node.closest(GRID) !== this.el) return false
    const holder = node.closest(NESTED)
    return !holder || holder === node || !this.el.contains(holder)
  },

  // The number of columns before the first data column.
  lead() { return Number(this.el.dataset.lead || 0) },

  // The table itself: the first in this element, as the tables nested
  // in it stand in its cells.
  table() { return this.el.querySelector(TABLE) },

  // The rows of the table: the header rows first, wherever the header
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

  // The input, menu or button of a filter, or the editor of a cell,
  // that a node is or is in.
  controlOf(node) {
    const control = node && node.closest ? node.closest("input,select,textarea,button") : null
    return control && this.el.contains(control) ? control : null
  },

  cellOf(node) {
    const cell = node && node.closest ? node.closest(ANYCELL) : null
    return cell && this.owns(cell) ? cell : null
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

  // LiveView puts a stream's items before the other children of its
  // container (its guide, "Non-stream items in stream containers", says
  // so, and to reorder them with a hook): the records' row groups before
  // the table's header. The eye sees the header first all the same, Tab
  // and a screen reader follow the page. So the rows that stand before
  // the header (all of them after a read, a new one at the top) are put
  // after it, in their order; the header, where focus may be (a filter),
  // is not moved.
  headFirst() {
    const table = this.table()
    const head = document.getElementById(headId(this.id))
    if (!table || !head || head.parentElement !== table) return
    const before = []
    for (let node = table.firstElementChild; node && node !== head; node = node.nextElementSibling) before.push(node)
    if (before.length > 0) head.after(...before)
  },

  // A cell that spans the table: a line, the cell of a nested table,
  // the cell of a nested table's pages.
  spans(cell) { return SPANNING(cell) },

  // The stops in an element, in the order Tab takes: what a person can use
  // there now (not disabled, not hidden).
  stopsIn(root) {
    return root ? Array.from(root.querySelectorAll(FOCUSABLE)).filter(node => node.getClientRects().length > 0) : []
  },

  // The table's first Tab stop: where focus goes when nothing better is
  // left (section 2.9 of the note).
  toFirstStop() {
    const stop = this.stopsIn(this.table())[0]
    if (stop) stop.focus({preventScroll: true})
  },

  // Where focus is in this table, for when a patch takes that element
  // away: its id, the record's row it is in (its place among the
  // records, and its own place among that row's stops), and, inside a
  // nested table, the line's and the expander's buttons around it. The
  // panel, the picker and the question, which stand in the page or over
  // it, are places of their own: focus there leaves this as it was.
  noteFocus(target) {
    const around = target.closest(`${DIALOG},${OPENED}`)
    if (around && this.el.contains(around)) return
    // the cell of this table that holds the nested table focus is in
    let holder = target.closest(NESTED)
    while (holder && holder.closest(GRID) !== this.el) holder = holder.parentElement && holder.parentElement.closest(NESTED)
    // the record's row it is in, or the lines under it (the detail, its
    // record's): a nested table stands in a line
    const group = (holder || target).closest(ROWGROUP)
    const records = this.records()
    const body = group && (this.isRecord(group) ? group : document.getElementById(rowId(this.id, group.dataset.row || "")))
    const row = body ? records.indexOf(body) : -1
    const place = body === group ? this.stopPlace(target) : [0, -1]
    // a cell of this table's filter row, whose clear button goes as its
    // filter is cleared: its id, and where in it
    const filterRow = !body && !holder ? document.getElementById(filterRowId(this.id)) : null
    const cell = filterRow && filterRow.contains(target) ? target.closest(ANYCELL) : null
    const within = cell ? this.stopsIn(cell).indexOf(target) : -1
    this.focused = {target, row, place, holder, cell: cell && cell.id, within, trail: holder ? [holder.dataset.lineCell, holder.dataset.expanderCell] : []}
  },

  // Where a stop stands in its row: its cell's column (`aria-colindex`),
  // and its place among the stops of that cell (-1: the cell itself).
  // Rows of one table have stops in other numbers (a "Show all" only
  // where a text is cut off, a cell editable in one record and not in
  // another), so a place is a column, not a count of stops.
  stopPlace(stop) {
    const cell = stop.closest(ANYCELL)
    if (!cell) return [0, -1]
    return [Number(cell.getAttribute("aria-colindex") || 0), cell === stop ? -1 : this.stopsIn(cell).indexOf(stop)]
  },

  // After a patch that left focus nowhere (the callers ask): to the
  // element that had it, where the patch took it out and put it back
  // (a stream that is reset puts back a row's elements, and `headFirst`
  // moves rows: either way the element is in the page and focus is
  // not); to the element of the same id, if it is back; inside a nested
  // table that went, to its line's button, else to its row's expander;
  // in a filter's cell, to the stop at the same place in it, else the one
  // before it; to the same stop of the row at the same place, which is the row
  // after the one that went, else of the row before; else to the
  // table's first stop. A nested table that is still there sees to its
  // own rows. The page does not scroll for it.
  repair() {
    const focused = this.focused
    if (!focused) return
    if (focused.holder && focused.holder.isConnected) return
    this.focused = null
    const take = node => {
      if (!node) return false
      node.focus({preventScroll: true})
      return document.activeElement === node
    }
    if (focused.target.isConnected && take(focused.target)) return
    if (focused.target.id && take(document.getElementById(focused.target.id))) return
    for (const id of focused.trail) {
      const cell = id && document.getElementById(id)
      if (cell && take(cell.querySelector("button[aria-expanded]"))) return
    }
    // in a filter's cell: the stop at the same place, else the one
    // before it (a filter's clear button goes with the filter: its value)
    const cell = focused.cell && document.getElementById(focused.cell)
    if (cell) {
      const stops = this.stopsIn(cell)
      if (take(stops[Math.min(focused.within, stops.length - 1)])) return
    }
    const records = this.records()
    if (focused.row >= 0 && records.length > 0) {
      // the stop at the same place, else the next one along the row,
      // else its last
      const body = records[Math.min(focused.row, records.length - 1)]
      const stops = this.stopsIn(body)
      const [column, within] = focused.place
      const at = place => place[0] > column || (place[0] === column && place[1] >= within)
      if (take(stops.find(stop => at(this.stopPlace(stop))) || stops[stops.length - 1])) return
    }
    this.toFirstStop()
  },

  // Heard from the tables nested in this one too: where focus is in
  // them is noted (`noteFocus`); the rest is this table's own.
  onFocusin(e) {
    this.noteFocus(e.target)
    if (!this.owns(e.target)) return
    const cell = this.cellOf(e.target)
    if (!cell) return
    // a cell that Tab comes to is brought out from under what stays in view
    if (page.tabbing) this.intoView(cell)
  },

  onFocusout(e) {
    // focus leaves the cell whose value is shown: it is hidden again
    const shown = this.revealed && this.revealed.cell
    if (shown && shown.contains(e.target) && !(e.relatedTarget && shown.contains(e.relatedTarget))) this.hide()
    // Focus goes somewhere else in the page: nothing is to be put back.
    // Without a new target either focus really left (a click on
    // nothing: the element is still there), or a patch took the element
    // away, and `repair` takes care of it.
    const target = e.target
    const to = e.relatedTarget
    if (to && !this.el.contains(to) && !to.closest(`${DIALOG},${OPENED}`)) this.focused = null
    // focus moves on in the table: what is noted is where it goes, so
    // that a patch while it is on its way (a value hidden as focus
    // leaves its cell) does not put it back
    else if (to && this.el.contains(to)) this.noteFocus(to)
    else if (!to) setTimeout(() => {
      if (target.isConnected && document.activeElement === document.body && this.focused && this.focused.target === target) this.focused = null
    }, 0)
  },

  onClick(e) {
    // a click on the handle of a column is no click on its header:
    // it does not sort
    if (e.target.closest(HANDLE)) { e.stopPropagation(); return }
    const cell = this.cellOf(e.target)
    if (!cell) return
    // the box of a row, and the one of the page
    if (this.selects() && (is(cell, SELECTOR) || is(cell, SELECT_PAGE))) {
      if (is(cell, SELECT_PAGE)) this.togglePage()
      else if (e.shiftKey && this.selects() === "multi") this.selectTo(cell.closest(ROWGROUP))
      else this.toggleRow(cell.closest(ROWGROUP))
      return
    }
    // the expander of a row and the button of a line; another control
    // of a line (of its nested table's heading line: "Columns" and its
    // list, an input, create) is used as it is
    if (is(cell, EXPANDER) || is(cell, LINE)) {
      const button = e.target.closest("button")
      if (button && button.hasAttribute("aria-expanded")) this.open(cell)
      return
    }
    // a button of the actions cell. A click beside the buttons is a
    // click on the cell.
    if (is(cell, ACTIONS)) {
      const opener = e.target.closest(OPEN)
      if (opener) return this.openRow(cell)
      const button = e.target.closest(ACTION)
      if (button) return this.act(button)
    }
    // the button of a cell that cuts its text off (a click, Enter or
    // Space): shows all of it, or cuts it off again; focus stays on it
    if (e.target.closest(WHOLE)) {
      this.toggleWhole(cell)
      return
    }
    // the button of a sensitive cell: shows the value, or hides it
    // again, which is shown for as long as focus is in the cell
    const reveal = e.target.closest(REVEAL)
    if (reveal) {
      if (!cell.contains(document.activeElement)) reveal.focus()
      this.reveal(cell)
      return
    }
    // a click on a filter's control or in an editor leaves focus there
    if (this.controlOf(e.target)) return
    if (this.editing && this.editing.cell === cell) return
    // A click from the keyboard or from assistive technology (no
    // pointer, `detail` 0) on an editable cell edits it, as Enter does:
    // a screen reader in browse mode may keep Enter for itself.
    if (e.detail === 0 && e.target === cell && this.canEdit(cell)) return this.startEdit(cell, null)
    // with Shift, on a row of records: the rows from the one that
    // was selected last to this one
    if (e.shiftKey && this.selects() === "multi" && this.record(cell)) this.selectTo(this.record(cell))
    // in a table to choose from, a click anywhere on a row selects
    // it; where several are chosen, or takes it out again
    else if (this.chooses() && this.record(cell)) this.toggleRow(this.record(cell))
    if (cell.matches(FOCUSABLE) && document.activeElement !== cell) cell.focus()
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
      this.resetWidth(handle.closest(ANYCELL))
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
}
