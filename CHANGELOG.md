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
- `AshTable.Router.ash_table/3` mounts a table as a page, with `id:`,
  `layout:` and `authorize?:` (`false` mounts the page without
  authorization, for an admin area behind the host's own access control); `<AshTable.table … />` places one in a LiveView of the host's,
  several to a page if wanted.
- `AshTable.Domain`, the extension with the domain's `table` section:
  `authorize?` and the socket assigns that hold scope, actor and tenant.
- `config :ash_table, layout: {MyAppWeb.Layouts, :app}` for the layout of
  mounted tables. The layout is given the flash and who is asking, under the
  conventional assign names and under those the domain names.


### Scrolling sideways

- Every table scrolls sideways in an area of its own: the table on a page,
  every nested table and the table of a picker. A nested table is as wide as
  what is seen of the table around it and stays in place while that table
  scrolls; the line that opens it, its "Columns" button and its pages stay
  with it. A nested table scrolled to its end does not scroll the table
  around it.
- A table whose own scrollbar is below the window has a second one at the
  bottom edge of the window, for the innermost table that is cut off there.
  `--ash-table-bottom` keeps it above a host's fixed footer.
- `sticky_label? true` in a `table` block or a named table keeps the label
  column in view while the table scrolls sideways, with the cells that select
  and expand a row. Off by default. Verified at compile time: the resource
  has a `label_field`, and the table shows it. `--ash-table-ground` names the
  colour behind a table for those cells.
- A cell that the keyboard moves focus to is brought into view in its own
  table's area, beside the cells that stay and above the second scrollbar.
  The grids are no tab stops of their own in browsers that make one of every
  element that scrolls.
- Changed markup: what a relationship line holds is in an element of its own
  (`td[data-line] > div > button`), and a nested table is two elements deep
  in its cell.

### Long text

- `max_lines` on a `column` (1 to 10, default 1): its cells wrap, keep the
  line breaks of the value and are cut off after that many lines; a row is
  as high as its highest cell. For a column shown as text. On a number, a
  date, a datetime, a boolean, an enum, a reference cell, a sensitive column
  or a column whose component shows the cell it is reported at compile time.
- The whole text of a cell that cuts some of its text off, in any column, is
  shown in a popover under the cell while the cell has the focus or the
  pointer rests on it, after a moment. Escape takes it away without moving
  the focus, the pointer can go onto it, and it scrolls when the text is
  long. The browser fills it from the cell's own text: nothing is sent for
  it. A sensitive cell has none. It is hidden from screen readers, which
  read the text in the cell.

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
- **Arguments.** Every `public?` argument of the table's read action has an
  input in the argument line, above the rows, with the control of its type:
  text, number, boolean, date, datetime, enum, a multiple choice for an
  array of enum values, a row per value for an array of text, numbers or
  dates, and a line of text for a key. Nothing is declared for it; an
  `argument` entity gives one a label. An argument is applied when its input
  is left or Enter is used, and is part of the table's state with the sort
  and the filters. While an argument the action requires is empty the
  action is not run, and the table says "Fill in … to see records." in
  place of its rows; a value Ash refuses is shown at its input with the
  action's message, and the rows stay. The arguments are given wherever the
  table runs its read action for the person: the page and its count, what
  is loaded onto its rows, the record of a row before an edit or an action,
  the selected records and "all that match", and the row a nested table
  belongs to. A nested table, the full view and a picker have the line of
  the action they read through.
- **Calculations with arguments as columns.** A `column` fixes them
  (`arguments currency: :eur`) or asks the person for them
  (`ask :currency, default: :eur`, with a value or a function of the page's
  assigns as its default), in the same line. `as` names the second column
  of one calculation. Each column is loaded, sorted and filtered by with its
  own arguments. A required argument that is given neither way, an unknown
  one, a value of the wrong type, and an asked argument that cannot be
  empty and has no default are reported when the resource is compiled.
  `<AshTable.table>` takes `assigns` for a default that is a function.
- Sort, filters, arguments and page in the URL of a mounted table, and of a
  table placed in a LiveView that hands it the page's `url`.
- Loading, empty and failed states. An error the read action returned on
  purpose is shown; any other failure is logged and shown as "The records
  could not be loaded."

### Editing

- Cells are edited in place and saved one at a time through the column's
  update action, with `AshPhoenix.Form`: text, numbers, booleans, dates,
  datetimes and enums. The row is shown from what the action returns.
- A failed save marks its cell with the action's message and keeps what was
  typed. `confirm` asks in a dialog before saving.
- **Choosing a related record.** A reference cell is edited where its
  column's update action, its own or the table's, accepts the relationship's
  foreign key: Enter, F2 or a double click opens the picker, a modal dialog
  at the right edge with the destination resource's own table (its columns,
  filter row, sorting and pages), read as the person. The table there is for
  choosing only, and its rows are selected one at a time. A row is selected
  with a click or Space and taken with "Choose"; Enter on a row and a double
  click choose it at once; "None" empties a key that can be empty; Escape
  and "Cancel" close. The save is that of a cell: the column's action with
  the key as its one input, nothing for the record the cell points at
  already, the question of `confirm` on top of the picker, the row shown
  from the action's result, and a refused save on the cell. The record that
  was chosen is read again on the server, as the person and through the
  read action the picker shows its rows through, before its key is saved: a
  key of a record they may not read there saves nothing. The records on
  offer are those of the relationship's own `read_action` when it names
  one, else of the read action of the destination's table. A relationship
  with a `filter`, or whose key is not a public, writable attribute, has no
  picker, and its cell stays read-only.
