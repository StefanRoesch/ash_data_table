# Keyboard and accessibility

Every table is an ARIA grid that can be used from the keyboard alone. After
reading this guide you know every key the table handles, how focus moves
through the filter row, the editors, the row actions and the action panel,
what is announced to assistive technology, how focus and the other states
are shown and what contrast they were measured at, and what has and has not
been tested.

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
- The controls around the grid are ordinary tab stops: the create button on
  the line of the table's name, where the table has one, the "Clear
  filters" button above the grid, while a filter applies, and the
  pagination buttons below it.
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
| Enter or F2, on the actions cell of a row | Goes to its first button. See [Row actions and the action panel](#row-actions-and-the-action-panel). |
| A character, on a filter cell or a cell that can be edited | Goes into the filter or starts editing, with that character typed. |
| Escape, on a cell whose save failed | Gives the failed edit up: the cell shows the saved value again. |
| Escape, on an actions cell that shows the message of a failed action | Gives the message up. |
| Space | Nothing. It is reserved for row selection, and it does not scroll the page. |

On macOS, Cmd works where the table says Ctrl. Key combinations with Alt are
left to the browser.

The header row and the filter row are rows of the grid. Both have a cell for
every column, including the columns that cannot be sorted or filtered, so
the arrow keys never skip a position. That includes the column of the
expanders and the "Actions" column, where a table has them: their filter
cells are empty.

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

## Row actions and the action panel

A table with row actions has a last column, "Actions", whose cell holds one
button per action. The cell is a cell of the grid like any other: the arrow
keys stop at it, and End reaches it. Its buttons are not tab stops. They
are reached from the cell, as a filter's controls are.

| Key | Where | Effect |
| --- | --- | --- |
| Enter, F2 | On an actions cell | Focus goes to its first button. |
| Left Arrow, Right Arrow | On a button | Move to the button before and after it. They do not leave the cell. |
| Enter, Space | On a button | Use it: the action runs, its question is asked, or its panel opens. |
| Escape | On a button | Returns to the cell. |
| Tab | On a button | Moves to the next button. Tab from the last one leaves the grid. |
| Escape | On an actions cell that shows a failure | Gives the message up. |

Space uses a button, as it does anywhere. On a **cell**, the actions cell
included, Space stays reserved for row selection and does nothing.

The **action panel** is a native `<dialog>` opened with `showModal()`, at
the right edge of the window. While it is open the rest of the page cannot
be reached, and the browser keeps focus inside it.

| Key | Effect |
| --- | --- |
| Tab, Shift+Tab | Move through the panel's fields and its two buttons. |
| Enter, in a field of one line | Runs the action, as "Run" does. In a text field of several lines it makes a new line. |
| Escape | Closes the panel, as "Cancel" does. Nothing runs. |

Where focus goes afterwards:

| After | Focus is |
| --- | --- |
| An action that ran straight away | Still on its button. The row is patched around it. |
| A destroy | On the actions cell of the row after the one that went, else of the row before it, else on the grid's first cell. |
| A create | On the first data cell of the new row, which is the first row of the page. |
| The panel closed with Cancel or Escape, or after its action ran | On the control that opened it. |
| A question answered with Cancel or Escape | On the button that asked. |

The **create button** is an ordinary button and a tab stop, before the
grid in the page's tab order. The create button of a nested table is on its
relationship line: see the next section.

What each action does is in
[Row actions and create](row-actions-and-create.md).

## Rows that expand

In a table whose rows expand, the first cell of every row holds the
expander: a button that says whether the row is expanded
(`aria-expanded`). An expanded row has, under it, one row per relationship
line, each a cell that spans the grid with a button of its own, and under an
open line a row whose one cell holds the nested table. All of them are cells
of the grid, which the arrow keys stop at. A line whose nested table lets
the person create has a second button after its label, such as "New
comment".

| Key | Where | Effect |
| --- | --- | --- |
| Left Arrow | On the first data cell of a row | Moves to the row's expander. Tab enters the grid one cell to its right. |
| Right Arrow | On an expander or a line that is closed | Opens it. On one that is open, moves on as on any cell. |
| Left Arrow | On an expander or a line that is open | Closes it, with everything open under it. |
| Enter | On an expander or a line | Opens or closes it. |
| F2 | On a line that has a create button | Goes to the line's controls: the button that opens and closes it, and the create button. Left Arrow and Right Arrow move between them; Enter uses one; Escape returns to the line. |
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
| The column of the row actions | A column of the grid, the last one, with the heading "Actions". It is counted in `aria-colcount` and `aria-colindex`. Each button is named by its action. |
| An action in progress | `aria-busy` on the row's actions cell. |
| An action that ran | The live region: "Archive: done"; after a create, "Task created". |
| An action that failed | The live region: "Archive failed: …". For an action that ran straight away, also `aria-invalid` on the row's actions cell, described by the message. |
| The action panel | A modal dialog named by its heading (`aria-labelledby`): "Reassign: Write the report", "New task". |
| A field of the panel | A label. A required field has `aria-required`, and the mark " \*" beside its label is hidden from assistive technology. A field with an error has `aria-invalid` and is described by the message. |
| What an action says that is about no field of its panel | An alert (`role="alert"`) above the fields. |
| The name of a table and its create button | Above the grid: the name as a heading of the page (`h1` on a mounted page), or as text where an embedded table is not told a heading level; the button named "New task". |
| A row that was added or taken away | The total (`aria-rowcount`) is one more or one less, and the rows after it are numbered again (`aria-rowindex`). |
| A failed or refused read | An alert (`role="alert"`) in place of the rows. |
| The pagination | A navigation landmark named after the table ("Pagination: Tasks"), buttons named "Go to page 3", and `aria-current="page"` on the current one. |

A successful save, a new sort and a new page are not announced in the live
region. Their result is in the grid itself. A row action and a create are
announced when they have run: a row that is gone, or one that appeared at
the top, is not where the person's focus was.

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

## How the states are shown

The table has no colours of its own and no setting for any. Everything
below is drawn in the semantic colours of the host's daisyUI theme, so it
follows the theme, light or dark.

| State | What a person sees |
| --- | --- |
| The focused cell | A solid ring of 2px, flush inside the cell, in the theme's text colour (`base-content`). Not in `primary`: a brand colour may be any lightness, and the text colour is the one a theme promises can be seen on its background. A cell keeps the ring while its editor has focus. |
| Focus in a control | A filter's input and menu, a button in a cell, the pagination buttons and the fields and buttons of the action panel and the dialog show daisyUI's own focus ring. It is in the text colour as well. |
| A cell whose save or action failed | A ring of 2px in the error colour mixed with the text colour, and a "!" at the end of the cell. The "!" is the mark that does not depend on a colour. Both are drawn by the cell's style: they do not change the row's height or the cell's width, and the cell's text stays where it is. The message is in a popover under the cell, in the text colour. |
| A failed cell that has focus | Both rings: the focus ring at the edge of the cell and the ring of the failure inside it, with the "!". |
| A cell whose save or action is on its way | Its text at 70% opacity. |
| A table that is reading | Its rows at 70% opacity. The header and the filters are not dimmed: they can be used meanwhile, and their text is muted already. |
| An input or a menu | An edge in the text colour at half strength, on the filters and on the fields of the action panel. daisyUI's own edge, at a fifth, does not show where an empty input is. |
| A rejected filter value, and a field of the panel with an error | The edge in the colour of a failed cell's ring, and the message under the control, in the text colour. The message is what says so without a colour. |

In **forced colours** (the contrast themes of Windows) the browser paints
with the system's colours and drops every fill and every shadow. Outlines,
borders and text stay, so the focus ring, the ring and the "!" of a failed
cell, the edges of inputs and buttons, and the dimming stay as well. Three
things are different there, and only there: the dialog and the action panel
have a border, since their shadow is gone; the current page is underlined,
since its fill is gone; and the triangle of an expander is told to keep its
two transparent sides, without which it would be a square that looks the
same open and closed.

### What was measured

Contrast was measured in Chromium, from the colours the browser computed for
each state and painted over what is behind them, in the demo's two themes,
which are those of a new Phoenix 1.8 application. The demo's browser tests
([`demo/e2e/contrast.spec.ts`](https://github.com/StefanRoesch/ash_table/blob/main/demo/e2e/contrast.spec.ts))
measure the same and hold each line at what WCAG 2 asks.

| | WCAG asks | Light | Dark |
| --- | --- | --- | --- |
| The focus ring against the cell (1.4.11) | 3:1 | 16.7:1 | 12.6:1 |
| The ring of a failed cell against the cell (1.4.11) | 3:1 | 7.1:1 | 4.6:1 |
| The "!" of a failed cell (1.4.1, 1.4.11) | 3:1 | 16.7:1 | 12.6:1 |
| The message of a failed cell, of a filter and of a field (1.4.3) | 4.5:1 | 16.7:1; a filter's 4.6:1 | 12.6:1; a filter's 5.6:1 |
| The text of a cell that is saving, and of the rows of a table that is reading (1.4.3) | 4.5:1 | 6.4:1 | 7.0:1 |
| The same on a row with the theme's second background (`base-200`) | 4.5:1 | 6.2:1 | 8.0:1 |
| The text of the header row and of the filters' controls, which daisyUI mutes (1.4.3) | 4.5:1 | 4.6:1 | 5.6:1 |
| The edge of an input or a menu (1.4.11) | 3:1 | 3.3:1 | 4.4:1 |
| The edge and the focus ring of an input that is `aria-invalid` (1.4.11) | 3:1 | 7.1:1 | 4.6:1 |

What these numbers do not cover:

- **Another theme.** The colours are the host's. The text colour is safe by
  daisyUI's own rule for a theme; the error colour is mixed with it for that
  reason. A theme whose `base-content` does not contrast with its `base-100`
  fails everywhere, not only in a table.
- **The labels of the coloured buttons.** "Run", "Create" and "Confirm" are
  daisyUI's `btn-primary`, and the button that deletes is `btn-error`: the
  theme's `primary-content` on `primary`, and `error-content` on `error`. In
  the demo's themes these pairs measure 2.75:1 (light) and 4.1:1 (dark) for
  `primary`, and 4.1:1 for `error`, which is less than the 4.5:1 that text
  needs. That is the theme's to put right, for every button of the
  application; the table does not recolour them.
- **Disabled buttons.** Previous and Next, when there is no such page, are
  1.5:1 and 1.75:1. WCAG leaves disabled controls out.
- **Focus Appearance (2.4.13, level AAA).** A solid ring of 2px inside the
  edge of the cell, 16.7:1 and 12.6:1 against the same cell without focus, is
  what that criterion describes as its smallest case. It was not tested as
  such and is not claimed.
- **`prefers-contrast: more`.** Nothing in the table or in daisyUI answers to
  it: the table looks the same with it.

## What has been tested, and what has not

The behaviour described in this guide is covered by the demo's browser tests
([`demo/e2e`](https://github.com/StefanRoesch/ash_table/tree/main/demo/e2e)):
scripted keyboard tests in Playwright, and automated checks with axe-core on
every demo table and in every state a table can be in (sorted, filtered,
empty, failed, with each editor open, with the dialog open, with a failed
cell, as each actor; with rows expanded and nested tables open to the
deepest level, on a page limited to the records of one parent, with
reference cells; with the actions column, a failed actions cell, the action
panel open, with errors and with the dialog on top of it, and with the
create button of a table and of a line).

The suite requires that axe reports no violation in any of them. The
landmarks around a table are the host page's and not the table's; see
[Layout and embedding](layout-and-embedding.md).

axe does not judge whether a focus ring can be seen, whether a state is shown
by more than a colour, or what is left in forced colours. Those are measured
by tests of their own, as [What was measured](#what-was-measured) says.

Two things about the action panel are covered more thinly than the rest: no
panel of the demo has a datetime field, and no action of the demo has both a
question and a panel, so that path is tested with a question put onto an
open panel by the test.

That is the whole of the verification, and its limits should be plain:

| | Status |
| --- | --- |
| Chromium, headless, keyboard scripted | Tested |
| axe-core, all of its default rules | Tested, in Chromium |
| Contrast of the focus ring, of a failed cell's ring and mark, of dimmed text and of the edges of inputs | Measured in Chromium, in the demo's light and dark theme. No other theme. |
| Forced colours | Tested as Chromium emulates them (`forced-colors: active`): that each state is still drawn. **Not tested** in a contrast theme of Windows itself. |
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
  whose save or action failed, in an editor, in a filter, on a button of a
  cell and in a nested table.
- **A cell whose save is on its way** cannot be opened until the server has
  answered.
- **The message of a failed cell** is a popover under the cell, shown while
  the cell has focus or the pointer. It does not change the row's height.
  The ring and the "!" of the cell are there all the time.
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
- **Expecting Tab to reach a row's buttons.** Move to the row's last cell
  and press Enter.
- **Expecting Enter on a relationship line to reach its create button.**
  Enter opens and closes the line. F2 goes to its controls.
- **Expecting a filter to be a tab stop.** Move to its cell and press Enter.
- **Treating "axe reports no violations" as "accessible".** See the table
  above.
- **A theme whose colours do not contrast.** The table draws with the
  theme's colours. See [What was measured](#what-was-measured) for what
  that leaves to the theme.

## Not in the first version

No row selection, no keyboard shortcuts of the host's choosing, and no
tested screen reader support. The roadmap is in the
[specification](https://github.com/StefanRoesch/ash_table/issues/21).
