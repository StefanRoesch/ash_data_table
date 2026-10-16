// What the sections of the grid's hook share besides the hook itself:
// constants, helpers that need no hook, and what is the same for all
// grids of a page (where the scrollbars at the bottom edge go, whether
// focus is moving with Tab).
import {CONTROL, DIALOG, GRID, GRIDCELL, HEADER, ROW, ROWGROUP, TABLE} from "../markers.js"

// a key that types a character
export const PRINTABLE = e => e.key.length === 1 && !e.ctrlKey && !e.metaKey && !e.altKey

// What a cell says about itself besides its content, which a patch
// does not bring to a cell that is being edited.
export const KEPT = ["aria-readonly", "aria-invalid", "aria-describedby", "data-value", "data-saved", "data-invalid"]

// keys that move through the options of a closed select
export const SELECT_KEYS = ["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "Home", "End", "PageUp", "PageDown"]

// The control of a form that holds something the browser cannot read
// as a value of its type, as in the panel's hook: the one thing the
// argument line is held back for.
export const UNREADABLE = form =>
  Array.from(form.elements).find(control => control.validity && control.validity.badInput)

// What is around an element, nearest first, as far as it is of
// the same tree of grids: the grid it is in, or the cell that
// holds the nested table it is in. Nothing beyond a dialog: a
// dialog is a place of its own.
export const AROUND = (node, what) => {
  const found = node.parentElement && node.parentElement.closest(`${what},${DIALOG}`)
  return found && found.matches(what) ? found : null
}

// The grid's structure, by its markers alone (the design note of
// stage 7, D4): whatever elements a kit draws it with, a grid
// (`role=grid`) holds rows, each record's in a row group of its own,
// and a row holds cells, a column's header or a grid cell. A cell
// says where it stands among the columns (`aria-colindex`, from 1).

// a cell of a row: a column's header or a grid cell
export const CELL = `${GRIDCELL},${HEADER}`

// the cells of a row, in their order
export const cellsOf = row => row ? Array.from(row.children).filter(child => child.matches(CELL)) : []

// where a cell stands among the columns, counted from 0
export const place = cell => Number(cell.getAttribute("aria-colindex")) - 1

// The rows of a grid, the header rows first: not those of a grid
// nested in it, which stand in one of its cells.
export const rowsOf = table => table ? Array.from(table.querySelectorAll(ROW)).filter(row => row.closest(TABLE) === table) : []

// the row groups of a grid, in their order: its records' and details', and
// its header and footer where a kit makes them row groups too (a record's
// is told apart by `isRecord` of the hook)
export const groupsOf = table => table ? Array.from(table.querySelectorAll(ROWGROUP)).filter(group => group.closest(TABLE) === table) : []

// the first row of a row group: a record's own row, or the first line
// of a detail
export const firstRow = group => group.querySelector(ROW)

// whether a cell spans the grid: a line, the cell of a nested table,
// of its pages or of its link to the full view
export const SPANNING = cell => Number(cell.getAttribute("colspan") || 1) > 1

// The control of an editor: what holds the value and takes the
// focus. A built-in editor is its own control. The editor of a
// column's component is whatever the component renders, and its
// control is the one that carries what the table gave it
// (`data-control`), else the first form control in it.
export const CONTROL_IN = root => root.matches(CONTROL)
  ? root
  : (root.querySelector(CONTROL) || root.querySelector("input,select,textarea") || root)

// What an editor holds, as a cell says it: a list is written as
// JSON. Two values are the same when they are written the same.
export const WRITTEN = value => Array.isArray(value) ? JSON.stringify(value) : value
export const SAME = (a, b) => WRITTEN(a) === WRITTEN(b)

// the list a cell says
export const LISTED = text => {
  try {
    const list = JSON.parse(text)
    return Array.isArray(list) ? list : []
  } catch (_error) { return [] }
}

// How long a text is, as Ash counts it when it checks `max_length`,
// from what a counter says of itself (`AshDataTable.Model.Limits`): a
// `:ci_string` that folds its case is folded first, the text is
// trimmed unless the type says otherwise, and what is left is
// counted in graphemes, codepoints or bytes. Trimmed as Elixir's
// `String.trim/1` trims, which is not quite what `trim()` takes
// away here (U+0085 and not U+FEFF).
export const BLANK = "\\t-\\r \\u0085\\u00A0\\u1680\\u2000-\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000"
export const TRIMMED = new RegExp(`^[${BLANK}]+|[${BLANK}]+$`, "g")
export const LENGTH = (text, {count, trim, casing}) => {
  if (casing === "lower") text = text.toLowerCase()
  else if (casing === "upper") text = text.toUpperCase()
  if (trim !== undefined) text = text.replace(TRIMMED, "")
  if (count === "bytes") return new TextEncoder().encode(text).length
  if (count === "graphemes" && typeof Intl !== "undefined" && Intl.Segmenter) {
    let graphemes = 0
    for (const _grapheme of new Intl.Segmenter().segment(text)) graphemes++
    return graphemes
  }
  // codepoints: a string is iterated by them
  return Array.from(text).length
}

// a control that text is typed into: typing on its cell replaces its value
export const TYPED = "textarea,input:is([type=text],[type=search],[type=tel],[type=url],[type=email],[type=password],[type=number],:not([type]))"

// What a cell is besides a cell of a column, by its marker: the
// expander of a row (`EXPANDER`), a line under an expanded row
// (`LINE`), the cell that holds a nested table (`NESTED`), …
export const is = (node, marker) => node.matches(marker)

// The attribute a marker of an attribute names (`[data-paragraph]` is
// `data-paragraph`), for an element the hook writes the marker on.
export const ATTRIBUTE = marker => marker.slice(1, -1)

export const STEP = 10

// The scrollbars at the bottom edge of the window (see "scrolling
// sideways") are placed for all grids of the page at once, before
// the next frame is drawn: first every grid says whether it wants
// one, then each is given it or not. Of the grids that are in one
// another, the innermost that wants one has it: the bar at the
// bottom edge belongs to the table whose rows are seen above it.
let PLACING = 0
export const PLACE = () => {
  if (PLACING) return
  PLACING = requestAnimationFrame(() => {
    PLACING = 0
    const hooks = Array.from(document.querySelectorAll(GRID)).map(grid => grid._ashDataTable).filter(Boolean)
    const wanted = new Map(hooks.map(hook => [hook.el, hook.barWanted()]))
    for (const hook of hooks) {
      const inner = Array.from(hook.el.querySelectorAll(GRID)).some(grid => wanted.get(grid))
      hook.placeBar(inner ? null : wanted.get(hook.el))
    }
  })
}

// Whether focus is moving with Tab just now: a cell that Tab comes
// to is brought into view as one the arrow keys come to is (see
// `intoView`). The key is heard before focus moves, and forgotten
// right after.
export const page = {tabbing: false}
window.addEventListener("keydown", e => {
  if (e.key !== "Tab") return
  page.tabbing = true
  setTimeout(() => { page.tabbing = false }, 0)
}, true)

// how high the scrollbar at the bottom edge is where the browser's
// scrollbars take no room (they lie over the content), in pixels,
// and how much of a grid has to be seen above it
export const BAR = 12
export const SEEN = 48

// How long a cell has the focus, and how long the pointer, before
// the whole of its text is shown (see "the whole text of a cell"),
// and how long the pointer may take from the cell to that text, in
// milliseconds. Long enough that going through cells with the arrow
// keys, or across them with the pointer, shows nothing.
export const WHOLE_FOCUS = 400
export const WHOLE_POINTER = 500
export const WHOLE_LEAVE = 200
