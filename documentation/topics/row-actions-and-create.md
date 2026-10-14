# Row actions and create

A row action is an action of the resource, declared for a table, that a
person runs on one record from that record's row. A table can also offer the
resource's create action, behind a button above it. After reading this guide
you can declare both, predict which action runs at once and which asks for
its inputs first in the action panel, say where each field of the panel
comes from, and say what a person sees when an action succeeds, fails or is
refused.

The question an action can ask first is in [Confirm](confirm.md). Changing
one value in place is [Inline editing](inline-editing.md). Running a row
action on several rows at once is in
[Selecting rows and bulk actions](selecting-rows-and-bulk-actions.md). An
action that belongs to the table as a whole, and a generic action in a row,
are in [Table actions](table-actions.md). What depends on
who is acting is summed up here and explained in
[Authorization](authorization.md).

## The smallest example

An `action` in the `table` block is a button in every row, and
`create_action` is a button above the table. The demo's comments have one of
each
([`demo/lib/demo/tracker/comment.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo/tracker/comment.ex)):

<!-- source: demo/lib/demo/tracker/comment.ex -->
```elixir
table do
  update_action :update
  on_forbidden :message

  # Live updates, also where the comments are nested under a task.
  live? true

  action :destroy do
    confirm "Delete this comment?"
  end

  # "New comment". Under a task, the table gives `task_id` itself: the
  # action accepts it, and the comments of a task are a has-many.
  create_action :create
end
```

**Try it:** `/comments` in the demo, as Ada Admin. The last column is
"Actions", with a button "Destroy" in every row. Use one: a dialog asks
"Delete this comment?", and Confirm takes the row away. On the line of the
table's name, at the right, is "New comment". It opens a panel at the right
edge of the window with the fields "Body" and "Task ID"; "Create" runs the
action, and the new comment is the first row.

Both are opt-in. A table with no `action` has no actions column, and one
with no `create_action` has no create button. The table never offers an
action because the resource happens to have it.

## Declaring row actions

Each `action` names an action of the resource. The buttons stand in the
declared order, in a last column headed "Actions". The demo's tasks declare
five, of which these are the first four
([`demo/lib/demo/tracker/task.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo/tracker/task.ex)):

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
# Row actions: a button each, in this order, in the last column of the
# table. `archive` has no inputs and runs when its button is used.
action :archive

# A required argument and an attribute: the button opens the action panel.
action :reassign

# One attribute, which the panel shows with the task's progress in it.
action :set_progress

# A destroy action asks first, or says that it does not (`confirm false`).
action :destroy do
  confirm "Delete this task? This cannot be undone."
end
```

| Option | Default | Meaning |
| --- | --- | --- |
| `label` | The action's name in words: "Set progress" | What the button says. |
| `confirm` | none | A question asked before the action runs, as a string; or `false`. See [`confirm`, and a destroy action without it](#confirm-and-a-destroy-action-without-it). |
| `bulk?` | `true`, for an action that can run on several rows | Whether the action is also offered for the rows a person has selected. `false` keeps it to one row. See [Selecting rows and bulk actions](selecting-rows-and-bulk-actions.md#which-actions-are-offered). |
| `record_argument` | none | For a generic action alone: the argument that is given the row's primary key. See [Table actions](table-actions.md#a-generic-action-in-a-row). |

The demo's task labels use both
([`demo/lib/demo/tracker/task_label.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo/tracker/task_label.ex)):

<!-- source: demo/lib/demo/tracker/task_label.ex -->
```elixir
# Taking a label off a task deletes nothing but the link: it runs at one
# click, and `confirm false` says that this is meant. Without it the
# compiler warns about a destroy action that asks nothing.
action :destroy do
  label "Remove"
  confirm false
end
```

**Try it:** `/tasks` as Ada Admin: "Archive", "Reassign", "Set progress",
"Destroy" and "Set labels" at the end of every row. `/task_labels`: one
button, "Remove".

An action is declared once, and is the same in every row: there is no
option that shows a button on some records only. Whether an action runs on
one record is the action's own business, and its policy's.

