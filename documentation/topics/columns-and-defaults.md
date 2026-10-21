# Columns and defaults

Which columns a table has, how to declare your own, and how each type is
shown. Sorting, filtering and editing have their own guides:
[Reading, sorting and pagination](reading-sorting-and-pagination.md),
[Filtering](filtering.md) and [Inline editing](inline-editing.md).

## The smallest table

A resource that lists the extension has a table with columns, without any
`column` declared. `Demo.Tracker.Project` declares none
([`demo/lib/demo/tracker/project.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/project.ex)):

<!-- source: demo/lib/demo/tracker/project.ex -->
```elixir
# No `column`: the table shows the public attributes, and edits those its
# `update` action accepts. A project is called by its name where a table
# shows it as one value: in the "Project" column of /tasks.
table do
  update_action :update
  label_field :name
  # ...
end
```

(`# ...` marks lines left out: its row actions and create button, see
[Row actions and create](row-actions-and-create.md).)

None of it is about columns. `update_action` makes the table editable (see
[Inline editing](inline-editing.md)), and `label_field` is for other tables
(see [Reference cells](#reference-cells)). Without the block the table would
have the same columns and be read-only.

**Try it:** `/projects` in the demo, as Ada Admin: ID, Name, Description,
Status, Starts on, Budget, Client, Milestones, Inserted at.

## The default set

With no `column` in the block, the columns are the resource's public
attributes in the order of `Ash.Resource.Info.public_attributes/1`: as the
resource declares them, then the public foreign keys of its `belongs_to`
relationships. No special cases:

- The primary key is a column like any other; `id` is in the default set.
- A timestamp is a column only if public. `Project.inserted_at` is
  (`create_timestamp :inserted_at, public?: true`); `updated_at` is not.
- Calculations, aggregates and relationships are not attributes and not in
  the default set.

A block that sets options but declares no `column` keeps the default set.
All demo tables but two are of this kind:

| Demo page | Block | Columns |
| --- | --- | --- |
| `/projects` | `update_action :update`, `label_field :name`, two `action`s, `create_action` | ID, Name, Description, Status, Starts on, Budget, Client, Milestones, Inserted at |
| `/labels` | `update_action :update`, `label_field :name`, one `action`, `create_action` | ID, Name, Colour |
| `/comments` | `update_action :update`, `on_forbidden :message`, one `action`, `create_action` | ID, Body, Inserted at, Task ID, Author ID |
| `/task_labels` | `update_action :update`, `max_depth 1`, one `action`, `create_action` | Note, Task ID, Label ID |
| `/specimens` | `update_action :update` | ID, then one column per attribute of the kitchen-sink resource |

On `/comments` and `/task_labels` the foreign keys come last, even though a
task label's two foreign keys are its primary key.

An `action` adds no column here. A table with row actions has one more grid
column at the end, "Actions", for their buttons, as a table whose rows
expand has one at the start. Neither is a column in this guide's sense: it
shows no field and is not declared, sorted or filtered.

## Declaring columns

Once one `column` is declared, the table has exactly the declared columns,
in the declared order. `/tasks` is declared this way
([`demo/lib/demo/tracker/task.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/task.ex)):

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
# a boolean
column :billable?
# ...
# an expression calculation: sortable and filterable, never editable
column :overdue?

# an aggregate: sortable and filterable, never editable
column :comment_count do
  label "Comments"
end
```

`column` takes the name of a public attribute, calculation or aggregate of
the resource, or of a public belongs-to relationship, which makes a
[reference cell](#reference-cells). There is no "default set plus one": a
task's `id`, `project_id` and other public attributes are not shown because
the block does not name them.

A table's block is the same wherever that table is shown. A resource can
have more tables beside its default one: see [Named tables](named-tables.md).

## `label`

A column's heading is the field's name in words, unless `label` says
otherwise:

| Field | Default heading |
| --- | --- |
| `title` | Title |
| `estimate_hours` | Estimate hours |
| `billable?` | Billable? |
| `id` | ID |
| `task_id` | Task ID |

Underscores become spaces, the first word is capitalised, and `id` is
written "ID" wherever it stands. `label "Comments"` above replaces "Comment
count".

The label names the column everywhere the table speaks of it: the
accessible names of its filter ("Filter Comments") and editor, and the
prefix of an error about the field. A host can translate it; see
[Messages and translations](messages-and-translations.md).

## Calculations and aggregates

A calculation or aggregate is a column only when the block names it. It is
loaded with every read and never editable. `/tasks` has two calculations and
one aggregate as columns:

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
# An expression without arguments: sortable and filterable in the database.
calculate :overdue?,
          :boolean,
          expr(not is_nil(due_on) and due_on < today() and status in ^TaskStatus.open()),
          public?: true

# A module calculation, computed in Elixir.
calculate :headline, :string, Demo.Tracker.Calculations.Headline, public?: true
```

Both are shown by their type. The data layer can sort and filter by an
expression, but not by a value computed in Elixir: on `/tasks`, "Overdue?"
sorts and has a filter choice; "Headline" has neither.

An aggregate's type follows from its kind and the field it aggregates:
`comment_count` is a count, so the column is a number.

The read actions an aggregate reads through (also one held, by name or
written out, in a calculation's expression) must be `public?`, as must
every action a table runs; which ones they are is in
[Authorization](authorization.md#which-actions).

## Reference cells

A column naming a belongs-to relationship shows the related record's label
instead of its key. The last three columns of `/tasks`:

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
column :project do
  confirm "Move this task to another project?"
end

column :assignee

# No update action accepts `reporter_id`: read-only.
column :reporter do
  label "Reported by"
end
```

The label is the attribute the destination's `table` block names as
`label_field` (`Project`'s above; `label_field :name` on the demo's people).
The cell is not sorted or filtered by. Where the column's update action
accepts the foreign key, it is edited by choosing another record from the
destination's own table; see
[Choosing a related record](choosing-a-related-record.md). The related
record is read through the relationship's own `read_action`, else the
destination's primary read action, which must be `public?`. A person who
can never read the destination has no such column: on `/tasks`, Vera
Viewer has "Project" but neither of the other two.

How the label is read, and what the cell shows when the record or its label
is not the person's to see:
[Nested tables](nested-tables.md#the-reference-cell).

## Aggregates and calculations over protected fields

Per Ash's policies guide ("References to related data & fields"), **an
aggregate** applies the related resource's read policy (unreadable records
are not aggregated) but **not** its field policies: a sum of a hidden field
is the sum of the real values. **A calculation** applies no policy to what
it references: no related read policy, no field policy, related or its own.
So, for a resource's author:

> An aggregate whose `field`, or whose own `filter`, references a field that
> a field policy protects on the related resource must itself be protected,
> by a field policy **for the aggregate on the resource that declares it**.
> The same holds for a calculation and every protected field its expression
> references. A resource can only have field policies with
> `Ash.Policy.Authorizer` among its authorizers, and then needs a policy; one
> that authorizes everything will do if it has no others.

Otherwise everyone who can read a row reads those values; in a table, as a
column to look at, sort by and filter by.

The demo's people have such an aggregate, protected
([`demo/lib/demo/tracker/user.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/user.ex)).
It adds up the estimates of a person's tasks; a task's estimate is seen by
admins and the task's own assignee:

<!-- source: demo/lib/demo/tracker/user.ex -->
```elixir
aggregates do
  sum :assigned_hours, :assigned_tasks, :estimate_hours, public?: true
end
```

<!-- source: demo/lib/demo/tracker/user.ex -->
```elixir
field_policies do
  field_policy :assigned_hours do
    description "As the estimates it adds up: admins. (A task's own assignee sees its estimate too, which a sum cannot follow.)"
    authorize_if actor_attribute_equals(:role, :admin)
  end

  field_policy :* do
    authorize_if always()
  end
end
```

**Try it:** `/tasks`, expand a row and open "Assignee". As Ada Admin the
person's table has "Assigned hours"; as Max Member it has not. Without the
first `field_policy`, Max would read the sum of estimates he may not see one
by one.

### The warning

The table shows what Ash returns and cannot protect the column. It warns at
compile time when an aggregate **column**'s field or filter is protected on
the related resource, or a calculation column's expression references a
protected field (related or its own), and the declaring resource has no
field policy naming the column. For a sketch (the demo compiles without a
warning):

<!-- sketch -->
```text
warning: The aggregate column `payroll` shows `salary` of Sketch.Member, which a field policy protects there, and Sketch.Team has no field policy for `payroll`. Ash applies the read policy of the related resource to an aggregate, and not its field policies: everyone who can read a row sees this column, and can sort and filter by it. Protect it with a field policy for `payroll` on Sketch.Team, which needs `Ash.Policy.Authorizer` among its authorizers and, if the resource has no policies yet, one that authorizes everything. If the column is meant to show this to everyone who reads a row, say so with `exposes_protected_field? true` on the column.
```

A field policy that lets everybody see everything protects nothing, on
either side: `field_policy :* do authorize_if always() end` on the declaring
resource does not answer the warning, and a related resource whose only
field policy is that one has no protected field.

If the column is meant to show the value to everyone who reads a row, say so
on the column to silence the warning (a sketch):

<!-- sketch -->
```elixir
column :payroll do
  exposes_protected_field? true
end
```

The warning cannot see:

- **A calculation computed in Elixir.** What its module loads is not in its
  declaration; the rule holds for it all the same.
- **An aggregate or calculation that is not a column.** The rule is Ash's,
  for every interface; the table only checks its own columns.
- **`authorize?: false` on an aggregate**, which also drops the check of the
  related records.
- **The join resource of a many-to-many.** One investigation saw that its
  policy does not restrict an aggregate over the relationship; this was not
  verified independently. Do not rely on a join resource's policy for an
  aggregate column.

### What a table does not sort by

- **An aggregate column a field policy hides from the person on some
  records.** Ash raises for such a sort. Its filter stays: a hidden value
  counts as none, and nothing is told of the records it is hidden on.
- **A reference cell**, as above.

## What cannot be a column

| Field | Example in the demo | What happens |
| --- | --- | --- |
| A private attribute, calculation or aggregate | `Task.internal_note`, `Task.stale?` | Not in the default set. Named as a `column`, it is reported when the resource is compiled. |
| A calculation with a required argument that the column gives neither way | `Task.due_within?`, which needs `days`, named as a bare `column` | Reported when the resource is compiled. The column fixes the argument with `arguments`, or asks the person for it with `ask`: see [Arguments](arguments.md#the-arguments-of-a-calculation). |
| A relationship that is not a belongs-to | `Task.comments`, `Task.latest_comment` | Reported when the resource is compiled. Many records, or one of many, are a [nested table](nested-tables.md) under the row. |
| A belongs-to whose destination has no table, or no `label_field` | | Reported when the resource is compiled: there is nothing to call the related record by. |
| A belongs-to, an aggregate, or a calculation that holds an aggregate, that Ash reads through a private action | | Reported when the resource is compiled: a table runs no private action. |
| A name the resource does not have | | Reported when the resource is compiled. |

Only what the resource declares `public?` can appear, the rule
`ash_json_api` and `ash_graphql` follow too: adding the extension cannot
expose a field the resource's other interfaces keep back. The same holds
for actions, including those reached through a column; see
[Authorization](authorization.md#every-action-a-table-runs-is-public).

The demo's calculation with a required argument:

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
# A calculation with a required argument: a column of it has to say what
# the argument is, or ask for it.
calculate :due_within?,
          :boolean,
          expr(not is_nil(due_on) and due_on <= date_add(today(), ^arg(:days), :day)) do
  public? true

  argument :days, :integer do
    allow_nil? false
    constraints min: 0
  end
end
```

A calculation whose arguments are all optional or have defaults can be a
column as it is. One that needs an argument must give it. The demo shows
this one twice: with seven days fixed, and asking the person for the days
under a name of its own.

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
column :due_within? do
  label "Due within 7 days"
  arguments days: 7
end

column :due_within? do
  as :due_within
  ask :days, default: 30
end
```

[Arguments](arguments.md) has the rest; the exact messages are in
[Mistakes at compile time](mistakes-at-compile-time.md).

A declared column can still be missing for one person: a field a field
policy never lets them see has no column in their table. See
[Authorization](authorization.md).

## How each type is displayed

Every Ash type falls into one of nine cell types, which decide how a value
is shown and which filter and editor the column gets.

| Ash type | Cell type | Shown as |
| --- | --- | --- |
| `:string`, `:ci_string` | text | The text as it is, on one line, cut off at the column's maximum width unless the column says `max_lines` ([Long text](#long-text)). |
| `:integer`, `:float`, `:decimal` | number | The digits, without grouping. A decimal in full, never in exponent notation. |
| `:boolean` | boolean | ✓ or –, with "Yes" or "No" for screen readers. |
| `:date` | date | ISO 8601: `2026-10-06`. |
| `:datetime`, `:utc_datetime`, `:utc_datetime_usec`, `:naive_datetime` | datetime | To the second, without a zone: `2026-10-06T14:23:03`. UTC types in the page's time zone, UTC unless the page gives one ([Time zones](time-zones.md)). |
| A module that uses `Ash.Type.Enum`; `:atom` with the constraint `one_of`; `:duration_name` | enum | The value's label: the enum's `label/1`, else the value in words (`:in_progress` becomes "In progress"). |
| An embedded resource; `:map`, with or without the `fields` constraint | map | Its fields on one line as plain text, each by its name in words and shown as its type's cell shows it: `Name: Lumen, Key account?: No`. See [Maps and embedded resources](maps-and-embedded-resources.md). |
| `:union`, with its kinds as `types` | union | The value it holds, as its kind's cell shows it: `12` for a number, `Street: Unionsweg 5, City: Köln` for an embedded resource. Nothing says which kind. See [Unions](unions.md). |
| `{:array, type}` of one of the types above | array | The values as plain text, each as its type's cell shows it, separated by a comma and a space (`api, mobile`, `Reviewed, Tested`, `Yes, No`); a semicolon for arrays of embedded resources, maps or unions. |
| Everything else | other | Read-only text. |

Text, numbers, dates and datetimes use the format of the matching native
HTML input, so a cell shows what its editor will hold. Nothing is localized
in the first version.

`nil`, and an array without values, is an empty cell for every type. An
array cell is plain text: only the commas set its values apart.

`component` names a module that renders the cell another way. On `/tasks`,
"State" and "Priority" are badges, "Progress" a bar with its number,
"Estimate hours" has its unit. The cell type, and with it filter and
sorting, stays as above. See [Custom components](custom-components.md).

A NewType counts as the type it is made of: the demo's
`Demo.KitchenSink.Percentage`, a NewType of `:integer`, is a number column.

### Types shown as read-only text

"Everything else" is: keywords, tuples, structs, UUIDs, times, durations,
binaries, modules, ranges, terms, an `:atom` without `one_of`, and arrays of
these and of arrays. Such a column has no editor and no filter. Sorting is
still the resource's decision: a UUID column sorts.

Not among them, each with no sort and no filter:

- **Embedded resources and maps**, shown field by field and edited in the
  side panel where their fields are declared. See
  [Maps and embedded resources](maps-and-embedded-resources.md).
- **Unions**, shown as the value they hold and edited in the side panel,
  kind first, with a control per kind. See [Unions](unions.md).
- **Arrays of values that have a cell type**, shown as their values and
  editable in the side panel. See
  [Inline editing](inline-editing.md#arrays).

A file is no column at all: `Ash.Type.File` types an action's argument, and
Ash stores none. See [Files](files.md).

The text is the plainest form of the value: a string as it is, a number or
atom written out, a module without its `Elixir.` prefix, a list as its items
separated by commas, anything else as `inspect/1` prints it.

**Try it:** `/specimens` in the demo has one column per built-in Ash type,
no login needed.

## Column widths

A table lays out its columns itself: it fills its place, and each column
gets what its content asks for, up to `20rem`. Nothing in the `table` block
sets a width.

A person can change a width:

- **Drag the handle** at the end of the column's header, seen when the
  pointer is over it. Built for mouse, pen and finger; only the mouse has
  been tried.
- **Double-click the handle** to restore the column's previous width. The
  handle is pointer only: no Tab stop.
- **Type the width** in the list "Columns" opens: each column has a number
  field in pixels beside its box ("Width of Title"); the label column has
  one too, first. Up and Down Arrow, the field's own keys, change it as
  well. "Reset widths" at the end restores every first width. This is the
  way for the keyboard and for a pointer that does not drag; see
  [Keyboard and accessibility](keyboard-and-accessibility.md#column-widths-and-hiding-columns).

- **A column is 48 to 1000 pixels wide.** Text that does not fit is cut off
  with an ellipsis, in header and cells. Rows stay one line high, except for
  a cell showing its whole text or a failed save's message, or with
  `max_lines` (see [Long text](#long-text)).
- **The first change fixes every column** at its current width. From then
  on the table is as wide as its columns together, narrower than its place
  or wider (scrolling sideways). Only the dragged column changes. "The width
  it had before" counts from that moment.
- **Not remembered.** Widths live in the browser while the page is open,
  through sorting, filtering, paging, saving a cell and expanding a row. A
  reload or leaving the page forgets them; nothing goes to the server or the
  URL.
- **Per table**: a nested table, a picker's table, each of several tables on
  a page. A nested table closed and opened again starts over.
- **Only the table's own columns.** The columns of the selection boxes, the
  expanders and the row actions have no handle and no width field.
- **No option** switches this off or sets a starting width.

**Try it:** drag the edge of "Title" on `/tasks`, then sort by another
column.

## Long text

A cell shows one line and cuts off the rest with "…", keeping rows one line
high. Two things help with longer text.

**The whole text, in the row.** Every cell that cuts text off, read-only or
editable, in every table, has a small "Show all" button: a Tab stop named
after its column ("Show all of Title"). Click, Enter or Space on it, or
Shift+Enter on an editable cell, shows the whole text in place, the row
growing as needed; focus stays. The button then says "Show less"; it,
Shift+Enter again, or Escape on an editable cell cuts the text off again
(Escape then does nothing else, focus stays). Until then the text stays
whole when focus and pointer move on. There is no button on a cell that
shows all its text, a cell being edited (the editor holds the text), or a
cell whose save failed or is on its way.

**More lines in a column.** `max_lines` lets a column's cells show several
lines:

<!-- source: demo/lib/demo/tracker/comment/compact_table.ex -->
```elixir
      column :body do
        max_lines 3
      end
```

- **The text wraps** and is cut off with "…" after that many lines; a short
  text still takes one. The number is 1 to 10; 1 is the default.
- **The value's line breaks are kept**, as far as the lines go; an empty
  line counts as a line.
- **A row is as high as its highest cell**, so rows differ in height; the
  other cells stay one line, centred vertically. A table without the option
  keeps one-line rows.
- **A narrower column gives more lines**, up to the number, also when a
  person drags it narrower.
- **Which columns:** those shown as text: a string, an array, a map or
  embedded resource, a union, and a type shown as read-only text. On a
  number, date, datetime, boolean, enum, reference cell, sensitive column,
  or a column whose `component` shows the cell, it has no effect and the
  compiler says so: see
  [Mistakes at compile time](mistakes-at-compile-time.md#columns).
- **Editing is the same**: a text's editor opens in the cell and grows with
  its lines.
- **Each table says it for itself**: a nested table and a picker's table
  follow their own table's block.

About the whole text:

- **It is the cell's own text.** Nothing floats over the page; the server
  sends nothing for it.
- **A sensitive cell has none**, masked or shown; nor has a cell of a field
  the person may not see.
- **A screen reader reads the whole text** whatever the eye is shown. The
  button tells whether it shows whole (`aria-expanded`).
- **A live update of the row** brings the new text, still whole if it was.
- **A cut-off column header has none.**

**Try it:** on `/comments/compact`, Tab to the "Show all" of a comment
starting "Done on my side" and press Enter. Then do the same on `/comments`,
where the same comments are one line.

## Hiding columns

On the heading line above the table, after its name, a "Columns" button (an
eye struck through, the word, and while columns are hidden their count in a
badge) opens a list of the table's columns with a box each. A column whose
box is not ticked is hidden. A nested table has its own button on the line
that opens it.

**Hiding is not a permission.** A hidden column is still read from the
database and still in the page, and anybody can show it again. Keep things
from a person with a policy, a field policy or `sensitive?`: see
[Authorization](authorization.md) and
[Sensitive columns](sensitive-columns.md).

- **Every column can be hidden but the label column** (the resource's
  `label_field`), without which rows could not be told apart; it has no
  box. The selection boxes, expanders and row actions are not in the list.
- **A table without a label column** lets every column be hidden, but one
  always stays: the box of the last shown column cannot be used. That is
  when the block names no `label_field`, the label is not among the
  declared columns, or the person may not see it. A table with one column
  has no "Columns" button.
- **A hidden column keeps its filter and sort**, so the rows do not change.
  The filter, which lives in the header row, goes out of sight with it, so
  the button says it: "Columns (2 hidden, 1 filtered)", likewise "1 sorted".
  The list reads "Progress (filtered)" while it is hidden. "Clear filters"
  clears a hidden column's filter too.
- **Not remembered, and per table**, as widths are (see
  [Column widths](#column-widths)): a reload, leaving the page, or closing
  and reopening a nested table shows every column again.
- **A hidden column keeps a width a person gave it.** If the other columns
  got their widths while it was hidden, it takes the width it needs when
  shown.
- **What was open in the column:** an open editor is left as when focus
  leaves it, so what was typed is saved. A shown sensitive value is masked
  again. A cell whose save failed stays marked; its message is read out
  when it fails and shown again with the column.
- **The action panel, selecting rows and their actions are not affected.**
  The panel shows an action's fields whether or not their columns are shown.
- **No option** keeps a column from being hidden or starts with one hidden.

The list is the browser's own popover, opening under its button; without
CSS anchor positioning (Firefox today) in the middle of the window. It
closes with Escape, a click elsewhere, or focus moving on. The button's
count uses the plural forms of the person's language (see
[Messages and translations](messages-and-translations.md#counts-plural-forms)).
The keys are in
[Keyboard and accessibility](keyboard-and-accessibility.md#column-widths-and-hiding-columns).

**Try it:** on `/tasks`, filter "Progress", then hide it with "Columns".

## Keeping the label column in view

A table wider than its place scrolls sideways (see
[Scrolling sideways](layout-and-embedding.md#scrolling-sideways)), and the
column that says which record a row is scrolls away with the rest. With
`sticky_label? true` in the block it stays in view:

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
    # What a task is called where a table shows it as one value.
    label_field :title
```

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
    # The table has many columns and scrolls sideways: the title, by which
    # a task is told from another, stays in view meanwhile, with the cells
    # that select and expand its row.
    sticky_label? true
```

- **What stays:** the label column (the resource's `label_field`) with
  header, filter and cells, plus the selection box and expander where the
  table has them. Nothing else, and a person cannot choose.
- **Where:** at the left edge of the table's scroll area, after box and
  expander. Columns before it scroll away under it once it reaches the
  edge.
- **Off unless written**, per table: the `table` block for the default
  table, a [named table](named-tables.md) in its own block. A nested table
  and a picker's table follow their table's block. On `/tasks` the title
  stays; in the comments under a task nothing does.
- **It needs a label column.** `sticky_label? true` on a resource without
  `label_field`, or on a table whose declared columns leave the label out,
  is reported at compile time: see
  [Mistakes at compile time](mistakes-at-compile-time.md#sticky_label).
- **It does not stay where it would take more than half** of the visible
  table (a narrow window, or a column made very wide); then the table
  scrolls as a whole.
- **A person who does not see the label's field** (a field policy) has no
  label column, so nothing stays.
- **Widths and hiding** work as usual: the label column has its handle and
  can be resized; it cannot be hidden, with or without the option.
- **The cells that stay have the page's ground** (the theme's
  `--color-base-100`) so nothing shows through. A table on another ground
  says so with `--ash-data-table-ground`: see
  [Scrolling sideways](layout-and-embedding.md#scrolling-sideways). While
  something is under them, the last has a thin edge.
- **The header row does not stay at the top** when the page scrolls down;
  no option for that yet (see
  [Not in the first version](#not-in-the-first-version)).

**Try it:** on `/tasks`, Shift and the mouse wheel over the table, or drag
the scrollbar at the bottom of the window: "Title" stays. On `/labels`, in a
narrow window, nothing does.

## Edge cases

- **A public foreign key shows the raw key.** `Task ID` on `/comments` is
  the task's UUID, since that table shows the public attributes. A column
  naming the relationship shows the label: "Project" on `/tasks`.
- **Both can be columns of one table**: the key as attribute, the label as
  relationship. A person who may not read the related record then sees a
  key beside an empty cell.
- **A public `sensitive?` attribute is a column with masked cells.**
  `Project.budget` shows `••••••` until a person asks for a cell.
  Sensitivity is not about who may see the field; in the demo its field
  policy keeps it from a viewer. See [Sensitive columns](sensitive-columns.md).
- **A composite primary key** needs nothing special: on `/task_labels` each
  row is identified by both parts.
- **An enum value without a label** in its type shows in words. A value no
  longer among the type's values is shown as text.
- **Editors and width.** A text cell's editor grows with its lines; in a
  column with a person-set width, an editor is as wide as the column. See
  [Column widths](#column-widths) and [Long text](#long-text).

## Things people trip over

- **Declaring one column removes all defaults.**
- **A new public attribute appears in every default table.** Declare the
  columns of a table whose set should not change by itself.
- **A missing calculation or aggregate** has to be named and `public?`.
- **The heading is not the attribute's `description`**, but the name in
  words, or `label`.
- **A time or a UUID cannot be edited or filtered** in the first version.
  As an input of a row action or create they get a plain field: see
  [Row actions and create](row-actions-and-create.md#the-fields-of-the-panel).

## Not in the first version

No reference cell for a has-one, no label that is a calculation, no
locale-aware formatting, no column widths in the `table` block, no
remembering of the widths a person set or of the columns they hid, no option
to forbid hiding a column or to start with one hidden, no header row that
stays at the top of the window while the page scrolls down, and no choosing
which columns stay in view. A
column's own look and editor are built: see
[Custom components](custom-components.md). Later slices are listed in the
[specification](https://github.com/StefanRoesch/ash_data_table/issues/21).
