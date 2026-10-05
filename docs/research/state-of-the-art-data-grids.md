# What defines a state-of-the-art data grid

Research for issue #3 (part of the map #2). Researched 2026-10-05.

## Question

Which features and interactions make Airtable, AG Grid, TanStack Table, Glide Data Grid, Notion databases and the open-source Airtable alternatives (Baserow, NocoDB, Grist) feel state of the art? Sorted into: what every serious grid has, what distinguishes the best, and what is rare or expensive.

## Method and trust level

- Sources are first-party only: official product documentation, the projects' own repositories, and the W3C WAI-ARIA Authoring Practices Guide (APG). Every claim below carries a source number; the list is at the end.
- Pages were read through a fetch tool that summarises page content. Quoted passages are as returned by that tool; the Glide Data Grid and TanStack Table passages were read directly from the raw Markdown in their repositories.
- Documentation states what a product documents, not everything it does. Where a behaviour is well known but I found no first-party statement, it is marked **unverified**.
- No product was operated hands-on. Feel (latency, animation, polish) is therefore not assessed.

## Answer in brief

**Every serious grid has**

1. A single focused cell moved with the arrow keys, with Tab and Shift+Tab moving horizontally.
2. Two modes: navigation and editing. Enter or F2 starts editing, Escape cancels, Enter commits; a commit on Tab moves to the next cell.
3. Sorting from the column header, with multi-column sort available.
4. Per-column filtering with operators that depend on the column type.
5. Column resize, reorder and hide; at least one frozen (pinned) column on the left.
6. Row selection with checkboxes, then bulk actions on the selection.
7. Type-specific cell renderers and editors for a core set of types: text, long text, number, boolean, date, single choice, multiple choice.
8. A deliberate strategy for large data: pagination, or virtualised rendering with lazy loading. Never "render everything".

**The best are distinguished by**

1. Spreadsheet-grade range selection (Shift+arrows, Ctrl/Cmd+Shift+arrows to the edge, drag) with copy, cut and paste of rectangular ranges, including from Excel or Google Sheets.
2. Type-to-edit: pressing a printable character on a focused cell starts editing with that character.
3. Fill handle and fill-down (Ctrl/Cmd+D).
4. Undo and redo of edits.
5. Grouping with collapsible groups and per-group summaries, plus a footer summary bar.
6. Nested filter groups mixing AND and OR.
7. An expanded-record view opened with Space, giving a form over the same row.
8. Full ARIA grid semantics including `aria-rowcount` and `aria-rowindex` when not all rows are in the DOM, and keyboard access to header operations (sort, resize, move).
9. Validation that is declared per column and shown at the cell, with a choice between blocking the commit and reverting.

**Rare or expensive**

1. Canvas rendering for millions of rows (Glide Data Grid). It buys scroll performance and costs a parallel accessibility tree and canvas-only custom cells.
2. Server-side grouping and aggregation with lazily loaded groups (AG Grid Enterprise only).
3. Pivoting, integrated charts, master/detail, Excel export with styles (AG Grid Enterprise).
4. Multiple disjoint ranges, merged or spanning cells, variable row heights under virtualisation.
5. Relationship-derived cell types: linked record, lookup, rollup, formula.
6. Virtualised scrolling that stays correct for screen readers. AG Grid's own documentation recommends pagination instead.

AG Grid's licence split is a useful price signal: what it gives away is the baseline, what it charges for is the expensive tier. Range selection, clipboard, row grouping, the set filter and the server-side row model are all paid [2][12][13][11][14][7].

## Findings by area

### Cell navigation

