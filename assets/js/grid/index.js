// Keyboard, focus and editing for one grid: a single tab stop with a
// roving tabindex, moved by the arrow keys.
//
// A nested table is a grid of its own, with a hook of its own, inside
// a cell of the grid around it. The tab stop is one for the whole
// tree: the tables on top of each other share where it is (`tree()`),
// and each hook deals only with what happens in its own grid
// (`owns()`). The arrow keys stay in the grid that has the focus;
// Enter on the cell that holds a nested table goes into it, and
// Escape in it comes back out to that cell.
//
// Moving about never talks to the server. Enter on a sortable header
// clicks it and Enter in a filter submits the filter row's form; both
// are the server's from there.
//
// Which cell is being edited is known here alone. The server renders
// one editor per editable column in a <template>; a copy of it is put
// into the cell, and when the person is done, one "save" event goes
// out with the row, the column and the value as typed. The answer is
// the row itself, patched in: with the new value, or with the cell
// marked as failed.
//
// Which rows are selected the server holds, and this hook paints
// (`data-select` on this element says whether rows can be selected:
// "multi" or "single"). The server renders a box in the first cell
// of every row and nothing of its state: after every patch the rows
// are marked again (`aria-selected`, and the box), so that no row
// is sent again for it. Every change a person makes is sent
// (`select`); where the server decides what is selected, it says so
// (`ash_data_table:select`). A row is remembered by the key in its
// id, with what the server is told of it: its primary key, which is
// that key, or what the row says in `data-key`. A selection
// outlives its page and the sort, and the server gives it up when
// the filters change. The line
// above the grid (`ID-selection`) is the server's, with the count
// and its buttons. Others learn of a selection from `selected()`
// and from the event `ash_data_table:selection`, which this element
// sends, with the same, whenever it changes.
//
// Where one row at a time is selected ("single"), the rows have
// radio buttons, and behave as those do: selecting another row
// takes the first one's place, and selecting the selected row
// again leaves it selected.
//
// A reference cell has no editor in the cell: its related record
// is chosen in the picker, a dialog with the table of the related
// resource, which the server renders when this hook asks for it
// (`pick`). That table is one to choose from (`data-choose`): a
// click anywhere on a row selects the row, Enter on a row and a
// double click choose it (`ash_data_table:choose`, for the picker's
// hook), and it starts with the row selected that the server marks
// as the record chosen now (`data-current`), until the person
// selects another.
//
// Nor has a cell of several values (an array, an embedded resource, a
// map, an array of either, a union): Enter, F2 and a double click ask
// the server for the side panel (`edit`), in which its values or
// fields are edited and saved, as a form; so does a key typed on an
// array.
// The cell is the panel's opener, and has the focus again when
// the panel is gone.
//
// A cell of a sensitive column holds a mask and a button, and
// not the value: Shift+Enter on the cell, or the button, asks
// the server for it (`reveal`), and the answer is put into the
// cell, which says it (a live region). It is taken out again
// when focus leaves the cell, with Escape, with the same key or
// button once more, and by every patch of the row, which brings
// the cell as the server renders it. One cell at a time. Its
// editor is a password input that opens empty; while its save
// is on its way the cell shows what it showed, never what was
// typed.
//
// A grid in a dialog is the top of its own tree
// of grids, wherever the dialog stands in the page: nothing
// outside a modal dialog can be reached while it is open.
//
// How wide the columns are is known here alone as well, once a
// person has changed a width (see "the widths of the columns"), and
// so is which columns a person has hidden (see "hiding columns").
//
// The hook is one object. Its methods are written in one module per
// section, below; they share the hook's state through `this`, and what
// is the same for every grid through ./shared.js. No two sections may
// name a method alike: that is checked as the object is put together.

import {COUNT, OF} from "../markers.js"
import {KEPT, PLACE} from "./shared.js"
import counter from "./counter.js"
import tree from "./tree.js"
import expanding from "./expanding.js"
import widths from "./widths.js"
import hiding from "./hiding.js"
import scrolling from "./scrolling.js"
import selecting from "./selecting.js"
import actions from "./actions.js"
import editing from "./editing.js"
import saving from "./saving.js"
import sensitive from "./sensitive.js"
import dialog from "./dialog.js"
import wholeText from "./whole_text.js"

