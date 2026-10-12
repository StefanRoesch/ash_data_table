# Four table features: how the leading tables do them

Research for `ash_table`, 2026-10-12. Sources are official docs and source code, read on that day.
Anything marked **(unverified)** I could not confirm from a primary source.

## Summary

**1. Hiding columns.** Every product has the same shape: one button above the table ("Hide fields", "Fields", "Columns") that opens a list of all columns with a switch each, and a "Hide" item in each column's header menu. The button shows how many are hidden. The label column cannot be hidden (Airtable, Baserow, Notion). A hidden column keeps its sort and filter (NocoDB and Airtable say so). The products save the choice per view; ash_table has no views, so the smallest good version is: a "Columns" button with a checkbox list, hiding done in the browser with CSS, nothing saved, the column still loaded. Hiding is a convenience, never a permission. One thing needs care: ash_table's filters sit in the header row, so a hidden column would hide its own active filter. Flag it.

**2. Footer summaries.** Two schools. Airtable, Baserow, NocoDB and Notion let the *viewer* click the footer cell and pick a function from a list that depends on the column's type. AG Grid, MUI, Tabulator and Retool let the *builder* set the function in config. All compute over the whole filtered result, not the page. For ash_table the builder should declare it on the column (the Ash way: no stored views, cost known up front), with count, sum, average, min, max. A summary a person may not see shows a dash, never a partial number.

**3. Endless scrolling.** Three different things: pages (fixed slices, a control to move), endless scrolling (the next slice is appended when you reach the bottom), virtual scrolling (the scrollbar stands for the whole result and only the visible rows exist in the page). The grid products are virtualised. LiveView offers the middle one natively: `phx-viewport-bottom` plus a stream, optionally with a stream `limit`. For ash_table, "endless" should mean: keyset pages appended as you scroll, with a visible "Load more" button as the fallback and as the keyboard way, no stream limit in the first version, position not kept in the URL. Pages stay the default.

**4. Resizing columns.** The common interaction: a handle on the right edge of the header, drag to resize, double click to fit the content, a minimum width. Only AG Grid documents a keyboard way (Alt+Left/Right on the header). WCAG 2.2 asks for a way without dragging. In LiveView the widths belong on `<col>` elements (or CSS variables on the table root) that the server does not re-render, not on cells in the stream.

---

## 1. Hiding columns

### How others do it