A table with a row action also has a box at the start of every row, and
every row action is offered for the rows a person selects, unless it says
`bulk? false`. That is the subject of
[Selecting rows and bulk actions](selecting-rows-and-bulk-actions.md).

## Which actions can be row actions

A row action is a **public update or destroy action** of the resource.

| The `action` names | What happens |
| --- | --- |
| A public update action | A row action. |
| A public destroy action | A row action. The compiler warns when it has no `confirm`. |
| A create action | Reported: a create action is offered with `create_action`. |
| A read action | Reported. |
| A generic action | No row action: a table action, with its button on the line of the table's name. With `record_argument` it is a row action. |
| An action that is not `public?` | Reported, whatever its policies say: a table runs no private action. |
| Nothing the resource has | Reported. |

The reason is in the word: a row action runs on the record of its row. An
update and a destroy action are given a record; a generic action is given
arguments and nothing else. So a generic action belongs to the table as a
whole, unless its declaration says which of its arguments takes the row's
key. Both are in [Table actions](table-actions.md).

The messages are in
[Mistakes at compile time](mistakes-at-compile-time.md#row-actions-and-the-create-action).

## Straight away, or the action panel

Using a button does one of two things, and the action decides which:

| The action | Using its button |
| --- | --- |
| Accepts no attribute and has no argument | Runs the action. |
| Has only arguments it runs without: optional ones, and ones with a default | Runs the action. The arguments keep their defaults and are not offered. |
| Has a required argument without a default (`allow_nil? false`) | Opens the action panel. |
| Accepts one or more attributes | Opens the action panel. |
| Has an argument that is given by choosing related records, required or not | Opens the action panel. See [Relationships an action manages](managing-relationships.md). |
| Has an argument that takes a file, required or not | Opens the action panel. See [Files](files.md). |

An action that accepts attributes opens the panel even when every one of
them may be empty. Changing them is what such an action is for: run without
them it would change nothing. This is why naming a resource's primary
`update` as a row action gives a button that opens a panel with every
attribute the action accepts. The same holds for an argument that the
action hands to a relationship, and whose records a person chooses.

The demo has both kinds. `archive` accepts nothing and has no arguments:

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
update :archive do
  accept []
  change set_attribute(:status, :archived)
end
```

`reassign` accepts an attribute and requires an argument:

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
# An action with a required argument: it cannot serve inline editing.
update :reassign do
  accept [:assignee_id]

  argument :reason, :string do
    allow_nil? false
    constraints min_length: 3, max_length: 200
  end

  change set_attribute(:internal_note, arg(:reason))
end
```

| Demo page | Runs straight away | Opens the panel |
| --- | --- | --- |
| `/tasks` | Archive; Destroy, after its question | Reassign (Assignee, Reason), Set progress (Progress), Set labels (Labels) |
| `/projects` | Destroy, after its question | Set status (Status) |
| `/comments`, `/labels` | Destroy, after its question | |
| `/task_labels` | Remove, with no question | |

**Try it:** `/tasks` as Ada Admin. "Archive" changes the "State" cell of its
row to "Archived" at once. "Reassign" opens the panel, headed "Reassign:"
and the task's title, and nothing has run yet.

The create action always opens the panel, whatever its inputs.

## The fields of the panel

The action panel is a modal dialog at the right edge of the window. It is
headed by the action and the record ("Set progress: Write the report"; the
record is called as in a [full view's heading](nested-tables.md#the-heading)),
has one field per input from top to bottom, and ends in "Cancel" and "Run".
For a create it is headed by the button's text, "New task", and ends in
"Cancel" and "Create".

**Which inputs, in which order.** The public attributes the action accepts,
in the order of its `accept`, then its public arguments in the order they
are declared. A private attribute or argument is never a field.

**What a field is called.**

| The input | Its label |
| --- | --- |
| An attribute the table has a column for | The column's label: "State" for `status` on `/tasks`, whose column says `label "State"`. |
| An attribute the table has no column for | The attribute's name in words: "External ref" for `external_ref`. |
| The key of a related record that is chosen in the picker | The label of the table's column of that relationship: "Assignee" for `assignee_id` on `/tasks`. Without such a column, the relationship's name in words. |
| An argument | The argument's name in words: "Reason"; "Labels" for an argument that takes the labels of a task. |

**Which control.** The controls are those of the cell editors, by the
input's type, and one more:

| Input type | Field |
| --- | --- |
| text (`:string`, `:ci_string`) | A text field of several lines. |
| number | A number input. |
| boolean | A checkbox. |
| date | A date input. |
| datetime | A datetime input, to the second, in the page's time zone (UTC unless the page gives one; see [Time zones](time-zones.md)). |
| enum | A menu of the values, with an empty choice when the input is not required. |
| array of enum values | Multiple choice: a box per value of the enum, in declared order, under the field's label. |
| array of text, numbers, booleans, dates or datetimes | A row per value, with the control of its type and a button that takes the value away, and the button "Add value" under them. |
| The key of a public belongs-to relationship whose destination has a table | What the related record is called, as plain text, and a button "Choose" that opens the picker. See below. |
| An argument that the action hands to a relationship, as the key of a related record or a list of such keys | The picker too: what the record is called and "Choose" for one key; for a list, what each record is called, each with a button that takes it out, and "Choose". See [Relationships an action manages](managing-relationships.md). |
| An argument that holds a key, or a list of keys, and whose `action` in the block says which resource they belong to (`reference`) | The same. See [Table actions](table-actions.md#an-argument-that-holds-the-key-of-a-record). |
| A value written as one line of text that has no editor of its own: a UUID, an `:atom` without `one_of`, a time, a duration | A plain text field. What is typed is given to the action as it is, and Ash casts it. |
| An embedded resource, a map that declares its fields, and an array of either | A group of the value's fields under the input's label, each with the control of its own type; for an array, a group per value. See [Maps and embedded resources](maps-and-embedded-resources.md#in-the-action-panel). |
| A union whose every kind has a control | The choice of its kind, and under it that kind's value. See [Unions](unions.md#in-the-action-panel). |
| An argument that takes a file (`:file`) | A file input. See [Files](files.md). |
| Anything else: a map that declares no fields, a union with a kind that has no control, a binary, several files, and an array of any of these, of unions, or of values written as one line of text | No field. See [Inputs the panel has no field for](#inputs-the-panel-has-no-field-for). |

**The field of a key.** An input that points at another resource, such as
`assignee_id` or `project_id`, is the foreign key of a relationship. Where
that is a public belongs-to relationship whose destination has a table, the
key is not typed: the field says what the related record is called, and its
button opens the picker, the destination's own table in a dialog on top of
the panel, where the person chooses a record. The panel underneath keeps
everything that was typed into it. On `/tasks`, "Reassign" has "Assignee",
and "New task" has "Project" and "Assignee". What the picker offers, what a
choice puts into the field and what a hand-made form cannot do with it is
in [Choosing a related record](choosing-a-related-record.md#in-the-action-panel).

A key whose destination has no table, whose relationship is private or has
a `filter`, or that is a key by name only, is a plain text field into which
the key is typed or pasted, as any UUID is.

An argument is a key by name only until something says which resource it
refers to: a `manage_relationship` change of the action, or a `reference`
in the `action` of the block. See
[Table actions](table-actions.md#an-argument-that-holds-the-key-of-a-record).

**The counter of a text.** A text field whose input has a `max_length` has
a counter under it, at its end: "15/200". It follows what is typed and
stops nothing. See [Inline editing](inline-editing.md#the-counter-of-a-text).

**The field of an array** is a group of controls under one label, in a row
action and in a create alike. On `/tasks`, "New task" has "Tags", a list of
values, and "Checks", a multiple choice.

- It gives the action a list in every case: the values as they were typed,
  and the empty array when there are none. It never gives nil, so a record
  whose array is nil has an empty array once an action with that field has
  run.
- It therefore has no mark of a required field. How many values an array
  has to have is the action's to say (`min_length`), and is shown at the
  field when the action says it.
- A value left empty is left out, as in a cell: see
  [Inline editing](inline-editing.md#arrays).
- A message about one value says which, as on a cell ("Tags 2: …"), and
  the control of that value is marked while the message is shown.
- A multiple choice keeps what the record holds that is none of its
  choices: it is sent with the ticked values, after them, and not shown.
- Nothing is sent to the action when a value is added or taken away, other
  than what typing in any field sends: the form as it stands, for the action
  to say what it makes of it.
- The editor of a column's component is not used for it.

**An attribute whose column has a component that edits** has that editor as
its field, in place of the control of its type: on `/tasks`, "Progress" is a
slider in the panel as it is in a cell, and "Estimate hours" a number input
with its unit. The label, the mark of a required field and the action's
messages around it stay the table's. Nothing is saved by moving the slider:
its value is sent with the form. An input the table has no column for, and
an argument, have the control of their type. See
[Custom components](custom-components.md#in-the-action-panel).

**What a field starts with.**

| The input | Starts with |
| --- | --- |
| An attribute, in a row action | The record's current value, as it was read when the panel opened. |
| An argument, in a row action | Its default, when that is a fixed value; else empty. |
| An argument that is everything a relationship is to hold, in a row action | The records that are related now. See [What a field starts with](managing-relationships.md#what-a-field-starts-with). |
| An attribute or an argument, in a create | Its default, when that is a fixed value; else empty. A default that is computed (a function) is left to the action. |

**Which fields are marked as required.** The mark is " \*" after the label,
and `aria-required` on the control. It comes from the action, not from the
table:

| The input | Required when |
| --- | --- |
| An attribute | It is `allow_nil? false` and the action does not list it in `allow_nil_input`, or the action lists it in `require_attributes`. |
| An attribute, in a create | The same, unless the attribute has a computed default: the action fills that in itself. |
| An argument | It is `allow_nil? false`. |
| A checkbox | Never marked: a box is never empty. |

The browser's own `required` is not used. A field that is left empty is not
stopped by the browser; the action says "is required", and the message is
shown at the field like every other message of the action.

**Try it:** `/tasks` as Ada Admin, "New task". Fourteen fields: "Title \*",
"Description", "State \*" starting with "To do", "Priority \*" with
"Medium", "Progress \*", a slider at 0, "Estimate hours", the checkbox "Billable?",
"Due on", "External ref", "Project \*" and "Assignee", each with the button
"Choose", and the two
arrays: "Tags", with the button "Add value" and no values yet, and "Checks",
four boxes; and "Repeats", a map, whose group has the button "Add value"
until the value is added. The create action accepts exactly these:

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
create :create do
  primary? true

  accept [
    :title,
    :description,
    :status,
    :priority,
    :progress,
    :estimate_hours,
    :billable?,
    :due_on,
    :external_ref,
    :project_id,
    :assignee_id,
    :tags,
    :checks,
    :recurrence
  ]

  change relate_actor(:reporter)
end
```

The reporter and the organization are no fields. The action sets the first
from the actor, and the second is the tenant the table runs every action in.

### Inputs the panel has no field for

| The input without a field is | What happens |
| --- | --- |
| Optional | It is left out of the panel. The action runs without it. |
| Required | The action cannot be run from a table. The compiler reports it, and a table of a resource compiled all the same has no button for it. |

A list of keys is among the inputs without a field, unless an action hands
it to a relationship whose records can be chosen. So are an argument that
takes several files, a union with a kind a table has no control for, and
an array of unions.

So an action whose only inputs have no field, all of them optional, runs
straight away. The demo's actions have no such input; the library's own
tests do
([`test/support/acting.ex`](https://github.com/StefanRoesch/ash_table/blob/main/test/support/acting.ex)).

### Inputs a person may not see

A field policy is about reading. The table takes it to mean that what a
person does not see in a table is not theirs to write through that table
either, as it does for a cell:

- **An attribute the person can never see** is no field of any panel for
  them, in a row action and in a create. On `/tasks`, "New task" has the
  field "External ref" for Ada Admin and not for Max Member.
- **An attribute hidden from them on this record** is left out of that
  record's panel. The demo's row actions accept no such attribute; the
  demo's tests have a resource whose do
  ([`demo/test/support/plain_tables.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/test/support/plain_tables.ex),
  `Demo.Support.Plain.Order`).
- **A value sent for such a field all the same is dropped.** The server
  takes the values by the names of the inputs the person has on the record,
  which it reads again when "Run" is used. A field that was visible when
  the panel opened and is hidden by then is not written.

This protects the table only. The action itself accepts the attribute from
anyone its policy allows; see
[Authorization](authorization.md#refusing-to-edit-a-hidden-field-protects-the-table-only).

## Errors in the panel

The panel's form is an `AshPhoenix.Form` of the action, and the table adds
no validation of its own. A number field says the least and the most its
constraints allow (`min`, `max`, `step`), from the action's argument or the
attribute it accepts, and the form is `novalidate`: the browser holds
nothing back over them, and the action's message is shown as below. See
[Limits an editor shows before saving](inline-editing.md#limits-an-editor-shows-before-saving).

- **While the person types**, what the fields hold is given to the action
  (`AshPhoenix.Form.validate/3`), and nothing runs. An error is shown at its
  field once the person has used that field.
- **After "Run"**, every error is shown, and the panel stays open with what
  was typed. Nothing was changed. Put right, the action runs.
- **An error at a field** is under the field, which is marked
  (`aria-invalid`) and described by it (`aria-describedby`).
- **An error about a field of a value made of fields** (an embedded
  resource, a map) is at that field, inside the value's group. See
  [Maps and embedded resources](maps-and-embedded-resources.md#when-a-save-fails).
- **An error about no field of the panel** is above the fields, as an
  alert. That is an error the action attached to no field, an error about a
  field that is no input of the panel, and a refusal.

| What went wrong | Where | What it says |
| --- | --- | --- |
| The action rejects a value | At the field | The action's message: "length must be greater than or equal to 3" |
| A required input is empty | At the field | "is required" |
| The value is not one of the type: text in a key field | At the field | "is invalid" |
| A validation about a field that is no input of the panel fails | Above the fields | The field's column label, then the message, when the person has a column for the field; the message alone when not. |
| A policy refuses the action on this record | Above the fields | "You are not allowed to do this." |
| The record is gone, or no longer the person's to read | Above the fields | "This record is no longer available." |
| Anything that is not of the action's making | Above the fields | "This could not be done." |

A failure is announced to screen readers as well: "Reassign failed:
Reason: is required".

**Try it:** `/tasks` as Ada Admin, "Reassign". Type `No` into "Reason":
"length must be greater than or equal to 3". Empty it and use "Run": "is
required". As Max Member, reassign a task that is neither
assigned to him nor reported by him: "You are not allowed to do this." above
the fields.

"Cancel", and Escape, close the panel and run nothing. Opened again, the
panel starts from the record.

## `confirm`, and a destroy action without it

`confirm` on an action asks its question in the table's dialog before the
action runs, with the buttons Cancel and Confirm. For a destroy action,
Confirm is in the error colour. The dialog and its answers are those of a
column's `confirm`; see [Confirm](confirm.md#confirm-on-a-row-action).

| The action | The question is asked |
| --- | --- |
| Runs straight away | When its button is used. Cancel leaves everything as it was, with focus on the button. |
| Opens the panel | When "Run" is used, on top of the panel. Cancel returns to the panel with everything as it was typed. |

A destroy action that names no `confirm` deletes at one click. That is
allowed, and it has to be a visible choice: the compiler warns about it
until the action has a question or says `confirm false`, as the demo's task
labels do above. `confirm false` on an update action is accepted and changes
nothing.

Like a column's question, an action's is asked in the browser. It guards
against slips and is no check.

## What running an action does

On the server, a row action is these steps:

1. **The action is looked up among the ones this table offers this
   person**, by its name, and the row among the rows of the page. An event
   that names anything else runs nothing.
2. **The record is read again** by its primary key, as the person, in their
   tenant and through the table's read action. The table keeps no records.
   For an action with a panel this happens twice: when the panel opens,
   which shows the record's values, and again when "Run" is used.
3. **The action runs** through `AshPhoenix.Form`: `for_update` or
   `for_destroy` on the record, then `submit` with the values of the
   panel's fields, or with nothing for an action that runs straight away.
4. **The page shows what the action returned.**

A create is `for_create` and `submit`, with the same last step.

| The action was | The page afterwards |
| --- | --- |
| An update | The row is shown from what the action returned, with the table's calculations, aggregates and reference cells loaded onto it, as the person. It stays where it is, also when it no longer matches the sort or the filters. |
| A destroy | The row is gone, with its detail and every nested table that was open under it. |
| A create | The new record is the first row of the page, a row like the others: it can be edited, expanded and acted on. |

The table's read action does not run again for any of them. A row that was
changed stays in its place, and a new row stays at the top, until the next
change of sort, filter or page reads the page afresh. That read puts each
where it belongs, which may be on another page or, under a filter, nowhere.

Loading calculations, aggregates and reference cells onto an action's
result goes through the resource's primary read action. A table with row
actions or a create action and such columns needs one, as a table with
editable columns does. The compiler reports it otherwise.

That primary read action has to be `public?` for every table with a row
action or a create action, whatever its columns are: Ash loads what a
create, an update or a destroy action returns through it. See
[Authorization](authorization.md#every-action-a-table-runs-is-public).

**Try it:** `/tasks` as Ada Admin. Create a task with a title that starts
with "Z": it is the first row. Click the heading "Title": it is at the end.

### The total

What the person did in the table is counted in, by one:

- After a create the range under the table reads "1–26 of 321" where it
  read "1–25 of 320". After a destroy it reads one less at both ends.
- The total that assistive technology is told (`aria-rowcount`) and the
  place of every row in it (`aria-rowindex`) follow.
- A keyset table, which shows the total alone, shows one more or one less.

Everything else is known at the next read: what other people did meanwhile,
and whether a new record matches the filters or belongs on this page. A
page that a destroy leaves without rows is read again at once.

### Focus

| After | Focus is |
| --- | --- |
| An update action that ran straight away | Still on the action's button. |
| A destroy | On the actions cell of the row after the one that went; else of the row before it; else on the grid's first cell. |
| A create | On the first data cell of the new row. It shows where the record went, and Enter edits it. |
| A row action that ran from its panel | Back on the action's button; after a destroy, as above. |
| The panel closed with Cancel or Escape | Back on the control that opened it. |

## When an action that ran straight away fails

Nothing pops up over the page. The failure is shown where a failed cell
edit is shown: on a cell of the row.

- The row's **actions cell** is marked (`aria-invalid`, a ring in the error
  colour) and described by the message (`aria-describedby`), which appears
  under the cell while the cell has focus or the pointer.
- The message is announced: "Archive failed: You are not allowed to do
  this."
- Focus is not moved, and the row's buttons stay.

| What went wrong | What the cell says |
| --- | --- |
| The action's own error about a field | The field's column label, then the message, when the person has a column for it |
| The action's own error about no field | The message |
| A policy refuses the action on this record | "You are not allowed to do this." |
| The record was deleted, or the person can no longer read it | "This record is no longer available." The row stays as it was read. |
| Anything that is not of the action's making | "This could not be done." |

The mark goes with the next action that runs in that row, with Escape on
the cell, and with the next read of the table. It stands beside a failed
cell of the same row without touching it: each is given up by itself.

**Try it:** `/tasks` as Max Member. Use "Archive" on a task that is neither
assigned to him nor reported by him.

## Creating records

`create_action` names a public create action of the resource:

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
# The "New task" button, on the line of the table's name.
create_action :create
```

The button opens the action panel with the action's inputs; "Create" runs
the action as the person and in their tenant.

**What the button says.** "New" and what one record is called: the
resource's short name in words. `Demo.Tracker.Task` gives "New task",
`Demo.Tracker.TaskLabel` "New task label". Both parts can be translated; see
[Messages and translations](messages-and-translations.md#your-resources-wording).

**Where the button is.**

| The table | The button |
| --- | --- |
| Mounted with `ash_table` | On the line of the page's heading: the table's name at the left, the button at the right. |
| Embedded with `<AshTable.table>` | On the line of the table's name, in the same way. The `heading` attribute says what the name is; see [Layout and embedding](layout-and-embedding.md#the-line-of-the-table-s-name). |
| The full view of a nested table | On the line that names the parent and the relationship, before "Show all records". The record is created under that parent. |
| A nested table | On its relationship line, after the label. See below. |

A person who can never run the create action has no button.

## Creating in a nested table

A nested table offers create where the table itself can say what joins the
new record to the row it is under. That is one case:

- the relationship is a **has-many joined by attributes**, and
- the destination's table names a `create_action` that **accepts the
  relationship's destination attribute**.

The demo's comments are that case. A task has many comments, joined by
`task_id`, and the comments' create action accepts it:

<!-- source: demo/lib/demo/tracker/comment.ex -->
```elixir
create :create do
  primary? true
  accept [:body, :task_id]
  change relate_actor(:author)
end
```

The table then gives that attribute itself and does not show it: under a
task, "New comment" opens a panel with "Body" alone, where the same button
on `/comments` has "Body" and "Task ID". The value is the parent row's own,
read again as the person when the panel opens and again when "Create" is
used. Nothing the form sends can replace it. When the parent is gone or no
longer theirs to read, nothing is created: "This record is no longer
available."

**Where the button is.** On the relationship line, right after its label,
while the line is open and once the nested table has read. A line is as
wide as the table around it, so its far end is usually out of sight; the
button is where the eye already is.

| Under a row of | The line | Offers |
| --- | --- | --- |
| `/tasks` | Comments | "New comment" |
| `/projects` | Tasks | "New task", without the field "Project ID" |
| `/tasks` | First comment, Newest comment (has-one) | nothing |
| `/tasks` | Labels (many-to-many) | nothing |
| `/tasks` | Project, Assignee, Reported by (belongs-to) | nothing |
| `/labels` | Tasks (many-to-many) | nothing |

A belongs-to, a has-one, a many-to-many, a manual relationship and one with
`no_attributes?` offer no create, whatever the destination's table
declares. An existing record is linked through a many-to-many by an action
of the row that takes the related records as an argument: "Set labels" on
`/tasks`, see [Relationships an action manages](managing-relationships.md).
The full view of such a nested table offers no create either.

**Try it:** `/tasks` as Max Member. Expand a row, open "Comments" and use
"New comment" on the line. The comment is the first row of the nested
table, with Max as its author.

The row actions of a nested table need nothing special: a nested table is
the destination's own table, with its actions column.

## Who may run what

The table asks Ash, each time it reads and without a query, which of the
actions the person can **never** run (`Ash.can/3`, once per action):

- A row action the person can never run has no button for them. If that is
  every one, the table has no actions column.
- A create action the person can never run has no create button.
- An action that depends on the record keeps its button on every row. The
  action's policy answers when it runs, and a refusal is shown on the
  actions cell or in the panel.

On `/tasks` in the demo:

| Actor | Actions column | "New task" |
| --- | --- | --- |
| Ada Admin | Five buttons on every row, and each runs on every task. | Yes, with thirteen fields. |
| Max Member | Five buttons on every row. A task that is neither assigned to him nor reported by him refuses: "You are not allowed to do this." | Yes, with twelve fields: no "External ref". |
| Vera Viewer | None. | No. |
| Olga Outsider | As the member, on Globex's tasks. | Yes; the task is Globex's. |
| Nobody | None, and no rows. | No. |

And on the other pages:

| Demo page | Row actions | Create |
| --- | --- | --- |
| `/projects` | "Set status" for admins and members, "Destroy" for admins | "New project" for admins |
| `/comments` | "Destroy" for admins and members; a member's is refused on a comment that is not theirs | "New comment" for admins and members |
| `/labels` | "Destroy" for admins | "New label" for admins |
| `/task_labels` | "Remove" for admins and members | "New task label" for admins and members |

So Max Member has an actions column on `/projects` with one button, and
none at all on `/labels`.

## The keyboard

The actions cell is a cell of the grid: the arrow keys stop at it, and End
reaches it. Its buttons are not tab stops. They are reached from the cell,
as a filter's controls are.

| Key | Where | Effect |
| --- | --- | --- |
| Enter, F2 | On an actions cell | Focus goes to its first button. |
| Left Arrow, Right Arrow | On a button | The button before, the button after. |
| Enter, Space | On a button | Uses it. |
| Escape | On a button | Back to the cell. |
| Tab | On a button | The next button; from the last one, out of the grid. |
| Escape | On an actions cell that shows a failure | Gives the message up. |
| Space | On the cell | Selects the row, or takes it out of the selection, as on any cell of a row. |

The action panel is a modal dialog. Focus moves into it and stays there,
Tab goes through its fields and buttons, and Escape is Cancel. The field
of a key has one control, its button "Choose": Enter or Space on it opens
the picker on top of the panel, and Escape there closes the picker alone.
The field of several related records has a button per record besides,
which takes that record out of the list.

A relationship line that has a create button holds two controls. Enter on
the line still opens and closes it. F2 on the line moves into its controls,
Left Arrow and Right Arrow move between them, Enter uses one and Escape
returns to the line.

The create button above a table is an ordinary button in the page's tab
order, before the grid.

All keys of a table are in
[Keyboard and accessibility](keyboard-and-accessibility.md).

## Edge cases

- **A `sensitive?` input** (an attribute or an argument) is a password
  field that starts empty, and left empty it gives the action nothing. See
  [Sensitive columns](sensitive-columns.md#in-the-action-panel).
- **An update action after which the person may no longer read the
  record** takes the row away, as a destroy does: there is nothing of it
  left for them to see.
- **A record that is created and is not the person's to read** closes the
  panel and adds no row. The total is not changed.
- **A create action that returns a record already on the page** (an
  upsert) shows that row again where it is.
- **One panel per table.** A table shows at most one panel. Each nested
  table has its own, and a panel of a nested table goes with it when its
  line or its row is closed.
- **A new read closes the panel.** A change of sort, filter or page while a
  panel is open takes the panel away with what was typed: its row may be
  another one by then.
- **An actions cell whose action is on its way** is marked `aria-busy`, and
  its buttons do nothing until the answer is there.
- **A panel whose record is gone when its button is used** does not open.
  The actions cell says "This record is no longer available."
- **The parent row does not follow a nested create.** A task's "Comments"
  cell counts as it did when the page was read, until the next read.
- **An argument that is `allow_nil? false` and has a fixed default** does
  not open the panel by itself: the action runs with the default, as with
  inline editing. Where the panel opens for another input, its field is
  marked as required and starts with the default.
- **A destroy action with inputs** opens the panel like any other, and its
  "Run" is in the error colour.
- **A question on an action is asked in the browser.** An `act` event sent
  to the LiveView by other means is not asked anything. What must not
  happen belongs in the action.

## Things people trip over

- **No button for an action.** The person can never run it; or it has a
  required input the panel has no field for, which the compiler reported.
- **Expecting a button to be missing on the records an action refuses.**
  It is there on every row. The table asks once per action, not per record;
  see [Authorization](authorization.md#why-a-rule-that-depends-on-the-record-shows-on-save).
- **A button that opens a panel where a click was expected.** The action
  accepts attributes. Give the table an action that accepts none.
- **Expecting a new record to appear where the sort puts it.** It is the
  first row until the table reads again.
- **A key field that is typed, where a picker was expected.** The key's
  relationship is not public, has a `filter`, or leads to a resource
  without a table. See
  [Choosing a related record](choosing-a-related-record.md#in-the-action-panel).
- **A button that opens a panel though its one argument is optional.** The
  action hands that argument to a relationship, and its records are chosen.
- **No create button under a relationship.** It is not a has-many joined by
  attributes, or the destination's create action does not accept the
  attribute that joins the two.
- **The compiler warns about `action :destroy`.** Give it a `confirm`, or
  `confirm false`.
- **Using `confirm` as protection.** It is not a check.

## Not in the first version

No form for a related record that an action creates or changes, no fields
for arrays of unions, nor for several files, no create under a many-to-many or a
has-one, no type-to-confirm, no custom buttons or icons, and no undo.
The later slices are listed in the
[specification](https://github.com/StefanRoesch/ash_table/issues/21).
