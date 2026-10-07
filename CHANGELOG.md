# Changelog

All notable changes to this project are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.1.0 (unreleased)

The first version: a resource as an editable table in Phoenix LiveView,
declared in the resource and mounted with one line in the router.

### Declaring and placing a table

- `AshTable.Resource`, the extension with the `table` section: `read_action`,
  `paginate_with`, `update_action`, `on_forbidden`, `label_field`, and
  `column` entities with `label`, `sortable?`, `filterable?`,
  `update_action`, `confirm` and `exposes_protected_field?`. With no
  block the table shows the public attributes, read-only. Mistakes in the
  block are reported by verifiers when the resource is compiled, as
  warnings: among them a column's own `update_action` on a column that no
  action could make editable. A table of a resource compiled despite a
  finding that leaves it nothing sound to do (no usable read action,
  pagination, column or update action) refuses to render with an
  `ArgumentError`.
- `AshTable.Router.ash_table/3` mounts a table as a page, with `id:` and
  `layout:`; `<AshTable.table … />` places one in a LiveView of the host's,
  several to a page if wanted.
- `AshTable.Domain`, the extension with the domain's `table` section:
  `authorize?` and the socket assigns that hold scope, actor and tenant.
- `config :ash_table, layout: {MyAppWeb.Layouts, :app}` for the layout of
  mounted tables. The layout is given the flash and who is asking, under the
  conventional assign names and under those the domain names.

### Reading

- Sorting, filtering and pagination on the server, through the read action,
  with `Ash.Query.sort_input/2` and `Ash.Query.filter_input/2`. Page size and
  default sort are the read action's.
- Offset pagination with page numbers and a total, keyset pagination with
  previous and next, or every record for an action without pagination. A
  countable action is asked for its count under either strategy: a keyset
  table shows the total alone ("320 records").
- A page beyond the last offers the pages there are, and Previous leads to
  the last of them.
- A filter row with one filter per column and a short list of operators per
  type: text, number, date, datetime, boolean and enum.
- Sort, filters and page in the URL of a mounted table, and of a table
  placed in a LiveView that hands it the page's `url`.
- Loading, empty and failed states. An error the read action returned on
  purpose is shown; any other failure is logged and shown as "The records
  could not be loaded."

### Editing

- Cells are edited in place and saved one at a time through the column's
  update action, with `AshPhoenix.Form`: text, numbers, booleans, dates,
  datetimes and enums. The row is shown from what the action returns.
- A failed save marks its cell with the action's message and keeps what was
  typed. `confirm` asks in a dialog before saving.

### Authorization

- Actor, tenant or scope passed into every Ash call. Columns a person can
  never see are left out, columns they can never edit are read-only, fields
  hidden on some records show "Not available", and a read refused outright
  answers 404, or a message with `on_forbidden :message`.
- An error names a field only when the person has a column for it.

### Accessibility and keyboard

- An ARIA grid with one tab stop, moved by the arrow keys, Home, End, Page Up
  and Page Down without a round trip; colocated hooks, no npm package.
- Enter, F2 or a character starts editing a cell or goes into a filter;
  Escape gives up. Results of filters and failed saves are announced, the
  former with their count whenever the read action counts.
- The pagination is ordinary buttons outside the grid. Focus stays on the
  one that was used; when it is disabled by the page it led to, focus goes to
  the button of that page, or to the other of Previous and Next in a table
  without page numbers.

### Translation

- Every text of the table is a message of the Gettext domain `ash_table`,
  in English by default; `config :ash_table, gettext_backend: …` has a host's
  backend translate them, and the labels of its columns and enum values.
- `config :ash_table, translate_error: …` has the host translate the messages
  of its actions as it does for its forms.

### Nested tables

- A row expands into one line per relationship, and a line opens the nested
  table: the destination resource's own table inside the row, limited to the
  records related to it, with its own sort, filters, pages and inline
  editing. Nested tables expand again.
- `relationship` entities in the `table` section, with `label`. With none
  declared, a row offers every public relationship whose destination has a
  table, except manual ones; once one is declared, exactly the declared ones
  in the declared order. A `relationship` that names no public relationship,
  or whose destination has no table, is reported when the resource is
  compiled, and refused when the table is built.
- `max_depth` in the `table` section (default 3): how deep a person can
  expand, counted from the table on the page. `0` means the rows of the
  table never expand.
