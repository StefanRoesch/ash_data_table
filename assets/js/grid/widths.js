// The grid's hook: the widths of the columns.
//
// These methods are part of the one hook object that grid/index.js
// puts together, and share its state through `this`.

import {filterRow as filterRowId, head as headId, headRow as headRowId} from "../ids.js"
import {HANDLE, HEADER, ROW, ROWGROUP, WIDTH} from "../markers.js"
import {DATACELL, cellsOf} from "./shared.js"

// The narrowest and the widest a column can be made, in pixels: the
// width fields' `min` and `max`, as the server renders them
// (`AshDataTable.Attrs.least_width/0`, `most_width/0`;
// test/attrs_test.exs compares them).
const LEAST = 48
const MOST = 1000
const clamp = width => Math.round(Math.min(MOST, Math.max(LEAST, width)))

export default {
  // A person changes how wide a column is with the handle at the end
  // of its header, dragged with the pointer (a double click on it makes
  // the column as wide again as it was), or in the list of "Columns":
  // a width field per column (`data-width`, the id of its header), a
  // number in pixels the browser's own keys change, and "Reset widths"
  // (`data-reset-widths`), which makes every column as wide again as it
  // was. The handle is no Tab stop.
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
  // what the width fields hold, as the list opens and as a width
  // changes.

  // The cells of the header row, left to right.
  headCells() { return cellsOf(document.getElementById(headRowId(this.id))) },

  // A rule's selector of the cells under a column, which stands at
  // `place` (`aria-colindex`): of the records and the lines under
  // them, and of the footer row of the summaries. Not a cell that
  // spans the grid, and not a cell of a grid nested in it.
  under(table, place) {
    const at = `#${CSS.escape(table.id)}`
    const cell = `:is(${DATACELL})[aria-colindex="${place}"]:not([colspan])`
    return `:is(${at}>${ROWGROUP}>${ROW}>${cell},#${CSS.escape(`${this.id}-summaries`)}>${cell})`
  },

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
    const table = this.table()
    if (!table || !document.getElementById(headId(this.id))) return
    const heads = this.headCells()
    this.styled = this.headed(heads)
    if (!this.widths && this.hidden.size === 0) {
      if (this.sheet) this.sheet.replaceSync("")
      return
    }
    const at = `#${CSS.escape(table.id)}`
    const filters = cellsOf(document.getElementById(filterRowId(this.id)))
    let css = this.widths ? `${at}{width:auto;min-width:0;max-width:none}` : ""
    for (const th of heads) {
      const gone = this.hidden.has(th.id)
      const entry = this.widths && this.widths.get(th.id)
      if (!gone && !entry) continue
      const place = th.getAttribute("aria-colindex")
      const head = `#${CSS.escape(th.id)}`
      // of the rows, and of the footer row of the summaries
      const cells = this.under(table, place)
      const below = filters[Number(place) - 1]
      const filter = below && below.id ? `#${CSS.escape(below.id)}` : null
      const all = [head, cells].concat(filter ? [filter] : [])
      if (gone) {
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

  // After every patch: when the header has another column than
  // before, or a column stands elsewhere (the boxes that select rows
  // came or went), the rules are written for the header as it is.
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
  },

  // Makes a column `width` wide, as far as it may be.
  setWidth(th, width) {
    if (!th || !this.freeze()) return
    const entry = this.widths.get(th.id)
    if (!entry) return
    entry.width = clamp(width)
    this.restyle()
    this.fitColumns()
    this.showWidths()
  },

  // Makes a column as wide again as it was before a person
  // changed any width.
  resetWidth(th) {
    const entry = this.widths && this.widths.get(th.id)
    if (!entry) return
    entry.width = entry.original
    this.restyle()
    this.fitColumns()
    this.showWidths()
  },

  // "Reset widths": every column as the browser lays it out again.
  resetWidths() {
    this.widths = null
    this.restyle()
    this.showWidths()
  },

  // Each width field of the list of "Columns" says how wide its column
  // is now, which the server does not know: as the list opens, and after
  // a width changed while it is open. Not the field a person is typing
  // into, nor that of a hidden column, which says what it said last.
  showWidths() {
    const list = this.part("columns")
    if (!list || !list.matches(":popover-open")) return
    for (const field of Array.from(list.querySelectorAll(WIDTH))) {
      const th = document.getElementById(field.dataset.width)
      if (!th || this.hidden.has(th.id) || field === document.activeElement) continue
      const width = th.getBoundingClientRect().width
      if (width && field.value !== String(clamp(width))) field.value = String(clamp(width))
    }
  },

  // A width field is changed: with the browser's keys or arrows at once,
  // as typed once the number is one a column can be (while typing "120",
  // "1" and "12" are none), and as it is left, as far as the column may
  // be, which the field then says.
  onWidthField(field, type) {
    const th = document.getElementById(field.dataset.width)
    const width = Number(field.value)
    if (!th || field.value === "" || !Number.isFinite(width)) return
    if (type === "input" && !field.validity.valid) return
    this.setWidth(th, width)
    if (type === "change") field.value = String(clamp(width))
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
    const th = handle.closest(HEADER)
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
}