| Product | Where the control is | The menu | What cannot be hidden | Hidden column that is sorted or filtered | Saved | Sign that columns are hidden |
| --- | --- | --- | --- | --- | --- | --- |
| [Airtable](https://support.airtable.com/articles/7905594155-airtable-grid-view) | "Hide fields" button in the view bar. Also in the field's header menu (unverified from docs, seen in product). | List with a toggle per field, "Find a field" search, "Hide all" / "Show all". Choices save as you make them. | The primary field. | Still works: ["Editors can sort by, filter by, group by, or hide fields"](https://support.airtable.com/articles/6540330000-airtable-field-actions); hiding touches the view only. No flag documented. | Per view. | The button reads "X fields hidden". |
| [Notion](https://www.notion.com/help/database-properties) | View settings → "Property visibility". "Properties" at the top right of a [table](https://www.notion.com/help/tables). Header menu item (unverified). | List with an eye icon per property, drag handle to reorder, show all / hide all ([timeline doc](https://www.notion.com/help/timelines)). | The Name property cannot be removed. Whether it can be hidden in a table: unverified. | Not documented. | Per view. | None documented. |
| [Baserow](https://baserow.io/user-docs/field-customization) | "Hide fields" button in the toolbar, "Hide field" in the header dropdown, and in the row detail panel. | Toggles for many fields at once. | "You cannot hide the Primary field". | Not documented. | Per view. | Count on the button (unverified from docs). |
| [NocoDB](https://nocodb.com/docs/product-docs/fields/actions-on-field) | Toolbar → "Fields" menu. | Toggles; search and "show system fields" (unverified from docs). | Display value (unverified). | "Hidden fields are not visible in the table view, but will still be accessible for Formulas, Sort, Filter, etc." | Per view. | Count on the button (unverified). |
| [GitHub Projects](https://docs.github.com/en/issues/planning-and-tracking-with-projects/customizing-views-in-your-project/customizing-the-table-layout) | View menu → "Fields", and "Hide field" in the header's menu. | List of fields to toggle. | Title (unverified). | Not documented. | Per view, after "Save". | None documented. |
| [Linear](https://linear.app/docs/display-options) | "Display" button at the top right; shortcut Shift+V. | "Display properties": a set of toggle chips, one per property. | — | — | Per person and view; "Set as default" saves it for the workspace. | None. |
| [AG Grid](https://www.ag-grid.com/javascript-data-grid/tool-panel-columns/) | Side panel "Columns" and ["Choose Columns" in the column menu](https://www.ag-grid.com/javascript-data-grid/column-menu/) (both Enterprise). | Checkbox per column, select/unselect all, search box, drag to reorder. | Columns with `lockVisible`. | Sort and filter state are separate from visibility. Only the quick filter skips hidden columns by default ([docs](https://www.ag-grid.com/javascript-data-grid/filter-quick/)). | Not saved; the app saves the column state. | None. |
| [MUI X Data Grid](https://mui.com/x/react-data-grid/column-visibility/) | "Columns" in the toolbar; "Hide column" and "Manage columns" in the header menu. | Checkbox list, search, show/hide all, reset. | Columns with `hideable: false`. | Quick filter skips hidden columns by default ([docs](https://mui.com/x/react-data-grid/filtering/quick-filter/)); column filters stay. | Not saved; `columnVisibilityModel` is the app's to keep. | None. |
| [TanStack Table](https://github.com/TanStack/table/blob/v8/docs/guide/column-visibility.md) | Headless: no UI. | The docs example is a plain list of checkboxes with a "Toggle All". | Columns with `enableHiding: false`; the checkbox is then disabled. | State is separate. | The app's. | — |
| [Google Sheets](https://support.google.com/docs/answer/54813) | Right click on the column header → hide. | No list. | — | — | In the file, for everybody. | Small arrows in the header where a column is missing (unverified from the help text, seen in product). |
| [Retool](https://docs.retool.com/apps/guides/data/table) | Not a viewer feature. The builder hides columns, or wires a multiselect to the table. | — | — | — | — | — |
| [Tabulator](https://tabulator.info/docs/6.3/columns) | No built-in control: `hideColumn()`, `showColumn()`, `toggleColumn()` for the app to call. | — | — | — | — | — |

What they agree on:

- **Two entry points.** A button for "all columns at once", a header menu item for "this one, now".
- **A list with one switch per column**, in column order. Search and show all / hide all appear once tables have many columns.
- **The label column stays.** It is what a row is called.
- **Hiding is display only.** Sort, filter and formulas still use the column. Nobody removes the filter. Nobody documents a flag on it either; that is a gap, not a model.
- **Persistence is per saved view.** No product keeps it in the URL. The libraries leave it to the application.

**Accessibility.** No product documents the ARIA pattern of its menu. The two patterns that fit are from the W3C practices:

- A [menu with `menuitemcheckbox`](https://www.w3.org/WAI/ARIA/apg/patterns/menubar/) items: arrow keys move, Space toggles and may keep the menu open, Escape closes.
- A [disclosure](https://www.w3.org/WAI/ARIA/apg/patterns/disclosure/): a button with `aria-expanded` that shows a group of ordinary checkboxes. Tab moves, Space toggles. Simpler, and correct when the list can hold a search box.

**Loaded or left out?** For a server-rendered table there are two ways to hide a column.

| | Visual only (CSS) | Left out of the read |
| --- | --- | --- |
| How | The cell is in the page, not displayed. | The column is not selected or loaded; the row is rendered without it. |
| Speed of toggling | Instant, no round trip. | A new read and a re-render of every row. |
| Payload | Unchanged. | Smaller. |
| Cost of calculations and aggregates | Still paid for a column nobody sees. | Saved. |
| Sort and filter on the hidden column | Work as before. | Work as before (they are part of the query, not of the select). |
| Security | None. The value is in the HTML. | None either: the person can switch it back on. |
| State on the server | None. | The server must know the set (URL or socket). |

Neither is a permission. A value a person must not see is kept away by a policy, a field policy or `sensitive?`, as today. Hiding must never be offered as a way to protect data, and the docs should say so in one sentence.

The CSS way needs one rule so it survives LiveView patches: the hook sets one attribute or class on the table's root (`data-hidden-cols="estimate due_on"`, or a class per column) and the stylesheet hides `th` and `td` by their column. The rows in the stream stay untouched, so a patched or newly streamed row is hidden correctly with no work. `aria-colcount` and `aria-colindex` may stay as they are: the [W3C practice](https://www.w3.org/WAI/ARIA/apg/practices/grid-and-table-properties/) uses exactly these two for "not all columns are in view". Arrow-key navigation in the hook must skip hidden cells.

### Recommendation for ash_table

The smallest good version, in the owner's words "toggle a column in and out, just visually":

- A **"Columns" button** above the table, beside "Clear filters". It opens a list of the table's columns, in order, each with a checkbox. Built as a disclosure with ordinary checkboxes.
- The button shows the count when something is hidden: **"Columns (2 hidden)"**.
- **"Show all"** in the list. No search, no reorder, no "hide all" in the first version.
- **Done in the browser.** Still loaded, hidden by CSS from an attribute on the table root. No event to the server.
- **Not saved.** A reload shows every column again. Same decision as for widths.
- The **label column cannot be hidden**; its checkbox is disabled.
- A hidden column **keeps its sort and filter**. While it does, the button says so ("Columns (2 hidden, 1 filtered)") and the entry in the list carries a mark. "Clear filters" still clears it.
- No header menu in the first version. ash_table's headings have no menu today; adding one for a single item is not worth it.

### Decisions for the owner

1. **Visual only, or left out of the read?** Recommend: visual only. *Why: it is what was asked, it needs no server state, and it is instant. Leaving a column out is a later option for expensive calculations.*
2. **Where is the control?** Recommend: one "Columns" button above the table. *Why: every product has it, and ash_table has no header menu to add a second entry to.*
3. **Can every column be hidden?** Recommend: all but the label column (`label_field`). The selection boxes, the expander and the actions column are not in the list. *Why: Airtable, Baserow and Notion keep the record's name; a row without it cannot be told apart.*
4. **May the builder forbid hiding a column?** Recommend: not in the first version. *Why: nothing breaks when a person hides a column for themselves; add `hideable?: false` when somebody asks (MUI and TanStack have it).*
5. **May the builder start a column hidden?** Recommend: not in the first version. *Why: it is a second meaning of "column" (declared but not shown) and belongs with the decision about saving.*
6. **What happens to the sort or filter of a hidden column?** Recommend: it stays active and is flagged on the button and in the list. *Why: all products keep it; dropping it would change the rows as a side effect of a display choice. The flag is ash_table's own addition, needed because its filters live in the header row.*
7. **Is the choice saved?** Recommend: no. Not in the URL, not in local storage. *Why: a shared link should not carry one person's layout, and the URL is for what changes the result. Decide saving once, for hidden columns and widths together.*
8. **Which ARIA pattern?** Recommend: disclosure with checkboxes. *Why: plain form controls, works with Tab and Space, and can take a search box later without a rewrite.*
9. **Does a hidden column count for "export" or "copy" features later?** Recommend: decide then; note that Airtable's views export only visible fields **(unverified)**. *Why: no such feature exists yet.*

---

## 2. Footer summaries

### How others do it

| Product | Who picks the function | Functions | Scope | With a selection | Notes |
| --- | --- | --- | --- | --- | --- |
| [Airtable summary bar](https://support.airtable.com/docs/the-summary-bar) | The viewer: click the bar under a field, pick from a menu. | Any field: Empty, Filled, Unique, and each as percent. Checkbox: Checked, Unchecked, percent. Number: Sum, Average, Median, Min, Max, Range, Standard deviation, Histogram. Date: Earliest, Latest, Date range in days or months. Attachment: total size. | All records of the view (filtered). With groups: one summary per group and one total. | "the summarization will only include cells that are in that selection range". | Bar at the bottom of the view, always in sight. Record count at its left (unverified from docs). |
| [Notion "Calculate"](https://www.notion.com/help/tables) | The viewer: column menu → "Calculate", or hover the footer cell. | Count all, Count values, Count unique values, Count empty, Count not empty, Percent empty, Percent not empty; Sum, Average, Median, Min, Max, Range; Earliest date, Latest date, Date range. | The whole view, not only the loaded rows (unverified from docs). | Not documented. | Footer row under the last row; blank until a function is chosen. |
| [Baserow field summaries](https://baserow.io/user-docs/footer-aggregation) | The viewer: "Click the footer cell to open the summary menu". | Text and select: Empty, Filled, % Empty, % Filled, Unique, Distribution. Number: Sum, Average, Median, Min, Max, Std deviation, Variance. Date: Earliest, Latest. Boolean: Checked, Unchecked, and percent. | Filtered rows of the view. | Not documented. | "updates automatically as your data changes". Saved per view. Lookup fields have none. |
| [NocoDB field summary](https://nocodb.com/docs/product-docs/fields/field-summary-footer) | The viewer: click the footer cell, choose from a dropdown. | General: Empty, Filled, Unique, and percent of each. Number: Sum, Min, Max, Average, Median, Standard deviation, Range. Date: Earliest, Latest, Date range, Month range. Checkbox: Checked, Unchecked, percent. Attachment: size. | All rows of the view, after filters. | The footer re-scopes to the selected cells or ticked rows; other columns show empty footers. Known limit: only over rows already loaded. | On a shared view a viewer can change the function; "NocoDB does not save these changes". |
| [Google Sheets](https://support.google.com/docs/answer/66032) | The viewer, for the selection only. | Sum, Average, Minimum, Maximum, Count, Count numbers. | The selected cells. There is no footer row; a total is a formula in a cell. | It *is* the selection. | Shown at the bottom right of the window. |
| [AG Grid status bar](https://www.ag-grid.com/javascript-data-grid/status-bar/) (Enterprise) | Builder picks the panels. | Total rows, filtered rows, selected rows; aggregation panel: count, sum, min, max, avg over "the selected range", numbers only. | Counts: the grid. Aggregation: the selection. | Yes, that is its purpose. | Bar under the grid. With server-side data the docs say to write your own panel. |
| [AG Grid grand total row](https://www.ag-grid.com/javascript-data-grid/grouping-footers/) (Enterprise) | The builder: `aggFunc` per column. | sum, min, max, count, avg, first, last (list unverified on this page). | All rows after filter. | No. | `grandTotalRow`: `"top"`, `"bottom"`, `"pinnedTop"`, `"pinnedBottom"`; the pinned ones stay in sight while scrolling. Works with the server-side row model. |
| [MUI aggregation](https://mui.com/x/react-data-grid/aggregation/) (Premium) | Builder in the model; the viewer can change it in the column menu under "Aggregation". | sum, avg (number); min, max (number, date); size (all); size true / false (boolean). | `aggregationRowsScope`: filtered rows (default) or all. | No. | "rendered in a footer row at the bottom of the Grid". The cell shows a small label with the function's name. Uses the column's formatter unless the function has its own. Server side is a separate feature. |
| [Tabulator](https://tabulator.info/docs/6.3/column-calcs) | The builder: `topCalc` / `bottomCalc` per column. | avg, max, min, sum, concat, count, unique; own formatter and precision. | The rows in the table. With remote pages: only the loaded page (unverified). | No. | A calc row at the top, the bottom or both; per group when grouped. |
| [Retool summary row](https://docs.retool.com/apps/guides/data/table/customization) | The builder, as an add-on. | Min, Max, Average, Sum, Count Distinct; depends on the column's format. | Not stated for server-side pages. | No. | — |
| GitHub Projects [field sum](https://docs.github.com/en/issues/planning-and-tracking-with-projects/customizing-views-in-your-project/customizing-the-table-layout) | The viewer: view menu → "Field sum". | Sum of number fields, and count of items. | Per group: "field sums are included in each group's header". No footer. | No. | — |

What they agree on, and where they split:

- **The scope is the filtered result**, never the page. Where a product can only see loaded rows it says so as a limitation (NocoDB selection, AG Grid).
- **Functions depend on the column's type.** Every column can be counted (empty, filled, unique). Numbers get sum, average, min, max and often median. Dates get earliest and latest. Booleans get checked and unchecked.
- **The viewer picks** in the no-code products, where the choice is saved with the view. **The builder picks** in the libraries.
- **The footer cell is blank** until a function is chosen. It shows a small label with the function's name beside the value ("Sum 1,240").
- **Formatting follows the column** (currency, decimals), except counts and percents.
- **Sticky.** Airtable's bar and AG Grid's pinned row stay in sight. Notion's row is after the last row.
- **After an edit** the summary updates by itself (Baserow says so; the others do it in the product).
- **While loading**: not documented by anyone. MUI shows skeletons for lazy rows; nothing is specified for the footer **(unverified)**.

### Recommendation for ash_table

- The builder declares the summary **on the column**: one function per column, for example `summary :sum`. Functions in the first version: **count, sum, average, min, max**. The compiler rejects a function that does not fit the type (sum of a text).
- A **footer row** (`<tfoot>`) inside the same table, so its cells line up with the columns and move with horizontal scrolling and resizing. Each cell shows the function's name and the value: "Sum 1,240". Cells of columns without a summary are empty.
- Over **the whole filtered result**, with the same arguments, filters, actor and tenant as the rows. Never over the page.
- **Recomputed with every read** and after a save that touched a summarised column. Until the new value is there, the old one is dimmed like the rows are (`aria-busy`), not replaced by a spinner.
- **Formatted as the column formats its cells.** Count is a plain integer.
- **When it cannot be computed for this person** (a field policy hides the field on some or all records, or the read is forbidden), the cell shows a dash and is announced as "Not available". Never a number computed over the visible part only: it looks like the total and is not.
- The row count already shown under the table ("1–25 of 320") stays where it is. The footer does not repeat it.
- Not in the first version: the viewer choosing the function, summaries of a selection, percent / unique / median, summaries per group.

### Decisions for the owner

1. **Who picks the function: builder or viewer?** Recommend: the builder, in the column's declaration. *Why: there is no saved view to keep a viewer's choice in, each summary is a query whose cost the builder should know, and it is how the libraries (AG Grid, Tabulator, Retool) do it. Ash precedent: aggregates are declared, not asked for ad hoc.*
2. **Which functions?** Recommend: count, sum, average, min, max. *Why: they are the set every product shares and they map one to one to Ash's aggregate kinds. Median, range, unique and the percents can follow.*
3. **One function per column or several?** Recommend: one. *Why: everybody shows one value per footer cell; two would need two footer rows.*
4. **Scope: filtered result or page?** Recommend: the filtered result, always. *Why: every product does it, and a page sum is a number nobody asked for.*
5. **What does it show for a selection of rows?** Recommend: nothing changes in the first version. *Why: Airtable and NocoDB do re-scope, but it is a second query path and ash_table's "all that match" selection makes it subtle. Good later addition.*
6. **What if a field policy hides the field on some records?** Recommend: show a dash, announced "Not available", for that person. *Why: a partial sum misleads and a full sum leaks. (Whether Ash can tell this cheaply is the separate research.)*
7. **Where is the row: sticky at the bottom, or after the last row?** Recommend: after the last row, in `<tfoot>`, not sticky, in the first version. *Why: ash_table pages are short (25 rows) and the table has no own vertical scroll area; sticky only matters with endless scrolling, where it should then become sticky.*
8. **How does it update after an inline edit?** Recommend: recompute after every save of a column that has a summary, and with every read. *Why: a stale total beside a fresh cell is the one thing people notice.*
9. **Does a summary need the action to be `countable` or cost an extra query?** Recommend: accept one extra statement per read for all summaries together, and document it, as the count is documented today. *Why: honest about cost; the builder opts in per column.*
10. **Label in the cell?** Recommend: yes, the function's name before the value, translatable. *Why: MUI, Airtable and Baserow all label it; "1,240" alone under a column does not say sum or max.*

---

## 3. Endless scrolling, virtual scrolling, pages

### The three in simple words

- **Pages.** The result is cut into slices of, say, 25. You see one slice. A control moves to the next. The address can say which slice. Everything in the page is in the DOM, and nothing else.
- **Endless (infinite) scrolling.** You start with the first slice. When you scroll to its end, the next slice is added below. The list grows. The scrollbar only knows about what was loaded so far, so it jumps each time.
- **Virtual scrolling.** The scrollbar stands for the whole result from the start, as if all 50,000 rows were there. Only the rows in view (plus a few above and below) exist in the DOM; the rest is empty space of the right height. Rows are created and thrown away as you scroll. Data is either all in the browser, or fetched in blocks for the part in view.

They can be combined. LiveView's own example is endless scrolling with a cap: old rows are dropped at the top while new ones arrive at the bottom.

### How others do it

| Product | What it does | Source |
| --- | --- | --- |
| Airtable | Virtualised grid over all records of the view; the data is in the browser. | Unverified (product behaviour, no doc). |
| Notion | Loads a set number of rows, then a "Load more" button. The number is the view's "Load limit". | [Load limit](https://www.notion.com/help/timelines) (documented for timelines; the same setting for tables is unverified). |
| Baserow | Virtualised grid; rows are fetched in blocks as you scroll. | Unverified (product behaviour). |
| NocoDB | Pages in the grid's footer by default; "Infinite Scrolling" is an opt-in [experimental feature](https://nocodb.com/docs/product-docs/account-settings/experimental-features): "Effortlessly browse large datasets with infinite scrolling." Whether it has since become the default: unverified. | Link. |
| Linear | All issues are synced to the browser; lists are virtualised. | Unverified. |
| GitHub Projects | Up to [50,000 items](https://github.blog/changelog/2025-02-26-increased-items-in-github-projects-now-in-public-preview/) per project; the table loads more as you scroll. How: unverified. | Link. |
| [AG Grid](https://www.ag-grid.com/javascript-data-grid/row-models/) | Four "row models". Client-side: all data in the browser, rows virtualised. Infinite: "load more data as the user scrolls down", flat lists only. Server-side (Enterprise): the same with groups. Pagination is a separate switch on top. | Link. |
| [MUI X](https://mui.com/x/react-data-grid/server-side-data/lazy-loading/) | Pagination is the default and the only way in the free version (max 100 rows a page, [docs](https://mui.com/x/react-data-grid/pagination/)). Pro: lazy loading "removing page controls and instead loading data dynamically". Two modes: with a known count, the grid is filled with skeleton rows and fetches what scrolls into view; with an unknown count, "fetches more data when the user scrolls to the bottom". | Link. |
| [TanStack Table](https://github.com/TanStack/table/blob/v8/docs/guide/pagination.md) | None built in. "The UI/UX of both virtualization and pagination have their own trade-offs". Virtualisation through TanStack Virtual. | Link. |
| [Tabulator](https://tabulator.info/docs/6.3/virtual-dom) | Virtual DOM: visible rows plus "a table heights worth of rows above and below". Needs a fixed table height. | Link. |
| [Retool](https://docs.retool.com/apps/guides/data/table/pagination) | Pages, client or server side (limit-offset, cursor, GraphQL Relay). | Link. |

The grid products virtualise because their data is in the browser, or because they own a client-side row store. ash_table has neither: rows are rendered on the server and patched in.

### What LiveView offers

From the guide ["Scroll events and infinite pagination"](https://hexdocs.pm/phoenix_live_view/bindings.html#scroll-events-and-infinite-pagination) and the docs of [`stream/4`](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#stream/4):

- `phx-viewport-top` and `phx-viewport-bottom` on the stream's container "detect when a container's first child reaches the top of the viewport, or the last child reaches the bottom of the viewport". They send an event; the server streams the next slice in.
- `stream(socket, :rows, rows, at: -1, limit: -75)` appends and keeps at most 75 rows in the DOM, dropping from the top. With a limit and both bindings this is what the guide calls "a fully virtualized list with bidirectional infinite scrolling". The guide sets the limit to three times the page size.
- The guide adds large padding (twice the viewport height) above and below the container "to allow smooth scrolling as results are loaded".
- A `"_overran" => true` parameter arrives when the person dragged the scrollbar past the container; the guide's answer is to reset to the first page.
- "the limit is not enforced on the first `mount/3` render"; load only what you want to show.
- `<.link patch>` and `push_patch` keep the scroll position ([live navigation](https://hexdocs.pm/phoenix_live_view/live-navigation.html)).

What it does not give:

- **No real scrollbar for the whole result.** It is endless scrolling with a cap, not virtual scrolling in the AG Grid sense. You cannot jump to row 30,000.
- **The guide's example pages by offset.** With keyset pagination, going down is `after: cursor of the last row`. Going back up after rows were dropped needs `before: cursor of the first row`, and Ash keyset pagination supports both.
- **The bindings watch the container's first and last child.** In ash_table every row is its own `<tbody>` inside the `<table>`, and the header is a child too. The viewport bindings, the padding trick and a `<tfoot>` summary row all have to be checked against that markup. A sentinel element after the table with a small hook (IntersectionObserver) may be simpler than the bindings.

### Known limits of endless scrolling

- **What comes after the list cannot be reached.** A footer, the summary row, the page's own content below: each time you get near, more rows arrive ([NN/g](https://www.nngroup.com/articles/infinite-scrolling-tips/): it "can make it impossible to access the footer"). The usual fix is a "Load more" button in place of automatic loading, or beside it.
- **Keyboard and screen reader users.** [Deque](https://www.deque.com/blog/infinite-scrolling-rolefeed-accessibility-issues/) lists keyboard-only, switch and speech users as the ones left out, and asks for a way to switch endless scrolling off with "Load more or pagination links" in its place. The W3C [feed pattern](https://www.w3.org/WAI/ARIA/apg/patterns/feed/) is for articles, not grids, but its rules carry over: `aria-busy` while rows are added, and a key that leaves the list (Ctrl+End "Move focus to the first focusable element after the feed").
- **Grids must say where they are.** When not all rows are in the DOM, the [W3C practice](https://www.w3.org/WAI/ARIA/apg/practices/grid-and-table-properties/) asks for `aria-rowcount` (the total, or `-1` when unknown) and `aria-rowindex` on each row. ash_table already sets `aria-rowcount` this way. With a stream limit, rows leave the DOM, so `aria-rowindex` must be the row's position in the result, not in the DOM. With keyset pagination that position is only known by counting from the start.
- **Virtualised rows and screen readers.** [AG Grid's own docs](https://www.ag-grid.com/javascript-data-grid/accessibility/): "screen readers assume all elements of the grid are loaded when the page is loaded", and "The best way to do this is to use pagination."
- **Focus.** If the focused cell's row is dropped by the stream limit, focus is lost. An open editor in such a row is lost with its text.
- **"Select all that match"** keeps working: in ash_table it means "whatever the filters match", not a list of rows. "Select all on the page" loses its meaning; it becomes "all loaded rows", which nobody can count. Ctrl+End "last cell of the last row" also changes meaning: last loaded, not last of the result.
- **Refinding and the back button.** NN/g: "it is hard to remember the location of any specific item and return to it", and after Back the person is at the top again. A page number in the URL solves both; endless scrolling has no natural URL state. Putting a cursor in the URL on every load would fill the history.
- **Sorting by a calculation or aggregate.** ash_table's keyset tables cannot do it today. Endless scrolling on offset pagination can, but then rows shift when records are added or removed while scrolling (a row shown twice, or skipped). Keyset does not have that problem.
- **Summary footer.** With endless rows the footer row must be sticky, or it is never seen.

### Recommendation for ash_table

"Endless scrolling as an option next to pages" should mean, in the smallest good version:

- An option in the `table` block (for example `paginate_with :keyset, scroll: :endless`; the name is the owner's). **Pages stay the default.**
- **Keyset only.** The action must support keyset pagination; the compiler says so otherwise.
- Rows are **appended** at the bottom when the person nears the end. **No stream limit**: what was loaded stays in the DOM. So no rows are dropped, focus and open editors are safe, and scrolling up needs no fetch.
- Under the last row a **"Load more" button** that does the same on demand. It is the keyboard and screen reader way, and what is left when automatic loading is off. Beside it the position: "75 of 320" when the action is countable, "75 loaded" otherwise. At the end: "All 320 records".
- **A ceiling** on loaded rows (say 20 slices). After it, loading on scroll stops and only the button remains. This bounds the DOM and makes the page's footer reachable.
- `aria-busy` on the table while a slice arrives, and an announcement "25 more rows loaded".
- **The URL keeps sort, filters and arguments, not the position.** A reload or a shared link starts at the top. A change of sort or filter resets the stream to the first slice.
- Selection: "select all" in the header means all loaded rows, and the offer "Select all 320 that match" stays as it is.

A capped, two-way window (`limit` plus `phx-viewport-top`) is a second step. It only pays for results people scroll thousands of rows into, and it brings the focus, `aria-rowindex` and editor problems above.

### Decisions for the owner

1. **Endless scrolling or virtual scrolling?** Recommend: endless (append on scroll). *Why: it is what LiveView does natively and what "endless" means to most people. A true virtual scroller needs a client-side row model, which is against server-rendered rows.*
2. **Is it a builder's option or the viewer's choice?** Recommend: the builder's, per table. *Why: it follows from the read action, like `paginate_with`; a viewer toggle doubles the states to test.*
3. **Which pagination underneath?** Recommend: keyset only. *Why: stable when records change while scrolling, and no growing offset cost. Price: no sort by calculation or aggregate, as for keyset pages today.*
4. **Automatic loading, a "Load more" button, or both?** Recommend: both: automatic near the end, and a button that is always there. *Why: Notion uses the button alone; NN/g and Deque both name it as the fix for the footer and keyboard problems.*
5. **Cap the rows in the DOM (stream `limit`)?** Recommend: not in the first version; a ceiling on what is loaded instead. *Why: dropping rows loses focus and open editors and needs `aria-rowindex` by position, which keyset cannot give.*
6. **Is the position in the URL?** Recommend: no. *Why: no product does it, a cursor per scroll step floods the history, and a shared link should open at the top with the same sort and filters.*
7. **What does Back do after following a link out of the table?** Recommend: accept the top of the list in the first version, and say so in the guide. *Why: restoring means reloading every slice or keeping state in the browser; this is the known price of endless lists.*
8. **What do "select all" and Ctrl+End mean?** Recommend: all loaded rows, and the last loaded row; "Select all N that match" unchanged. *Why: both are honest about what is on screen, and the match-selection already covers the rest.*
9. **How big is a slice?** Recommend: the action's `default_limit`, as a page is today. *Why: one rule for page size, on the read action.*
10. **Does the table get its own scroll area with a fixed height?** Recommend: no, it scrolls with the page; the header becomes sticky. *Why: nested scroll areas are hard for keyboard and touch; a fixed height is a layout decision of the host page.*
11. **Summary footer with endless rows?** Recommend: sticky at the bottom of the viewport while the table is in view. *Why: otherwise it cannot be reached.*

---

## 4. Resizing columns (not remembered)

### How others do it

| Product | Mouse | Auto-fit | Keyboard | Limits |
| --- | --- | --- | --- | --- |
| [AG Grid](https://www.ag-grid.com/javascript-data-grid/column-sizing/) | "dragging the right edge of the column header". Shift while dragging takes the space from the neighbour. | "double clicking the right side of the header". Counts rendered rows only. Also "Autosize This Column" in the menu. | "When a column header is focused, press Alt + ← / → to resize". | `minWidth`, `maxWidth` per column. A resized flex column stops being flex. |
| [MUI X](https://mui.com/x/react-data-grid/column-dimensions/) | Drag the separator at the right edge of the header. | Double click the separator; measures "the cells currently rendered in the DOM". | None documented. | Default width 100px, minimum 50px, `maxWidth`, `resizable: false`. |
| [TanStack Table](https://github.com/TanStack/table/blob/v8/docs/guide/column-sizing.md) | A handle the app renders; `getResizeHandler()` for `onMouseDown` and `onTouchStart`. | `resetSize()`; the examples reset on double click. | None. | Default 150, min 20. Mode `onEnd` (a guide line while dragging, apply on release) or `onChange` (live). Advice: "Use CSS variables to communicate column widths to your table cells." |
| [Airtable](https://support.airtable.com/articles/7905594155-airtable-grid-view) | Hover the header's edge until ↔ appears, drag. | None documented. | None documented. | Saved per view. |
| [Notion](https://www.notion.com/help/tables) | "Resize columns by hovering over their edges, and dragging right or left." | None documented. | None. | Saved per view. |
| [Baserow](https://baserow.io/user-docs/field-customization), [NocoDB](https://nocodb.com/docs/product-docs/fields/actions-on-field) | Drag the field's edge. | None documented. | None. | Saved per view. |
| Google Sheets | Drag the border between column letters; double click fits the content. | Double click, and "Fit to data" in the menu. | "Resize column" in the header's menu takes a number. | Unverified from the help text; product behaviour. |
| [Tabulator](https://tabulator.info/docs/6.3/columns) | `resizable`: drag the column's edges, in the header or in cells. | Unverified. | None. | `minWidth`, `maxWidth`. |

**What the standards say.**

- There is no ARIA pattern for resizing a grid column. The nearest is the [window splitter](https://www.w3.org/WAI/ARIA/apg/patterns/windowsplitter/): a focusable `role="separator"` with `aria-valuenow`, `aria-valuemin`, `aria-valuemax`, moved with Left and Right Arrow, Home and End optional. It would add one tab stop or one grid cell per column, which is heavy inside a grid.
- AG Grid's way keeps focus on the header and uses a modifier: Alt+Arrow. ash_table's keyboard guide says combinations with Alt are left to the browser and the system, so check for a clash before copying it.
- [WCAG 2.2, 2.5.7 Dragging Movements](https://www.w3.org/TR/WCAG22/#dragging-movements) (AA): what is done by dragging must also be possible with a single pointer action without dragging, unless dragging is essential. Double click to auto-fit covers part of it; a keyboard way or a menu item covers the rest. [2.1.1 Keyboard](https://www.w3.org/TR/WCAG22/#keyboard) (A) asks for a keyboard way.
- [2.5.8 Target Size](https://www.w3.org/TR/WCAG22/#target-size-minimum) (AA): 24 by 24 CSS pixels, with exceptions. A resize handle is usually 4 to 8px wide to the eye; make the hit area wider than what is drawn.

**Layout.**

- With `table-layout: auto` the browser sizes columns from their content and treats a width as a wish. A resize can be ignored or can move other columns.
- With [`table-layout: fixed`](https://developer.mozilla.org/en-US/docs/Web/CSS/table-layout) widths come from `<col>` elements, or else from the first row's cells, and content no longer matters. The table needs an explicit width, or the fixed algorithm is not used. Long content is cut off by `overflow`. This is the layout that makes dragged widths exact.
- Widths on `<col>` are one place per column, outside the rows. That fits LiveView streams well: no row has to change.
- The alternative is a CSS variable per column on the table root (`--w-title: 240px`) that header and cells read. TanStack recommends this for speed. It is needed anyway if the table is ever built from CSS grid, or for the `left` offset of sticky columns.
- **Horizontal scrolling.** A resize should change the table's total width, not squeeze the neighbours: set the table's width to the sum of the columns and let the wrapper scroll (ash_table's wrapper is already `overflow-x-auto`).
- **Sticky columns.** A sticky column's `left` offset is the sum of the widths before it, so it must be recomputed while dragging. Variables on the root make that a `calc()`.
- **Touch.** Pointer events with `setPointerCapture` and `touch-action: none` on the handle cover mouse, pen and touch in one code path; TanStack wires touch separately.

**LiveView patches.** A width set by the hook is an inline style the server does not know. The next patch of that element removes it. Ways to keep it:

| Way | What it does | Fits |
| --- | --- | --- |
| `<colgroup phx-update="ignore">` with the `<col>`s inside | The server renders it once and never touches it again. | Best fit: widths live on `<col>`, nothing else in it changes. A column that appears later needs care. |
| [`JS.ignore_attributes("style")`](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.JS.html#ignore_attributes/1) on the element, run from `phx-mounted` | Later server changes to that attribute are skipped. It "will only ever ignore future changes from the server". | Good for the table root's `style` holding CSS variables. |
| CSS variables set on an element the server never re-renders with a `style` | Survive as long as the server sends no `style` for it. | Fragile unless combined with the line above. |
| The hook's `updated()` re-applies the widths | Works everywhere, but flickers one frame if the patch removed them. | Fallback. |
| `dom: {onBeforeElUpdated}` on the LiveSocket | Copies attributes before each patch. | Not for a library: it is the host application's socket. |

### Recommendation for ash_table

Short, since it is being built:

- A handle on the right edge of each header cell. Drag resizes that column and the table grows; the wrapper scrolls.
- Double click on the handle fits the column to its content (rows in the DOM only).
- A keyboard way on the focused header. Recommend Shift+Left / Shift+Right if Alt is ruled out, in steps of about 16px; announce the new width in the live region.
- A minimum of about 48px, and no maximum.
- `table-layout: fixed` once any column has been resized, widths on `<col>` in a `<colgroup phx-update="ignore">`, or as CSS variables on the table root protected by `JS.ignore_attributes`.
- The handle is a decoration for pointers (`aria-hidden`), not a tab stop; the keyboard way is on the header.
- Nothing saved. A reload gives the natural widths back.

### Decisions for the owner

1. **Which keyboard way?** Recommend: a key combination on the focused header (AG Grid's model), not a focusable separator per column. *Why: no extra stops in the grid. Pick the modifier that does not clash with ash_table's rule about Alt.*
2. **Double click to auto-fit?** Recommend: yes. *Why: AG Grid, MUI and Sheets have it, and it is the non-drag way WCAG 2.5.7 asks for.*
3. **Does resizing squeeze the neighbours or grow the table?** Recommend: grow the table. *Why: this is what the spreadsheet-like products do; the table already scrolls sideways.*
4. **Is there a way back to the natural widths without a reload?** Recommend: not in the first version. *Why: nothing is saved, so a reload is the reset.*
5. **Minimum width?** Recommend: about 48px, the same for all columns. *Why: MUI uses 50, TanStack 20; below about 48 a cell cannot be focused and read.*

---

## Sources

Primary, fetched 2026-10-12:

- Airtable: [grid view](https://support.airtable.com/articles/7905594155-airtable-grid-view), [field actions](https://support.airtable.com/articles/6540330000-airtable-field-actions), [summary bar](https://support.airtable.com/docs/the-summary-bar)
- Notion: [tables](https://www.notion.com/help/tables), [database properties](https://www.notion.com/help/database-properties), [views, filters and sorts](https://www.notion.com/help/views-filters-and-sorts), [timelines](https://www.notion.com/help/timelines), [performance](https://www.notion.com/help/optimize-database-load-times-and-performance)
- Baserow: [field customization](https://baserow.io/user-docs/field-customization), [field summaries](https://baserow.io/user-docs/footer-aggregation)
- NocoDB: [actions on field](https://nocodb.com/docs/product-docs/fields/actions-on-field), [field summary](https://nocodb.com/docs/product-docs/fields/field-summary-footer), [experimental features](https://nocodb.com/docs/product-docs/account-settings/experimental-features)
- Google Sheets: [see the sum and average](https://support.google.com/docs/answer/66032)
- GitHub Projects: [customizing the table layout](https://docs.github.com/en/issues/planning-and-tracking-with-projects/customizing-views-in-your-project/customizing-the-table-layout), [increased items](https://github.blog/changelog/2025-02-26-increased-items-in-github-projects-now-in-public-preview/)
- Linear: [display options](https://linear.app/docs/display-options)
- AG Grid: [columns tool panel](https://www.ag-grid.com/javascript-data-grid/tool-panel-columns/), [column menu](https://www.ag-grid.com/javascript-data-grid/column-menu/), [column sizing](https://www.ag-grid.com/javascript-data-grid/column-sizing/), [keyboard](https://www.ag-grid.com/javascript-data-grid/keyboard-navigation/), [status bar](https://www.ag-grid.com/javascript-data-grid/status-bar/), [total rows](https://www.ag-grid.com/javascript-data-grid/grouping-footers/), [row models](https://www.ag-grid.com/javascript-data-grid/row-models/), [accessibility](https://www.ag-grid.com/javascript-data-grid/accessibility/), [quick filter](https://www.ag-grid.com/javascript-data-grid/filter-quick/)
- MUI X: [column visibility](https://mui.com/x/react-data-grid/column-visibility/), [column dimensions](https://mui.com/x/react-data-grid/column-dimensions/), [aggregation](https://mui.com/x/react-data-grid/aggregation/), [pagination](https://mui.com/x/react-data-grid/pagination/), [lazy loading](https://mui.com/x/react-data-grid/server-side-data/lazy-loading/), [accessibility](https://mui.com/x/react-data-grid/accessibility/), [quick filter](https://mui.com/x/react-data-grid/filtering/quick-filter/)
- TanStack Table (v8 docs in the repository): [column visibility](https://github.com/TanStack/table/blob/v8/docs/guide/column-visibility.md), [column sizing](https://github.com/TanStack/table/blob/v8/docs/guide/column-sizing.md), [virtualization](https://github.com/TanStack/table/blob/v8/docs/guide/virtualization.md), [pagination](https://github.com/TanStack/table/blob/v8/docs/guide/pagination.md)
- Tabulator: [columns](https://tabulator.info/docs/6.3/columns), [column calculations](https://tabulator.info/docs/6.3/column-calcs), [virtual DOM](https://tabulator.info/docs/6.3/virtual-dom)
- Retool: [table](https://docs.retool.com/apps/guides/data/table), [customization](https://docs.retool.com/apps/guides/data/table/customization), [pagination](https://docs.retool.com/apps/guides/data/table/pagination)
- Phoenix LiveView (main branch): [bindings guide](https://github.com/phoenixframework/phoenix_live_view/blob/main/guides/client/bindings.md), [`stream/4`](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#stream/4), [`JS.ignore_attributes/1`](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.JS.html#ignore_attributes/1), [JS interop](https://github.com/phoenixframework/phoenix_live_view/blob/main/guides/client/js-interop.md), [live navigation](https://github.com/phoenixframework/phoenix_live_view/blob/main/guides/server/live-navigation.md)
- W3C: [grid and table properties](https://www.w3.org/WAI/ARIA/apg/practices/grid-and-table-properties/), [feed](https://www.w3.org/WAI/ARIA/apg/patterns/feed/), [window splitter](https://www.w3.org/WAI/ARIA/apg/patterns/windowsplitter/), [menu](https://www.w3.org/WAI/ARIA/apg/patterns/menubar/), [WCAG 2.2](https://www.w3.org/TR/WCAG22/)
- MDN: [`table-layout`](https://developer.mozilla.org/en-US/docs/Web/CSS/table-layout)

Secondary (opinion, not a product's own statement): [NN/g on infinite scrolling](https://www.nngroup.com/articles/infinite-scrolling-tips/), [Deque on infinite scrolling](https://www.deque.com/blog/infinite-scrolling-rolefeed-accessibility-issues/).

Not verified from a primary source, and marked so above:

- That Airtable's, Baserow's and Linear's lists are virtualised, and how GitHub Projects loads rows. These are product behaviour without a doc page.
- Notion: hiding from the column header, whether the title can be hidden in a table, the table's "Load limit", the scope of "Calculate".
- The count on the "hide fields" button in Baserow and NocoDB; NocoDB's display value rule.
- AG Grid's full list of built-in aggregate functions; Tabulator's calcs under remote pagination; Google Sheets' column resize details.
- What any product shows in the footer while a summary loads. None documents it.
- The WCAG criteria are paraphrased, not quoted.
- The Retool pagination and disclosure-pattern links were not fetched; the pages are cited from search results and from memory of the W3C practices.
