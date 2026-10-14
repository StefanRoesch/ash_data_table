// The grid's hook: the values of an array.
//
// These methods are part of the one hook object that grid/index.js
// puts together, and share its state through `this`.

import {PRINTABLE, SELECT_KEYS, TEXT, SAME, TYPED} from "./shared.js"

export default {
  // A list editor (`[data-list]`), in a cell or in the action
  // panel: its rows, one per value, each with the control that
  // holds the value. The panel's hook uses these too.
  items(list) { return Array.from(list.querySelectorAll("[data-item]")) },

  controlIn(item) { return item.querySelector("textarea,input:not([type=hidden])") },

  valueIn(item) {
    const control = this.controlIn(item)
    return control.type === "checkbox" ? String(control.checked) : control.value
  },

  values(list) { return this.items(list).map(item => this.valueIn(item)) },

  // Adds a row for a value after the others, and returns its control.
  addValue(list, value) {
    const item = list.querySelector("template").content.firstElementChild.cloneNode(true)
    const control = this.controlIn(item)
    if (control.type === "checkbox") control.checked = value === "true"
    else control.value = value
    list.querySelector("[data-add]").before(item)
    this.hold(item)
    this.number(list)
    this.recountIn(item)
    if (control.tagName === "TEXTAREA" && list.closest("td")) this.fit(control)
    return control
  },

  // Takes a row away. Focus goes to the value after it, else to the
  // one before it, else to the button that adds one.
  removeValue(list, item) {
    const items = this.items(list)
    const at = items.indexOf(item)
    const next = items[at + 1] || items[at - 1]
    item.remove()
    this.number(list)
    ;(next ? this.controlIn(next) : list.querySelector("[data-add]")).focus()
  },

  fill(list, values) {
    for (const item of this.items(list)) item.remove()
    for (const value of values) this.addValue(list, value)
  },

  // Marks the controls of the values at `places`, counted from 0,
  // as the ones an action refused, and no others.
  markValues(list, places) {
    this.items(list).forEach((item, index) => {
      const control = this.controlIn(item)
      if (places.includes(index)) control.setAttribute("aria-invalid", "true")
      else control.removeAttribute("aria-invalid")
    })
  },

  // A box sends nothing while it is not ticked: in the panel, what
  // it holds is sent by the input beside it.
  hold(item) {
    const held = item.querySelector("input[type=hidden]")
    if (held) held.value = this.valueIn(item)
  },

  // What the controls of a row are called says the row's place.
  number(list) {
    this.items(list).forEach((item, index) => {
      const place = String(index + 1)
      this.controlIn(item).setAttribute("aria-label", list.dataset.valueLabel.replace("{n}", place))
      // the counter of a text is named by the row's place, too
      const counter = item.querySelector("[data-count]")
      if (counter && list.id) {
        counter.id = `${list.id}-count-${place}`
        this.controlIn(item).setAttribute("aria-describedby", counter.id)
      }
      item.querySelector("[data-remove]").setAttribute("aria-label", list.dataset.removeLabel.replace("{n}", place))
    })
  },

  // The editor of a column's component. What the table does for it
  // follows from its control, as it knows nothing else about it.
  //
  // A control that text is typed into (text, a number) behaves as
  // the built-in editors of text and numbers do: typing on the
  // cell replaces the value. Any other control (a slider, a menu,
  // a date) keeps its value, as the built-in date does: a key
  // typed on the cell opens the editor and goes on to the control,
  // which does with it what it does.
  //
  // An editor that saves when its value changes (`commit` is
  // "change") is saved on the control's `change` event, and stays
  // open. As with the built-in menu, a change made by stepping
  // with the keys is not yet a choice: Enter or leaving saves it.
  startComponent(ed, key, current) {
    const {root, input} = ed
    this.showValue(ed)
    input.addEventListener("input", () => this.showValue(ed))
    if (ed.commit === "change") {
      input.addEventListener("change", () => this.onComponentChange(ed))
      input.addEventListener("pointerdown", () => { ed.lastKey = null })
    }
    // a click beside the control, in the editor, leaves the focus in it
    root.addEventListener("mousedown", e => { if (e.target !== input && !input.contains(e.target)) e.preventDefault() })
    input.focus()
    if (!input.matches(TYPED)) return key === null
    if (input.tagName === "TEXTAREA") {
      input.addEventListener("input", () => this.fit(input))
      this.fit(input)
    }
    if (key === null) { input.select(); return true }
    // typing replaces the value; the character itself is typed by the
    // browser. One a number does not take changes nothing.
    input.value = ""
    if (input.type === "number") {
      setTimeout(() => {
        if (this.editing === ed && input.value === "" && !input.validity.badInput) {
          input.value = current
          input.select()
        }
      }, 0)
    }
    return false
  },

  // What an editor shows of its control's value besides the control:
  // the number beside a slider. An element of the editor that is
  // marked `data-value-text` is kept at the control's value.
  showValue(ed) {
    for (const shown of ed.root.querySelectorAll("[data-value-text]")) {
      const text = shown.childNodes.length === 1 && shown.firstChild.nodeType === 3 ? shown.firstChild : null
      // the text node is changed where there is one: the observer
      // of the rows has nothing to do with it
      if (text) text.nodeValue = ed.input.value
      else shown.textContent = ed.input.value
    }
  },

  // A textarea as high as its text, up to eight lines or so.
  fit(input) {
    input.style.height = "auto"
    input.style.height = `${Math.min(input.scrollHeight, 160)}px`
  },

  // While a cell is edited the keys belong to its editor, the arrow
  // keys among them. The grid keeps two; Tab leaves the grid, which
  // saves.
  onEditorKeydown(e) {
    const ed = this.editing
    ed.lastKey = PRINTABLE(e) ? "ArrowDown" : e.key
    switch (e.key) {
      case "Escape":
        e.preventDefault()
        this.finish(ed, false, true)
        break
      case "Enter":
        // on the editor's "Clear" button Enter uses the button
        if (e.target === ed.clear) return
        // a new line in text
        if (ed.input.tagName === "TEXTAREA" && e.shiftKey) return
        if (ed.input.tagName === "SELECT") {
          // an open menu takes Enter as the choice, which saves; a
          // closed one has its value already
          setTimeout(() => this.finish(ed, true, true), 0)
          return
        }
        e.preventDefault()
        this.finish(ed, true, true)
        break
    }
  },

  // A choice saves when it is made: picked from the open menu, or
  // with the pointer. Moving through a closed menu with the keys
  // changes the value at every step, which is not yet a choice;
  // Enter or leaving the cell makes it one.
  onEditorChange(ed) {
    if (SELECT_KEYS.includes(ed.lastKey)) return
    this.finish(ed, true, true)
  },

  // The editor of a component that saves when its value changes: a
  // change made with the pointer, or by a key that is a choice, is
  // saved at once. The editor stays open.
  onComponentChange(ed) {
    if (SELECT_KEYS.includes(ed.lastKey)) return
    this.commit(ed)
  },

  // Saves what an open editor holds, after asking when the column
  // has a question, and leaves the editor open.
  commit(ed) {
    if (this.editing !== ed || ed.asking) return
    const {cell, input} = ed
    const value = input.value
    const old = ed.old
    if (value === old) return
    const send = () => {
      // what "unchanged" means from here on, unless the save fails
      ed.old = value
      ed.pending = true
      this.save(cell, value, old, () => cell.replaceChildren(...ed.saved), ed)
    }
    if (!ed.confirm) return send()
    ed.asking = true
    this.ask(ed.confirm).then(confirmed => {
      ed.asking = false
      if (this.editing !== ed) return
      // Cancel: back in the editor, with what was chosen
      if (confirmed) send()
      input.focus()
    })
  },

  // The server's answer to the save of an editor that is still
  // open. A patch has left its cell alone, and has been kept aside
  // (`beforeUpdate`). Saved: the editor stays as it is. Not saved:
  // the editor is closed, and the cell says what the server says
  // of it, as any cell whose save failed.
  committed(ed, value, old, reply) {
    const {cell} = ed
    cell.removeAttribute("aria-busy")
    ed.pending = false
    if (reply && reply.ok) return
    ed.old = old
    const focused = ed.root.contains(document.activeElement)
    this.detach(ed)
    this.released(cell, true)
    cell.replaceChildren(...ed.saved)
    // the record is gone: there is no row to send, so the cell is marked here
    if (reply && reply.error) this.mark(cell, value, old, reply.error, () => cell.replaceChildren(...ed.saved))
    if (this.tree().activeId === cell.id) cell.tabIndex = 0
    if (focused) cell.focus()
    this.showMessage()
  },

  onEditorBlur(ed) {
    // Leaving the window is not leaving the cell.
    if (!document.hasFocus()) return
    // Focus is on its way to somewhere else: nothing pulls it back.
    // The editor is taken out of the cell once focus has arrived,
    // as Tab goes on from where the editor stands. Unless it has
    // arrived in the editor itself: on the button beside the
    // control, or back on the control.
    setTimeout(() => {
      if (ed.root.contains(document.activeElement)) return
      this.finish(ed, true, false)
    }, 0)
  },

  // "Clear" in the editor of a sensitive cell: asks the server to
  // empty the cell, after the column's question if it has one.
  // What was typed is given up. The answer is a patch of the row,
  // as after a save: with the cell empty, or marked as failed.
  clearCell(ed) {
    if (this.editing !== ed || ed.asking) return
    const {cell} = ed
    const run = () => {
      const restore = () => cell.replaceChildren(...ed.saved)
      this.detach(ed)
      this.released(cell, true)
      restore()
      if (this.tree().activeId === cell.id) cell.tabIndex = 0
      cell.focus()
      cell.setAttribute("aria-busy", "true")
      const payload = {row: this.rowKey(cell), column: this.columnOf(cell)}
      this.transport.push("clear", payload).then(reply => {
        if (!cell.isConnected || !cell.hasAttribute("aria-busy")) return
        cell.removeAttribute("aria-busy")
        // the record is gone: there is no row to send, so the cell is marked here
        if (reply && reply.error) this.mark(cell, "", "", reply.error, restore)
      })
    }
    if (!ed.confirm) return run()
    ed.asking = true
    this.ask(ed.confirm).then(confirmed => {
      ed.asking = false
      if (this.editing !== ed) return
      // Cancel: back in the editor, with what was typed
      if (confirmed) run()
      else ed.input.focus()
    })
  },

  // What an editor holds: the value of its control, or the list of
  // the values of its controls.
  held(ed) { return ed.read ? ed.read() : ed.input.value },

  // Ends an edit: saves the value if it has changed, after asking
  // when the column has a question, or gives it up. `refocus` puts
  // focus on the cell, for Enter and Escape; after a blur it is left
  // where the person has put it.
  finish(ed, save, refocus) {
    if (this.editing !== ed || ed.asking) return
    if (!ed.cell.isConnected) { this.editing = null; return }
    if (save && !SAME(this.held(ed), ed.old) && ed.confirm) {
      ed.asking = true
      this.ask(ed.confirm).then(confirmed => {
        ed.asking = false
        if (this.editing !== ed) return
        // Cancel: back in the editor, with what was typed
        if (confirmed) this.close(ed, true, refocus)
        else ed.input.focus()
      })
    } else {
      this.close(ed, save, refocus)
    }
  },

  // The cell is no longer being edited: it says of itself what the
  // server last said of it, and patches reach it again. What it
  // shows is the caller's to put in.
  detach(ed) {
    const {cell} = ed
    for (const [name, value] of ed.attributes || []) {
      if (value === null) cell.removeAttribute(name)
      else cell.setAttribute(name, value)
    }
    this.editing = null
    cell.removeAttribute("phx-update")
  },

  // The editor of a cell is gone. Where its row was to go
  // meanwhile (`ash_data_table:leaving`), it goes now, unless something
  // was saved from the editor: the answer to that save says on the
  // cell that the record is no longer available, and the row
  // stays for it to be read, as after any such save.
  released(cell, saved) {
    if (!this.leaving.size || !cell.isConnected) return
    const row = this.rowKey(cell)
    if (!this.leaving.delete(row) || saved) return
    setTimeout(() => { if (this.el.isConnected) this.transport.push("left", {row}) }, 0)
  },

  close(ed, save, refocus) {
    const {cell, input} = ed
    const value = this.held(ed)
    // The cell as the server last sent it: as it was when the
    // editor opened, or as a patch of its row has brought it since.
    const restore = () => cell.replaceChildren(...ed.saved)
    // shows what was typed until the server has answered
    const text = ed.shown ? ed.shown() : (input.tagName === "SELECT" && input.selectedOptions[0] ? input.selectedOptions[0].textContent : value)
    this.detach(ed)
    const failed = cell.hasAttribute("aria-invalid")
    // what was typed into a sensitive cell is never shown: until
    // the server has answered, the cell shows what it showed
    const typed = () => ed.type === "secret" ? restore() : cell.replaceChildren(...this.textFor(cell, text))
    if (save && !SAME(value, ed.old)) {
      typed()
      this.save(cell, value, ed.old, restore)
      this.released(cell, true)
    } else if (ed.pending) {
      // a save of this editor is on its way still: its answer puts
      // the cell right, as the answer to any save does
      typed()
      this.released(cell, true)
    } else {
      // given up, or back at the value the record has: nothing is
      // saved, and a failed edit of the cell is given up with it
      restore()
      if (failed) this.discard(cell)
      this.released(cell, false)
    }
    // the cell is the grid's tab stop again, unless focus has gone to another cell
    if (this.tree().activeId === cell.id) cell.tabIndex = 0
    if (refocus) cell.focus()
  },

  // A boolean: toggled and saved at once.
  /** @this {any} */
  toggle(cell, template) {
    const value = this.valueOf(cell) === "true" ? "false" : "true"
    const old = cell.dataset.saved !== undefined ? cell.dataset.saved : this.valueOf(cell)
    const commit = () => {
      // back at the value the record has: the failed edit is given up
      if (cell.hasAttribute("aria-invalid") && value === old) return this.discard(cell)
      const saved = Array.from(cell.childNodes)
      const box = template.content.firstElementChild.cloneNode(true)
      box.checked = value === "true"
      cell.replaceChildren(box)
      this.save(cell, value, old, () => cell.replaceChildren(...saved))
    }
    if (!template.dataset.confirm) return commit()
    this.ask(template.dataset.confirm).then(confirmed => {
      if (confirmed) commit()
      cell.focus()
    })
  },

  // Sends the value. The answer is a patch of the row, which takes
  // `aria-busy` away with everything else this hook put into the
  // cell. Where no patch came, the cell is put back as it was: the
  // server refused the event, or the record is gone, and then the
  // cell is marked here.
  //
  // `ed` is the editor the value was saved from, when that editor
  // stays open: see `committed`.
  save(cell, value, old, restore, ed) {
    cell.setAttribute("aria-busy", "true")
    const payload = {row: this.rowKey(cell), column: this.columnOf(cell), value}
    this.transport.push("save", payload).then(reply => {
      if (!cell.isConnected) return
      if (ed && this.editing === ed) return this.committed(ed, value, old, reply)
      if (!cell.hasAttribute("aria-busy")) return
      cell.removeAttribute("aria-busy")
      if (reply && reply.error) this.mark(cell, value, old, reply.error, restore)
      else restore()
    })
  },

  // Marks a cell as failed the way the server does, for a record
  // that is gone.
  mark(cell, value, old, message, restore) {
    this.fail(cell, message, restore)
    // what was typed into a sensitive cell is not kept in the page
    const template = this.editorOf(cell)
    const secret = template && template.dataset.editor === "secret"
    cell.dataset.value = secret ? "" : TEXT(value)
    cell.dataset.saved = TEXT(old)
  },
}
