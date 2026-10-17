// The development check of the hooks.
//
// While LiveView's client debug is on (`liveSocket.enableDebug()`), each
// hook looks, once mounted and after every patch, for the markers it
// relies on (`markers.js`), and says on the console which one a part of
// the table lacks: what a kit that draws the table's parts with markup
// of its own has to write. Nothing is checked otherwise.

import {CELL, cellsOf} from "./grid/shared.js"
import {BULK, CONFIRM, DIALOG, OF, OPENED, QUESTION, REGION, SENDER, TABLE} from "./markers.js"

// What a hook's element lacks, as words, by the part it is.
const lacks = {
  // the grid: its table, the header, and the place of every cell
  grid(hook) {
    if (!hook.el.matches(`[${OF}]`)) return [`${OF} on its element`]
    const table = hook.table()
    if (!table) return [`an element ${TABLE} in its element`]
    const missing = []
    if (!hook.part("head")) missing.push(`its header (an element with the id ${hook.id}-head)`)
    if (!document.querySelector(`${SENDER}[${OF}="${CSS.escape(hook.id)}"]`)) missing.push(`its sender (an element ${SENDER} that names its table)`)
    // a table that asks before something runs: a row action, a column, an
    // action on the selection; without the dialog nothing of it runs
    const line = hook.line()
    const asks = hook.el.querySelector(`${QUESTION},${CONFIRM}`) || (line && line.querySelector(BULK))
    // modal: a <dialog> the hook opens; inline: a region of the page
    const dialog = hook.part("dialog")
    const question = dialog && (dialog.dataset.presentation === "inline"
      ? dialog.matches(`${REGION}${OPENED}`)
      : dialog.matches(DIALOG) && typeof dialog.showModal === "function")
    if (asks && !question) {
      missing.push(`its question dialog (a <dialog> ${DIALOG}, or ${REGION} with data-presentation="inline", with the id ${hook.id}-dialog)`)
    }
    for (const row of hook.rows()) {
      for (const cell of cellsOf(row)) {
        if (!cell.hasAttribute("aria-colindex")) missing.push(`aria-colindex on the cell ${cell.id || `(${CELL})`}`)
      }
    }
    return missing
  },
  // what opens: the table it is of, how it opens, and the role that
  // goes with it (a modal one is a dialog the hook opens, an inline one a
  // region of the page)
  dialog(hook) {
    const inline = hook.el.dataset.presentation === "inline"
    const role = inline ? REGION : DIALOG
    const modal = inline || typeof hook.el.showModal === "function"
    return [[`${OF}`, hook.el.matches(`[${OF}]`)], [OPENED, hook.el.matches(OPENED)], [role, hook.el.matches(role)],
      ["a <dialog>, as it is modal", modal]]
      .filter(([, there]) => !there).map(([what]) => what.startsWith("a <") ? what : `${what} on its element`)
  },
  sender(hook) {
    return hook.el.matches(`[${OF}]`) ? [] : [`${OF} on its element`]
  },
  pagination(hook) {
    return hook.el.matches(`[${OF}]`) ? [] : [`${OF} on its element`]
  }
}

// `part` is what the hook is: "grid", "dialog" (the action panel, the
// picker), "sender" or "pagination".
export function check(hook, part) {
  if (!hook.transport || !hook.transport.debug()) return
  for (const what of lacks[part](hook)) {
    console.error(`ash_data_table: the ${part} ${hook.el.id} has no ${what}`)
  }
}
