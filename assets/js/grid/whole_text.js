// The grid's hook: the whole text of a cell.
//
// These methods are part of the one hook object that grid/index.js
// puts together, and share its state through `this`.

import {ACTIONS, EXPANDER, GRIDCELL, MASK, REVEAL, ROW, SECRET, SELECTOR, PARAGRAPH} from "../markers.js"
import {is, WHOLE_FOCUS, WHOLE_POINTER, WHOLE_LEAVE} from "./shared.js"

export default {
  // A cell shows one line of its text, or as many as its column
  // says (`data-lines`), and cuts off the rest. The whole text of
  // a cell that cuts some off is shown under the cell, in the
  // table's popover for it (`ID-whole`), while the cell has the
  // focus or the pointer has rested on it: after a moment, so
  // that going through cells shows nothing, and gone at once when
  // the focus moves on. Above the cell where there is no room
  // under it.
  //
  // The text is taken from the cell, here: the server sends
  // nothing for it, and so nothing that the cell does not show.
  // A sensitive cell has none, masked or shown; nor has a cell
  // that is being edited, whose editor holds the whole text, or
  // one whose save failed, which has its message there.
  //
  // It is for the eye: a screen reader reads the whole text in
  // the cell, and is told nothing of this (`aria-hidden`). It
  // never takes the focus. Escape takes it away and nothing else
  // (the focus stays, and the key does nothing more); the pointer
  // can go onto it, and it stays for as long as the pointer is on
  // it or on its cell; scrolling anything but itself takes it away.

  // What in a cell holds its text, when some of it is cut off:
  // the paragraph of a cell with several lines, else the cell.
  // Null for a cell that shows all it holds, and for one that has
  // no whole text to show.
  cutIn(cell) {
    if (!cell || !cell.isConnected || !is(cell, GRIDCELL) || this.spans(cell)) return null
    if (!this.record(cell)) return null
    if (is(cell, SELECTOR) || is(cell, EXPANDER) || is(cell, ACTIONS)) return null
    // never for a sensitive cell: neither its mask nor its value
    if (cell.querySelector(`${REVEAL},${MASK},${SECRET}`)) return null
    if (cell.hasAttribute("aria-invalid") || cell.hasAttribute("aria-busy")) return null
    if (this.editing && this.editing.cell === cell) return null
    const text = cell.querySelector(`:scope > ${PARAGRAPH}`) || cell
    const cut = text === cell ? cell.scrollWidth > cell.clientWidth : text.scrollHeight > text.clientHeight
    return cut ? text : null
  },

  // The text an element shows to the eye: not what is there for a
  // screen reader alone, and not what a control or a message says.
  seenIn(node) {
    let text = ""
    for (const child of node.childNodes) {
      if (child.nodeType === 3) text += child.nodeValue
      else if (child.nodeType === 1 && !child.matches("[popover],[hidden],.sr-only,button,input,select,textarea,template")) text += this.seenIn(child)
    }
    return text
  },

  // What a cell with several lines shows of a text that the hook
  // puts into it: the paragraph the server would render.
  textFor(cell, text) {
    if (cell.dataset.lines === undefined || text === "") return [document.createTextNode(text)]
    const paragraph = document.createElement("p")
    paragraph.textContent = text
    return [paragraph]
  },

  // The focus is on a cell (not in a control of it), or on none
  // of this grid.
  focusedWhole(cell) {
    clearTimeout(this.wholeTimers.focus)
    if (cell !== this.wholeOff) this.wholeOff = null
    if (this.whole && (this.whole.by === "focus" || cell) && this.whole.cell !== cell) this.hideWhole()
    if (!cell) return
    this.wholeTimers.focus = setTimeout(() => {
      if (document.activeElement === cell) this.showWhole(cell, "focus")
    }, WHOLE_FOCUS)
  },

  // The pointer is on a cell, or on none of this grid.
  pointedWhole(cell) {
    clearTimeout(this.wholeTimers.pointer)
    clearTimeout(this.wholeTimers.leave)
    if (cell && cell !== this.wholeOff) this.wholeOff = null
    const shown = this.whole
    if (shown && shown.by === "pointer" && shown.cell !== cell) {
      // on its way to the text, perhaps
      this.wholeTimers.leave = setTimeout(() => this.hideWhole(), WHOLE_LEAVE)
    }
    if (!cell || (shown && shown.cell === cell)) return
    this.wholeTimers.pointer = setTimeout(() => {
      if (this.pointed === cell) this.showWhole(cell, "pointer")
    }, WHOLE_POINTER)
  },

  // The pointer is on the text: it stays for as long, also when
  // the cell loses the focus by a click on the text.
  holdWhole() {
    clearTimeout(this.wholeTimers.leave)
    if (this.whole) this.whole.by = "pointer"
  },

  leaveWhole() {
    clearTimeout(this.wholeTimers.leave)
    if (!this.whole || this.pointed === this.whole.cell) return
    this.wholeTimers.leave = setTimeout(() => this.hideWhole(), WHOLE_LEAVE)
  },

  // Escape, wherever the focus is: the text goes, and the key
  // does nothing else. It does not come back for this cell until
  // the focus or the pointer has been somewhere else.
  onWholeKeydown(e) {
    if (e.key !== "Escape" || !this.whole) return
    e.preventDefault()
    e.stopPropagation()
    this.wholeOff = this.whole.cell
    this.hideWhole()
  },

  // Something scrolled, or the window is another size: the text
  // is no longer where its cell is. Not when it is the text
  // itself that scrolled.
  scrolledWhole(e) {
    if (!this.whole) return
    const whole = this.part("whole")
    if (e && whole && e.target === whole) return
    this.hideWhole()
  },

  showWhole(cell, by) {
    const whole = this.part("whole")
    if (!whole || !whole.showPopover || cell === this.wholeOff) return
    const within = this.cutIn(cell)
    const text = within ? this.seenIn(within) : ""
    if (text.trim() === "") return
    if (this.whole && this.whole.cell !== cell) this.hideWhole()
    clearTimeout(this.wholeTimers.leave)
    if (whole.textContent !== text) whole.textContent = text
    if (!whole.matches(":popover-open")) whole.showPopover()
    if (!this.whole) {
      whole.scrollTop = 0
      // the row of the cell is watched for as long: a live update
      // may bring another text
      const watch = new MutationObserver(() => this.freshWhole())
      watch.observe(cell.closest(ROW), {subtree: true, childList: true, characterData: true})
      this.whole = {cell, by, text, watch}
      document.addEventListener("keydown", this.onWholeKey, true)
    }
    this.whole.text = text
    this.placeWhole()
  },

  // Under the cell, at its start; above it where there is more
  // room; and within the window. As wide as its text asks, up to
  // what its style says, or up to the cell where that is wider.
  placeWhole() {
    const whole = this.part("whole")
    if (!this.whole || !whole) return
    const box = this.whole.cell.getBoundingClientRect()
    whole.style.maxWidth = ""
    if (box.width > parseFloat(getComputedStyle(whole).maxWidth)) whole.style.maxWidth = `${box.width}px`
    const height = whole.offsetHeight
    const below = window.innerHeight - box.bottom - 2
    const above = box.top - 2
    const top = height <= below || below >= above ? box.bottom + 2 : box.top - 2 - height
    const most = document.documentElement.clientWidth - whole.offsetWidth
    whole.style.top = `${Math.max(0, top)}px`
    whole.style.left = `${Math.max(0, Math.min(box.left, most))}px`
  },

  // After a patch: the cell is gone, or shows all of its text
  // now, and the text goes; or it holds another text, which is
  // shown in place of the old one.
  freshWhole() {
    const shown = this.whole
    if (!shown) return
    const within = this.cutIn(shown.cell)
    const text = within ? this.seenIn(within) : ""
    if (text.trim() === "") return this.hideWhole()
    if (text !== shown.text) this.showWhole(shown.cell, shown.by)
  },

  hideWhole() {
    const shown = this.whole
    if (!shown) return
    this.whole = null
    shown.watch.disconnect()
    document.removeEventListener("keydown", this.onWholeKey, true)
    const whole = this.part("whole")
    if (!whole) return
    if (whole.matches(":popover-open")) whole.hidePopover()
    whole.textContent = ""
  },

  // Nothing is shown, and nothing is on its way.
  quitWhole() {
    for (const timer of Object.values(this.wholeTimers || {})) clearTimeout(timer)
    this.hideWhole()
  }
}
