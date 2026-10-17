// The grid's hook: editing.
//
// These methods are part of the one hook object that grid/index.js
// puts together, and share its state through `this`.

import {ADD, CLEAR, COUNT, EXPANDER, GRIDCELL, ITEM, REMOVE, ROWGROUP} from "../markers.js"
import {CONTROL_IN, LISTED, TYPED, is} from "./shared.js"

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
    this.quitWhole()
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
    // nor has a map cell, or a union: Enter and F2 open the side panel, typing does nothing
    if (type === "group" || type === "groups" || type === "union") {
      if (key === null) this.editInPanel(cell)
      return key === null
    }
    const root = template.content.firstElementChild.cloneNode(true)
    if (type === "choices" || type === "list") return this.startList(cell, template, root, key)
    const input = CONTROL_IN(root)
    const current = this.valueOf(cell)
    // whether a sensitive cell holds a value: it then has its mask
    const held = !!this.secretOf(cell)
    const saved = Array.from(cell.childNodes)
    // LiveView leaves an element marked like this alone, so a patch of
    // the row, after another cell's save, does not take the editor away.
    //
    // Owner-kept exception (final review R3, stage 7 note §15): LiveView
    // documents `phx-update="ignore"` as rendered by the server, not as
    // switched by a hook. The documented way, an empty container with
    // `phx-update="ignore"` and an id in every editable cell, would send
    // that element with every row (about 14 × 25 more ids on a page of
    // /tasks, some 12 % more on a page change against D3's 5 %), and the
    // cell's own content and the attributes the hook sets on it would
    // still be patched under the editor. Guarded by editing.spec.ts,
    // arrays.spec.ts, filter_values.spec.ts and live_updates.spec.ts.
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
      ed.count = root.querySelector(`${COUNT}[popover]`)
      this.recountIn(root)
      this.fit(input)
      input.focus()
      if (key === null) input.select()
      this.placeCount()
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

  // The editor of an array: several controls in one cell. For an
  // array of enum values, one box per value of the enum (multiple
  // choice); for any other array, one control per value with a
  // button that takes the value away, and a button that adds one.
  //
  // It is one editor all the same. Enter saves what all of its
  // controls hold and Escape gives all of it up, from wherever in
  // it the focus is; leaving it saves. Tab goes through its
  // controls, and from the last of them out of the grid, as it
  // does from a filter. Nothing is saved while a person is still
  // in it: a box that is ticked or a value that is taken away is a
  // step on the way to the list they want, which the action may
  // not accept half done.
  startList(cell, template, root, key) {
    const choices = template.dataset.editor === "choices"
    // an enum without values has nothing to tick
    if (!root.querySelector(`input,${ADD}`)) return key === null
    const current = LISTED(this.valueOf(cell))
    const saved = Array.from(cell.childNodes)
    // (the owner-kept exception of `startEdit`)
    cell.setAttribute("phx-update", "ignore")
    cell.replaceChildren(root)
    const boxes = () => Array.from(root.querySelectorAll("input[type=checkbox]"))
    // What a multiple choice holds that is none of its choices: a
    // value the record has and the enum no longer does. It has no
    // box, so a person can neither see nor change it here, and it
    // is sent with the ticked values, after them, as it is.
    let boxless = []
    const load = values => {
      if (!choices) return this.fill(root, values)
      const offered = boxes().map(box => box.value)
      for (const box of boxes()) box.checked = values.includes(box.value)
      boxless = values.filter(value => !offered.includes(value))
    }
    const read = () => choices
      ? boxes().filter(box => box.checked).map(box => box.value).concat(boxless)
      : this.values(root)
    // what the cell shows of a list until the server has answered:
    // the labels of the choices, and values as they were typed
    const shown = () => choices
      ? boxes().filter(box => box.checked).map(box => box.parentElement.textContent.trim()).concat(boxless).join(", ")
      : read().join(", ")
    // What "unchanged" means: the list the record has, as these
    // controls hold it. A failed cell shows what was typed instead.
    load(cell.dataset.saved !== undefined ? LISTED(cell.dataset.saved) : current)
    const old = read()
    load(current)
    // the values the action refused when this cell was saved last
    if (!choices && cell.dataset.invalid !== undefined) this.markValues(root, LISTED(cell.dataset.invalid))
    const ed = {cell, root, input: root, type: template.dataset.editor, saved, old, read, shown, list: true, confirm: template.dataset.confirm, lastKey: null}
    this.editing = ed
    cell.tabIndex = -1
    // the control the focus is in, or was in last: where it goes
    // back to when the column's question is answered with Cancel
    root.addEventListener("focusin", e => { ed.input = e.target })
    // Leaving the editor saves; going from one of its controls to
    // another is not leaving it.
    root.addEventListener("focusout", () => {
      if (!document.hasFocus()) return
      setTimeout(() => { if (!root.contains(document.activeElement)) this.finish(ed, true, false) }, 0)
    })
    // A click in the editor leaves the focus in it: on the box or
    // the button that was clicked, which not every browser gives
    // the focus by itself, and where it was for a click beside the
    // controls. A control that is typed into takes the click as it is.
    root.addEventListener("mousedown", e => {
      if (e.target.closest(TYPED) || e.target.closest("input:not([type=checkbox])")) return
      e.preventDefault()
      const label = e.target.closest("label")
      const control = e.target.closest("input,button") || (label && label.querySelector("input"))
      if (control) control.focus()
    })
    root.addEventListener("click", e => {
      if (e.target.closest(ADD)) this.addValue(root, "").focus()
      else if (e.target.closest(REMOVE)) this.removeValue(root, e.target.closest(ITEM))
    })
    root.addEventListener("input", e => {
      if (e.target.tagName === "TEXTAREA") this.fit(e.target)
      // a value that was refused is another value now
      e.target.removeAttribute("aria-invalid")
    })
    root.addEventListener("change", e => e.target.removeAttribute("aria-invalid"))
    const controls = Array.from(root.querySelectorAll("input,textarea"))
    // into the first value, or to the button that adds one when
    // there is none yet
    const first = controls[0] || root.querySelector(ADD)
    if (key === null) {
      first.focus()
      if (first.matches(TYPED)) first.select()
      return true
    }
    if (choices) {
      // a typed character goes to the first choice that starts with
      // it, as it does in a menu; nothing is ticked by that alone
      const letter = key.toLowerCase()
      const box = controls.find(box => box.parentElement.textContent.trim().toLowerCase().startsWith(letter))
      ;(box || first).focus()
      return true
    }
    // Typing on the cell starts a new value with what is typed: the
    // values the cell holds stay. The character itself is typed by
    // the browser. Only where a value is typed, though: on a list
    // of dates or of boxes a key opens the editor, as Enter does.
    const added = this.addValue(root, "")
    if (!added.matches(TYPED)) {
      added.closest(ITEM).remove()
      first.focus()
      return true
    }
    added.focus()
    if (added.type === "number") {
      // a character a number does not take adds nothing
      setTimeout(() => {
        if (this.editing === ed && added.isConnected && added.value === "" && !added.validity.badInput) {
          this.removeValue(root, added.closest(ITEM))
        }
      }, 0)
    }
    return false
  },

  // In the editor of an array the keys belong to its controls: the
  // arrow keys move in a text and step a number, Space ticks a box,
  // Enter on a button uses it. The grid keeps two, and among the
  // boxes of a multiple choice the arrow keys go from box to box.
  onListKeydown(e) {
    const ed = this.editing
    switch (e.key) {
      case "Escape":
        e.preventDefault()
        this.finish(ed, false, true)
        break
      case "Enter":
        if (e.target.tagName === "BUTTON") return
        // a new line in text
        if (e.target.tagName === "TEXTAREA" && e.shiftKey) return
        e.preventDefault()
        this.finish(ed, true, true)
        break
      case "ArrowDown":
      case "ArrowUp": {
        if (ed.type !== "choices") return
        const boxes = Array.from(ed.root.querySelectorAll("input[type=checkbox]"))
        const next = boxes[boxes.indexOf(e.target) + (e.key === "ArrowDown" ? 1 : -1)]
        if (next) next.focus()
        e.preventDefault()
        break
      }
    }
  },
}
