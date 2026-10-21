# Table actions

A table action runs on the table as a whole, not on one record. On the
resource it is a generic action: it takes arguments, returns a value and is
given no record ("generic action" is the resource's word, "table action" the
table's). This guide also covers turning a generic action into a row action
(`record_argument`), a generic action that runs once on the selected rows
(`selection_argument`), a file an action returns, which the browser saves,
choosing a key argument in the picker (`reference`), and table actions in
nested tables.

Row actions, the action panel and its fields:
[Row actions and create](row-actions-and-create.md). The question an action
asks first: [Confirm](confirm.md). Who may act:
[Authorization](authorization.md).

## The smallest example

An `action` in the `table` block that names a generic action is a button on
the line of the table's name. The demo's labels have five; three are below.
"Merge" is under
[An argument that holds the key of a record](#an-argument-that-holds-the-key-of-a-record),
"Import" (a file) in [Files](files.md)
([`demo/lib/demo/tracker/label.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/label.ex)):

<!-- source: demo/lib/demo/tracker/label.ex -->
```elixir
# Table actions: generic actions, each a button on the line of the
# table's name, after "New label". This one takes no argument, so it
# runs when its button is used, and the table says the number it returns.
action :count_unused

# Two required arguments: the button opens the action panel.
action :recolour

# It returns nothing, and asks first.
action :remove_unused do
  confirm "Delete every label that no task carries?"
end
```

The first counts the labels no task carries:

<!-- source: demo/lib/demo/tracker/label.ex -->
```elixir
# Returns a number, which the table shows: "Count unused: 3".
action :count_unused, :integer do
  description "How many labels no task carries."

  run fn _input, context ->
    __MODULE__
    |> Ash.Query.filter(task_count == 0)
    |> Ash.count(Ash.Context.to_opts(context))
  end
end
```

**Try it:** `/labels` in the demo, as Ada Admin. On the line of the table's
name, at the right: "New label", "Count unused", "Recolour", "Remove
unused", "Merge", "Import". "Count unused" says "Count unused: 0" above the
grid (every seeded label is on a task). Make a label with "New label" and
count again: "Count unused: 1".

Table actions are opt-in, like row actions: the table never offers an action
just because the resource has it.

## Declaring table actions

There is no second entity. `action` names an action of the resource; its
kind decides what it is in the table:

| The `action` names | In the table |
| --- | --- |
| A public update or destroy action | A row action: a button in every row. See [Row actions and create](row-actions-and-create.md). |
| A public generic action | A table action: a button on the line of the table's name. |
| A public generic action, with `record_argument` | A row action. See [A generic action in a row](#a-generic-action-in-a-row). |
| A create action, a read action | Reported. |
| An action that is not `public?` | Reported, whatever its policies say: a table runs no private action. |

| Option | Default | Meaning |
| --- | --- | --- |
| `label` | The action's name in words: "Count unused" | What the button says. |
| `confirm` | none | A question asked before the action runs. |
| `record_argument` | none | The argument that is given the primary key of a row. With it the action is a row action. |
| `bulk?` | | For a row action only. `bulk? true` on a table action is reported. |

Inside an `action`, `reference` says which resource a key argument refers
to (see
[An argument that holds the key of a record](#an-argument-that-holds-the-key-of-a-record)),
and `page_argument` names an argument the page fills, which the panel does
not ask for (see
[Row actions and create](row-actions-and-create.md#arguments-the-page-fills)).

The buttons stand in declared order, after the create button if any. Like
"New label", they are ordinary buttons, Tab stops on the table's heading
line.

**Where the buttons are:**

| The table | The buttons |
| --- | --- |
| Mounted with `ash_data_table`, or embedded with `<AshDataTable.table>` | On the line of the table's name, at the right. A table without a name and without a create button has the line for them alone. |
| The full view of a nested table | On the line that names the parent and the relationship, before "Show all records". |
| A nested table | On its relationship line, at its far end, after the create button. See [Nested tables](#nested-tables). |
| The table in a picker | None. A picker is for choosing a record. |

A table that could not read has no buttons: none beside an error, none while
the argument line waits for a required argument.

## At once, after a question, or the action panel

The action decides what its button does:

| The action | Using its button |
| --- | --- |
| Has no argument, or only arguments it runs without: optional ones, and ones with a default | Runs the action. |
| The same, declared with `confirm` | Asks the question. Confirm runs the action; Cancel and Escape run nothing and put focus back on the button. |
| Has a required argument without a default (`allow_nil? false`) | Opens the action panel. |
| Has an argument that takes a file, required or not | Opens the action panel: see [Files](files.md). |

The panel is the row actions' panel: one field per public argument, in
declared order, with its type's control and its name in words as label. A
union argument has the choice of kind and that kind's value
([Unions](unions.md#in-the-action-panel)); a file argument has a file input
([Files](files.md)). The panel is headed by the button's text and ends in
"Cancel" and "Run". With `confirm`, the question is asked on "Run", on top
of the panel, or inside it where questions open in the page.

The demo's "Recolour" has two required arguments:

<!-- source: demo/lib/demo/tracker/label.ex -->
```elixir
# Returns how many labels it changed.
action :recolour, :integer do
  description "Gives every label of one colour another colour."
  transaction? true

  argument :from, :string do
    allow_nil? false
    constraints match: ~r/^#[0-9a-f]{6}$/
  end

  argument :to, :string do
    allow_nil? false
    constraints match: ~r/^#[0-9a-f]{6}$/
  end

  # ...
end
```

**Try it:** `/labels` as Ada Admin, "Recolour". The panel has "From \*" and
"To \*". Type `red` into "From" and "Run": the action's message is under the
field and nothing ran. Give a label's colour in "From" and `#123456` in
"To": the panel closes, the table says "Recolour: 1", and the label has the
new colour.

**Which arguments have a field** is as for a row action: text, numbers,
booleans, dates, datetimes, choices, arrays of those, values written as one
line of text (such as a key), and embedded resources and maps that declare
their fields. An optional argument without a field is left out; an action
that requires one cannot be run from a table, and the compiler reports it.

## An argument that holds the key of a record

An argument such as `argument :into, :uuid` holds a record's key, but Ash
does not say of which resource: a generic action accepts no attribute and
has no changes, so no relationship explains it. Without more, its field is
a plain text field where the key is typed.

`reference` in the `action` names the resource. The demo's labels have
"Merge"
([`demo/lib/demo/tracker/label.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/label.ex)):

<!-- source: demo/lib/demo/tracker/label.ex -->
```elixir
# Two arguments that hold keys of labels: one key, and a list of them.
# `reference` says that they are labels, so both are chosen in the
# picker, from this very table: one row for the first, any number of
# rows for the second.
action :merge do
  reference :into, __MODULE__
  reference :labels, __MODULE__
end
```

<!-- source: demo/lib/demo/tracker/label.ex -->
```elixir
action :merge, :integer do
  description "Puts one label in the place of others, and deletes those."
  transaction? true

  argument :into, :uuid, allow_nil?: false
  argument :labels, {:array, :uuid}, allow_nil?: false

  # ...
end
```

`reference :argument, Resource` takes the argument's name and the resource
its keys belong to. The field then works like a reference cell:

- **The key is not typed.** The field shows the chosen record's name; its
  "Choose" button opens the picker with that resource's table. See
  [Choosing a related record](choosing-a-related-record.md).
- **One key chooses one record.** "None" is offered where the argument can
  be empty.
- **A list of keys (`{:array, :uuid}`) chooses any number of records**, like
  an argument a `manage_relationship` change hands to a relationship. See
  [Relationships an action manages](managing-relationships.md).
- **The chosen records are read again before the action runs**, as the
  person, through the read action of the picker's table. A key naming no
  record they could have chosen runs nothing.
- **The action always opens the panel**, even where the argument can be
  empty: choosing is what the field is for.
- **The field's label is the argument's name in words.** `:assignee` reads
  better than `:assignee_id`.

It works for every `action` of the block: a table action, a generic action
in a row (for its other arguments, not the `record_argument`), an update or
destroy action, and a run on the selected rows. The demo's projects have a
generic action in every row that takes a person
([`demo/lib/demo/tracker/project.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/project.ex)):

<!-- source: demo/lib/demo/tracker/project.ex -->
```elixir
action :assign_open_tasks do
  record_argument :project_id
  reference :assignee, Demo.Tracker.User
end
```

The compiler reports these:

| The `reference` | |
| --- | --- |
| Names no argument of the action, or an attribute it accepts | Reported. The foreign key of a public belongs-to relationship is chosen in the picker without a declaration. |
| Names an argument that is not `public?` | Reported. |
| Names the action's `record_argument` | Reported: the table gives that one. |
| Names an argument that is `sensitive?` | Reported: a picker shows what is chosen. |
| Names an argument twice | Reported. |
| Names an argument that a `manage_relationship` change hands to a relationship | Reported: the relationship says which resource it is. Leave the `reference` out. |
| The resource has no table (it does not list `AshDataTable.Resource`) | Reported: the records are chosen from its table. |
| The resource's table has no public read action | Reported. |
| The resource's primary key is several attributes, or none | Reported: one argument holds one value. |
| The argument is not stored as that primary key is, nor a list of it | Reported. |

A `reference` is for an `action` only. The table's `create_action` and a
column's `update_action` are options with no block to put one in.

**Try it:** `/labels` as Ada Admin, "Merge". The panel has "Into \*" and
"Labels", each a "Choose" button without input. Choose one label for "Into"
and two others for "Labels", and "Run": the table says "Merge: 2", and the
two are gone. On `/projects` every row has "Assign open tasks", whose panel
asks for the "Assignee" from the table of people.

## What the table says afterwards

A generic action returns a value or nothing, never a row. The table says
one short line above the grid, reads it out, then reads its records again.

| The action returned | The table says |
| --- | --- |
| Text, a number, a date, a datetime | The action and the value: "Recolour: 2" |
| A boolean | "Yes" or "No" after the action |
| An atom | Its name. A value of an enum by its label: "Mood: High" |
| Nothing, `nil`, an empty text | "Remove unused: done" |
| A file, from an action that `returns Ash.Type.File` | The action and the file's name: "Export CSV: tasks.csv". The browser saves the file; see [A file the action returns](#a-file-the-action-returns). |
| Anything else: a record, a list, a map | The same, "done". Returned records are not shown as a table. |

The returned value decides, not the declared type: Ash does not cast what a
generic action returns. A file is the one exception: an action declared to
return `Ash.Type.File` has what it returns cast as Ash casts a file.

The line stays until the table's next action has run, a filter changes, or
the selection changes. The same line says what an action on the selected
rows came to.

**Reading again** reads the page as now asked for: same sort, filters and
page. A table action may have changed any record, so nothing of the old
page is kept: open rows close, marks of failed edits go.

**Try it:** `/labels` as Ada Admin. Make a label with "New label". Use
"Remove unused" and Confirm: "Remove unused: done", and the label is gone.

## A generic action in a row

Some generic actions are about one record: they take its key as an
argument. `record_argument` names that argument and makes the action a row
action. The demo's labels have one:

<!-- source: demo/lib/demo/tracker/label.ex -->
```elixir
# A generic action that takes the key of a label. `record_argument`
# names the argument, which makes it a row action: the table gives the
# row's key, and the panel asks for the rest, the new name. A name can
# be given to one label only, so `bulk? false` keeps the action off the
# line of the selected rows.
action :copy do
  record_argument :label_id
  bulk? false
end
```

<!-- source: demo/lib/demo/tracker/label.ex -->
```elixir
# Takes the key of a label and a name: a table gives the first from
# the row the action is used on (`record_argument` in the block above).
action :copy do
  description "Makes another label of the same colour."

  argument :label_id, :uuid, allow_nil?: false

  argument :name, :string do
    allow_nil? false
    constraints min_length: 1, max_length: 30
  end

  # ...
end
```

- **Its button is in the actions column**, among the other row actions, in
  declared order.
- **The named argument has no field.** The table gives it the row's primary
  key and takes nothing the browser sends for it.
- **The other arguments are asked for in the action panel**, headed by
  action and record: "Copy: bug". With no other required argument the
  action runs when its button is used.
- **The record is read first**, as the person, through the table's read
  action, as for every row action. A row that is gone or no longer theirs
  to read runs nothing: "This record is no longer available."
- **Afterwards the table says what the action returned and reads again**,
  as after a table action. A generic action returns no row to show.
- **A failure without a panel is shown on the row's actions cell**, as for
  any row action.

The compiler reports these:

| The argument | |
| --- | --- |
| Is no argument of the action | Reported. |
| Is not `public?` | Reported: a private argument is not given from the outside. |
| Is not stored as the primary key is: an `:integer` for a UUID key, an array | Reported. |
| The resource's primary key is several attributes, or none | Reported: one argument takes one value. |
| `record_argument` on an update or a destroy action | Reported: those are given their record. |

**On the selected rows.** Such an action is offered for a selection like any
row action, unless it says `bulk? false`. It asks first, with the number of
records, and asks for its inputs once. It runs once per selected record,
each read as the person first; the table says on how many it ran and on how
many it did not. What each run returned is not shown. See
[Selecting rows and bulk actions](selecting-rows-and-bulk-actions.md). An
action that is to run once on all of them takes their keys as a list:
[An action on the selection](#an-action-on-the-selection).

**Try it:** `/labels` as Ada Admin. Every row has "Destroy" and "Copy".
"Copy" opens a panel headed "Copy:" and the label's name, with one field,
"Name \*". Another label's name gives "has already been taken" under the
field. A new name gives "Copy: done", and the copy is a row where the sort
puts it.

## An action on the selection

Some generic actions are about a set of records: an export, a report, a
message to their owners. They take a list of keys. `selection_argument`
names that argument and makes the action an action on the selection. The
demo's tasks have one:

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
# An action on the selection: a generic action that runs once, given
# the keys of every selected task (`selection_argument`) and the
# table's sort (`sort_argument`). It returns a file, which the
# person's browser saves: `tasks.csv`. Its button is in the line above
# the grid, after the row actions that run on each selected task.
action :export_csv do
  label "Export CSV"
  selection_argument :ids
  sort_argument :sort
end
```

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
# The selected tasks as a CSV file, in the table's order: the table
# gives it their keys and its sort, and the browser saves the file it
# returns (`Demo.Tracker.Task.ExportCsv`, through ash_csv_interchange).
action :export_csv, Ash.Type.File do
  argument :ids, {:array, :uuid}, allow_nil?: false
  argument :sort, :string

  run Demo.Tracker.Task.ExportCsv
end
```

- **Its button is in the line above the grid** while rows are selected,
  among the actions on the selected rows, in declared order. No row and no
  heading has it.
- **It runs once**, given the keys of every selected record the person may
  read. Selected rows are read again as the person first; "all that match"
  is read when it runs, through the table's read action, with the person's
  filters, keys only. A key that names nothing the person may read is left
  out. With none left it does not run: "Export CSV failed: None of the
  selected records is available any more."
- **`sort_argument`** names a `:string` argument that is given the table's
  sort in the syntax of `Ash.Query.sort_input/2` (`"title"`, `"-due_on"`),
  or nil where the person chose none. A read the action runs over the keys
  can keep the table's order with it. A sort by a column whose calculation
  is given arguments cannot be written so, and is nil too.
- **It asks first only with a `confirm` of its own**, as a table action
  does; its other arguments are asked for in the action panel, once.
- **Afterwards the table says what it returned and reads again**, as after
  a table action. The rows stay selected.
- **The page is told `:action_ran`**, with `key` nil, and `selected` (the
  keys it was given) and `all?`.

The compiler reports these:

| The declaration | |
| --- | --- |
| The argument is no argument of the action, or not `public?` | Reported. |
| The argument is not a list of what the primary key is stored as (`{:array, :uuid}` for a UUID key) | Reported. |
| The resource's primary key is several attributes, or none | Reported. |
| `selection_argument` on an update or a destroy action, or beside `record_argument` or `bulk?` | Reported. |
| `sort_argument` without `selection_argument`, on no public argument, on a required one, or one that is not `:string` | Reported. |

**Try it:** `/tasks` as Ada Admin. Select two rows, open "More" in the line
above the grid and use "Export CSV": the browser saves `tasks.csv` with the
two tasks, and the line says "Export CSV: tasks.csv". Sort by "Title" and
export "all that match": the file has them in that order.

## A file the action returns

A generic action that `returns Ash.Type.File` has the file it returns saved
in the person's browser, wherever it runs: from a row, from the line of the
table's name, on the selection. It is Ash's own type, the other half of
[Files](files.md), where an `Ash.Type.File` argument is an upload.

- **The table casts what the action returned** as Ash casts a file
  (`Ash.Type.cast_input/3`: the file itself, a `Plug.Upload`, anything that
  implements `Ash.Type.File.Source`), opens it with `Ash.Type.File.open/2`,
  reads it whole and closes it.
- **It is named** by `Ash.Type.File.filename/1`, else after the action
  (`export_csv`), and **typed** by `Ash.Type.File.content_type/1`, else as
  `application/octet-stream`.
- **It is sent to the page at once**, as the push `ash_data_table:download`,
  its content in Base64, and is kept nowhere: not in the table, not in an
  assign. The library's own window listener has the browser save it, in
  every kit; nothing is to be set up.
- **The line above the grid names it**: "Export CSV: tasks.csv".
- **The page is told** `:action_ran` with the file as `result`, by its name
  and type (`%{filename: …, content_type: …}`), never its content.
- **An action that returns `nil`** saves nothing, and says "done".
- **A file that cannot be read**, or a value that is no file, is "This
  could not be done."; the reason is in the log.

The demo's export returns a CSV file held in memory: a struct that
implements `Ash.Type.File.Implementation` and `Ash.Type.File.Source`
(`Demo.CsvFile`), so nothing is written to disk.

## What running does

On the server:

1. **The action is looked up by name among those this table offers this
   person.** An event naming anything else runs nothing.
2. **The action runs** through `AshPhoenix.Form`: `for_action` builds an
   `Ash.ActionInput`, then `submit`, which is `Ash.run_action/2`. It runs as
   the person, in their tenant, with authorization, like everything a table
   runs. It is given the panel's field values by field name, and nothing
   else that was sent.
3. **The table says what it returned, and reads again.**

The page can hear that it ran (`:action_ran`) and stop it before it runs;
see [Events and commands](events-and-commands.md).

The table adds nothing of its own; what the action does inside is the
resource's. The demo's actions read and write as the person, with the
options Ash hands the action (`Ash.Context.to_opts/1`).

## When it fails

| What went wrong | Where it is shown | What it says |
| --- | --- | --- |
| The action rejects an argument | In the panel, at the field | The action's message |
| A required argument is empty | In the panel, at the field | "is required" |
| The action returned an error about no field | In the panel above the fields; without a panel, above the grid | The message |
| A policy refuses the action | The same | "You are not allowed to do this." |
| Anything that is not of the action's saying: an exception inside it | The same | "This could not be done." The error is in the log. |

Without a panel the line above the grid reads "Count unused failed:" and
the message. A failure is read out too. Nothing is read again after a
failure.

## Who may run what

Each time it reads, the table asks Ash, without a query, which actions the
person can **never** run (`Ash.can/3`, once per action):

- A table action the person can never run has no button for them.
- A generic row action they can never run has no button in any row.
- Ash is asked without arguments. A generic action's policy has no record,
  so it can look only at the actor and the arguments, and before a button
  is used there are none.
- A check on an argument (the row's key included) answers when the action
  runs; a refusal then shows like any failure. For the button to be
  offered, such a check must say yes while the argument is absent.

The demo's labels:

<!-- source: demo/lib/demo/tracker/label.ex -->
```elixir
# A generic action takes no record, so its policy can look at the actor
# and at nothing of a label. Counting is for everyone of an
# organization; what changes labels is for admins, as above.
policy action(:count_unused) do
  authorize_if actor_present()
end

policy action([:recolour, :remove_unused, :copy, :import, :merge]) do
  authorize_if actor_attribute_equals(:role, :admin)
end
```

| Actor on `/labels` | On the line of the table's name | In the rows |
| --- | --- | --- |
| Ada Admin | "New label", "Count unused", "Recolour", "Remove unused", "Merge", "Import" | "Destroy", "Copy" |
| Max Member, Vera Viewer | "Count unused" | No actions column. |
| Olga Outsider | As her role in Globex says, and every action counts and changes Globex's labels alone. | |
| Nobody | Nothing. | |

Only `public?` actions run, as everywhere in a table. See
[Authorization](authorization.md#every-action-a-table-runs-is-public).

A table whose only actions are generic changes no record through an update,
destroy or create, so the rules about the resource's primary read action do
not apply to it.

## Nested tables

A nested table is the destination resource's table, so it has that table's
table actions. It has no line of its own name: its heading line is the
relationship line of the table around it. The buttons are there, at its far
end after any create button, once the nested table has read. They look like
the create button.

- A button acts on the nested table: panel, question and what it says
  afterwards are the nested table's; the table around it says nothing.
- **A table action in a nested table is not given the row it is under.**
  It is the same action with the same arguments as on the table's own page:
  "Count unused" under a task counts the organization's unused labels, not
  the task's. Nothing in Ash says which argument of a generic action would
  take a parent.
- It runs as the person, in the tenant the nested table reads in.
- The nested table reads again afterwards; the table around it does not.

**Try it:** `/tasks` as Ada Admin. Expand a row and open "Labels". At the
far end of the line: "Count unused", "Recolour", "Remove unused", "Merge",
"Import".

## The keyboard

The buttons on the line of the table's name are ordinary buttons: Tab
reaches them before the grid; Enter and Space use them.

| After | Focus is |
| --- | --- |
| An action that ran at once | Still on its button. |
| A question answered with Cancel or Escape | Back on the button. |
| A question answered with Confirm | On the button. |
| The panel closed, by "Run", Cancel or Escape | Back on the button that opened it. |

The buttons on a relationship line are Tab stops after the line's button
and its create button.

A generic action in a row is a button of the actions cell, a Tab stop like
the others. After it ran and the table read again, focus is on it again.

What the table says afterwards is in a live region (`role="status"`), read
out when it changes. All keys of a table are in
[Keyboard and accessibility](keyboard-and-accessibility.md).

## Edge cases

- **A long action holds the page.** A table action runs in the LiveView's
  process, as a row action does; until it returns, the page answers
  nothing else.
- **An action with only optional arguments runs with their defaults.** The
  panel opens only for an argument the action does not run without, as for
  a row action. Give an argument `allow_nil? false` to have it asked for.
- **A generic action under a policy that looks at a record cannot run at
  all.** Ash raises for such a check on a generic action; the table takes
  that as "never" and has no button.
- **A question on an action is asked in the browser.** A `table_run` event
  sent to the LiveView by other means is asked nothing, in controlled mode
  too. What must not happen belongs in the action's policy or the page's
  `before_action` (see [Events and commands](events-and-commands.md)).
- **A new read closes the panel**, as for a row.
- **A table with `on_forbidden :message` that was refused** has no buttons:
  a table that did not read offers nothing.
- **Returned text is shown as is**, however long. Return a short line.
- **A file travels through the LiveView's connection**, whole and in Base64,
  a third larger than it is. A file of many megabytes is better served by a
  controller the action links to.
- **An action on the selection with "all that match" is given every key**,
  in one list: as many as the filters match.

## Things people trip over

- **No button for an action.** The person can never run it, or it has a
  required argument without a field (the compiler reported it), or the
  table has not read.
- **A button that runs at once where a panel was expected.** Every argument
  of the action is optional or has a default.
- **Expecting the returned records in a table.** The table says "done" and
  reads its own records again.
- **Expecting a table action under a row to know that row.** It does not.
- **Expecting a generic action's button to be missing on the rows it
  refuses.** It is on every row; the action answers when it runs.
- **`record_argument` on an update action.** It is for generic actions; an
  update action is given its record.
- **A key argument that is a plain text field.** Nothing says which
  resource it refers to. Say it with `reference` in the `action`.
- **A check on an argument that hides the button from everybody.** It is
  asked without the argument first.
- **Expecting the keys of an action on the selection in the table's order.**
  They come in no order; `sort_argument` gives the sort to apply.
- **An action on the selection that runs once per record.** That is a row
  action with `record_argument`; `selection_argument` runs once on all.

## Not in the first version

No `reference` for an argument of the table's `create_action`, no own label
for an argument's field, no way to give a table action in a nested table
the row it is under, no table of returned records, no file streamed to the
browser in parts (a returned file is sent whole), no progress while an
action runs and no way to stop one, no result per record after a run on the
selected rows, and no icons on the buttons. The later slices are listed in the
[specification](https://github.com/StefanRoesch/ash_data_table/issues/21).