- In the action panel, an input that is such a key is a field that says
  what the related record is called and has a button that opens the same
  picker, on top of the panel; the panel keeps what else was typed. The
  field is called what the table's column of the relationship is called. A
  key that was put into such a field is looked up as the person before the
  action runs. A key whose destination has no table stays a typed field.
- `update_action` and `confirm` on a column that names a relationship are
  no longer mistakes in themselves. They are reported where the action does
  not accept the relationship's foreign key, and where the related record
  cannot be chosen.
- Where one row at a time is selected, a table's rows have radio buttons
  of one group, its grid says `aria-multiselectable="false"`, and the
  selected row stays selected when it is used again.
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
- **Maps and embedded resources.** An embedded resource, a map, and an
  array of either are cells of their own (`cell_type: :map`, and
  `{:array, :map}`), where they were read-only text as Elixir writes them.
  The cell shows the value on one line, as plain text: its fields as
  `label: value` with commas between them, each field called by its name in
  words (through the host's Gettext, as a column's label) and shown as a
  cell of its type shows it; a field that holds nothing is left out; a
  value inside the value follows its label the same way; the values of an
  array have `; ` between them. The fields of an embedded resource are its
  public attributes, without a primary key that nobody gives; those of a
  map are the fields it declares, or whatever it holds when it declares
  none. A private attribute of an embedded resource is no longer shown.
- An embedded resource, a map that declares its fields (also as a NewType),
  and an array of either are edited in the side panel: Enter, F2 or a
  double click on the cell opens the action panel, headed by the column and
  the record, with the value as a group of its fields, each with the
  control of its type, a value inside it as a group in the group, and an
  array as a group per value with a button that takes the value away and
  one that adds a value. A value that may be empty is taken away and added
  the same way. "Save" runs the column's update action with the attribute
  as its one input, given as a map of its fields; a panel that holds what
  the record holds saves nothing; the column's `confirm` asks only when
  something was changed. What the action says about a field of the value is
  shown at that field, in an array at that field of that value, and the
  panel stays open with what was typed. A map that declares no fields is
  read-only, and so is a value with a field a table has no control for, or
  an embedded resource whose create and update actions accept different
  attributes or need what a table cannot give; a column's own
  `update_action` on one is reported when the resource is compiled.
- In the action panel, of a row action, of an action on the selected rows
  and of the create action, an input that is such a value is the same
  group of fields under the input's label.
- An embedded resource and a map are neither sorted nor filtered by. A
  column of an embedded resource, or of a NewType of a map, no longer
  offers a sort: `Ash.Query.sort_input/2` refuses the first, and the second
  is a map, which Ash does not sort by.
- The forms a table runs its actions through build no nested forms
  (`forms: [auto?: false]`): the value of an embedded resource is given to
  the action as a map, as the value of a map is.
