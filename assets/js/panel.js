// The action panel: open for as long as the server renders it. A
// modal dialog (`data-presentation="modal"`): focus moves into it and
// stays there. Inline (`"inline"`), a part of the page: focus moves
// into it as it opens, and Tab leaves it. Escape (inside it, inline)
// and Cancel ask the server to take it away; when it is gone, focus
// goes back to the control that opened it, and to the table when that
// control is gone too.

// The control of a form that holds something the browser cannot read
// as a value of its type: a number that is none, a date half typed.
// Such a control says it holds nothing (`value` is ""), and sent so
// it would be taken as empty. It is the one thing a form is held
// back for here: the browser says at the control what is wrong.
// Everything else a control says of its value (the least and the
// most a number can be) describes, and is the action's to judge:
// the forms are `novalidate`.
const UNREADABLE = form =>
  Array.from(form.elements).find(control => control.validity && control.validity.badInput)

import {ADD, CANCEL, CONTROL, COUNT, DESTRUCTIVE, FIELD, GRID, ITEM, LIST, OF, OPENED, REMOVE, REMOVE_GROUP, SELECTION, VALUE_TEXT} from "./markers.js"

// The field of an array that is given value by value (`LIST`): its rows,
// one per value (`ITEM`), each with the control that holds the value.
const items = list => Array.from(list.querySelectorAll(ITEM))
const controlIn = item => item.querySelector("textarea,input:not([type=hidden])")
const valueIn = item => {
  const control = controlIn(item)
  return control.type === "checkbox" ? String(control.checked) : control.value
}

// A box sends nothing while it is not ticked: what it holds is sent by the
// input beside it.
const hold = item => {
  const held = item.querySelector("input[type=hidden]")
  if (held) held.value = valueIn(item)
}

// What the controls of a row are called says the row's place, and so does
// the id of the counter of a text, which its control names.
const number = list => {
  items(list).forEach((item, index) => {
    const place = String(index + 1)
    controlIn(item).setAttribute("aria-label", list.dataset.valueLabel.replace("{n}", place))
    const counter = item.querySelector(COUNT)
    if (counter && list.id) {
      counter.id = `${list.id}-count-${place}`
      controlIn(item).setAttribute("aria-describedby", counter.id)
    }
    item.querySelector(REMOVE).setAttribute("aria-label", list.dataset.removeLabel.replace("{n}", place))
  })
}

// Adds a row for a value after the others, from the list's template, and
// returns its control.
const addValue = list => {
  const item = list.querySelector("template").content.firstElementChild.cloneNode(true)
  list.querySelector(ADD).before(item)
  hold(item)
  number(list)
  return controlIn(item)
}

// Takes a row away. Focus goes to the value after it, else to the one
// before it, else to the button that adds one.
const removeValue = (list, item) => {
  const all = items(list)
  const at = all.indexOf(item)
  const next = all[at + 1] || all[at - 1]
  item.remove()
  number(list)
  ;(next ? controlIn(next) : list.querySelector(ADD)).focus()
}

// Marks the controls of the values at `places`, counted from 0, as the
// ones the action refused, and no others.
const markValues = (list, places) => {
  items(list).forEach((item, index) => {
    const control = controlIn(item)
    if (places.includes(index)) control.setAttribute("aria-invalid", "true")
    else control.removeAttribute("aria-invalid")
  })
}

// What takes the focus as a panel or a picker opens in the page, as
// the browser finds it in a modal dialog: its first control.
export const FOCUSABLE = ":is(input:not([type=hidden]),select,textarea,button,a[href],[tabindex]):not([tabindex='-1'],[hidden],[disabled])"

