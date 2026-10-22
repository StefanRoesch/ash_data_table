// The grid's hook: row actions.
//
// These methods are part of the one hook object that grid/index.js
// puts together, and share its state through `this`.

import {DESTRUCTIVE} from "../markers.js"
import {is} from "./shared.js"

export default {
  // Uses a button of a row's actions cell: one event with the row
  // and the action, after the question of an action that has one.
  // What happens then is the server's: the action runs and the row
  // comes back, patched in, or is taken away; or its panel opens. Where
  // the patch takes the button away, focus is put back (`repair`).
  act(button) {
    const cell = this.cellOf(button)
    if (!cell || cell.hasAttribute("aria-busy")) return
    const run = () => {
      this.busy(cell, true)
      const payload = {row: this.rowKey(cell), action: button.dataset.action}
      this.transport.push("act", payload).then(reply => {
        if ((reply && reply.removed) || !cell.isConnected) return
        this.busy(cell, false)
        // the record is gone: there is no row to send, so the cell is marked here
        if (reply && reply.error) this.fail(cell, reply.error, () => {})
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
}