- An error an action returns about a field of a value inside the record,
  where it is not shown at that field, says the way to it ("Client: Street:
  is required"), when the person has a column for the value; such an error
  is never taken for one about a column of the same name.
- New texts: "%{field}: %{value}", "Save", "Remove %{column}".
- A column's `component` shows the cells of such a column; its editor is
  not used for one. A component is told `cell_type: :map`, or
  `{:array, :map}`, where it was told `:other`.
- An error an action returns about one value of an array is shown, in a
  cell and in the action panel, and says which value: "Tags 2: length must
  be greater than or equal to 2". In the list of values the control of that
  value is marked `aria-invalid`, when the cell is opened again and in the
  panel.
- A multiple choice keeps the values a record holds that are none of its
  choices (possible for an array of `:atom` with `one_of`): they have no
  box and are sent back after the ticked values, so a save changes only
  what a person could see. Whether the list is accepted is the action's to
  say.

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

### Relationships an action manages

- An argument of an action that a `manage_relationship` change hands to a
  relationship, and that holds the key of a related record or a list of
  such keys, is given by choosing existing records in the picker. Nothing
  is declared for it. The key is the related resource's primary key, or the
  attribute the change names with `value_is_key`. The relationship has to
  be public, without a `filter`, and its destination has to have a table;
  any other such argument is the input it was (one key is typed, a list of
  keys has no field). A map, or a list of maps, is no such argument: a
  table creates no related record through an action.
- A field of one key is the field of a key the action accepts. A field of a
  list of keys lists what its records are called, each with a button that
  takes it out again, and its "Choose" opens the picker with a box per row,
  the rows of the field's records selected on whatever page they are, and a
  count of what is selected above the grid. "Choose" takes whatever is
  selected; Enter on a row and a double click choose nothing there.
- Where the argument is everything the relationship is to hold
  (`on_missing`: `:append_and_remove`), its field starts with the records
  that are related now, read as Ash reads them when the action runs, for
  the same person. A record they may not read is neither shown nor taken
  away. `:append` and `:remove` start empty.
- A reference cell is edited through such an argument: where its update
  action does not accept the foreign key and has an argument that hands one
  key to the column's relationship and relates the record it names. The key
  need not be public or writable then. The key the action accepts comes
  first.
- Every key that was not related already is read as the person, through
  the picker's read action, when it is chosen and again before the action
  runs. One that names nothing they may read runs nothing.
- A record Ash does not find for a key (`Ash.Error.Query.NotFound`, which
  has no text of its own) is said at the argument's field: "This record is
  no longer available."
- A change that would make a record for a key that names none
  (`type: :direct_control`, `type: :create`) is not chosen.
- Reported when the resource is compiled: a column's own `update_action`
  whose argument holds a list of keys, does not relate the record it
  names, or holds no key; and an action that requires a list of keys whose
  records cannot be chosen, with the reason.

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

### Row selection and bulk actions

- A table with a row action that a person can run on several rows has a
  first column of boxes: one per row, and one in the header that stands for
  the rows of the page and is mixed when some are selected. It counts as a
  column (`aria-colindex`, `aria-colcount`); where rows expand, the
  expander is the second cell of a row. The grid is
  `aria-multiselectable`, and every row of records says `aria-selected`.
  The mark of a selected row is its ticked box.
- Selecting is the browser's alone: a click on a box, Space on any cell of
  a row, Shift and a click or Shift with Down or Up Arrow for a range. It
  sends nothing and brings no row back. A selection lasts through a sort
  and a change of page, is given up when a filter changes, and is in no
  URL. Each table has its own; a nested table's is apart from that of the
  table around it.
- "Select all N that match", offered once every row of the page is selected
  and the filters match more: every record the read action returns for the
  person under the filters, worked out on the server when an action runs.
  Without a number where the read action does not count.
- A line above the grid, beside "Clear filters": the number of selected
  records in a live region, "Clear selection", and a button per bulk
  action.
- The bulk actions are the table's row actions. `bulk? false` on an
  `action` keeps it to one row. An action that accepts an attribute of the
  primary key, or one that is an identity by itself, is not offered either;
  `bulk? true` on such an action is reported when the resource is compiled.
- Every bulk action asks first, in the table's dialog, with the number of
  records: "Run “Archive” on 3 records?", or the action's own `confirm` and
  the number after it.
- An action with inputs opens the action panel once for the selection,
  headed by the action and the number. Its fields start empty; what they
  hold is given to the action on every record. An input of a field the
  person sees on some records only is no field of it.
- A bulk action runs through `Ash.bulk_update/4` or `Ash.bulk_destroy/4`,
  as the person and with authorization, on records that were read as the
  person through the table's read action: `strategy: :stream`,
  `batch_size: 1`, `transaction: :batch`, `return_errors?: true`,
  `stop_on_error?: false`, `return_records?: true`, `notify?: true`. One
  record and one transaction at a time, as the row's button does it: any
  update or destroy action can run so, a record that a policy, a validation
  or the database refuses does not take the others with it, and nobody
  changes in bulk what they could not change from its row or cannot read.
  In a nested table the records are read through the row it belongs to.
- Afterwards the table reads again and says how many records were done and
  how many were not, with each message of the action and the number of
  records it is about, above the grid and to screen readers. The rows the
  action did not run on stay selected. A record that is gone, or not the
  person's to read, counts as not done.
- The run is beside the page's process: the page stays in use, its rows are
  dimmed and the buttons of the line are `aria-disabled` until it is over.
- New messages in the Gettext template: "Select row", "Select all rows of
  this page", "Selected rows", "%{count} selected", "All %{count} that
  match are selected", "All that match are selected", "Select all %{count}
  that match", "Select all that match", "Clear selection", the questions
  ("Run “%{action}” on 1 record?" and its plural, "Run “%{action}” on all
  records that match?", "%{question} 1 record is selected." and its plural,
  "%{question} All records that match are selected."), the panel's headings
  ("%{action}: 1 record" and its plural, "%{action}: all records that
  match") and the result ("%{action}: %{done} done.", "%{action}: %{done}
  done, %{failed} not done.", "%{message} (%{count})").

### Table actions

- An `action` that names a public generic action is a table action: a
  button on the line of the table's name, after the create button, in the
  declared order. In a nested table the buttons are on the relationship
  line, after its create button, and in a full view on the line that names
  the parent. A table that could not read has none.
- An action that runs without arguments runs when its button is used,
  after its `confirm` question when it has one. One with a required
  argument without a default opens the action panel, with a field per
  public argument: the fields a row action's arguments have.
- It runs as the person, in their tenant and with authorization, through
  `AshPhoenix.Form.for_action/3` and `Ash.run_action/2`. A person who can
  never run it has no button (`Ash.can/3`, once per action and without
  arguments).
- Afterwards the table says one line above the grid, which is read out:
  the action and what it returned, when that is text, a number, a boolean,
  a date, a datetime or an atom (a value of an enum by its label), else
  that it is done. Then it reads again. Returned records are not shown.
- `record_argument` on an `action`: the argument of a generic action that
  is given the primary key of a row. The action is then a row action: its
  button is in every row, the argument is no field of its panel, and the
  record is read as the person before it runs. It is offered for the
  selected rows like any row action, runs once per record there, and
  `bulk? false` keeps it to one row.
- A failure is shown at the fields of the panel or above them, on the
  row's actions cell for a generic action in a row, and above the grid for
  a table action without a panel. An exception inside a generic action,
  which Ash raises, is logged and reads "This could not be done."
- A table whose only actions are generic is not held to the rules about the
  resource's primary read action: Ash loads nothing of a generic action's
  result through it.
- New message in the Gettext template: "%{action}: %{result}".
- Reported when the resource is compiled: a `record_argument` on an update
  or a destroy action, one that names no argument of the action, a private
  one, one that is not stored as the primary key is, one on a resource
  whose primary key is several attributes or none, `bulk? true` on a table
  action, and a generic action with a required argument the panel has no
  field for.

### Unions

- A union (`Ash.Type.Union`, also as a NewType) is a cell of its own
  (`cell_type: :union`), where it was read-only text as Elixir writes it.
  The cell shows the value the union holds, as a cell of that kind's type
  shows it: a number as a number, a boolean as its check mark, the label of
  an enum's value, an embedded resource or a map as its one line. Nothing
  says which kind it is. An array of unions (`{:array, :union}`) shows its
  values with `; ` between them, and a union inside an embedded resource or
  a map is shown after its field's label.
- A union is edited in the side panel, kind first: Enter, F2 or a double
  click on the cell opens the action panel with the union as a group, in it
  "Kind", a choice of the union's kinds by their names in words (through
  the host's Gettext, as the labels of an enum's values), and under it the
  value of the kind that is chosen: the one control of its type, or the
  fields of a kind made of fields. Choosing another kind puts that kind's
  fields in place of the others, empty; no kind is no value, where the
  attribute may be empty. "Save" runs the column's update action with the
  kind and its value as Ash takes a union from outside
  (`%{"_union_type" => …, "_union_value" => …}`), for tagged and untagged
  unions alike; the key a tagged union tells its kinds by is given by the
  table and is no field of the panel. A value that was typed for one kind
  is never given as the value of another.
- What the action says of the value of a kind is shown at that value's
  control, of a field of a kind made of fields at that field, and anything
  else about the union under its label.
- A union is editable when every kind has a control: text, a number, a
  boolean, a date, a datetime, a choice, a value written as one line of
  text, or an embedded resource or a map whose fields can all be given. A
  union with another kind (an array, a map without fields, a tuple) is
  read-only, and so is an array of unions; a column's own `update_action`
  on one is reported when the resource is compiled. An embedded resource
  among the kinds is given through its create action alone, which is what
  `Ash.Type.Union` runs.
- An embedded resource or a map with a union among its fields is no longer
  read-only for that: the union is a field of its group.
- In the action panel, of a row action, of a table action, of an action on
  the selected rows and of the create action, an input that is a union is
  the same group. An action that requires a union the panel has no field
  for is reported and has no button, as before.
- A union is neither sorted nor filtered by, as in `ash_json_api` and
  `ash_graphql`. A union column no longer offers a sort, which
  `Ash.Resource.Info.sortable?/3` alone would allow.
- New text: "Kind".
- A column's `component` shows the cells of a union column; its editor is
  not used for one. A component is told `cell_type: :union`, or
  `{:array, :union}`, where it was told `:other`.

### Files

- An argument of an action that takes a file (`Ash.Type.File`, also as a
  NewType) is a field of the action panel: the browser's file input, under
  the argument's label, for one file. It is there for a row action, a
  generic action in a row, a table action, the create action and an action
  on the selected rows. An action with such an argument always opens its
  panel. Before, an action that required a file was reported and had no
  button, and an optional file was left out.
- The field is an upload of LiveView's. The file is sent when the panel's
  button is used, and the action runs while LiveView holds it. The action
  is given a `Plug.Upload`, which Ash casts to an `Ash.Type.File` with the
  uploaded file's path, the name the browser gave (without any directory)
  and its content type. A file is never taken from what the form sent.
- A file is given once: after the panel's button is used the file input is
  empty again, whatever came of the action, and what the action said of
  the file stays at the field until another is chosen.
- `upload`, an entity of the `table` section, says what the upload of the
  arguments of one name takes: `accept`, a list of file name extensions and
  MIME types, and `max_file_size`, in bytes. Without one the upload takes
  any file of 8 MB at most, which are LiveView's own limits;
  `Ash.Type.File` has no constraints to say them with.
  `AshTable.Resource.Info.uploads/1` returns the declarations.
- A file the upload does not take is refused as it is chosen, at the field
  and in the live region, and "Run" then runs nothing. New texts: "The file
  is too large. The limit is %{limit}.", "This type of file is not
  accepted.", "The file could not be uploaded."
- On the selected rows every record is given the same file: the run has a
  copy of it, which is removed when the run is done.
- Reported when the resource is compiled: an `upload` that names no public
  file argument of an action the table offers, one whose `accept` is empty
  or lists what LiveView does not know. An action that requires several
  files (`{:array, :file}`) cannot be run from a table, and a file is no
  input of the argument line.

### Sensitive columns

- A column of a field the resource declares `sensitive?` (an attribute, a
  calculation or an aggregate) is masked: its cells show `••••••`, the same
  for every value, and a "Show" button named with the column. The value is
  not in the page and not in what the server keeps of a row. It is read
  again, as the person, when they ask for one cell (the button, or
  Shift+Enter), and hidden again when focus leaves the cell, with Escape,
  and on every new read. An empty cell stays empty. `sensitive?` is no
  access rule: whoever the field policies allow may ask.
- Such a column is neither sorted nor filtered by, has no component, and
  cannot be the `label_field`. It is edited where what is typed can be
  hidden, which is text and a number: the editor is a password input that
  starts empty, and an editor left empty saves nothing (a value is emptied
  with "Clear": see "Emptying a sensitive value" below). A sensitive column
  of another type is read-only.
- A sensitive input of an action is a password field in the action panel,
  starts empty, and left empty gives the action nothing. A sensitive
  argument has no input on the argument line, whose values are kept in the
  URL.
- A sensitive attribute of an embedded resource is a mask on the value's
  one line, and a value with such an input is not edited in a table.
- New compile-time findings for all of the above: see "Sensitive fields" in
  the guide to mistakes at compile time.

### Limits shown before saving

- A number input says what the resource's constraints say, before anything
  is saved: `min` and `max` of an integer, a float and a decimal, and
  `step` ("1" for an integer, "any" otherwise). On the editor of a cell, on
  a field of the action panel, on a number inside a map cell, an embedded
  resource or a union, on each value of an array of numbers, and on the
  argument line. The arrows stop at the limits, and assistive technology
  is told them. An argument's input has the argument's constraints, an attribute's
  the attribute's. Nothing is declared for it.
- The limits describe and never stop a save: a number past them is sent as
  typed, and Ash's message is shown at the cell or the field, as before.
  The forms of the action panel and of the argument line are `novalidate`.
  Only what the browser cannot read as a number or a date at all is held
  back, as before.
- The editor of a cell says `aria-required` where the column's update
  action cannot take the cell empty (`allow_nil?`, `require_attributes`),
  as a field of the action panel does. A component's editor is told the
  same in a cell (`@control`).
- Not put on an input, on purpose: the length of text (`max_length`,
  `min_length`: `maxlength` would stop the typing without a word, and
  counts differently from Ash; a text with a `max_length` has a counter
  instead, see below), `match`, the bounds `greater_than` and
  `less_than`, and how many values an array takes. See "Limits an editor
  shows before saving" in the guide to inline editing.

### The counter of a text

- A text whose type says the most it can be long (`max_length` of
  `:string` and `:ci_string`, also as a NewType) has a counter beside the
  control it is typed into: how long it is now and the most it can be,
  "12/30". It follows what is typed at every key, without the server. In
  the editor of a cell (under the cell, floating as the message of a failed
  cell does, so that neither the row nor the column moves), on each value
  of an array of text, on a field of the action panel (also inside a map
  cell, an embedded resource or a union) and on the argument line. Nothing is declared for it, and a text
  without `max_length` has none.
- It counts as Ash counts, in Elixir as the server renders it and in the
  browser as a person types: the text trimmed unless the type says
  `trim?: false`, a `:ci_string` folded by its `casing`, and what is left
  in the unit of `length_count` (codepoints, graphemes or bytes), else in
  the application's (`config :ash, :default_string_length_count`).
- It describes and never stops a save, as the limits of a number: there is
  still no `maxlength`. Past the most it says a number greater than the
  most ("34/30") in a heavier weight, and Ash's message is shown as before.
- The control names it as its description (`aria-describedby`); it is no
  live region. A sensitive text has none, nor has the editor of a column's
  `component`.

### An argument that refers to a record

- `reference`, an entity of `action` in the `table` section:
  `reference :to_id, MyApp.User` says which resource an argument's keys
  belong to, where nothing in Ash says it (an argument of a generic action,
  or one of an update or a destroy action that no `manage_relationship`
  change explains). The argument is then chosen in the picker, from the
  table of that resource, where it was a plain text field: one record for a
  key, any number for a list of keys. The chosen records are read again, as
  the person, before the action runs, and a key that names none they could
  have chosen runs nothing. For a table action, a generic action in a row
  (not its `record_argument`), an update and a destroy action, and a run on
  the selected rows. `AshTable.Resource.Info.actions/1` returns the
  declarations with their action (`references`,
  `AshTable.Resource.Reference`).
- Reported when the resource is compiled, and refused when the table is
  built: a `reference` that names no public argument of the action, an
  accepted attribute, the `record_argument`, a sensitive argument, an
  argument twice, or one a `manage_relationship` change hands to a
  relationship (the relationship says it); a resource without a table,
  without a public read action behind it, or with a primary key that is not
  one attribute; and an argument that is not stored as that key is, nor a
  list of it.
- Not for the table's `create_action`, which is an option and has no block.

### Emptying a sensitive value

- The editor of a sensitive cell has a button, "Clear", named with the
  column ("Clear Budget"), where the cell holds a value and the column's
  update action takes the attribute without one. It empties the cell at
  once, after the column's `confirm` question if it has one. Tab goes from
  the input to the button without saving.
- The field of a sensitive attribute in the panel of a row's update action
  has the same button, where the record has a value. Used, the field says
  "Will be cleared." and the button "Keep", which takes it back; the
  attribute is given without a value when the action runs.
- It is asked for by name: an event of its own for a cell, and what the
  panel keeps for a field. An empty editor and an empty field change
  nothing, as before, and nothing a form sends empties a value. The record
  is read again as the person, and what the action says is shown as for
  any save.
- Not offered by a create action, a destroy action, an action on the
  selected rows, or for an argument.
- New texts: "Clear", "Clear %{column}", "Keep", "Keep %{column}", "Will be
  cleared."

### Column widths

- A person can change how wide a column is. Every column's header ends in a
  handle: dragged with the pointer (built for mouse, pen and touch; tested
  with the mouse in Chromium), or moved from the
  keyboard once F2 on the header has put focus on it (Left and Right Arrow
  by 10 pixels, Home and End to the narrowest and the widest, Enter back to
  the width before, Escape back to the header). A double click on the handle
  goes back to the width before as well. A column is between 48 and 1000
  pixels wide. A click or a drag on the handle does not sort.
- The widths are not remembered. They are kept in the browser while the page
  is open, through every sort, filter, page, save and expanded row; a reload
  forgets them. Nothing is sent to the server, nothing is in the URL, and
  nothing is declared: there is no option for it.
- With the first change every column keeps the width it has, and the table
  is as wide as its columns from then on, so that only the dragged column
  moves. Text that does not fit a narrow column is cut off with an ellipsis,
  in the header too, and rows keep their height.
- Each table has its own widths: a nested table, the table of a picker, each
  of several tables on a page. The columns of the boxes, the expanders and
  the row actions have no handle.
- The handle is a `role="separator"` named "Resize %{column}" (a new message
  of the template), with the width in `aria-valuenow`. A column's header now
  has its label as `aria-label` too, so that its name stays the label alone.

### Hiding columns

- A person can hide columns and show them again. A "Columns" button above
  the grid, beside "Clear filters", opens a list of the table's columns with
  a box each. It is a disclosure (`aria-expanded`, `aria-controls`, a group
  of labelled checkboxes), closes with Escape, with a click elsewhere and
  when focus moves on, and is the same in a nested table and in a picker.
- Hiding is done in the browser and is not a permission: the column is still
  read and still in the page. Nothing is sent to the server, nothing is in
  the URL, nothing is stored, and nothing is declared. A reload shows every
  column again.
- Every column can be hidden but the label column (`label_field`). A table
  without one always keeps one column. The columns of the boxes, the
  expanders and the row actions are not in the list.
- A hidden column keeps its filter and its sort. The button says so
  ("Columns (2 hidden, 1 filtered)"), and so does the column's line in the
  list ("Progress (filtered)"). "Clear filters" clears it as well.
- The arrow keys, Home and End pass over hidden columns, and a hidden cell
  is never focused or the tab stop. `aria-colindex` and `aria-colcount`
  keep counting hidden columns, whose cells are not displayed. Hiding and
  showing a column is read out.
- Hidden columns stay hidden through every sort, filter, page, save and
  expanded row, and keep the width a person gave them.
- New messages of the template: "Columns", "Columns (%{details})",
  "%{count} hidden", "%{count} filtered", "%{count} sorted", "filtered",
  "sorted", "filtered, sorted", "%{column} hidden", "%{column} shown".

### Named tables

- A resource can have several tables. The `table` block stays its default
  table; the new `tables` section declares named tables beside it
  (`tables do table :compact do … end end`). A named table has every option
  and entity of the `table` block except `label_field`, which belongs to the
  resource, and takes nothing over from the default table. A resource has
  its default table with or without a `table` block, as before.
- `relationship` has a new option, `table`: which of the destination's
  tables is nested (`relationship :comments do table :compact end`). Without
  it the destination's default table is nested.
- `ash_table "/comments/compact", MyApp.Comment, table: :compact` mounts a
  named table, and `<AshTable.table resource={…} table={:compact} />` places
  one. A name the resource has no table for raises when the page is opened
  or the component rendered, with the resource's tables. `:default` names
  the default table wherever a table is named.
- The id of a named table defaults to the resource's, `_` and the table's
  name (`comment_compact`). The `id` of `<AshTable.table>` is no longer
  required: it defaults as the id of a mounted table does.
- "Open in full view" on a nested table leads to the mounted page of the
  same table, and is not there when that table is mounted nowhere. In the
  parameter `of`, a named table of the parent that offers the relationship
  is named with the resource: `comment_compact[of][task_board][comments]=KEY`.
- The picker shows the destination's default table.
- Every compile-time check runs for each table of a resource; a finding in
  a named table has the path `tables -> table -> NAME -> …`. New findings: a
  name that is no lower-case atom, the reserved name `:default`,
  `label_field` in a named table, a declaration made twice in a named
  table, and a `relationship` that names a table its destination does not
  have.
- `AshTable.Resource.Info.tables/1`, `table/2` and `table!/2` return the
  tables of a resource as `AshTable.Resource.Table`, in one shape for the
  default table and a named one.
- A table can be declared in a file of its own, as a Spark fragment of the
  resource. Every check holds for it, and a finding points at the
  fragment's file and line. See the guide "Named tables".

### Live updates

- `live? true` in a resource's `table` block makes its tables follow what
  other people change. The resource gets a notifier, `AshTable.Notifier`,
  which announces every create, update and destroy through the
  `Phoenix.PubSub` server that the domain's `table` block names with the new
  option `pub_sub`. An announcement holds the resource, the kind of action,
  the primary key and the tenant, and nothing of the record. A domain with
  such a resource and no `pub_sub` is an error when it is compiled.
- A table that hears a key reads the record again as the person, through
  its read action: a row of the page is updated in place, or goes when the
  read does not return it. A record that is no row of the page is not put
  in: the table says "There are new or changed records." with a "Read
  again" button, and only when at least one of them is a record that person
  would be shown.
- Nothing a person is working on changes under them. A cell that is being
  edited keeps what was typed. A row is left as it is while the action panel
  or the picker is open for it, or a panel or picker is open in a table
  nested under it, at any depth. A row whose record is gone stays while a
  cell of it is edited: the table asks the browser about that one row
  before it takes it away.
- `AshTable.Test.flush/1` hands a page what was announced so far, for a test
  that changes a record and then looks at the page.
- Nested tables and pickers follow their own resource. A named table says
  `live? false`, and a page or a placed table `live?: false`, not to
  follow.
- See the guide [Live updates](documentation/topics/live-updates.md).

### Changed since sensitive columns were added

- **The editor of a text column with a `max_length`, and of a sensitive
  column that can be emptied, is an element around its control**, which
  carries `data-control`, where it was the control itself. A host's test
  that looked for a `textarea` or an `input` in the cell finds it as
  before; one that took the editor's first element for the control does
  not.
- **A control with a counter names it in `aria-describedby`**, after its
  error message where it has one.
- **A generic action is now given no key that names a record the person
  could not have chosen**, for an argument with a `reference`.

- **The group of a map cell says "required" as the cell's update action
  says it** (`require_attributes` included), no longer as the attribute's
  `allow_nil?` alone does.
- **The argument line and the action panel are `novalidate` forms.** A
  host's test or script that counted on the browser's own check of a form
  finds none: only an input the browser cannot read is held back.

### Fixed

- A read that was on its way when the argument its read action requires was
  emptied is no longer stopped. Stopping it killed a process that could be
  in the middle of a statement, and its end was then shown as "The records
  could not be loaded." in place of "Fill in … to see records.". It is now
  left to finish, and what it brings is not shown.
- Two tables of one LiveView can each take a file for an argument of the
  same name: two placed tables, a table and its nested table, a picker.
  Before, the second file that was chosen crashed the LiveView ("existing
  upload for file-… already allowed in another component"), because every
  table allowed its upload under the argument's name alone. The name now
  holds the table's id: `ID-file-ARGUMENT`, which is also the `name` of the
  file input.

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
- `AshTable.Components.Image` shows the picture at the address a text
  column holds, at the height of a line: an `http://` or `https://`
  address, or a path that starts with `/`. Anything else is shown as text.
- Three more components are shipped: `AshTable.Components.Badge` shows an enum's
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

### Changed since arrays were added

- **Space on a cell selects its row**, in a table that has the boxes. It
  did nothing, and was held back for this.
- **The columns of a table with a row action stand one further.** The boxes
  are its first column, so `aria-colindex` of every other cell, and
  `aria-colcount`, are one more; the expander is the second cell of a row.
  A table without a row action that runs on several rows is as it was.
- **A table with a row action has the table's dialog in its markup**, also
  when nothing of it has a `confirm`: an action on the selected rows always
  asks.
- "Clear filters" is at the right end of the line above the grid as before;
  the line now also holds what is selected, at its left end.

### Changed since the argument line was added

- **An `action` that names a generic action is no longer reported.** It is
  a table action now.
- The message for an `action` that names a create or a read action reads
  "An `action` of a table is an update or a destroy action, which runs on
  the record of a row, or a generic action, which runs on the table as a
  whole."
- A table that is refused over an `action` says "its action `NAME` cannot
  be used", no longer "its row action".
- **A table with a table action that asks first has the table's dialog in
  its markup.**
- The create button of a relationship line is told apart from the buttons
  of table actions beside it by `data-create`; those have
  `data-table-action`.

### Changed since table actions were added

- **An action whose argument is handed to a relationship opens the action
  panel**, whether the argument is required or not, where the related
  records can be chosen. An action with nothing but a typed optional
  argument still runs when its button is used.
- **An argument of one key that an action hands to a relationship is no
  longer a typed key** where its records can be chosen: its field says what
  the record is called and opens the picker.
- **A list of keys that an action hands to a relationship has a field**,
  where its records can be chosen. Before, an action that required one was
  reported and had no button.
- A reference cell whose column names its own `update_action`, and whose
  foreign key is not public or not writable, is no longer reported where
  that action takes the related record through an argument.
- The message for a column's `update_action` that cannot save a reference
  cell reads "… does not accept `KEY`, the foreign key of `NAME`, and has
  no argument that a `manage_relationship` change hands to `NAME` …", and
  the one for `confirm` on such a cell ends "… or has an argument that a
  `manage_relationship` change hands to the relationship."
- The picker's "Choose" is rendered `aria-disabled="false"` where several
  records are chosen, and its dialog says `data-several`. The `picked`
  event carries `rows` there, in place of `row`.

### Changed since relationship editing was added

- **A union column is a cell type of its own.** `cell_type` is `:union`
  where it was `:other`, an array of unions `{:array, :union}`, and such a
  column is no longer sortable. A component on one is told so.
- **A union is editable under a table-level `update_action`** that accepts
  it, where every kind has a control. A table that should keep it
  read-only says `update_action false` on the column.
- **An embedded resource with a union in it is editable**, where it was
  read-only because of the union.
- **An action with a file argument has a button and a panel.** One that
  requires a file is no longer reported; one whose only input is an
  optional file opens the panel where it ran at once.
- The message for an action that requires an input without a field, and
  the one for a column's `update_action` on a type without an editor, name
  unions and files among what a table has a field for.

### Tooling

- `mix ash_table.install`, an Igniter installer (`mix igniter.install
  ash_table`): the hook in `app.js`, the Tailwind source in `app.css`, the
  formatter and the configuration.
- The DSL reference, generated by Spark.
