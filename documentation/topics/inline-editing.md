# Inline editing

An inline edit changes one cell's value in place and saves it for that cell
alone, through the update action its column names. After reading this guide
you can make a table editable as a whole or column by column, predict which
cells open and which do not, and say what a person sees when a save succeeds
and when it fails.

The question a column can ask before saving is in [Confirm](confirm.md). What
depends on who is editing is in [Authorization](authorization.md). The keys
are in [Keyboard and accessibility](keyboard-and-accessibility.md).

## The smallest example

One line makes a table editable: `update_action` in the `table` block. The
demo's task labels
([`demo/lib/demo/tracker/task_label.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo/tracker/task_label.ex)):

<!-- source: demo/lib/demo/tracker/task_label.ex -->
```elixir
table do
  update_action :update
  # ...
end

actions do
  defaults [:destroy, create: [:task_id, :label_id, :note], update: [:note]]
```

**Try it:** `/task_labels` in the demo, as Ada Admin. Move to a cell of the
"Note" column, press Enter, type, press Enter again. The note is saved. The
cells of "Task ID" and "Label ID" do not open: the action `update` accepts
`note` only.

## Editing is opt-in

With no `update_action`, at the table or at a column, a table is read-only.
The table never guesses an action, not even the primary update action.
Listing the extension so that people can look at a resource must not, by
itself, let them change it: which action the table runs is a decision, and
the block is where it is made.

In the demo every mounted table names one. The table of the people
(`Demo.Tracker.User`) names none, on purpose: under a task on `/tasks`, the
one row of "Assignee" or "Reported by" has no cell that opens, for an admin
either.

## `update_action` at the table and at a column

| Where | Meaning |
| --- | --- |
| `update_action :name` in `table` | Every column whose attribute this action accepts becomes editable through it. |
| `update_action :name` in a `column` | This column is edited through this action. |
| `update_action false` in a `column` | This column is read-only, whatever the table says. |
| nothing in a `column` | The column follows the table. |

The task table uses all of them
([`demo/lib/demo/tracker/task.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo/tracker/task.ex)):

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
table do
  # Inline editing: every column whose attribute `update` accepts can be
  # edited in place, unless the column says otherwise.
  update_action :update
  # ...
  # edited through an action of its own
  column :priority do
    update_action :reprioritise
  end

  # numbers: one that is always there and one that can be empty. Progress
  # has its own action, which also starts a task that is still to do.
  column :progress do
    update_action :set_progress
  end
  # ...
  # `update` accepts it, the table does not offer it
  column :external_ref do
    update_action false
  end
  # ...
end
```

(A line `# ...` stands for lines of the block that are left out here.)

A column's own action is the way to let a cell do more than store a value.
The table runs the whole action, with its changes and validations:

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
# Reporting progress on a task that is still to do starts it.
update :set_progress do
  accept [:progress]

  change set_attribute(:status, :in_progress) do
    where attribute_equals(:status, :todo)
  end
