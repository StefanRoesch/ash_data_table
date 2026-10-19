# Table semantics, controls in the Tab order: design note

Status: **accepted, 2026-10-19.** It carries the owner's decision of 2026-10-19, taken on the advice of his accessibility expert (section 1), and the owner's answers to the questions of section 14 (same day). Nothing in it is built. The ADR is [0003](../adr/0003-table-semantics-controls-in-the-tab-order.md) (accepted). The amendment to [target.md](target.md) is made there (D-tab, stage 8a). Code references are of `9543abd`. Words follow `CONTEXT.md`. The model for this note is [react-kit-design.md](react-kit-design.md).

## 0. In one paragraph

Today a table is an ARIA grid: one Tab stop for the whole tree of tables, and the arrow keys move from cell to cell. That changes. A table becomes a plain table (`role="table"`), and **every interactive element in it is a Tab stop of its own**: editable cells, boxes, expanders, relationship lines, sort buttons, filter controls, action buttons, the heading line's controls, the pagination. They come in the order they stand in the page, nested tables included. A read-only cell is no stop: a screen reader reads it with its own table keys, as on any web page. A "Skip table" link at the start of each table jumps past it. The table handles no arrow key any more: screen readers have their own keys to move through a table, and the browser moves focus with Tab. Editing stays as it is: Enter on a cell edits it in place, or opens the side panel; Escape gives the edit up. Most of the hook stays (editing, saving, selection, widths, hiding, scrolling, live updates); what goes is the code that moved the one tab stop about.

## 1. The owner's decision (2026-10-19)

The expert's advice: "the best and simplest thing is if every element is accessible via Tab and not arrow keys; the tools people with special needs use do the arrow thing on their own; each element of the table and nested table reachable via Tab and the ARIA attributes set."

"Every element" is read as **every interactive element**. The first draft of this note made read-only cells stops too; the sources lean against that (section 2.10), and the owner, after an explanation, decided: "readonly cells not focusable" (question 14).

| # | Decision |
| --- | --- |
| T1 | `role="table"` semantics instead of the ARIA grid pattern: no `role="grid"`, no roving tabindex |
| T2 | Every interactive element is a Tab stop: every control (row box, expander, editable cell, filter controls, sort buttons, action buttons, relationship lines, "Columns", the heading line's controls, "Skip table", pagination, …). Read-only cells are no stops. Nested tables the same as top tables |
| T3 | A "Skip table" link at the start of each table, top and nested |
| T4 | No arrow-key navigation at all ("makes everything simpler") |
| T5 | Editing as today: Enter on a cell edits in place; lists, maps, groups and unions open the side panel as today; Escape cancels as today |

It supersedes the open parts of #43 (the arrow walk through nested tables, and its "on hold" Tab question) and all of #45 (arrow keys opening expanders). #41 (no filter row without filters) and #42 (the focus ring of a spanning cell) stay useful; #42 changes, see section 10 (risk 6).

## 2. What changes for a person

### 2.1 Three kinds of people

- **A sighted keyboard user** presses Tab and Shift+Tab. Focus goes from control to control in reading order: left to right along a row, then the next row. Enter or Space uses what has focus. "Skip table" jumps past a table they do not need. Read-only values are read by eye; the table scrolls sideways as focus moves along a row.
- **A screen-reader user** moves through the table with the screen reader's own table keys (in NVDA, Control+Alt+arrows; JAWS and VoiceOver have their own), read-only cells included. The table now says it is a table, so those keys work as on any web page. Tab reaches every control, with its name and state.
- **A mouse user** sees no change, but for the focus ring, which now follows Tab instead of the arrows, and the column widths, which can also be typed (section 2.7).

### 2.2 The Tab order through one table

In page order, which is the order the table is drawn in:

1. **The heading line**: "Columns", the inputs of the argument line, the create button, the table actions.
2. **The selection line**, while rows are selected: "Clear selection", "Select all … that match", the bulk actions.
3. **"Skip table"**: a link, hidden until it has focus. Enter jumps to the end of the table (section 2.4).
4. **The header row**: the "select all rows of this page" box, then the sort button of each column that sorts. A header that does not sort is no stop (question 6).
5. **The filter row**, where a column filters: per filter, its operator menu, its value, its clear button. A cell without a filter is no stop.
6. **Each row, left to right**: the row's box, the expander, each editable cell, the row's action buttons. A read-only cell is passed over; a read-only sensitive cell's "Show" button is a stop. Under an expanded row: each relationship line's button, and under an open line its nested table (section 3). Then the next row.
7. **The footer row** of the summaries: no stops (its cells are read-only).
8. **The pagination**: page size, Previous, the page numbers, Next.

A hidden column is not drawn for the eye (`display: none`), so the browser passes it over by itself.

How long is that? `/tasks` has 25 rows of at most about 20 stops each (box, expander, its 17 cells where all are editable, actions), fewer by every read-only column: at most about 500 stops in its rows, plus the controls above and below. "Skip table" and the screen reader's own keys are the way past (section 10, risk 1).

### 2.3 Into and out of a nested table

A nested table follows exactly the model of a table on the page. Section 3 says it in full.

### 2.4 "Skip table"

- A link at the start of each table's grid area, after the heading line and the selection line and before the header row: `<a href="#ID-end">Skip table Tasks</a>` (Gettext `"Skip table %{name}"`), visually hidden until it has focus, then shown at the top left of the table (WCAG 2.4.7 asks that focus can be seen).
- Its target is an empty element after the table's pagination, `<span id="ID-end" tabindex="-1">`. The browser moves focus there, and the next Tab goes on from there. No JavaScript.
- In a nested table, the name says which: "Skip table Comments".

### 2.5 What the keys do on each element

| Element | Enter | Space | Escape | Other |
| --- | --- | --- | --- | --- |
| A read-only cell | No stop: a screen reader reads it with its table keys | | | |
| An editable cell | Starts editing: in place; a boolean toggles and saves; a reference opens the picker; an array, a map, a group or a union opens the side panel (as today) | The browser's | Gives up a failed edit (as today) | A character typed starts editing with it, as today. Shift+Enter shows a cut-off text whole, and cuts it off again (as today). Double click edits, as today |
| A sensitive cell | Edits, where editable | | Hides a shown value | Its "Show" button is a stop of its own, also in a read-only sensitive cell; Shift+Enter on an editable sensitive cell still shows and hides |
| The editor in a cell | Saves; focus back on the cell | Types | Gives up; focus back on the cell | Tab saves and goes on to the next stop (today it left the grid). Shift+Tab saves and goes back. Arrows belong to the editor |
| A row's box | — | Selects the row, or takes it out (the browser's own checkbox) | | |
| The "all rows of this page" box | — | Selects every row of the page, or none | | |
| The expander | Opens or closes the row | The same (a real button) | | |
| A relationship line's button | Opens or closes the line | The same | | |
| A sort button in a header | Sorts: ascending, descending, none; focus stays | The same | | |
| A filter's input | Applies the filter; focus stays | Types | Gives up what was typed and not applied; focus stays | |
| A filter's menu | The browser's | The browser's | | Arrows are the menu's own |
| An action button | Runs the action, asks its question, or opens its panel | The same | | |
| "Skip table" | Jumps past the table | | | |
| A pagination button, "Columns", create, a table action | Uses it | The same | | |