- APG defines the data grid key set: arrows move one cell and stop at the edge ("If focus is on the right-most cell in the row, focus does not move"); Home and End go to the first and last cell of the row; Ctrl+Home and Ctrl+End go to the first and last cell of the grid; Page Up and Page Down move "an author-determined number of rows" [1].
- AG Grid follows this with deviations: Ctrl+Left and Ctrl+Right jump to row start and end, Tab moves across cells and headers, and Up from the first row moves focus into the header row [3].
- Airtable: arrows move between cells; Cmd/Ctrl+arrow "Jump to the edge of the table" [15].
- Grist: arrows, Tab ("Move to the next field, saving changes if editing"), Home, End, Page Up, Page Down, Ctrl+Up and Ctrl+Down to the first and last record [22].
- Baserow: arrows, Tab and Shift+Tab [19]. NocoDB: arrows, Tab ("if on last cell, move to beginning of next record"), Cmd+arrow to jump to the first or last record or field [21].
- Glide Data Grid: arrows, Ctrl/Cmd+arrow or Home/End "as far as possible in the direction pressed", Page Up and Page Down, Ctrl/Cmd+Home and End [24].
- Notion: the keyboard shortcuts page documents no arrow-key cell navigation for table views [27]. Whether it exists is **unverified**.
- Tab conflicts with APG. APG treats a grid as a composite widget with one tab stop, so Tab should leave the grid [8]; every spreadsheet-like product above uses Tab to move to the next cell. This is a decision for `ash_table`, not a settled convention.

### Editing

- The two-mode model is universal. APG: Enter "Disables grid navigation" and places focus in the input; F2 does the same and "A subsequent press of F2 restores grid navigation functions"; Escape "Restores grid navigation. If content was being edited, it may also undo edits"; alphanumeric keys on an editable cell place focus in an input [1].
- Enter or F2 to start editing: Airtable [15], Grist [22], Baserow [19], AG Grid [4]. NocoDB documents Enter only [21].
- AG Grid's full start list: Enter, F2, Backspace, any printable character, double click (or single click with `singleClickEdit`). Stop list: Enter (commit), Tab (commit and move to the next cell), Escape (discard), focus moving to another cell, and optionally focus leaving the grid (`stopEditingWhenCellsLoseFocus`). `enterNavigatesVerticallyAfterEdit` moves focus down after a commit [4].
- Editors by column type are the default in AG Grid: "string columns will use a text input, number columns will use a numeric input" [5]. Provided editors in Community: text, large text, select, number, date, checkbox. Rich select and formula editors are Enterprise [6].
- Row-level editing (all cells of a row in edit mode, one commit) exists in AG Grid as full-row editing with its own validation hook [9].
- Undo and redo: AG Grid Community has it behind `undoRedoCellEditing`, default depth 10, and "sorting, filtering and grouping, will clear the undo / redo stacks" [10]. Airtable has Cmd/Ctrl+Z and Y [15]; Baserow has undo and redo [19]. NocoDB states bulk update "cannot be undone" [20].
- Inserting a row from the keyboard: Airtable Shift+Enter [15], Baserow Shift+Enter [19], Grist Ctrl+Enter [22], NocoDB Alt+R [21].
- Expanded record: Space opens the row as a form in Airtable [15], Baserow [19], NocoDB [21] and Grist ("Show the record card widget") [22]. In Notion every row opens as a page [25].

### Selection

- APG keys: Ctrl+Space selects the column, Shift+Space the row, Ctrl+A all cells, Shift+arrow extends the selection one cell [1]. Glide Data Grid implements exactly these [24].
- Focus and selection are separate concepts: "focus is a pointer, like a mouse pointer ... There is only one point of focus at any time", and the focus indicator must stay visible and distinct from the selection indicator [8].
- Range selection: Airtable (Shift+arrows, Cmd/Ctrl+Shift+arrows to the edge) [15], Grist [22], Baserow [19], Glide (`rangeSelect`: "none" | "cell" | "rect" | "multi-cell" | "multi-rect") [23]. In AG Grid it is Enterprise [12].
- Row selection with checkboxes and bulk edit: Notion ("select multiple rows in order to edit their properties") [25], Baserow (checkbox, Shift+click, Cmd/Ctrl+click) [18], NocoDB bulk update [20], AG Grid (Space toggles row selection) [3].
- Lazy loading limits selection: Baserow allows selecting "up to 200 rows at once" because of lazy loading [30].
- Space is contested: APG and Glide use Shift+Space for row selection; Airtable and NocoDB use Space for expand record and Shift+Space for expand cell; AG Grid uses Space to toggle row selection [1][24][15][21][3].

### Clipboard and fill

