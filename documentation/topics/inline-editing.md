# Inline editing

An inline edit changes one cell's value in place and saves that cell alone,
through the update action its column names. This guide covers making a
table editable as a whole or per column, which cells open, and what a
person sees when a save succeeds or fails.

Elsewhere: the question a column can ask before saving is in
[Confirm](confirm.md); what depends on who is editing in
[Authorization](authorization.md); the keys in
[Keyboard and accessibility](keyboard-and-accessibility.md); actions with
more than one value, deleting and creating in
[Row actions and create](row-actions-and-create.md).

## The smallest example

One line makes a table editable: `update_action` in the `table` block. The
demo's task labels
([`demo/lib/demo/tracker/task_label.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/task_label.ex)):

<!-- source: demo/lib/demo/tracker/task_label.ex -->
```elixir
table do
  update_action :update
  # ...
end

actions do
  defaults [:destroy, create: [:task_id, :label_id, :note], update: [:note]]
```

**Try it:** `/task_labels` as Ada Admin. Move to a "Note" cell, press Enter,
type, press Enter again: the note is saved. "Task ID" and "Label ID" do not
open: `update` accepts `note` only.

## Editing is opt-in

With no `update_action`, at the table or a column, a table is read-only.
The table never guesses an action, not even the primary update action:
listing the extension to let people look at a resource must not by itself
let them change it.

In the demo every mounted table names one, except the people's table
(`Demo.Tracker.User`), on purpose: under a task on `/tasks`, the one row of
"Assignee" or "Reported by" has no cell that opens, for an admin either.

## `update_action` at the table and at a column

| Where | Meaning |
| --- | --- |
| `update_action :name` in `table` | Every column whose attribute this action accepts becomes editable through it. |
| `update_action :name` in a `column` | This column is edited through this action. |
| `update_action false` in a `column` | This column is read-only, whatever the table says. |
| nothing in a `column` | The column follows the table. |

The task table uses all of them
([`demo/lib/demo/tracker/task.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/task.ex)):

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
    component AshDataTable.Components.Badge
  end

  # numbers: one that is always there and one that can be empty. Progress
  # has its own action, which also starts a task that is still to do. It
  # is shown as a bar and edited with a slider.
  column :progress do
    update_action :set_progress
    component DemoWeb.Cells.Progress
    # ...
  end
  # ...
  # `update` accepts it, the table does not offer it
  column :external_ref do
    update_action false
  end
  # ...
end
```

(`# ...` stands for lines left out. `component` sets how a column's cells
look and what they are edited with; it does not change how they are saved.
See [Custom components](custom-components.md).)

A column's own action lets a cell do more than store a value: the table
runs the whole action, with its changes and validations:

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

**Try it:** on `/tasks`, change the progress of a "To do" task. Its "State"
cell changes to "In progress" with the save.

## What makes a cell editable

All of this must hold:

1. Its column is an attribute. Calculations and aggregates are never
   editable. A reference cell (a column naming a belongs-to relationship) is
   edited through the relationship's foreign key, or through an argument
   its action hands to the relationship: see
   [Choosing a related record](choosing-a-related-record.md).
