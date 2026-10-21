# The screen-reader check of stage 8a: a checklist by hand

For the accessibility expert. The tab model (ADR 0003, [0003-table-semantics-controls-in-the-tab-order.md](../adr/0003-table-semantics-controls-in-the-tab-order.md)) is done only once this check has been run and its result written into the guide's "What has been tested" ([keyboard-and-accessibility.md](../../documentation/topics/keyboard-and-accessibility.md#what-has-been-tested)) or into issues.

**What the table is now:** a plain table (`role="table"`). Every control and every editable cell is a Tab stop; a read-only cell is not, and is read with the screen reader's own table keys. No arrow key of the table's own. A link "Skip table *Name*" before each table, nested ones too.

## Set-up

- The demo: `cd demo && mix phx.server`, then http://localhost:4478. Pick **Ada Admin** with the actor switcher at the top (she may edit everything).
- Run each part with:
  - **NVDA** on Windows, in **Firefox** and in **Chrome**;
  - **VoiceOver** on macOS, in **Safari** (turn on "Press Tab to highlight each item" in Safari's settings, Advanced).
- Use browse mode (NVDA) or the VO cursor (VoiceOver) where a step says "read"; use Tab where it says "Tab".
- Write the result of each step in its last column: ✅ as expected, ❌ with what was heard or what happened, or ➖ not tried.

## A. `/tasks`: the table on the page

| # | Do | Expected | NVDA + Firefox | NVDA + Chrome | VoiceOver + Safari |
| --- | --- | --- | --- | --- | --- |
| A1 | Tab from the top of the page into the table | "Columns", the search field, "New task", then **"Skip table Tasks"** (a link, shown at the table's top left) | | | |
| A2 | Tab on: the header | The box "Select all rows of this page", then the sort buttons by column name ("Title, button", sort state). Headers that do not sort are not reached | | | |
| A3 | Tab on: the filter row | Each filter's controls by name: "How to filter Title", "Filter Title" | | | |
| A4 | Tab on: the first row | "Select row" box, "Related records" button (collapsed), then the **editable cells** only, left to right: Title, State, Priority, Progress, Estimate hours, Billable?, Due on, Completed at, Description, Tags, Checks, Repeats, Project, Assignee (after a cell that cuts its text off, its "Show all" button), then the row's action buttons. Read-only cells ("Overdue?", "Comments", "Headline", "Due within 7 days", "Due within", "External ref", "Inserted at", "Reported by") are passed over | | | |
| A5 | On the Title cell: what is said? | The cell's value, its column header ("Title"); the row is named by its title (row header). **Q2: can you tell that this cell can be edited, without any extra text?** Write down exactly what is said | | | |
| A6 | Read the table with the table keys (NVDA: Ctrl+Alt+arrows; VoiceOver: Ctrl+Option+arrows) | The screen reader says it is a table, its name "Tasks" and its size; moving reaches every cell, read-only ones too; moving down a column names each row by its title | | | |
| A7 | **Risk 2.** Tab to a Title cell and press **Enter**, without leaving browse mode first | Editing starts: a text field with the title, focus in it. If nothing happens, or the screen reader does something else: ❌ and say which mode it was in | | | |
| A8 | In the editor: change the text, press Enter | Saved; focus back on the cell; the new value is read | | | |
| A9 | Open the editor again, type, press **Tab** | Saved, and focus on the next stop of the row | | | |
| A10 | Open the editor again, type, press **Escape** | Nothing saved; focus back on the cell, old value | | | |
| A11 | On the "Billable?" cell, Enter | The value toggles and is saved; "Yes"/"No" is read | | | |
| A12 | Make a save fail: in a Title type `ab` (too short), Enter | The message is read out ("… was not saved: …"); focus on the cell, which is described by the message. Escape gives it up | | | |
| A13 | **"Show all".** Narrow the window until a Title is cut off ("…"), Tab to the button after it | "Show all of Title, button, collapsed". Enter: the whole text shows, "expanded". Enter again: cut off. **Then press Escape on the button**: nothing happens (by design). Is that a problem? | | | |
| A14 | Sort: Tab to the "Title" sort button, Enter twice | The sort state is said (ascending, descending); focus stays on the button | | | |
| A15 | Space on two rows' boxes | "checked"; the line above the table says "2 selected" (read out). Shift+Tab reaches "Clear selection" and the bulk actions before "Skip table" | | | |
| A16 | "Clear selection" | Read out; focus on the table's first stop | | | |
| A17 | Tab to the pagination, use "Next" | Page 2; focus stays on "Next"; "Pagination: Tasks" is a landmark | | | |
| A18 | Back at the top: "Skip table Tasks", Enter, then Tab | Focus goes past the table and its pages | | | |
| A19 | **Risk 2, a typed character, browse mode.** Tab to a Title cell and, without leaving browse mode, type a letter (for example `z`) | Editing starts with that letter: the text field holds only `z`. Escape: nothing saved, the old title is back. If the screen reader takes the letter for itself (a jump to another element, a sound) or nothing happens: ❌ and say what happened | | | |
| A20 | **Risk 2, a typed character, focus mode.** The same as A19 in focus mode (NVDA: NVDA+Space; VoiceOver: Quick Nav off) | As A19 | | | |
| A21 | **Space on an editable cell**, first in browse mode, then in focus mode: Space on a Title cell; then Space on a "Billable?" cell; then Space on an "Assignee" cell | Space acts as Enter. On Title: the editor opens with the title as it was, nothing replaced (Escape gives it up). On Billable?: the value toggles and is saved, "Yes"/"No" is read. On Assignee: the picker opens (Escape: focus back on the cell). The page never scrolls | | | |
| A22 | **Column widths.** Tab to "Columns", Enter; Tab through the list | Each column's box, and its number field "Width of *Column*" (the label column first, with a field and no box), then "Reset widths". In "Width of Title" type `400`, Tab: the column is 400 pixels wide. Up and Down Arrow in the field change the width. "Reset widths": every column has its first width again. Escape closes the list, focus back on "Columns" | | | |

## B. Nested tables (`/tasks`)

| # | Do | Expected | NVDA + Firefox | NVDA + Chrome | VoiceOver + Safari |
| --- | --- | --- | --- | --- | --- |
| B1 | On the first task, Enter on "Related records" | "expanded"; focus stays. Tab: the lines "Comments", "Labels", "Project", … each a button, collapsed | | | |
| B2 | Enter on "Comments", then Tab | Focus stays on "Comments" (now expanded). Tab: the nested table's "Columns", "New comment", then **"Skip table Comments"**, then its header, filters and rows | | | |
| B3 | Read the nested table with the table keys | It is announced as a table named "Comments" and the task's title; where it starts and ends is clear ("out of table" at its end) | | | |
| B4 | Edit a comment's body in the nested table (Enter, type, Enter) | As A7–A8 | | | |
| B5 | Two levels: in "Comments", expand a comment, open one of its lines | Tab goes through that table inside the comments; after it, the comment's next line, the next comment, and after the comments the task's next line | | | |
| B6 | Open "Comments" and "Labels" at once | Each table in its own place; Tab goes through one, then the other | | | |
| B7 | "Skip table Comments", Enter, Tab | Past the comments only: the next stop is the task's next line | | | |
| B8 | Close "Comments" while focus is inside it (Shift+Tab back to "Comments", Enter) | Focus stays on "Comments"; "collapsed" | | | |

## C. `/projects`: side panel, row actions, a confirm question

| # | Do | Expected | NVDA + Firefox | NVDA + Chrome | VoiceOver + Safari |
| --- | --- | --- | --- | --- | --- |
| C1 | On a project's "Client" cell, Enter | The side panel opens as a dialog, named by its heading; focus in its first field | | | |
| C2 | Tab through it, Escape | Escape is Cancel: the panel closes, focus back on the "Client" cell | | | |
| C3 | A row's "Set status" button | The action panel opens; run it; "Set status: done" is read out; focus back on the button | | | |
| C4 | A row's "Destroy" button. **Note:** destroying a project deletes all its tasks. To have the demo's records back afterwards, run `mix run priv/repo/seeds.exs` in `demo` (it empties the database and fills it again; the server may keep running), then reload the page | The question opens with focus on "Cancel"; Escape: nothing runs, focus back on "Destroy". Again, then confirm: the row goes, the result is read out, focus on the same stop of the next row | | | |
| C5 | "Budget" of a row as Max Member (switch actor): its "Show" button | The value is shown and read; Escape hides it | | | |

## D. The picker (`/tasks`)

| # | Do | Expected | NVDA + Firefox | NVDA + Chrome | VoiceOver + Safari |
| --- | --- | --- | --- | --- | --- |
| D1 | On a task's "Project" cell, Enter | A dialog "Project: choose …"; focus on the radio button of the current project | | | |
| D2 | Up and Down Arrow | They move among the rows' radio buttons (the browser's radio group), each named "Select row" in its row | | | |
| D3 | Enter on a radio button | That project is chosen; the question "Move this task to another project?" opens; Cancel: back in the cell, nothing saved | | | |
| D4 | In the picker, Escape | Closes it; focus back on the "Project" cell | | | |

## E. In German

| # | Do | Expected | NVDA + Firefox | NVDA + Chrome | VoiceOver + Safari |
| --- | --- | --- | --- | --- | --- |
| E1 | Switch the language to German (beside the actor switcher), repeat A1, A4, A13 and B2 | "Tabelle Aufgaben überspringen", "Zeile auswählen", "Zugehörige Einträge", "Alles zeigen: …" with the column's name; the screen reader's own words in its language | | | |

## F. Open questions to answer

| # | Question | Answer |
| --- | --- | --- |
| F1 | **Risk 2:** did Enter, Space and a typed character on a focused editable cell start the edit in browse mode, in each screen reader (A7, A19, A21)? If not: the fallback is a button in each editable cell | |
| F2 | **Q2:** were editable cells recognisable as editable, without a description (A5)? If not: the fallback is a description of the focused cell only | |
| F3 | **Escape on "Show all"** does nothing (A13). Should it cut the text off? | |
| F4 | Is the Tab path through a long table workable with "Skip table"? Too many stops? | |
| F5 | Anything else heard that was wrong or confusing | |

## Result

- Tried by: ______ on ______ (date), screen-reader and browser versions: ______
- Summary: ______
- Issues opened: ______
