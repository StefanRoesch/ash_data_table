// The grid's hook: the widths of the columns.
//
// These methods are part of the one hook object that grid/index.js
// puts together, and share its state through `this`.

import {HANDLE} from "../markers.js"
import {STEP} from "./shared.js"

export default {
  // A person changes how wide a column is with the handle at the
  // end of its header: by dragging it, or with the arrow keys once
  // F2 on the header has put the focus on the handle. A double
  // click on the handle, or Enter, makes the column as wide again
  // as it was.
  //
  // Until a person does, the browser lays the table out: as wide
  // as the place it is in, every column as its content asks. At
  // the first change every column is given the width it has just
  // then, and the table is as wide as its columns from there on:
  // so that one column changes and no other does, and the handle
  // stays under the pointer. The width a column had at that
  // moment is the one it goes back to.
  //
  // The widths are rules of a style sheet that belongs to this
  // hook and is no part of the page: for a header by its id and
  // for the cells under it by where they stand (`aria-colindex`).
  // The server never hears of them and no patch takes them away,
  // whatever it brings: rows, another page, the header again.
  // They are gone with the hook: with the page, and with a nested
  // table that is closed. Nothing else is written to the page but
  // what a handle says of its column (`aria-valuenow`), which is
  // written again after every patch.

  // The cells of the header row, left to right.
  headCells() {
    const table = this.el.querySelector("table")
    return table && table.tHead && table.tHead.rows[0] ? Array.from(table.tHead.rows[0].cells) : []
  },

  // The handle of a column's header, if it has one: the columns of
  // the table have, the ones before and after them have not.
  handleOf(th) { return th.querySelector(`:scope > ${HANDLE}`) },

  // Gives every column the width it has now. Not while the table
  // cannot be seen and has no widths to take.
  freeze() {
    if (this.widths) return true
    const widths = new Map()
    for (const th of this.headCells()) {
      // a hidden column has no width to take: it is given one
      // when it is shown again (`fitColumns`)
      if (this.hidden.has(th.id)) continue
      const width = th.getBoundingClientRect().width
      if (!width) return false
      widths.set(th.id, {width, original: width})
    }
    this.widths = widths
    this.restyle()
    return true
  },

  // Writes the widths as rules. A column is as wide as its rule
  // says, whatever its cells hold: what does not fit is cut off,
  // in the header and in the filter as in the cells, and nothing
  // in them insists on a width of its own.
  //
  // And the hidden columns: the header, the filter and the cells
  // of one are not shown at all (`display: none`), which takes
  // them out of what a screen reader is told as well.
  restyle() {
    const table = this.el.querySelector("table")
    if (!table || !table.tHead) return
    const heads = this.headCells()
    this.styled = this.headed(heads)
    this.goneAt = new Set()
    if (!this.widths && this.hidden.size === 0) {
      if (this.sheet) this.sheet.replaceSync("")
      return
    }
    const at = `#${CSS.escape(table.id)}`
    const filters = table.tHead.rows[1]
    let css = this.widths ? `${at}{width:auto;min-width:0;max-width:none}` : ""
    for (const th of heads) {
      const gone = this.hidden.has(th.id)
      const entry = this.widths && this.widths.get(th.id)
      if (!gone && !entry) continue
      const place = th.getAttribute("aria-colindex")
      const head = `#${CSS.escape(th.id)}`
      // of the rows, and of the footer row of the summaries
      const cells = `${at}>:is(tbody,tfoot)>tr>td[aria-colindex="${place}"]:not([colspan])`
      const filter = filters && filters.cells[th.cellIndex] && filters.cells[th.cellIndex].id
        ? `#${CSS.escape(filters.cells[th.cellIndex].id)}`
        : null
      const all = [head, cells].concat(filter ? [filter] : [])
      if (gone) {
        this.goneAt.add(place)
        css += `${all.join(",")}{display:none}`
        continue
      }
      const above = [head].concat(filter ? [filter] : [])
      css += `${all.join(",")}{width:${entry.width}px;min-width:${entry.width}px;max-width:${entry.width}px}`
      css += `${above.join(",")}{overflow:hidden;text-overflow:ellipsis}`
      css += `${all.map(one => `${one}>*,${one} :is(input,select,textarea)`).join(",")}{min-width:0}`
    }
    if (!this.sheet) {
      this.sheet = new CSSStyleSheet()
      document.adoptedStyleSheets = [...document.adoptedStyleSheets, this.sheet]
    }
    this.sheet.replaceSync(css)
  },

  unstyle() {
    if (!this.sheet) return
    document.adoptedStyleSheets = document.adoptedStyleSheets.filter(sheet => sheet !== this.sheet)
    this.sheet = null
  },

  // which columns the header has, and where each stands
  headed(heads) { return heads.map(th => `${th.id}:${th.getAttribute("aria-colindex")}`).join() },

  // After every patch: each handle says how wide its column is
  // now, which the server does not know and does not render. And
  // when the header has another column than before, or a column
  // stands elsewhere (the boxes that select rows came or went),
  // the rules are written for the header as it is.
  fitColumns() {
    const heads = this.headCells()
    if (this.styled !== this.headed(heads)) this.restyle()
    if (this.widths) {
      // a column that has no width yet takes the one it has now:
      // one the server has added, or one that was hidden when the
      // others were given theirs
      let added = false
      for (const th of heads) {
        if (this.widths.has(th.id) || this.hidden.has(th.id)) continue
        const width = th.getBoundingClientRect().width
        if (width) { this.widths.set(th.id, {width, original: width}); added = true }
      }
      if (added) this.restyle()
    }
    for (const th of heads) {
      const handle = this.handleOf(th)
      // the handle of a hidden column says what it said last
      if (!handle || this.hidden.has(th.id)) continue
      const [least, most] = this.limits(handle)
      const now = String(Math.round(Math.min(most, Math.max(least, th.getBoundingClientRect().width))))
      if (handle.getAttribute("aria-valuenow") !== now) handle.setAttribute("aria-valuenow", now)
    }
  },

  // The narrowest and the widest a column can be made, which the
  // handle says.
  limits(handle) {
    return [Number(handle.getAttribute("aria-valuemin")), Number(handle.getAttribute("aria-valuemax"))]
  },

  // Makes a column `width` wide, as far as it may be.
  setWidth(th, width) {
    const handle = th && this.handleOf(th)
    if (!handle || !this.freeze()) return
    const entry = this.widths.get(th.id)
    if (!entry) return
    const [least, most] = this.limits(handle)
    entry.width = Math.round(Math.min(most, Math.max(least, width)))
    this.restyle()
    this.fitColumns()
  },

  // Makes a column as wide again as it was before a person
  // changed any width.
  resetWidth(th) {
    const entry = this.widths && this.widths.get(th.id)
    if (!entry) return
    entry.width = entry.original
    this.restyle()
    this.fitColumns()
  },

  // Where the end of a column is: to the right, or to the left
  // where text runs from right to left.
  forward(th) { return getComputedStyle(th).direction === "rtl" ? -1 : 1 },

  // The pointer goes down on a handle: the column follows it until
  // it goes up. The handle holds the pointer meanwhile, wherever on
  // the page it is; no text is selected, and what follows the
  // drag as a click is no click on the header.
  onResizeStart(e) {
    const handle = e.target.closest(HANDLE)
    if (!handle || e.button !== 0 || e.isPrimary === false) return
    e.preventDefault()
    const th = handle.parentElement
    if (!this.freeze()) return
    const drag = {id: th.id, x: e.clientX, width: th.getBoundingClientRect().width, forward: this.forward(th), moved: false}
    try { handle.setPointerCapture(e.pointerId) } catch (_error) { return }
    handle.setAttribute("data-dragging", "")
    const move = e => {
      if (e.clientX === drag.x && !drag.moved) return
      drag.moved = true
      this.setWidth(document.getElementById(drag.id), drag.width + drag.forward * (e.clientX - drag.x))
    }
    const end = () => {
      handle.removeEventListener("pointermove", move)
      handle.removeEventListener("pointerup", end)
      handle.removeEventListener("pointercancel", end)
      handle.removeEventListener("lostpointercapture", end)
      handle.removeAttribute("data-dragging")
      if (!drag.moved) return
      // The click that ends a drag goes to the handle, which
      // holds the pointer, and is dealt with there (`onClick`).
      // This is for a browser that sends it to what the pointer
      // was let go over instead.
      const swallow = e => { e.stopPropagation(); e.preventDefault() }
      window.addEventListener("click", swallow, {capture: true, once: true})
      setTimeout(() => window.removeEventListener("click", swallow, {capture: true}), 0)
    }
    handle.addEventListener("pointermove", move)
    handle.addEventListener("pointerup", end)
    handle.addEventListener("pointercancel", end)
    handle.addEventListener("lostpointercapture", end)
  },

  // The keys of a handle that has the focus. Right Arrow and Left
  // Arrow move the column's end a step; Home and End make the
  // column as narrow and as wide as it can be; Enter makes it as
  // wide again as it was; Escape goes back to the header. The
  // other keys that would move about the grid or scroll the page
  // do nothing here. Tab leaves the grid, as from a cell.
  onResizeKeydown(e, handle) {
    const th = handle.parentElement
    const [least, most] = this.limits(handle)
    const step = key => {
      if (!this.freeze()) return
      const forward = (key === "ArrowRight" ? 1 : -1) * this.forward(th)
      this.setWidth(th, this.widths.get(th.id).width + forward * STEP)
    }
    switch (e.key) {
      case "ArrowRight":
      case "ArrowLeft": step(e.key); break
      case "Home": this.setWidth(th, least); break
      case "End": this.setWidth(th, most); break
      case "Enter": this.resetWidth(th); break
      case "Escape": th.focus(); break
      case "ArrowUp":
      case "ArrowDown":
      case "PageUp":
      case "PageDown":
      case " ": break
      default: return
    }
    e.preventDefault()
  },
}
