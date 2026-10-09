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
  `update_action`, `confirm` and `exposes_protected_field?`; `relationship`
  and `action` entities and `create_action` are described below. With no
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
- **Arrays.** An array of text, numbers, booleans, dates, datetimes or enum
  values is a cell of its own: shown as its values, as plain text separated
  by commas, each as a cell of its type shows it (the labels of an enum's
  values), and edited as a whole. An array of enum values is edited as
  multiple choice, a list of boxes that opens in the cell; any other with
  one control per value, a button that takes each value away and one that
  adds a value. Enter or leaving the editor saves the list, Escape gives it
  up; the values go to the column's update action as they were typed, and
  the array's constraints are the action's to check. The same two editors
  are the fields of an array in the action panel. An array column is
  neither sorted nor filtered by, as in Ash's interface extensions. Arrays
  of anything else (maps, embedded resources, unions, keys, arrays) stay
  read-only text. A column's `component` shows an array's cells; its editor
  is not used for one. A component is told `cell_type: {:array, item}` for
  such a column, where it was told `:other`.
- An error an action returns about one value of an array is shown, in a
  cell and in the action panel.

### Authorization

- Actor, tenant or scope passed into every Ash call. Columns a person can
  never see are left out, columns they can never edit are read-only, fields
  hidden on some records show "Not available", and a read refused outright
  answers 404, or a message with `on_forbidden :message`.