- Copy and paste of cells: Airtable (also cut) [15], Grist (also cut) [22], Baserow [19], NocoDB [21], Glide [24]. AG Grid clipboard is Enterprise; Community has none [13].
- Paste from external spreadsheets, creating rows as needed: Baserow ("Copy cells from Excel or Google Sheets ... Baserow creates or updates rows and fields as needed") [18][30].
- Fill: Airtable fill handle [16]; Grist Ctrl+D "Fills current selection with contents of top row" [22]; Notion Cmd/Ctrl+D and R to fill down or right [27]; Glide `fillHandle` and optional `downFill`, `rightFill` [23][24]; AG Grid Ctrl+D within Enterprise cell selection [12]. A Baserow fill handle is **unverified**.

### Column operations

- Resize by dragging the header edge and reorder by dragging the header: Airtable [16], Notion [25], Baserow [18], Grist [31], NocoDB [29], AG Grid [33], Glide (`onColumnResize`, `onColumnMoved`) [23].
- Hide: Airtable (primary field cannot be hidden) [16], Baserow [18], NocoDB [29], Grist [31], TanStack `columnVisibilityFeature` [26].
- Pin or freeze: Airtable, by dragging the divider, "No more than three fields can be frozen in a single view" [17]; Baserow "a maximum of 4 columns per view", primary field pinned by default [18]; Glide `freezeColumns`, left only [23]; AG Grid left and right, by config or by dragging to the edge [34]; TanStack `columnPinningFeature` [26].
- Keyboard access to header operations is rare. AG Grid documents it: on a focused header Enter sorts, Shift+Enter multi-sorts, Shift+Left/Right moves the column, Alt+Left/Right resizes it, Alt+Down opens the column menu [3].
- Row height presets (short, medium, tall, extra tall): Airtable [16], Baserow [18], NocoDB [29]. Wrap text per column: Notion [25].

### Sorting

- Header click cycles "ascending -> descending -> none" in AG Grid; Shift+click adds a column to a multi-sort [32].
- Multi-column sort: Notion (reorder sorts by dragging) [28], Grist [35], NocoDB ("by One or More Criteria") [29], AG Grid [32].
- Sorting interacts with manual row order: in Baserow manual row reordering "requires removing automatic sorts first" [18]; Airtable's insert-at-end shortcut applies to "an unsorted/ungrouped grid view" [15].
- Accessibility limit: "ARIA does not provide a way to indicate levels of sort for data sets that have multiple sort keys. Thus, there is limited value to applying `aria-sort` with a value other than `none` to more than one column or row" [36].
- **Unverified:** the AG Grid comparison page, as summarised, lists "Row Grouping & Multi-Column Sorting" under Enterprise [2], while the sorting page documents Shift+click multi-sort with no Enterprise marker [32]. Treat the licence status of multi-sort as unconfirmed.

### Filtering

- Structure of a condition is field, operator, value, with operators depending on the field type (Airtable) [37].
- Nested AND/OR groups: Airtable, up to three levels and at most 49 conditions per view [37]; Notion, filter groups "can be nested up to three layers deep" [28].
- AG Grid distinguishes column filters (text, number, date in Community), quick filter (text across all columns), external filter and advanced filter with a visual builder [38][39]. The Excel-style set filter (checkbox list of distinct values) is Enterprise [14].
- Grist: filter by value list, range filters for numeric and date columns with relative dates, pinned filter buttons above the table [35].
- Faceting (distinct values and counts to build a filter UI) is a named TanStack feature, `columnFacetingFeature` [26].
- Search, separate from filtering, moving the cursor to matches: Grist Ctrl+F [35], Airtable Cmd/Ctrl+F [15], Baserow [19], Glide (`showSearch`) [23].
- Glide Data Grid ships no sorting or filtering: "these are usually very application-specific, and can often also be implemented more efficiently in the data source, via a database query" [40]. TanStack takes the same position on server-side processing [41].

### Grouping and summaries

- Airtable: "a maximum of 3 levels of grouping", collapsible, a summary bar per group, and dragging a record to another group rewrites the grouped value (not for computed fields) [42].
- Notion: grouping with one level of sub-grouping, hide empty groups [28]. Baserow: collapsible groups [18]. NocoDB: group by [29].
- AG Grid: row grouping is Enterprise [11]; lazy loading of groups needs the Enterprise server-side row model [7].
- Footer summaries (count, sum, average, min, max and so on): Notion "Calculate" [25], Baserow field summaries that "respect active filters" [18], Airtable summary bar [42].

### Pagination versus virtual scrolling

