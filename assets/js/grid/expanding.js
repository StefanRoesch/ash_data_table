// The grid's hook: expanding.
//
// These methods are part of the one hook object that grid/index.js
// puts together, and share its state through `this`.

import {GRID, HANDLE} from "../markers.js"
import {PRINTABLE, is} from "./shared.js"

export default {
  // Whether the expander of a row, or a line, is open.
  isOpen(cell) {
    const button = cell.querySelector("button")
    return !!button && button.getAttribute("aria-expanded") === "true"
  },

  // Uses the expander of a row, or a line under it: one event. A
  // line comes back with its row's detail, patched in. A row is not
  // sent again, so the answer says whether it is expanded now.
  open(cell) {
    const button = cell.querySelector("button")
    if (!button || button.dataset.pending !== undefined) return
    if (is(cell, "line")) {
      const row = cell.closest("tbody").dataset.row
      this.transport.push("toggle", {row, relationship: cell.dataset.line})
    } else {
      button.dataset.pending = ""
      this.transport.push("expand", {row: this.rowKey(cell)}, reply => {
        delete button.dataset.pending
        if (reply && typeof reply.open === "boolean") button.setAttribute("aria-expanded", String(reply.open))
      })
    }
  },

  // Follows the link a cell holds, as a click on it does.
  follow(cell) {
    const link = cell.querySelector("a[href]")
    if (link) link.click()
  },

  // Into the nested table a cell holds: to the cell it was left at,
  // or to its first.
  enterNested(cell) {
    const grid = cell.querySelector(GRID)
    const hook = grid && grid._ashDataTable
    if (hook) hook.move(hook.pos.r, hook.pos.c)
    return !!hook
  },

  onKeydown(e) {
    const cell = this.cellOf(e.target)
    if (!cell || e.altKey) return
    if (this.editing && this.editing.list && this.editing.root.contains(e.target)) return this.onListKeydown(e)
    if (this.editing && e.target === this.editing.input) return this.onEditorKeydown(e)
    // the "Clear" button of a sensitive cell's editor is of the editor
    if (this.editing && this.editing.clear === e.target) return this.onEditorKeydown(e)
    const handle = e.target.closest(HANDLE)
    if (handle) return this.onResizeKeydown(e, handle)
    const control = this.controlOf(e.target)
    if (control) return this.onControlKeydown(e, control)
    const rows = this.rows()
    const head = this.headRows()
    const r = cell.parentElement.rowIndex
    // Where Page Down and Ctrl+End end: at the last row, but for
    // the footer row of the summaries, which is an Arrow Down
    // further, as the header rows are an Arrow Up further from
    // Page Up and Ctrl+Home.
    const lastR = this.lastRow(rows)
    const ctrl = e.ctrlKey || e.metaKey
    let handled = true
    // the expander of a row, and a line under it
    const expands = is(cell, "expander") || is(cell, "line")
    // with Shift, Down Arrow and Up Arrow select as they go
    if (e.shiftKey && (e.key === "ArrowDown" || e.key === "ArrowUp") && this.selects() === "multi" && this.record(cell)) {
      this.extend(cell, e.key === "ArrowDown" ? 1 : -1)
      e.preventDefault()
      return
    }
    if (e.key !== "Shift") this.selection.range = null
    // Shift+Enter on a sensitive cell shows its value, and hides
    // it again; Enter alone is the cell's editor, as everywhere
    if (e.key === "Enter" && e.shiftKey && this.secretOf(cell)) {
      this.reveal(cell)
      e.preventDefault()
      return
    }
    switch (e.key) {
      // on an expander that is closed, Right Arrow opens it and Left
      // Arrow on one that is open closes it, as in a tree
      case "ArrowRight":
        if (expands && !this.isOpen(cell)) this.open(cell)
        else if (!this.spans(cell)) { this.col = this.step(cell, 1); this.move(r, this.col) }
        break
      case "ArrowLeft":
        if (expands && this.isOpen(cell)) this.open(cell)
        else if (!this.spans(cell)) { this.col = this.step(cell, -1); this.move(r, this.col) }
        break
      case "ArrowDown": this.move(r + 1, this.col); break
      // from the first data row this reaches the filter row, then the header
      case "ArrowUp": this.move(r - 1, this.col); break
      case "PageDown": this.move(Math.max(r, Math.min(r + this.pageRows(cell), lastR)), this.col); break
      // stays in the data rows; the header rows are an Arrow Up further
      case "PageUp": this.move(r < head ? r : Math.max(r - this.pageRows(cell), head), this.col); break
      // to the first column that is shown, and to the last
      case "Home":
        this.col = this.edge(rows[0], 1)
        this.move(ctrl ? Math.min(head, lastR) : r, this.col)
        break
      case "End": {
        const row = ctrl ? rows[lastR] : cell.parentElement
        if (!this.spans(row.cells[0])) this.col = this.edge(row, -1)
        this.move(row.rowIndex, this.edge(row, -1))
        break
      }
      case "Enter":
        if (cell.tagName === "TH" && cell.dataset.sort !== undefined) cell.click()
        else if (cell.dataset.filter !== undefined || is(cell, "pager") || is(cell, "actions")) this.enter(cell)
        else if (expands) this.open(cell)
        else if (is(cell, "nested")) this.enterNested(cell)
        else if (is(cell, "view")) this.follow(cell)
        else if (this.canEdit(cell)) this.startEdit(cell, null)
        // in a table to choose one record from, Enter on a row chooses it
        else if (this.chooses() && this.selects() === "single" && this.record(cell)) this.chooseRow(this.record(cell))
        else handled = false
        break
      case "F2":
        // on the header of a column: to the handle that changes
        // the column's width
        if (cell.tagName === "TH" && this.handleOf(cell)) this.handleOf(cell).focus()
        // into a cell that holds controls; a line among them, when
        // it holds more than the button that opens it
        else if (cell.dataset.filter !== undefined || is(cell, "pager") || is(cell, "actions")) this.enter(cell)
        else if (is(cell, "line") && cell.querySelector("button[data-create],button[data-table-action]")) this.enter(cell)
        else if (is(cell, "nested")) this.enterNested(cell)
        else if (this.canEdit(cell)) this.startEdit(cell, null)
        else handled = false
        break
      // gives up the edit of a cell whose save failed; in a nested
      // table, goes back out to the cell that holds it
      case "Escape":
        // first of all, a value that is shown is hidden again
        if (this.revealed && this.revealed.cell === cell) this.hide()
        else if (cell.hasAttribute("aria-invalid")) this.discard(cell)
        else if (this.holder()) this.holder().focus()
        else handled = false
        break
      // Selects the row, or takes it out of the selection, from any
      // of its cells; on the box of the page, all its rows. Anywhere
      // else, and where rows are not selected, it does nothing, and
      // is swallowed so that the page does not scroll.
      case " ":
        if (!this.selects()) break
        if (is(cell, "selectPage")) this.togglePage()
        else if (this.record(cell)) this.toggleRow(this.record(cell))
        break
      default:
        if (PRINTABLE(e) && cell.dataset.filter !== undefined) {
          // Typing on a filter cell goes into the filter as Enter
          // does, and the browser goes on to type the character
          // there: over the text or number, which is selected; into
          // the first part of a date; to the first choice that
          // starts with it.
          const control = this.enter(cell)
          handled = false
          // A character a number does not take (a letter, say)
          // would empty it: the number stays, as in a data cell.
          if (control && control.type === "number") {
            const current = control.value
            setTimeout(() => {
              if (document.activeElement === control && control.value === "" && !control.validity.badInput) {
                control.value = current
                control.select()
              }
            }, 0)
          }
        } else {
          // typing starts the edit with what is typed
          handled = PRINTABLE(e) && this.canEdit(cell) && this.startEdit(cell, e.key)
        }
    }
    if (handled) e.preventDefault()
  },

  pageRows(cell) {
    return Math.max(1, Math.floor(window.innerHeight / (cell.offsetHeight || 24)) - 2)
  },
}