const core = {
  mounted() {
    // the table's id, which every id in it starts with
    this.id = this.el.getAttribute(OF)
    // Every listener this hook adds to its element, the document and the
    // window goes with it (`destroyed`), so that the hook can be mounted on
    // the same element again (`mountGrid`, under React's StrictMode).
    this.ending = new AbortController()
    const until = {signal: this.ending.signal}
    // for the hooks of the grids around this one and in it
    this.el._ashDataTable = this
    // the cell arrow keys start from: the first data cell of the first
    // data row, or of the last header row while there are no rows. The
    // expander of the row is one cell to the left of it.
    this.pos = {r: this.headRows(), c: this.lead()}
    this.col = this.lead()
    // the edit in progress: {cell, root, input, type, saved, old,
    // confirm, commit}, and `attributes` once a patch has brought
    // the cell's row again. `root` is what was put into the cell
    // and `input` the control in it; `commit` says when a
    // component's editor saves.
    this.editing = null
    // the sensitive cell whose value is shown: {cell}, or null
    this.revealed = null
    // cells this hook has marked as failed itself, with what they showed before
    this.marked = new WeakMap()
    // the cell under the pointer, and the cells whose whole text shows,
    // by id (see "the whole text of a cell")
    this.pointed = null
    this.expanded = new Set()
    // the row action that was used last: where its cell stood, for
    // when its row is gone
    this.acted = null
    // the widths of the columns, by the id of their header, once a
    // person has changed one: {width, original}. And the style
    // sheet that holds them.
    this.widths = null
    this.sheet = null
    // the columns a person has hidden, by the id of their header,
    // and where those stand now (`aria-colindex`)
    this.hidden = new Set()
    this.goneAt = new Set()
    // What is selected: `keys` holds the rows by the key in their
    // id, each with what the server is told of it (see `named`);
    // `all` says that every record the filters match is selected,
    // on whatever page. `anchor` is the row a range starts from,
    // and `range` the range that Shift and the arrow keys are
    // drawing, with what was selected before it.
    this.selection = {keys: new Map(), all: false, anchor: null, range: null}
    // The line above the grid is outside this element, and so is the
    // heading line, which a nested table has on the line that names it,
    // in the table around it: what happens there is heard at the
    // document, and each handler takes only what is this table's (by
    // the ids of its parts).
    this.scope = document
    this.onLine = e => this.onLineClick(e)
    this.scope.addEventListener("click", this.onLine, until)
    // the button of the line the focus was in last, for when the
    // server takes the buttons away with the selection (`paint`)
    this.lineFocus = null
    this.onLineFocus = e => {
      const line = this.line()
      if (line && line.contains(e.target)) this.lineFocus = e.target
    }
    this.scope.addEventListener("focusin", this.onLineFocus, until)
    // so is the argument line: Enter in one of its inputs applies
    // what the line holds now, as it does in a filter. A form of
    // several inputs without a button is not sent by Enter itself.
    this.onArgument = e => this.onArgumentKeydown(e)
    this.scope.addEventListener("keydown", this.onArgument, until)
    // The counter of a text follows what is typed, wherever in the
    // table the text is: in a cell, in the argument line, in the
    // action panel. Nothing is sent for it.
    this.onTyped = e => this.onCount(e)
    this.scope.addEventListener("input", this.onTyped, until)
    // and so is "Columns", with its list
    this.onColumns = e => this.onColumnsEvent(e)
    for (const type of ["change", "focusout"]) this.scope.addEventListener(type, this.onColumns, until)
    // A patch of the argument line brings its counters as the
    // server counted them, from what it had heard by then, which
    // need not be all that has been typed since: they are counted
    // again from what the inputs hold. (The panel's hook does the
    // same for the panel.)
    const line = this.part("arguments")
    if (line && line.querySelector(COUNT)) {
      this.counted = new MutationObserver(() => this.recountIn(line))
      this.counted.observe(line, {subtree: true, childList: true, characterData: true})
    }
    // the server says what is selected where it decided it: a
    // selection made under other filters is given up, a row that went
    // is selected no longer, and after an action on the selection the
    // rows it did not run on stay selected, and no others
    this.transport.on("ash_data_table:select", ({table, all, rows}) => {
      if (table !== this.id) return
      this.select(new Map(rows), all, false, true)
    })
    // The server says that a row is to go: its record is gone, or
    // no longer this person's to read (a live update). A row with
    // an open editor stays until that is closed: see `released`.
    this.leaving = new Set()
    this.transport.on("ash_data_table:leaving", ({table, row}) => {
      if (table !== this.id) return
      const ed = this.editing
      if (ed && ed.cell.isConnected && this.rowKey(ed.cell) === row) this.leaving.add(row)
      else this.transport.push("left", {row})
    })
    // Saves that wait for the host's answer to their column's question
    // (controlled mode), by the `ref` of the host's request: the cell and
    // what puts it back (`waitFor`). The server says when one is answered.
    this.holds = new Map()
    this.transport.on("ash_data_table:answered", answer => {
      if (answer.table === this.id) this.answered(answer)
    })
    // the server says where focus goes after something it did: to
    // the first cell of a row that was created
    // and into a row of the argument line that was added, or to
    // what stands where one that was taken away stood
    this.transport.on("ash_data_table:focus", ({table, cell}) => {
      if (table !== this.id) return
      const target = document.getElementById(cell)
      const line = this.part("arguments")
      if (target && (this.el.contains(target) || (line && line.contains(target)))) target.focus({preventScroll: true})
    })
    // The server says that a table action asks first: its question is
    // asked in the table's dialog, and Confirm runs the action. A
    // question that is open gives way to it (`ask`).
    // Cancel, and Escape: the browser puts focus back on the button.
    this.transport.on("ash_data_table:ask", ({table, action, question}) => {
      if (table !== this.id) return
      this.ask(question, false).then(confirmed => {
        if (confirmed === true) this.transport.push("table_run", {action})
      })
    })
    // what happens in a grid nested in this one is that grid's
    const own = handle => e => { if (this.owns(e.target)) handle(e) }
    this.el.addEventListener("keydown", own(e => this.onKeydown(e)), until)
    this.el.addEventListener("focusin", own(e => this.onFocusin(e)), until)
    this.el.addEventListener("focusout", own(e => this.onFocusout(e)), until)
    this.el.addEventListener("click", own(e => this.onClick(e)), until)
    this.el.addEventListener("mousedown", own(e => this.onMousedown(e)), until)
    this.el.addEventListener("dblclick", own(e => this.onDblclick(e)), until)
    this.el.addEventListener("pointerdown", own(e => this.onResizeStart(e)), until)
    this.el.addEventListener("mouseover", e => this.onPointer(this.cellOf(e.target)), until)
    this.el.addEventListener("mouseleave", () => this.onPointer(null), until)
    // The window scrolls, or is another size: the scrollbar at its
    // bottom edge follows (`PLACE`). Nothing else is placed by hand.
    this.onScroll = () => PLACE()
    window.addEventListener("scroll", this.onScroll, {capture: true, signal: this.ending.signal})
    window.addEventListener("resize", this.onScroll, until)
    // The grid scrolls sideways: its scrollbar at the bottom edge
    // of the window follows, and the other way round; and what
    // stays in view has an edge while something is under it.
    this.pins = null
    this.pinned = null
    this.clips = []
    this.inset = 0
    this.bar = this.part("scrollbar")
    this.onSideways = () => this.sideways()
    this.onBar = () => this.fromBar()
    this.el.addEventListener("scroll", this.onSideways, {passive: true, signal: this.ending.signal})
    if (this.bar) this.bar.addEventListener("scroll", this.onBar, {passive: true, signal: this.ending.signal})
    // how wide the grid is, and the table in it, is watched: for
    // what a nested table is told, and for the scrollbar
    this.measured = new ResizeObserver(() => this.measure())
    this.measured.observe(this.el)
    this.measured.observe(document.body)
    // updated() only runs when this element itself is patched; a
    // stream insert or reset touches the rows alone.
    //
    // A patch of a row also takes away what this hook has said of
    // it: that it is selected. So that is watched for as well.
    // (Not for the button of a cell's whole text alone, which this hook
    // puts in and takes out itself.)
    this.observer = new MutationObserver(records => {
      const patched = records.filter(record => !this.ofWhole(record))
      if (patched.length > 0) this.sync(patched)
    })
    this.observer.observe(this.el, {
      subtree: true,
      childList: true,
      attributes: true,
      attributeFilter: ["tabindex", "aria-selected"]
    })
    this.sync()
  },

  // A cell that is being edited is left alone by patches, so that
  // what is typed survives when another cell's save puts the row
  // back. The row the server sent holds what the cell shows now,
  // though; it is kept aside here, for when the edit is given up.
  beforeUpdate(toEl) {
    const ed = this.editing
    if (!ed || !toEl || !toEl.querySelector) return
    const fresh = toEl.querySelector(`[id="${CSS.escape(ed.cell.id)}"]`)
    if (!fresh) return
    ed.saved = Array.from(fresh.childNodes).map(node => node.cloneNode(true))
    ed.attributes = KEPT.map(name => [name, fresh.getAttribute(name)])
  },

  updated() { this.sync() },

  destroyed() {
    this.quitWhole()
    this.unstyle()
    this.unpin()
    this.observer && this.observer.disconnect()
    this.counted && this.counted.disconnect()
    this.listed && this.listed.disconnect()
    this.measured && this.measured.disconnect()
    this.ending.abort()
    if (this.el._ashDataTable === this) delete this.el._ashDataTable
  },

  // Says which cell is being edited, by its id, or that none is (null), to
  // whoever mounted the hook and asked (`mountGrid`'s `onEdit`): a kit that
  // draws in the browser keeps the cell's content as it is meanwhile, as
  // LiveView leaves an edited cell alone (`editing.js`).
  edited(cellId) {
    const onEdit = this.options && this.options.onEdit
    if (onEdit) onEdit(cellId)
  },
}

const grid = {}
for (const part of [core, counter, tree, expanding, widths, hiding, scrolling, selecting, actions, editing, saving, sensitive, dialog, wholeText]) {
  for (const key of Object.keys(part)) {
    if (Object.hasOwn(grid, key)) throw new Error(`ash_data_table: the grid's hook has two methods named ${key}`)
    grid[key] = part[key]
  }
}

export default grid