F2 has no use any more (it was the key that went "into" a cell). It is dropped (question 9).

### 2.6 Editing: how it starts and ends, and where focus goes

Starting is as today: Enter, a typed character or a double click on an editable cell. The editor opens in the cell and has focus.

| After | Focus is |
| --- | --- |
| Enter, saved | On the cell |
| Enter, refused by Ash | On the cell, which shows the message under its value (as today) and is described by it; the message is read out in the live region |
| Escape | On the cell; nothing saved |
| Tab or Shift+Tab | On the next or previous stop; what was typed is saved (as when focus leaves an editor today) |
| The side panel saved or cancelled | On the cell that opened it (as today) |
| The picker chose or was cancelled | On the cell that opened it (as today) |
| A question answered with Cancel | Back in the editor (as today) |

A cell being edited is still left alone by patches (`phx-update="ignore"` on that one cell, the owner-kept exception), so a live update of the row does not take what is typed.

### 2.7 Column widths from the keyboard

The handle at the end of each header is dragged with the pointer, as today, and is **no** Tab stop (17 fewer stops in the header). For the keyboard, the list that "Columns" opens gets, beside each column's box, a number field "Width of Title" (in pixels, 48 to 1000) and one button "Reset widths" (question 1). A number field is the browser's own: Up and Down Arrow change it, typing works, and a pointer can click its arrows, which is also what WCAG 2.5.7 (dragging) asks for.

### 2.8 The side panel, the picker and the question

Unchanged: they open over the page (modal) or in it (inline), as the kit says; focus goes into them, Escape is "Cancel", and focus goes back to what opened them. Inside the picker the table is a table like the others, with its controls as Tab stops. Its rows' choice is a radio button per row (single) or a box (several); see question 8.

### 2.9 Focus after the page changes

The rows are replaced when a person sorts, filters or changes page, and a row when a live update changes it.

- A row that is patched in place keeps its elements (same ids), and focus stays where it was. LiveView does this by itself.
- When the focused element is gone (a sort, a filter, another page, a row taken out), focus goes, in this order: to the element with the same id, if it is back; to the same place (the same stop of the row at the same position); to the row after, else before; to the table's first stop. The page does not scroll for it.
- After a destroy: the same stop of the row after, else before (as today).
- After a create: the first stop of the new row (as today, `ash_data_table:focus`, which names an element that is a stop).
- After "Clear filters": the first control of the filter row. After one filter's own clear button: that filter's value.
- Read again: the table's first stop.
- When a live update takes away the row being edited: the row stays until the edit ends (as today), then the rule above.

### 2.10 Is this an established pattern?

Yes. The established table pattern is a native table where **only the interactive controls** are Tab stops, and this design follows it. The APG's table pattern has no keyboard interaction of its own ("Not applicable") and says "each widget contained in a table is a separate stop in the page tab sequence": the widgets, not the cells ([APG, Table pattern](https://www.w3.org/WAI/ARIA/apg/patterns/table/)). The A11y Project calls the idea that `tabindex="0"` on non-interactive elements "helps" a "myth" that "does not create a good assistive technology experience" ([Use the tabindex attribute](https://a11yproject.com/posts/how-to-use-the-tabindex-attribute/), 2021). A screen reader reads a read-only cell with its own table keys without it being focusable. The first draft made every cell a stop, so that a sighted keyboard user could reach every value; that gave focus to elements with no action and doubled what a screen reader already does, and the owner decided against it (question 14). An editable cell is a stop because it is a control: Enter, a typed character or a click edits it.

## 3. Nested tables: exactly the same model

A nested table is a table like any other. Nothing in this section is special to nesting but where the table stands in the page; every rule of section 2 holds inside it, at every depth: its controls and editable cells are stops, its read-only cells are not.

### 3.1 The Tab path from a parent row into a nested table and back

Take a task row on `/tasks`, expanded, with "Comments" open and "Reported by" closed:

1. The task's box, its expander (`aria-expanded="true"`), its editable cells, its action buttons.
2. **The relationship lines** of the expanded row, in their order. On each line: the line's button ("Comments", `aria-expanded`).
3. On an **open** line, after its button: the nested table's **heading line**, which stands on the line: "Columns", the inputs of its argument line, its create button ("New comment"), its table actions.
4. The nested table's **selection line**, while rows of it are selected.
5. The nested table's **"Skip table Comments"**.
6. Its **header row** (box, sort buttons), its **filter row** (filter controls), its **rows** left to right (their controls and editable cells; and, under an expanded comment, that comment's lines and nested tables: the same path one level down), its **pagination**, its link "Open in full view: Comments".
7. **Back out**: the next line of the task ("First comment", …, "Reported by": its button only, as it is closed), then the next task row's box.

Shift+Tab walks the same path backwards. No key leaves or enters a nested table: it is simply further down the page. Escape no longer leaves it (today it went to the cell that holds it).

### 3.2 Two levels deep, and several open at once

- **Two levels:** a comment row inside "Comments", expanded, with one of its lines open: its nested table's path (step 3 to 6) stands after that line's button, inside step 6 of the level above. After it, Tab goes on to the comment's next line, then the next comment row, and at the end of "Comments" out to the task's next line. Every level is the same.
- **Several open at once:** two lines of one row open ("Comments" and "Reported by"), or lines open under two rows: each nested table stands under its own line, and Tab goes through them in page order, one after the other. There is no shared state between them: no tab stop to remember, nothing that one table's hook knows of another's.

### 3.3 What a nested table's "Skip table" skips

Only that nested table: from its link to just after its pagination and full-view link (`ID-end` of the nested table's id). Focus lands on the target; the next Tab is the next line of the row around it, or the next row. The table around it is not skipped; its own "Skip table" (at its top) skips it with everything nested in it.

### 3.4 How a screen reader hears where a nested table starts and ends

- **Start:** the table is a `role="table"` named by its line and its row (`aria-labelledby` the line's button and the row's first data cell, as today: "Comments Write the report"). A screen reader says the table, its name and its size ("table, Comments Write the report, 4 rows, 6 columns", in its own words) when focus or its cursor enters it. The "Skip table Comments" link before it says the same name.
- **End:** screen readers say when they leave a table ("out of table", in their words); the skip target after the pagination is empty and says nothing. The pagination of a nested table is a group named "Pagination: Comments" (as today), so its buttons are not taken for the parent's.
- **Captions:** not added. `aria-labelledby` names the table already, and a visible `<caption>` would repeat the line's button above it. (A kit may draw one; `KitCase` accepts either.)
- **Row and column numbers** of a nested table are its own (`aria-rowcount`, `aria-rowindex`, `aria-colindex`), as today.

### 3.5 Focus when a nested table opens and closes

| What | Focus |
| --- | --- |
| Enter or Space on a closed line's button: the table opens | Stays on the line's button. The nested table stands after it; Tab goes into it. Its status ("Loading…", then the count) is read out by its live region |
| Enter or Space on the expander of a row: the lines appear | Stays on the expander. Tab goes to the first line's button |
| Enter or Space on an open line's button: the table closes | Stays on the button |
| A line or a row closes while focus is inside what it holds (another way: a live update, a page change of the parent) | On the line's button, else on the row's expander, else the rule of 2.9 (as today) |
| The nested table's rows change (its sort, filter, page, a live update) | The rule of 2.9, inside that table only |

## 4. The markup

### 4.1 Roles and attributes

| Element | Today | New |
| --- | --- | --- |
| The `<table>` | `role="grid"`, `aria-multiselectable` | `role="table"`. No `aria-multiselectable` (ARIA allows it only on grid, listbox, tablist, tree). Keeps `aria-label`/`aria-labelledby`, `aria-rowcount`, `aria-colcount`, `aria-busy` |
| Row groups, rows | `role="rowgroup"`, `role="row"`, `aria-rowindex`, `aria-selected` on a record's row | Same roles and `aria-rowindex`. **No `aria-selected`**: the checked box says it (question 7) |
| A header cell (`<th>`) | `role="columnheader"`, `tabindex="-1"`, clicked to sort | `role="columnheader"`, `aria-sort` where it sorts. A sortable header holds a `<button>` with the label and the sort mark; the button is the stop. A header that does not sort has no `tabindex` and is no stop |
| A data cell (`<td>`) | `role="gridcell"`, `tabindex="-1"` | `role="cell"`. `tabindex="0"` only on an **editable** cell; none on a read-only cell, and none on a cell that holds controls (the box, the expander, the actions, a line, a nested table, the pages, the full-view link, a read-only sensitive cell's "Show"): there the controls are the stops |
| The label column's cell | `gridcell` | `role="rowheader"` (`<th scope="row">`), so a screen reader names the row as it moves down a column (question 5); a stop only where it is editable |
| A read-only cell | `aria-readonly="true"` | **Gone**: ARIA allows `aria-readonly` on gridcell, not on cell. A read-only cell is no stop; an editable cell is one and says nothing more (question 2) |
| A failed cell | `aria-invalid="true"`, `aria-describedby` the message | `aria-describedby` the message only: `aria-invalid` is not for `cell` (its global use is deprecated in ARIA 1.2). The hook finds a failed cell by `data-failed` |
| The expander, a line's button | `<button tabindex="-1" aria-expanded>` | `<button aria-expanded>`, a stop |
| The boxes | `<input type=checkbox tabindex="-1">` | `<input type=checkbox>`, a stop, named "Select row" / "Select all rows of this page" (as today) |
| Filter controls, action buttons, nested heading and pagination buttons | `tabindex="-1"` | No `tabindex`: native stops |
| A column's handle | `role="separator"`, reached with F2 | Pointer only, `aria-hidden="true"`, no stop (question 1) |
| The scroll area (`ID-grid`) | `tabindex="-1"` | Same: the area is no stop; its contents are |

A table is drawn with native `<table>`, `<tr>`, `<th>`, `<td>`, and keeps its explicit roles: they are the markers the hooks find elements by (stage 7 D2), they let a kit draw with other elements, and they keep the semantics where CSS `display` would take them away (Roselli, see ADR 0003).

### 4.2 Labels

- The table: by its name (`aria-label`) or, nested, by its line and the row it belongs to (`aria-labelledby`, as today: "Comments Write the report").
- "Skip table": its text names the table.
- Every control has a name, as today: the boxes, "Related records" on the expander, the line by its relationship, "Filter Title" and its siblings, each action by its label, "Go to page 3".
- The sort button: the column's label; the header's `aria-sort` says the direction (the mark ▲▼ stays `aria-hidden`).

### 4.3 Live regions

Kept as they are: the status (`role="status"`: "12 results", "Title was not saved: …", "Archive: done"), the selection count, what "Columns" hid or showed, the alerts.

## 5. The hook

### 5.1 What goes

| Where | What | About |
| --- | --- | --- |
| `grid/tree.js` | The shared tab stop of the tree (`tree()`, `activeId`, `owner`, `trail`, `trailOf`, `setActive`), restoring the tab stop after each patch (most of `sync`), `move`, `stops`, `vertical`, `inColumn`, `cellAt`, `lastRow`, going "into" a cell (`enter`), the keys inside a cell's controls (`onControlKeydown`, `toControl`, `typedInto`) | 230 of 450 lines |
| `grid/expanding.js` | The arrow, Home, End, Page, F2 and Ctrl handling of `onKeydown`, `pageRows`, `enterNested`, `lineControls`, `follow` | 160 of 200 lines; a keydown of about 40 lines stays |
| `grid/hiding.js` | `seenNear`, `step`, `edge` (hidden columns are passed over by the browser) | 40 lines |
| `grid/selecting.js` | `extend` (Shift+Arrow selects as it goes) | 25 lines |
| `grid/widths.js` | `onResizeKeydown` | 30 lines |
| `grid/index.js`, `saving.js`, `editing.js`, `pagination.js` | `pos`, `col`, the `tabindex` writes, the `[tabindex="0"]` lookups | 30 lines |
| `grid/shared.js` | `SELECT_KEYS` stays (a closed menu); `page.tabbing` stays | — |

About **500 lines go**, of about 3,370 in `assets/js/grid/`. About **150 come**: a small keydown (Enter, Shift+Enter, Escape, a typed character, on the focused editable cell), a focus repair after patches (section 2.9), the width fields in the Columns list, and the `data-failed` marker. So `grid/` ends at about 3,000 lines.

### 5.2 What stays

Editing and saving (the editor in the cell, the side panel, the picker, the question, controlled mode's held saves), the "Clear" of a sensitive cell, showing a sensitive value, the whole text of a cell, painting the selection (now only the boxes' `checked`), selection events and `ash_data_table:select`, column widths and hiding, scrolling sideways and the scrollbar at the bottom edge, bringing a focused element out from under the sticky label column (`intoView`, now on every Tab), renumbering `aria-rowindex`, live updates while a cell is edited (`beforeUpdate`, `leaving`), the sender, the counter of a text, the transport.

## 6. The kit contract

| Contract | Change |
| --- | --- |
| Markers (`Attrs` `@markers`, `markers.js`) | `[role=grid]` → `[role=table]`, `[role=gridcell]` → `[role=cell]`, plus `[role=rowheader]`; `[data-failed]` new |
| `Attrs` bundles | `table/9` loses `selecting` (no `aria-multiselectable`); `gridcell/3`, `spanning/3`, `header/3` write `role="cell"` and the stop rule of 4.1; `column_header/5` gives the sort button its bundle (`phx-click`, `aria-*`) and the `th` keeps `aria-sort`; new `skip/2` and `skip_target/1`; `Item`'s cell attributes write `tabindex="0"` on an editable cell in place of `aria-readonly` on a read-only one (no edit description, question 2) |
| `Ids`, `ids.js` | New `skip(id)`, `skip_target(id)` (`ID-skip`, `ID-end`), `sort(id, column)` |
| `owned.js` | `tabindex` and `aria-selected` leave the list (the server renders `tabindex`, and no hook writes it); `aria-invalid` and `aria-readonly` leave it (no longer used); `data-failed` comes ("given") |
| Kit version | Contract **3**: the grid's markup changes for every kit (`Kit.Default`, the demo's `DivKit`, the React kit). Greenfield: no support of contract 2 (stage 7 D15) |
| `KitCase` | Asserts the new roles, the stop rule (an editable cell is a stop; a read-only cell, a header that does not sort and a cell with a control are not), the skip link and its target, and that no element has `aria-readonly`, `aria-invalid` on a cell, or `aria-selected` |

## 7. The React kit (stage 8)

R0 is done; R1 (tooling) does not touch the grid. Order, as decided: **this change as stage 8a, after R1 and before R2** (question 10), so the React grid is built once, on the new markup.

- `mountGrid` stays, simpler: no shared tree state across the grids React draws, no roving `tabindex` that React's re-renders could undo ("once" goes from the owned list), no arrow walk to test.
- R2's scope loses the keyboard-grid checks (arrow keys, roving tabindex, the tab stop across nested grids) and gains the Tab order and the skip link on the React page.
- C6 (`owned.js`) shrinks, as section 6 says.
- The spike's "arrow keys work on React's DOM" is no longer needed.

## 8. The browser suite and the other tests

Counted at `9543abd` in `demo/e2e/` (51 spec files, 902 tests):

| What a test uses | Tests | Spec files |
| --- | --- | --- |
| Arrow keys, Home, End, Page Up/Down, Ctrl+Home/End | 105 | |
| F2 | 21 | |
| The tab stop (`tabStop`, `tabindex`) | 104 | |
| `role=grid` or `gridcell` | 15 | |
| **Any of these** | **182** | **41** |

The heaviest: `actions.spec.ts` (21), `nesting.spec.ts` (18), `components`, `navigation`, `selection` (10 each), `editing` (9), `hiding` (8), `filtering` (7). `navigation.spec.ts` is rewritten whole, as the Tab-order spec. Besides, `support/table.ts` changes its role selectors (`[role=gridcell]` in about a dozen locators) and drops `tabStop`; `support/a11y.ts` drops its one exception (axe's "scrollable region must have keyboard access" for nested grids: their areas now hold stops).

New specs: the Tab order through `/tasks` and through open nested tables (section 3: two levels deep, two open at once, back out to the parent's next row; a walk that lists the stops and passes over read-only cells); "Skip table" top and nested; focus after sort, page change, live update of the focused row, destroy, create; Tab out of an editor saves; the width fields. The axe checks of every state stay; they now also check the table roles.

Elixir tests: 38 demo test files and `test/owned_test.exs` name `gridcell`, `tabindex`, `aria-selected` or `aria-readonly`; most through `demo/test/support/table_page.ex`, which changes first. The 17 markup snapshots are made again and reviewed.

Guides: `keyboard-and-accessibility.md` is rewritten (69 passages about arrows, F2 or the one tab stop), and short passages change in 15 other guides (most in `nested-tables.md` and `selecting-rows-and-bulk-actions.md`) and `CHANGELOG.md`.

## 9. Performance

- **DOM size:** the same, plus per table two small elements (the skip link and its target) and a `<button>` in each sortable header. Per row a little less: read-only cells lose their `tabindex="-1"`, an editable cell's `tabindex="0"` is as long as it was, and `aria-readonly`/`aria-invalid` go. Measured with `demo/perf/baseline.mjs` on `/tasks` (bytes per action within 2 %, times within 20 %). K1 with the edit description of question 2's first decision (`aria-describedby="ID-editable"` on each editable cell) cost **+9.0 %** on a page change; the same markup without it **+1.1 %**, so the description was dropped (question 2, decided again). Measured again after the drop (2026-10-19, `93e0bee` before K1 against `c0dcd2f`, `PERF_WIRE=1`, 15 repetitions, old, new, new, old back to back; load 17 falling to 3), bytes per action: page change 156,341 → 158,126 (+1.1 %), cell save +0.8 %, cell save with a nested table open +0.6 %, open a nested table +0.5 %, expand −1.0 %, cell save in a nested table −5.0 %, the panels and selecting a row unchanged; **open the picker +2.4 %** (30,002 → 30,726; its two-frame case 37,648 → 38,721, +2.9 %), over the budget: the picker's table is drawn whole each time it opens, with its new skip link, skip target and a sort button per sortable header. Put to the owner, who accepted it (question 15). One cause is the row header: the label column's `th` is drawn by a loop of its own between the loops of the cells before and after it, which sends two comprehensions more per row and the cell's template three times (the same markup without that split: page change +0.2 %, the picker's two-frame case +1.8 %).
- **The cell's body drawn once** (K1's drift check, 2026-10-19: one private function component for what the `td` and the label column's `th` hold, in place of the template written in each of the three loops). Measured 2026-10-19 against `93e0bee` (`PERF_WIRE=1`, 15 repetitions; load 2.5 falling to 1.3; the old version gave the same bytes as in the measurement above, to the byte, in both of its runs), bytes per action: one loop with the `td` and the `th` under `:if` and the body a component: page change **+11.3 %** (174,025), cell save +8.3 %, open the picker +5.2 % (39,619); the three loops kept, the body a component: page change **+5.1 %** (164,315), cell save +3.7 %, open the picker +4.1 % (31,191; two frames 39,186). A function component is one level more in the diff of every cell of every row (about 15 bytes a cell), more than the statics it saves. Not built: the three loops with the body written out stay (page change +1.1 %, the picker +2.4 %).
- **Work in the browser:** less. No `tabindex` writes on every focus move, no MutationObserver records for `tabindex` and `aria-selected`, no tree walk after each patch. Tab is the browser's own: it costs nothing per key, also with 25 × 25 cells and a nested table of the same size open.
- **Tests:** a test that presses Tab hundreds of times is slow. Specs focus an element directly and press Tab only for the part of the walk they check.

## 10. Risks

| Risk | What we do |
| --- | --- |
| 1. Long Tab paths: up to about 500 stops in a page of `/tasks` where every column is editable, more with a nested table open | "Skip table" for each table; read-only columns are no stops; hiding columns shortens rows; screen-reader users have their table keys; the guide says so. Measured in the Tab-order spec |
| 2. A screen reader in browse mode may keep Enter (and typed characters) for itself on a plain cell, so the edit does not start | A click on a focused editable cell from the keyboard or from assistive technology (`click` with `detail === 0`) starts the edit as Enter does. Tried by the expert with NVDA and VoiceOver in stage K4; if it fails, a button in each editable cell (question 2's first option b) |
| 3. Typing on a cell starts an edit by accident | As today: only a printable character on an editable cell, the only cells that are stops |
| 4. A patch replaces the focused element and focus falls to the page | The focus repair of 2.9, after every patch, with a spec per case (sort, page, live update, destroy) |
| 5. Tab out of an editor now goes to the next stop, not out of the grid; a save that fails meanwhile | The cell shows its message and is described by it, the live region says it; focus is not pulled back (as with a blur today) |
| 6. The focus ring of a spanning cell (#42) | Spanning cells are no stops any more; the ring is on the line's button and on the nested table's own elements. #42 is checked again after K1, likely closed |
| 7. Screen readers announce a focusable editable cell differently | The expert's manual check (K4); the guide's "what has been tested" table says what was tried |
| 8. A kit breaks the stop rule (a cell with a control that is also a stop: a double stop; or a read-only cell made a stop) | `KitCase` asserts it; the development check warns |
| 9. A sighted keyboard user cannot focus a read-only value | They read it by eye: the table scrolls sideways as focus moves along a row's stops, and the scroll area scrolls with the arrow keys while focus is in it (the browser's). A screen reader reads it with its table keys. A cut-off text in a read-only cell, which Shift+Enter showed whole, is the one gap: not decided here, to put to the owner before K1 |

## 11. Stages

Stage 8a of [target.md](target.md), after R1 and before R2. Each stage: its own commits on `main`; during a stage only `mix test --stale` and the changed or named spec files; each of the three suites (root, demo, browser) **once** at the end of the stage; `docs/agents/architecture.md` corrected where the stage made it false; **an independent drift check** against target.md and this note. It reports; a stage is done only after it.

| Stage | What | Days | Done when |
| --- | --- | --- | --- |
| **K1. Markup** | Roles (table, cell, rowheader), the stop rule (controls and editable cells, no read-only cell), sort buttons in headers, skip link and target, no `aria-multiselectable`/`aria-selected`/`aria-readonly`/`aria-invalid` on cells, no edit description (question 2), `data-failed`, nested controls without `tabindex="-1"`; `Attrs`, `markers.js`, `Ids`/`ids.js`, `Item`, `Kit.Default`, `DivKit`, `KitCase`; contract 3; snapshots; byte measurement | 2–3 | Snapshots reviewed; `KitCase` green with the new asserts; bytes within 2 %; the K1 items of 12.1 ticked and greps 1, 3, 4 clean in `lib/` and `demo/lib` |
| **K2. Hook** | Section 5: the roving tabindex, arrows, F2 and tree memory gone; the small keydown; focus repair; `owned.js`; the width fields in the Columns list; `npm run check` | 2–3 | The walks of sections 2.2 and 3 work on `/tasks` by hand, two levels deep; `owned_test.exs` green; the K2 items of 12.1 ticked and greps 1–4 and 6 clean in `assets/js` |
| **K3. Browser suite** | The 182 tests in 41 files; `support/table.ts`, `support/a11y.ts`; the new specs of section 8 | 3–4 | The browser suite green once; axe with no exception; the K3 items of 12.1 ticked and greps 1, 4, 5 clean in `demo/e2e` and `demo/test` |
| **K4. Guides and the check by hand** | `keyboard-and-accessibility.md` rewritten; the other 15 guides and the CHANGELOG; the expert tries `/tasks` with a screen reader (NVDA with Firefox or Chrome; VoiceOver with Safari) and the result goes into the guide's "what has been tested" | 1–2 (plus the expert's time) | The guide test passes; the expert's findings are in the guide or in issues; every item of 12.1 ticked and all six greps of 12.2 clean |

**Total: 8–12 days.** Then the React kit goes on with R2.

## 12. What is removed, completely

Greenfield rule: no compatibility code, no dead code, no comment that describes the old model. Each item is removed in the stage named, and the drift check of that stage ticks it.

### 12.1 Checklist

**The hook (K2)**

- [ ] `grid/expanding.js` `onKeydown`: every case for ArrowUp/Down/Left/Right, Home, End, Ctrl+Home/End, PageUp/PageDown, F2; Right/Left opening and closing expanders and lines (#45); `pageRows`, `enterNested`, `lineControls`, `follow`. What stays (Enter, Shift+Enter, Escape, a typed character, the picker's Enter) moves to a small `keys.js` or stays as a short `onKeydown`.
- [ ] `grid/tree.js`: `tree()` and `_ashDataTableTree`, `activeId`, `owner`, `trail`, `hadFocus`, `trailOf`, `setActive`, the tab-stop part of `sync`, `move`, `stops`, `vertical`, `inColumn`, `cellAt`, `cellBack`, `lastRow`, `spans` (if no caller is left), `enter`, `onControlKeydown`, `toControl`, `typedInto`, `usable` (if no caller is left); the `onFocusin` lines that set the tab stop.
- [ ] `grid/hiding.js`: `seenNear`, `step`, `edge`, and the `setActive(this.seenNear(…))` in `columns`.
- [ ] `grid/selecting.js`: `extend` (Shift+Arrow); `selection.range` if nothing else reads it (Shift+click stays for the pointer).
- [ ] `grid/widths.js`: `onResizeKeydown` and the handle's focus; `aria-valuenow` writes (the handle is `aria-hidden`); the drag clamp's reads of `aria-valuemin`/`aria-valuemax`.
- [ ] Moved from K1 (2026-10-19), as the drag clamp reads them until the width fields: in `Attrs`, the handle's `role="separator"`, its label, `aria-valuemin`, `aria-valuemax`; in `Messages`/`Kit.Words`, `resize_column` ("Resize %{column}") and its comment "moves it with the arrow keys"; its msgid in `priv/gettext/ash_data_table.pot` and the demo's German `.po`.
- [ ] `grid/index.js`: `this.pos`, `this.col`; `"tabindex"` and `"aria-selected"` in the MutationObserver's `attributeFilter`; the header comment's "single tab stop with a roving tabindex, moved by the arrow keys" and "Enter on the cell that holds a nested table goes into it, and Escape in it comes back out".
- [ ] `grid/saving.js`, `grid/editing.js`: every `cell.tabIndex = …` and `this.tree().activeId` test.
- [ ] `grid/selecting.js` `paint`: the `aria-selected` writes on rows.
- [ ] `grid/actions.js` `refocus`, `pagination.js` `toGrid`: `[tabindex="0"]` lookups and `cellBack`, replaced by the focus repair of 2.9.
- [ ] The `aria-invalid` writes and reads on cells (`marked`, `discard`, `fail`), replaced by `data-failed`.
- [ ] `owned.js`: the entries `tabindex`, `aria-selected`, `aria-invalid`, `aria-readonly`, `aria-valuenow`; the comment's `tabindex="-1"` example of "once".
- [ ] `types.d.ts`: whatever typed the removed state (`pos`, `col`, the tree).
- [ ] Found by K1's drift check (2026-10-19): `grid/shared.js` `KEPT` (what a patch does not bring to a cell being edited) lists `aria-readonly` and `aria-invalid` and lacks `data-failed` and `tabindex`; `picker.js` `enter` reads `aria-selected` to find the current row, which breaks once the hook stops writing it: the picker's current row gets its own state; `grid/whole_text.js` `cutIn` reads `aria-invalid` (`data-failed` instead).

**The server side (K1)**

- [ ] `Attrs`: `role="grid"`, `role="gridcell"`, `aria-multiselectable`, the `"tabindex" => "-1"` of `gridcell/3`, `spanning/3`, `header/3`; `table/9`'s `selecting` argument; `gridcell/3` renamed (no name with "grid" for a cell); the "Events"/moduledoc lines that describe the one tab stop.
- [ ] `@markers` in `Attrs`: `[role=grid]`, `[role=gridcell]`.
- [ ] `Item`: `aria-readonly` in a cell's attributes, and its moduledoc line.
- [ ] The parts (`grid.ex`, `filter.ex`, `summary.ex`, `related.ex`, `heading.ex`, `pagination.ex`, `selection.ex`, `messages.ex`): every `tabindex="-1"` on a cell or control (38 today) and every `tabindex={@nested? && "-1"}`; the two `JS.focus(to: "#ID-table [tabindex='0']")`; `role="gridcell"`; the comments that explain "no tab stop, reached from its cell".
- [ ] `Parts.Look`: the rules written on `[role=grid]`/`[role=gridcell]` (19 today), on the new markers; the focus ring of a focused spanning cell (#42).
- [ ] The edit description of question 2's first decision, built in K1 and dropped on 2026-10-19 (question 2): `Ids.editable/1`, `ids.js`'s `editable` and its `/e2e/ids` sample, `Attrs.editable/1`, the `editable` text (`Messages`, `Kit.Words`, the `.pot` and the German `.po`), the hidden element in `grid.ex` and `DivKit`, the cell's `aria-describedby` to it in `Item`, `KitCase`'s check of it (now: editable cells are stops, read-only cells are not).
- [ ] `Kit`, `Kit.Default`, `KitCase`, the demo's `DivKit`: every `grid`/`gridcell` role and the asserts on them; contract 2 → 3 with no clause for 2.
- [ ] `Ids`/`ids.js`: nothing goes (new ones come); the resizer's id stays for the pointer.
- [ ] `markers.js`: `TABLE = "[role=grid]"`, `GRIDCELL = "[role=gridcell]"` become `[role=table]`, `CELL` (with `ROWHEADER`, and `DATACELL`/`ANYCELL` in `grid/shared.js`); the name `GRIDCELL` goes. (Listed under K2 at first; K1 did it with the markup, 2026-10-19.)
- [ ] `demo/test/support/table_page.ex` and the demo test files: `gridcell`, `tabindex`, `aria-selected`, `aria-readonly`; the 17 snapshots made again. (Listed under K3 at first; K1 did it with the markup, 2026-10-19.)

**Tests (K3)**

- [ ] `demo/e2e/navigation.spec.ts`: deleted, replaced by the Tab-order spec.
- [ ] In the other 40 spec files: every test of arrow navigation, F2, the one tab stop, Escape out of a nested grid, Shift+Arrow selection, keyboard resizing on the handle: rewritten to Tab and Enter, or deleted where the behaviour is gone.
- [ ] `support/table.ts`: `tabStop`, the `[role=gridcell]` locators, the comment "cell with tabindex -1, and the hook makes one of them the tab stop".
- [ ] `support/a11y.ts`: the `scrollable-region-focusable` exception and `ofNestedGrid`.
- [ ] `test/owned_test.exs` follows `owned.js` (with K2's `owned.js`). The demo test files and the snapshots moved to K1.

**Documentation (K4)**

- [ ] `keyboard-and-accessibility.md`: the sections "The grid is one tab stop", "Keys on a cell" (rewritten), "Column widths from the keyboard" (rewritten), the arrow parts of "Hiding columns", "The filter row", "Row actions", "Selecting rows", "Rows that expand", "Focus after the page changes", the rows of "What assistive technology is told" for `role="grid"`, `aria-multiselectable`, `aria-selected`, `aria-readonly`, the separator, and "Things people trip over" about arrows, F2 and Tab leaving the grid.
- [ ] The 15 other guides with arrow, F2 or tab-stop passages (list in section 8); `README.md`; a CHANGELOG entry that says what was removed.
- [ ] `docs/agents/architecture.md` ("The five hooks"), `react-kit-design.md` (the spike's "arrow keys, roving tabindex" as history only, marked so). target.md is amended already (D-tab, stage 8a).
- [ ] Issues #43 and #45 closed as superseded, with a link to ADR 0003.

### 12.2 The greps the drift check runs

Run from the repository root. After each stage, the greps over the folders that stage cleared (its done-criterion in section 11) print nothing but the hits listed as allowed beneath them; after K4, all six over every folder.

```sh
# 1. The grid role and the roving tab stop, in code, kits, tests and guides
grep -rnE 'role=\\?"?grid\b|"role" => "grid"|gridcell|GRIDCELL|aria-multiselectable|roving|tabStop|activeId|_ashDataTableTree|trailOf|setActive|enterNested|onControlKeydown|onResizeKeydown|seenNear|extend\(cell' \
  lib assets/js demo/lib demo/assets/js demo/test demo/e2e/*.ts demo/e2e/support test documentation README.md
# allowed: lib/ash_data_table/kit_case.ex (the checks that these are absent) and lib/ash_data_table/kit.ex (the history of the contract versions and `changed/1`)

# 2. Arrow, Home/End, Page and F2 handling of ours
grep -rnE '"(Arrow(Up|Down|Left|Right)|Home|End|PageUp|PageDown|F2)"' assets/js
# allowed: grid/shared.js SELECT_KEYS and grid/saving.js `lastKey` (the keys of a closed menu in an editor: the browser's, which we only watch)

# 3. tabindex: only "0" on an editable cell, "-1" on the scroll area and the skip target
grep -rnE 'tabindex|tabIndex' lib assets/js demo/lib
# allowed: Attrs (the stop rule, the scroll area, the skip target, the scrollbar at the bottom edge `tabindex="-1"`), item.ex (the stop rule: `tabindex="0"` on an editable cell), the parts that spread them, the whole-text button (`tabIndex = -1`, no stop on purpose), panel.js FOCUSABLE, KitCase and Kit (the checks of the stop rule and the contract that states it)

# 4. ARIA that a table cell or row does not take
grep -rnE 'aria-readonly|aria-selected' lib assets/js demo/lib demo/test demo/e2e
grep -rnE 'aria-invalid' assets/js lib/ash_data_table/item.ex lib/ash_data_table/parts/grid.ex
# allowed: aria-invalid on panel fields, filter inputs and argument inputs (form controls), not on a cell; aria-selected and aria-readonly: none but the checks of their absence in KitCase, Kit (the contract) and the demo tests

# 5. Arrow keys pressed in the browser suite
grep -rnE 'press\("(Shift\+)?Arrow|press\("(Control\+)?(Home|End|PageUp|PageDown)"|press\("F2"' demo/e2e/*.spec.ts
# allowed: inside an editor's or a filter's own control (a menu, a slider, a number field, the width field), each with a comment naming the control

# 6. Words of the old model in comments and guides
grep -rniE 'arrow key|one tab stop|single tab stop|the tab stop|tree of grids|into the (grid|nested table)|out of the grid|leave[s]? the grid|\bF2\b' \
  lib assets/js demo/lib demo/e2e documentation docs/agents README.md
# allowed: the CHANGELOG entry that says it was removed; the history sections of the design notes in docs/architecture
```

## 13. What this note does not change

The events and replies of S6, the server's pushes, `Operation` and every safety rule, the stream items' shape (apart from the cell attributes of K1), controlled mode, the panel and picker hooks, the look.

## 14. The questions, decided (owner, 2026-10-19)

The owner took every recommendation ("as recommended") but question 14, which he decided the other way. Each answer is marked **Decided**.

1. **Column widths from the keyboard.** a) the handle a Tab stop, a separator moved with the arrow keys (today's keys, one more stop per column); b) the handle pointer-only, and a width field per column in the Columns list, with "Reset widths"; c) no keyboard resizing. c fails WCAG 2.1.1. **Decided: b**: no arrow keys of ours, fewer stops, and the field also serves a pointer without dragging (WCAG 2.5.7).
2. **How an editable cell says it is editable, now that `aria-readonly` is not allowed on a cell.** a) the cell (`tabindex="0"`) is described by one hidden text per table, "Editable: press Enter" (`aria-describedby`, beside a failure's message); b) a `<button>` in every editable cell that holds the text (a widget a screen reader activates for sure, but more bytes on every row and a new cell markup for every kit); c) say nothing. **Decided: a**, with the keyboard click of risk 2; **b** as the fallback if the expert's check in K4 shows a screen reader cannot start an edit. **Decided again, 2026-10-19, after K1's byte measurement: no description.** K1 built a: every editable cell said `aria-describedby="ID-editable"`, which cost +9.0 % on a page change of `/tasks` (`demo/perf/baseline.mjs`, `PERF_WIRE=1`), against +1.1 % for the same markup without it and the budget of 2 %. The owner was given three options: a) keep it; b) drop it: an editable cell is a Tab stop (`tabindex="0"`) and says nothing more, a failed cell is described by its message only; c) the hook describes only the focused cell. **Decided: b** (owner, "as recommended"). c is looked at again only if the expert's screen-reader check in K4 shows that editable cells go unrecognised; the button in each cell (first option b) stays the fallback if an edit cannot be started.
3. **The sort control.** a) a `<button>` inside the `<th>`, `aria-sort` on the `<th>` (as the APG's sortable table example); b) the `<th>` itself focusable and clicked. **Decided: a**: a real button needs no key handling of ours, and a screen reader says "button".
4. **The skip link's text and place.** **Decided:** "Skip table *Name*" (Gettext `"Skip table %{name}"`), placed after the heading line and the selection line and before the header row, jumping to after the pagination. Visible only while it has focus.
5. **The label column as row header.** **Decided: yes**: where the table has a label column, its cells are `<th scope="row" role="rowheader">`, so moving down a column names each row. No label column: no row header.
6. **Headers and cells with nothing to do: stops or not?** **Decided** with question 14: only interactive elements are stops. A header that does not sort is no stop (the headers over the expanders, "Related records", and over the actions, "Actions", included); an empty filter cell and the empty header over the boxes when rows are not selectable are no stops either.
7. **Selection state.** a) `aria-selected` on the row as today; b) only the checkbox's own `checked`. **Decided: b**: in a table the box is the control, and the hook stops writing `aria-selected` on rows.
8. **The picker's rows (one record at a time).** Its radio buttons are one group, and the browser makes a radio group one Tab stop moved with the arrow keys. a) keep the native group (the browser's keys, which assistive technology knows); b) a box per row that unticks the others. **Decided: a**: the arrows are the browser's, not ours; Tab goes into the group and out.
9. **F2.** **Decided: dropped.** Enter does all F2 did.
10. **When to build.** **Decided:** as stage 8a, after R1 and before R2 of the React kit, so the React grid is built once, on the new markup.
11. **Focus after a live update takes away the focused row.** **Decided:** the same stop of the row after, else before, else the table's first stop; nothing announced besides what the live region says today (a row that went is not read out).
12. **Shift+Arrow range selection.** It goes with the arrows. **Decided: not replaced**: Space on each box, the page's box, and "Select all … that match"; Shift+click stays for the pointer.
13. **Escape in a filter's input.** Today it gives up what was typed and goes back to the cell. **Decided:** it gives up what was typed and focus stays in the input.
14. **Read-only cells as Tab stops.** The sources lean against focusable non-interactive cells (section 2.10): the APG's table pattern puts only widgets in the Tab order, and the A11y Project calls `tabindex="0"` on non-interactive elements a myth that does not help. a) every cell a stop, as first planned; b) only controls and editable cells are stops, read-only cells are read with the screen reader's table keys and seen by eye. **Decided: b**, changed from the first plan. The owner, after an explanation: "readonly cells not focusable". The expert's "every element" is read as "every interactive element"; in top and nested tables alike.
15. **The picker's bytes (K1).** Opening the picker cost +2.4 % (two frames +2.9 %) after the description went, over the budget of 2 % (section 9). **Accepted by the owner (2026-10-19)**, unless drawing a cell's body once brought it under 2 %. It did not (section 9: +4.1 % that way), so K1's markup stays and the +2.4 % is accepted.

Process note (K1, 2026-10-19): #46 (the focus rings) was closed with K1's commits, before K1's drift check had run; a stage's issues are closed after its drift check.