2. The attribute is writable (`writable? true`, the default).
3. An update action is behind the column (its own, else the table's), is
   `public?`, accepts the attribute, and has no required argument without a
   default.
4. The column's type has an editor (below). For an embedded resource or a
   map, a person must be able to give every field: see
   [Maps and embedded resources](maps-and-embedded-resources.md#what-can-be-edited).
5. No field policy hides the field from the person on that row.
6. The person is not someone who can never run the action.

Points 1–4 are the same for everybody; 5 and 6 depend on the person (see
[Authorization](authorization.md)).

The two levels are held to different standards. A table-level action is a
blanket statement: columns it cannot save are quietly read-only (on
`/tasks`, "Inserted at", which no action accepts). A column's own action is
specific: the compiler reports one that does not exist, does not accept the
column's attribute, or needs an argument, and one on a column that points
1, 2 or 4 keep from ever being edited. See
[Mistakes at compile time](mistakes-at-compile-time.md).

When a table offers a person any editing, the cells they can edit are Tab
stops and the others are not.

## Actions that cannot serve a cell

An inline edit supplies exactly one input: the cell's value, under the
attribute's name. An action that cannot run on that alone cannot be behind
a column. The demo's tasks have one:

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
record. Such an action is a row action: the tasks declare `action
:reassign`, whose button opens the action panel that asks for the reason.
See [Row actions and create](row-actions-and-create.md).

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
| datetime | `:datetime`, `:utc_datetime`, `:utc_datetime_usec`, `:naive_datetime` | A datetime input, to the second, in the page's time zone (UTC unless the page gives one; see [Time zones](time-zones.md)). |
| enum | an `Ash.Type.Enum`, `:atom` with `one_of` | The browser's own menu (a `<select>`) of the values, with an empty choice when the attribute can be nil. |
| array of enum values | `{:array, type}` of an enum | Not in the cell: the side panel, with a box per value of the enum. See [Arrays](#arrays). |
| array of text, numbers, booleans, dates or datetimes | `{:array, type}` of one of the types above | Not in the cell: the side panel, with one control per value, a button that takes the value away and a button that adds one. See [Arrays](#arrays). |
| a value made of fields | an embedded resource, `:map` with the `fields` constraint, and an array of either | Not in the cell: the side panel, with a field for every field of the value. See [Maps and embedded resources](maps-and-embedded-resources.md). |

Every other type is read-only text (see
[Columns and defaults](columns-and-defaults.md#types-shown-as-read-only-text)).
A NewType is edited as the type it is made of.

A reference cell has no editor in the cell: Enter or Space opens the picker,
a dialog with the related resource's own table to choose the related record
in. See [Choosing a related record](choosing-a-related-record.md).

Nor has a value made of fields: Enter or Space opens the side panel, where
it is edited field by field and saved with "Save" (see
[Maps and embedded resources](maps-and-embedded-resources.md)). An array
opens the same side panel (see [Arrays](#arrays)).

A column's `component` can replace the editor: on `/tasks`, "Progress" is
edited with a slider and "Estimate hours" in a number input with its unit
beside it. Such an editor opens, saves and cancels like the others, through
the same action. See [Custom components](custom-components.md).

**Try it:** `/specimens` has an editable cell of every type with an editor,
beside read-only ones.

## Arrays

An array is edited as a whole: its editor holds all values, and one save
sends all of them as the column action's one input. The demo's tasks have
two
([`demo/lib/demo/tracker/task.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/task.ex)):

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

Both are columns of `/tasks`, accepted by `update`, with nothing else
declared: an array is editable on the conditions of
[What makes a cell editable](#what-makes-a-cell-editable), like any column.

**An array is not edited in its cell.** Enter, a double click or a typed
key opens the side panel (the [action panel](row-actions-and-create.md))
with the column's attribute as its one field, as for a map or a union. The
typed key is typed into nothing. The row keeps its height.

**An array of enum values is multiple choice**: a group of boxes, one per
enum value in the enum's declared order, each with the value's label. The
record's values are ticked.

**Any other array is edited value by value**: one control per value (the
editor of the value's type from the table above; a box for a boolean), each
followed by a button that removes it, and "Add value" under them. Values are
not typed as one comma-separated text.

| Gesture | Effect |
| --- | --- |
| Ticking a box, adding a value, taking one away, typing into one | Changes the panel only. Nothing is saved. |
| "Save" | Runs the column's update action with the whole list. The panel closes, and focus is on the cell again. |
| Escape, or "Cancel" | Gives up everything done since the panel opened. Focus is on the cell again. |

An array is saved when the person is done, never at each step: a
half-edited list may be one the action does not accept.

What is sent, and what becomes of it:

- **The values as typed, in their order.** For a multiple choice, the
  ticked values in the enum's declared order. Ash casts each value.
- **No values is the empty array**, not nil. A nil array and an empty one
  both show an empty cell and a field without values, and "Save" with the
  record's values changes nothing.
- **A value left empty is left out.** `AshPhoenix.Form`, which the save goes
  through, removes from an array what its `empty_values` constraint names:
  the empty text unless the attribute says otherwise
  (`constraints empty_values: []`). This is `ash_phoenix` 2.3.22 on; an
  earlier one passes the empty value to the action, which refuses it with
  "no nil values" unless the array takes nil.
- **The constraints are the action's.** Ash checks `min_length`,
  `max_length`, `nil_items?` and the values' constraints (`items`) when the
  action runs; the table checks none, and shows what the action says: "must
  have 5 or fewer items" for a sixth tag, "Tags 2: length must be greater
  than or equal to 2" for a one-character second tag.
- **A refused list stays in the panel**, open with what was typed or ticked,
  the action's message at the field, read out ("Tags was not saved: …").
  The cell is not marked: it shows what the record holds. Escape or
  "Cancel" gives the edit up.
- **A message about one value says which.** Ash gives the refused value's
  place; the table prefixes the message with the value control's name in
  the panel: the column's label and the place, counted from 1. That control
  is marked (`aria-invalid`) until it is typed over. Of several values not
  of the type, Ash names the first. A multiple choice has no places, so its
  message stands alone.
- **The same values in another order are another value**, and are saved.

An array column is never sorted or filtered by: see
[Reading, sorting and pagination](reading-sorting-and-pagination.md#sorting)
and [Filtering](filtering.md#a-column-without-a-filter).

An array of embedded resources, or of maps that declare their fields, is
edited in the side panel as a list of groups: see
[Maps and embedded resources](maps-and-embedded-resources.md#an-array). An
array of anything else (maps without fields, unions, UUIDs, times, arrays)
is read-only. A single union is edited in the side panel too: see
[Unions](unions.md).

**Try it:** on `/tasks` as Ada Admin, press Enter on a "Tags" cell, Tab to
"Add value", press Enter, type a tag and use "Save". Then add a
one-character tag. On a "Checks" cell, press Enter, tick with Space, move
with Tab, use "Save". `/specimens` has "Strings", "Integers" (which has to
keep one value) and "Shades".

## Limits an editor shows before saving

A number's editor shows the attribute's constraints before anything is
saved. The demo's specimens have a whole number between -1000 and 1000
([`demo/lib/demo/kitchen_sink/specimen.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/kitchen_sink/specimen.ex)):

<!-- source: demo/lib/demo/kitchen_sink/specimen.ex -->
```elixir
attribute :an_integer, :integer do
  allow_nil? false
  public? true
  constraints min: -1000, max: 1000
end
```

Its editor is `<input type="number" min="-1000" max="1000" step="1">`. The
arrow keys and the input's own arrows stop at -1000 and 1000, and assistive
technology is told both limits. Nothing is declared in the `table` block.

| The constraint | On the input |
| --- | --- |
| `min`, `max` of `:integer`, `:float`, `:decimal` | `min`, `max` |
| a whole number (`:integer`) | `step="1"` |
| `:float`, `:decimal` | `step="any"` |
| the action cannot take the input empty | `aria-required="true"` |

The same applies to a number field of the action panel, a number inside a
map cell, an embedded resource or a union, each value of an array of
numbers, and a number of the argument line. Each takes it from where the
input belongs: an attribute's constraints, an argument's own, and
"required" from the action that runs (the attribute's `allow_nil?`, the
action's `require_attributes` and `allow_nil_input`). A NewType has the
limits of its underlying type. A column's `component` is given the
constraints and shows them itself, as the slider does: see
[Custom components](custom-components.md).

**The limits describe; they never stop a save.** A person can type 5000 and
press Enter: the value is sent as typed, Ash refuses it, and the message
shows at the cell (see [When a save fails](#when-a-save-fails)). The browser
checks nothing: the forms of the action panel and the argument line are
`novalidate`, and a cell's editor is in no form. One thing is held back:
what the browser cannot read as a number or date at all (`1e`, a half-typed
date). Such an input reports itself empty, and sending it would clear the
value.

Left out on purpose, as HTML has no attribute that means what Ash means:

- **Text length** (`min_length`, `max_length`). The browser's `maxlength`
  silently stops typing and cuts pasted text, and counts UTF-16 code units
  of the text as typed, where Ash counts codepoints, graphemes or bytes of
  the trimmed text: fifty emoji are fifty characters to Ash and a hundred to
  `maxlength`. So text can be typed past its limit, and Ash's message says
  what is wrong. A text with a `max_length` has a counter instead: see
  [The counter of a text](#the-counter-of-a-text).
- **A pattern** (`match`): an Erlang regular expression, which a browser
  reads by other rules; and a text editor is a `<textarea>`, which has no
  `pattern`.
- **Bounds that exclude their own value** (`greater_than`, `less_than`):
  `min="0"` would say 0 is fine.
- **How many values an array takes** (the array's `min_length`,
  `max_length`), and a decimal's `precision` and `scale`.

A resource's `validate` is no constraint: it is known only once the action
has run with the record, so it shows after a save.

**Try it:** on `/specimens`, press Enter on an "An integer" cell, hold the
up arrow past 1000, then type `5000` and press Enter. On `/tasks`, press the
down arrow in "Due within: Days" until it stops at 0.

## The counter of a text

A text whose type has a `max_length` gets a counter with its editor: the
current length and the maximum. A label's name takes 30 characters
([`demo/lib/demo/tracker/label.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/label.ex)):

<!-- source: demo/lib/demo/tracker/label.ex -->
```elixir
attribute :name, :string do
  allow_nil? false
  public? true
  constraints min_length: 1, max_length: 30
end
```

Its editor says `3/30` for "bug" and updates at every key. Nothing is
declared in the `table` block.

**Only for a maximum.** No `max_length`, no counter. It says nothing of
`min_length` or `match`.

**It counts as Ash counts**, so the two never disagree:

| Ash | The counter |
| --- | --- |
| Trims the text first, unless the type says `trim?: false` | Does not count the blanks and line breaks around the text. Those inside it count. |
| Counts in the unit of `length_count`: `:codepoints`, `:graphemes` or `:bytes` | Counts in the same unit. |
| Without `length_count`, counts as the application configures (`config :ash, default_string_length_count:`) | The same. The demo counts codepoints. |
| Folds a `:ci_string` that has a `casing` before it counts | The same. |

So a family emoji of three people is 5 in codepoints and 1 in graphemes;
`é` is 1 in codepoints and 2 in bytes. The server counts the editor's
starting value, in Elixir; the browser counts while a person types and
sends nothing for it.

**It describes; it never stops a save.** There is no `maxlength`. A text
past the maximum is typed in full, the counter says `34/30` in the weight
of the surrounding text (no longer muted), and the save is sent. Ash
refuses it, shown as under [When a save fails](#when-a-save-fails).

**Where it is.**

| The text | The counter |
| --- | --- |
| In the editor of a cell | Under the text, in the cell, at its end. The row grows to it while the editor is open; the column keeps its width. |
| A value of an array of text, in the side panel | After the value, in its row. |
| A field of the action panel, also inside a map cell, an embedded resource or a union | Under the field, at its end. |
| An argument of the argument line | After its input, on the line. |

A screen reader reads the counter when the editor gets focus, as the
editor's description (`aria-describedby`). It is no live region, so it is
not read at every key.

No counter on a sensitive text (typed hidden), nor on the editor of a
column's `component`, which is given the constraints and can show them
itself.

**Try it:** on `/labels` as Ada Admin, press Enter on a name and type. Type
past 30 characters and press Enter: the cell is marked, with "length must be
less than or equal to 30". On `/tasks`, type into "Search" above the table.

## Saving and cancelling

| Gesture | Effect |
| --- | --- |
| Enter | Saves. Focus stays on the cell. |
| Leaving the cell: a click elsewhere, Tab, Shift+Tab | Saves. Focus goes where the person sent it: Tab to the next stop, Shift+Tab to the one before. |
| Escape | Gives the edit up. The cell shows its value again. |
| Toggling a boolean, choosing from a menu with the pointer | Saves at once. |
| Moving through a closed menu with Up and Down Arrow | Nothing yet: Enter, or leaving the cell, saves the value reached. |
| Enter, a double click or a typed key on an array | Opens the side panel; "Save" there saves the list. See [Arrays](#arrays). |
| Letting go of a slider, or changing any other editor of a component that saves on change | Saves at once. The editor stays open; Enter or leaving the cell closes it. |

Two rules keep the table from doing more than asked:

- **An unchanged value runs nothing.** An editor holding what the cell
  showed sends no event; a `save` event with the value the record already
  has runs no action.
- **Empty input is sent as is.** The table does not decide what empty means:
  Ash's casting turns it into nil for most types, and the action decides
  whether nil is allowed. Emptying `estimate_hours` on `/tasks` saves nil;
  emptying `title` is refused with "is required".

While a save is on its way, its cell is dimmed, marked `aria-busy`, and
cannot be opened again until the answer arrives.

## What a save does

On the server:

1. **The record is read again** by its primary key, as the person saving,
   in their tenant, through the table's read action. The table does not keep
   the records it shows; reading the way the page was read applies the same
   action, policies and field policies to the save as to the page. A row the
   table shows can be read again, even where the resource's primary read
   action would not return it.
2. If the field is hidden from the person on this record, the save is
   refused here.
3. **The column's action runs** through `AshPhoenix.Form`: `for_update` on
   the record, then `submit` with one parameter, the cell's.
4. **The row is shown from what the action returns**, with the table's
   calculations, aggregates and reference cells loaded onto it, as the
   person.

The table's read action does not run again. So the row reflects everything
the action did (on `/tasks`, "Headline" follows a new title and "Overdue?" a
new due date), and the row stays where it is, even if it no longer matches
the filters or the sort, until the next change of page, sort or filter
reads the page afresh.

A saved cell is sent to the page as the event `:row_saved`, and the page
can veto a save before it runs: see
[Events and commands](events-and-commands.md).

Loading calculations, aggregates and related records onto an action's
result goes through the resource's primary read action, as always in Ash.
So a table with both editable columns and calculation, aggregate or
reference columns needs a primary read action. The compiler reports it
otherwise, and the table of a resource compiled all the same refuses to
render.

Ash goes through the primary read action for the result of every update,
whatever the table shows: it loads the result through it, and asks its
policies and field policies what of the result the person may have. So the
primary read action must be `public?` for a table that edits, as every
action a table runs must be. A resource whose primary read action is private
can have a table that names a public read action and only reads. See
[Authorization](authorization.md#every-action-a-table-runs-is-public).

## When a save fails

Nothing is saved, and the table shows what the action returned:

- The cell keeps what was typed and is marked: `aria-invalid`, a ring in
  the error colour, and a "!" at its end, which shows the failure without
  colour.
- The action's message stands in the cell under the value; the row grows
  to it. It is the cell's description (`aria-describedby`) and is announced
  to screen readers when it arrives.
- Focus is not pulled back. A person who tabbed on stays where they are.

| What went wrong | What the cell says |
| --- | --- |
| The action rejects the value | The action's message: "length must be greater than or equal to 3" |
| The value is not one of the type | Ash's message: "is invalid" |
| A validation about another field fails | That field's column label, then the message: "Progress: must be 100 when the task is done" |
| A policy refuses the action on this record | "You are not allowed to change this." |
| The record was deleted, or the person can no longer read it | "This record is no longer available." |
| Anything that is not of the action's making: a database error, a crash in a change | "This could not be saved." |

Only errors of Ash's "invalid" class, which an action returns on purpose,
are shown in their own words. A field is named only if the person has a
column for it. The messages can be translated: see
[Messages and translations](messages-and-translations.md). A refused list
is shown in the side panel, not the cell: see [Arrays](#arrays).

A failed cell is put right by:

- editing it again and saving a value the action accepts;
- Escape on the cell, which shows the saved value again;
- typing the saved value again: nothing runs, and the mark is gone.

**Try it:** on `/tasks` as Ada Admin, set a title to `ab`, an estimate to
`-3`, or the state of a task with progress below 100 to "Done".

## An inline edit and a row action

Both run an action on one row's record and share everything around it: the
record is read again as the person, the action runs through
`AshPhoenix.Form`, and the row is shown from what it returns. They differ
in what the person gives:

| | Inline edit | Row action |
| --- | --- | --- |
| Declared with | `update_action`, at the table or at a column | `action` |
| Runs | an update action | an update or a destroy action |
| Started from | the cell | a button in the last column of the row |
| Inputs | exactly one: the cell's attribute | none, or every input of the action, given in the action panel |
| A required argument | cannot be served | is a field of the panel |
| A failure is shown | on the cell | on the row's actions cell, or in the panel |

One action can be both. On `/tasks`, `set_progress` is behind the
"Progress" column and is a row action: the cell changes the number in
place, the button "Set progress" opens the panel with the same number.

## No undo

No undo and no history: a saved cell is saved. To take a change back, the
resource must offer an action for it; the table only runs actions.

## Edge cases

- **A `sensitive?` field's cell**: its editor hides what is typed and
  starts empty; left empty, it saves nothing. Only text and numbers are
  edited so. See [Sensitive columns](sensitive-columns.md#editing).
- **Several cells of one row.** A failed cell stays marked when another
  cell of its row is saved. A cell being edited is left alone when another
  cell's save puts its row back, so what is typed survives; if that edit is
  then given up, the cell shows what the server sent last.
- **The next read forgets a failed edit.** Changing the page, sort or a
  filter reads the rows again and drops the marks, with what was typed.
- **A field hidden on the row cannot be edited, whatever is sent.** A
  `save` event for it saves nothing, and the cell keeps saying "Not
  available". The value stays hidden in the refreshed row after another
  cell of that row is saved.
- **A `save` event for a cell the table does not offer** (a read-only
  column, a row not on the page, a column that does not exist) runs nothing
  and shows nothing.
- **A record that is gone.** The row stays as it was read, with the message
  on its cell. Escape restores the cell. The rest of the page works on.
- **A datetime with microseconds** is shown and edited to the second.
  Saving a changed value stores that second; saving nothing keeps the
  microseconds.
- **A number cell and a letter.** A key the number input does not take
  starts the edit without replacing the number.
- **A multiple choice whose record holds a value that is no longer a
  choice.** The cell shows it as is; the panel has no box for it. It is not
  lost: a save sends the ticked values in the enum's order, then every such
  value in the record's order, so only what a person could see and change
  has changed. The action then decides; Ash refuses a value not of the
  type, so the list fails to save, with the action's message, until the
  record is put right elsewhere. This only happens to an array of `:atom`
  limited by `one_of`: an `Ash.Type.Enum` fails the read of a value it does
  not have, and the table says "The records could not be loaded."
- **An array whose values may be nil** (`nil_items?: true`). An empty value
  is left out before the action sees it, so nil cannot be given through the
  table unless the attribute also says `empty_values: []`.
- **A column's `component` on an array column** shows its cells; its editor
  is not used: see
  [Custom components](custom-components.md#what-cannot-have-a-component).
- **Somebody else's change** does not show until the table reads again. The
  action still runs on the record as it is in the database, not as the row
  shows it.
- **A table-level action with a required argument** makes nothing editable,
  and nothing reports it. Name it on a column to get the compiler's
  message.
- **A table-level action that is not `public?`** is not one of the quiet
  cases: it is reported, and the table is refused.
- **An update action that runs its statement over a read action of its
  own** (`atomic_upgrade_with`). The table reads the record again through
  its own read action; the update then runs as the action says, by default
  over the primary read action, filters included. Records the primary read
  action filters out are saved only if the update action names a read
  action that returns them.

## Things people trip over

- **Nothing is editable.** No `update_action`, or the action does not
  accept the columns' attributes.
- **One column stays read-only.** The action does not accept its attribute,
  the attribute is not writable, its type has no editor, or it is a
  calculation.
- **Expecting the whole row to be sent.** One input is sent. A validation
  comparing two fields sees the other as stored.
- **Expecting the row to move or vanish after a save.** It stays until the
  next read.
- **`update_action :update` where `update` accepts everything.** Every
  column with an editor becomes editable. Use `update_action false` on the
  columns that should not be, or name an action that accepts less.
- **A refusal that only shows on save.** The policy depends on the record.
  See [Authorization](authorization.md).
- **Expecting `min` and `max` to stop a wrong number.** They show the
  limits; Ash refuses the value. See
  [Limits an editor shows before saving](#limits-an-editor-shows-before-saving).
- **Expecting the counter to stop typing at the maximum.** It counts; Ash
  refuses the text. See [The counter of a text](#the-counter-of-a-text).
- **A counter that says fewer characters than were typed.** Blanks around
  the text are not counted, as Ash trims them first.

## Not in the first version

Not yet: editing structs, keyword lists, tuples, a map that declares no
fields, or an array of unions; sorting or filtering by an array, an
embedded resource, a map or a union; a limit that stops typing a text, or
anything that shows its `min_length` or pattern before saving (see
[Limits an editor shows before saving](#limits-an-editor-shows-before-saving));
a hint beside an editor that states its limits in words; bulk edits; undo.
These are later slices in the
[specification](https://github.com/StefanRoesch/ash_data_table/issues/21).
A column's own editor is built: see [Custom components](custom-components.md).
Creating and deleting records, and actions with several inputs, are not
inline edits: see [Row actions and create](row-actions-and-create.md).
