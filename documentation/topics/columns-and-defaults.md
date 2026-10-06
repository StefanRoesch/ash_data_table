# Columns and defaults

After reading this guide you can say which columns a table has before you
open it, choose your own set and order, give a column another heading, add
calculations and aggregates, and tell how a value of each Ash type will look
in a cell.

Sorting, filtering and editing are each a guide of their own:
[Reading, sorting and pagination](reading-sorting-and-pagination.md),
[Filtering](filtering.md) and [Inline editing](inline-editing.md).

## The smallest table

A resource has a table as soon as it lists the extension. `Demo.Tracker.Project`
has no `table` block at all
([`demo/lib/demo/tracker/project.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo/tracker/project.ex)):

<!-- source: demo/lib/demo/tracker/project.ex -->
```elixir
# No `table` block: the table shows the public attributes.
extensions: [AshTable.Resource],
```

**Try it:** `/projects` in the demo, as Ada Admin. The columns are ID, Name,
Description, Status, Starts on, Budget and Inserted at.

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
set. The demo has three such tables:

| Demo page | Block | Columns |
| --- | --- | --- |
| `/comments` | `on_forbidden :message` | ID, Body, Inserted at, Task ID, Author ID |
| `/task_labels` | `update_action :update` | Note, Task ID, Label ID |
| `/specimens` | `update_action :update` | ID, then one column per attribute of the kitchen-sink resource |

On `/comments` and `/task_labels` the foreign keys come last, although a task
label's two foreign keys are its primary key.

## Declaring columns

Once one `column` is declared, the table has exactly the declared columns in
the declared order. The table at `/tasks` is declared this way
([`demo/lib/demo/tracker/task.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo/tracker/task.ex)):

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
column :estimate_hours
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
calculation or aggregate. There is no way to say "the default set and one
more". A task has an `id`, a `project_id` and other public attributes that
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

## What cannot be a column

| Field | Example in the demo | What happens |
| --- | --- | --- |
| A private attribute, calculation or aggregate | `Task.internal_note`, `Task.stale?` | Not in the default set. Named as a `column`, it is reported when the resource is compiled. |
| A calculation with a required argument that has no default | `Task.due_within?`, which needs `days` | Reported when the resource is compiled. A table has no place where a person could supply the argument. |
| A relationship | `Task.project` | Reported when the resource is compiled: a column shows an attribute, a calculation or an aggregate. |
| A name the resource does not have | | Reported when the resource is compiled. |

Only what the resource declares `public?` can appear. This is the same rule
`ash_json_api` and `ash_graphql` follow, and it means that adding the
extension to a resource cannot expose a field that its other interfaces keep
back.

The calculation the demo keeps for this case:

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
# A calculation with a required argument: it cannot be a column.
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
column. The exact messages are in
[Mistakes at compile time](mistakes-at-compile-time.md).

A column that the block declares can still be missing for one person: a field
that a field policy never lets them see has no column in their table. See
[Authorization](authorization.md).

## How each type is displayed

The table sorts every Ash type into one of seven cell types. The cell type
decides how a value is shown, which filter the column gets and which editor.

| Ash type | Cell type | Shown as |
| --- | --- | --- |
| `:string`, `:ci_string` | text | The text as it is, on one line. Long text is cut off at the column's maximum width. |
| `:integer`, `:float`, `:decimal` | number | The digits, without grouping. A decimal is written out in full, never in exponent notation. |
| `:boolean` | boolean | A mark, ✓ or –, with the text "Yes" or "No" for screen readers. |
| `:date` | date | ISO 8601: `2026-10-06`. |
| `:datetime`, `:utc_datetime`, `:utc_datetime_usec`, `:naive_datetime` | datetime | To the second, without a zone: `2026-10-06T14:23:03`. The UTC types are shown in UTC. |
| A module that uses `Ash.Type.Enum`; `:atom` with the constraint `one_of`; `:duration_name` | enum | The label of the value: what the enum's `label/1` returns, else the value in words (`:in_progress` becomes "In progress"). |
| Everything else | other | Read-only text. |

Text, numbers, dates and datetimes are shown in the format the matching
native HTML input uses, so a cell shows what its editor will hold. Nothing is
localized in the first version.

`nil` is an empty cell for every type.

A NewType counts as the type it is made of. The demo's
`Demo.KitchenSink.Percentage`, a NewType of `:integer`, is a number column.

### Types shown as read-only text

"Everything else" is: arrays of any type, maps, keywords, tuples, structs,
embedded resources, unions, UUIDs, times, durations, binaries, modules,
ranges, terms, and an `:atom` without `one_of`. A column of such a type has
no editor and no filter. Whether it can be sorted is still the resource's
decision: a UUID column sorts, an array or a map column does not.

The text is the plainest form the value has: a string as it is, a number or
an atom written out, a module without its `Elixir.` prefix, a list as its
items separated by commas, and anything else as `inspect/1` prints it.

**Try it:** `/specimens` in the demo has one column per built-in Ash type.
No login is needed for that page.

## Edge cases

- **A public foreign key shows the raw key.** `Task ID` on `/comments` is the
  UUID of the task. A cell that shows the related record's name is a later
  slice.
- **A public `sensitive?` attribute is a column like any other.**
  `Task.external_ref` is sensitive and public. Sensitivity is about logs and
  inspection, not about exposure. What keeps the column from most people in
  the demo is its field policy.
- **A primary key of several attributes** needs nothing special. On
  `/task_labels` each row is identified by both parts of its key.
- **An enum whose type has no label for a value** shows the value in words.
  An enum value that is no longer one of the type's values is shown as text.
- **Width.** There is no width setting. Rows are one line high; a cell wider
  than `20rem` is cut off with an ellipsis. The editor of a text cell is a
  field that grows with the lines of its text.

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
  as read-only text in the first version.

## Not in the first version

No reference cells for `belongs_to`, no nested tables, no custom cell
components, no dedicated cells for arrays, maps and embedded resources, no
locale-aware formatting, no column widths, and one table per resource. The
later slices are listed in the
[specification](https://github.com/StefanRoesch/ash_table/issues/21).
