# Row actions and create

A row action is an action of the resource, declared for a table, that a
person runs on the record of one row. A table can also offer the resource's
create action, behind a button above it. This guide covers declaring both,
which actions run at once and which open the action panel, where the
panel's fields come from, and what a person sees on success, failure and
refusal.

Elsewhere: the question an action can ask first is in [Confirm](confirm.md);
changing one value in place in [Inline editing](inline-editing.md); a row
action on several rows in
[Selecting rows and bulk actions](selecting-rows-and-bulk-actions.md); an
action of the whole table, and a generic action in a row, in
[Table actions](table-actions.md); who may act in
[Authorization](authorization.md).

## The smallest example

An `action` in the `table` block is a button in every row; `create_action`
is a button above the table. The demo's comments have one of each
([`demo/lib/demo/tracker/comment.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/comment.ex)):

<!-- source: demo/lib/demo/tracker/comment.ex -->
```elixir
table do
  update_action :update
  on_forbidden :message

  # Live updates, also where the comments are nested under a task.
  live? true

  # ...

  action :destroy do
    confirm "Delete this comment?"
  end

  # "New comment". Under a task, the table gives `task_id` itself: the
  # action accepts it, and the comments of a task are a has-many.
  create_action :create
end
```

**Try it:** `/comments` as Ada Admin. The last column, "Actions", has
"Destroy" in every row; it asks "Delete this comment?", and Confirm removes
the row. "New comment", right of the table's name, opens a panel at the
window's right edge with "Body" and "Task ID"; "Create" adds the comment as
the first row.

Both are opt-in: no `action`, no actions column; no `create_action`, no
create button. The table never offers an action just because the resource
has it.

## Declaring row actions

Each `action` names an action of the resource. Its button stands in
declared order in a last column headed "Actions". The first four of the
demo's five task actions
([`demo/lib/demo/tracker/task.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/task.ex)):

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
| `label` | The action's name in words: "Set progress" | The button's text. |
| `confirm` | none | A question asked before the action runs, or `false`. See [below](#confirm-and-a-destroy-action-without-it). |
| `bulk?` | `true` for an action that can run on several rows | Also offer it for the selected rows; `false` keeps it to one row. See [Selecting rows and bulk actions](selecting-rows-and-bulk-actions.md#which-actions-are-offered). |
| `record_argument` | none | Generic actions only: the argument given the row's primary key. See [Table actions](table-actions.md#a-generic-action-in-a-row). |

The demo's task labels use `label` and `confirm`
([`demo/lib/demo/tracker/task_label.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/task_label.ex)):

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

**Try it:** `/tasks` as Ada Admin: every row ends in "Archive", "Reassign",
"Set progress", "Destroy" and "Set labels". `/task_labels`: one button,
"Remove".

- An action is the same in every row; no option hides its button on some
  records. Whether it runs on a record is up to the action and its policy.
- `open: "Open"` on the tag, `attach/4` or the router line adds a first
  button to every row. It runs no action and tells the page which row was
  opened; see [Events and commands](events-and-commands.md).
- A table with a row action has a selection box at the start of every row,
  and each row action is offered for the selected rows unless it says
  `bulk? false`; see
  [Selecting rows and bulk actions](selecting-rows-and-bulk-actions.md).

## Which actions can be row actions

A row action is a **public update or destroy action**: it runs on the
record of its row, and only those two are given a record.

| The `action` names | Result |
| --- | --- |
| A public update action | A row action. |
| A public destroy action | A row action; the compiler warns when it has no `confirm`. |
| A create action | Reported: use `create_action`. |
| A read action | Reported. |
| A generic action | A table action, its button on the line of the table's name; a row action with `record_argument`. See [Table actions](table-actions.md). |
| An action that is not `public?` | Reported, whatever its policies say: a table runs no private action. |
| Nothing the resource has | Reported. |

The messages are in
[Mistakes at compile time](mistakes-at-compile-time.md#row-actions-and-the-create-action).

## Straight away, or the action panel

| The action | Its button |
| --- | --- |
| Accepts no attribute, has no argument | Runs it. |
| Has only optional arguments or ones with a default | Runs it; the arguments keep their defaults and are not offered. |
| Has a required argument without a default (`allow_nil? false`) | Opens the action panel. |
| Accepts one or more attributes | Opens the panel, even when all may be empty: without them it would change nothing. |
| Has an argument given by choosing related records, required or not | Opens the panel. See [Relationships an action manages](managing-relationships.md). |
| Has an argument that takes a file, required or not | Opens the panel. See [Files](files.md). |
| Is the create action | Always opens the panel. |

So a resource's primary `update` as a row action opens a panel with every
attribute it accepts.

`archive` accepts nothing and has no arguments; `reassign` accepts an
attribute and requires an argument:

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
update :archive do
  accept []
  change set_attribute(:status, :archived)
end
```

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

**Try it:** `/tasks` as Ada Admin. "Archive" sets the row's "State" to
"Archived" at once. "Reassign" opens the panel, headed "Reassign:" and the
task's title; nothing has run yet.

## The fields of the panel

In the default kit the panel is a modal dialog at the window's right edge;
a kit, or `presentation: [panel: :inline]` on the table, opens it in the
page under the table ([Kits](kits.md)). A row action's panel is headed by
the action and the record ("Set progress: Write the report", the record
named as in a [full view's heading](nested-tables.md#the-heading)) and ends
in "Cancel" and "Run". A create's is headed "New task" (the button's text)
and ends in "Cancel" and "Create".

**Which inputs, in which order.** The public attributes the action accepts,
in `accept` order, then its public arguments in declared order. Private
attributes and arguments are never fields.

**What a field is called.**

| The input | Its label |
| --- | --- |
| An attribute with a column in the table | The column's label: "State" for `status` on `/tasks` (`label "State"`). |
| An attribute without a column | Its name in words: "External ref". |
| A key chosen in the picker | The label of the table's column of that relationship ("Assignee" for `assignee_id`); without one, the relationship's name in words. |
| An argument | Its name in words: "Reason", "Labels". |

**Which control.** The cell editors' controls, by input type, plus the
picker:

| Input type | Field |
| --- | --- |
| text (`:string`, `:ci_string`) | A text field of several lines. |
| number | A number input. |
| boolean | A checkbox. |
| date | A date input. |
| datetime | A datetime input, to the second, in the page's time zone (UTC unless given; see [Time zones](time-zones.md)). |
| enum | A menu of the values, with an empty choice when not required. |
| array of enum values | Multiple choice: a box per value, in declared order, under the label. |
| array of text, numbers, booleans, dates or datetimes | A row per value, with its type's control and a button that removes it; "Add value" below. |
| The key of a public belongs-to whose destination has a table | What the related record is called, as text, and "Choose", which opens the picker. |
| An argument the action hands to a relationship (one key or a list) | The picker: the record's name and "Choose"; for a list, each record's name with a button that removes it, and "Choose". See [Relationships an action manages](managing-relationships.md). |
| An argument holding a key or a list of keys, whose `action` in the block names their resource (`reference`) | The same. See [Table actions](table-actions.md#an-argument-that-holds-the-key-of-a-record). |
| A one-line value without an editor of its own: a UUID, an `:atom` without `one_of`, a time, a duration | A plain text field; Ash casts what is typed. |
| An embedded resource, a map that declares its fields, an array of either | A group of the value's fields under the label, each with its type's control; a group per value for an array. See [Maps and embedded resources](maps-and-embedded-resources.md#in-the-action-panel). |
| A union whose every kind has a control | A choice of kind, and that kind's value under it. See [Unions](unions.md#in-the-action-panel). |
| An argument that takes a file (`:file`) | A file input. See [Files](files.md). |
| Anything else: a map that declares no fields, a union with a kind that has no control, a binary, several files, and an array of any of these, of unions, or of one-line values | No field. See [below](#inputs-the-panel-has-no-field-for). |

**The field of a key.** A foreign key such as `assignee_id` of a public
belongs-to whose destination has a table is not typed: "Choose" opens the
picker, the destination's own table in a dialog over the panel, which keeps
what was typed. On `/tasks`, "Reassign" has "Assignee"; "New task" has
"Project" and "Assignee". Details:
[Choosing a related record](choosing-a-related-record.md#in-the-action-panel).
The key is a plain text field instead when its destination has no table,
its relationship is private or has a `filter`, or it is a key by name only.
An argument is a key by name only until a `manage_relationship` change or a
`reference` in the block's `action` names its resource
([Table actions](table-actions.md#an-argument-that-holds-the-key-of-a-record)).

**The counter of a text.** An input with a `max_length` gets a counter at
the end under its field, "15/200". It stops nothing. See
[Inline editing](inline-editing.md#the-counter-of-a-text).

**The field of an array** is a group of controls under one label, in row
actions and creates alike ("Tags", a list, and "Checks", a multiple choice,
in "New task" on `/tasks`).

- It always sends a list, the empty array when there are no values; never
  nil. A record whose array is nil has an empty array once an action with
  that field has run.
- So it has no required mark. A minimum count is the action's
  `min_length`, shown at the field when set.
- An empty value is left out: see [Inline editing](inline-editing.md#arrays).
- A message about one value names it ("Tags 2: …") and marks its control.
- A multiple choice sends record values that are none of its choices after
  the ticked ones, without showing them.
- Adding or removing a value sends only what typing in any field sends: the
  form as it stands.
- A column's component editor is not used for it.

**An attribute whose column has an editing component** uses that editor
instead of its type's control: on `/tasks`, "Progress" is a slider and
"Estimate hours" a number input with its unit, as in a cell. Label,
required mark and messages stay the table's. Moving the slider saves
nothing; its value goes with the form. Inputs without a column, and
arguments, get their type's control. See
[Custom components](custom-components.md#in-the-action-panel).

**What a field starts with.**

| The input | Starts with |
| --- | --- |
| An attribute, in a row action | The record's value, as read when the panel opened. |
| An argument, in a row action | Its default when fixed; else empty. |
| An argument holding everything a relationship is to hold, in a row action | The records related now. See [What a field starts with](managing-relationships.md#what-a-field-starts-with). |
| An attribute or argument, in a create | Its default when fixed; else empty. A computed default (a function) is left to the action. |

**Which fields are marked as required.** " \*" after the label and
`aria-required` on the control, taken from the action:

| The input | Required when |
| --- | --- |
| An attribute | `allow_nil? false` and not in the action's `allow_nil_input`, or in its `require_attributes`. |
| An attribute, in a create | The same, unless it has a computed default, which the action fills in. |
| An argument | `allow_nil? false`. |
| A checkbox | Never marked: a box is never empty. |

The browser's `required` is not used: an empty field is not stopped by the
browser, and the action's "is required" shows at the field.

**Try it:** `/tasks` as Ada Admin, "New task". Fourteen fields: "Title \*",
"Description", "State \*" (starts "To do"), "Priority \*" ("Medium"),
"Progress \*" (a slider at 0), "Estimate hours", the checkbox "Billable?",
"Due on", "External ref", "Project \*" and "Assignee" (each with "Choose"),
"Tags" ("Add value", no values yet), "Checks" (four boxes), and "Repeats",
a map whose group shows "Add value" until the value is added. The create
action accepts exactly these:

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

The reporter is set by the action from the actor, and the organization is
the tenant every action of the table runs in; neither is a field.

### Inputs the panel has no field for

| The input without a field is | Result |
| --- | --- |
| Optional | Left out of the panel; the action runs without it. |
| Required | The action cannot run from a table. The compiler reports it; a resource compiled anyway has no button for it. |

These include a list of keys (unless handed to a relationship whose records
can be chosen), an argument taking several files, a union with a kind
without a control, and an array of unions. An action whose only inputs
are such optional ones runs straight away; the library's tests have one
([`test/support/acting.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/test/support/acting.ex)),
the demo none.

### Inputs a person may not see

A field policy is about reading; the table treats what a person cannot see
as not theirs to write through it, as for a cell:

- **An attribute the person can never see** is no field of any panel for
  them. On `/tasks`, "New task" has "External ref" for Ada Admin, not for
  Max Member.
- **An attribute hidden on this record** is left out of that record's panel
  (none in the demo's row actions; see `Demo.Support.Plain.Order` in
  [`demo/test/support/plain_tables.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/test/support/plain_tables.ex)).
- **A value sent for such a field anyway is dropped.** The server takes
  values by the inputs the person has on the record, read again at "Run". A
  field visible when the panel opened and hidden by then is not written.

This protects the table only: the action accepts the attribute from anyone
its policy allows; see
[Authorization](authorization.md#refusing-to-edit-a-hidden-field-protects-the-table-only).

### Arguments the page fills

A `page_argument` inside an `action` names a public argument that the page
fills, not the person:

<!-- sketch -->
```elixir
action :assign do
  page_argument :assignee_id
end
```

The value comes from `page_arguments` on the tag, `attach/4` or the router
line. The panel has no field for it and nothing from the browser replaces
it. An action whose only required input is such an argument runs straight
away. A page that gives no value raises when the action opens or runs. See
[Events and commands](events-and-commands.md).

## Errors in the panel

The panel's form is an `AshPhoenix.Form` of the action; the table adds no
validation. A number field carries `min`, `max` and `step` from its
constraints, but the form is `novalidate`, so the browser blocks nothing and
the action's message shows. See
[Limits an editor shows before saving](inline-editing.md#limits-an-editor-shows-before-saving).

- **While typing**, the action validates the fields
  (`AshPhoenix.Form.validate/3`); nothing runs. An error shows once its field
  has been used.
- **After "Run"**, every error shows and the panel stays open with what was
  typed; nothing changed. Once corrected, the action runs.
- **At a field**, the error stands under it; the field is marked
  `aria-invalid` and described by it (`aria-describedby`).
- **Inside a value made of fields** (an embedded resource, a map), it is at
  that inner field. See
  [Maps and embedded resources](maps-and-embedded-resources.md#when-a-save-fails).
- **About no field of the panel** (attached to no field, about a field that
  is no input, or a refusal), it is an alert above the fields.

| What went wrong | Where | Message |
| --- | --- | --- |
| The action rejects a value | At the field | The action's: "length must be greater than or equal to 3" |
| A required input is empty | At the field | "is required" |
| A value not of the type (text in a key field) | At the field | "is invalid" |
| A validation about a field that is no input fails | Above | The field's column label and the message if the person has that column; else the message. |
| A policy refuses the action on this record | Above | "You are not allowed to do this." |
| The record is gone or no longer readable | Above | "This record is no longer available." |
| Anything not of the action's making | Above | "This could not be done." |

Screen readers hear the failure: "Reassign failed: Reason: is required".

**Try it:** `/tasks` as Ada Admin, "Reassign". Type `No` into "Reason": the
length message. Empty it and "Run": "is required". As Max Member, reassign
a task neither assigned to nor reported by him: "You are not allowed to do
this." above the fields.

"Cancel" and Escape close the panel and run nothing. Reopened, the panel
starts from the record.

## `confirm`, and a destroy action without it

`confirm` asks its question in the table's dialog, with Cancel and Confirm,
before the action runs; for a destroy, Confirm is in the error colour. It is
the dialog of a column's `confirm`; see
[Confirm](confirm.md#confirm-on-a-row-action).

| The action | The question is asked |
| --- | --- |
| Runs straight away | When its button is used. Cancel changes nothing; focus stays on the button. |
| Opens the panel | At "Run", over the panel (inside it where questions open in the page). Cancel returns to the panel as typed. |

- A destroy without `confirm` deletes at one click. Allowed, but it must be
  a visible choice: the compiler warns until it has a question or
  `confirm false`, as the demo's task labels do.
- `confirm false` on an update action is accepted and changes nothing.
- One question at a time per table: a new one gives up the open one, as
  Cancel does.
- The question is asked in the browser. It guards against slips and is no
  check, in controlled mode too.

## What running an action does

On the server, a row action:

1. **Looks up the action among those this table offers this person**, by
   name, and the row among the page's rows. An event naming anything else
   runs nothing.
2. **Reads the record again** by primary key, as the person, in their
   tenant, through the table's read action; the table keeps no records.
   With a panel this happens when it opens (to show the values) and again
   at "Run".
3. **Runs the action** through `AshPhoenix.Form`: `for_update` or
   `for_destroy`, then `submit` with the panel's values (or none).
4. **Shows what the action returned.**

A create is `for_create` and `submit`, then the same last step. The page can
hear what ran (`:action_ran`, `:row_destroyed`, `:row_created`) and stop a
write before it runs; see [Events and commands](events-and-commands.md).

| The action was | Afterwards |
| --- | --- |
| An update | The row shows what the action returned, with the table's calculations, aggregates and reference cells loaded onto it as the person. It stays in place even if it no longer matches the sort or filters. |
| A destroy | The row is gone, with its detail and every nested table open under it. |
| A create | The new record is the page's first row, and can be edited, expanded and acted on like any other. |

The table's read action does not run again. Changed rows stay in place and
new rows at the top until the next change of sort, filter or page, which
puts each where it belongs (possibly another page, or nowhere under a
filter).

Calculations, aggregates and reference cells are loaded onto the result
through the resource's primary read action, so a table with row actions or
a create action and such columns needs one (as with editable columns); the
compiler reports it otherwise. That primary read action must be `public?`
for any table with a row or create action, whatever its columns, because
Ash loads every create, update and destroy result through it. See
[Authorization](authorization.md#every-action-a-table-runs-is-public).

**Try it:** `/tasks` as Ada Admin. Create a task titled "Z…": it is the
first row. Click "Title": it moves to the end.

### The total

The person's own changes are counted in, by one:

- After a create, "1–25 of 320" under the table becomes "1–26 of 321"; after
  a destroy, both ends drop by one.
- `aria-rowcount` and every row's `aria-rowindex` follow.
- A keyset table, which shows only the total, shows one more or less.

Everything else waits for the next read: others' changes, and whether a new
record matches the filters or belongs on this page. A page left without
rows by a destroy is read again at once.

### Focus

| After | Focus is |
| --- | --- |
| An update that ran straight away | Still on its button. |
| A destroy | On the same stop (its action button) of the next row; else of the previous row; else on the table's first stop. |
| A create | On the new row's box, else its first stop, showing where the record went. |
| A row action run from its panel | Back on its button; after a destroy, as above. |
| Cancel or Escape in the panel | Back on the control that opened it. |

## When an action that ran straight away fails

Nothing pops up; the failure is shown on the row, as a failed cell edit is:

- The **actions cell** is marked (`aria-invalid`, a ring in the error
  colour) and described by the message (`aria-describedby`), shown under
  its buttons; the row grows for it.
- The message is announced: "Archive failed: You are not allowed to do
  this."
- Focus does not move; the buttons stay.

| What went wrong | The cell says |
| --- | --- |
| The action's error about a field | The field's column label and the message, if the person has that column |
| The action's error about no field | The message |
| A policy refuses the action on this record | "You are not allowed to do this." |
| The record was deleted or is no longer readable | "This record is no longer available." The row stays as read. |
| Anything not of the action's making | "This could not be done." |

The mark goes with the next action in that row, Escape on the cell, or the
next read. A failed cell in the same row is independent of it.

**Try it:** `/tasks` as Max Member: "Archive" on a task neither assigned to
nor reported by him.

## Creating records

`create_action` names a public create action of the resource:

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
# The "New task" button, on the line of the table's name.
create_action :create
```

The button opens the panel with the action's inputs; "Create" runs the
action as the person, in their tenant. It says "New" and the resource's
short name in words ("New task", "New task label" for
`Demo.Tracker.TaskLabel`); both parts can be translated, see
[Messages and translations](messages-and-translations.md#your-resources-wording).
A person who can never run the create action has no button.

| The table | The button |
| --- | --- |
| Mounted with `ash_data_table` | At the right of the page's heading line (the table's name, "Columns" and the argument line's inputs at the left). |
| Embedded with `<AshDataTable.table>` | The same, on the line of the table's name, which the `heading` attribute sets; see [Layout and embedding](layout-and-embedding.md#the-line-of-the-table-s-name). |
| The full view of a nested table | On the line naming the parent and the relationship, before "Show all records"; the record is created under that parent. |
| A nested table | At the far end of its relationship line. See below. |

## Creating in a nested table

A nested table offers create only where the table can join the new record
to its row itself:

- the relationship is a **has-many joined by attributes**, and
- the destination table's `create_action` **accepts the relationship's
  destination attribute**.

The demo's comments qualify: a task has many comments by `task_id`, and the
comments' create action accepts it:

<!-- source: demo/lib/demo/tracker/comment.ex -->
```elixir
create :create do
  primary? true
  accept [:body, :task_id]
  change relate_actor(:author)
end
```

The table fills that attribute in and hides it: under a task, "New comment"
has only "Body" (on `/comments`, "Body" and "Task ID"). The value is the
parent row's, read again as the person when the panel opens and at
"Create"; nothing the form sends replaces it. If the parent is gone or no
longer readable, nothing is created: "This record is no longer available."

The button stands at the far end of the relationship line (the nested
table's heading line), while the line is open and once the nested table has
read. The line is as wide as the visible part of the table around it and
stays put while that table scrolls sideways, so the button stays in view.

| Under a row of | The line | Offers |
| --- | --- | --- |
| `/tasks` | Comments | "New comment" |
| `/projects` | Tasks | "New task", without "Project ID" |
| `/tasks` | First comment, Newest comment (has-one) | nothing |
| `/tasks` | Labels (many-to-many) | nothing |
| `/tasks` | Project, Assignee, Reported by (belongs-to) | nothing |
| `/labels` | Tasks (many-to-many) | nothing |

Belongs-to, has-one, many-to-many, manual and `no_attributes?`
relationships offer no create, whatever the destination's table declares,
nor does such a nested table's full view. An existing record is linked
through a many-to-many by a row action taking the related records as an
argument ("Set labels" on `/tasks`; see
[Relationships an action manages](managing-relationships.md)).

**Try it:** `/tasks` as Max Member. Expand a row, open "Comments", use "New
comment": it is the nested table's first row, with Max as author.

Row actions in a nested table need nothing special: it is the destination's
own table, actions column included.

## Who may run what

Each time it reads, the table asks Ash, without a query, which actions the
person can **never** run (`Ash.can/3`, once per action):

- Such a row action has no button; if all are such, there is no actions
  column.
- Such a create action has no create button.
- An action that depends on the record keeps its button on every row; its
  policy answers when it runs, and a refusal shows on the actions cell or in
  the panel.

| `/tasks` as | Actions column | "New task" |
| --- | --- | --- |
| Ada Admin | Five buttons per row; each runs on every task. | Yes, fourteen fields. |
| Max Member | Five buttons per row; refused on a task neither assigned to nor reported by him: "You are not allowed to do this." | Yes, thirteen fields: no "External ref". |
| Vera Viewer | None. | No. |
| Olga Outsider | As the member, on Globex's tasks. | Yes; the task is Globex's. |
| Nobody | None, and no rows. | No. |

| Demo page | Row actions | Create |
| --- | --- | --- |
| `/projects` | "Set status" for admins and members, "Destroy" for admins | "New project" for admins |
| `/comments` | "Destroy" for admins and members; a member's is refused on others' comments | "New comment" for admins and members |
| `/labels` | "Destroy" for admins | "New label" for admins |
| `/task_labels` | "Remove" for admins and members | "New task label" for admins and members |

So Max Member has one action button on `/projects` and no actions column on
`/labels`.

## The keyboard

Each button of the actions cell is a Tab stop at the end of its row, after
the row's editable cells.

| Key | Where | Effect |
| --- | --- | --- |
| Enter, Space | On a button | The action runs, asks its question, or opens its panel. |
| Escape | On a button of a row whose action failed | Gives the message up. |

- Focus moves into the panel as it opens; Tab goes through its fields and
  buttons; Escape is Cancel.
- A modal panel keeps focus; an inline one lets Tab leave. Either way focus
  returns to what opened it when it closes.
- A key's field has one control, "Choose": Enter or Space opens the picker
  over the panel; Escape there closes only the picker. A field of several
  related records also has a removal button per record.
- A nested table's create button is a Tab stop on its relationship line,
  after the line's button; the one above a table is a Tab stop on the
  heading line.

All keys: [Keyboard and accessibility](keyboard-and-accessibility.md).

## Edge cases

- **A `sensitive?` input** is a password field that starts empty; left
  empty, it gives the action nothing. See
  [Sensitive columns](sensitive-columns.md#in-the-action-panel).
- **An update after which the person can no longer read the record**
  removes the row, as a destroy does.
- **A created record the person cannot read** closes the panel and adds no
  row; the total does not change.
- **A create that returns a record already on the page** (an upsert) shows
  that row again in place.
- **One panel per table.** Each nested table has its own, which goes when
  its line or row closes.
- **A new read closes the panel.** Changing sort, filter or page discards it
  with what was typed: its row may be another by then.
- **An actions cell whose action is under way** is `aria-busy`, and its
  buttons do nothing until the answer arrives.
- **A record gone when its button is used**: the panel does not open, and
  the actions cell says "This record is no longer available."
- **The parent row does not follow a nested create.** A task's "Comments"
  count stays as read until the next read.
- **An argument `allow_nil? false` with a fixed default** does not open the
  panel by itself: the action runs with the default, as with inline
  editing. If the panel opens for another input, the field is marked
  required and starts with the default.
- **A destroy action with inputs** opens the panel; its "Run" is in the
  error colour.
- **An `act` event sent to the LiveView by other means** is asked no
  question, in controlled mode too. What must not happen belongs in the
  action's policy or the page's `before_action`
  ([Events and commands](events-and-commands.md)).

## Things people trip over

- **No button for an action:** the person can never run it, or it has a
  required input without a field (reported by the compiler).
- **A button on records the action refuses:** the table asks per action,
  not per record; see
  [Authorization](authorization.md#why-a-rule-that-depends-on-the-record-shows-on-save).
- **A panel where a click was expected:** the action accepts attributes;
  use one that accepts none.
- **A panel though the one argument is optional:** the action hands it to a
  relationship whose records are chosen.
- **A new record not where the sort puts it:** it is first until the next
  read.
- **A typed key field where a picker was expected:** the relationship is
  not public, has a `filter`, or leads to a resource without a table; see
  [Choosing a related record](choosing-a-related-record.md#in-the-action-panel).
- **No create button under a relationship:** not a has-many joined by
  attributes, or the destination's create action does not accept the
  joining attribute.
- **A compiler warning on `action :destroy`:** add `confirm`, or
  `confirm false`.
- **`confirm` as protection:** it is not a check.

## Not in the first version

No form for a related record that an action creates or changes, no fields
for arrays of unions or several files, no create under a many-to-many or a
has-one, no type-to-confirm, no custom buttons or icons, no undo. Later
slices are in the
[specification](https://github.com/StefanRoesch/ash_data_table/issues/21).
