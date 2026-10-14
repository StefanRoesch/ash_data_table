// The picker: a modal dialog that is open for as long as the server
// renders it, as the action panel is, and on top of the panel when
// a field of the panel opened it. Focus moves into its table, to
// the row of the record that is chosen now when that is on the
// page. The person selects a row there, which is the table's own
// hook's to know and to say (`ash_data_table:selection`), and "Choose"
// sends it; Enter on a row and a double click choose that row at
// once (`ash_data_table:choose`). Escape and Cancel ask the server to
// take the picker away; when it is gone, focus goes back to the
// cell, or to the button of the panel, that opened it.
export default {
  mounted() {
    const dialog = this.el
    const grid = document.getElementById(dialog.id.replace(/-picker$/, "-grid"))
    // the hook of the table the picker belongs to: its dialog asks
    // a column's question
    this.grid = grid && grid._ashDataTable
    const active = document.activeElement
    this.opener = active && active !== document.body ? active : null
    this.openerId = this.opener && this.opener.id
    // the rows that are selected in the picker's table: one at
    // most, unless several records are chosen (`data-several`)
    this.rows = []
    this.several = dialog.dataset.several !== undefined
    this.busy = false
    if (dialog.showModal) dialog.showModal()
    // Escape: the dialog stays until the server has taken it away
    dialog.addEventListener("cancel", e => { e.preventDefault(); this.cancel() })
    dialog.addEventListener("click", e => {
      if (!e.target.closest) return
      if (e.target.closest("[data-cancel]")) this.cancel()
      else if (e.target.closest("[data-none]")) this.choose(null)
      else if (e.target.closest("[data-take]")) this.chooseSelected()
    })
    dialog.addEventListener("ash_data_table:selection", e => this.heard(e.detail))
    dialog.addEventListener("ash_data_table:choose", e => { this.heard(e.detail); this.chooseSelected() })
    // once the table's own hook is there
    setTimeout(() => this.enter())
  },

  // The table in the picker, as its hook.
  table() {
    const grid = this.el.querySelector("[data-ash-data-table]")
    return grid && grid._ashDataTable
  },

  // Into the table: to the row that is selected as it opens, else
  // to where the arrow keys start from. A picker whose table could
  // not be read has no grid, and focus stays on its first button.
  enter() {
    const table = this.table()
    if (!table || !this.el.isConnected) return
    this.heard(table.selected())
    const current = table.el.querySelector("tr[aria-selected='true']")
    const cell = current ? current.cells[Math.min(table.lead(), current.cells.length - 1)] : table.cellAt(table.pos.r, table.pos.c)
    if (cell) cell.focus()
  },

  // What is selected in the table. "Choose" is for a selected row;
  // where several records are chosen it takes whatever is
  // selected, no row among it.
  heard(detail) {
    this.rows = detail && detail.rows ? detail.rows : []
    const button = this.el.querySelector("[data-take]")
    if (!button || this.several) return
    const none = this.rows.length === 0
    button.setAttribute("aria-disabled", String(none))
    button.classList.toggle("btn-disabled", none)
  },

  chooseSelected() {
    if (this.several) this.choose(this.rows)
    else if (this.rows.length > 0) this.choose(this.rows[0])
  },

  // Sends the choice: a row as the table's hook names it, or null
  // for no record; where several records are chosen, the list of
  // the rows. The server reads that record as the person, and
  // answers with the question of a column that has one when the
  // choice would change the row; Confirm sends it again. What
  // comes of it is the server's to show: it takes the picker away,
  // or says in it why nothing was chosen.
  choose(row, confirmed) {
    if (this.busy) return
    this.busy = true
    const cell = this.cell()
    if (cell) cell.setAttribute("aria-busy", "true")
    // What the argument line of the picker's table holds: the
    // record is read through the same action, given the same.
    const line = this.el.querySelector("form[data-arguments]")
    // @ts-expect-error: a FormData is what URLSearchParams takes; TypeScript's DOM types say otherwise
    const held = line ? new URLSearchParams(new FormData(line)).toString() : null
    const payload = this.several ? {rows: row, arguments: held} : {row, confirmed: !!confirmed, arguments: held}
    this.transport.push("picked", payload).then(reply => {
      this.busy = false
      if (cell) cell.removeAttribute("aria-busy")
      if (reply && reply.ask && this.grid) {
        // Cancel, and Escape: the browser puts focus back in the picker
        this.grid.ask(reply.ask).then(yes => { if (yes && this.el.isConnected) this.choose(row, true) })
        return
      }
      // the row's record is gone: there is no row to send, so the cell is marked here
      if (reply && reply.error) this.failed = reply.error
    })
  },

  // The cell the picker was opened from, when it was a cell.
  cell() {
    const opener = this.opener && this.opener.isConnected ? this.opener : (this.openerId ? document.getElementById(this.openerId) : null)
    return opener && opener.matches("td[role='gridcell']") ? opener : null
  },

  cancel() { this.transport.push("picker_cancel", {}) },

  // Once the patch is done, and only while focus is nowhere, as the
  // action panel does.
  destroyed() {
    const failed = this.failed
    setTimeout(() => {
      const active = document.activeElement
      const opener = this.opener && this.opener.isConnected
        ? this.opener
        : (this.openerId ? document.getElementById(this.openerId) : null)
      const cell = opener && opener.closest("td,th")
      if (failed && cell && cell === opener && this.grid) {
        this.grid.fail(cell, failed, () => {
          const message = document.getElementById(`${cell.id}-error`)
          if (message) message.remove()
        })
      }
      if (active && active !== document.body && active !== cell) return
      if (opener && opener.getClientRects().length > 0) opener.focus({preventScroll: true})
      else if (this.grid && this.grid.el.isConnected) this.grid.toTabStop()
    })
  }
}
