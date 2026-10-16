// The grid's hook: the dialog.
//
// These methods are part of the one hook object that grid/index.js
// puts together, and share its state through `this`.

export default {
  // Asks a question in the table's dialog and resolves to whether it
  // was confirmed. Escape closes the dialog as Cancel does. When it
  // closes, the browser puts focus back where it was.
  ask(question, destructive) {
    const dialog = document.getElementById(`${this.id}-dialog`)
    if (!dialog || !dialog.showModal) return Promise.resolve(true)
    document.getElementById(`${this.id}-dialog-question`).textContent = question
    // the answer that deletes says so (`data-destructive`), which
    // its look follows
    const confirm = dialog.querySelector("button[value='confirm']")
    confirm.toggleAttribute("data-destructive", !!destructive)
    dialog.returnValue = ""
    return new Promise(resolve => {
      dialog.addEventListener("close", () => resolve(dialog.returnValue === "confirm"), {once: true})
      // focus goes to the dialog's first control: Cancel, the safe answer
      dialog.showModal()
    })
  },
}
