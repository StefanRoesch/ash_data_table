// The grid's hook: the dialog.
//
// These methods are part of the one hook object that grid/index.js
// puts together, and share its state through `this`.

import {DESTRUCTIVE} from "../markers.js"
import {ATTRIBUTE} from "./shared.js"

export default {
  // Asks a question in the table's dialog and resolves to whether it
  // was confirmed. Escape closes the dialog as Cancel does. When it
  // closes, the browser puts focus back where it was.
  //
  // A table without its dialog (`ID-dialog`, a `<dialog>`), which a kit
  // may have left out, is not confirmed: what would be asked about does
  // not run. The development check names the dialog, and so does this
  // while the client debug is on.
  ask(question, destructive) {
    const dialog = document.getElementById(`${this.id}-dialog`)
    if (!dialog || typeof dialog.showModal !== "function") {
      if (this.transport.debug()) console.error(`ash_data_table: the grid ${this.el.id} has no question dialog (a <dialog> with the id ${this.id}-dialog): nothing runs of what it would ask "${question}"`)
      return Promise.resolve(false)
    }
    document.getElementById(`${this.id}-dialog-question`).textContent = question
    // the answer that deletes says so (`data-destructive`), which
    // its look follows
    const confirm = dialog.querySelector("button[value='confirm']")
    confirm.toggleAttribute(ATTRIBUTE(DESTRUCTIVE), !!destructive)
    dialog.returnValue = ""
    return new Promise(resolve => {
      dialog.addEventListener("close", () => resolve(dialog.returnValue === "confirm"), {once: true})
      // focus goes to the dialog's first control: Cancel, the safe answer
      dialog.showModal()
    })
  },
}
