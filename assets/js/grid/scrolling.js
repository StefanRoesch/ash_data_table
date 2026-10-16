// The grid's hook: scrolling sideways.
//
// These methods are part of the one hook object that grid/index.js
// puts together, and share its state through `this`.

import {GRIDCELL, ROW, ROWGROUP} from "../markers.js"
import {PLACE, BAR, SEEN} from "./shared.js"

export default {
  // Every table scrolls sideways in its own area, which is this
  // element: the table on a page, a nested table, the table of a
  // picker. The browser does the scrolling. What this hook adds is
  // in a style sheet of its own, as the widths are, so that no
  // patch takes it away and nothing is written to the page:
  //
  //   * how wide the area is (`--ash-data-table-view`): the cell of a
  //     nested table holds an element that is that wide and stays
  //     at the left edge of this area (the server renders it), so
  //     a nested table is as wide as what is seen of the table
  //     around it, at every depth, and does not move when that
  //     table scrolls;
  //   * what stays in view while the table scrolls, in a table
  //     that says `sticky_label? true` (its header says which
  //     column the label's is, `data-label`; without that nothing
  //     stays): the cells that select and expand a row, and the
  //     label column, each at the place it has when the cells
  //     before it that stay are at the left edge. The label column
  //     stays where it stands among the columns: a column before
  //     it scrolls away under it. Nothing stays where it would
  //     take more than half of what is seen. These cells have the
  //     ground of the table (`--ash-data-table-ground`, else the
  //     theme's) so that nothing shows through, and the last of
  //     them an edge while something is under them.
  //
  // A cell that the keyboard moves focus to is brought into view in
  // this area, beside the cells that stay and not under them, and
  // above the scrollbar at the bottom edge (`intoView`). The browser
  // brings a focused cell into view by itself, and knows of neither.
  //
  // A grid whose own scrollbar is below the window has it once
  // more at the bottom edge of the window, `ID-scrollbar`: see
  // `PLACE`, `barWanted` and `placeBar`. The two are kept
  // together here.

  // After every patch, and when the grid or the table in it is
  // another size.
  measure() {
    const table = this.table()
    if (table !== this.sized) {
      if (this.sized) this.measured.unobserve(this.sized)
      if (table) this.measured.observe(table)
      this.sized = table
    }
    // what cuts the grid off at the bottom, besides the window:
    // whatever around it scrolls or clips
    this.clips = []
    for (let node = this.el.parentElement; node && node !== document.body && node !== document.documentElement; node = node.parentElement) {
      if (getComputedStyle(node).overflowY !== "visible") this.clips.push(node)
    }
    // what a host keeps free at the bottom of the window
    this.inset = parseFloat(getComputedStyle(this.el).getPropertyValue("--ash-data-table-bottom")) || 0
    this.repin()
    PLACE()
  },

  // The header cells that stay in view, left to right, each with
  // where it stays; and how wide they are together.
  /** @returns {[Array<any>, number]} */
  stays() {
    const heads = this.headCells()
    const label = heads.find(th => th.dataset.label !== undefined)
    if (!label) return [[], 0]
    const pins = []
    let left = 0
    for (const th of heads.slice(0, this.lead()).concat([label])) {
      pins.push([th, left])
      left += th.getBoundingClientRect().width
    }
    return left <= this.el.clientWidth / 2 ? [pins, left] : [[], 0]
  },

  // Writes the rules, when they would be others than before.
  repin() {
    const table = this.table()
    if (!table) return
    const view = this.el.clientWidth
    const [pins, width] = this.stays()
    this.kept = width
    this.scrolled = this.el.scrollLeft > 0
    const says = [view, width, this.scrolled].concat(pins.map(([th, left]) => `${th.id}:${th.getAttribute("aria-colindex")}:${left}`)).join()
    if (says === this.pinned) return
    this.pinned = says
    const at = `#${CSS.escape(table.id)}`
    // the cells of the column: in the header and the filter row, and
    // of the records and their lines (not a cell that spans the grid)
    const body = place => `${at}>${ROWGROUP}>${ROW}>${GRIDCELL}[aria-colindex="${place}"]:not([colspan])`
    const cells = th => {
      const place = th.getAttribute("aria-colindex")
      const head = ["head-row", "filter-row"].map(row => `#${CSS.escape(`${this.id}-${row}`)}>[aria-colindex="${place}"]`)
      return `${head.join(",")},${body(place)}`
    }
    let css = `#${CSS.escape(this.el.id)}{--ash-data-table-view:${view}px}`
    if (pins.length > 0) {
      for (const [th, left] of pins) {
        css += `${cells(th)}{position:sticky;left:${left}px;z-index:1;background-color:var(--ash-data-table-ground,var(--ash-data-table-default-ground,Canvas))}`
      }
      const last = cells(pins[pins.length - 1][0])
      const line = "color-mix(in oklab,var(--ash-data-table-line,var(--ash-data-table-default-line,CanvasText)) 20%,transparent)"
      if (this.scrolled) {
        css += `${last}{box-shadow:inset -1px 0 0 0 ${line}}`
        // A cell that stays is not seen through while it is
        // dimmed: its text is, as far as the cell would be.
        const dimmed = pins.map(([th]) => body(th.getAttribute("aria-colindex")))
          .map(cell => `${cell}[aria-busy],${cell.replace(at, `${at}[aria-busy]`)}`)
        css += `${dimmed.join(",")}{opacity:1;color:color-mix(in oklab,currentColor 70%,transparent)}`
      }
      // forced colours take the shadow away: there the edge is a border
      css += `@media (forced-colors:active){${last}{border-inline-end:1px solid CanvasText}}`
    }
    if (!this.pins) {
      this.pins = new CSSStyleSheet()
      document.adoptedStyleSheets = [...document.adoptedStyleSheets, this.pins]
    }
    this.pins.replaceSync(css)
  },

  // Brings a cell that the keyboard has moved focus to into view,
  // as far as the browser has not: sideways in this grid, out
  // from under the cells that stay and to this side of the grid's
  // end; and up, when it is at the bottom edge of the window, where
  // a scrollbar may lie over it. Not a cell that stays, which is in
  // view, nor sideways one that spans the table.
  intoView(cell) {
    const el = this.el
    if (!this.spans(cell) && getComputedStyle(cell).position !== "sticky") {
      const start = el.getBoundingClientRect().left + el.clientLeft
      const from = start + (this.kept || 0)
      const to = start + el.clientWidth
      const box = cell.getBoundingClientRect()
      // by whole pixels, and rather one too many: a browser may
      // scroll to whole pixels only
      if (box.left < from) el.scrollLeft = Math.floor(el.scrollLeft - (from - box.left))
      else if (box.right > to) el.scrollLeft = Math.ceil(el.scrollLeft + Math.min(box.right - to, box.left - from))
    }
    const box = cell.getBoundingClientRect()
    const over = Math.min(box.bottom - (this.bottomEdge() - this.barHeight()), box.top)
    if (over <= 0) return
    const scroller = this.clips.find(node => node.scrollHeight > node.clientHeight + 1 && /auto|scroll/.test(getComputedStyle(node).overflowY))
    if (scroller) scroller.scrollTop += over
    else window.scrollBy(0, over)
  },

  // How high the scrollbar at the bottom edge is: as the grid's own.
  barHeight() { return (this.el.offsetHeight - this.el.clientHeight) || BAR },

  unpin() {
    this.measured && this.measured.disconnect()
    this.el.removeEventListener("scroll", this.onSideways)
    if (this.bar) this.bar.removeEventListener("scroll", this.onBar)
    if (this.pins) document.adoptedStyleSheets = document.adoptedStyleSheets.filter(sheet => sheet !== this.pins)
    this.pins = null
    // another grid's scrollbar may take the place of this one's
    PLACE()
  },

  // The grid was scrolled sideways: its scrollbar at the bottom
  // edge of the window goes with it.
  sideways() {
    if (this.bar && !this.bar.hidden) this.toBar()
    if (this.el.scrollLeft > 0 !== this.scrolled) this.repin()
  },

  // Puts the scrollbar at the bottom edge where the grid is, and
  // notes where that is (`barAt`): the bar says that it was
  // scrolled whoever scrolled it, and when it is shown, and when
  // it is another size.
  toBar() {
    const bar = this.bar
    if (Math.abs(bar.scrollLeft - this.el.scrollLeft) > 0.5) bar.scrollLeft = this.el.scrollLeft
    this.barAt = bar.scrollLeft
  },

  // And the other way round, when it was a person who moved the
  // bar: it is somewhere else than this hook has put it. Neither
  // is written what it holds already, so the two do not go on
  // telling each other.
  fromBar() {
    const bar = this.bar
    if (bar.hidden) return
    const at = bar.scrollLeft
    if (Math.abs(at - this.barAt) <= 0.5) return
    this.barAt = at
    if (Math.abs(this.el.scrollLeft - at) > 0.5) this.el.scrollLeft = at
  },

  // Where what is seen of the page ends at the bottom, for this
  // grid: the bottom edge of the window, or of what cuts the grid
  // off before that, less what the host keeps free there
  // (`--ash-data-table-bottom`).
  bottomEdge() {
    let edge = document.documentElement.clientHeight
    for (const node of this.clips) {
      if (!node.isConnected) continue
      edge = Math.min(edge, node.getBoundingClientRect().top + node.clientTop + node.clientHeight)
    }
    return edge - this.inset
  },

  // Whether this grid would have its scrollbar at the bottom edge,
  // and where: it has something to scroll, its own scrollbar is
  // below the edge, and enough of it is seen above the edge.
  barWanted() {
    const el = this.el
    if (!this.bar || !el.isConnected || el.scrollWidth - el.clientWidth < 1) return null
    const box = el.getBoundingClientRect()
    if (!box.width || !box.height) return null
    const edge = this.bottomEdge()
    if (box.bottom <= edge || box.top + SEEN > edge) return null
    const height = this.barHeight()
    return {left: box.left + el.clientLeft, top: edge - height, width: el.clientWidth, height, scroll: el.scrollWidth}
  },

  // Shows the scrollbar at the bottom edge where `want` says, or
  // hides it.
  placeBar(want) {
    const bar = this.bar
    if (!bar || !bar.isConnected) return
    if (!want) {
      if (!bar.hidden) bar.hidden = true
      return
    }
    const style = `left:${want.left}px;top:${want.top}px;width:${want.width}px;height:${want.height}px`
    if (bar.getAttribute("style") !== style) bar.setAttribute("style", style)
    const inner = bar.firstElementChild
    if (inner && inner.style.width !== `${want.scroll}px`) inner.style.width = `${want.scroll}px`
    if (bar.hidden) bar.hidden = false
    this.toBar()
  },
}
