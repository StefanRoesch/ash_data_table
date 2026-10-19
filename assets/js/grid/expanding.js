// The grid's hook: expanding.
//
// These methods are part of the one hook object that grid/index.js
// puts together, and share its state through `this`.

import {LINE, ROWGROUP} from "../markers.js"
import {is} from "./shared.js"

export default {
  // Uses the expander of a row, or a line under it: one event. A
  // line comes back with its row's detail, patched in. A row is not
  // sent again, so the answer says whether it is expanded now.
  open(cell) {
    const button = cell.querySelector("button")
    if (!button || button.dataset.pending !== undefined) return
    if (is(cell, LINE)) {
      const row = cell.closest(ROWGROUP).dataset.row
      this.transport.push("toggle", {row, relationship: cell.dataset.line})
    } else {
      button.dataset.pending = ""
      this.transport.push("expand", {row: this.rowKey(cell)}).then(reply => {
        delete button.dataset.pending
        if (reply && typeof reply.open === "boolean") button.setAttribute("aria-expanded", String(reply.open))
      })
    }
  },
}