// Opens what the server has put into the page, as it says
// (`data-presentation`): a modal dialog over the page, or a part of
// the page, which focus moves into. Escape inside it is Cancel, as
// it is in a modal dialog, unless what has the focus took it.
//
// `own` keeps to the events of `el` itself, where something else that
// opens is drawn inside it. `until` is the hook's: its listeners go with it.
export function opened(el, cancel, until, own = handle => handle) {
  if (el.dataset.presentation === "inline") {
    el.addEventListener("keydown", own(e => {
      if (e.key !== "Escape" || e.defaultPrevented) return
      e.preventDefault()
      cancel()
    }), until)
    const first = Array.from(el.querySelectorAll(FOCUSABLE)).find(control => control.getClientRects().length > 0)
    if (first) first.focus()
  } else {
    // (open already where the hook is mounted on it again)
    if (el.showModal && !el.open) el.showModal()
    // Escape: the dialog stays until the server has taken it away
    el.addEventListener("cancel", e => { e.preventDefault(); cancel() }, until)
  }
}

export default {
  mounted() {
    const dialog = this.el
    // every listener of the hook goes with it (`destroyed`)
    this.ending = new AbortController()
    const until = {signal: this.ending.signal}
    const grid = document.querySelector(`${GRID}[${OF}="${CSS.escape(dialog.getAttribute(OF))}"]`)
    this.grid = grid && grid._ashDataTable
    // the control that opened the panel has the focus still
    const active = document.activeElement
    this.opener = active && active !== document.body ? active : null
    this.openerId = this.opener && this.opener.id
    this.confirmed = false
    // A picker that a field opened may be drawn inside the panel (a
    // modal panel, an inline picker): what happens in it is the
    // picker's, not the panel's.
    const own = handle => e => { if (e.target.closest && e.target.closest(OPENED) === dialog) handle(e) }
    opened(dialog, () => this.cancel(), until, own)
    // Focus is on the first control of the panel. Where that is the
    // button that takes a group away, it goes on to the group's first
    // field: Enter there is not to remove what the person came to edit.
    if (document.activeElement && document.activeElement.matches(REMOVE_GROUP)) this.into(dialog.id)
    dialog.addEventListener("click", own(e => { if (e.target.closest(CANCEL)) this.cancel() }), until)
    // What the editor of a column's component shows of its control's
    // value besides the control (the number beside a slider) follows
    // the control here, as it does in a cell, without waiting for
    // the server.
    dialog.addEventListener("input", own(e => {
      const field = e.target.closest && e.target.closest(FIELD)
      if (!field || !e.target.matches(CONTROL)) return
      for (const shown of field.querySelectorAll(VALUE_TEXT)) shown.textContent = e.target.value
    }), until)
    // The field of an array that is given value by value: its rows
    // are added and taken away here. The server is told as it is of
    // anything typed into a field, by the entry the field sends before
    // its values.
    this.mark()
    const changed = list => {
      const own = list.parentElement.querySelector("input[data-own]")
      if (own) own.dispatchEvent(new Event("input", {bubbles: true}))
    }
    dialog.addEventListener("click", own(e => {
      const list = e.target.closest && e.target.closest(LIST)
      if (!list) return
      if (e.target.closest(ADD)) addValue(list).focus()
      else if (e.target.closest(REMOVE)) removeValue(list, e.target.closest(ITEM))
      else return
      changed(list)
    }), until)
    // a box of such a field: what it holds is sent by the input beside it
    dialog.addEventListener("change", own(e => {
      const item = e.target.closest && e.target.closest(`${LIST} ${ITEM}`)
      if (!item || e.target.type !== "checkbox") return
      hold(item)
      changed(item.closest(LIST))
    }), until)
    // The buttons of a field made of groups (an embedded resource, a
    // map, an array of either), of one that holds several related
    // records, and of a sensitive one that can be emptied, send their
    // events themselves (`phx-click`). The server says where focus goes
    // then: into the group that was added, to what stands where the one
    // that is gone stood, back to the button.
    this.transport.on("ash_data_table:focus", ({table, cell}) => {
      if (table !== dialog.getAttribute(OF)) return
      const target = document.getElementById(cell)
      if (target && dialog.contains(target)) this.into(cell)
    })
    // The panel of a cell asks the column's question only when
    // something was changed: what its form holds as it opens is
    // what the record has.
    this.initial = dialog.dataset.ask === "changed" ? this.snapshot() : null
    // An action with a question asks it when "Run" is used, in the
    // table's other dialog, on top of this one. Cancel there comes
    // back here, with everything as it was typed.
    dialog.addEventListener("submit", own(e => {
      // what the browser cannot read is not sent as "nothing"
      const unreadable = UNREADABLE(e.target)
      if (unreadable) {
        e.preventDefault()
        e.stopPropagation()
        unreadable.reportValidity()
        return
      }
      const question = dialog.dataset.question
      const same = this.initial !== null && this.snapshot() === this.initial
      if (!question || this.confirmed || same) { this.confirmed = false; return }
      e.preventDefault()
      e.stopPropagation()
      // without the grid there is no one to ask: nothing runs that would
      // be asked about, as the grid's own question does without its dialog
      if (!this.grid) {
        if (this.transport.debug()) console.error(`ash_data_table: the panel ${dialog.id} finds no grid of its table (an element with the grid's hook and data-table="${dialog.getAttribute(OF)}"): nothing runs of what it would ask "${question}"`)
        return
      }
      const submitter = e.submitter
      this.grid.ask(question, dialog.matches(DESTRUCTIVE), dialog).then(confirmed => {
        if (confirmed !== true || !dialog.isConnected) return
        this.confirmed = true
        e.target.requestSubmit(submitter)
      })
    }), {capture: true, signal: this.ending.signal})
  },

  cancel() { this.transport.push("panel_cancel", {}) },

  // What the form holds, as it would be sent.
  snapshot() {
    const form = this.el.querySelector("form")
    // @ts-expect-error: a FormData is what URLSearchParams takes; TypeScript's DOM types say otherwise
    return form ? new URLSearchParams(new FormData(form)).toString() : ""
  },

  // Into the element of that id: to the first field in it, else to
  // its first button, or to the element itself when it is a control.
  into(id) {
    const element = id && document.getElementById(id)
    if (!element) return
    const shown = control => control.type !== "hidden" && !control.hidden
    const control = element.matches("button,input,select,textarea")
      ? element
      : (Array.from(element.querySelectorAll("input,select,textarea")).find(shown) ||
         Array.from(element.querySelectorAll("button")).find(shown))
    if (control) control.focus()
  },

  // The server says which values of an array the action refuses, on
  // the group around the field's rows; the rows are this hook's, so
  // their controls are marked here, after every answer.
  //
  // A counter of a text comes as the server counted it, from what
  // it had heard by then: it is counted again from what its
  // control holds now.
  updated() {
    this.mark()
    if (this.grid) this.grid.recountIn(this.el)
  },

  mark() {
    for (const list of this.el.querySelectorAll(LIST)) {
      let places = []
      try { places = JSON.parse(list.parentElement.dataset.invalid || "[]") } catch (_error) { /* none */ }
      markValues(list, places)
    }
  },

  // Once the patch is done, and only while focus is nowhere: the
  // server may have sent it somewhere itself (to a new row), and the
  // table may have put it back where a patch took it away (`repair`
  // of the grid's hook). Else to the control that opened the panel; to
  // the table's first stop where that was a button of the line above
  // it, which went with the selection; else where focus was in the
  // table, if that went.
  destroyed() {
    this.ending.abort()
    // a question it asked in it is answered as Cancel
    if (this.grid) this.grid.goneWith(this.el)
    setTimeout(() => {
      const active = document.activeElement
      const opener = this.opener && this.opener.isConnected
        ? this.opener
        : (this.openerId ? document.getElementById(this.openerId) : null)
      if (active && active !== document.body) return
      if (opener && opener.getClientRects().length > 0) opener.focus({preventScroll: true})
      else if (this.grid && this.grid.el.isConnected && opener && opener.closest(SELECTION)) this.grid.toFirstStop()
      else if (this.grid && this.grid.el.isConnected) this.grid.repair()
    })
  }
}
