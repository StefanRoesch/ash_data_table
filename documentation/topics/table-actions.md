# Table actions

A table action is an action of the resource, declared for a table, that a
person runs on the table as a whole and not on one record. On the resource
it is a generic action: one that takes arguments and returns a value, and is
given no record. After reading this guide you can declare a table action,
predict whether its button runs it at once, asks first or opens the action
panel, say what the table tells a person afterwards, turn a generic action
into a row action with `record_argument`, have a key argument chosen in the
picker with `reference`, and say what a table action in a nested table does
and does not know.

The actions of a row, the action panel and its fields are in
[Row actions and create](row-actions-and-create.md). The question an action
can ask first is in [Confirm](confirm.md). What depends on who is acting is
summed up here and explained in [Authorization](authorization.md).

A note on words: "generic action" is what the action is on the resource.
"Table action" is what it is in a table.

## The smallest example

An `action` in the `table` block that names a generic action is a button on
the line of the table's name. The demo's labels have five, of which these
are three. "Merge" is under
[An argument that holds the key of a record](#an-argument-that-holds-the-key-of-a-record),
and "Import" takes a file and is in [Files](files.md)
([`demo/lib/demo/tracker/label.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo/tracker/label.ex)):

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

The first of them counts the labels that no task carries:

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
name, at the right, are "New label", "Count unused", "Recolour", "Remove
unused", "Merge" and "Import". Use "Count unused": above the grid the table says "Count unused:
0", as every label of the seed is on some task. Make a label with "New
label" and count again: "Count unused: 1".

Table actions are opt-in, as row actions are. The table never offers an
action because the resource happens to have it.

## Declaring table actions

There is no second entity. `action` names an action of the resource, and
what the action is there says what it is in the table:

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
to: see
[An argument that holds the key of a record](#an-argument-that-holds-the-key-of-a-record).

The buttons stand in the declared order, after the create button where the
table has one. They are the same buttons as "New label": ordinary buttons of
the page, in its tab order before the grid.

**Where the buttons are.**

| The table | The buttons |
| --- | --- |
| Mounted with `ash_data_table`, or embedded with `<AshDataTable.table>` | On the line of the table's name, at the right. A table without a name and without a create button has the line for them alone. |
| The full view of a nested table | On the line that names the parent and the relationship, before "Show all records". |
| A nested table | On its relationship line, after the label and the create button. See [Nested tables](#nested-tables). |
| The table in a picker | None. A picker is for choosing a record. |

A table that could not read has none: no buttons beside an error, and none
while the argument line still waits for a required argument.

## At once, after a question, or the action panel

Using a button does one of three things, and the action decides which:
it runs the action, asks first, or opens the action panel.

| The action | Using its button |
| --- | --- |
| Has no argument, or only arguments it runs without: optional ones, and ones with a default | Runs the action. |
| The same, declared with `confirm` | Asks the question in the table's dialog. Confirm runs the action; Cancel and Escape run nothing and put focus back on the button. |
| Has a required argument without a default (`allow_nil? false`) | Opens the action panel. |
| Has an argument that takes a file, required or not | Opens the action panel: see [Files](files.md). |

The panel is the one of a row action: one field per public argument, in the
order they are declared, each with the control of its type and its name in
words as its label. An argument that is a union has the choice of its kind
and that kind's value ([Unions](unions.md#in-the-action-panel)), and one
that takes a file a file input ([Files](files.md)). It is headed by what the button says and ends in
"Cancel" and "Run". An action with `confirm` asks its question when "Run"
is used, on top of the panel.

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
"To \*". Type `red` into "From" and use "Run": the action's message is under
the field, and nothing has run. Give the colour of a label in "From" and
`#123456` in "To": the panel closes, the table says "Recolour: 1", and the
label has the new colour.

**Which arguments have a field** is the same as for a row action: text,
numbers, booleans, dates, datetimes, choices, arrays of those, values
written as one line of text, such as a key, and embedded resources and maps
that declare their fields. An optional argument without a field is left out.
An action that requires one cannot be run from a table, and the compiler
reports it.

## An argument that holds the key of a record

An argument such as `argument :into, :uuid` holds the key of a record. Ash
does not say of which resource: a generic action accepts no attribute and
has no changes, so no relationship explains the argument. Without more, its
field is a plain text field, and the key is typed.

`reference` in the `action` says which resource it is. The demo's labels
have "Merge"
([`demo/lib/demo/tracker/label.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo/tracker/label.ex)):

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
its keys belong to. The field is then the one of a reference cell:

- **The key is not typed.** The field says what the chosen record is
  called, and its "Choose" button opens the picker, with the table of that
  resource. See [Choosing a related record](choosing-a-related-record.md).
- **One key chooses one record.** "None" is offered where the argument can
  be empty.
- **A list of keys (`{:array, :uuid}`) chooses any number of records**, as
  an argument that a `manage_relationship` change hands to a relationship
  does. See [Relationships an action manages](managing-relationships.md).
- **The chosen records are read again before the action runs**, as the
  person and through the read action of the picker's table. A key that
  names no record they could have chosen runs nothing.
- **An action with such an argument opens the action panel**, also where
  the argument can be empty: choosing is what the field is for.
- **The field is called by the argument's name in words.** Name the
  argument for what it is: `:assignee` reads better than `:assignee_id`.

It works for every `action` of the block: a table action, a generic action
in a row (for its other arguments, not for the `record_argument`), an
update action and a destroy action, and for a run on the selected rows.
The demo's projects have a generic action in every row that takes a person
([`demo/lib/demo/tracker/project.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo/tracker/project.ex)):

<!-- source: demo/lib/demo/tracker/project.ex -->
```elixir
action :assign_open_tasks do
  record_argument :project_id
  reference :assignee, Demo.Tracker.User
end
```

What the declaration has to be, or it is reported:

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

A `reference` is for an `action`. The table's `create_action` and a column's
`update_action` are named by an option and have no block to put one in.

**Try it:** `/labels` as Ada Admin, "Merge". The panel has "Into \*" and
"Labels", each with a "Choose" button and no input. Choose one label for
"Into" and two others for "Labels", and use "Run": the table says "Merge:
2", and the two are gone. Then `/projects`: every row has "Assign open
tasks", whose panel asks for the "Assignee" and opens the table of the
people.

## What the table says afterwards

A generic action returns a value, or nothing. It returns no row, so there
is no row to show the result on. The table says one short line above the
grid, reads it out, and then reads its records again.

| The action returned | The table says |
| --- | --- |
| Text, a number, a date, a datetime | The action and the value: "Recolour: 2" |
| A boolean | "Yes" or "No" after the action |
| An atom | Its name. A value of an enum by its label: "Mood: High" |
| Nothing, `nil`, an empty text | "Remove unused: done" |
| Anything else: a record, a list, a map | The same, "done". Returned records are not shown as a table. |

The value is looked at, not the type the action declares. Ash does not cast
what a generic action returns.

The line stays until the next action of that table has run, a filter
changes, or the selection changes. It is the line that says what an action
on the selected rows came to.

**Reading again** is one read of the page as it is asked for now: the same
sort, filters and page. A table action may have changed any record, so
nothing of the old page is kept: open rows close, and marks of failed edits
go.

**Try it:** `/labels` as Ada Admin. Make a label with "New label". Use
"Remove unused" and Confirm: "Remove unused: done", and the label is gone.

## A generic action in a row

Some generic actions are about one record all the same: they take its key
as an argument. `record_argument` names that argument, and the action is
then a row action. The demo's labels have one:

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
  the declared order.
- **The named argument is no field.** The table gives it the primary key of
  the row, and takes nothing the browser sends for it.
- **The other arguments are asked for in the action panel**, which is
  headed by the action and the record: "Copy: bug". With no other required
  argument the action runs when its button is used.
- **The record is read first**, as the person and through the table's read
  action, as for every row action. A row that is gone, or no longer theirs
  to read, runs nothing: "This record is no longer available."
- **Afterwards the table says what the action returned and reads again**,
  as after a table action. The row is not shown from the action's result:
  a generic action returns no row.
- **A failure without a panel is shown on the row's actions cell**, as for
  any row action.

What the argument has to be:

| The argument | |
| --- | --- |
| Is no argument of the action | Reported. |
| Is not `public?` | Reported: a private argument is not given from the outside. |
| Is not stored as the primary key is: an `:integer` for a UUID key, an array | Reported. |
| The resource's primary key is several attributes, or none | Reported: one argument takes one value. |
| `record_argument` on an update or a destroy action | Reported: those are given their record. |

**On the selected rows.** Such an action is offered for a selection like
every other row action, unless it says `bulk? false`. It asks first, with
the number of records, and asks for its inputs once. It then runs once per
selected record, each read as the person first, and the table says on how
many records it ran and on how many it did not. What each run returned is
not shown. See
[Selecting rows and bulk actions](selecting-rows-and-bulk-actions.md).

**Try it:** `/labels` as Ada Admin. Every row has "Destroy" and "Copy".
Use "Copy": the panel is headed "Copy:" and the label's name, and has one
field, "Name \*". Type the name of another label: "has already been taken"
under the field. Type a new name: "Copy: done", and the copy is a row of
the table, where the sort puts it.

## What running does

On the server, a table action is these steps:

1. **The action is looked up among the ones this table offers this
   person**, by its name. An event that names anything else runs nothing.
2. **The action runs** through `AshPhoenix.Form`: `for_action`, which builds
   an `Ash.ActionInput`, then `submit`, which is `Ash.run_action/2`. It runs
   as the person, in their tenant and with authorization, like everything a
   table runs. It is given the values of the panel's fields, by the names of
   the fields, and nothing else that was sent.
3. **The table says what it returned, and reads again.**

The table adds nothing of its own. What the action does inside is the
resource's: the demo's read and write as the person who runs them, with the
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
the message. A failure is read out as well. Nothing is read again after a
failure.

## Who may run what

The table asks Ash, each time it reads and without a query, which of the
actions the person can **never** run (`Ash.can/3`, once per action):

- A table action the person can never run has no button for them.
- A generic row action they can never run has no button in any row.
- Ash is asked about the action without arguments. A policy of a generic
  action has no record to look at, so it can only look at the actor and at
  the arguments, and before a button is used there are none.
- A check that looks at an argument, the row's key among them, answers
  when the action runs. A refusal is then shown like any other failure. For
  the button to be offered, such a check has to say yes while the argument
  is not there.

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
a destroy or a create, so the rules about the resource's primary read
action do not apply to it.

## Nested tables

A nested table is the table of the destination resource, so it has that
table's table actions. A nested table has no line of its name of its own:
its name is the relationship line of the table around it. The buttons are
there, after the label and after the create button where the line has one,
once the nested table has read. They look as the create button of a line
does.

- A button of a line is used on the nested table. Its panel, its question
  and what it says afterwards are the nested table's, and the table around
  it says nothing.
- **A table action in a nested table is not given the row it is under.**
  It is the same action with the same arguments as on the table's own page:
  "Count unused" under a task counts the unused labels of the organization,
  not those of the task. Nothing in Ash says which argument of a generic
  action would take a parent.
- It runs as the person and in the tenant the nested table reads in.
- The nested table reads again afterwards, and the table around it does
  not.

**Try it:** `/tasks` as Ada Admin. Expand a row and open "Labels". On the
line, after "Labels", are "Count unused", "Recolour", "Remove unused",
"Merge" and "Import".

## The keyboard

The buttons on the line of the table's name are ordinary buttons: Tab
reaches them before the grid, and Enter and Space use them.

| After | Focus is |
| --- | --- |
| An action that ran at once | Still on its button. |
| A question answered with Cancel or Escape | Back on the button. |
| A question answered with Confirm | On the button. |
| The panel closed, by "Run", Cancel or Escape | Back on the button that opened it. |

The buttons on a relationship line are no tab stops, as its create button
is none. F2 on the line moves into its controls, Left Arrow and Right Arrow
move between them, Enter uses one and Escape returns to the line.

A generic action in a row is a button of the actions cell, with the keys of
that cell. After it ran, the table reads again, and focus stays in the
grid.

What the table says afterwards is in a live region (`role="status"`), and
is read out when it changes. All keys of a table are in
[Keyboard and accessibility](keyboard-and-accessibility.md).

## Edge cases

- **An action that runs for long holds its table.** A table action runs in
  the table's own process, as a row action does. Until it returns, that
  table answers nothing else.
- **An action with optional arguments only runs with their defaults.** The
  panel opens for an argument the action does not run without, as for a row
  action. Give an argument `allow_nil? false` to have it asked for.
- **A generic action under a policy that looks at a record cannot be run
  at all.** Ash raises for such a check on a generic action. The table
  takes the question as answered with "never", and has no button.
- **A question on an action is asked in the browser.** A `table_run` event
  sent to the LiveView by other means is not asked anything. What must not
  happen belongs in the action.
- **A new read closes the panel**, as for a row.
- **In a table with `on_forbidden :message` that was refused**, there are
  no buttons: a table that did not read offers nothing.
- **Returned text is shown as it is**, however long. Return a short line.

## Things people trip over

- **No button for an action.** The person can never run it; or it has a
  required argument the panel has no field for, which the compiler
  reported; or the table has not read.
- **A button that runs at once where a panel was expected.** Every argument
  of the action is optional or has a default.
- **Expecting the returned records in a table.** The table says "done" and
  reads its own records again.
- **Expecting a table action under a row to know that row.** It does not.
- **Expecting a generic action's button to be missing on the rows it
  refuses.** It is there on every row; the action answers when it runs.
- **`record_argument` on an update action.** It is for generic actions. An
  update action is given its record.
- **A key argument that is a plain text field.** Nothing says which
  resource it refers to. Say it with `reference` in the `action`.
- **A check on an argument that hides the button from everybody.** It is
  asked without the argument first.

## Not in the first version

No `reference` for an argument of the table's `create_action`, no label of
its own for the field of an argument, no way to give a table action in a
nested table the row it is under, no table of returned records,
no file to download from an action, no progress while an action runs and no
way to stop one, no result per record after a run on the selected rows, and
no icons on the buttons. The later slices are listed in the
[specification](https://github.com/StefanRoesch/ash_table/issues/21).
