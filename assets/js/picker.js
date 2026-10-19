// The picker: open for as long as the server renders it, as the
// action panel is, modal or inline as it says, and a modal one on
// top of the panel when a field of the panel opened it. Focus moves into its table, to
// the row of the record that is chosen now when that is on the
// page. The person selects a row there, which the table's own hook
// tells the server (`select`), and "Choose" sends `picked`: the
// server takes what is selected; Enter on a row and a double click
// choose that row at once (`ash_data_table:choose`). "Choose" says
// whether there is a row to take as the server draws it. Escape and
// Cancel ask the server to take the picker away; when it is gone,
// focus goes back to the cell, or to the button of the panel, that
// opened it.
import {error as errorId} from "./ids.js"
import {cellsOf} from "./grid/shared.js"
import {ARGUMENTS, CANCEL, GRID, GRIDCELL, HEADER, NONE, OF, TAKE} from "./markers.js"
import {opened} from "./panel.js"

export default {
  mounted() {
    const dialog = this.el
    // every listener of the hook goes with it (`destroyed`)
    this.ending = new AbortController()
    const until = {signal: this.ending.signal}
    const grid = document.querySelector(`${GRID}[${OF}="${CSS.escape(dialog.getAttribute(OF))}"]`)
    // the hook of the table the picker belongs to: its dialog asks
    // a column's question
    this.grid = grid && grid._ashDataTable
    const active = document.activeElement
    this.opener = active && active !== document.body ? active : null
    this.openerId = this.opener && this.opener.id
    this.busy = false
    opened(dialog, () => this.cancel(), until)
    dialog.addEventListener("click", e => {
      if (!e.target.closest) return
      if (e.target.closest(CANCEL)) this.cancel()
      else if (e.target.closest(NONE)) this.choose(true)
      // the server knows what is selected, and takes nothing where nothing is
      else if (e.target.closest(TAKE)) this.choose(false)
    }, until)
    // after the table's hook has told the server of the row it selected
    dialog.addEventListener("ash_data_table:choose", () => this.choose(false), until)
    // once the table's own hook is there
    setTimeout(() => this.enter())
  },

  // The table in the picker, as its hook.
  table() {
    const grid = this.el.querySelector(GRID)
    return grid && grid._ashDataTable
  },

  // Into the table: to the row that is selected as it opens, else
  // to where the arrow keys start from. A picker whose table could
  // not be read has no grid, and focus stays on its first button.
  enter() {
    const table = this.table()
    if (!table || !this.el.isConnected) return
    const current = table.rows().find(row => row.getAttribute("aria-selected") === "true")
    const cells = current ? cellsOf(current) : []
    const cell = current ? cells[Math.min(table.lead(), cells.length - 1)] : table.cellAt(table.pos.r, table.pos.c)
    if (cell) cell.focus()
  },

  // Sends the choice: what is selected in the picker's table, which
  // the server holds, or no record (`none`). The server reads that
  // record as the person, and answers with the question of a column
  // that has one when the choice would change the row; Confirm sends
  // it again. What comes of it is the server's to show: it takes the
  // picker away, or says in it why nothing was chosen.
  choose(none, confirmed) {
    if (this.busy) return
    this.busy = true
    const cell = this.cell()
    if (cell) cell.setAttribute("aria-busy", "true")
    // What the argument line of the picker's table holds: the
    // record is read through the same action, given the same.
    const line = this.el.querySelector(`form${ARGUMENTS}`)
    // @ts-expect-error: a FormData is what URLSearchParams takes; TypeScript's DOM types say otherwise
    const held = line ? new URLSearchParams(new FormData(line)).toString() : null
    this.transport.push("picked", {none, confirmed: !!confirmed, arguments: held}).then(reply => {
      this.busy = false
      // the column's question is the host's to ask (controlled mode): the
      // cell waits, busy, until it is answered; nothing in it changed, so
      // nothing is put back
      if (reply && reply.held) {
        if (cell && cell.isConnected && this.grid) this.grid.waitFor(reply.ref, cell, {restore: () => {}})
        return
      }
      if (cell) cell.removeAttribute("aria-busy")
      if (reply && reply.ask && this.grid) {
        // Cancel, and Escape: the browser puts focus back in the picker
        this.grid.ask(reply.ask, false, this.el).then(yes => { if (yes === true && this.el.isConnected) this.choose(none, true) })
        return
      }
      // the row's record is gone: there is no row to send, so the cell is marked here
      if (reply && reply.error) this.failed = reply.error
    })
  },

  // The cell the picker was opened from, when it was a cell.
  cell() {
    const opener = this.opener && this.opener.isConnected ? this.opener : (this.openerId ? document.getElementById(this.openerId) : null)
    return opener && opener.matches(GRIDCELL) ? opener : null
  },

  cancel() { this.transport.push("picker_cancel", {}) },

  // Once the patch is done, and only while focus is nowhere, as the
  // action panel does.
  destroyed() {
    this.ending.abort()
    // a question it asked in it is answered as Cancel
    if (this.grid) this.grid.goneWith(this.el)
    const failed = this.failed
    setTimeout(() => {
      const active = document.activeElement
      const opener = this.opener && this.opener.isConnected
        ? this.opener
        : (this.openerId ? document.getElementById(this.openerId) : null)
      const cell = opener && opener.closest(`${GRIDCELL},${HEADER}`)
      if (failed && cell && cell === opener && this.grid) {
        this.grid.fail(cell, failed, () => {
          const message = document.getElementById(errorId(cell.id))
          if (message) message.remove()
        })
      }
      if (active && active !== document.body && active !== cell) return
      if (opener && opener.getClientRects().length > 0) opener.focus({preventScroll: true})
      else if (this.grid && this.grid.el.isConnected) this.grid.toTabStop()
    })
  }
}
