// The grid's hook: sensitive cells.
//
// These methods are part of the one hook object that grid/index.js
// puts together, and share its state through `this`.

import {ACTIONS, MASK, MASKED, REVEAL, SECRET} from "../markers.js"
import {is} from "./shared.js"

export default {
  // What a sensitive cell holds besides its mask: the button that
  // asks for the value, what says "hidden" to a screen reader, and
  // the live region the value is put into. Null for every other
  // cell, and for a sensitive cell without a value, which is empty.
  secretOf(cell) {
    const button = cell.querySelector(REVEAL)
    if (!button) return null
    const within = button.parentElement
    return {
      button,
      mask: within.querySelector(MASK),
      masked: within.querySelector(MASKED),
      value: within.querySelector(SECRET)
    }
  },

  // Whether a cell shows its value now: a patch brings it back as
  // the server renders it, with its mask.
  shows(cell) {
    const secret = cell.isConnected && this.secretOf(cell)
    return !!secret && secret.mask.hidden
  },

  // Asks the server for the value of a sensitive cell and shows it
  // in the cell, where a screen reader says it; on a cell that
  // shows its value, hides it again. The value is shown only while
  // the person is still at the cell when the answer comes.
  reveal(cell) {
    const secret = this.secretOf(cell)
    if (!secret) return
    if (this.revealed && this.revealed.cell === cell) return this.hide()
    this.hide()
    if (this.revealing) return
    this.revealing = true
    const payload = {row: this.rowKey(cell), column: this.columnOf(cell)}
    this.transport.push("reveal", payload).then(reply => {
      this.revealing = false
      // a patch may have brought the cell anew meanwhile
      const now = cell.isConnected && this.secretOf(cell)
      if (!now) return
      if (!reply || !reply.ok) {
        // the record is gone: the cell is marked here, as it is
        // when the picker cannot be opened for it
        if (reply && reply.error) {
          this.fail(cell, reply.error, () => {
            const message = document.getElementById(`${cell.id}-error`)
            if (message) message.remove()
          })
        }
        return
      }
      if (!cell.contains(document.activeElement) || (this.editing && this.editing.cell === cell)) return
      now.value.textContent = reply.value
      now.mask.hidden = true
      now.masked.hidden = true
      now.button.textContent = now.button.dataset.hide
      now.button.setAttribute("aria-label", now.button.dataset.hideLabel)
      this.revealed = {cell}
    })
  },

  // Takes the value that is shown out of its cell again.
  hide() {
    const shown = this.revealed
    if (!shown) return
    this.revealed = null
    const secret = shown.cell.isConnected && this.secretOf(shown.cell)
    if (!secret) return
    secret.value.textContent = ""
    secret.mask.hidden = false
    secret.masked.hidden = false
    secret.button.textContent = secret.button.dataset.show
    secret.button.setAttribute("aria-label", secret.button.dataset.showLabel)
  },

  // Marks a cell with a message, as the server marks one whose save
  // or whose action failed. `restore` puts the cell back as it was.
  fail(cell, message, restore) {
    const template = document.getElementById(`${this.id}-failure`)
    const error = template.content.firstElementChild.cloneNode(true)
    error.id = `${cell.id}-error`
    error.textContent = message
    if (!this.marked.has(cell)) this.marked.set(cell, restore)
    const stale = document.getElementById(error.id)
    if (stale) stale.remove()
    cell.append(error)
    cell.setAttribute("aria-invalid", "true")
    cell.setAttribute("aria-describedby", error.id)
    this.showMessage()
  },

  // Gives up the edit of a failed cell: the server puts the row back
  // with the value the record has.
  discard(cell) {
    const restore = this.marked.get(cell)
    if (restore) {
      this.marked.delete(cell)
      const error = document.getElementById(`${cell.id}-error`)
      if (error && is(cell, ACTIONS)) error.remove()
      cell.removeAttribute("aria-invalid")
      cell.removeAttribute("aria-describedby")
      delete cell.dataset.value
      delete cell.dataset.saved
      restore()
      this.showMessage()
    } else if (is(cell, ACTIONS)) {
      // the message of a row action that failed is given up
      this.transport.push("dismiss", {row: this.rowKey(cell)})
    } else {
      this.transport.push("discard", {row: this.rowKey(cell), column: this.columnOf(cell)})
    }
  },
}
