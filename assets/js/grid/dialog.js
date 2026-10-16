// The grid's hook: the dialog.
//
// These methods are part of the one hook object that grid/index.js
// puts together, and share its state through `this`.

import {DESTRUCTIVE, DIALOG, OPENED} from "../markers.js"
import {ATTRIBUTE} from "./shared.js"

// Whether the table's question is drawn in the page, not over it.
const inline = dialog => dialog.dataset.presentation === "inline"

export default {
  // Asks a question in the table's dialog and resolves to whether it
  // was confirmed. Escape closes the dialog as Cancel does. When it
  // closes, focus goes back where it was: the browser does it for a
  // modal dialog, and `askInline` for a question in the page.
  //
  // A table without its dialog (`ID-dialog`: a `<dialog>`, or one in
  // the page, `data-presentation="inline"`), which a kit may have left
  // out, is not confirmed: what would be asked about does not run. The
  // development check names the dialog, and so does this while the
  // client debug is on.
  ask(question, destructive) {
    const dialog = document.getElementById(`${this.id}-dialog`)
    if (!dialog || (!inline(dialog) && typeof dialog.showModal !== "function")) {
      if (this.transport.debug()) console.error(`ash_data_table: the grid ${this.el.id} has no question dialog (a <dialog> with the id ${this.id}-dialog): nothing runs of what it would ask "${question}"`)
      return Promise.resolve(false)
    }
    document.getElementById(`${this.id}-dialog-question`).textContent = question
    // the answer that deletes says so (`data-destructive`), which
    // its look follows
    const confirm = dialog.querySelector("button[value='confirm']")
    confirm.toggleAttribute(ATTRIBUTE(DESTRUCTIVE), !!destructive)
    if (inline(dialog)) return this.askInline(dialog)
    dialog.returnValue = ""
    return new Promise(resolve => {
      dialog.addEventListener("close", () => resolve(dialog.returnValue === "confirm"), {once: true})
      // focus goes to the dialog's first control: Cancel, the safe answer
      dialog.showModal()
    })
  },

  // The question in the page (stage 7b): shown, focus on its first
  // button (Cancel, the safe answer); a button answers, Escape inside it
  // is Cancel; then it is hidden and focus goes back to what had it, if
  // focus is in the question or nowhere. Nothing else is inert, and Tab
  // leaves it. One question at a time, as a modal one is: one asked while
  // another is still open gives the first up, as Cancel does.
  //
  // Asked from a panel or a picker that is open over the page (modal),
  // the page under it is inert: the question is shown inside that panel
  // or picker, as a copy with ids of its own (`-in`), which goes again
  // when it is answered. A patch that takes the copy away answers it as
  // Cancel does.
  askInline(dialog) {
    if (this.answer) this.answer(false)
    const opener = document.activeElement && document.activeElement !== document.body ? document.activeElement : null
    const over = opener && opener.closest(`${DIALOG}${OPENED}`)
    const modal = over && over.getAttribute("data-presentation") === "modal" && !over.contains(dialog) ? over : null
    let shown = dialog
    if (modal) {
      shown = /** @type {HTMLElement} */ (dialog.cloneNode(true))
      for (const node of [shown, ...shown.querySelectorAll("[id]")]) node.id = `${node.id}-in`
      shown.setAttribute("aria-labelledby", `${dialog.getAttribute("aria-labelledby")}-in`)
      modal.append(shown)
    }
    return new Promise(resolve => {
      const onClick = e => {
        const button = e.target.closest && e.target.closest("button[value]")
        if (!button) return
        e.preventDefault()
        answer(button.value === "confirm")
      }
      const onKeydown = e => {
        if (e.key !== "Escape" || e.defaultPrevented) return
        e.preventDefault()
        e.stopPropagation()
        answer(false)
      }
      const gone = new MutationObserver(() => { if (!shown.isConnected) answer(false) })
      const answer = yes => {
        this.answer = null
        gone.disconnect()
        shown.removeEventListener("click", onClick)
        shown.removeEventListener("keydown", onKeydown)
        const back = shown.contains(document.activeElement) || document.activeElement === document.body
        if (modal) shown.remove()
        else shown.hidden = true
        if (back && opener && opener.isConnected) opener.focus({preventScroll: true})
        resolve(yes)
      }
      this.answer = answer
      shown.addEventListener("click", onClick)
      shown.addEventListener("keydown", onKeydown)
      if (modal) gone.observe(modal, {childList: true, subtree: true})
      shown.hidden = false
      const first = shown.querySelector("button[value]")
      if (first) first.focus()
    })
  },
}
