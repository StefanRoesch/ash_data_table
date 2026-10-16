// The grid's hook: the tree of grids.
//
// These methods are part of the one hook object that grid/index.js
// puts together, and share its state through `this`.

import {GRID, HANDLE} from "../markers.js"
import {AROUND, is, page} from "./shared.js"

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
    const holder = node.closest("td[data-nested]")
    return !holder || holder === node || !this.el.contains(holder)
  },

  // The cell of the grid around this one that holds it, if any.
  holder() { return AROUND(this.el, "td[data-nested]") },

  // The number of columns before the first data column.
  lead() { return Number(this.el.dataset.lead || 0) },

  // Where focus goes when a cell goes away with what is around it,
  // nearest first: out of each nested table to the cell that held it,
  // then to its line, then to the expander of its row.
  trailOf(cell) {
    const trail = []
    for (let node = cell; node;) {
      if (is(node, "nested")) trail.push(node.dataset.lineCell, node.dataset.expanderCell)
      else if (is(node, "line")) trail.push(node.id.replace(/-l-[^-]+-c$/, "-e"))
      const grid = node.closest(GRID)
      node = grid ? AROUND(grid, "td[data-nested]") : null
      if (node) trail.push(node.id)
    }
    return trail
  },

  rows() {
    // HTMLTableElement.rows lists the header rows first, wherever the
    // header sits among the stream's rows in the DOM.
    const table = this.el.querySelector("table")
    return table ? table.rows : []
  },

  // The rows above the data rows: the header and the filter row.
  headRows() {
    const table = this.el.querySelector("table")
    return table && table.tHead ? table.tHead.rows.length : 1
  },

  // The input, menu or button of a filter, or the editor of a cell,
  // that a node is or is in.
  controlOf(node) {
    const control = node && node.closest ? node.closest("input,select,textarea,button") : null
    return control && this.el.contains(control) ? control : null
  },

  cellOf(node) {
    const cell = node && node.closest ? node.closest("td,th") : null
    return cell && this.owns(cell) ? cell : null
  },

  // The last row that is not the footer row of the summaries: the
  // last record, or in a nested table the row of its pages or of
  // its link.
  lastRow(rows) {
    const foot = rows.length - 1
    return foot > 0 && is(rows[foot], "summaries") ? foot - 1 : foot
  },

  // The cell at the place of one that is gone, as `cellAt`, but
  // never in the footer row of the summaries: where the last record
  // went, focus goes to the row before it, and to the filter row
  // when no record is left.
  cellBack(r, c) { return this.cellAt(Math.min(r, this.lastRow(this.rows())), c) },

  cellAt(r, c) {
    const rows = this.rows()
    if (rows.length === 0) return null
    const row = rows[Math.max(0, Math.min(r, rows.length - 1))]
    const cell = row.cells[Math.max(0, Math.min(c, row.cells.length - 1))]
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
    this.pos = {r: cell.parentElement.rowIndex, c: cell.cellIndex}
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
    // a patch may have brought, replaced or taken away a message
    this.showMessage()
    // or the text of the cell whose whole text is showing
    this.freshWhole()
  },

  move(r, c) {
    const cell = this.cellAt(r, c)
    if (!cell) return
    cell.focus()
    this.intoView(cell)
  },

  // The rows say where they stand among all rows (`aria-rowindex`).
  // The server numbers them when it reads a page, and sends a row
  // again only when that row changes: after a row was added at the
  // top or taken out, the others are numbered here, from the first
  // row's index on, in the order they stand in. The server counts
  // the same way for the rows it sends later.
  renumber() {
    const table = this.el.querySelector("table")
    let index = table && Number(table.dataset.firstRow)
    if (!index) return
    for (const body of table.tBodies) {
      if (is(body, "detail") || !body.rows[0]) continue
      if (body.rows[0].getAttribute("aria-rowindex") !== String(index)) {
        body.rows[0].setAttribute("aria-rowindex", String(index))
      }
      index++
    }
  },

  // A cell that spans the table: a line, the cell of a nested table,
  // the cell of a nested table's pages. Moving up and down through
  // one keeps the column the person was in.
  spans(cell) { return cell.colSpan > 1 },

  onFocusin(e) {
    const tree = this.tree()
    const cell = this.cellOf(e.target)
    if (!cell) { tree.hadFocus = false; return }
    tree.hadFocus = true
    if (!this.spans(cell)) this.col = cell.cellIndex
    this.setActive(cell)
    this.showMessage()
    this.focusedWhole(e.target === cell ? cell : null)
    if (page.tabbing) this.intoView(cell)
  },

  onFocusout(e) {
    const tree = this.tree()
    const top = this.top()
    // focus leaves the cell whose value is shown: it is hidden again
    const shown = this.revealed && this.revealed.cell
    if (shown && shown.contains(e.target) && !(e.relatedTarget && shown.contains(e.relatedTarget))) this.hide()
    // focus goes on from the list of a filter for several values:
    // the list closes, and what was ticked applies. A click on the
    // name of a box takes focus to the cell on its way to the box.
    const now = this.choosing
    if (now && e.relatedTarget && e.relatedTarget !== now.cell &&
        !now.list.contains(e.relatedTarget) && e.relatedTarget !== now.button) this.closeChoices(true, false)
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
    setTimeout(() => this.showMessage(), 0)
    this.focusedWhole(null)
  },

  onClick(e) {
    // a click on the handle of a column is no click on its header:
    // it does not sort
    if (e.target.closest(HANDLE)) { e.stopPropagation(); return }
    const cell = this.cellOf(e.target)
    if (!cell) return
    if (!this.spans(cell)) this.col = cell.cellIndex
    this.selection.range = null
    // the box of a row, and the one of the page: a click on it or
    // beside it in its cell uses it, with focus on the cell
    if (this.selects() && (is(cell, "selector") || is(cell, "selectPage"))) {
      if (is(cell, "selectPage")) this.togglePage()
      else if (e.shiftKey && this.selects() === "multi") this.selectTo(cell.closest("tbody"))
      else this.toggleRow(cell.closest("tbody"))
      if (document.activeElement !== cell) cell.focus()
      return
    }
    // the expander of a row and the button of a line: used, with
    // focus on their cell
    if (is(cell, "expander") || is(cell, "line")) {
      const button = e.target.closest("button")
      // another control of a line (its create button) is used as it
      // is, and keeps the focus: its panel gives it back
      if (button && !button.hasAttribute("aria-expanded")) return
      if (button) this.open(cell)
      // a button that was used from the keyboard keeps the focus
      if (document.activeElement !== cell && !(button && e.detail === 0)) cell.focus()
      return
    }
    // a button of the actions cell: used, and it keeps the focus. A
    // click beside the buttons is a click on the cell.
    if (is(cell, "actions")) {
      const opener = e.target.closest("button[data-open]")
      if (opener) return this.openRow(cell)
      const button = e.target.closest("button[data-action]")
      if (button) return this.act(button)
    }
    // the button of a sensitive cell: shows the value, or hides it
    // again, with focus on the cell, which the value is shown for
    // as long as it has
    if (e.target.closest("button[data-reveal]")) {
      if (document.activeElement !== cell) cell.focus()
      this.reveal(cell)
      return
    }
    // the button of a filter for several values opens its list, and
    // closes it again, which applies what was ticked
    const chooser = e.target.closest("[data-choices-button]")
    if (chooser) return this.choosing ? this.closeChoices(true, false) : this.openChoices(chooser)
    if (e.target.closest("[data-choices]")) return
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
    if (this.controlOf(e.target) && !is(cell, "selector")) return
    if (this.editing && this.editing.cell === cell) return
    e.preventDefault()
  },

  onDblclick(e) {
    // on the handle of a column: the column is as wide again as
    // it was
    const handle = e.target.closest(HANDLE)
    if (handle) {
      e.stopPropagation()
      this.resetWidth(handle.parentElement)
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
    if (this.onChoicesKeydown(e, control)) return
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
      case "Enter":
        if (input && control.form) {
          e.preventDefault()
          if (control.form.reportValidity()) {
            control.defaultValue = control.value
            control.form.requestSubmit()
          }
        }
        break
      // through the controls of this filter; from its last one Tab
      // leaves the grid, as it does from a cell
      case "Tab":
        if (this.toControl(cell, control, e.shiftKey ? -1 : 1)) e.preventDefault()
        break
      // through the buttons of a cell that holds several: the pages
      // of a nested table, the actions of a row, a line's controls
      case "ArrowLeft":
      case "ArrowRight":
        if (is(cell, "pager") || is(cell, "actions") || is(cell, "line")) {
          this.toControl(cell, control, e.key === "ArrowLeft" ? -1 : 1)
          e.preventDefault()
        }
        break
    }
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
