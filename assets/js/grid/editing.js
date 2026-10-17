// The grid's hook: editing.
//
// These methods are part of the one hook object that grid/index.js
// puts together, and share its state through `this`.

import {CLEAR, EXPANDER, GRIDCELL, ROWGROUP} from "../markers.js"
import {CONTROL_IN, is} from "./shared.js"

export default {
  // A cell's ids hold what an event names: `ID-row-KEY` on the row's
  // row group, and `ID-row-KEY-c-COLUMN` on the cell.
  rowKey(cell) { return cell.closest(ROWGROUP).id.slice(this.id.length + 5) },
  columnOf(cell) { return cell.id.slice(cell.closest(ROWGROUP).id.length + 3) },

  editorOf(cell) { return document.getElementById(`${this.id}-editor-${this.columnOf(cell)}`) },

  // A data cell of an editable column that the server has not marked
  // as read-only for this person, and whose last save has been answered.
  canEdit(cell) {
    return is(cell, GRIDCELL) && !!this.record(cell) && !is(cell, EXPANDER) &&
      cell.getAttribute("aria-readonly") !== "true" && !cell.hasAttribute("aria-busy") &&
      !!this.editorOf(cell)
  },

  // What a cell's editor starts with: the text the cell shows, unless
  // the server says otherwise (a choice, a boolean, a failed cell).
  valueOf(cell) {
    return cell.dataset.value !== undefined ? cell.dataset.value : cell.textContent
  },

  // Opens the column's editor in the cell. `key` is the character
  // that was typed on the cell, or null for Enter, F2 and a double
  // click. Returns whether the key has been dealt with here; if not,
  // the browser goes on to type it into the editor, which has the
  // focus by then.
  startEdit(cell, key) {
    // a value that is shown is hidden before anything else is
    // put into its cell, or kept of it
    this.hide()
    // and the cell's whole text is not shown beside its editor
    this.quitWhole(cell)
    const template = this.editorOf(cell)
    const type = template.dataset.editor
    // a boolean has no edit mode: Enter and F2 toggle it, typing does nothing
    if (type === "boolean") {
      if (key === null) this.toggle(cell, template)
      return key === null
    }
    // nor has a reference cell: Enter and F2 open the picker, typing does nothing
    if (type === "reference") {
      if (key === null) this.pick(cell)
      return key === null
    }
    // nor has an array: Enter, F2 and a key typed on it open the side
    // panel, with the field of its values
    if (type === "choices" || type === "list") {
      this.editInPanel(cell)
      return true
    }
    // nor has a map cell, or a union: Enter and F2 open the side panel, typing does nothing
    if (type === "group" || type === "groups" || type === "union") {
      if (key === null) this.editInPanel(cell)
      return key === null
    }
    const root = template.content.firstElementChild.cloneNode(true)
    const input = CONTROL_IN(root)
    const current = this.valueOf(cell)
    // whether a sensitive cell holds a value: it then has its mask
    const held = !!this.secretOf(cell)
    const saved = Array.from(cell.childNodes)
    // LiveView leaves an element marked like this alone, so a patch of
    // the row, after another cell's save, does not take the editor away.
    //
    // Owner-kept exception (owner, 2026-10-17): LiveView
    // documents `phx-update="ignore"` as rendered by the server on a
    // container with an id, not as switched by a hook. It is switched here,
    // on the one cell whose single value is being edited, and nowhere else.
    // The documented way, an empty container with `phx-update="ignore"` and
    // an id in every editable cell, measured on /tasks with PERF_WIRE=1
    // (the demo's socket compresses): a page change 155,550 → 183,412 bytes
    // of payload (+18 %) and 11,796 → 13,901 on the wire (+18 %), against
    // the 5 % a page change may grow; a cell save 8,500 → 9,674 (+14 %),
    // 116 → 130 on the wire.
    // And the cell's own content and the attributes the hook sets on it
    // would still be patched under the editor. It relies on LiveView
    // 1.2.12 deciding "ignored" from the live element: re-check it on every
    // upgrade. Guarded by editing.spec.ts and live_updates.spec.ts.
    cell.setAttribute("phx-update", "ignore")
    cell.replaceChildren(root)
    // What "unchanged" means: the value the record has, as this
    // editor writes it. A failed cell shows what was typed instead.
    input.value = cell.dataset.saved !== undefined ? cell.dataset.saved : current
    const old = input.value
    input.value = current
    const ed = {cell, root, input, type, saved, old, confirm: template.dataset.confirm, commit: template.dataset.commit, lastKey: null}
    this.editing = ed
    cell.tabIndex = -1
    input.addEventListener("blur", () => this.onEditorBlur(ed))
    let handled = true
    if (type === "component") {
      handled = this.startComponent(ed, key, current)
    } else if (type === "enum") {
      input.addEventListener("change", () => this.onEditorChange(ed))
      input.addEventListener("pointerdown", () => { ed.lastKey = null })
      // a typed character goes to the first choice that starts with
      // it, as it would in the menu; nothing is saved by that alone
      if (key !== null) {
        const letter = key.toLowerCase()
        const option = Array.from(input.options).find(o => o.textContent.trim().toLowerCase().startsWith(letter))
        if (option) input.value = option.value
        ed.lastKey = "ArrowDown"
      }
      input.focus()
      try { input.showPicker() } catch (_error) { /* the closed menu works too */ }
    } else if (type === "secret") {
      // A sensitive cell: nothing of its value is in the page, so
      // the editor opens empty, and what is typed is typed into
      // it by the browser, hidden. Left empty it saves nothing.
      //
      // So the cell is emptied by a button beside the input, where
      // the column can be empty: "Clear". Tab goes from the input to
      // it and on out of the grid, Shift+Tab back; Enter and Space
      // use it. It is part of the editor: focus on it is focus in
      // the editor, and leaving it saves what was typed, as leaving
      // the input does. A cell that holds nothing has none.
      const clear = root.querySelector(CLEAR)
      if (clear && !held) clear.remove()
      else if (clear) {
        ed.clear = clear
        clear.addEventListener("blur", () => this.onEditorBlur(ed))
        clear.addEventListener("click", () => this.clearCell(ed))
        // a click on the button or beside the input leaves the focus where it is
        root.addEventListener("mousedown", e => { if (e.target !== input) e.preventDefault() })
      }
      input.focus()
      handled = key === null
    } else if (type === "text") {
      input.addEventListener("input", () => this.fit(input))
      // a text with a counter: a click on the counter leaves the
      // focus in the control
      if (root !== input) root.addEventListener("mousedown", e => { if (e.target !== input) e.preventDefault() })
      // typing replaces the text; the character itself is typed by the browser
      if (key !== null) { input.value = ""; handled = false }
      this.recountIn(root)
      this.fit(input)
      input.focus()
      if (key === null) input.select()
    } else if (type === "number") {
      input.focus()
      if (key === null) input.select()
      else {
        // Typing replaces the number, if the input takes the character.
        // One it does not take changes nothing: the number stays.
        input.value = ""
        handled = false
        setTimeout(() => {
          if (this.editing === ed && input.value === "" && !input.validity.badInput) {
            input.value = current
            input.select()
          }
        }, 0)
      }
    } else {
      // A date or a datetime keeps its value: a digit typed on the
      // cell goes into the first part of the input, any other
      // character the input ignores.
      input.focus()
      handled = key === null
    }
    return handled
  },

  // Asks for the picker of a reference cell: one event with the row
  // and the column. The server renders the picker, whose own hook
  // takes it from there; the cell is its opener, and has the focus
  // again when it is gone. Where the row's record is gone there is
  // nothing to open it for, and the cell is marked here.
  pick(cell) {
    if (this.picking) return
    this.picking = true
    const payload = {row: this.rowKey(cell), column: this.columnOf(cell)}
    this.transport.push("pick", payload).then(reply => {
      this.picking = false
      if (!reply || !reply.error || !cell.isConnected) return
      this.fail(cell, reply.error, () => {
        const message = document.getElementById(`${cell.id}-error`)
        if (message) message.remove()
      })
    })
  },

  // Asks for the side panel of a map cell: one event with the row
  // and the column. The server renders the panel, whose own hook
  // takes it from there. Where the row's record is gone there is
  // nothing to open it for, and the cell is marked here.
  editInPanel(cell) {
    if (this.picking) return
    this.picking = true
    const payload = {row: this.rowKey(cell), column: this.columnOf(cell)}
    this.transport.push("edit", payload).then(reply => {
      this.picking = false
      if (!reply || !reply.error || !cell.isConnected) return
      this.fail(cell, reply.error, () => {
        const message = document.getElementById(`${cell.id}-error`)
        if (message) message.remove()
      })
    })
  },
}
