// A file a table's action returned, saved in the person's browser.
//
// A generic action that returns `Ash.Type.File` (a row's, the table's or
// one on the selection) has its file read on the server and pushed to
// the page as `ash_data_table:download` ({table, name, type, data}, the
// content in Base64; `AshDataTable.Live.Core.download/2`). LiveView hands
// a push to `window` as the event `phx:ash_data_table:download`, wherever
// the table is drawn and whatever kit draws it, so one listener on
// `window` serves every table of the page: it makes the content a Blob
// and has the browser save it under its name, through a link that is
// never put into the page.
//
// The listener is set up once per window, as this module is imported
// (index.js): the hooks may be bundled twice on one page (the colocated
// hooks, and a kit that imports this package), and a file is saved once.

const SAVED = "phx:ash_data_table:download"

/**
 * Has the browser save a file, given as the push gives it.
 *
 * @param {{name: string, type: string, data: string}} file
 */
function save({name, type, data}) {
  const bytes = Uint8Array.from(atob(data), char => char.charCodeAt(0))
  const url = URL.createObjectURL(new Blob([bytes], {type}))
  const link = document.createElement("a")
  link.href = url
  link.download = name
  link.click()
  // the browser has taken the file once the click is handled
  setTimeout(() => URL.revokeObjectURL(url), 0)
}

/** Listens for the files the server pushes, once per window. */
function listen() {
  if (typeof window === "undefined" || window._ashDataTableDownload) return
  window._ashDataTableDownload = true
  window.addEventListener(SAVED, event => save(/** @type {CustomEvent} */ (event).detail))
}

listen()
