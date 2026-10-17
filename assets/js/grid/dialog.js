// The grid's hook: the dialog.
//
// These methods are part of the one hook object that grid/index.js
// puts together, and share its state through `this`.

import {DESTRUCTIVE, OPENED} from "../markers.js"
import {ATTRIBUTE, GIVEN_UP} from "./shared.js"

// Whether the table's question is drawn in the page, not over it.
const inline = dialog => dialog.dataset.presentation === "inline"

// What is open over the page (a modal panel or picker) around `from`:
// itself, or the one it is drawn in.
const overPage = from => {
  let opened = from && from.closest(OPENED)
  while (opened && opened.getAttribute("data-presentation") !== "modal") {
    opened = opened.parentElement && opened.parentElement.closest(OPENED)
  }
  return opened
}

// Focus on the safe answer, Cancel; else on the first answer there is.
const toSafe = shown => {
  const safe = shown.querySelector("button[value='cancel']") || shown.querySelector("button[value]")
  if (safe) safe.focus()
}

export default {
  // Asks a question in the table's dialog and resolves to whether it
  // was confirmed: true, false, or `GIVEN_UP` when nobody answered it
  // (another question took its place, or what it was about changed:
  // `giveUp`). Escape closes the dialog as Cancel does. When it is
  // answered, focus goes back where it was: the browser does it for a
  // modal dialog, and `askInline` for a question in the page; a
  // question given up leaves focus where it is, and so do its callers.
  //
  // One question at a time per table: a question asked while another
  // is open gives the first up, and what the first was about does not
  // run.
  //
  // `from` is the panel or picker that asks, when one does: a question
  // in the page asked from inside one that is open over the page is
  // shown in it (see `askInline`).
  //
  // A table without its dialog (`ID-dialog`: a `<dialog>`, or one in
  // the page, `data-presentation="inline"`), its question
  // (`ID-dialog-question`) or its Confirm, which a kit may have left
  // out, is not confirmed: what would be asked about does not run. The
  // development check names the dialog, and so does this while the
  // client debug is on.
  ask(question, destructive, from) {
    this.giveUp()
    const dialog = document.getElementById(`${this.id}-dialog`)
    const text = document.getElementById(`${this.id}-dialog-question`)
    const confirm = dialog && dialog.querySelector("button[value='confirm']")
    if (!dialog || !text || !confirm || (!inline(dialog) && typeof dialog.showModal !== "function")) {
      if (this.transport.debug()) console.error(`ash_data_table: the grid ${this.el.id} has no question dialog (a <dialog> with the id ${this.id}-dialog, ${this.id}-dialog-question in it and a button value="confirm"): nothing runs of what it would ask "${question}"`)
      return Promise.resolve(false)
    }
    text.textContent = question
    // the answer that deletes says so (`data-destructive`), which
    // its look follows
    confirm.toggleAttribute(ATTRIBUTE(DESTRUCTIVE), !!destructive)
    return inline(dialog) ? this.askInline(dialog, from) : this.askModal(dialog)
  },

  // Gives up the question that is open, if one is: it resolves to
  // `GIVEN_UP`, and what it was about does not run.
  giveUp() {
    if (this.answer) this.answer(GIVEN_UP)
  },

  // The question over the page: the page is inert while it is open, the
  // browser keeps focus in it and puts it back when it closes.
  askModal(dialog) {
    dialog.returnValue = ""
    return new Promise(resolve => {
      const onClose = () => {
        // the close of a question given up, heard after the next
        // question opened the dialog again
        if (dialog.open) return
        settle(dialog.returnValue === "confirm")
      }
      const settle = value => {
        dialog.removeEventListener("close", onClose)
        if (this.answer === answer) this.answer = null
        resolve(value)
      }
      const answer = value => {
        settle(value)
        if (dialog.open) dialog.close()
      }
      this.answer = answer
      dialog.addEventListener("close", onClose)
      dialog.showModal()
      toSafe(dialog)
    })
  },

  // The question in the page (stage 7b): shown, focus on Cancel, the
  // safe answer; a button answers, Escape inside it is Cancel; then it
  // is hidden and focus goes back to what had it, if focus is in the
  // question or nowhere. Nothing else is inert, and Tab leaves it.
  //
  // Asked from a panel or a picker that is open over the page (modal),
  // or from what is drawn inside one, the page under it is inert: the
  // question is shown inside that panel or picker, as a copy with ids of
  // its own (`-in`), which goes again when it is answered. A patch that
  // takes the copy away, or the panel or picker it is in, answers it as
  // Cancel does. Which one asks is `from`, else the dialog that is open
  // over the page now (`:modal`).
  askInline(dialog, from) {
    const opener = document.activeElement && document.activeElement !== document.body ? document.activeElement : null
    const over = overPage(from) || document.querySelector(":modal")
    const modal = over && !over.contains(dialog) ? over : null
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
      // the copy, or the panel or picker it is in, taken away by a patch
      const gone = new MutationObserver(() => { if (!shown.isConnected) answer(false) })
      const answer = value => {
        if (this.answer === answer) this.answer = null
        gone.disconnect()
        shown.removeEventListener("click", onClick)
        shown.removeEventListener("keydown", onKeydown)
        const back = value !== GIVEN_UP && (shown.contains(document.activeElement) || document.activeElement === document.body)
        if (modal) shown.remove()
        else shown.hidden = true
        if (back && opener && opener.isConnected) opener.focus({preventScroll: true})
        resolve(value)
      }
      this.answer = answer
      shown.addEventListener("click", onClick)
      shown.addEventListener("keydown", onKeydown)
      if (modal) gone.observe(document.body, {childList: true, subtree: true})
      shown.hidden = false
      toSafe(shown)
    })
  },
}
