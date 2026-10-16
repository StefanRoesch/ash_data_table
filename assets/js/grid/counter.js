// The grid's hook: the counter of a text.
//
// These methods are part of the one hook object that grid/index.js
// puts together, and share its state through `this`.

import {COUNT} from "../markers.js"
import {UNREADABLE, LENGTH} from "./shared.js"

export default {
  // Something was typed into a control: the counters it names as
  // its description are counted again.
  onCount(e) {
    const control = e.target
    if (!control || !control.getAttribute || control.value === undefined) return
    for (const id of (control.getAttribute("aria-describedby") || "").split(/\s+/)) {
      const counter = id && document.getElementById(id)
      if (counter && counter.dataset.count !== undefined) this.recount(counter, control)
    }
    // the editor may be higher now, and its counter another width
    this.placeCount()
  },

  // The counter of the text a cell's editor holds is a popover, as
  // the message of a failed cell is: shown under the cell, at its
  // end, for as long as the editor is open, without taking room
  // from the text or making the row higher. It goes with the
  // editor, which it is part of.
  placeCount() {
    const ed = this.editing
    const count = ed && ed.count
    if (!count || !count.isConnected || !count.showPopover) return
    if (!count.matches(":popover-open")) count.showPopover()
    const box = ed.cell.getBoundingClientRect()
    count.style.top = `${box.bottom + 2}px`
    count.style.left = `${Math.max(0, box.right - count.offsetWidth)}px`
  },

  // Writes how long the text of `control` is into its counter, and
  // whether that is more than the most it can be. Nothing is
  // written that is there already, so that whoever watches the
  // counter is not told of a change that is none.
  recount(counter, control) {
    const max = Number(counter.dataset.max)
    const length = LENGTH(control.value, counter.dataset)
    const text = `${length}/${max}`
    if (counter.textContent !== text) counter.textContent = text
    if (length > max === counter.hasAttribute("data-over")) return
    if (length > max) counter.setAttribute("data-over", "")
    else counter.removeAttribute("data-over")
  },

  // Counts every counter in an element again, from what its control
  // holds now: after a patch, and when an editor is filled in.
  recountIn(scope) {
    for (const counter of scope.querySelectorAll(`${COUNT}[id]`)) {
      const control = scope.querySelector(`[aria-describedby~="${counter.id}"]`)
      if (control && control.value !== undefined) this.recount(counter, control)
    }
  },

  // Enter in an input of this table's argument line: the line's form
  // is sent, with everything it holds. Not from a button, which
  // Enter uses, and not from the line of a table nested in this one.
  onArgumentKeydown(e) {
    if (e.key !== "Enter" || e.isComposing) return
    const control = e.target
    if (!control || !control.matches || !control.matches("input,select")) return
    const form = control.form
    if (!form || form.id !== `${this.id}-arguments`) return
    e.preventDefault()
    const unreadable = UNREADABLE(form)
    if (unreadable) unreadable.reportValidity()
    else form.requestSubmit()
  },
}
