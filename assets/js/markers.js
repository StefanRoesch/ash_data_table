// The markers the hooks find the table's elements by (target.md S5):
// every selector a hook looks for, in one place. `AshDataTable.Attrs`
// writes them, and names the same list (`AshDataTable.Attrs.markers/0`;
// a test compares the two).
//
// A marker is an ARIA role where the element has one, else a `data-*`
// attribute the table writes (the design note of stage 7, D2). Ids are
// markers too: every id of a table starts with the table's own (`ID`,
// which the element of each hook says in `data-table`), and the hooks
// find a part of their table by it (`ID-whole`, `ID-dialog`, …).
//
// Besides these, the hooks ask for native controls by their kind:
// `input`, `select`, `textarea`, `button`, `a[href]`, `label`, `form`,
// `option` and `template`, which hold a value, take the focus or hold
// what is copied. Never for the table's structure: no `table`, `tr`,
// `td`, `th`, `tbody`, `p`, `span` or `dialog`.

// ---- the structure, by ARIA role

// the grid, its row groups (a record and the detail under it each have
// one; the header `ID-head` and the footer `ID-foot` may be row groups
// too, and are no record's, as a detail is none), its rows, and its cells
export const TABLE = "[role=grid]"
export const ROWGROUP = "[role=rowgroup]"
export const ROW = "[role=row]"
export const GRIDCELL = "[role=gridcell]"
export const HEADER = "[role=columnheader]"
// what opens over the page: the action panel, the picker, the question
export const DIALOG = "[role=dialog]"
// what opens in the page: the action panel or the picker, inline
export const REGION = "[role=region]"
// what opens, over the page or in it: the action panel and the picker
// say which (`modal`, `inline`), and the hooks follow
export const OPENED = "[data-presentation]"

// ---- the elements of the hooks

// the element a grid's hook is on
export const GRID = "[data-ash-data-table]"
// the element of each hook names the table it is of, by its id
export const OF = "data-table"
// the element beside a grid whose hook pushes the grid's events
export const SENDER = "[data-sender]"

// ---- what a cell or row group is besides a cell of a column

// a cell that spans the table: a line, the cell of a nested table, of its
// pages or of its link to the full view
export const SPANS = "[colspan]"
export const SELECTOR = "[data-selector]"
export const SELECT_PAGE = "[data-select-page]"
export const EXPANDER = "[data-expander]"
export const LINE = "[data-line]"
export const NESTED = "[data-nested]"
export const ACTIONS = "[data-actions]"
export const PAGER = "[data-pager]"
export const VIEW = "[data-view]"
export const FILTER = "[data-filter]"
// a cell whose text is a paragraph of several lines, and that paragraph
export const LINES = "[data-lines]"
export const PARAGRAPH = "[data-paragraph]"
// the row group of a row's detail, and the row of the record chosen now
export const DETAIL = "[data-detail]"
export const CURRENT = "[data-current]"
// the footer row of the summaries
export const SUMMARIES = "[data-summaries]"

// ---- in a cell

// the handle at the end of a column's header
export const HANDLE = "[data-resize]"
export const OPEN = "[data-open]"
export const ACTION = "[data-action]"
export const CREATE = "[data-create]"
export const TABLE_ACTION = "[data-table-action]"
// an action that destroys: a row action's button, an action on the
// selected rows, the action panel, and the confirm of the question
// dialog while it asks about one (the hook sets it there)
export const DESTRUCTIVE = "[data-destructive]"
// what asks a question in the table's dialog (`ID-dialog`) first: a row
// action's button, the action panel and the picker, which say the
// question, and the editor template of a column with one
export const QUESTION = "[data-question]"
export const CONFIRM = "[data-confirm]"
// a sensitive cell: the button that asks for the value, the mask, what
// a screen reader is told, and where the value goes
export const REVEAL = "[data-reveal]"
export const MASK = "[data-mask]"
export const MASKED = "[data-masked]"
export const SECRET = "[data-secret]"
// what a screen reader alone is told, not seen
export const UNSEEN = "[data-unseen]"
// a filter for several values: its button and its list
export const CHOICES_BUTTON = "[data-choices-button]"
export const CHOICES = "[data-choices]"

// ---- editors

// the control of an editor that the table gave its attributes
export const CONTROL = "[data-control]"
// the "Clear" of a sensitive cell's editor, and "Clear selection" in the
// line above the grid
export const CLEAR = "[data-clear]"
// the counter of a text
export const COUNT = "[data-count]"
// what a component's editor shows of its value besides its control
export const VALUE_TEXT = "[data-value-text]"
// the list editor of an array: the list, a value of it, adding and
// taking one away
export const LIST = "[data-list]"
export const ITEM = "[data-item]"
export const ADD = "[data-add]"
export const REMOVE = "[data-remove]"
// the entry of a field given value by value, which tells the server
export const OWN = "[data-own]"

// ---- above and around the grid

// the line above the grid with what is selected
export const SELECTION = "[data-selection]"
// its "Select all" the records the filters match, and the button of an
// action on the selected rows
export const SELECT_ALL = "[data-select-all]"
export const BULK = "[data-bulk]"
// the argument line's form
export const ARGUMENTS = "[data-arguments]"

// ---- the action panel and the picker

export const FIELD = "[data-field]"
export const CANCEL = "[data-cancel]"
export const ADD_GROUP = "[data-add-group]"
export const REMOVE_GROUP = "[data-remove-group]"
export const UNPICK = "[data-unpick]"
export const CLEAR_FIELD = "[data-clear-field]"
export const NONE = "[data-none]"
export const TAKE = "[data-take]"
// the page shown now, in the pagination
export const PAGE_NOW = "[aria-current=page]"
