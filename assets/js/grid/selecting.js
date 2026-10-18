// The grid's hook: selecting.
//
// These methods are part of the one hook object that grid/index.js
// puts together, and share its state through `this`.

import {BULK, CLEAR, CURRENT, DESTRUCTIVE, DETAIL, ROWGROUP, SELECT_ALL, SELECTION, SELECTOR, TABLE} from "../markers.js"
import {LISTED, cellsOf, firstRow, groupsOf, is, place} from "./shared.js"

export default {
  // Whether rows can be selected, and how many at a time: "multi",
  // "single", or nothing.
  selects() { return this.el.dataset.select },

  // Whether the table is one to choose a record from: the one in a
  // picker.
  chooses() { return this.el.dataset.choose !== undefined },

  // Chooses a row at once: selects it, and tells the picker.
  chooseRow(body) {
    this.toggleRow(body)
    this.el.dispatchEvent(new CustomEvent("ash_data_table:choose", {bubbles: true, detail: this.selected()}))
  },

  // The rows of records of the page, top to bottom: not what is
  // open under a row.
  records() {
    return groupsOf(this.table()).filter(body => this.isRecord(body) && firstRow(body))
  },

  // Whether a row group is a record's: not the grid's header or footer
  // (`ID-head`, `ID-foot`, which a kit may make row groups too), nor the
  // detail under a record (`DETAIL`).
  isRecord(group) {
    return !!group && is(group, ROWGROUP) && group !== this.part("head") && group !== this.part("foot") && !is(group, DETAIL)
  },

  // The row of records a cell is in, if it is in one: not the header
  // or the footer, nor the lines of a detail.
  record(cell) {
    const body = cell.closest(ROWGROUP)
    return body && body.closest(TABLE) === cell.closest(TABLE) && this.isRecord(body) ? body : null
  },

  keyOf(body) { return body.id.slice(this.id.length + 5) },

  // What the server is told of a row: nothing more than its key,
  // where that is its primary key, else what the row says itself.
  named(body) { return body.dataset.key !== undefined ? LISTED(body.dataset.key) : null },

  // The line above the grid, and a part of the table by its id.
  line() { return document.getElementById(`${this.id}-selection`) },
  part(name) { return document.getElementById(`${this.id}-${name}`) },

  // What is selected, for whoever asks: every record the filters
  // match (`all`), or `rows`, each by its primary key: one value,
  // or the list of them for a key of several attributes.
  //
  // In a table to choose one record from, what is selected is the
  // selected row that is in view: one that a filter or another
  // page has taken out of sight is not there to be taken, and is
  // selected again when it comes back. Where several are chosen,
  // what is selected is what is chosen, in view or not: the
  // records the field holds already are among it from the start.
  selected() {
    const {keys, all} = this.selection
    const held = this.chooses() && this.selects() === "single"
      ? Array.from(keys).filter(([key]) => document.getElementById(`${this.id}-row-${key}`))
      : Array.from(keys)
    return {
      table: this.id,
      mode: this.selects(),
      all,
      rows: all ? [] : held.map(([key, named]) => named || key)
    }
  },

  // Makes `keys` the selection, or every record that matches. This
  // is where a selection changes: the rows and the line follow, and
  // whoever listens is told. `seen` says that the person did it,
  // which is when the outcome of the last action on a selection has
  // been read and can go. The server holds what is selected, and is
  // told every change (`select`), but the one it made itself and
  // tells the hook (`told`, `ash_data_table:select`).
  //
  // A question about running an action on the selection that is still
  // open is given up when the selection changes: it named another.
  select(keys, all, seen = true, told = false) {
    const selection = this.selection
    const changed = all !== selection.all || keys.size !== selection.keys.size ||
      Array.from(keys.keys()).some(key => !selection.keys.has(key))
    if (changed && this.bulkAsked && this.answer === this.bulkAsked) this.giveUp()
    selection.keys = keys
    selection.all = all
    if (!all && keys.size === 0) selection.anchor = null
    this.paint()
    this.el.dispatchEvent(new CustomEvent("ash_data_table:selection", {bubbles: true, detail: this.selected()}))
    if (!told) {
      this.transport.push("select", all ? {all: true} : {rows: Array.from(keys).map(([key, named]) => named || key)})
    }
    if (seen && this.part("result")) this.transport.push("bulk_seen", {})
  },

  // The keys that are selected as a person sees them: with "all
  // that match", the rows of the page are what there is to take
  // one out of.
  shown() {
    const {keys, all} = this.selection
    return all ? new Map(this.records().map(body => [this.keyOf(body), this.named(body)])) : new Map(keys)
  },

  toggleRow(body) {
    const key = this.keyOf(body)
    let keys = this.shown()
    // the person has selected: what the server marked as chosen
    // is no longer what the selection starts from
    this.selection.touched = true
    if (this.selects() === "single") {
      // as radio buttons: the selected row stays selected
      if (keys.has(key) && keys.size === 1) return
      keys = new Map([[key, this.named(body)]])
    } else if (keys.has(key)) keys.delete(key)
    else keys.set(key, this.named(body))
    this.selection.anchor = key
    this.select(keys, false)
  },

  // The box of the page: all its rows, or none of them when all
  // are selected already. The rows of other pages stay as they are.
  togglePage() {
    if (this.selects() !== "multi") return
    const rows = this.records()
    const keys = this.shown()
    const every = rows.length > 0 && rows.every(body => keys.has(this.keyOf(body)))
    for (const body of rows) {
      if (every) keys.delete(this.keyOf(body))
      else keys.set(this.keyOf(body), this.named(body))
    }
    this.select(keys, false)
  },

  // The rows from `from` to `to`, by their keys, as they stand in
  // the page; only `to` when `from` is on another page.
  between(from, to) {
    const rows = this.records()
    const end = rows.indexOf(to)
    let start = rows.findIndex(body => this.keyOf(body) === from)
    if (start < 0) start = end
    return rows.slice(Math.min(start, end), Math.max(start, end) + 1)
  },

  // A click with Shift: the rows from the one that was selected or
  // clicked last to this one are selected, with what was before.
  selectTo(body) {
    // with every record selected there is none to add
    if (this.selection.all) return
    const keys = this.shown()
    for (const row of this.between(this.selection.anchor, body)) keys.set(this.keyOf(row), this.named(row))
    if (this.selection.anchor === null) this.selection.anchor = this.keyOf(body)
    this.select(keys, false)
  },

  // Shift with Down Arrow or Up Arrow: focus goes to the row of
  // records after or before this one, and the rows from where the
  // key was first pressed to there are selected, with what was
  // selected before. Going back takes rows out of it again.
  extend(cell, step) {
    const selection = this.selection
    const rows = this.records()
    const from = this.record(cell)
    const to = rows[rows.indexOf(from) + step]
    if (!to) return
    const cells = cellsOf(firstRow(to))
    const target = cells[Math.min(place(cell), cells.length - 1)]
    // with every record selected there is none to add
    if (selection.all) return target.focus()
    if (!selection.range) selection.range = {anchor: this.keyOf(from), before: this.shown()}
    const keys = new Map(selection.range.before)
    for (const row of this.between(selection.range.anchor, to)) keys.set(this.keyOf(row), this.named(row))
    selection.anchor = selection.range.anchor
    target.focus()
    this.select(keys, false)
  },

  // Says of every row whether it is selected, on the row and in
  // its box. After every change of the selection, and after every
  // patch: the server sends rows that say nothing of it. The line
  // above the grid is the server's: it draws it from what it is told.
  paint() {
    const mode = this.selects()
    if (!mode) return
    const selection = this.selection
    const rows = this.records()
    // A table to choose several records from starts with the rows
    // selected of the records that are chosen now, as the server
    // names them (`data-chosen-rows`): on this page and on the others.
    if (this.chooses() && mode === "multi" && !selection.seeded) {
      selection.seeded = true
      let chosen = []
      try { chosen = JSON.parse(this.el.dataset.chosenRows || "[]") } catch (_error) { /* none */ }
      if (chosen.length > 0) return this.select(new Map(chosen), false, false)
    }
    // In a table to choose one from, the row of the record that is
    // chosen now is selected until the person selects another.
    if (this.chooses() && mode === "single" && !selection.touched) {
      const current = rows.find(body => is(body, CURRENT) && !selection.keys.has(this.keyOf(body)))
      if (current) return this.select(new Map([[this.keyOf(current), this.named(current)]]), false, false)
    }
    let onPage = 0
    for (const body of rows) {
      const on = selection.all || selection.keys.has(this.keyOf(body))
      if (on) onPage++
      const row = firstRow(body)
      if (row.getAttribute("aria-selected") !== String(on)) row.setAttribute("aria-selected", String(on))
      const selector = row.querySelector(SELECTOR)
      const box = selector && selector.querySelector("input")
      if (box && box.checked !== on) box.checked = on
    }
    // A table to choose from says again what is selected when the
    // selected row comes into view or goes out of it, with the
    // rows of another read.
    if (this.chooses() && selection.inView !== onPage) {
      const before = selection.inView
      selection.inView = onPage
      if (before !== undefined) {
        this.el.dispatchEvent(new CustomEvent("ash_data_table:selection", {bubbles: true, detail: this.selected()}))
      }
    }
    const every = rows.length > 0 && onPage === rows.length
    // this table's own header: not that of a table nested in it,
    // which may stand before it in the page
    const head = this.part("select-head")
    const page = head && head.querySelector("input")
    if (page) {
      if (page.checked !== every) page.checked = every
      const some = onPage > 0 && !every
      if (page.indeterminate !== some) page.indeterminate = some
    }
    // The buttons of the line go with the selection, as the server
    // draws it, and the line with them where nothing else is on it:
    // where one of them had the focus, it goes on to the grid.
    const controls = this.part("selection-controls")
    const focus = this.lineFocus
    const gone = !!focus && (!focus.isConnected || (!!controls && controls.hidden && controls.contains(focus)))
    const left = document.activeElement === document.body || (!!controls && controls.contains(document.activeElement))
    if (gone && left) {
      this.lineFocus = null
      this.toTabStop()
    }
  },

  // To the cell that is the tab stop of the tree of grids.
  toTabStop() {
    const tree = this.tree()
    const cell = tree.activeId && document.getElementById(tree.activeId)
    if (cell) cell.focus({preventScroll: true})
  },

  // A button of the line above the grid. The line of a table nested
  // in this one is inside this table's element too, and is that
  // table's.
  onLineClick(e) {
    const line = e.target.closest && e.target.closest(SELECTION)
    if (!line || line !== this.line()) return
    const button = e.target.closest("button")
    if (!button) return
    // "Select all that match" goes as every record is selected, and
    // focus goes on to "Clear selection"; that one goes with what was
    // selected, and focus goes on to the grid
    if (is(button, SELECT_ALL)) {
      this.select(new Map(), true)
      this.part("clear-selection").focus({preventScroll: true})
    } else if (is(button, CLEAR)) {
      this.select(new Map(), false)
      this.toTabStop()
    } else if (is(button, BULK)) {
      // one of the menu of the actions after the first two: the menu
      // closes, and its button has the focus, which the question gives
      // back to it
      const menu = button.closest("[popover]")
      if (menu) {
        menu.hidePopover()
        const opener = this.part("bulk-more-button")
        if (opener) opener.focus({preventScroll: true})
      }
      this.bulk(button)
    }
  },

  // Uses the button of an action on the selected rows. The server
  // is told the action, and runs it on what it holds as selected,
  // and nothing runs yet: it opens the action's panel, or answers
  // with the question to ask first, which says how many records it
  // is about, and with a token of the selection it named
  // (`selection`). Confirm then runs the action, with that token: the
  // server runs nothing when what it holds as selected is no longer
  // what the question named. What became of it comes back as a patch,
  // and as the rows on which it did not run, which stay selected
  // (`ash_data_table:select`).
  //
  // A question that is open gives way to this one (`ask`), and this
  // one is given up when the selection changes (`select`).
  bulk(button) {
    if (button.getAttribute("aria-disabled") === "true" || this.bulking) return
    const {all, rows} = this.selected()
    if (!all && rows.length === 0) return
    const action = button.dataset.bulk
    // one push at a time: a second waits for the answer to the first
    this.bulking = true
    this.transport.push("bulk", {action}).then(reply => {
      this.bulking = false
      if (!reply || !reply.ask) return
      // Cancel, and Escape: the browser puts focus back on the button
      const asked = this.ask(reply.ask, is(button, DESTRUCTIVE))
      this.bulkAsked = this.answer
      asked.then(confirmed => {
        if (confirmed === true) this.transport.push("bulk_run", {action, selection: reply.selection})
      })
    })
  },
}