- AG Grid virtualises rows and columns by default, with a buffer of 10 rows either side and a cap of 500 rendered rows [43]. Pagination is a Community feature and works with all row models; `paginationAutoPageSize` fits the page to the viewport [44].
- AG Grid's row models are the clearest map of the design space: client-side (all data in the browser), infinite (flat, lazily loaded blocks, sorting and filtering on the server, no grouping), server-side (lazy loading plus server grouping; Enterprise), viewport (server pushes exactly the visible rows; Enterprise) [7].
- TanStack: "Virtualization is a rendering strategy, not a table feature" and "is not a replacement for server-side pagination, filtering, or sorting. If the data is virtualized on the client, the data still needs to exist on the client." Also: "For small tables, normal rendering is simpler and usually preferable" [45]. On the client/server choice: "you pretty much have to choose just one or the other" [41].
- Glide abandoned DOM virtualisation for canvas: "Once you need to load/unload hundreds of DOM elements per frame nothing can save you" [40].
- The Airtable-like products scroll rather than paginate: Baserow uses lazy loading [30]; NocoDB marks its page-jump shortcuts obsolete [21]. That Airtable virtualises its grid is **unverified** (no first-party statement found); its record limits per base are 1,000 (Free), 50,000 (Team) and 125,000 (Business) [46]. Notion's per-view load limit is **unverified**.
- Accessibility cost of virtualisation, in AG Grid's words: "Screen readers assume all elements of the grid are loaded when the page is loaded", and the recommended remedy is "Best way to do this is to use pagination" [47].

### Cell types and editors

Types present in every product examined (Airtable [48], Notion [49], Baserow [50], Grist [51]):

| Type | Notes |
|---|---|
| Text, long text | Long text may be rich in Airtable and Notion |
| Number | Integer and decimal; currency and percent as formats |
| Boolean | Checkbox or toggle, usually editable in place without entering edit mode |
| Date, date and time | Calendar picker |
| Single choice | Coloured tag from a fixed list |
| Multiple choice | Several tags |
| Reference to another table | Linked record, relation, link-to-table, reference |
| File or attachment | |

Common but not universal: email, URL and phone (Airtable, Notion, Baserow), rating (Airtable, Baserow), duration (Airtable, Baserow), user or collaborator, button, and computed read-only types (formula, lookup, rollup, count, autonumber, created and modified time and user) [48][49][50].

Glide's built-in cell kinds are Uri, Text, Image, RowID, Number, Bubble, Boolean, Loading, Markdown, Drilldown, Protected and Custom [23]. "Loading" and "Protected" are worth noting as first-class states of a cell.

### Validation feedback

- AG Grid: provided editors validate constraints declared on the column; `getValidationErrors()` adds custom rules; "the Grid will show the errors in a tooltip when hovering the editor". `invalidEditValueMode` is `'revert'` (default: "Cancels the edit and reverts the cell to its original value") or `'block'` ("Keeps the invalid editing session open until a valid value is provided or the edit is cancelled"). Cross-field validation exists for full-row editing only [9].
- Glide: `validateCell` — "When returns false indicates to the user the value will not be accepted. When returns a new GridCell the value is coerced to match" [23]. Coercion is a third outcome besides accept and reject.
- Grist stores the invalid value and marks it: "the cell will be highlighted with an error (and columns referencing the invalid value will also display an error)" [51].
- Paste has its own path: Glide `coercePasteValue` [23]; Baserow overwrites on paste "without warning" [30].
- How Airtable, Notion, Baserow and NocoDB present a rejected edit is **unverified**; their documentation describes field types as constraining input but not the feedback shown.
- None of the sources describes validation that comes back from a server after the commit (the `ash_table` case, where an Ash action returns errors). That pattern is not covered by this research.

### Keyboard and accessibility

