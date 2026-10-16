// The grid's hook: several values of a filter.
//
// These methods are part of the one hook object that grid/index.js
// puts together, and share its state through `this`.

import {CHOICES} from "../markers.js"

export default {
  // A filter for several of a column's values ("is any of") has a
  // button in its filter cell and a list of boxes that the button
  // opens (`choices/1`), built and placed as "Columns" and its list
  // are. The boxes belong to the filter row's form. A filter that
  // is typed applies on Enter and when its input is left, and not
  // while typing; so here: ticking a box changes nothing yet (the
  // form does not hear of it, see `mounted`), and what is ticked
  // applies when the list is closed, by Enter, by the button, or by
  // going on to something else. Escape closes the list and gives
  // up what was ticked and not applied, as it does in an input.
  //
  // `choosing` is the list that is open: {cell, button, list, was},
  // where `was` are the values that applied when it was opened.
  // While it is open no patch touches the list (`phx-update`), so
  // that what was ticked and has not been sent stays.
  choiceBoxes(list) { return Array.from(list.querySelectorAll("input[type=checkbox]")) },

  openChoices(button) {
    const cell = this.cellOf(button)
    const list = cell && cell.querySelector(CHOICES)
    if (!list || !list.showPopover) return
    this.closeChoices(true, false)
    const boxes = this.choiceBoxes(list)
    this.choosing = {cell, button, list, was: new Set(boxes.filter(box => box.checked).map(box => box.value))}
    list.setAttribute("phx-update", "ignore")
    list.showPopover()
    button.setAttribute("aria-expanded", "true")
    this.placeChoices()
    document.addEventListener("pointerdown", this.onOutsideChoices, true)
    if (boxes[0]) boxes[0].focus()
  },

  // Closes the list. `apply` sends what is ticked, when that is not
  // what applied before; without it the boxes are as they were.
  // `refocus` puts focus on the button.
  closeChoices(apply, refocus) {
    const now = this.choosing
    if (!now) return
    this.choosing = null
    document.removeEventListener("pointerdown", this.onOutsideChoices, true)
    const boxes = this.choiceBoxes(now.list)
    if (!apply) for (const box of boxes) box.checked = now.was.has(box.value)
    const ticked = boxes.filter(box => box.checked)
    const changed = ticked.length !== now.was.size || ticked.some(box => !now.was.has(box.value))
    now.list.removeAttribute("phx-update")
    if (now.list.isConnected && now.list.matches(":popover-open")) now.list.hidePopover()
    now.button.setAttribute("aria-expanded", "false")
    if (refocus && now.button.isConnected) now.button.focus()
    const form = boxes[0] && boxes[0].form
    if (apply && changed && form) form.requestSubmit()
  },

  // The list is shown under its button, and stays in the window.
  placeChoices() {
    const now = this.choosing
    if (!now || !now.button.isConnected) return
    const box = now.button.getBoundingClientRect()
    now.list.style.top = `${box.bottom + 2}px`
    now.list.style.left = `${Math.max(0, Math.min(box.left, window.innerWidth - now.list.offsetWidth - 8))}px`
  },

  // The keys of the button and of the boxes that are not left to
  // the browser (Space ticks a box, and Enter and Space use the
  // button) or to the filter cell (Tab goes through its controls).
  // Says whether the key was dealt with.
  onChoicesKeydown(e, control) {
    const now = this.choosing
    const button = control.dataset.choicesButton !== undefined
    const inList = !!now && now.list.contains(control)
    if (!button && !inList) return false
    const boxes = now ? this.choiceBoxes(now.list) : []
    switch (e.key) {
      case "Escape":
        if (!now) return false
        this.closeChoices(false, true)
        break
      case "Enter":
        if (!inList) return false
        this.closeChoices(true, true)
        break
      case "ArrowDown":
      case "ArrowUp": {
        if (!now) { if (e.key === "ArrowUp") return false; this.openChoices(control); break }
        const at = boxes.indexOf(control)
        const next = boxes[e.key === "ArrowDown" ? at + 1 : at - 1]
        if (next) next.focus()
        else if (inList && e.key === "ArrowUp") now.button.focus()
        break
      }
      default:
        return false
    }
    e.preventDefault()
    return true
  },
}
