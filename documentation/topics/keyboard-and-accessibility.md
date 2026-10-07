# Keyboard and accessibility

Every table is an ARIA grid that can be used from the keyboard alone. After
reading this guide you know every key the table handles, how focus moves
through the filter row and the editors, what is announced to assistive
technology, and what has and has not been tested.

A note on words: this guide says "grid" for the element with `role="grid"`
and for the ARIA pattern it follows. Everywhere else the thing is a table.

## The smallest example

There is nothing to declare. The keyboard is handled in the browser by
JavaScript hooks that ship with the library, so the only requirement is that
they are registered, which is one import. In the demo
([`demo/assets/js/app.js`](https://github.com/StefanRoesch/ash_table/blob/main/demo/assets/js/app.js)):

<!-- source: demo/assets/js/app.js -->
```js
import {hooks as ashTableHooks} from "phoenix-colocated/ash_table"
// ...
  hooks: {...colocatedHooks, ...ashTableHooks},
```

(The line `// ...` stands for the lines between the import and the
`LiveSocket`'s options.)

**Try it:** `/tasks` in the demo, as Ada Admin. Press Tab until a cell has
the focus ring, then use the arrow keys.

## The grid is one tab stop

Tab moves focus into the grid and Tab moves it out again. Inside, the arrow
keys move. A table of 25 rows and 17 columns is one stop in the page's tab
order, not 425.

- Exactly one cell is in the tab order at any time. At first it is the first
  cell of the first row of records.
- The cell a person moved to is the one Tab returns to.
- The controls around the grid are ordinary tab stops: the "Clear filters"
  button above it, while a filter applies, and the pagination buttons below
  it.
- Moving about never contacts the server.
- Where rows expand into nested tables, the first cell of a row is its
  expander, and a nested table is a grid of its own inside a cell: the whole
  tree of grids is one tab stop. See [Rows that expand](#rows-that-expand).

## Keys on a cell

| Key | Effect |
| --- | --- |
| Arrow keys | Move one cell. They do not wrap at the end of a row or of the grid. |
| Up Arrow, from the first row of records | Moves to the filter row, then to the header row, and stops there. |
| Home, End | First and last cell of the row. |
| Ctrl+Home | First cell of the first row of records. |
| Ctrl+End | Last cell of the last row. |
| Page Down, Page Up | Move by a screenful of rows. Page Up stops at the first row of records and does not enter the header rows. |
| Tab, Shift+Tab | Leave the grid, forwards or backwards. |
| Enter, on the heading of a sortable column | Sorts by the column: ascending, descending, none. Focus stays on the heading. |
| Enter or F2, on a filter cell | Goes into the filter. |
| Enter or F2, on a cell that can be edited | Starts editing. On a boolean cell, toggles the value and saves. |
| A character, on a filter cell or a cell that can be edited | Goes into the filter or starts editing, with that character typed. |
| Escape, on a cell whose save failed | Gives the failed edit up: the cell shows the saved value again. |
| Space | Nothing. It is reserved for row selection, and it does not scroll the page. |

On macOS, Cmd works where the table says Ctrl. Key combinations with Alt are
left to the browser.

The header row and the filter row are rows of the grid. Both have a cell for
every column, including the columns that cannot be sorted or filtered, so
the arrow keys never skip a position.

With the pointer: a click moves focus to a cell, a click on a sortable
heading sorts, and a double click on an editable cell starts editing.

## The filter row from the keyboard

A filter's controls are not tab stops. They are reached from their cell:

| Key | Where | Effect |
| --- | --- | --- |
| Enter, F2 | On a filter cell | Focus goes to the filter's value: the input, or the menu of a choice. An existing text or number is selected. A filter whose operator takes no value has only its operator menu to go to. |
| A character | On a filter cell | The same, and the character is typed there: over the text or number, into the first part of a date, or to the first choice that starts with it, which applies at once. |
| Arrow keys, Home, End | In a filter's control | Belong to the control. They do not move through the grid. |
| Enter | In a filter's input | Applies what was typed. Focus stays in the input. |
| Escape | In a filter's control | Gives up what was typed and not yet applied, and returns to the cell. |
| Tab, Shift+Tab | In a filter's control | Move through the controls of this one filter: the operator menu, the value, the clear button. Tab from the last one leaves the grid. Shift+Tab from the first one returns to the cell. |

After a filter is cleared with its own button, focus goes to its cell. After
"Clear filters", focus goes to the grid's current cell. In both cases the
button that had focus is gone, and focus is not left on nothing.

When a filter applies and what it matches is in [Filtering](filtering.md).

## Editors from the keyboard

Which key starts an edit, and what the typed character does, depends on the
cell's type:

| Cell type | Enter or F2 | A character |
| --- | --- | --- |
| text | Opens the editor with the text selected. | Opens the editor and replaces the text with the character. |
| number | Opens the editor with the number selected. | Replaces the number, if the input takes the character. A letter opens the editor and leaves the number as it was. |
| date, datetime | Opens the editor with its value. | Opens the editor and keeps the value; a digit goes into the input's first part. |
| enum | Opens the menu at the cell's value. | Opens the menu at the first value that starts with the character. Nothing is saved by that alone. |
| boolean | Toggles the value and saves. | Nothing. |

While a cell is being edited:

| Key | Effect |
| --- | --- |
| Enter | Saves. Focus stays on the cell. |
| Shift+Enter, in text | A new line. |
| Escape | Gives the edit up. In an open menu, Escape closes the menu first. |
| Tab, Shift+Tab | Save and leave the grid, forwards or backwards. Tab does not move to the next cell. |
| Arrow keys, Home, End | Belong to the editor. |

What saving does, and what a failed save looks like, is in
[Inline editing](inline-editing.md). The dialog of a column with a question
is in [Confirm](confirm.md).

## Rows that expand

In a table whose rows expand, the first cell of every row holds the
expander: a button that says whether the row is expanded
(`aria-expanded`). An expanded row has, under it, one row per relationship
line, each a cell that spans the grid with a button of its own, and under an
open line a row whose one cell holds the nested table. All of them are cells
of the grid, which the arrow keys stop at.

| Key | Where | Effect |
| --- | --- | --- |
| Left Arrow | On the first data cell of a row | Moves to the row's expander. Tab enters the grid one cell to its right. |
| Right Arrow | On an expander or a line that is closed | Opens it. On one that is open, moves on as on any cell. |
| Left Arrow | On an expander or a line that is open | Closes it, with everything open under it. |
| Enter | On an expander or a line | Opens or closes it. |
| Down Arrow, Up Arrow | | Go through the lines and the nested tables' cells as through rows, keeping the column for the rows below them. |
| Enter, F2 | On the cell that holds a nested table | Goes into the nested table: to the cell that was left last, or to its first data cell. |
| Escape | On a cell of a nested table | Comes back out, to the cell that holds it. |
| Enter, F2 | On the cell of a nested table's pages, a row at the end of its grid | Goes to its buttons. Left Arrow and Right Arrow move between them; Enter uses one; Escape returns to the cell. |
| Enter, F2 | On the cell of the link "Open in full view", the last row of a nested table's grid | Follows the link, as a click does. |

A nested table is a grid of its own, with its own header row and filter row,
and inside it every key of this guide works as on a page. Three things differ
from a table of its own, so that the whole tree stays one tab stop:

- Its pages are a group in a row of its grid, and not a landmark after it.
- Its link to the full view is a row of its grid.
- Its "Clear filters" button is not in the tab order and not reached from
  the keyboard. Each filter is cleared from its own cell.

On the page a nested table's link leads to, the heading that says what the
table is limited to and the control "Show all records" are ordinary content
above the grid: a heading and a link, both in the page's tab order.

When a line or a row is closed while focus is in something under it, focus
goes to the line, or to the row's expander. What a nested table is, and what
the lines offer, is in [Nested tables](nested-tables.md).

## Focus after the page changes

The rows of a table are replaced whenever it sorts, filters or changes page,
and a row is replaced when one of its cells is saved. After every such
change the grid restores its single tab stop and, if it had focus, the
focus:

- to the same cell, if that cell is still on the page;
- otherwise to the cell at the same position.

A cell that is being edited is protected from these changes, so what is typed
survives a save of another cell in the same row.

The pagination buttons keep focus in the same way. After a page change, focus
is on the button that was used: Previous, Next or a page number. When that
button can no longer take it, because Next has reached the last page or
Previous the first and is disabled now, focus goes

- on an offset table, to the button of the page now shown (the one marked
  `aria-current="page"`);
- on a keyset table, which has no page numbers, to the other of Previous and
  Next.

When the pagination itself goes away, with a read that failed, focus goes to
the grid's tab stop. Focus is kept as well when the page that is left had no
records, as a page beyond the last has: Previous there leads to the last
page and keeps the focus.

## What assistive technology is told

| What | How |
| --- | --- |
| The grid and its name | `role="grid"` with `aria-label`: the table's name, such as "Tasks". |
| Size and position | `aria-rowcount` (the total when the table knows it, counting the two header rows; else `-1`), `aria-colcount`, `aria-rowindex` on every row, `aria-colindex` on every cell. Under offset pagination the row numbers run through all pages; under keyset pagination they do not (see below). |
| Sort | `aria-sort` on every sortable heading: `ascending`, `descending` or `none`. |
| A read in progress | `aria-busy` on the grid. The previous rows stay. |
| A filter's controls | An accessible name each: "Filter Title", "How to filter Title", "Clear the Title filter". |
| A rejected filter value | `aria-invalid` on the input, described by "Not a valid value". |
| The result of a filter change | A polite live region: "12 results", or "Results updated" when the table has no total. |
| A boolean cell | A mark that is hidden from assistive technology, and the text "Yes" or "No". |
| A cell hidden from the person by a field policy | The text "Not available", for screen readers only. |
| The expander of a row, and the button of a line | `aria-expanded`. The expanders, and the heading of their column, are named "Related records"; a line is named by its relationship. The expanders are a column of the grid, counted in `aria-colcount` and `aria-colindex`. |
| A nested table | A grid of its own, named by its line and by the first cell of the row it belongs to (`aria-labelledby`): "Comments Write the report". |
| A nested table whose first rows are on their way | The text "Loading…", and `aria-busy` on its grid. |
| The pages of a nested table | A group (`role="group"`) named "Pagination: Comments", in place of the landmark. |
| The link to the full view | A link named "Open in full view: Comments": its text and the nested table's name. |
| A table limited to the records of one parent | A heading above the grid: the parent and the relationship, "Write the report: Comments". |
| Cells that cannot be edited | `aria-readonly`, on a table that offers the person any editing. |
| A save in progress | `aria-busy` on the cell. |
| A failed save | `aria-invalid` on the cell, described by the action's message, and the same live region: "Title was not saved: …". |
| A failed or refused read | An alert (`role="alert"`) in place of the rows. |
| The pagination | A navigation landmark named after the table ("Pagination: Tasks"), buttons named "Go to page 3", and `aria-current="page"` on the current one. |

A successful save, a new sort and a new page are not announced in the live
region. Their result is in the grid itself.

### Row numbers under keyset pagination

The table knows the total (`aria-rowcount`) whenever the read action is
`countable`. It knows a row's place in that total (`aria-rowindex`) only
under offset pagination, where the page number says how many records come
before. A keyset page starts at a cursor and has no such number.

ARIA has no value for "position unknown": `aria-rowindex` has to be a whole
number from 1 up that grows from row to row and does not exceed the row
count, and where it is left out, the browser counts the rows that are in the
page, which comes to the same. So on a keyset table the rows of every page
are numbered from the top of that page: 3 for the first row of records,
after the two header rows. On the first page that is the row's true place.
On a later page it is not: what a screen reader may announce there as the
third row of the table is the third row of the page. The total is true on
every page.

## What has been tested, and what has not

The behaviour described in this guide is covered by the demo's browser tests
([`demo/e2e`](https://github.com/StefanRoesch/ash_table/tree/main/demo/e2e)):
scripted keyboard tests in Playwright, and automated checks with axe-core on
every demo table and in every state a table can be in (sorted, filtered,
empty, failed, with each editor open, with the dialog open, with a failed
cell, as each actor; with rows expanded and nested tables open to the
deepest level, on a page limited to the records of one parent, and with
reference cells).

The suite requires that axe reports no violation in any of them. The
landmarks around a table are the host page's and not the table's; see
[Layout and embedding](layout-and-embedding.md).

That is the whole of the verification, and its limits should be plain:

| | Status |
| --- | --- |
| Chromium, headless, keyboard scripted | Tested |
| axe-core, all of its default rules | Tested, in Chromium |
| A screen reader (NVDA, JAWS, VoiceOver, TalkBack) | **Not tested.** No screen reader has been tried. This includes how a grid inside a cell of a grid is announced, which the ARIA grid pattern does not describe. |
| Firefox | **Not tested** |
| Safari | **Not tested** |
| Touch devices | **Not tested** |

An automated checker finds markup that is wrong. It cannot tell whether a
table is pleasant, or even workable, with a screen reader. The ARIA
attributes above are what the grid pattern prescribes; how each screen
reader reads them is unverified. If you use the table with assistive
technology, a report of what you find is welcome in the
[issue tracker](https://github.com/StefanRoesch/ash_table/issues).

## Edge cases

- **A table without records** still has its two header rows. The tab stop is
  then the filter cell of the first column.
- **A closed choice menu.** In an enum editor whose menu is closed, the arrow
  keys change the value step by step without saving. Enter, or leaving the
  cell, saves the value reached.
- **Escape on an ordinary cell** does nothing. It is only handled on a cell
  whose save failed, in an editor and in a filter.
- **A cell whose save is on its way** cannot be opened until the server has
  answered.
- **The message of a failed cell** is a popover under the cell, shown while
  the cell has focus or the pointer. It does not change the row's height.
- **Long text is cut off** to keep rows one line high. The whole value is in
  the cell for assistive technology, and in the editor.
- **A mounted table brings no main landmark.** Its page is a heading and the
  table; `<main>` has to come from your layouts. See
  [Layout and embedding](layout-and-embedding.md).

## Things people trip over

- **The arrow keys do nothing.** The hooks are not registered, or the assets
  were built before the dependency was compiled. See the
  [tutorial](../tutorials/get-started-with-ash-table.md#1-install).
- **Expecting Tab to move to the next cell.** Tab leaves the grid; this is
  the ARIA grid pattern. Arrow keys move between cells.
- **Expecting Space to toggle a boolean.** Enter and F2 do. Space is held
  back for row selection.
- **Expecting a filter to be a tab stop.** Move to its cell and press Enter.
- **Treating "axe reports no violations" as "accessible".** See the table
  above.

## Not in the first version

No row selection, no keyboard shortcuts of the host's choosing, and no
tested screen reader support. The roadmap is in the
[specification](https://github.com/StefanRoesch/ash_table/issues/21).
