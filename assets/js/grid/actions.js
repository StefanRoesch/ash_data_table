// The grid's hook: row actions.
//
// These methods are part of the one hook object that grid/index.js
// puts together, and share its state through `this`.

import {DESTRUCTIVE, ROWGROUP} from "../markers.js"
import {cellsOf, firstRow, is, place} from "./shared.js"

export default {
  // Uses a button of a row's actions cell: one event with the row
  // and the action, after the question of an action that has one.
  // What happens then is the server's: the action runs and the row
  // comes back, patched in, or is taken away; or its panel opens.
  act(button) {
    const cell = this.cellOf(button)
    if (!cell || cell.hasAttribute("aria-busy")) return
    const run = () => {
      this.note(cell, button)
      cell.setAttribute("aria-busy", "true")
      const payload = {row: this.rowKey(cell), action: button.dataset.action}
      this.transport.push("act", payload).then(reply => {
        if (reply && reply.removed) return this.refocus()
        if (!cell.isConnected) return
        cell.removeAttribute("aria-busy")
        // the record is gone: there is no row to send, so the cell is marked here
        if (reply && reply.error) this.fail(cell, reply.error, () => {})
        // the button keeps the focus through the patch of its row
        if (reply && !reply.panel && document.activeElement === document.body) {
          const same = document.getElementById(button.id)
          if (same) same.focus({preventScroll: true})
        }
      })
    }
    const question = button.dataset.question
    if (!question) return run()
    // Cancel, and Escape: the browser puts focus back on the button
    this.ask(question, is(button, DESTRUCTIVE)).then(confirmed => { if (confirmed === true) run() })
  },

  // Uses the page's "Open" of a row: the server is told the row, and
  // tells the page. Nothing changes here.
  openRow(cell) {
    this.transport.push("open", {row: this.rowKey(cell)})
  },

  // Where the cell of the action stands, for when its row is gone:
  // its column, and the rows after and before its own.
  note(cell, button) {
    const row = step => {
      let body = cell.closest(ROWGROUP)
      do { body = step(body) } while (body && !this.isRecord(body))
      return body ? body.id : null
    }
    this.acted = {
      c: place(cell),
      next: row(body => body.nextElementSibling),
      previous: row(body => body.previousElementSibling),
      button: button.id
    }
  },

  // After the row of the action that was used last is gone: to the
  // same column of the row after it, else of the row before it,
  // else to the grid's first cell.
  refocus() {
    const acted = this.acted || {}
    const body = [acted.next, acted.previous].map(id => id && document.getElementById(id)).find(body => body && firstRow(body))
    const cells = body ? cellsOf(firstRow(body)) : []
    const cell = body
      ? cells[Math.min(acted.c, cells.length - 1)]
      : this.cellBack(this.headRows(), this.lead())
    if (cell) cell.focus({preventScroll: true})
  },
}
