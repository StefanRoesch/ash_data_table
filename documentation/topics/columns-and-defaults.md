# Columns and defaults

After reading this guide you can say which columns a table has before you
open it, choose your own set and order, give a column another heading, add
calculations and aggregates, show a related record by its label, and tell how
a value of each Ash type will look in a cell. You also know what an
aggregate or a calculation column shows of a field that a field policy
protects, and what the compiler says about it.

Sorting, filtering and editing are each a guide of their own:
[Reading, sorting and pagination](reading-sorting-and-pagination.md),
[Filtering](filtering.md) and [Inline editing](inline-editing.md).

## The smallest table

A resource has a table as soon as it lists the extension, and that table
has columns without a `column` being declared. `Demo.Tracker.Project`
declares none
([`demo/lib/demo/tracker/project.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo/tracker/project.ex)):

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

(A line `# ...` stands for lines of the block that are left out here.)

No line of its block is about columns. `update_action` makes the table
editable (see [Inline editing](inline-editing.md)), and `label_field` is
about other tables (see [Reference cells](#reference-cells)). The lines left
out declare its row actions and its create button (see
[Row actions and create](row-actions-and-create.md)). Without the block the
table would have the same columns, and be read-only.

**Try it:** `/projects` in the demo, as Ada Admin. The columns are ID, Name,
Description, Status, Starts on, Budget, Client, Milestones and Inserted at.

## The default set

With no `column` in the block, the columns are the resource's public
attributes, in the order `Ash.Resource.Info.public_attributes/1` returns
them. That is the order in which the resource declares them, followed by the
public foreign-key attributes of its `belongs_to` relationships.

There are no special cases:

- The primary key is a column like any other. `id` is in the default set.
- A timestamp is a column only if it is public. `Project.inserted_at` is
  (`create_timestamp :inserted_at, public?: true`); `updated_at` is not.
- Calculations, aggregates and relationships are not attributes and are not
  in the default set.

A `table` block that sets options but declares no `column` keeps the default
set. All of the demo's tables but two are of this kind:

| Demo page | Block | Columns |
| --- | --- | --- |
| `/projects` | `update_action :update`, `label_field :name`, two `action`s, `create_action` | ID, Name, Description, Status, Starts on, Budget, Client, Milestones, Inserted at |
| `/labels` | `update_action :update`, `label_field :name`, one `action`, `create_action` | ID, Name, Colour |
| `/comments` | `update_action :update`, `on_forbidden :message`, one `action`, `create_action` | ID, Body, Inserted at, Task ID, Author ID |
| `/task_labels` | `update_action :update`, `max_depth 1`, one `action`, `create_action` | Note, Task ID, Label ID |
| `/specimens` | `update_action :update` | ID, then one column per attribute of the kitchen-sink resource |

On `/comments` and `/task_labels` the foreign keys come last, although a task
label's two foreign keys are its primary key.

An `action` adds no column to this list. The grid of a table with row
actions has one more column at its end, "Actions", which holds their
buttons, as the grid of a table whose rows expand has one more at its start.
Neither is a column in the sense of this guide: it shows no field, and is
not declared, sorted or filtered.

## Declaring columns

Once one `column` is declared, the table has exactly the declared columns in
the declared order. The table at `/tasks` is declared this way
([`demo/lib/demo/tracker/task.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo/tracker/task.ex)):

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
# a boolean
column :billable?
# a date and a datetime, both of which can be empty
column :due_on
column :completed_at
# an expression calculation: sortable and filterable, never editable
column :overdue?

# an aggregate: sortable and filterable, never editable
column :comment_count do
  label "Comments"
end
```

`column` takes the name of a field of the resource: a public attribute,
calculation or aggregate. It also takes the name of a public belongs-to
relationship, which makes the column a [reference cell](#reference-cells).
There is no way to say "the default set and one more". A task has an `id`, a `project_id` and other public attributes that
this table does not show, because the block does not name them.

A resource has one table. The block is the same wherever the table is shown.

## `label`

The heading of a column is the field's name in words, unless `label` says
otherwise:

| Field | Default heading |
| --- | --- |
| `title` | Title |
| `estimate_hours` | Estimate hours |
| `billable?` | Billable? |
| `id` | ID |
| `task_id` | Task ID |

Underscores become spaces, the first word is capitalised, and the word `id`
is written "ID" wherever it stands. `label "Comments"` in the excerpt above
replaces "Comment count".

The label is also the column's name in everything the table says about it:
the accessible names of its filter ("Filter Comments") and of its editor, and
the prefix of an error about that field. A host can translate it; see
[Messages and translations](messages-and-translations.md).

## Calculations and aggregates

A calculation or an aggregate is a column when the block names it, and only
then. It is loaded with every read and is never editable. The task table has
two calculations and one aggregate as columns. The resource defines them like
this:

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

Both are shown the same way, by their type. They differ in what the resource
can do with them: the data layer can sort and filter by an expression, and
can do neither with a value computed in Elixir. On `/tasks`, the heading of
"Overdue?" sorts and its filter cell has a choice; "Headline" has neither.

The type of an aggregate follows from its kind and from the field it
aggregates: `comment_count` is a count, so the column is a number.

An aggregate reads the related records through read actions of the
resources on its path: for each relationship its own `read_action`, else
the primary read action of its destination, and for the last one the
aggregate's own `read_action` in place of the primary one. Each has to be
`public?` for the aggregate to be a column, as every action a table runs has
to be. The same holds for a calculation whose expression holds an
aggregate, by name or written out. See
[Authorization](authorization.md#every-action-a-table-runs-is-public).

## Reference cells

A column that names a belongs-to relationship shows the related record's
label in place of its key. The last three columns of `/tasks` are of this
kind:

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

The label is the attribute that the destination's `table` block names as
`label_field`: `Project`'s block above, and `label_field :name` on the
demo's people. The cell is neither sorted nor filtered by. It is edited by
choosing another related record from the destination's own table, where the
column's update action accepts the relationship's foreign key; see
[Choosing a related record](choosing-a-related-record.md).
The related record is read through the relationship's own `read_action`,
else the destination's primary read action, and that action has to be
`public?`.
A person who can never read the destination has no such column: on `/tasks`,
Vera Viewer has "Project" and neither of the other two.

How the label is read, and what the cell shows when the related record or
its label is not the person's to see, is in
[Nested tables](nested-tables.md#the-reference-cell).

## Aggregates and calculations over protected fields

Ash has a rule about what an aggregate and a calculation are made from, in
its policies guide under "References to related data & fields":

- **An aggregate** applies the read policy of the related resource: records
  the person may not read are not aggregated. It does **not** apply the
  related resource's field policies. A sum of a field that a field policy
  hides is the sum of the real values.
- **A calculation** applies no policy at all to what it references: not the
  read policy of a related resource, and no field policy, of a related
  resource or of its own.

So the rule for a resource's author is:

> An aggregate whose `field`, or whose own `filter`, references a field that
> a field policy protects on the related resource must itself be protected,
> by a field policy **for the aggregate on the resource that declares it**.
> The same holds for a calculation and every protected field its expression
> references. A resource can only have field policies with
> `Ash.Policy.Authorizer` among its authorizers, and then needs a policy; one
> that authorizes everything will do if it has no others.

Otherwise everyone who can read a row reads those values. In a table that
means a column to look at, to sort by and to filter by.

The demo's people have such an aggregate, protected
([`demo/lib/demo/tracker/user.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo/tracker/user.ex)).
It adds up the estimates of a person's tasks, and a task's estimate is seen
by admins and by the task's own assignee:

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
person's table has the column "Assigned hours". As Max Member it has not.
Take the first `field_policy` away, and Max reads the sum of estimates he
may not see one by one.

### The warning

The table cannot protect the column, and does not try: it shows what Ash
returns. It warns when the resource is compiled. For an aggregate **column**
whose field or filter is protected on the related resource, and for a
calculation column whose expression references a protected field, on a
related resource or on its own, when the declaring resource has no field
policy that names the column, the compiler prints (here for a sketch, not
for the demo, which compiles without a warning):

<!-- sketch -->
```text
warning: The aggregate column `payroll` shows `salary` of Sketch.Member, which a field policy protects there, and Sketch.Team has no field policy for `payroll`. Ash applies the read policy of the related resource to an aggregate, and not its field policies: everyone who can read a row sees this column, and can sort and filter by it. Protect it with a field policy for `payroll` on Sketch.Team, which needs `Ash.Policy.Authorizer` among its authorizers and, if the resource has no policies yet, one that authorizes everything. If the column is meant to show this to everyone who reads a row, say so with `exposes_protected_field? true` on the column.
```

A field policy that lets everybody see everything protects nothing, on
either side: `field_policy :* do authorize_if always() end` on the declaring
resource does not answer the warning, and a related resource whose only
field policy is that one has no protected field.

When the column is meant to show the value to everyone who reads a row, say
so on the column, which silences the warning (a sketch):

<!-- sketch -->
```elixir
column :payroll do
  exposes_protected_field? true
end
```

What the warning cannot see:

- **A calculation computed in Elixir.** What its module loads and reads is
  not in its declaration. The rule holds for it all the same.
- **An aggregate or a calculation that is not a column.** The rule is Ash's
  and holds for every interface; the table only looks at its own columns.
- **`authorize?: false` on an aggregate**, which drops the check of the
  related records as well.
- **The join resource of a many-to-many.** One investigation saw that its
  policy does not restrict an aggregate over the relationship. This was not
  verified independently; do not rely on a join resource's policy for an
  aggregate column.

### What a table does not sort by

- **An aggregate column that a field policy hides from the person on some
  records is not sorted by.** Ash raises for such a sort. The filter of the
  column stays: there a hidden value counts as none, and nothing is told of
  the records it is hidden on.
- **A reference cell is not sorted by**, as said above.
- In a nested table there is one more case: see
  [Nested tables](nested-tables.md#aggregate-columns-in-a-nested-table).

### A `first` aggregate beside a calculation over the same relationship

A `first` aggregate over one related record (through a belongs-to, or a
has-one on a key of the destination) returns the value of a record the
person may **not** read when the same SQL statement joins that relationship
another way. This is a defect in the SQL layer, not Ash's rule (tracked as
#32). In a table the other join is an expression calculation column that
reaches through the same relationship, such as `expr(assignee.role)` beside
`first :assignee_name, :assignee, :name`.

The table keeps the two apart: it reads such an aggregate in a statement of
its own, and does not sort or filter by it. The compiler says so, and says
how to get both back:

<!-- sketch -->
```text
warning: The aggregate column `boss_name` is a `first` aggregate over the one record of `boss`, and the calculation column `boss_initial` reaches through the same relationship. Read together through a SQL data layer, such an aggregate returns the value of a related record that the reader may not read (ash_table issue #32). The table therefore reads `boss_name` apart from the rest of the row, and does not sort or filter by it. To have it read with the row again, and sorted and filtered by, take the aggregate out of the join the two share: give it a `join_filter` or a `read_action` of its own. To leave it at that, say `sortable? false` and `filterable? false` on the column.
```

The table sees its own columns only. A read action or a policy of the
resource that filters through the same relationship is another such join,
which no column shows; there the aggregate needs its `join_filter` or its
`read_action` whatever the table does. A reference cell is no such join: it
loads the relationship in a statement of its own.

The demo has no column of this kind. The library's tests have one, on
Postgres
([`demo/test/support/ledger_tables.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/test/support/ledger_tables.ex)):

<!-- source: demo/test/support/ledger_tables.ex -->
```elixir
# reaches through the relationship that the aggregate below is over
column :assignee_role

# read apart from the row for that, and neither sorted nor filtered by
column :assignee_name do
  sortable? false
  filterable? false
end
```

## What cannot be a column

| Field | Example in the demo | What happens |
| --- | --- | --- |
| A private attribute, calculation or aggregate | `Task.internal_note`, `Task.stale?` | Not in the default set. Named as a `column`, it is reported when the resource is compiled. |
| A calculation with a required argument that the column gives neither way | `Task.due_within?`, which needs `days`, named as a bare `column` | Reported when the resource is compiled. The column fixes the argument with `arguments`, or asks the person for it with `ask`: see [Arguments](arguments.md#the-arguments-of-a-calculation). |
| A relationship that is not a belongs-to | `Task.comments`, `Task.latest_comment` | Reported when the resource is compiled. Many records, or one of many, are a [nested table](nested-tables.md) under the row. |
| A belongs-to whose destination has no table, or no `label_field` | | Reported when the resource is compiled: there is nothing to call the related record by. |
| A belongs-to, an aggregate, or a calculation that holds an aggregate, that Ash reads through a private action | | Reported when the resource is compiled: a table runs no private action. |
| A name the resource does not have | | Reported when the resource is compiled. |

Only what the resource declares `public?` can appear. This is the same rule
`ash_json_api` and `ash_graphql` follow, and it means that adding the
extension to a resource cannot expose a field that its other interfaces keep
back. The same holds for actions: every action a table runs is `public?`,
the ones it reaches through a column among them. See
[Authorization](authorization.md#every-action-a-table-runs-is-public).

The calculation the demo has of this kind:

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
column as it is. One that needs an argument is a column that gives it: the
demo shows this one twice, once with seven days fixed and once asking the
person for the days, under a name of its own.

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

[Arguments](arguments.md) has the rest, and the exact messages are in
[Mistakes at compile time](mistakes-at-compile-time.md).

A column that the block declares can still be missing for one person: a field
that a field policy never lets them see has no column in their table. See
[Authorization](authorization.md).

## How each type is displayed

The table sorts every Ash type into one of nine cell types. The cell type
decides how a value is shown, which filter the column gets and which editor.

| Ash type | Cell type | Shown as |
| --- | --- | --- |
| `:string`, `:ci_string` | text | The text as it is, on one line. Long text is cut off at the column's maximum width. |
| `:integer`, `:float`, `:decimal` | number | The digits, without grouping. A decimal is written out in full, never in exponent notation. |
| `:boolean` | boolean | A mark, ✓ or –, with the text "Yes" or "No" for screen readers. |
| `:date` | date | ISO 8601: `2026-10-06`. |
| `:datetime`, `:utc_datetime`, `:utc_datetime_usec`, `:naive_datetime` | datetime | To the second, without a zone: `2026-10-06T14:23:03`. The UTC types are shown in UTC. |
| A module that uses `Ash.Type.Enum`; `:atom` with the constraint `one_of`; `:duration_name` | enum | The label of the value: what the enum's `label/1` returns, else the value in words (`:in_progress` becomes "In progress"). |
| An embedded resource; `:map`, with the `fields` constraint or without | map | Its fields on one line, as plain text: `Name: Lumen, Key account?: No`. Each field is called by its name in words and shown as a cell of its type shows it. See [Maps and embedded resources](maps-and-embedded-resources.md). |
| `:union`, with its kinds as `types` | union | The value it holds, as a cell of that kind's type shows it: `12` for a number, `Street: Unionsweg 5, City: Köln` for an embedded resource. Nothing says which kind it is. See [Unions](unions.md). |
| `{:array, type}` of one of the types above | array | The values as plain text, separated by a comma and a space, each as a cell of its type shows it: `api, mobile` for text, `Reviewed, Tested` for an enum, `Yes, No` for booleans. An array of embedded resources, maps or unions has a semicolon between its values. |
| Everything else | other | Read-only text. |

Text, numbers, dates and datetimes are shown in the format the matching
native HTML input uses, so a cell shows what its editor will hold. Nothing is
localized in the first version.

`nil` is an empty cell for every type, and so is an array without values.
An array cell is text and nothing else: its values are not set apart from
each other by anything but the commas.

A column can show its values another way: `component` names a module that
renders the cell. On `/tasks`, "State" and "Priority" are badges, "Progress"
is a bar with its number, and "Estimate hours" has its unit. The cell type
stays what the table above says, and with it the filter and the sorting.
See [Custom components](custom-components.md).

A NewType counts as the type it is made of. The demo's
`Demo.KitchenSink.Percentage`, a NewType of `:integer`, is a number column.

### Types shown as read-only text

"Everything else" is: keywords, tuples, structs, UUIDs, times,
durations, binaries, modules, ranges, terms, an `:atom` without `one_of`,
and the arrays of all of these and of arrays. A column of such a type has
no editor and no filter. Whether it can be sorted is still the resource's
decision: a UUID column sorts.

An embedded resource and a map are not among them: they are shown field by
field, and edited in the side panel where their fields are declared. See
[Maps and embedded resources](maps-and-embedded-resources.md). They have no
sort and no filter.

Nor is a union: it is shown as the value it holds, and edited in the side
panel, its kind first, where every kind has a control. See
[Unions](unions.md). It has no sort and no filter either.

A file is no column at all: `Ash.Type.File` is the type of an action's
argument, and Ash stores none. See [Files](files.md).

An array of values that do have a cell type is not among them: it is shown
as its values and can be edited, see
[Inline editing](inline-editing.md#arrays). It has no sort and no filter
either.

The text is the plainest form the value has: a string as it is, a number or
an atom written out, a module without its `Elixir.` prefix, a list as its
items separated by commas, and anything else as `inspect/1` prints it.

**Try it:** `/specimens` in the demo has one column per built-in Ash type.
No login is needed for that page.

## Column widths

A table lays its columns out by itself: it is as wide as the place it is in,
and each column gets what its content asks for, up to `20rem`. Nothing in the
`table` block sets a width.

The person using the table can change a width. Every column's header ends in
a handle, which is not seen until the pointer is over it or it has focus:

- **Drag the handle** to make the column narrower or wider. It is built for
  a mouse, a pen and a finger; only the mouse has been tried.
- **Double-click the handle** to give the column the width it had before.
- **From the keyboard:** F2 on the header moves focus to the handle. Left and
  Right Arrow change the width by 10 pixels, Home and End go to the narrowest
  and the widest, Enter gives the column its old width back, and Escape
  returns to the header. See
  [Keyboard and accessibility](keyboard-and-accessibility.md#column-widths-from-the-keyboard).

What to know about it:

- **A column is between 48 and 1000 pixels wide.** Text that does not fit is
  cut off with an ellipsis, in the header as in the cells. Rows stay one line
  high.
- **The first change fixes every column.** Each column keeps the width it has
  at that moment, and from then on the table is as wide as its columns
  together: narrower than its place, or wider, in which case it scrolls
  sideways as before. Only the column that is dragged changes. "The width it
  had before" is the width from that moment.
- **Widths are not remembered.** They live in the browser, for as long as the
  page is open. They stay through sorting, filtering, paging, saving a cell
  and expanding a row. A reload forgets them, and so does leaving the page.
  Nothing is sent to the server and nothing is put in the URL.
- **Each table has its own widths**: a nested table, the table in a picker,
  and each of several tables on one page. A nested table that is closed and
  opened again starts over.
- **Which columns:** the table's own columns. The columns of the boxes that
  select rows, of the expanders and of the row actions have no handle.
- **There is no option** to switch this off or to set a starting width.

**Try it:** drag the edge of "Title" on `/tasks` in the demo, then sort by
another column.

## Hiding columns

A person can take columns out of sight and bring them back. Above the table,
at the end of the line that also holds "Clear filters", is a button
"Columns". It opens a list of the table's columns with a box each. A column
whose box is not ticked is hidden.

Hiding is for the eye only. **It is not a permission.** A hidden column is
still read from the database and still in the page; anybody can show it
again. What a person must not see is kept away by a policy, a field policy
or `sensitive?`, as before: see [Authorization](authorization.md) and
[Sensitive columns](sensitive-columns.md).

What to know about it:

- **Which columns can be hidden:** every column of the table but the label
  column, the one of the resource's `label_field`. Without it a row could
  not be told from another, so it has no box. The columns of the boxes that
  select rows, of the expanders and of the row actions are not in the list.
- **A table without a label column** lets every column be hidden, but one
  always stays: the box of the last column that is shown cannot be used.
  That is the case when the `table` block names no `label_field`, when the
  label is not among the declared columns, or when this person may not see
  it. A table with one column has no "Columns" button.
- **A hidden column keeps its filter and its sort.** The rows do not change
  when a column is hidden. Because a filter lives in the header row, it goes
  out of sight with its column, so the button says it: "Columns (2 hidden,
  1 filtered)", and "1 sorted" likewise. In the list the column reads
  "Progress (filtered)" for as long as it is hidden. "Clear filters" clears
  the filter of a hidden column too.
- **Nothing is remembered.** What is hidden lives in the browser, for as
  long as the page is open. It stays through sorting, filtering, paging,
  saving a cell and expanding a row. A reload shows every column again, and
  so does leaving the page. Nothing is sent to the server and nothing is put
  in the URL.
- **Each table has its own list**: a nested table, the table in a picker,
  and each of several tables on one page. A nested table that is closed and
  opened again shows every column.
- **A hidden column keeps its width**, if a person gave it one. When the
  other columns got their widths while it was hidden, it takes the width it
  needs when it is shown.
- **What was open in the column:** an editor that is open in a cell of the
  column is left as when focus leaves it, so what was typed is saved. A
  sensitive value that was shown is masked again. A cell whose save failed
  stays marked; its message is read out when it fails and is shown again
  when the column is.
- **The action panel is not affected.** It shows the fields of an action,
  whether or not their columns are shown. So are selecting rows and the
  actions on them.
- **There is no option** to keep a column from being hidden, or to start
  with a column hidden.

The list closes with Escape, with a click anywhere else, and when focus
moves on. The keys are in
[Keyboard and accessibility](keyboard-and-accessibility.md#hiding-columns-from-the-keyboard).

**Try it:** on `/tasks` in the demo, filter "Progress", then hide it with
"Columns".

## Edge cases

- **A public foreign key shows the raw key.** `Task ID` on `/comments` is the
  UUID of the task, because that table shows the public attributes. A column
  that names the relationship shows the related record's label: "Project" on
  `/tasks`.
- **Both can be columns of one table**: the key, as the attribute, and the
  label, as the relationship. A person who may not read the related record
  then sees a key beside an empty cell.
- **A public `sensitive?` attribute is a column, and its cells are masked.**
  `Project.budget` is sensitive and public: its cells show `••••••` until a
  person asks for one. Sensitivity is not about who may see the field. What
  keeps the column from a viewer in the demo is its field policy. See
  [Sensitive columns](sensitive-columns.md).
- **A primary key of several attributes** needs nothing special. On
  `/task_labels` each row is identified by both parts of its key.
- **An enum whose type has no label for a value** shows the value in words.
  An enum value that is no longer one of the type's values is shown as text.
- **Width.** There is no width setting in the `table` block. Rows are one
  line high; a cell wider than `20rem` is cut off with an ellipsis, until a
  person makes the column wider: see [Column widths](#column-widths). The
  editor of a text cell is a field that grows with the lines of its text. In
  a column whose width a person set, an editor is as wide as the column.

## Things people trip over

- **Declaring one column removes all the defaults.** The block is either
  empty of columns or complete.
- **A new public attribute appears in every default table.** A table without
  declared columns follows the resource. Declare the columns of a table whose
  set should not change by itself.
- **A calculation or aggregate is missing.** It has to be named, and it has
  to be `public?`.
- **The heading is not the attribute's `description`.** It is the name in
  words, or `label`.
- **A time or a UUID cannot be edited or filtered.** Their types are shown
  as read-only text in the first version. As an input of a row action or of
  a create they do have a field, a plain one: see
  [Row actions and create](row-actions-and-create.md#the-fields-of-the-panel).

## Not in the first version

No reference cell for a has-one, no label that is a calculation, no choosing
another related record in a reference cell, no dedicated cells for maps and
embedded resources, no locale-aware formatting, no column widths in the
`table` block, no remembering of the widths a person set or of the columns they hid, no
option to forbid hiding a column or to start with one hidden,
and one table per resource. A column's own look and editor are built: see
[Custom components](custom-components.md). The
later slices are listed in the
[specification](https://github.com/StefanRoesch/ash_table/issues/21).
