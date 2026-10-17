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
  // shown in it (see `placeOf`).
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
    // in the page, the question's place: the table's own, or its place
    // inside the panel or picker over the page that asks (`placeOf`)
    const shown = dialog && (inline(dialog) ? this.placeOf(dialog, from) : dialog)
    const text = shown && shown.querySelector(`[id^="${CSS.escape(this.id)}-dialog-question"]`)
    const confirm = shown && shown.querySelector("button[value='confirm']")
    if (!shown || !text || !confirm || (!inline(dialog) && typeof dialog.showModal !== "function")) {
      if (this.transport.debug()) console.error(`ash_data_table: the grid ${this.el.id} has no question dialog (a <dialog> with the id ${this.id}-dialog, ${this.id}-dialog-question in it and a button value="confirm"; inside a panel or picker over the page that asks, ${this.id}-dialog-in-panel or -in-picker): nothing runs of what it would ask "${question}"`)
      return Promise.resolve(false)
    }
    text.textContent = question
    // the answer that deletes says so (`data-destructive`), which
    // its look follows
    confirm.toggleAttribute(ATTRIBUTE(DESTRUCTIVE), !!destructive)
    return inline(dialog) ? this.askInline(shown) : this.askModal(dialog)
  },

  // Where a question in the page is asked: in the table's own place, or,
  // asked from a panel or a picker that is open over the page (or from
  // what is drawn inside one), whose page under it is inert, in the place
  // the server draws for it inside that panel or picker
  // (`ID-dialog-in-panel`, `ID-dialog-in-picker`).
  // Which one asks is `from`, else the dialog that is open over the page
  // now (`:modal`). Null where that one has no such place.
  placeOf(dialog, from) {
    const over = overPage(from) || document.querySelector(":modal")
    if (!over || over.contains(dialog)) return dialog
    const place = over.querySelector(`[id^="${CSS.escape(this.id)}-dialog-in-"][data-presentation]`)
    return place && place.id.slice(this.id.length).match(/^-dialog-in-(panel|picker)$/) ? place : null
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
  // question or nowhere. Nothing else is inert, and Tab leaves it. A
  // panel or picker that goes while it asks in it answers it as Cancel
  // (`goneWith`).
  askInline(shown) {
    const opener = document.activeElement && document.activeElement !== document.body ? document.activeElement : null
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
      const answer = value => {
        if (this.answer === answer) this.answer = null
        this.asked = null
        shown.removeEventListener("click", onClick)
        shown.removeEventListener("keydown", onKeydown)
        const back = value !== GIVEN_UP && (shown.contains(document.activeElement) || document.activeElement === document.body)
        shown.hidden = true
        if (back && opener && opener.isConnected) opener.focus({preventScroll: true})
        resolve(value)
      }
      this.answer = answer
      this.asked = shown
      shown.addEventListener("click", onClick)
      shown.addEventListener("keydown", onKeydown)
      shown.hidden = false
      toSafe(shown)
    })
  },

  // A panel or picker went (`el`, its hook's element): the question it
  // asks in it, if one is open, is answered as Cancel.
  goneWith(el) {
    if (this.answer && this.asked && el.contains(this.asked)) this.answer(false)
  },
}
