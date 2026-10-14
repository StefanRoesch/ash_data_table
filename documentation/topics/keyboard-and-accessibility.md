# Keyboard and accessibility

Every table is an ARIA grid that can be used from the keyboard alone. After
reading this guide you know every key the table handles, how focus moves
through the filter row, the editors, the row actions and the action panel,
how rows are selected, what is announced to assistive technology, how focus and the other states
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
  the line of the table's name, where the table has one, and the buttons of
  its [table actions](table-actions.md) after it, the inputs of the
  [argument line](arguments.md), where the table has arguments, the buttons
  of the line above the grid ("Clear selection" and the bulk actions, while rows
  are selected, "Clear filters", while a filter applies, and "Columns"), and the
  pagination buttons below it.
- Moving about never contacts the server. Neither does selecting rows.
- Where rows can be selected, the first cell of a row holds its box; where
  rows expand into nested tables, the next cell is the row's expander. Tab
  enters the grid on the first column of the table, to the right of both.
  A nested table is a grid of its own inside a cell: the whole tree of grids
  is one tab stop. See [Selecting rows](#selecting-rows) and
  [Rows that expand](#rows-that-expand).

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
| F2, on the heading of a column | Goes to the handle that changes the column's width. See [Column widths from the keyboard](#column-widths-from-the-keyboard). |
| Enter or F2, on a filter cell | Goes into the filter. |
| Enter or F2, on a cell that can be edited | Starts editing. On a boolean cell, toggles the value and saves. On a reference cell, opens the picker: see [Choosing a related record](choosing-a-related-record.md#the-keyboard). |
| Enter or F2, on the actions cell of a row | Goes to its first button. See [Row actions and the action panel](#row-actions-and-the-action-panel). |
| Shift+Enter, on a cell of a sensitive column | Shows the cell's value, and hides it again. Escape hides it too, and so does leaving the cell. See [Sensitive columns](sensitive-columns.md#showing-a-value). |
| A character, on a filter cell or a cell that can be edited | Goes into the filter or starts editing, with that character typed. |
| Escape, on a cell whose save failed | Gives the failed edit up: the cell shows the saved value again. |
| Escape, on an actions cell that shows the message of a failed action | Gives the message up. |
| Space, on a cell of a row of records | Where rows can be selected: selects the row, or takes it out of the selection. Anywhere else nothing, and it does not scroll the page. |
| Shift+Down Arrow, Shift+Up Arrow, on a cell of a row of records | Where rows can be selected: move to the next or previous row and select as they go. See [Selecting rows](#selecting-rows). |

On macOS, Cmd works where the table says Ctrl. Key combinations with Alt are
left to the browser.

The header row and the filter row are rows of the grid. Both have a cell for
every column, including the columns that cannot be sorted or filtered, so
the arrow keys never skip a position. That includes the column of the
boxes that select a row, the column of the expanders and the "Actions"
column, where a table has them: their filter cells are empty.

With the pointer: a click moves focus to a cell, a click on a sortable
heading sorts, and a double click on an editable cell starts editing.

## Scrolling

Every table scrolls sideways in an area of its own (see
[Layout and embedding](layout-and-embedding.md#scrolling-sideways)). From the
keyboard there is nothing to scroll by hand: a table scrolls with the focus.

- **A cell that the arrow keys, Home, End, Page Up, Page Down or Tab move
  focus to is brought into view whole**, in the area of its own table. In a
  nested table that is the nested table's area: the table around it does not
  move.
- **Never under what stays in view.** In a table with
  [`sticky_label?`](columns-and-defaults.md#keeping-the-label-column-in-view)
  the cell is brought out from under the label column, and it is kept above
  the scrollbar at the bottom edge of the window (WCAG 2.2, "Focus Not
  Obscured").
- **The cells that stay are cells like the others.** They keep their place
  in the row for the arrow keys and for a screen reader; only where they are
  drawn changes. Focus on one of them does not scroll the table: Home on a
  row that is scrolled far to the right moves focus to the row's first cell,
  which is in view, and the table scrolls back when focus moves on into the
  columns.
- **An area that scrolls is no tab stop.** Some browsers make one of every
  element that scrolls; the grids are taken out of the tab order
  (`tabindex="-1"`), so that the tree of grids stays one stop.
- **The scrollbar at the bottom edge of the window is for the pointer**: no
  tab stop, and hidden from assistive technology (`aria-hidden`).
- **Focus that a patch puts back is not scrolled to.** When a person has
  scrolled the focused cell out of view with the wheel and a live update
  renders its row again, the table stays where they scrolled it.

## Column widths from the keyboard

The heading of every column ends in a handle that changes the column's
width. It is not a stop of the arrow keys or of Tab. It is reached from its
heading:

| Key | Where | Effect |
| --- | --- | --- |
| F2 | On the heading of a column | Focus goes to the handle. |
| Right Arrow, Left Arrow | On the handle | Make the column 10 pixels wider or narrower. Where text runs from right to left, the other way round. |
| Home, End | On the handle | Make the column as narrow (48 pixels) and as wide (1000 pixels) as it can be. |
| Enter | On the handle | Gives the column the width it had before any width was changed. |
| Escape | On the handle | Returns to the heading. The width stays. |
| Up Arrow, Down Arrow, Page Up, Page Down, Space | On the handle | Nothing. They do not move through the grid or scroll the page. |
| Tab, Shift+Tab | On the handle | Tab leaves the grid. Shift+Tab returns to the heading. |

Enter on a heading still sorts; that is why the handle is on F2. The handle
that has focus shows a ring and a line at the column's edge.

With the pointer the handle is dragged, and a double click on it does what
Enter does. A click or a drag on the handle never sorts. What a width does
to the table, and how long it lasts, is in
[Columns and defaults](columns-and-defaults.md#column-widths).

ARIA has no pattern for changing a column's width in a grid. The handle
follows the nearest one, the
[window splitter](https://www.w3.org/WAI/ARIA/apg/patterns/windowsplitter/):
a separator that takes focus and is moved with the arrow keys. It sits
inside the heading and is reached with F2, as the controls of a filter
cell and of an actions cell are reached from their cell, so the grid stays
one tab stop.

## Hiding columns from the keyboard

"Columns", above the grid, is an ordinary button and a tab stop. It opens a
list with a box per column; a column whose box is not ticked is hidden.
What hiding does and does not do is in
[Columns and defaults](columns-and-defaults.md#hiding-columns).

| Key | Where | Effect |
| --- | --- | --- |
| Enter, Space | On "Columns" | Opens the list, or closes it. Focus stays on the button. |
| Tab, Shift+Tab | On "Columns", with the list open | Tab goes to the first box, and on through the boxes. |
| Space | On a box | Hides the column, or shows it again. The list stays open. |
| Escape | On the button or in the list | Closes the list. Focus goes to the button. In a picker, the picker stays open. |
| Tab | On the last box | Leaves the list, which closes. |

A click anywhere outside the list closes it as well.

In the grid, hidden columns are passed over:

- Left and Right Arrow go to the next column that is shown. Home and End go
  to the first and the last cell of the row that are shown.
- A hidden cell never has focus and is never the tab stop. When the column
  of the focused cell, or of the tab stop, is hidden, the next cell to the
  right that is shown takes its place; where there is none, the next to the
  left.

It is a disclosure: a button with `aria-expanded` and `aria-controls`, and
a group of labelled checkboxes named "Columns". It is not an ARIA menu. The
button's text says how many columns are hidden, and how many of them the
rows are filtered or sorted by: "Columns (2 hidden, 1 filtered)". Hiding
or showing a column is read out once, politely: "Progress hidden",
"Progress shown".

A hidden column is not told to a screen reader: its cells are not
displayed. The cells that are shown keep their `aria-colindex`, and the
table keeps its `aria-colcount`, so column 5 of 12 is still announced as
column 5 of 12 when column 4 is hidden. That is what ARIA has these two
attributes for: a grid of which
[not every column is there](https://www.w3.org/WAI/ARIA/apg/practices/grid-and-table-properties/).

The "Columns" button of a nested table is a tab stop of its own, inside the
grid around it: there is no other way to its list from the keyboard.

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

## The argument line from the keyboard

The inputs of the [argument line](arguments.md) stand before the grid and
are ordinary tab stops, each with its label. The keys in them are the
browser's.

| Key | Where | Effect |
| --- | --- | --- |
| Tab, Shift+Tab | Anywhere on the line | To the next and the previous input, and from the last one into the grid. Leaving an input applies what was typed in it. |
| Enter | In an input | Applies what the line holds now. Focus stays in the input. |
| Space | On a box | Ticks it, which applies at once. So does a choice from a menu. |
| Enter, Space | On "Add value" of a list | Adds a row for one more value, and focus goes into it. |
| Enter, Space | On the button after a value of a list | Takes the value away. Focus goes to the value that stands in its place, else to the one before it, else to "Add value". |

Typing sends nothing, and neither do the arrow keys in the grid afterwards.

A nested table's argument line is inside the cell that holds the nested
table, above its grid, and its inputs are ordinary tab stops as well: Tab
from a cell of the grid around it passes through them on its way out of the
grid, where they come after that cell in the page. They are the one thing
inside a grid, besides the buttons of a nested table's selected rows, that
Tab stops at. In a picker the line is above the picker's table.

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
| array of enum values (multiple choice) | Opens the list of boxes, with focus on the first. | Opens the list, with focus on the first choice that starts with the character. Nothing is ticked by that alone. |
| array of text or of numbers | Opens the list of values, with focus in the first and its text selected; on the button "Add value" when there is none. | Opens the list and starts a new value with the character, after the others. A character a number does not take adds nothing. |
| array of dates, datetimes or booleans | As above. | Opens the list, as Enter does. |
| a value made of fields: an embedded resource, a map, an array of either | Opens the side panel, with focus in the value's first field. | Nothing. |
| a union | Opens the side panel, with focus on the choice of its kind. | Nothing. |
| The editor of a column's component, with a control that is typed into (text, a number) | Opens the editor with its value selected. | As text and number above. |
| The editor of a column's component, with any other control (a slider, a menu, a date) | Opens the editor with its value. | Opens the editor and keeps the value; the key goes on to the control, which does with it what it does. A slider takes no characters. |

While a cell is being edited:

| Key | Effect |
| --- | --- |
| Enter | Saves. Focus stays on the cell. |
| Shift+Enter, in text | A new line. |
| Escape | Gives the edit up. In an open menu, Escape closes the menu first. |
| Tab, Shift+Tab | Save and leave the grid, forwards or backwards. Tab does not move to the next cell. |
| Arrow keys, Home, End, Page Up, Page Down | Belong to the editor: in a slider they move it. |
| Tab, in the editor of a sensitive cell that has "Clear" | Goes from the input to the button "Clear", without saving. Enter or Space there empties the cell; Shift+Tab goes back to the input; Tab from the button saves what was typed and leaves the grid. See [Sensitive columns](sensitive-columns.md#emptying-a-value). |

**The editor of an array** has several controls in one cell: the boxes of a
multiple choice, or a control and a button per value and the button that
adds one. It is one editor all the same, and the two keys of the grid work
from wherever in it the focus is:

| Key | In the editor of an array |
| --- | --- |
| Enter | Saves the whole list. Focus goes back to the cell. On a button it uses the button: "Add value" adds a value and puts focus in it, a value's button takes the value away. |
| Shift+Enter, in a value that is text | A new line. |
| Escape | Gives up everything done since the editor opened. Focus goes back to the cell. |
| Space | Ticks or unticks the box that has focus; uses the button that has focus. Nothing is saved by it. |
| Down Arrow, Up Arrow | In a multiple choice, move from box to box, and stop at the first and the last. In a list of values they belong to the value's control. |
| Tab, Shift+Tab | Move through the controls of the editor. Tab from the last one, and Shift+Tab from the first, save and leave the grid, as from any editor. |

When a value is taken away, focus goes to the value after it, else to the
one before it, else to "Add value". The controls are named by their place:
"Tags 1", "Tags 2", "Remove Tags 2". The names follow when a value is added
or taken away.

**A value made of fields** is edited in the side panel, not in the cell.
The panel is the [action panel](#row-actions-and-the-action-panel), and its
keys are the panel's: Tab goes through the fields in their order, Escape
closes it without saving, and focus comes back to the cell either way. The
value is a group named by the column, a value inside it a group in the
group, and each value of an array a group named by its place ("Milestones
2"). The buttons that add a value and take one away are tab stops among
the fields; when the server has added a group, focus is in its first field,
and when one is gone, on what stands in its place: the value after it, the
one before it, or "Add value". See
[Maps and embedded resources](maps-and-embedded-resources.md#editing-in-the-side-panel).

**A union** is edited in the side panel too. Its group is named by the
column and starts with "Kind", a menu of the union's kinds, which has the
focus when the panel opens. Up and Down Arrow choose another kind, as in
any menu; the server then puts that kind's fields under the menu, and
focus stays on the menu. Tab goes on into the fields of the kind. See
[Unions](unions.md#editing-in-the-side-panel).

An editor of a component that saves when its value changes, such as the
slider of "Progress" on `/tasks`, saves a change made with the pointer at
once and stays open. A step made with these keys is not yet a choice, as in
a menu: Enter or leaving the cell saves it, and Escape gives it up. Escape
never takes back what was saved. See
[Custom components](custom-components.md#the-keyboard).

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
included, Space selects the row.

The **action panel** is a native `<dialog>` opened with `showModal()`, at
the right edge of the window. While it is open the rest of the page cannot
be reached, and the browser keeps focus inside it.

| Key | Effect |
| --- | --- |
| Tab, Shift+Tab | Move through the panel's fields and its two buttons. |
| Enter or Space, on the button "Choose" of a field that holds the key of a related record | Opens the picker, a second modal dialog on top of the panel. Escape there closes the picker alone, and focus is on the button again. |
| Enter or Space, on the button "✕" of a record in a field that holds several related records | Takes the record out of the field's list. Focus goes to the button of the record that stands in its place, else to the one before it, else to "Choose". See [Relationships an action manages](managing-relationships.md#the-keyboard-and-what-assistive-technology-is-told). |
| Enter or Space, on the button "Clear" under a sensitive field | Notes that the field is to be emptied when the action runs: the field says "Will be cleared.", the button says "Keep", and focus stays on it. Once more takes it back. See [Sensitive columns](sensitive-columns.md#emptying-a-value). |
| Enter, in a field of one line | Runs the action, as "Run" does. In a text field of several lines it makes a new line. |
| Enter or Space, on the file input of an argument that takes a file | Opens the browser's file dialog. The file is sent when the action is run. See [Files](files.md#the-field). |
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
grid in the page's tab order. So are the buttons of a table's **table
actions**, which stand after it: Enter and Space use one, focus stays on it
when its action has run, and comes back to it from its question and from
its panel. The create button of a nested table, and the buttons of its
table actions, are on its relationship line: see the next section.

What each action does is in
[Row actions and create](row-actions-and-create.md).

## Selecting rows

A table with a row action that runs on several rows has a first column of
boxes, one per row and one in the header for the rows of the page. The
boxes are not tab stops; their cells are cells of the grid.

| Key | Where | Effect |
| --- | --- | --- |
| Space | On any cell of a row of records | Selects the row, or takes it out of the selection. |
| Space | On the cell of the box in the header | Selects every row of the page; when all are selected, takes them out. |
| Shift+Down Arrow, Shift+Up Arrow | On a cell of a row of records | Move to the next or the previous row of records, in the same column, and select the rows from where the key was first pressed to where focus is. Going back takes rows out again. What is open under a row is passed over. |
| Shift+Tab | On a cell | Leaves the grid backwards. While rows are selected, the buttons of the line above the grid are what comes before it: the bulk actions, "Clear selection", and "Select all … that match" when it is offered. |
| Enter, Space | On a button of that line | Uses it. |

Space belongs to the grid while focus is on a cell, and to a control once
focus is in one: on a button it uses the button, in an editor or a filter
it types. A boolean cell is toggled with Enter or F2, never with Space,
which selects its row.

With the pointer: a click on a box, or beside it in its cell, selects the
row or takes it out; Shift and a click anywhere on a row selects from the
row that was selected or clicked last to this one.

Where focus goes afterwards:

| After | Focus is |
| --- | --- |
| The question of a bulk action answered with Cancel or Escape | On the button that asked. |
| A bulk action that left rows selected | On the button that was used. |
| A bulk action that left nothing selected, and "Clear selection" | On the grid's current cell: the buttons are gone. |
| "Select all … that match" | On "Clear selection": the button that was used is gone. |

What a selection is, how long it lasts and what runs on it is in
[Selecting rows and bulk actions](selecting-rows-and-bulk-actions.md).

## Rows that expand

In a table whose rows expand, the first cell of every row holds the
expander, after the row's box where rows can be selected: a button that
says whether the row is expanded
(`aria-expanded`). An expanded row has, under it, one row per relationship
line, each a cell that spans the grid with a button of its own, and under an
open line a row whose one cell holds the nested table. All of them are cells
of the grid, which the arrow keys stop at. A line whose nested table lets
the person create has a second button after its label, such as "New
comment".

| Key | Where | Effect |
| --- | --- | --- |
| Left Arrow | On the first data cell of a row | Moves to the row's expander, and from there to the row's box, where rows can be selected. Tab enters the grid on the first data cell. |
| Right Arrow | On an expander or a line that is closed | Opens it. On one that is open, moves on as on any cell. |
| Left Arrow | On an expander or a line that is open | Closes it, with everything open under it. |
| Enter | On an expander or a line | Opens or closes it. |
| F2 | On a line that has a create button, or the buttons of table actions | Goes to the line's controls: the button that opens and closes it, the create button, and the buttons of the nested table's table actions. Left Arrow and Right Arrow move between them; Enter uses one; Escape returns to the line. |
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

One thing is a tab stop inside the tree all the same: the buttons of a
nested table's line above its grid, while that nested table has rows
selected. They are there only then, and have to be reached.

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
| The handle of a column's width | `role="separator"` with `aria-orientation="vertical"`, named "Resize Title". `aria-valuenow` is the column's width in pixels, between `aria-valuemin` (48) and `aria-valuemax` (1000). The heading has its column's label as `aria-label`, so the handle's name is not read as part of it. |
| A read in progress | `aria-busy` on the grid. The previous rows stay. |
| A filter's controls | An accessible name each: "Filter Title", "How to filter Title", "Clear the Title filter". |
| A rejected filter value | `aria-invalid` on the input, described by "Not a valid value". |
| An argument's input | A `<label>` for it: the argument's name, and for one a column asks for the column's label before it ("Due within: Days"). An argument of several controls (a multiple choice, a list) is a `role="group"` named by that label, and each value of a list is called by its place ("Tags 2"). `aria-required` where the argument cannot be empty. |
| An argument's value that Ash refused | `aria-invalid` on the input, described by the action's message, which is also read out through the live region with the input's label. |
| An argument the read action requires, while it is empty | "Fill in Due by to see records." in place of the rows, read out through the live region. The grid has its header rows only. |
| The result of a filter change | A polite live region: "12 results", or "Results updated" when the table has no total. |
| A boolean cell | A mark that is hidden from assistive technology, and the text "Yes" or "No". |
| An array cell | Its values as text, separated by commas. |
| A value of an array that the action refused | The message names it as its control is named ("Tags 2: …"). In the list of values, in a cell that is opened again and in the action panel, that control has `aria-invalid`. |
| The editor of an array, in a cell and in the action panel | A group (`role="group"`) named by the column. In a multiple choice each box is named by its choice; in a list each value's control is named by the column and its place ("Tags 2"), and its button "Remove Tags 2". The button that adds a value says "Add value". |
| A cell hidden from the person by a field policy | The text "Not available", for screen readers only. |
| The expander of a row, and the button of a line | `aria-expanded`. The expanders, and the heading of their column, are named "Related records"; a line is named by its relationship. The expanders are a column of the grid, counted in `aria-colcount` and `aria-colindex`. |
| A nested table | A grid of its own, named by its line and by the first data cell of the row it belongs to (`aria-labelledby`): "Comments Write the report". |
| A nested table whose first rows are on their way | The text "Loading…", and `aria-busy` on its grid. |
| The pages of a nested table | A group (`role="group"`) named "Pagination: Comments", in place of the landmark. |
| The link to the full view | A link named "Open in full view: Comments": its text and the nested table's name. |
| A table limited to the records of one parent | A heading above the grid: the parent and the relationship, "Write the report: Comments". |
| Cells that cannot be edited | `aria-readonly`, on a table that offers the person any editing. |
| The editor of a cell | Named by its column. `aria-required` where the column's action cannot take the cell empty; not on a box, on the group of an array, or on the editor of a sensitive cell, which saves nothing when left empty. |
| The limits of a number | `min`, `max` and `step` on the number input of a cell's editor, of a field of the action panel and of the argument line, from the resource's constraints: the browser passes them on as the least and the greatest value of the input. Nothing is checked against them in the browser. See [Inline editing](inline-editing.md#limits-an-editor-shows-before-saving). |
| The length of a text | A text with a `max_length` is described by its counter (`aria-describedby`): "12/30", read when the control gets the focus. It is no live region, and is not read out at every key. Past the most it says a number greater than the most, in a heavier weight. In a cell's editor, on a field of the action panel and on the argument line. See [Inline editing](inline-editing.md#the-counter-of-a-text). |
| The button that empties a sensitive value | Named with the column or the field: "Clear Budget". In the action panel it says "Keep" once it was used, named "Keep Budget" and described by "Will be cleared.". |
| A save in progress | `aria-busy` on the cell. |
| A failed save | `aria-invalid` on the cell, described by the action's message, and the same live region: "Title was not saved: …". |
| The column of the row actions | A column of the grid, the last one, with the heading "Actions". It is counted in `aria-colcount` and `aria-colindex`. Each button is named by its action. |
| That rows can be selected | `aria-multiselectable="true"` on the grid, and `aria-selected`, `true` or `false`, on every row of records. Neither is there on a table without the boxes. In the picker, where one row is selected at a time, the grid says `aria-multiselectable="false"`. |
| The box of a row, and the one in the header | Checkboxes named "Select row" and "Select all rows of this page", in a first column of the grid that is counted in `aria-colcount` and `aria-colindex`. The one in the header is mixed when some rows of the page are selected. |
| What is selected | A group above the grid (`role="group"`) named "Selected rows", with a live region (`role="status"`) that says the number when it changes: "3 selected", "All 320 that match are selected". |
| A bulk action in progress | `aria-busy` on the grid, and `aria-disabled` on the buttons of the line, which keep the focus. |
| What a bulk action came to | The live region: "Archive: 2 done, 1 not done. You are not allowed to do this. (1)". The same is text above the grid. |
| An action in progress | `aria-busy` on the row's actions cell. |
| An action that ran | The live region: "Archive: done"; after a create, "Task created". |
| A table action, or a generic action in a row, that ran | The live region, and the same words above the grid: the action and what it returned, "Count unused: 3", or "Remove unused: done". |
| A table action without a panel that failed | The live region, and the same words above the grid: "Count unused failed: …". |
| An action that failed | The live region: "Archive failed: …". For an action that ran straight away, also `aria-invalid` on the row's actions cell, described by the message. |
| The action panel | A modal dialog named by its heading (`aria-labelledby`): "Reassign: Write the report", "New task". |
| A field of the panel | A label. A required field has `aria-required`, and the mark " \*" beside its label is hidden from assistive technology. A field with an error has `aria-invalid` and is described by the message. |
| A field of the panel that holds the key of a related record | A group (`role="group"`) named by the field's label, with what the record is called as text and the button "Choose", which is described by that text. A group cannot say `aria-required`, so the label of a required one ends in the word "required", for screen readers only. Its errors describe the group. |
| The picker | A modal dialog named by its heading: "Assignee: choose user". Its table is a grid named as the destination's table is, with `aria-multiselectable="false"`, `aria-selected` on every row, and a radio button named "Select row" in every row, all of one group. See [Choosing a related record](choosing-a-related-record.md#what-assistive-technology-is-told). |
| A field of the panel that holds several related records | A group named by the field's label, with what each record is called as text, a button per record named by what it does ("Remove ops"), and the button "Choose". Its picker's grid says `aria-multiselectable="true"`, and has a box named "Select row" in every row and a status above it that says how many rows are selected. |
| The field of a union | A group (`role="group"`) named by the field's label, which ends in the word "required", for screen readers only, where the union cannot be empty. In it a menu labelled "Kind", and the fields of the kind that is chosen, each with its own label. What the action says of the value of a kind that holds one value describes that value's control; of a kind made of fields, the group. |
| The field of an argument that takes a file | The browser's file input, with a label. A required one has `aria-required`. A file the upload refuses, and what the action said of the file, mark the input `aria-invalid` and describe it; a refusal as the file is chosen is said in the live region as well ("File: The file is too large. …"). While the file is sent, a `<progress>` named by the file says how far it has come. |
| What an action says that is about no field of its panel | An alert (`role="alert"`) above the fields. |
| The name of a table, its create button and the buttons of its table actions | Above the grid: the name as a heading of the page (`h1` on a mounted page), or as text where an embedded table is not told a heading level; the buttons named by what they say, "New task", "Count unused". |
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
| A selected row | The box at its start is ticked. A row has no other mark of being selected and no colour of its own; the box has an edge in the text colour at half strength, as the other boxes of a table have. |
| A table that is reading | Its rows at 70% opacity. The header and the filters are not dimmed: they can be used meanwhile, and their text is muted already. |
| An input or a menu | An edge in the text colour at half strength, on the filters and on the fields of the action panel. daisyUI's own edge, at a fifth, does not show where an empty input is. |
| A rejected filter value, and a field of the panel with an error | The edge in the colour of a failed cell's ring, and the message under the control, in the text colour. The message is what says so without a colour. |
| A badge, a progress bar and a slider (three of the components that are shipped) | The badge has an edge in the text colour at half strength and its label in the text colour. The bar is filled in the text colour, on a track at a fifth of it, with the number beside it as text. The slider is filled in the text colour, with a track at half strength and the number beside it. None of them has a colour that means something. |

In **forced colours** (the contrast themes of Windows) the browser paints
with the system's colours and drops every fill and every shadow. Outlines,
borders and text stay, so the focus ring, the ring and the "!" of a failed
cell, the edges of inputs and buttons, and the dimming stay as well. Three
things are different there, and only there: the dialog and the action panel
have a border, since their shadow is gone; the current page is underlined,
since its fill is gone; and the triangle of an expander is told to keep its
two transparent sides, without which it would be a square that looks the
same open and closed. A progress bar and a slider keep their own drawing
there, in the system's text colour: their filled parts are a fill and a
shadow, which forced colours would take away.

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
| The label of a badge (1.4.3), and its edge | 4.5:1; the edge is not asked for | 16.7:1; 3.3:1 | 12.6:1; 4.4:1 |
| The filled part of a progress bar against its track (1.4.11) | 3:1 | 10.9:1 | 6.8:1 |
| The track of a slider, its filled part, and its thumb, each against the page (1.4.11) | 3:1 | 3.3:1; 16.7:1; 16.7:1 | 4.4:1; 12.6:1; 12.6:1 |

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
- **The filled part of a slider against the rest of its track** is 5.0:1 in
  the light theme and 2.9:1 in the dark one. Where the slider stands is
  shown by its thumb, which stands out of the track, and by the number
  beside it; the two parts of the track are not what says it.
- **The track of a progress bar against the page** is 1.5:1 and 1.9:1. The
  bar's value is its number.
- **A component of the host's own.** What it draws is the host's to
  measure. See [Custom components](custom-components.md#what-a-component-owes-the-people-who-use-it).
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
empty, failed, with each editor open, the two editors of an array among
them, with the dialog open, with a failed cell, as each actor; with rows expanded and nested tables open to the
deepest level, on a page limited to the records of one parent, with
reference cells; with the actions column, a failed actions cell, the action
panel open, with errors and with the dialog on top of it, and with the
create button of a table and of a line; with what a table action
returned, with its question and its panel open, with an error at a field
of it, and with the buttons of table actions on a line; with rows selected, with all that
match selected, with the question of a bulk action open, and with what a
bulk action came to, in the light and in the dark theme; with the picker
open, with a row selected in it, with a choice that was not taken, with a
column's question on top of it, with a cell whose choice was refused, and
with the picker on top of the action panel, in both themes; with a field
that holds several related records, with one of them taken out, and with
the picker for several on top of the panel, in both themes; with the side
panel of an embedded resource open, with a value inside it taken away, with
errors at its fields, and with the list of groups of an array of embedded
resources with a value added and one refused, in both themes; with the
side panel of a union open, with an error at the value of a kind and at a
field of a kind made of fields, in both themes; with the panel of an action
that takes a file open, in both themes, and with a file the upload or the
action refused; with the
argument line, with a value Ash refused at one of its inputs and with "Fill
in … to see records." in place of the rows, in both themes, and with a list
of values in it, in German, and with the line of a nested table and of a
picker; with the counter of a text in a cell, in the action panel and on the
argument line, within the most and past it, in both themes; with "Clear" in
the editor of a sensitive cell and in the action panel, before and after it
is used, in both themes; with the panel and the pickers of an action
whose arguments refer to records, in both themes; and with columns made
narrower and wider, a handle of a column's width with focus, and the same
in a nested table, in both themes).

The suite requires that axe reports no violation in any of them. The
landmarks around a table are the host page's and not the table's; see
[Layout and embedding](layout-and-embedding.md).

axe does not judge whether a focus ring can be seen, whether a state is shown
by more than a colour, or what is left in forced colours. Those are measured
by tests of their own, as [What was measured](#what-was-measured) says.

The question a column asks before "Clear" empties a sensitive cell is
tested with a question put onto the column's editor by the test: the demo's
sensitive column has none.

Two things about the action panel are covered more thinly than the rest: no
panel of the demo has a datetime field, and no action of the demo has both a
question and a panel, so that path is tested with a question put onto an
open panel by the test. The side panel of a cell with a question is tested
as it is: "Repeats" on `/tasks` asks when "Save" is used.

The argument line is tested in the browser with what the demo's tables
have: a text, a number, a date, a box and a list of text. A menu, a multiple
choice and a datetime in the line are the controls of the action panel at
another size, and are covered by the page tests on the server only.

The editor of an array is tested in the browser for text, for numbers and
for enum values, which is what the demo's tasks and specimens have. The
lists of dates, datetimes and booleans are made of the same rows with
another control, and are covered by the demo's LiveView tests, which do not
run the hook.

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
  then the filter cell of the first column. So it is while an argument the
  read action requires is empty.
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
  the cell for assistive technology, and in the editor. For the eye it is
  shown under the cell while the cell has the focus or the pointer, and
  Escape takes it away: see
  [Long text](columns-and-defaults.md#long-text).
- **A mounted table brings no main landmark.** Its page is a heading and the
  table; `<main>` has to come from your layouts. See
  [Layout and embedding](layout-and-embedding.md).

## Things people trip over

- **The arrow keys do nothing.** The hooks are not registered, or the assets
  were built before the dependency was compiled. See the
  [tutorial](../tutorials/get-started-with-ash-table.md#1-install).
- **Expecting Tab to move to the next cell.** Tab leaves the grid; this is
  the ARIA grid pattern. Arrow keys move between cells.
- **Expecting Space to toggle a boolean.** Enter and F2 do. Space selects
  the row, where rows can be selected, and does nothing where they cannot.
  In the open editor of an array Space does tick a box, as it does
  anywhere.
- **Expecting a tick in a multiple choice to be saved at once.** The list is
  saved by Enter or by leaving it.
- **Pressing Enter on "Add value" to save.** Enter on a button uses the
  button. Enter in a value saves; so does Tab from the last control.
- **Expecting Tab to reach a row's buttons.** Move to the row's last cell
  and press Enter.
- **Expecting Enter on a relationship line to reach its create button, or
  the buttons of its table actions.**
  Enter opens and closes the line. F2 goes to its controls.
- **Expecting a filter to be a tab stop.** Move to its cell and press Enter.
- **Expecting Enter on a heading to reach the handle of its width.** Enter
  sorts. F2 goes to the handle.
- **Treating "axe reports no violations" as "accessible".** See the table
  above.
- **axe reports "Scrollable region must have keyboard access" for a nested
  table.** The rule asks that Tab stops in every area that scrolls. A nested
  table is reached with Enter and the arrow keys, not with Tab, and its area
  scrolls with the focus; the demo's checks leave this one finding out for
  the grids of nested tables, and nothing else.
- **A theme whose colours do not contrast.** The table draws with the
  theme's colours. See [What was measured](#what-was-measured) for what
  that leaves to the theme.

## Not in the first version

No keyboard shortcuts of the host's choosing, and no
tested screen reader support. The roadmap is in the
[specification](https://github.com/StefanRoesch/ash_table/issues/21).
