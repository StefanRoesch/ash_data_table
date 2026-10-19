// The grid's hook: the keys.
//
// These methods are part of the one hook object that grid/index.js
// puts together, and share its state through `this`.
//
// The table is a table: Tab and Shift+Tab go from stop to stop (its
// controls and its editable cells), and every control keeps the keys
// the browser gives it. What is left here: on an editable cell, Enter,
// a typed character, Shift+Enter and Escape; in a filter, Enter and
// Escape; in a table to choose a record from, Enter on a row's button;
// Escape on a row action's button whose action failed; and the keys of
// an open editor (saving.js).

import {filters as filtersId} from "../ids.js"
import {FAILED, SELECTOR} from "../markers.js"
import {PRINTABLE, is} from "./shared.js"

export default {
  onKeydown(e) {
    if (e.altKey) return
    const ed = this.editing
    // the "Clear" button of a sensitive cell's editor is of the editor
    if (ed && (e.target === ed.input || e.target === ed.clear)) return this.onEditorKeydown(e)
    const cell = this.cellOf(e.target)
    if (!cell) return
    const control = this.controlOf(e.target)
    if (control) return this.onControlKey(e, control, cell)
    if (e.target !== cell || !this.canEdit(cell)) return
    // Shift+Enter on a cell that cuts its text off shows all of it, and
    // cuts it off again; on a sensitive cell it shows its value, and
    // hides it again. Enter alone is the cell's editor.
    if (e.key === "Enter" && e.shiftKey) {
      if (this.toggleWhole(cell)) e.preventDefault()
      else if (this.secretOf(cell)) { this.reveal(cell); e.preventDefault() }
      return
    }
    let handled = true
    switch (e.key) {
      case "Enter": this.startEdit(cell, null); break
      // a value that is shown is hidden again, a whole text cut off
      // again, and the edit of a cell whose save failed given up
      case "Escape":
        if (this.revealed && this.revealed.cell === cell) this.hide()
        else if (this.lessWhole(cell)) break
        else if (is(cell, FAILED)) this.discard(cell)
        else handled = false
        break
      // typing starts the edit with what is typed
      default: handled = PRINTABLE(e) && this.startEdit(cell, e.key)
    }
    if (handled) e.preventDefault()
  },

  // The keys in a control of the table: a filter's, a row's box or
  // button, a sensitive cell's "Show". The browser's, but for these.
  onControlKey(e, control, cell) {
    const input = control.tagName === "INPUT"
    switch (e.key) {
      case "Escape":
        // a value that is shown is hidden again
        if (this.revealed && this.revealed.cell === cell) { this.hide(); e.preventDefault() }
        // the message of a row action that failed is given up, and the
        // failed reveal of a sensitive cell
        else if (is(cell, FAILED)) { this.discard(cell); e.preventDefault() }
        // a filter gives up what was typed and not applied; focus stays
        else if (input && control.form && control.form.id === filtersId(this.id)) {
          control.value = control.defaultValue
          e.preventDefault()
        }
        break
      case "Enter":
        // A filter applies now; focus stays where the person is typing.
        // A patch leaves the value attribute of a focused input alone,
        // so what Escape restores is noted here. This table's filters
        // only: the argument line of a nested table on a line is that
        // table's (its hook sends it).
        if (input && control.form && control.form.id === filtersId(this.id)) {
          e.preventDefault()
          if (control.form.reportValidity()) {
            control.defaultValue = control.value
            control.form.requestSubmit()
          }
        // in a table to choose one record from, Enter on a row's button
        // chooses that row
        } else if (this.chooses() && this.selects() === "single" && is(cell, SELECTOR) && this.record(cell)) {
          e.preventDefault()
          this.chooseRow(this.record(cell))
        }
        break
    }
  },
}