- A nested table reads through Ash's own loader: the row it belongs to is
  read again by its primary key, as the person, with the relationship as a
  load that carries the nested table's query. It runs the relationship's own
  `read_action` if it has one and puts the relationship's own `sort` first.
  It has pages where Ash can page the relationship; a belongs-to and a
  has-one are a table of at most one row without sort, filters or pages.
- A line whose destination a person can never read is left out for them. A
  nested table shows no total while a filter is set on a column the person
  sees on some records only, as Ash counts a page of related records without
  the field policies.
- The expander is the first cell of a row and counts as a column
  (`aria-colindex`, `aria-colcount`). Right Arrow and Left Arrow on it expand
  and collapse; Enter on the cell of a nested table goes into it and Escape
  comes back out. The whole tree of tables is one tab stop.
- Nothing of a nested table is in the URL.
- **The full view.** The last row of a nested table is a link, "Open in full
  view", to the page the host's router mounts the destination's table at:
  the first `ash_table` route for that resource whose path has no parameter.
  Without such a route there is no link. The page shows the same records,
  limited by the table's parameter `of`
  (`/comments?comment[of][task][comments]=KEY`; a key of several attributes
  by attribute), with sort, filters and page in the address beside it, a
  heading that names the parent and the relationship, and "Show all records"
  to take the limit away. The parent's resource is looked up by its short
  name among the resources of the application's domains and of the table's
  own, and only where its table offers the person that relationship; the
  key is cast; the parent is read as the person on every read. Anything else
  in the parameter is ignored. A table placed with `<AshTable.table url=…>`
  reads the same parameter.
- The heading calls the parent by its `label_field`, else by the first of
  its table's attribute columns that the person sees on it, and names no
  record that was not read for them.

### Reference cells

- `column :assignee`, naming a public belongs-to relationship, shows the
  related record's label: the public attribute that the destination's
  `table` block names with `label_field`. Read-only; not sorted by (Ash
  applies no policy of the related resource to a sort through a
  relationship) and not filtered by.
- The label is read as Ash loads the relationship, with a select of the key
  and the label, as the person: one statement per reference column per
  page, and again for a row that is saved. A related record the person may
  not read is an empty cell, as no related record is; a label hidden from
  them is "Not available"; a person who can never read the destination, or
  never see its label, has no such column.
- Reported when the resource is compiled: a column naming a relationship
  that is not a belongs-to, whose destination has no table, no
  `label_field` or no read action to load through, `sortable? true`,
  `filterable? true`, `update_action` and `confirm` on such a column, and a
  `label_field` that names no public attribute.

### Aggregate and calculation columns

- A warning when the resource is compiled, for an aggregate column whose
  field or `filter` is protected by a field policy on the related resource,
  and for a calculation column whose expression references a protected
  field, while the declaring resource has no field policy that names the
  column. Ash applies no field policy of what an aggregate or a calculation
  is made from. `exposes_protected_field? true` on the column says that the
  exposure is meant.
- A `first` aggregate column over one related record, beside an expression
  calculation column over the same relationship, is read in a statement of
  its own and is not sorted or filtered by: read together on a SQL data
  layer, it returns the value of a record the reader may not read. A warning
  says so, and how to get out of it (`join_filter` or `read_action` on the
  aggregate; or `sortable? false` and `filterable? false` on the column).
- Aggregate columns are loaded onto the records of a page after the page is
  read, and related records are read bare with everything loaded
  afterwards: a statement with an aggregate beside a field that a field
  policy hides on some records fails in the SQL layer where it is a
  subquery. One more statement per read of a table with aggregate columns.
- An aggregate column that a field policy hides from a person on some
  records is not sorted by for them, as Ash raises for it; nor is any
  aggregate column in a nested table read in pages, for a person who sees
  some field of that resource on some records only. Their filters stay.

### Changed since the nested tables were added

- A column that names nothing the resource has is now reported as "The
  resource has no attribute, calculation, aggregate or belongs-to
  relationship named …", and the finding about editing without a primary
  read action counts reference columns.
- The pages of a nested table are no longer the last row of its grid where
  the nested table has a link to the full view: the link's row follows.

### Tooling

- `mix ash_table.install`, an Igniter installer (`mix igniter.install
  ash_table`): the hook in `app.js`, the Tailwind source in `app.css`, the
  formatter and the configuration.
- The DSL reference, generated by Spark.
