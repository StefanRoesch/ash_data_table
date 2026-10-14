// The action panel: a modal dialog that is open for as long as the
// server renders it. Focus moves into it and stays there; Escape and
// Cancel ask the server to take it away; when it is gone, focus goes
// back to the control that opened it, and to the grid when that
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

export default {
  mounted() {
    const dialog = this.el
    const grid = document.getElementById(dialog.id.replace(/-panel$/, "-grid"))
    this.grid = grid && grid._ashDataTable
    // the control that opened the panel has the focus still
    const active = document.activeElement
    this.opener = active && active !== document.body ? active : null
    this.openerId = this.opener && this.opener.id
    this.confirmed = false
    if (dialog.showModal) dialog.showModal()
    // The browser puts focus on the first control of the dialog.
    // Where that is the button that takes a group away, it goes on
    // to the group's first field: Enter there is not to remove what
    // the person came to edit.
    if (document.activeElement && document.activeElement.matches("[data-remove-group]")) this.into(dialog.id)
    // Escape: the dialog stays until the server has taken it away
    dialog.addEventListener("cancel", e => { e.preventDefault(); this.cancel() })
    dialog.addEventListener("click", e => { if (e.target.closest("[data-cancel]")) this.cancel() })
    // What the editor of a column's component shows of its control's
    // value besides the control (the number beside a slider) follows
    // the control here, as it does in a cell, without waiting for
    // the server.
    dialog.addEventListener("input", e => {
      const field = e.target.closest && e.target.closest("[data-field]")
      if (!field || !e.target.matches("[data-control]")) return
      for (const shown of field.querySelectorAll("[data-value-text]")) shown.textContent = e.target.value
    })
    // The field of an array that is given value by value: its rows
    // are added and taken away here, as they are in a cell, by the
    // grid's hook. The server is told as it is of anything typed
    // into a field, by the entry the field sends before its values.
    this.mark()
    const changed = list => {
      const own = list.parentElement.querySelector("input[data-own]")
      if (own) own.dispatchEvent(new Event("input", {bubbles: true}))
    }
    dialog.addEventListener("click", e => {
      const list = e.target.closest && e.target.closest("[data-list]")
      if (!list || !this.grid) return
      if (e.target.closest("[data-add]")) this.grid.addValue(list, "").focus()
      else if (e.target.closest("[data-remove]")) this.grid.removeValue(list, e.target.closest("[data-item]"))
      else return
      changed(list)
    })
    // a box of such a field: what it holds is sent by the input beside it
    dialog.addEventListener("change", e => {
      const item = e.target.closest && e.target.closest("[data-list] [data-item]")
      if (!item || e.target.type !== "checkbox" || !this.grid) return
      this.grid.hold(item)
      changed(item.closest("[data-list]"))
    })
    // A field made of groups (an embedded resource, a map, an array
    // of either): the server adds a group and takes one away, and
    // says where focus goes then: into the group that was added,
    // or to what stands where the one that is gone stood.
    dialog.addEventListener("click", e => {
      const button = e.target.closest && e.target.closest("[data-add-group],[data-remove-group]")
      if (!button) return
      const add = button.dataset.addGroup !== undefined
      let path = null
      try { path = JSON.parse(add ? button.dataset.addGroup : button.dataset.removeGroup) } catch (_error) { return }
      this.transport.push(add ? "panel_add" : "panel_remove", {path}, reply => this.into(reply && reply.focus))
    })
    // A field that holds several related records: the server takes
    // one out, and says where focus goes then: to the button of the
    // record that stands where it stood, or to the field's "Choose".
    dialog.addEventListener("click", e => {
      const button = e.target.closest && e.target.closest("[data-unpick]")
      if (!button) return
      let named = null
      try { named = JSON.parse(button.dataset.unpick) } catch (_error) { return }
      this.transport.push("panel_unpick", {input: named[0], key: named[1]}, reply => this.into(reply && reply.focus))
    })
    // A sensitive field that can be emptied: its button asks the
    // server to note it, or to take it back, and has the focus
    // again once the field is rendered anew.
    dialog.addEventListener("click", e => {
      const button = e.target.closest && e.target.closest("[data-clear-field]")
      if (!button) return
      this.transport.push("panel_clear", {input: button.dataset.clearField}, reply => this.into(reply && reply.focus))
    })
    // The panel of a cell asks the column's question only when
    // something was changed: what its form holds as it opens is
    // what the record has.
    this.initial = dialog.dataset.ask === "changed" ? this.snapshot() : null
    // An action with a question asks it when "Run" is used, in the
    // table's other dialog, on top of this one. Cancel there comes
    // back here, with everything as it was typed.
    dialog.addEventListener("submit", e => {
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
      if (!question || !this.grid || this.confirmed || same) { this.confirmed = false; return }
      e.preventDefault()
      e.stopPropagation()
      const submitter = e.submitter
      this.grid.ask(question, dialog.dataset.destructive !== undefined).then(confirmed => {
        if (!confirmed || !dialog.isConnected) return
        this.confirmed = true
        e.target.requestSubmit(submitter)
      })
    }, true)
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
    if (!this.grid) return
    for (const list of this.el.querySelectorAll("[data-list]")) {
      let places = []
      try { places = JSON.parse(list.parentElement.dataset.invalid || "[]") } catch (_error) { /* none */ }
      this.grid.markValues(list, places)
    }
  },

  // Once the patch is done, and only while focus is nowhere: the
  // server may have sent it somewhere itself (to a new row). The
  // panel of a nested table is inside the grid around that table,
  // which takes focus back to its tab stop when the panel goes: the
  // cell the opener is in. That is nowhere yet, too.
  destroyed() {
    setTimeout(() => {
      const active = document.activeElement
      const opener = this.opener && this.opener.isConnected
        ? this.opener
        : (this.openerId ? document.getElementById(this.openerId) : null)
      const cell = opener && opener.closest("td,th")
      if (active && active !== document.body && active !== cell) return
      if (opener && opener.getClientRects().length > 0) opener.focus({preventScroll: true})
      // a button of the line above the grid went with the selection
      else if (this.grid && this.grid.el.isConnected && opener && opener.closest("[data-selection]")) this.grid.toTabStop()
      else if (this.grid && this.grid.el.isConnected) this.grid.refocus()
    })
  }
}
