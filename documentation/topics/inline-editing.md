# Inline editing

An inline edit changes one cell's value in place and saves it for that cell
alone, through the update action its column names. After reading this guide
you can make a table editable as a whole or column by column, predict which
cells open and which do not, and say what a person sees when a save succeeds
and when it fails.

The question a column can ask before saving is in [Confirm](confirm.md). What
depends on who is editing is in [Authorization](authorization.md). The keys
are in [Keyboard and accessibility](keyboard-and-accessibility.md). An action
that needs more than one value, deleting a record and creating one are in
[Row actions and create](row-actions-and-create.md).

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
    component AshTable.Components.Badge
  end

  # numbers: one that is always there and one that can be empty. Progress
  # has its own action, which also starts a task that is still to do. It
  # is shown as a bar and edited with a slider.
  column :progress do
    update_action :set_progress
    component DemoWeb.Cells.Progress
  end
  # ...
  # `update` accepts it, the table does not offer it
  column :external_ref do
    update_action false
  end
  # ...
end
```

(A line `# ...` stands for lines of the block that are left out here.
`component` says how the cells of a column look and what they are edited
with; it changes nothing about how they are saved. See
[Custom components](custom-components.md).)

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
   editable. A reference cell, whose column names a belongs-to
   relationship, is edited through the relationship's foreign key, or
   through an argument that its action hands to the relationship: see
   [Choosing a related record](choosing-a-related-record.md).
2. The attribute is writable (`writable? true`, the default).
3. An update action is behind the column: its own, else the table's. The
   action is `public?`, accepts the attribute, and has no required argument
   without a default.