- Roles: `grid` (or `treegrid` when grouped, as AG Grid does), `row`, `rowgroup`, `columnheader`, `rowheader`, `gridcell`; the grid needs `aria-label` or `aria-labelledby` [1][47].
- States: `aria-sort` on the sorted header, `aria-selected` on selected rows or cells, `aria-readonly` where "editing is disabled" [1].
- When rows or columns are "hidden or not present in the DOM": `aria-rowcount`, `aria-colcount`, `aria-rowindex`, `aria-colindex`. A total of `-1` means unknown. "Missing or inconsistent values of `aria-rowindex` could have devastating effects on assistive technology behavior" [1][36]. This applies to pagination as much as to virtualisation.
- Focus management: one tab stop for the whole grid, using roving `tabindex` or `aria-activedescendant`. "One benefit of using roving `tabindex` ... is that the user agent will scroll the newly focused element into view" [8].
- Where focus lands matters: the best case is a cell containing text with focus on the cell, or a cell containing one widget that does not need arrow keys with focus on that widget [1].
- AG Grid targets WCAG 2.0 AA and notes that some screen readers "will not recognise changes that happen to an element that is currently focused" (for example a sort state change on the focused header) [47].
- Glide claims accessibility support on canvas and concedes "there are likely flaws in the implementation we are not aware of" [40].
- No accessibility statement for the grid views of Airtable, Notion, Baserow, NocoDB or Grist was found in the pages read; their conformance is **unverified**.

## What this means for `ash_table`

These are observations for the spec, not decisions.

1. The first version named in the map (sorting, filtering, pagination, keyboard and ARIA grid behaviour, inline editing) matches the "every serious grid has" tier closely. Missing from the map's list but in that tier: column resize, reorder, hide and one frozen column; row selection with bulk actions.
2. Server-side sorting, filtering and pagination is the model AG Grid calls "infinite" and TanStack calls manual. It is the natural fit for Ash read actions, and both sources say not to mix it with client-side processing [7][41].
3. Pagination first is defensible on accessibility grounds, not just effort: AG Grid recommends it over virtualisation for screen readers [47]. `aria-rowcount` and `aria-rowindex` are still required on a paginated grid [36].
4. The APG key set plus Enter/F2/Escape/type-to-edit is a complete, citable keyboard spec for the first version [1][4].
5. A LiveView round trip per arrow key would be at odds with every product here; focus movement is local in all of them. Focus and edit-mode state belong in the JS hook. (Inference; no source measures this.)
6. Range selection, clipboard, fill and undo are the tier that makes a grid feel like Airtable, and the tier AG Grid charges for. They are a coherent later slice, and each depends on range selection.
7. AG Grid's `revert` versus `block` and Glide's coercion give three named behaviours for an invalid edit. Ash changeset errors arrive after the commit, which favours `block` (keep the editor open, show the error at the cell).

## Open questions surfaced

1. Does Tab move to the next cell (spreadsheet convention, all Airtable-like products) or leave the grid (APG composite rule)?
2. What does Space do on a focused cell: toggle row selection, or open an expanded record?
3. What happens to an edit whose action fails validation on the server: keep the editor open, revert, or keep the invalid value and mark it as Grist does?
4. Is cell-level commit the only editing unit, or is row-level editing with cross-field validation needed, given that Ash validations are often cross-attribute?
5. How is `aria-sort` expressed under multi-column sort, given ARIA cannot express sort levels?
6. Which Ash types map to the eight universal cell types, and how are relationships shown (the "reference" type is universal in the Airtable-like products)?
7. Does the first version need an expanded-record form? All four Airtable-like products with a grid have one.
8. Does undo exist for edits that have already run an Ash action? No source here covers undo over server-committed writes.

## Sources

