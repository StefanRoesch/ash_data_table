# Table semantics, controls in the Tab order, no arrow keys

Status: accepted (2026-10-19).

## Context

Every table has been an ARIA grid (`role="grid"`): one Tab stop for the whole tree of tables, a roving `tabindex`, and arrow keys, Home, End, Page Up/Down, F2 and Escape to move between cells, into a cell's controls and into and out of nested tables. That is the WAI-ARIA Authoring Practices' grid pattern: "Only one of the focusable elements contained by the grid is included in the page tab sequence" ([APG, Grid pattern](https://www.w3.org/WAI/ARIA/apg/patterns/grid/)). The APG calls it "particularly useful if the tabular information is editable or interactive", and says of tables that "since a table is not a widget, each widget contained in a table is a separate stop in the page tab sequence", and that replacing a table with a grid "can dramatically reduce the length of the page tab sequence" ([APG, Table pattern](https://www.w3.org/WAI/ARIA/apg/patterns/table/)). Its table pattern has no keyboard interaction ("Not applicable").

The owner found the walk through expanded rows and nested tables hard to follow (#43, #45), and asked an accessibility expert whether to keep one Tab stop with arrow keys or Tab through everything. The expert's answer (2026-10-19): "the best and simplest thing is if every element is accessible via Tab and not arrow keys; the tools people with special needs use do the arrow thing on their own; each element of the table and nested table reachable via Tab and the ARIA attributes set."

That matches a known critique of the grid role for data tables. Adrian Roselli, [ARIA Grid As an Anti-Pattern](https://adrianroselli.com/2020/07/aria-grid-as-an-anti-pattern.html) (2020, updated 2022): "For simple tabular data, an HTML `<table>` is all you need", "you should probably ignore ARIA `grid` unless you are trying to recreate Excel", and, as grid semantics "are only exposed to screen reader users", "a keyboard-only user will have no idea" that the arrow keys work differently. Screen readers bring their own table navigation (NVDA: Control+Alt+arrows, "staying in the same row" or column; [NVDA user guide](https://download.nvaccess.org/documentation/userGuide.html)), which works on a table and needs no script of ours. No screen reader has been tried with the grid we have (keyboard guide, "What has been tested").

## Decision

(Owner, 2026-10-19.)

- A table is a table: `role="table"`, `row`, `columnheader`, `cell`, and `rowheader` for the label column; native `<table>` elements with the roles written out, as markers and against CSS `display` taking the semantics away ([Roselli, Tables, CSS Display Properties, and ARIA](https://adrianroselli.com/2018/02/tables-css-display-properties-and-aria.html)). No `role="grid"`, no roving `tabindex`.
- Every interactive element is a Tab stop, in page order: editable cells, boxes, expanders, relationship lines, sort buttons (a `<button>` in the header, `aria-sort` on the header), filter controls, action buttons, the heading line's controls, the skip link, the pagination. **Read-only cells are no stops**: a screen reader reads them with its own reading cursor and table keys. A cell that holds controls is not a stop itself. Nested tables the same as top tables. The expert's "every element" is read as "every interactive element"; the owner, after an explanation: "readonly cells not focusable".
- A "Skip table %{name}" link at the start of each table, top and nested, before the header row, visible on focus, jumping to after its pagination.
- The table handles no arrow key, no F2, no Home/End/Page keys, and has no Shift+Arrow range selection (Shift+click stays). Controls keep the browser's own keys (a menu, a number field, a radio group). Column widths are typed in a width field per column in the "Columns" list, with "Reset widths"; the drag handle is pointer-only.
- Editing is as today: Enter or a typed character on an editable cell edits in place; arrays, maps, groups and unions open the side panel; Escape gives up. Space acts as Enter on an editable cell (owner, 2026-10-19).
- Built as stage 8a, after the React kit's R1 and before its R2.


## Considered options

- **The ARIA grid pattern, fixing the walk** (#43's decisions: arrows leave a nested grid; #45: arrows never open). Replaced: it keeps a keyboard model that sighted keyboard users do not expect and screen-reader users do not need, and its code (the shared tab stop of the tree of grids) is where the walk broke.
- **Grid with Tab between cells as well.** Rejected: two models at once, and still `role="grid"`, which puts screen readers in application mode.
- **Every cell a Tab stop, read-only cells included** (the first reading of the expert's advice). Rejected: it gives focus to elements with no action, and screen readers read cells themselves. The APG's table pattern puts the widgets in the Tab order, not the cells, and the A11y Project calls `tabindex="0"` on non-interactive elements a myth that "does not create a good assistive technology experience" ([Use the tabindex attribute](https://a11yproject.com/posts/how-to-use-the-tabindex-attribute/)).
- **One Tab stop per row, Enter into it.** Rejected: another model of our own, with "into" and "out" again.

## Consequences

- It follows the established pattern: a native table with its controls in the Tab order.
- Simpler hook: about 500 of about 3,370 lines of `assets/js/grid/` go (the shared tab stop, arrows, F2, "into" a cell, Shift+Arrow selection); about 150 come (a small keydown, focus repair after patches, width fields).
- Long Tab paths where many columns are editable: up to about 500 stops in a page of `/tasks`. "Skip table", read-only columns (no stops), hidden columns and the screen reader's own table keys are the way past.
- A sighted keyboard user reads read-only values by eye and cannot focus them. A cut-off text, read-only or editable, is shown whole from the keyboard with the "Show all" button in its cell, a Tab stop named after its column (decided by the owner).
- ARIA allows `aria-readonly`, `aria-invalid`, `aria-selected` and `aria-multiselectable` on grid roles, not on `cell` or `table` (WAI-ARIA 1.2: `aria-multiselectable` "Used in Roles: grid, listbox, tablist, tree"; `aria-invalid`'s global use is deprecated; [MDN, aria-readonly](https://developer.mozilla.org/en-US/docs/Web/Accessibility/ARIA/Reference/Attributes/aria-readonly)). So a read-only cell is not marked (an editable cell is a Tab stop, and says nothing more), a failed cell is described by its message, and the boxes say what is selected.
- A sortable header holds a button, as the APG's [sortable table example](https://www.w3.org/WAI/ARIA/apg/patterns/table/examples/sortable-table/) does, with `aria-sort` on the header.
- Column widths get a keyboard way that is not arrow keys on the handle (WCAG 2.1.1): width fields, which also give a pointer a way without dragging ([WCAG 2.5.7](https://www.w3.org/WAI/WCAG22/Understanding/dragging-movements.html)).
- Kit contract 3: every kit's grid markup changes. The React kit's `mountGrid` gets simpler, and `owned.js` loses `aria-selected`; it keeps `tabindex` as "given": the hook puts back the `tabindex` the table gave a cell that was edited, and writes no other.
- About 182 of 902 browser tests (in 41 spec files) change; the keyboard guide is rewritten.
- Whether a screen reader in browse mode passes Enter on an editable cell to the page is not known: the expert checks it by hand; the fallback is a button in each editable cell.
- Reversing it later means rebuilding the roving tabindex and its tests: costly, which is why this is an ADR.
