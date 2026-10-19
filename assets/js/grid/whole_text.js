// The grid's hook: the whole text of a cell.
//
// These methods are part of the one hook object that grid/index.js
// puts together, and share its state through `this`.

import {ACTIONS, EXPANDER, FAILED, MASK, REVEAL, SECRET, SELECTOR, PARAGRAPH, WHOLE} from "../markers.js"
import {ATTRIBUTE, DATACELL, is} from "./shared.js"

export default {
  // A cell shows one line of its text, or as many as its column
  // says (`data-lines`), and cuts off the rest. A cell that cuts some
  // off shows all of it in place, its row as high as it needs: the
  // hook puts a button into the cell (`WHOLE`) while the cell has the
  // pointer or the focus, and the button, or Shift+Enter on the cell,
  // shows the whole text and cuts it off again; so does Escape. The
  // root's rules do the rest, by the button's `aria-expanded`.
  //
  // Nothing of it is the server's, and nothing floats: the text is the
  // cell's own. A screen reader reads the whole text in the cell
  // whatever the eye is shown, so the button is for the eye
  // (`aria-hidden`), and no tab stop. A sensitive cell has no whole
  // text, masked or shown; nor has a cell that is being edited, whose
  // editor holds the whole text, or one whose save failed or is on
  // its way.
  //
  // A patch of a row brings its cells as the server renders them,
  // without the button: those that were expanded are expanded again
  // (`offerWhole`, after every patch), as far as they still cut text.

  // What in a cell holds its text, when some of it is cut off:
  // the paragraph of a cell with several lines, else the cell.
  // Null for a cell that shows all it holds, and for one that has
  // no whole text to show.
  cutIn(cell) {
    if (!cell || !cell.isConnected || !is(cell, DATACELL) || this.spans(cell)) return null
    if (!this.record(cell)) return null
    if (is(cell, SELECTOR) || is(cell, EXPANDER) || is(cell, ACTIONS)) return null
    // never for a sensitive cell: neither its mask nor its value
    if (cell.querySelector(`${REVEAL},${MASK},${SECRET}`)) return null
    if (is(cell, FAILED) || cell.hasAttribute("aria-busy")) return null
    if (this.editing && this.editing.cell === cell) return null
    const text = cell.querySelector(`:scope > ${PARAGRAPH}`) || cell
    const cut = text === cell ? cell.scrollWidth > cell.clientWidth : text.scrollHeight > text.clientHeight
    return cut ? text : null
  },

  // What a cell with several lines shows of a text that the hook
  // puts into it: the paragraph the server would render, with its
  // marker (`PARAGRAPH`), which the rules of the table's look cut off
  // after the column's lines and `cutIn` measures.
  textFor(cell, text) {
    if (cell.dataset.lines === undefined || text === "") return [document.createTextNode(text)]
    const paragraph = document.createElement("p")
    paragraph.setAttribute(ATTRIBUTE(PARAGRAPH), "")
    paragraph.textContent = text
    return [paragraph]
  },

  // The button of a cell, if it has one.
  wholeOf(cell) {
    return cell ? Array.from(cell.children).find(child => is(child, WHOLE)) || null : null
  },

  expandedIn(cell) {
    const button = this.wholeOf(cell)
    return !!button && button.getAttribute("aria-expanded") === "true"
  },

  // The pointer is on a cell, or on none of this grid.
  onPointer(cell) {
    if (cell === this.pointed) return
    this.pointed = cell
    this.offerWhole()
  },

  // The cells that are offered their whole text: the one that has the
  // pointer and the one that has the focus, where they cut some off,
  // and every one that shows it. The button goes from any other.
  offerWhole() {
    const focused = this.cellOf(document.activeElement)
    const offered = [this.pointed, focused].filter(cell => cell && this.owns(cell) && this.cutIn(cell))
    for (const button of Array.from(this.el.querySelectorAll(WHOLE))) {
      const cell = button.parentElement
      if (!this.owns(cell) || offered.includes(cell)) continue
      if (button.getAttribute("aria-expanded") !== "true") button.remove()
    }
    // expanded before a patch brought the cell again: first, so that the
    // cell is expanded again rather than offered
    for (const id of Array.from(this.expanded)) {
      const cell = document.getElementById(id)
      if (!cell || !this.owns(cell)) this.expanded.delete(id)
      else if (!this.wholeOf(cell) && this.cutIn(cell)) this.wholeButton(cell, true)
      else if (!this.wholeOf(cell)) this.expanded.delete(id)
    }
    for (const cell of offered) if (!this.wholeOf(cell)) this.wholeButton(cell, false)
  },

  // Puts the button into a cell, saying whether the whole text shows.
  wholeButton(cell, open) {
    const button = document.createElement("button")
    button.type = "button"
    button.tabIndex = -1
    button.setAttribute("aria-hidden", "true")
    cell.append(button)
    this.showWhole(cell, button, open)
    return button
  },

  // What the button says is its marker's value, which the root's rules
  // show (`content: attr(data-whole)`): no text of its own, so the cell's
  // text stays its own to whoever reads it.
  showWhole(cell, button, open) {
    button.setAttribute("aria-expanded", String(open))
    button.setAttribute(ATTRIBUTE(WHOLE), (open ? this.el.dataset.showLess : this.el.dataset.showWhole) || "")
    if (open) this.expanded.add(cell.id)
    else this.expanded.delete(cell.id)
  },

  // Shows the whole text of a cell, or cuts it off again: the button,
  // and Shift+Enter on the cell. Whether there was anything to do.
  toggleWhole(cell) {
    const button = this.wholeOf(cell) || (this.cutIn(cell) ? this.wholeButton(cell, false) : null)
    if (!button) return false
    this.showWhole(cell, button, button.getAttribute("aria-expanded") !== "true")
    return true
  },

  // Escape on a cell whose whole text shows: it is cut off again.
  // Whether there was one.
  lessWhole(cell) {
    if (!this.expandedIn(cell)) return false
    this.showWhole(cell, this.wholeOf(cell), false)
    return true
  },

  // Nothing is shown: before an editor is put into a cell, and when the
  // hook goes.
  quitWhole(cell) {
    const buttons = cell ? [this.wholeOf(cell)].filter(Boolean) : Array.from(this.el.querySelectorAll(WHOLE))
    for (const button of buttons) {
      if (cell || this.owns(button)) {
        this.expanded.delete(button.parentElement.id)
        button.remove()
      }
    }
  },

  // Whether all that changed in the grid was the button of a cell.
  ofWhole(record) {
    if (record.type !== "childList") return false
    const nodes = [...record.addedNodes, ...record.removedNodes]
    return nodes.length > 0 && nodes.every(node => node.nodeType === 1 && is(node, WHOLE))
  }
}