- An error names a field only when the person has a column for it.
- Every action a table runs is `public?`, however the table came by it. A
  private action is not meant for interfaces, and the policy Ash documents
  for one lets everybody run it. Reported when the resource is compiled,
  and refused when the table is built: a private primary read action that
  the table falls back to; a private read action behind a relationship the
  block declares (the relationship's own, else that of the destination's
  table; that of the join resource of a many-to-many; that of a resource a
  `through` path passes), behind a reference cell (the relationship's own,
  else the destination's primary one), or behind an aggregate column or a
  calculation column that holds an aggregate (along the aggregate's whole
  path); and a private primary read action under a table that changes
  records, since Ash loads what a create, an update or a destroy action
  returns through it. A relationship of the default set that leads to a
  private read action is not offered.
- The record of a row is read again through the table's read action before
  a cell is saved or a row action runs, and the row a nested table belongs
  to through the read action of the table that shows it; the row a full
  view is limited to through the read action of that row's own table. A key
  reaches no record that the table would not show.

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
- States are shown with the theme's colours and can be seen: the focus ring
  is in the text colour, 2px inside the cell; a failed cell has a ring and a
  "!" that does not depend on a colour, and shows both rings when it has
  focus; a saving cell and the rows of a table that is reading are dimmed to
  70%, the header and the filters not at all; inputs and menus have an edge
  at half the strength of the text colour. Their contrast is measured by the
  demo's browser tests in its light and dark theme.
- In forced colours every state is still drawn: the failed ring is a border,
  the dialog and the action panel have one there, the current page is
  underlined there, and an expander stays a triangle.

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

### Row actions and create

- `action` entities in the `table` section, with `label` and `confirm`: a
  row action, a public update or destroy action of the resource that a
  person runs on the record of a row. The buttons stand in the declared
  order in a last column of the grid, "Actions", which counts as a column
  (`aria-colindex`, `aria-colcount`). Opt-in: no `action`, no column.
- `create_action` in the `table` section: a public create action behind a
  create button, named after the resource ("New task").
- An action without inputs, or with optional arguments only, runs when its
  button is used. One that accepts attributes or has a required argument
  opens the **action panel** first, a modal dialog at the right edge of the
  window, built on the native `<dialog>`; a create always does. The panel
  has one field per public input in the action's order, accepted attributes
  first: labelled as the table's column for the attribute, else by the
  input's name in words; with the cell editor of its type, or a plain text
  field for a value written as one line (a UUID, a time, an atom); starting
  with the record's values and the arguments' defaults; marked as required
  as the action requires it.
- An optional input of a type without a field (maps, embedded resources,
  unions, and arrays of them) is left out of the panel. An action that requires one
  is reported when the resource is compiled and has no button.
- The panel's form is an `AshPhoenix.Form`: what is typed is validated by
  the action as it is typed, errors are shown at their fields, and what is
  about no field of the panel is above them. The panel stays open when the
  action fails.
- `confirm` on an action asks its question in the table's dialog before the
  action runs; for an action with a panel, when "Run" is used. The answer
  that confirms a destroy action is in the error colour. A destroy action
  without `confirm` is a warning when the resource is compiled;
  `confirm false` says that a delete in one click is meant.
- The record of a row is read again, as the person, before its action runs,
  and before its panel opens. After an update the row is shown from what
  the action returned, in its place; after a destroy the row is taken away
  with everything open under it; a created record is the first row of the
  page until the next read. The total, the range and the row indices follow
  by one. A page left without rows is read again.
- An action that ran straight away and failed marks the row's actions cell
  with the action's message, as a failed save marks its cell, and is
  announced. Escape on the cell gives the message up.
- A row action a person can never run has no button for them, and a table
  with none left has no actions column; a create action they can never run
  has no create button (`Ash.can/3`, once per action). An input of a field
  a person can never see is no field of a panel for them, one hidden on the
  record is left out of that record's panel, and a value sent for either is
  dropped.
- A nested table has the row actions of the destination's table. It offers
  create for a has-many joined by attributes whose destination's
  `create_action` accepts the joining attribute: the table fills that in
  from the row above, read again as the person, and the button is on the
  relationship line. The full view has it beside "Show all records".
- The keyboard: Enter or F2 on an actions cell goes to its first button,
  Left and Right Arrow move between the buttons, Escape returns to the
  cell, Tab goes on through them and out of the grid. F2 on a relationship
  line with a create button goes to the line's controls. After a destroy,
  focus goes to the actions cell of the next row; after a create, to the
  first cell of the new row; after the panel closes, to the control that
  opened it.
- `heading` on `<AshTable.table>`: how the table's name is shown on the
  line above it, which also holds the create button. `true` (the default)
  shows it as text, a number from 1 to 6 as a heading of that level, `false`
  leaves it out.
- New messages in the Gettext template: "Actions", "New %{name}", "Run",
  "Create", "%{action}: %{record}", "%{action}: done", "%{name} created",
  "%{action} failed: %{message}", "You are not allowed to do this." and
  "This could not be done." The labels of actions and of the panel's fields,
  the questions, and what one record is called are looked up like column
  labels.
- Reported when the resource is compiled: an `action` that names no public
  update or destroy action (a create, a read and a generic action each with
  its own sentence), one declared twice, an action or a create action with
  a required input the panel has no field for, a `create_action` that names
  no public create action, and row actions or a create action beside
  calculation, aggregate or reference columns without a primary read
  action.

### Custom components

- `component` on a `column`: a module that says how the cells of the column
  look, what they are edited with, or both. It changes the look and the
  control only: a save runs the column's `update_action` as before, and
  sorting, filtering and authorization are untouched.
- `AshTable.Component`, the behaviour of such a module, with two optional
  function components. `cell/1` is given the value, the text the table
  itself would show, and the column (`AshTable.Component.Column`: the
  field's name, type and constraints, an enum's values with their labels,
  the column's label, whether the person can edit it). `editor/1` is given
  the control's value, the attributes the table needs on the control
  (`{@control}`), the label, the column, and where it is (`:grid` or
  `:panel`). `use AshTable.Component` checks that a module has one of the
  two parts.
- A component is never given a value the person may not see, a record
  without a value, or the record itself: the table shows its own placeholder
  and its own empty cell.
- `use AshTable.Component, commit: :change` makes an editor save when its
  value changes (a slider when it is let go) and stay open; the default,
  `:enter`, saves on Enter and on leaving the cell. A step with the keyboard
  is saved by Enter or by leaving, as in the table's own menus. Escape gives
  up what has not been saved. `confirm` asks before a change is saved.
- The editor of a column's component is the field of that attribute in the
  action panel, under the table's label and with the action's messages. In
  the panel a change saves nothing: the value goes with the form.
- Three components are shipped: `AshTable.Components.Badge` shows an enum's
  value as a badge, `AshTable.Components.Progress` a number between its
  minimum and maximum as a bar with the number beside it, and
  `AshTable.Components.Slider` edits such a number with a native range
  input. Each says when the resource is compiled what its field has to be
  (`verify/1`, which a component of the host's can define as well).
- Reported when the resource is compiled, and refused when the table is
  built: a `component` that names no module, a module that is no component
  or has neither part, and a component that cannot serve its column. Also
  reported: a component that only edits on a column that can never be
  edited, and `component` on a column that names a relationship.
- A resource does not depend on the component it names: no compile-time
  dependency from the data layer to the web layer. The component is looked
  at once the application is compiled, so a change to the component alone is
  checked by the next full compile.
- A badge, a progress bar and a slider leave a row as high as it is without
  them, are drawn in the theme's text colour, and are still drawn in forced
  colours. Their contrast is measured by the demo's browser tests.

### Changed since the reference cells were added

- A table placed with `<AshTable.table … />` now shows its name on a line
  above its grid. A page that names the table itself passes
  `heading={false}`.
- The heading of a mounted page is rendered by the table: the `h1` has the
  id `ID-name`, in the line `ID-header`, beside the create button.
- A table with row actions has one column more for assistive technology
  (`aria-colcount`), and the cells that span a nested table's grid span it
  too.

### Changed since the nested tables were added

- A column that names nothing the resource has is now reported as "The
  resource has no attribute, calculation, aggregate or belongs-to
  relationship named …", and the finding about editing without a primary
  read action counts reference columns.
- The pages of a nested table are no longer the last row of its grid where
  the nested table has a link to the full view: the link's row follows.

### Changed since row actions and create were added

- The editor template of a column says when it saves (`data-commit`) when
  it is a component's, and `data-editor` is `component` then.
- A cell of an editable column whose component shows carries `data-value`,
  as the cells of choices and booleans do.
- A double click beside the control of an editor that is open no longer
  opens the editor a second time.

### Changed since custom components were added

- **A table that ran a private action is now refused.** A resource is
  affected when an action is declared `public? false` and a table runs it
  without the block naming it: as the primary read action of a table whose
  block names no `read_action`; as a read action of a relationship (its
  own, that of its destination's table, that of a many-to-many's join
  resource, that of a resource on a `through` path), of a reference cell,
  or of an aggregate column or a calculation column that holds an
  aggregate; or as the primary read action of a table that has editable
  columns, row actions or a create action. Each is reported when the
  resource is compiled. A relationship of the default set that is read
  through a private action is no longer offered, with nothing reported.
- **The record of a row is read again through the table's read action**, no
  longer through the primary one, and the row of a nested table through the
  read action of the table that shows it. Where the two actions return different
  records, a row that the table shows and the primary read action does not
  return can now be saved and acted on, and one that the table does not
  show can no longer be reached by a key in an address. Aggregates of a
  page, and everything a nested table's columns show besides attributes,
  are loaded through the table's read action as well.
- A nested table whose relationship names an action that is no read action
  of its resource is refused. It was read through the table's own read
  action in its place.
- "New …" on a relationship line whose row is gone makes the nested table
  read again, which shows "This record is no longer available."; it was only
  announced.
- The create button in a table's header is not rendered beside a read that
  failed or was refused.

### Tooling

- `mix ash_table.install`, an Igniter installer (`mix igniter.install
  ash_table`): the hook in `app.js`, the Tailwind source in `app.css`, the
  formatter and the configuration.
- The DSL reference, generated by Spark.
