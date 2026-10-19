# Keyboard and accessibility

A table can be used with the keyboard alone, and with a screen reader. This
guide says how: where Tab goes, what each key does, where focus goes after
a change, what a screen reader is told, how focus and the other states are
shown, and what has been tested.

The model in one paragraph: a table is a plain table (`role="table"`), as on
any web page. **Every control in it is a Tab stop**: the boxes, the
expanders, the sort buttons, the filters, the action buttons, the
pagination, and every cell that can be edited. A cell that cannot be edited
is no stop. Tab and Shift+Tab go from stop to stop in the order they stand
in the page, nested tables included. A screen reader moves through the
cells with its own table keys. The decision and its reasons are in
[ADR 0003](https://github.com/StefanRoesch/ash_data_table/blob/main/docs/adr/0003-table-semantics-controls-in-the-tab-order.md).

## The smallest example

There is nothing to declare. The keys are handled in the browser by the
JavaScript hooks that ship with the library, so the only requirement is that
they are registered, which is one import. In the demo
([`demo/assets/js/app.js`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/assets/js/app.js)):

<!-- source: demo/assets/js/app.js -->
```js
import {hooks as ashDataTableHooks} from "phoenix-colocated/ash_data_table"
// ...
  hooks: {
    ...colocatedHooks,
    ...ashDataTableHooks,
```

(The line `// ...` stands for the lines between the import and the
`LiveSocket`'s options.)

**Try it:** `/tasks` in the demo, as Ada Admin. Press Tab: past "Columns"
and the search, "Skip table Tasks" shows, then the sort buttons, the
filters, and each row from left to right.

## The Tab order

### Through one table

Tab goes through a table in this order:

1. **The heading line**: "Columns", the inputs of the
   [argument line](arguments.md), the create button, the buttons of the
   [table actions](table-actions.md).
2. **The line above the rows**, while it shows: "Clear selection", "Select
   all … that match" and the bulk actions while rows are selected; "Clear
   filters" while a filter is set; "Read again" while the table says that
   records changed.
3. **"Skip table Tasks"**: a link, seen only while it has focus. Enter
   jumps past the table (see below).
4. **The header row**: the box that selects the page's rows, then the sort
   button of each column that sorts. A header that does not sort is no stop.
5. **The filter row**: for each filter, its menu of how to filter, its
   value, and its clear button. A column without a filter has no stop here.
6. **Each row, left to right**: its box, its expander, each cell that can be
   edited, and its action buttons. A cell that cannot be edited is passed
   over, but a button in it is not: "Show" in a sensitive cell, and "Show
   all" in a cell that cuts its text off (after the cell, where the cell is
   a stop too). Under an expanded row: the button of each relationship line,
   and under an open line its nested table (see below). Then the next row.
7. **The footer row** of the [summaries](footer-summaries.md): no stops.
8. **The pagination**: Previous, the page numbers, Next, and the menu of
   the page size where the table offers one.

Shift+Tab goes the same way backwards. A hidden column has no stops: the
browser passes over what is not shown.

A long table has many stops: `/tasks` has up to about 20 in a row. "Skip
table" jumps past them. A column that cannot be edited adds none, and
hiding columns ("Columns") takes theirs away.

### Through nested tables

A nested table is a table like any other, further down the page. It has the
same stops, in the same order, and Tab simply goes on into it. Take a task
on `/tasks`, expanded, with "Comments" open:

1. The task's box, its expander, its editable cells, its action buttons.
2. The button of the line "Comments".
3. The nested table's heading line, which stands on the line: its
   "Columns", its argument line, "New comment", its table actions.
4. Its line above the rows, while it shows.
5. "Skip table Comments".
6. Its header row, its filter row, its rows, its pagination, and its link
   "Open in full view".
7. Then the task's next line, and the next task.

**Two levels deep**: a comment row can be expanded too, and a line under it
opened. That nested table stands after its line's button, inside the
comments, and Tab goes through it there. After it come the comment's next
line, the next comment, and at the end of the comments the task's next line.

**Several open at once**: each nested table stands under its own line, and
Tab goes through them one after the other, in page order.

No key "enters" or "leaves" a nested table. Escape does not leave one.

### "Skip table"

Every table starts with a link "Skip table *Name*", in a nested table too
("Skip table Comments"). It is hidden until Tab reaches it, then it shows at
the table's top left. Enter jumps to just after the table's pagination: the
next Tab goes on after the table. A nested table's link skips only that
table; the next Tab is the parent row's next line. The link is a plain
link to a place in the page, and needs no JavaScript.

## What the keys do

### On each kind of stop

| Stop | Enter | Space | Escape |
| --- | --- | --- | --- |
| A cell that can be edited | Starts editing (see [Editing a cell](#editing-a-cell)). | Starts editing with a space typed, as any character does; nothing on a boolean. | Gives up a failed save: the cell shows the saved value again. Cuts off a whole text that shows. Hides a shown sensitive value. |
| The editor in a cell | Saves; focus goes back to the cell. | Types. | Gives the edit up; focus goes back to the cell. |
| A row's box | — | Selects the row, or takes it out. | — |
| The box in the header | — | Selects every row of the page, or none. | — |
| The expander of a row | Opens or closes the row. | The same. | — |
| The button of a relationship line | Opens or closes the line. | The same. | — |
| A sort button | Sorts: ascending, descending, none. Focus stays. | The same. | — |
| A filter's input | Applies the filter. Focus stays. | Types. | Gives up what was typed and not applied. Focus stays. |
| A filter's menu | The browser's. | The browser's. | — |
| "Show all" in a cell | Shows the whole text, or cuts it off again. Focus stays. | The same. | Nothing. Use Enter or Space again. |
| "Show" in a sensitive cell | Shows the value, or hides it. | The same. | Hides a shown value; gives up a reveal that failed. |
| A row's action button | Runs the action, asks its question, or opens its panel. | The same. | Gives up the message of the row's action that failed. |
| A row's radio button, in a picker | Chooses the row, as "Choose" does. | Selects the row. | Closes the picker. |
| "Skip table" | Jumps past the table. | — | — |
| Any other button: the pagination, "Columns", create, a table action | Uses it. | The same. | — |

Other keys on a cell that can be edited:

- **A character** starts editing with that character typed (see the next
  section for what each type does with it).
- **Shift+Enter** shows a cut-off text whole, and cuts it off again; on a
  sensitive cell it shows the value, and hides it again.
- **A double click** starts editing too.

Every other key is the browser's. The table moves focus with Tab only;
inside a menu, a number field, a slider or a group of radio buttons, Up
and Down Arrow and the other keys are that control's own. Key combinations
with Alt are left to the browser.

### Editing a cell

Enter on an editable cell starts editing. What happens depends on the type:

| Cell type | Enter | A character |
| --- | --- | --- |
| text | Opens the editor with the text selected. | Opens the editor and replaces the text with the character. |
| number | Opens the editor with the number selected. | Replaces the number, if the input takes the character. A letter opens the editor and leaves the number as it was. |
| date, datetime | Opens the editor with its value. | Opens the editor and keeps the value; a digit goes into the input's first part. |
| enum | Opens the browser's menu at the cell's value. | Opens the menu at the first value that starts with the character. Nothing is saved by that alone. |
| boolean | Toggles the value and saves. | Nothing. |
| reference | Opens the [picker](choosing-a-related-record.md#the-keyboard). | Nothing. |
| array | Opens the side panel. | Opens the side panel, as Enter does. |
| a value made of fields (an embedded resource, a map), a union | Opens the side panel. | Nothing. |
| a column's own component | Opens the editor with its value. | As text and number; a slider takes no characters. |

While the editor is open:

| Key | Effect |
| --- | --- |
| Enter | Saves. Focus goes back to the cell. |
| Shift+Enter, in text | A new line. |
| Escape | Gives the edit up. In an open menu, Escape closes the menu first. |
| Tab | Saves, and goes on to the next stop. |
| Shift+Tab | Saves, and goes back to the stop before the cell. |
| Up and Down Arrow, Home, End, Page Up, Page Down | Belong to the editor: in a closed menu they change the value, in a slider they move it. |

A step in a closed menu or a slider is not yet a choice: Enter or leaving
the cell saves it, and Escape gives it up. Escape never takes back what was
saved. See [Custom components](custom-components.md#the-keyboard).

In the editor of a sensitive cell with "Clear", Tab goes from the input to
"Clear" first, without saving. See
[Sensitive columns](sensitive-columns.md#emptying-a-value).

### The side panel, the picker and the question

An array, a value made of fields and a union are edited in the **side
panel**. A row action with fields opens the **action panel**. A reference
cell opens the **picker**. A column or an action may ask a **question**
first. All four work the same way from the keyboard:

- Focus goes into them as they open: a panel to its first field, the
  picker to the row chosen now (its radio button), a question to "Cancel".
- Tab and Shift+Tab move through their fields and buttons.
- Escape is "Cancel": nothing is saved or run.
- When they close, focus goes back to what opened them.

Over the page (modal, the default kit) nothing else can be reached while
they are open. In the page (inline, as a kit or `presentation:` says) Tab
from the last control goes on into the page. See [Kits](kits.md).

Inside the side panel of an array, Space ticks a box, Enter on "Add value"
adds a value and puts focus in it, and the button after a value takes it
away; focus then goes to the value in its place, else the one before, else
"Add value". The controls are named by their place: "Tags 2", "Remove
Tags 2". A union's panel starts on its "Kind" menu: choosing another kind
puts that kind's fields under it, and focus stays on the menu. See
[Maps and embedded resources](maps-and-embedded-resources.md#editing-in-the-side-panel)
and [Unions](unions.md#editing-in-the-side-panel).

The picker's table is a table like any other. Where one record is chosen,
each row has a radio button, and they are one group: Tab goes into the
group and out of it, and Up and Down Arrow move within it, as with any
radio buttons. Enter on a row's radio button chooses that row. Where
several are chosen, each row has a box. See
[Choosing a related record](choosing-a-related-record.md#the-keyboard).

## Selecting and sorting

**Selecting.** A table with a bulk action has a box at the start of every
row, and one in the header for the rows of the page. The boxes are stops:
Space ticks one. While rows are selected, the line above the rows holds
"Clear selection", "Select all … that match" and the bulk actions; they
come before "Skip table" in the Tab order. There is no key that selects a
range; a pointer can, with Shift and a click. See
[Selecting rows and bulk actions](selecting-rows-and-bulk-actions.md).

**Sorting.** A column that sorts has a button in its header. Enter or Space
sorts: ascending, descending, then not at all. Focus stays on the button.

## "Show all"

A cell that cuts its text off has a small button "Show all", read-only or
editable. It is a Tab stop, named after its column ("Show all of Title").
Enter or Space shows the whole text in the cell, the row as high as it
needs; the button then says "Show less", and the same keys cut the text off
again. Focus stays on the button. On an editable cell, Shift+Enter does the
same, and Escape cuts the text off. See
[Long text](columns-and-defaults.md#long-text).

## Column widths and hiding columns

"Columns", on the heading line, opens a list (the browser's own popover).
It holds, for each column:

- a box: not ticked, the column is hidden;
- a number field, "Width of Title": the column's width in pixels, from 48 to
  1000. Type a number, or use Up and Down Arrow, the field's own keys.

The label column, which cannot be hidden, comes first, with its width field
and no box. "Reset widths", at the end, gives every column its first width
again.

| Key | Where | Effect |
| --- | --- | --- |
| Enter, Space | On "Columns" | Opens or closes the list. Focus stays on the button. |
| Tab, Shift+Tab | In the list | Through the boxes, the width fields and "Reset widths". Tab past the last one, or Shift+Tab past the button, closes the list. |
| Space | On a box | Hides the column, or shows it again. |
| Escape | In the list | Closes it. Focus goes back to "Columns". |

The handle at the right end of each header is for the pointer only. It is
no stop and is hidden from screen readers; the width fields do the same
from the keyboard, and with a pointer without dragging. What widths and
hiding do to a table is in
[Columns and defaults](columns-and-defaults.md#column-widths).

## The filter row and the argument line

A filter's controls are stops: its menu of how to filter, its value, and
its clear button. Enter in the value applies the filter; focus stays.
Escape gives up what was typed and not yet applied; focus stays. A filter
of "is any of" has a button that opens the side panel with a box per
value. See [Filtering](filtering.md).

The inputs of the [argument line](arguments.md) are stops on the heading
line, each with its label. Enter, or leaving an input, applies what the
line holds; a box and a menu apply at once.

## Focus after a change

The table puts focus back when a change takes away the element that had it.
The page does not scroll for it.

| After | Focus is on |
| --- | --- |
| A save, or Escape, in a cell's editor | The cell. |
| A failed save | The cell, which shows the message under its value. |
| Tab or Shift+Tab out of an editor | The next or the previous stop. |
| The side panel or the action panel closes | What opened it. |
| The picker closes | The cell or the button that opened it. |
| A question answered with Cancel | What asked: the editor, or the button. |
| A sort | The sort button. |
| A filter applied | The filter's input. |
| A filter's clear button | The stop at the same place in that filter, else the one before (its value). |
| "Clear filters" | The first control of the filter row. |
| A page change | The pagination button that was used; when it is disabled now, the button of the page shown, or the other of Previous and Next. |
| A destroy, or a live update that takes the row away | The same stop in the row after, else in the row before. |
| A create | The new row's box, else its first stop. |
| A live update of the focused row | The same element: the row is patched around it. A cell being edited keeps what is typed. |
| "Clear selection", or a bulk action that left nothing selected | The table's first stop. |
| "Select all … that match" | "Clear selection". |
| "Read again" | The table's first stop. |
| Opening or closing a row or a line | The same button. Tab goes into what opened. |
| A line or row closes while focus is inside it | The line's button, else the row's expander. |

The general rule, where the table above has no line: the element itself if
it is back, else the same stop in the row at the same place (the row after,
else the one before), else the next stop along that row, else the table's
first stop.

## Scrolling

Every table scrolls sideways in an area of its own (see
[Layout and embedding](layout-and-embedding.md#scrolling-sideways)). There is
nothing to scroll by hand:

- **A stop that Tab reaches is brought into view**, in its own table's area.
  It is brought out from under a
  [sticky label column](columns-and-defaults.md#keeping-the-label-column-in-view)
  and kept above the scrollbar at the bottom edge of the window (WCAG 2.2,
  "Focus Not Obscured").
- **The area itself is no stop** (`tabindex="-1"`): its stops are inside it.
- **The scrollbar at the bottom edge** is for the pointer only: no stop, and
  hidden from screen readers.
- **Focus that a patch puts back is not scrolled to.** A table scrolled away
  with the wheel stays where it was.

## Screen readers

### How a screen reader moves through a table

The table says it is a table, so a screen reader's own table keys work on
it as on any web page: in NVDA and JAWS Control+Alt and the arrows, in
VoiceOver Control+Option and the arrows. They
reach every cell, read-only cells included. Tab reaches every control, with
its name and state.

Entering a table, a screen reader says that it is a table, its name
("Tasks") and its size, in its own words. Moving down a column, it names
each row by the cell of its label column, which is the row's header. A
nested table is named by its line and its row ("Comments Write the
report"), and its "Skip table Comments" says the same name.

### Editable cells say nothing more

An editable cell is a Tab stop; a read-only cell is not. That is the whole
difference a screen reader is given: an editable cell has no text such as
"editable, press Enter". A column that no row may be edited in has a lock
after its header, named "read-only".

A first version described every editable cell with such a text. It made a
page of `/tasks` 9 % larger on the wire, against a budget of 2 %, so it was
dropped (owner, 2026-10-19; question 2 of the
[design note](https://github.com/StefanRoesch/ash_data_table/blob/main/docs/architecture/tab-model-design.md)).
If the accessibility check shows that editable cells cannot be recognised,
the fallback is a description of the focused cell only.

A screen reader in browse mode may keep Enter for itself. A click on a
focused editable cell from the keyboard or from assistive technology starts
the edit as Enter does, so the edit starts either way.

### What assistive technology is told

| What | How |
| --- | --- |
| The table | `role="table"`, named by `aria-label` ("Tasks"). Cells are `role="cell"`; the label column's cell is the row's header (`role="rowheader"`). |
| Size and position | `aria-rowcount` (the total when the table knows it, counting the header rows and the footer row; else `-1`), `aria-colcount`, `aria-rowindex` on every row, `aria-colindex` on every cell. Under offset pagination the row numbers run through all pages; under keyset pagination they do not (see below). |
| "Skip table" | A link before the header row, "Skip table Tasks", to a place after the pagination. |
| Sort | A button in the header, named by the column; `aria-sort` on the header: `ascending`, `descending` or `none`. |
| An editable cell | A Tab stop (`tabindex="0"`), and nothing more. |
| A read-only cell | No stop. A screen reader reads it with its table keys. |
| A column no row may be edited in | A lock after its header, named "read-only". |
| A cell that cuts its text off | The whole text is in the cell, and is read from there. Its button "Show all of Title" says whether the text shows whole (`aria-expanded`). |
| A cell hidden by a field policy | The text "Not available", for screen readers only. |
| A boolean cell | A mark hidden from assistive technology, and the text "Yes" or "No". |
| An array cell | Its values as text, separated by commas. |
| A save in progress | `aria-busy` on the cell. |
| A failed save | The cell is described by the message, which stands under its value; the live region says "Title was not saved: …". |
| The editor of a cell | Named by its column. `aria-required` where the action cannot take it empty. Number limits as `min`, `max`, `step`; a text with a `max_length` described by its counter ("12/30"). See [Inline editing](inline-editing.md#limits-an-editor-shows-before-saving). |
| A filter's controls | A name each: "Filter Title", "How to filter Title", "Clear the Title filter". A rejected value: `aria-invalid`, described by "Not a valid value". |
| The result of a filter | The live region: "12 results", or "Results updated" without a total. |
| An argument's input | A `<label>`; a group for an argument of several controls; `aria-required` where it cannot be empty; `aria-invalid` and the message where Ash refused the value. "Fill in Due by to see records." in place of the rows while a required one is empty. |
| A read in progress | `aria-busy` on the grid. The previous rows stay. |
| The boxes | Checkboxes named "Select row" and "Select all rows of this page", the second mixed when some rows are selected. A row is selected when its box is ticked; nothing else says so. In a picker that chooses one record, radio buttons of one group. |
| What is selected | A group "Selected rows" with a live region: "3 selected", "All 320 that match are selected". |
| The expander, a line's button | `aria-expanded`. The expanders are named "Related records"; a line by its relationship. |
| A nested table | A table named by its line and its row (`aria-labelledby`): "Comments Write the report". "Loading…" and `aria-busy` while its first rows come. |
| A nested table's pages and full view | A group "Pagination: Comments"; a link "Open in full view: Comments". |
| The actions column | The last column, "Actions"; each button named by its action. `aria-busy` on the cell while an action runs. |
| An action that ran or failed | The live region: "Archive: done", "Task created", "Archive failed: …". A failed action of a row also describes its cell. |
| A table action, or a bulk action | The live region and the same words above the rows: "Count unused: 3", "Archive: 2 done, 1 not done. …". |
| The side panel, the action panel, the picker, the question | A dialog over the page, or a region in the page, named by its heading or its question. |
| A field of a panel | A label; `aria-required` (the " \*" is hidden); `aria-invalid` and the message. A field of a related record, a union or several values is a group named by its label. |
| What a panel's action says about no field | An alert above the fields. |
| A failed or refused read | An alert in place of the rows. |
| The pagination | A navigation landmark "Pagination: Tasks"; buttons named "Go to page 3"; `aria-current="page"` on the current one. |
| "Columns" | Its name says what is hidden: "Columns (2 hidden, 1 filtered)"; of a nested table "Columns of Comments (2 hidden)". Hiding is read out: "Progress hidden", "Progress shown". A hidden column keeps the others' `aria-colindex`. |

A save, a sort and a page change are not read out: their result is in the
table. A row action and a create are, as the row may be away from focus.

### Row numbers under keyset pagination

The table knows the total (`aria-rowcount`) whenever the read action is
`countable`. It knows a row's place in that total (`aria-rowindex`) only
under offset pagination, where the page number says how many records come
before. A keyset page starts at a cursor and has no such number.

ARIA has no value for "position unknown", so on a keyset table the rows of
every page are numbered from the top of that page. On the first page that
is the row's true place; on a later page, what a screen reader announces as
the third row of the table is the third row of the page. The total is true
on every page.

## How the states are shown

The table has no colours of its own. Everything is drawn in the semantic
colours of the host's daisyUI theme, so it follows the theme, light or dark.

| State | What a person sees |
| --- | --- |
| Focus on an editable cell | A solid ring of 2px inside the cell, in the theme's text colour (`base-content`), as daisyUI draws its own. Not in `primary`: a brand colour may be any lightness, the text colour is the one a theme promises can be seen. The cell keeps it while its editor has focus. |
| Focus on a sort button, an expander, a line's button | The same ring of 2px in the text colour, outside the button. |
| Focus on any other control | daisyUI's own focus ring, in the text colour too: the boxes, a filter's controls, "Show all", "Skip table", the pagination, the panels' fields and buttons. |
| A failed cell | A ring of 2px in the error colour mixed with the text colour, and a "!" at the end of the cell: a mark that does not depend on colour. The message stands under the value. With focus, both rings show. |
| A cell that cuts its text off | A small underlined button "Show all" at its end; once used, the whole text and "Show less" under it. |
| A cell whose save is on its way | Its text at 70% opacity. |
| Which cells can be edited | At rest they look alike. Under the pointer an editable cell shows a thin edge, a text cursor and a small ✎. A column no row may be edited in has a lock after its header. |
| A selected row | Its box is ticked. Nothing else. |
| A table that is reading | Its rows at 70% opacity. The header and the filters are not dimmed. |
| An input or a menu | An edge in the text colour at half strength. |
| A rejected filter value, a field with an error | The edge in the failed ring's colour, and the message under the control. |
| A badge, a progress bar, a slider (shipped components) | Drawn in the text colour, with the number as text. No colour means anything. |

**Forced colours** (the contrast themes of Windows): the browser paints with
the system's colours and drops fills and shadows. Outlines, borders and text
stay, so the focus rings, the failed ring and its "!", the edges of inputs
and the dimming stay too. Only there: the dialog and the action panel have
a border, the current page is underlined, an expander keeps its triangle,
and a progress bar and a slider are drawn in the system's text colour.

### What was measured

Contrast was measured in Chromium, from the colours the browser computed,
in the demo's two themes (those of a new Phoenix 1.8 application). The
demo's browser tests
([`demo/e2e/contrast.spec.ts`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/e2e/contrast.spec.ts))
measure the same and hold each line at what WCAG 2 asks.

| | WCAG asks | Light | Dark |
| --- | --- | --- | --- |
| The focus ring against the cell, and of a sort button (1.4.11) | 3:1 | 16.7:1 | 12.6:1 |
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

- **Another theme.** The colours are the host's. A theme whose
  `base-content` does not contrast with its `base-100` fails everywhere.
- **The coloured buttons.** "Run", "Create", "Confirm" (`btn-primary`) and
  the delete button (`btn-error`) measure 2.75:1 (light) and 4.1:1 (dark)
  for `primary`, 4.1:1 for `error`, in the demo's themes: less than the
  4.5:1 text needs. That is the theme's to put right.
- **A slider's filled part against the rest of its track**: 5.0:1 light,
  2.9:1 dark. Its thumb and its number say where it stands.
- **A progress bar's track against the page**: 1.5:1 and 1.9:1. Its number
  says its value.
- **A component of the host's own**: see
  [Custom components](custom-components.md#what-a-component-owes-the-people-who-use-it).
- **Disabled buttons** (Previous, Next): 1.5:1 and 1.75:1. WCAG leaves them
  out.
- **Focus Appearance (2.4.13, AAA)**: not tested as such, not claimed.
- **`prefers-contrast: more`**: nothing answers to it.

## What has been tested

The demo's browser tests
([`demo/e2e`](https://github.com/StefanRoesch/ash_data_table/tree/main/demo/e2e))
press the keys of this guide in Chromium: the Tab order through `/tasks`
and through nested tables two levels deep and several open at once,
"Skip table", focus after each change of the table above, Tab out of an
editor, the width fields, and every editor, panel and picker. axe-core
checks every demo table in every state (sorted, filtered, empty, failed,
each editor and panel open, nested tables open, rows selected, the picker,
the question, in both themes and in German) and must find nothing, with no
exception.

| | Status |
| --- | --- |
| Chromium, headless, keys scripted | Tested |
| axe-core, all its default rules | Tested, in Chromium |
| Contrast of focus rings, failed cells, dimmed text, input edges | Measured in Chromium, in the demo's two themes |
| Forced colours | Tested as Chromium emulates them; **not** in a Windows contrast theme |
| NVDA (Firefox, Chrome), VoiceOver (Safari) | **Pending**: an accessibility expert's check by hand, with [this checklist](https://github.com/StefanRoesch/ash_data_table/blob/main/docs/architecture/tab-model-expert-check.md). Its result will be written here. |
| JAWS, TalkBack | **Not tested** |
| Firefox, Safari, touch devices | **Not tested** |

axe finds markup that is wrong. It cannot tell whether a table is workable
with a screen reader. If you use the table with assistive technology, a
report is welcome in the
[issue tracker](https://github.com/StefanRoesch/ash_data_table/issues).

## Edge cases

- **A table without records** still has its header row, and its sort
  buttons and filters are stops.
- **A closed menu in an editor**: Up and Down Arrow change the value without
  saving; Enter, or leaving the cell, saves.
- **A cell whose save is on its way** cannot be edited until the server has
  answered.
- **Tab out of an editor while the save fails**: focus stays where Tab took
  it. The cell shows the message and the live region says it.
- **A mounted table brings no main landmark.** `<main>` comes from your
  layout. See [Layout and embedding](layout-and-embedding.md).

## Things people trip over

- **Nothing happens on Enter.** The hooks are not registered, or the assets
  were built before the dependency was compiled. See the
  [tutorial](../tutorials/get-started-with-ash-data-table.md#1-install).
- **Tab passes over a value.** It is read-only: only controls and editable
  cells are stops. A screen reader reads it with its table keys; the eye
  sees it as Tab moves along the row.
- **Too many stops.** Use "Skip table", hide columns you do not need, or
  make columns read-only that nobody edits.
- **Expecting Space to toggle a boolean.** Enter does. Space on a cell
  starts editing like any character, and does nothing on a boolean.
- **Expecting Escape to leave a nested table.** Nothing leaves a nested
  table: Tab goes on through it, and its "Skip table" jumps past it.
- **Pressing Enter on "Add value" to save.** Enter on a button uses it.
  "Save" saves the list.
- **Treating "axe reports nothing" as "accessible".** See
  [What has been tested](#what-has-been-tested).

## Not in the first version

No keyboard shortcuts of the host's choosing. The roadmap is in the
[specification](https://github.com/StefanRoesch/ash_data_table/issues/21).