4. The column's type has an editor (the table below). For an embedded
   resource or a map, a person has to be able to give every field of it:
   see [Maps and embedded resources](maps-and-embedded-resources.md#what-can-be-edited).
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
record. Such an action is a row action: the demo's tasks declare
`action :reassign`, and its button opens the action panel, which asks for
the reason. See [Row actions and create](row-actions-and-create.md).

The rule for a cell is narrow:

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
| array of enum values | `{:array, type}` of an enum | Multiple choice: a list of boxes in the cell, one per value of the enum. See [Arrays](#arrays). |
| array of text, numbers, booleans, dates or datetimes | `{:array, type}` of one of the types above | One control per value, with a button that takes the value away and a button that adds one. See [Arrays](#arrays). |
| a value made of fields | an embedded resource, `:map` with the `fields` constraint, and an array of either | Not in the cell: the side panel, with a field for every field of the value. See [Maps and embedded resources](maps-and-embedded-resources.md). |

Every other type is read-only text; see
[Columns and defaults](columns-and-defaults.md#types-shown-as-read-only-text).
A NewType is edited as the type it is made of.

A reference cell has no editor in the cell: Enter and F2 open the picker,
a dialog with the related resource's own table, in which the person chooses
the related record. See
[Choosing a related record](choosing-a-related-record.md).

Nor has a cell whose value is made of fields: Enter and F2 open the side
panel, where the value is edited field by field and saved with "Save". See
[Maps and embedded resources](maps-and-embedded-resources.md).

A column's `component` can put an editor of its own in the place of the one
in this table: on `/tasks`, "Progress" is edited with a slider and "Estimate
hours" in a number input with its unit beside it. Such an editor is opened,
saved and cancelled as the others are, and its value goes through the same
action. See [Custom components](custom-components.md).

**Try it:** `/specimens` in the demo has an editable cell of every type with
an editor, beside the read-only ones.

## Arrays

An array is edited as a whole. Its editor holds all of its values, and one
save sends all of them, as the one input of the column's action. The demo's
tasks have two
([`demo/lib/demo/tracker/task.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo/tracker/task.ex)):

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
# An array of text: at most five tags, each of two to twenty characters.
attribute :tags, {:array, :string} do
  allow_nil? false
  default []
  public? true
  constraints max_length: 5, items: [min_length: 2, max_length: 20]
end

# An array of enum values.
attribute :checks, {:array, Demo.Tracker.TaskCheck} do
  allow_nil? false
  default []
  public? true
end
```

Both are columns of `/tasks`, and `update` accepts both. Nothing else is
declared for them: an array is editable on the conditions of
[What makes a cell editable](#what-makes-a-cell-editable), as any column.

**An array of enum values is multiple choice.** The editor is a list of
boxes that opens in the cell: one per value of the enum, in the order the
enum declares them, each with the value's label. The boxes of the record's
values are ticked.

**Any other array is edited value by value.** The editor is a list that
opens in the cell: one control per value, which is the editor the value's
type has in the table above (a box for a boolean), each followed by a button
that takes the value away; and under them the button "Add value". Values are
not typed as one text with commas.

The row is as high as its editor needs while the editor is open, and one
line high again when it closes.

| Gesture | Effect |
| --- | --- |
| Ticking a box, adding a value, taking one away, typing into one | Changes the editor only. Nothing is sent. |
| Enter, in a value or on a box | Saves the list. Focus stays on the cell. |
| Leaving the editor: a click elsewhere, Tab from its last control | Saves the list. |
| Escape | Gives up everything done since the editor opened. |

An array's editor saves when the person is done with it, never at each
step: a list with one value ticked or one value taken away is on the way to
the list they want, and the action may not accept it half done.

What is sent, and what becomes of it:

- **The values as typed, in their order.** Of a multiple choice, the values
  that are ticked, in the order the enum declares them. Casting each value is
  Ash's.
- **No values is the empty array**, not nil. A record whose array is nil and
  one whose array is empty both have an empty cell and an editor without
  values, and closing that editor as it opened saves nothing.
- **A value left empty is left out.** `AshPhoenix.Form`, which the save goes
  through, takes out of an array what the array's `empty_values` constraint
  names, and that is the empty text unless the attribute says otherwise
  (`constraints empty_values: []`). This is `ash_phoenix` from 2.3.22 on;
  an earlier one gives the empty value to the action, which refuses it with
  "no nil values" unless the array takes nil.
- **The constraints are the action's.** `min_length`, `max_length`,
  `nil_items?` and the constraints of the values (`items`) are checked by
  Ash when the action runs. The table checks none of them, and shows what
  the action says: "must have 5 or fewer items" for a sixth tag, "Tags 2:
  length must be greater than or equal to 2" for a second tag of one
  character.
- **A message about one value says which.** Ash says the place of the value
  it refuses, and the table puts it in front of the message, as the value's
  control is called in the editor: the column's label and the place,
  counted from 1. When the cell is opened again, the control of that value
  is marked (`aria-invalid`), until it is typed over. Of several values that
  are none of the type, Ash names the first. A multiple choice names no
  place, as its boxes have none: the message stands alone.
- **The same values in another order are another value**, and are saved.

An array column is never sorted or filtered by, whatever it holds: see
[Reading, sorting and pagination](reading-sorting-and-pagination.md#sorting)
and [Filtering](filtering.md#a-column-without-a-filter).

An array of embedded resources, or of maps that declare their fields, is
edited in the side panel, as a list of groups: see
[Maps and embedded resources](maps-and-embedded-resources.md#an-array). An
array of anything else (maps without fields, unions, UUIDs, times, arrays)
is read-only. A single union is edited in the side panel too:
see [Unions](unions.md).

**Try it:** on `/tasks`, as Ada Admin, move to a cell of "Tags", press
Enter, Tab to "Add value", press Enter, type a tag and press Enter again.
Then add a tag of one character. On a cell of "Checks", press Enter, tick
with Space, move with the arrow keys, and press Enter. `/specimens` has
"Strings", "Integers" (which has to keep one value) and "Shades".

## Saving and cancelling

| Gesture | Effect |
| --- | --- |
| Enter | Saves. Focus stays on the cell. |
| Leaving the cell: a click elsewhere, Tab | Saves. Focus goes where the person sent it. |
| Escape | Gives the edit up. The cell shows its value again. |
| Toggling a boolean, choosing from a menu | Saves at once. |
| Ticking a box of a multiple choice; adding, changing or taking away a value of an array | Nothing yet: the list is saved by Enter or by leaving its editor. See [Arrays](#arrays). |
| Letting go of a slider, or changing any other editor of a component that saves on change | Saves at once. The editor stays open; Enter or leaving the cell closes it. |

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

1. **The record is read again** by its primary key, as the person saving, in
   their tenant and through the table's read action. The table does not keep
   the records it shows, and reading again the way the page was read means
   that the same action, with its policies and field policies, applies to
   the save as it applied to the page. A row the table shows is a row it can
   read again, also where the resource's primary read action would not
   return it.
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

Ash goes through the primary read action for the result of every update,
whatever the table shows: it loads what the action returns through it, and
asks its policies and field policies what of the result the person may
have. So the primary read action has to be `public?` for a table that
edits, as every action a table runs has to be. A resource whose primary
read action is private can have a table that names a public read action
and only reads. See
[Authorization](authorization.md#every-action-a-table-runs-is-public).

## When a save fails

Nothing is saved, and the table shows what the action returned.

- The cell keeps what was typed and is marked: `aria-invalid`, a ring in
  the error colour, and a "!" at its end, which shows the failure without a
  colour.
- The action's message is the cell's description (`aria-describedby`). It
  appears under the cell while the cell has focus or the pointer, so the row
  keeps its height, and it is announced to screen readers when it arrives.
- Focus is not pulled back to the cell. A person who tabbed on stays where
  they are.

| What went wrong | What the cell says |
| --- | --- |
| The action rejects the value | The action's message: "length must be greater than or equal to 3" |
| The value is not one of the type | Ash's message: "is invalid" |
| One value of an array is refused | The value's name in the editor, then the message: "Tags 2: length must be greater than or equal to 2" |
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

**Try it:** on `/tasks`, as Ada Admin, set a title to `ab`, or an estimate
to `-3`, or the state of a task whose progress is below 100 to "Done".

## An inline edit and a row action

Both run an action of the resource on the record of one row, and they share
everything around the action: the record is read again as the person, the
action runs through `AshPhoenix.Form`, and the row is shown from what it
returns. They differ in what the person gives it.

| | Inline edit | Row action |
| --- | --- | --- |
| Declared with | `update_action`, at the table or at a column | `action` |
| Runs | an update action | an update or a destroy action |
| Started from | the cell | a button in the last column of the row |
| Inputs | exactly one: the cell's attribute | none, or every input of the action, given in the action panel |
| A required argument | cannot be served | is a field of the panel |
| A failure is shown | on the cell | on the row's actions cell, or in the panel |

One action can be both. On `/tasks`, `set_progress` is the action behind the
"Progress" column and a row action: the cell changes the number in place,
the button "Set progress" opens the panel with the same number in it.

## No undo

The table has no undo and no history. A saved cell is saved. If people need
to take a change back, the resource has to offer an action for it; the table
only runs actions.

## Edge cases

- **A cell of a `sensitive?` field** has an editor that hides what is typed
  and starts empty, and an editor left empty saves nothing. Only text and
  numbers are edited so. See [Sensitive columns](sensitive-columns.md#editing).
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
- **A multiple choice whose record holds a value that is no longer one of
  the choices.** The value is shown in the cell as it is, and has no box.
  It is not lost: a save sends the ticked values, in the order the enum
  declares them, and then every such value, in the order the record has
  them, so that only what a person could see and change has changed. The
  action then decides. Ash refuses a value that is not one of the type's,
  so such a cell fails to save, with the action's message, until the record
  is put right elsewhere. This can only happen to an array of `:atom`
  limited by `one_of`: an `Ash.Type.Enum` fails the read of a value it does
  not have, and the table says "The records could not be loaded."
- **An array whose values may be nil** (`nil_items?: true`). A value left
  empty is left out before the action sees it, so nil is not given through
  the table unless the attribute also says `empty_values: []`.
- **A column's `component` on an array column** shows its cells, and its
  editor is not used: see
  [Custom components](custom-components.md#what-cannot-have-a-component).
- **Somebody else's change.** The table does not show changes made
  elsewhere until it reads again. The action still runs on the record as it
  is in the database, not on what the row shows.
- **A table-level action with a required argument** makes nothing editable,
  and nothing reports it. Name such an action on a column to get the
  compiler's message.
- **A table-level action that is not `public?`** is not one of the quiet
  cases: it is reported, and the table is refused.
- **An update action that runs its statement over a read action of its
  own** (`atomic_upgrade_with`). The table reads the record again through
  its own read action; the update then runs as the action says, which by
  default is over the primary read action, filters included. A table that
  shows records the primary read action filters out saves them only if the
  update action names a read action that returns them.

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

No editing of structs, keyword lists or tuples, nor of a map that
declares no fields or of an array of unions; no sorting or filtering by an
array, an embedded resource, a map or a union; no validation display
before a cell is saved, no bulk edits and no undo. A column's own editor is built: see
[Custom components](custom-components.md). They are later slices in the
[specification](https://github.com/StefanRoesch/ash_table/issues/21).
Creating and deleting records, and actions with several inputs, are not
inline edits: see [Row actions and create](row-actions-and-create.md).
