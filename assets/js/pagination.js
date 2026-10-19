// Focus stays on the pagination control that was used. Previous and
// Next are patched where they are. A page number is not always: when
// the numbers around it change, the patch takes its button out and
// puts it back, and the browser drops the focus of an element that is
// moved, as it does of one that becomes disabled. So the control
// that had focus before a patch is given it back after the patch.
//
// When it cannot have it, because Next was used to reach the last
// page or Previous to reach the first, focus goes to the button of
// the page that is shown now and, in a table without page numbers, to
// the other of the two. When the pagination itself goes away, with a
// read that failed, focus goes to the grid.
import {GRID, OF, PAGER, PAGE_NOW} from "./markers.js"

export default {
  mounted() {
    // the table it is of
    this.table = this.el.getAttribute(OF)
    this.used = null
    this.hasFocus = false
    // the control that had focus last
    this.last = null
    // every listener of the hook goes with it (`destroyed`)
    this.ending = new AbortController()
    const until = {signal: this.ending.signal}
    this.el.addEventListener("focusin", e => { this.hasFocus = true; this.last = e.target.id }, until)
    // noted a moment later: a control that is taken out of the page
    // loses the focus as one that is left does, and `destroyed` has
    // to know that it had it
    this.el.addEventListener("focusout", () => {
      setTimeout(() => { this.hasFocus = this.el.contains(document.activeElement) })
    }, until)
  },

  // A patch that takes away what stands above the pagination ("No
  // records", when the rows are back) moves the pagination itself,
  // and by the time this is called the browser has dropped the focus
  // of what was moved. The control is then the one that had it last.
  beforeUpdate() {
    const active = document.activeElement
    this.used = this.el.contains(active) ? active.id : (this.hasFocus ? this.last : null)
  },

  updated() {
    if (!this.used) return
    const usable = control => control && this.el.contains(control) && !control.disabled
    const control = [
      document.getElementById(this.used),
      this.el.querySelector(PAGE_NOW),
      ...this.el.querySelectorAll("button")
    ].find(usable)
    this.used = null
    if (!control) return this.toGrid()
    if (control !== document.activeElement) control.focus({preventScroll: true})
  },

  // After the patch, once the grid has its tab stop again, and only
  // while focus is still nowhere.
  destroyed() {
    this.ending.abort()
    if (!this.hasFocus) return
    setTimeout(() => { if (document.activeElement === document.body) this.toGrid() })
  },

  // To the grid's tab stop; in a nested table, whose tab stop may be
  // anywhere in the tables around it, to the cell the controls are in.
  toGrid() {
    const cell = this.el.closest(PAGER) ||
      document.querySelector(`${GRID}[${OF}="${CSS.escape(this.table)}"] [tabindex="0"]`)
    if (cell) cell.focus({preventScroll: true})
  }
}