end
```

**Try it:** on `/tasks`, find a task whose state is "To do" and change its
progress. The "State" cell of the same row changes to "In progress" with the
save.

## What makes a cell editable

A cell can be edited when all of this holds:

1. Its column is an attribute. Calculations and aggregates are never
   editable.
2. The attribute is writable (`writable? true`, the default).
3. An update action is behind the column: its own, else the table's. The
   action is `public?`, accepts the attribute, and has no required argument
   without a default.
4. The column's type has an editor (the table below).
5. The field is not hidden from the person on that row by a field policy.
6. The person is not someone who can never run the action.

Points 1 to 4 are the same for everybody. Points 5 and 6 depend on the
person; see [Authorization](authorization.md).

The two levels are held to different standards. A table-level action is a
blanket statement, so the columns it cannot save are quietly read-only: on
`/tasks`, "Inserted at" is, because no action accepts it. A column's own
action is a specific statement, so the compiler reports one that does not
exist, does not accept the column's attribute, or needs an argument, and one
on a column that points 1, 2 or 4 keep from ever being edited. See
[Mistakes at compile time](mistakes-at-compile-time.md).

When a table offers a person any editing, the cells they cannot edit are
marked `aria-readonly`.

## Actions that cannot serve a cell

An inline edit supplies exactly one input: the cell's value, under the
attribute's name. An action that cannot run on that alone cannot be behind a
column. The demo's tasks have such an action:

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

A cell has nowhere to ask for the reason, and the reason is not on the
record. The rule is narrow:

| The action has | Can it serve a cell? |
| --- | --- |
| A required argument without a default | No |
| An argument that may be nil, or has a default | Yes |
| Attributes it accepts besides the cell's | Yes; they are not sent |
| Attributes it requires (`allow_nil? false`) | Yes; the record already has them |

## The editor of each type

| Cell type | Ash types | Editor |
| --- | --- | --- |
| text | `:string`, `:ci_string` | A text field that grows with its lines. Shift+Enter makes a new line. |
| number | `:integer`, `:float`, `:decimal` | A number input. |
| boolean | `:boolean` | No edit mode: the value is toggled in place and saved at once. |
| date | `:date` | A date input. |
| datetime | `:datetime`, `:utc_datetime`, `:utc_datetime_usec`, `:naive_datetime` | A datetime input, in UTC, to the second. |
| enum | an `Ash.Type.Enum`, `:atom` with `one_of` | A menu of the values, with an empty choice when the attribute can be nil. |

Every other type is read-only text; see
[Columns and defaults](columns-and-defaults.md#types-shown-as-read-only-text).
A NewType is edited as the type it is made of.

**Try it:** `/specimens` in the demo has an editable cell of every type with
an editor, beside the read-only ones.

## Saving and cancelling

| Gesture | Effect |
| --- | --- |
| Enter | Saves. Focus stays on the cell. |
| Leaving the cell: a click elsewhere, Tab | Saves. Focus goes where the person sent it. |
| Escape | Gives the edit up. The cell shows its value again. |
| Toggling a boolean, choosing from a menu | Saves at once. |

Two rules keep the table from doing more than was asked:

- **An unchanged value runs nothing.** If the editor holds what the cell
  showed, no event is sent. If a `save` event arrives with the value the
  record already has, no action runs.
- **Empty input is sent as it is.** The table does not decide what empty
  means. Ash's type casting turns it into nil for most types, and the action
  decides whether nil is allowed. Emptying `estimate_hours` on `/tasks` saves
  nil; emptying `title` is refused with "is required".

While a save is on its way its cell is dimmed and marked `aria-busy`, and
cannot be opened again until the answer is there.

## What a save does

On the server, a save is four steps:

1. **The record is read again** by its primary key, as the person saving and
   in their tenant. The table does not keep the records it shows, and reading
   again means that policies and field policies apply to the save as they
   applied to the page.
2. If the field is hidden from the person on this record, the save is
   refused here.
3. **The column's action runs** through `AshPhoenix.Form`: `for_update` on
   the record, then `submit` with one parameter, the cell's.
4. **The row is shown from what the action returns**, with the table's
   calculations, aggregates and reference cells loaded onto it, as the
   person.

The table's read action does not run again. So the row reflects everything
the action did: on `/tasks`, "Headline" follows a new title and "Overdue?" a
new due date. And the row stays where it is, even if its new value no longer
matches the filters or belongs elsewhere in the sort, until the next change
of page, sort or filter reads the page afresh.

Loading calculations, aggregates and related records onto an action's result
goes through the resource's primary read action, as it always does in Ash. A
table that has both editable columns and calculation, aggregate or reference
columns therefore needs a primary read action. The compiler reports it otherwise, and the table of a
resource compiled all the same refuses to render.

## When a save fails

Nothing is saved, and the table shows what the action returned.

- The cell keeps what was typed and is marked: `aria-invalid`, and a ring in
  the error colour.
- The action's message is the cell's description (`aria-describedby`). It
  appears under the cell while the cell has focus or the pointer, so the row
  keeps its height, and it is announced to screen readers when it arrives.
- Focus is not pulled back to the cell. A person who tabbed on stays where
  they are.

| What went wrong | What the cell says |
| --- | --- |
| The action rejects the value | The action's message: "length must be greater than or equal to 3" |
| The value is not one of the type | Ash's message: "is invalid" |
| A validation about another field fails | That field's column label, then the message: "Progress: must be 100 when the task is done" |
| A policy refuses the action on this record | "You are not allowed to change this." |
| The record was deleted, or the person can no longer read it | "This record is no longer available." |
| Anything that is not of the action's making: a database error, a crash in a change | "This could not be saved." |

Only errors of Ash's "invalid" class are shown in their own words; they are
what an action returns on purpose. A field is named only if the person has a
column for it. The messages can be translated; see
[Messages and translations](messages-and-translations.md).

A failed cell is put right in one of three ways:

- Edit it again and save a value the action accepts.
- Press Escape on the cell: it shows the saved value again.
- Type the saved value again: nothing runs, and the mark is gone.

**Try it:** on `/tasks`, as Ada Admin, set a title to `ab`, or a progress to
`150`, or the state of a task whose progress is below 100 to "Done".

## No undo

The table has no undo and no history. A saved cell is saved. If people need
to take a change back, the resource has to offer an action for it; the table
only runs actions.

## Edge cases

- **Several cells of one row.** A failed cell stays marked when another cell
  of its row is saved. A cell that is being edited is left alone when another
  cell's save puts its row back, so what is typed survives; if that edit is
  then given up, the cell shows what the server sent last.
- **A failed edit is forgotten by the next read.** Changing the page, the
  sort or a filter reads the rows again and drops the marks, with what was
  typed.
- **A field hidden on the row cannot be edited, whatever is sent.** A `save`
  event for such a cell saves nothing, and the cell goes on saying "Not
  available". The value also stays hidden in the refreshed row after another
  cell of that row is saved.
- **A `save` event for a cell the table does not offer** (a read-only
  column, a row that is not on the page, a column that does not exist) runs
  nothing and shows nothing.
- **A record that is gone.** The row stays as it was read, since there is no
  record to show it from, and its cell carries the message. Escape restores
  the cell. The rest of the page works on.
- **A datetime with microseconds** is shown and edited to the second. Saving
  a changed value stores that second; saving nothing leaves the microseconds.
- **A number cell and a letter.** A key the number input does not take starts
  the edit without replacing the number.
- **Somebody else's change.** The table does not show changes made
  elsewhere until it reads again. The action still runs on the record as it
  is in the database, not on what the row shows.
- **A table-level action with a required argument** makes nothing editable,
  and nothing reports it. Name such an action on a column to get the
  compiler's message.

## Things people trip over

- **Nothing is editable.** There is no `update_action`, or the action does
  not accept the attributes of the columns.
- **One column stays read-only.** The action does not accept its attribute,
  the attribute is not writable, its type has no editor, or it is a
  calculation.
- **Expecting the whole row to be sent.** One input is sent. A validation
  that compares two fields sees the other one as it is stored.
- **Expecting the row to move or vanish after a save.** It stays until the
  next read.
- **`update_action :update` on a resource whose `update` accepts
  everything.** Every column with an editor becomes editable. Use
  `update_action false` on the columns that should not be, or give the table
  an action that accepts less.
- **A refusal that only shows on save.** The policy depends on the record.
  See [Authorization](authorization.md).

## Not in the first version

No creating or deleting records, no row actions with several inputs, no
editing of arrays, maps, embedded resources or related records, no
validation display before saving, no bulk edits and no undo. They are later
slices in the
[specification](https://github.com/StefanRoesch/ash_table/issues/21).