1. W3C APG, Grid Pattern — https://www.w3.org/WAI/ARIA/apg/patterns/grid/
2. AG Grid, Community vs Enterprise — https://www.ag-grid.com/javascript-data-grid/community-vs-enterprise/
3. AG Grid, Keyboard Interaction — https://www.ag-grid.com/javascript-data-grid/keyboard-navigation/
4. AG Grid, Start/Stop Cell Editing — https://www.ag-grid.com/javascript-data-grid/cell-editing-start-stop/
5. AG Grid, Cell Editing (v36.2.0) — https://www.ag-grid.com/javascript-data-grid/cell-editing/
6. AG Grid, Provided Cell Editors — https://www.ag-grid.com/javascript-data-grid/provided-cell-editors/
7. AG Grid, Row Models — https://www.ag-grid.com/javascript-data-grid/row-models/
8. W3C APG, Developing a Keyboard Interface — https://www.w3.org/WAI/ARIA/apg/practices/keyboard-interface/
9. AG Grid, Cell Editing Validation — https://www.ag-grid.com/javascript-data-grid/cell-editing-validation/
10. AG Grid, Undo/Redo Edits — https://www.ag-grid.com/javascript-data-grid/undo-redo-edits/
11. AG Grid, Row Grouping — https://www.ag-grid.com/javascript-data-grid/grouping/
12. AG Grid, Cell Selection — https://www.ag-grid.com/javascript-data-grid/cell-selection/
13. AG Grid, Clipboard — https://www.ag-grid.com/javascript-data-grid/clipboard/
14. AG Grid, Set Filter — https://www.ag-grid.com/javascript-data-grid/filter-set/
15. Airtable, Keyboard shortcuts — https://support.airtable.com/docs/airtable-keyboard-shortcuts
16. Airtable, Grid view — https://support.airtable.com/docs/airtable-grid-view
17. Airtable, Changing the number of frozen fields — https://support.airtable.com/docs/changing-the-number-of-frozen-fields-columns
18. Baserow, Guide to grid view — https://baserow.io/user-docs/guide-to-grid-view
19. Baserow, Keyboard shortcuts — https://baserow.io/user-docs/baserow-keyboard-shortcuts
20. NocoDB, Actions on record — https://nocodb.com/docs/product-docs/records/actions-on-record
21. NocoDB, Keyboard shortcuts — https://nocodb.com/docs/product-docs/getting-started/keyboard-shortcuts
22. Grist, Keyboard shortcuts — https://support.getgrist.com/keyboard-shortcuts/
23. Glide Data Grid, API.md — https://github.com/glideapps/glide-data-grid/blob/main/packages/core/API.md
24. Glide Data Grid, API.md, section Keybindings — same file as 23
25. Notion, Table view — https://www.notion.com/help/tables
26. TanStack Table, Features guide (v9) — https://tanstack.com/table/latest/docs/guide/features
27. Notion, Keyboard shortcuts — https://www.notion.com/help/keyboard-shortcuts
28. Notion, Views, filters, sorts and groups — https://www.notion.com/help/views-filters-and-sorts
29. NocoDB, Grid view — https://nocodb.com/docs/product-docs/views/view-types/grid
30. Baserow, Paste data into a table — https://baserow.io/user-docs/paste-data-into-baserow-table
31. Grist, Table widget — https://support.getgrist.com/widget-table/
32. AG Grid, Row Sorting — https://www.ag-grid.com/javascript-data-grid/row-sorting/
33. AG Grid, Column Moving — https://www.ag-grid.com/javascript-data-grid/column-moving/
34. AG Grid, Column Pinning — https://www.ag-grid.com/javascript-data-grid/column-pinning/
35. Grist, Search, sort and filter — https://support.getgrist.com/search-sort-filter/
36. W3C APG, Grid and Table Properties — https://www.w3.org/WAI/ARIA/apg/practices/grid-and-table-properties/
37. Airtable, Filtering records using conditions — https://support.airtable.com/docs/filtering-records-using-conditions
38. AG Grid, Filtering overview — https://www.ag-grid.com/javascript-data-grid/filtering-overview/
39. AG Grid, Simple column filters — https://www.ag-grid.com/javascript-data-grid/filter-provided-simple/
40. Glide Data Grid, README (FAQ) — https://github.com/glideapps/glide-data-grid/blob/main/README.md
41. TanStack Table, Client-Side vs Server-Side guide — https://github.com/TanStack/table/blob/main/docs/guide/client-side-vs-server-side.md
42. Airtable, Grouping records — https://support.airtable.com/docs/grouping-records-in-airtable
43. AG Grid, DOM Virtualisation — https://www.ag-grid.com/javascript-data-grid/dom-virtualisation/
44. AG Grid, Row Pagination — https://www.ag-grid.com/javascript-data-grid/row-pagination/
45. TanStack Table, Virtualization guide (React) — https://github.com/TanStack/table/blob/main/docs/framework/react/guide/virtualization.md
46. Airtable, Plans — https://support.airtable.com/docs/airtable-plans
47. AG Grid, Accessibility — https://www.ag-grid.com/javascript-data-grid/accessibility/
48. Airtable, Supported field types — https://support.airtable.com/docs/supported-field-types-in-airtable-overview
49. Notion, Database properties — https://www.notion.com/help/database-properties
50. Baserow, Field overview — https://baserow.io/user-docs/baserow-field-overview
51. Grist, Column types — https://support.getgrist.com/col-types/
