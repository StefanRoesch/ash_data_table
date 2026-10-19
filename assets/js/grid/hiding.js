// The grid's hook: hiding columns.
//
// These methods are part of the one hook object that grid/index.js
// puts together, and share its state through `this`.

import {RESET_WIDTHS, WIDTH} from "../markers.js"
import {is} from "./shared.js"

export default {
  // A person hides a column of the table, and shows it again, in
  // the list that "Columns" opens above the grid: a box for every
  // column that can be hidden. The server renders the button and
  // the list, with every box ticked, and knows nothing of what is
  // hidden: the column is read and rendered as before, and is
  // hidden here, by a rule of the style sheet that holds the
  // widths, written the same way (for the header by its id, for
  // the cells under it by where they stand). So no patch brings a
  // hidden column back, whatever it brings, and nothing is sent.
  // What is hidden is gone with the hook: with the page, and with
  // a nested table that is closed.
  //
  // A hidden column is still a column of the table: the cells keep
  // their place in the row and what they say of it
  // (`aria-colindex`, and `aria-colcount` on the table), as ARIA
  // has it for a table of which not every column is there to be
  // seen. They are not shown and not told to a screen reader, and
  // Tab passes over them, as the browser passes over what is not
  // shown. Focus is in the list of "Columns" as a column goes.
  //
  // What this hook writes outside its own style sheet: which
  // boxes are ticked, the text of the button, and what is read
  // out (see `columns/1` for what a patch does to them).

  // A patch may bring the list with another column or without
  // one, say of a column that the rows are filtered or sorted by
  // it now, or tick a box again, as the server renders every box:
  // the list is watched for all of that, from when it is there (a
  // table gets its list once it has two columns), and what this
  // hook knows is put back before the page is drawn.
  watchColumns() {
    const list = this.part("columns")
    if (!list || this.watched === list) return
    this.watched = list
    if (this.listed) this.listed.disconnect()
    this.listed = new MutationObserver(() => this.applyColumns())
    this.listed.observe(list, {
      subtree: true,
      childList: true,
      attributes: true,
      attributeFilter: ["data-filtered", "data-sorted", "checked", "disabled"]
    })
    // its width fields say the widths as it opens (see "the widths of
    // the columns")
    list.addEventListener("toggle", e => { if (e.newState === "open") this.showWidths() }, {signal: this.ending.signal})
    this.applyColumns()
  },

  // The boxes of the list, one per column that can be hidden.
  boxes() {
    const list = this.part("columns")
    return list ? Array.from(list.querySelectorAll("input[type=checkbox]")) : []
  },

  // What happens in the list of "Columns", which is outside this
  // element: a box that is used, a width field, "Reset widths". The
  // browser opens and closes the
  // list (a popover its button names, `popovertarget`), closes it on a
  // click elsewhere and on Escape, and says whether it is open; focus
  // that goes on to somewhere else closes it here. Those of a table
  // nested in this one are inside this table's element too, and are
  // that table's.
  onColumnsEvent(e) {
    const target = e.target
    const control = this.part("columns-control")
    if (!control || !target || !target.closest || !control.contains(target)) return
    if (e.type === "change" && target.dataset.head !== undefined) this.onColumnChange(target)
    if ((e.type === "input" || e.type === "change") && is(target, WIDTH)) this.onWidthField(target, e.type)
    if (e.type === "click" && target.closest(RESET_WIDTHS)) this.resetWidths()
    if (e.type === "focusout" && e.relatedTarget && !control.contains(e.relatedTarget)) {
      const list = this.part("columns")
      if (list && list.matches(":popover-open")) list.hidePopover()
    }
  },

  // A box of the list was used: its column is hidden, or shown
  // again, and that is read out.
  onColumnChange(box) {
    if (box.checked) this.hidden.delete(box.dataset.head)
    else this.hidden.add(box.dataset.head)
    this.applyColumns()
    const status = this.part("columns-status")
    if (status) status.textContent = this.hidden.has(box.dataset.head) ? box.dataset.sayHidden : box.dataset.sayShown
  },

  // What is hidden has changed, or may have: the list and the rules
  // follow.
  applyColumns() {
    this.paintColumns()
    this.restyle()
    this.fitColumns()
  },

  // Says in the list which columns are shown, and on the button
  // how many are hidden (in its name, and in its badge), and how
  // many of those the rows are filtered and sorted by: their filters are in the header row,
  // out of sight with them. After every change of what is hidden,
  // and of the list.
  //
  // Where one column has to stay (`data-keeps-one`), the box of
  // the last column that is shown cannot be used; and should the
  // server take the last one away, the first of the others is
  // shown again.
  paintColumns() {
    const list = this.part("columns")
    const button = this.part("columns-button")
    if (!list || !button) return
    const boxes = this.boxes()
    const keepsOne = list.dataset.keepsOne !== undefined
    const seen = () => boxes.filter(box => !this.hidden.has(box.dataset.head))
    if (keepsOne && boxes.length > 0 && seen().length === 0) this.hidden.delete(boxes[0].dataset.head)
    const last = keepsOne && seen().length === 1 ? seen()[0] : null
    const counts = {hidden: 0, filtered: 0, sorted: 0}
    for (const box of boxes) {
      const on = !this.hidden.has(box.dataset.head)
      // The attribute with the property: a patch ticks the box
      // again by writing the attribute, which is what the list
      // is watched for.
      if (box.checked !== on) box.checked = on
      if (box.hasAttribute("checked") !== on) box.toggleAttribute("checked", on)
      if (box.disabled !== (box === last)) box.disabled = box === last
      if (on) continue
      counts.hidden++
      if (box.dataset.filtered !== undefined) counts.filtered++
      if (box.dataset.sorted !== undefined) counts.sorted++
    }
    // each said for every number it can be (the server's plural forms):
    // the one for this number
    const said = (texts, count) => { try { return JSON.parse(texts)[count - 1] || "" } catch (_error) { return "" } }
    const {text, textWith, textHidden, textFiltered, textSorted} = button.dataset
    const details = [[counts.hidden, textHidden], [counts.filtered, textFiltered], [counts.sorted, textSorted]]
      .filter(([count]) => count > 0)
      .map(([count, texts]) => said(texts, count))
    const says = details.length > 0 ? textWith.replace("{details}", details.join(", ")) : text
    const shown = this.part("columns-text")
    if (shown && shown.textContent !== says) shown.textContent = says
    // the badge with how many are hidden: empty, and so out of sight,
    // while none is
    const count = this.part("columns-count")
    const number = counts.hidden > 0 ? String(counts.hidden) : ""
    if (count && count.textContent !== number) count.textContent = number
  },
}
