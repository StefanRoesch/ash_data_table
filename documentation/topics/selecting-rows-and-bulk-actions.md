# Selecting rows and bulk actions

A person can select rows of a table and run one of the table's row actions
on all of them at once. After reading this guide you can say which tables
have the boxes that select a row, select with the pointer and from the
keyboard, say how long a selection lasts and what "all that match" means,
keep an action to one row, predict what is asked before an action runs on a
selection and what is said afterwards, and say what a selection can never be
used to do.

The actions themselves, and the action panel, are in
[Row actions and create](row-actions-and-create.md). What depends on who is
acting is summed up here and explained in [Authorization](authorization.md).

A note on words: this guide says "bulk action" for a row action that runs on
the selected rows. It is the same action of the resource; there is no second
kind to declare.

## The smallest example

There is nothing to declare. A table that has a row action has the boxes,
and every row action is offered for a selection. The demo's tasks declare
five, of which these are the first four
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

**Try it:** `/tasks` in the demo, as Ada Admin. Every row starts with a
box. Tick three: above the grid a line reads "3 selected", with the buttons
"Clear selection", "Archive", "Reassign", "Set progress", "Destroy" and
"Set labels". Use
"Archive": a dialog asks "Run “Archive” on 3 records?". Confirm: the three
rows read "Archived", nothing is selected any more, and above the grid the
table says what became of it: "Archive: 3 done."

## Which tables have the boxes

A table has the column of boxes when it has something to do with a
selection: at least one row action that this person can ever run and that
runs on several rows. Otherwise it has no such column, no line above the
grid, and is not announced as a grid whose rows can be selected.

| Demo page | As | Boxes |
| --- | --- | --- |
| `/tasks` | Ada Admin, Max Member, Olga Outsider | Yes: five actions. |
| `/tasks` | Vera Viewer, nobody | No: they can run no action. |
| `/projects` | Ada Admin, Max Member | Yes: "Set status". "Destroy" is kept to one row; see [Keeping an action to one row](#keeping-an-action-to-one-row). |
| `/comments`, `/task_labels` | Ada Admin, Max Member | Yes: "Destroy", and "Remove". |
| `/labels` | Ada Admin | Yes: "Destroy". |
| `/labels` | Max Member, Vera Viewer | No. |
| `/specimens` | anyone | No: the table has no row action. |

The boxes are the first column of the grid. Where rows expand, the expander
is the second cell of a row, and the first column of the table the third.
The box in the header stands for the rows of the page. The cell under it in
the filter row is empty.

A nested table is the table of its resource and has its own boxes, its own
line and its own selection. See [Nested tables](#nested-tables).

## Selecting

| With | Effect |
| --- | --- |
| A click on a row's box, or beside it in its cell | Selects the row, or takes it out of the selection. |
| A click on the box in the header | Selects every row of the page. When all of them are selected already, takes them out. |
| Shift and a click, anywhere on a row | Selects the rows from the one that was selected or clicked last to this one. It adds, and takes nothing out. |
| Space, on any cell of a row | Selects the row, or takes it out. |
| Space, on the cell of the box in the header | As a click on that box. |
| Shift+Down Arrow, Shift+Up Arrow, on a cell of a row | Moves to the next or the previous row and selects as it goes: the rows from where the key was first pressed to where focus is now, with what was selected before. Going back takes rows out again. |

The box in the header is ticked when every row of the page is selected, and
shows the mixed state (a dash) when only some are.

The table holds what is selected on the server. The box is ticked in the
browser at once, and every change of what is selected is sent to the
server, which brings no row back: it draws the line above the grid from
what it holds, so the count and the buttons follow a moment later.

**Try it:** `/tasks` as Ada Admin. Press Tab until a cell has the focus
ring, then Space: "1 selected". Hold Shift and press Down Arrow twice: "3
selected". Still holding Shift, press Up Arrow: "2 selected".

### What Space does where

Space is the key of row selection on a cell. It keeps what it does anywhere
else inside a control that a cell holds:

| Focus is | Space |
| --- | --- |
| On a cell of a row of records, a boolean cell among them | Selects the row, or takes it out. A boolean is toggled with Enter or F2. |
| On the cell of the box in the header | Selects the rows of the page. |
| On any other cell: a heading, a filter cell, a relationship line, the cell that holds a nested table | Nothing. It does not scroll the page. |
| On a button in a cell: a row action, an expander | Uses the button. |
| In a filter's input, or in the editor of a cell | Types a space. |
| On a cell, in a table without boxes | Nothing. |

This is the split the ARIA grid pattern makes: a key belongs to the grid
while focus is on a cell, and to the control once focus is in one.

## What is selected, and for how long

A selection is a set of records, remembered by their primary keys.

| When | The selection |
| --- | --- |
| Another page is opened | Stays. The rows of the page left behind are still selected, and the count says so. |
| The table is sorted | Stays. |
| A filter is set, changed or cleared | Is given up. What was selected under other filters may not be among the rows any more. |
| An [argument](arguments.md) of the table is changed | Is given up, for the same reason. "All that match" is what the filters match of what the read action returns for its arguments. |
| The record the table is limited to (`of`) changes | Is given up, for the same reason. |
| A cell is saved, a row action runs on one row | Stays. A row that the action took away is taken out of it. |
| The page is reloaded, or left | Is gone. It is not in the URL, and the table holds it only while the page is open. |
| An action ran on it | The rows it did not run on stay selected; the others are taken out. |

The line above the grid says how many records are selected, on this page
and on the others: "1 selected", "3 selected", in the plural forms of the
page's language (see [Messages and translations](messages-and-translations.md#counts-plural-forms)).
The count is a live region: it is read out when it appears and whenever it
changes, and focus stays where it is.

A page hears of a selection through the events `:selection_changed` and
`:bulk_ran`, and reads or clears it with the commands
`selected_records/2` and `clear_selection/2`: see
[Events and commands](events-and-commands.md).

A table whose records have no primary key has no boxes: a row that cannot
be named cannot be told from another.

## All that match

Once every row of the page is selected, and the filters match more records
than the page shows, the line offers one more button: "Select all 320 that
match". It selects every record the table's read action returns for this
person under the current filters, on every page.

- The count then reads "All 320 that match are selected".
- This selection is not a list of rows. It is "whatever matches", and it
  is worked out when an action runs: the server reads the records through
  the table's read action, with the filters, as the person.
- Taking one row out of it turns it back into a list: the other rows of
  this page stay selected, and those of the other pages are selected no
  longer.
- The box in the header clears it.
- Where the read action does not count (`countable: false`), there is no
  number: the button reads "Select all that match", the count "All that
  match are selected". It is offered whenever there is another page.

**Try it:** `/tasks` as Ada Admin. Tick the box in the header: "25
selected", and "Select all 320 that match" appears. Use it. Filter "Title"
by `email`: the selection is given up.

## The line above the grid

The line is above the grid, under the line of the table's name. It holds,
from the left:

| | Shown |
| --- | --- |
| The count: "1 selected", "3 selected", or "All 320 that match are selected" | While anything is selected. |
| "Select all 320 that match" | While every row of the page is selected and there is more than the page. |
| "Clear selection" | While anything is selected. |
| One button per bulk action, in the declared order | While anything is selected. |

"Clear filters" is at the other end of the same line. On a table
of its own the line is as high as a button whether or not anything is
selected, so the grid does not move when the buttons appear. A nested table
keeps no room free for it.

The server draws the line from the selection it holds. Its buttons are
ordinary buttons in the page's tab order, before the grid and the
"Columns" button. They are there only while rows are selected. See
[The keyboard](#the-keyboard).

## Which actions are offered

Every row action of the table that this person can ever run, with two
exceptions.

| The action | For a selection |
| --- | --- |
| A public update or destroy action declared with `action` | Offered. |
| A generic action declared with `record_argument` | Offered. It runs once per selected record, each time given that record's key. See [Table actions](table-actions.md#a-generic-action-in-a-row). |
| A generic action without it: a table action | Never. It runs on no record. `bulk? true` on it is reported. |
| The same, declared with `bulk? false` | Not offered. It stays a row action. |
| One that accepts an attribute of the primary key, or an attribute that is an identity by itself | Not offered. It stays a row action. |
| One the person can never run | Not offered, and no button in the rows either. |
| The create action, a column's `update_action` | Never. |

### Keeping an action to one row

`bulk? false` on an `action` keeps it off the line. The demo's projects use
it
([`demo/lib/demo/tracker/project.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/project.ex)):

<!-- source: demo/lib/demo/tracker/project.ex -->
```elixir
# A project is deleted with all its tasks: one at a time, from its own
# row. `bulk? false` keeps the action off the line of the selected rows.
action :destroy do
  confirm "Delete this project, with all its tasks?"
  bulk? false
end
```

| Option | Default | Meaning |
| --- | --- | --- |
| `bulk?` | `true`, for an action that can run on several rows | Whether the action is offered for the selected rows. It can only switch off. |

**Try it:** `/projects` as Ada Admin. Every row has "Set status" and
"Destroy". Select two rows: the line has "Set status" alone.

### Actions that cannot run on several rows

The inputs of a bulk action are given once and applied to every record. A
value that only one record can hold cannot be given to several. So an
action that accepts such an attribute is not offered for a selection:

- an attribute of the primary key;
- an attribute that is an identity by itself (`identity :unique_name,
  [:name]`).

An identity of several attributes is no reason: each of them can be the
same on many records. The demo's tables have no such action; the library's
own tests do
([`test/support/acting.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/test/support/acting.ex),
`AshDataTable.Test.Acting.Sheet`).

`bulk? true` on such an action is reported when the resource is compiled:
the option switches nothing on. See
[Mistakes at compile time](mistakes-at-compile-time.md#row-actions-and-the-create-action).

## The question

Every bulk action asks first, whether its action has a `confirm` or not:
one click must not change a page of records. The question opens over the
page or in it, as the table's [presentation](layout-and-embedding.md)
says; a table asks one question at a time, and a new one gives the open
one up, as Cancel.

| The action | The question |
| --- | --- |
| Has no `confirm` | "Run “Archive” on 3 records?" |
| Has a `confirm` | Its own question, then the number: "Delete this task? This cannot be undone. 3 records are selected." |
| Says `confirm false` | As an action without one. |
| All that match are selected | The number is the total the table counted: "Run “Archive” on 320 records?" |
| All that match, and the read action does not count | "Run “Archive” on all records that match?" |

The buttons are Cancel and Confirm, and Confirm is in the error colour for
a destroy action, as for a row. Cancel, and Escape, run nothing and put
focus back on the button. For an action with inputs the question is asked
when "Run" is used in the panel, on top of it.

The number is worked out on the server when the button is used. Confirm
runs the action on exactly the selection the question named. The page
stays in use while the question is open; if the selection changed before
Confirm, nothing runs, and the table says so: "Nothing was run: the
selection changed after the question was asked."

Like every question of a table, it guards against slips and is no check:
the server does not enforce it, and an event sent by other means can skip
it. Rules belong in the resource's policies. See [Confirm](confirm.md).

## Inputs

An action with inputs opens the action panel, once, for the whole
selection. It is headed by the action and the number of records ("Reassign:
3 records"; "Reassign: all records that match" where the table has no
number) and has the fields the panel of a row has, with these differences:

| | In the panel of a row | In the panel of a selection |
| --- | --- | --- |
| An attribute starts with | The record's value | Nothing: there is no one record to take it from. Not the attribute's default either. |
| An argument starts with | Its default, when that is a fixed value | The same. |
| An argument that is everything a relationship is to hold starts with | The records that are related now | Nothing: what is chosen is given to every selected record, in place of what each had. See [Relationships an action manages](managing-relationships.md#on-the-selected-rows-in-a-create-in-a-nested-table). |
| A union starts with | The kind and the value the record holds | No kind, which is given to every selected record as no value. See [Unions](unions.md#in-the-action-panel). |
| A file | Is given to the action on this record | Is given to the action on every selected record: the same file each time. See [Files](files.md#on-the-selected-rows). |
| A field of an attribute the person sees on some records only | Is there where they see it on this record | Is never there. |
| What the fields hold | Is given to the action on this record | Is given to the action on every selected record. |

**An empty field is an empty value**, as in the panel of a row: on
`/tasks`, "Reassign" with "Assignee ID" left empty takes the assignee off
every selected task. A field does not mean "leave as it is" when it is
empty. An action for a selection should accept what it is meant to change,
and no more.

**Errors while typing** are shown at the fields as in any panel. The form
behind them is the action's on a record that holds nothing, so it knows
what the action makes of a value as such: text that is no number, an
argument that is too short, a required input that is empty. After "Run",
such an error keeps the panel open and nothing runs. What depends on the
record (a validation that looks at another field, a policy) is known when
the action has run, and is said then.

**Try it:** `/tasks` as Ada Admin. Select two rows, "Reassign". Type `No`
into "Reason": "length must be greater than or equal to 3". Put it right
and use "Run": the question, and then the result, "Reassign: 2 done."

## What running does

On the server, a bulk action is these steps:

1. **The action is looked up among the ones this table offers this person
   for a selection**, by its name. An event that names anything else runs
   nothing.
2. **The records are read**, as the person, in their tenant and through the
   table's read action, a hundred at a time. The rows that were named are
   read by their primary keys. For "all that match", the keys of everything
   the filters match are read first, before anything is changed.
3. **The action runs on each record that was read**, as the person, with
   authorization, through `Ash.bulk_update/4` or `Ash.bulk_destroy/4`. A
   generic action that takes a row's key has no bulk call in Ash: it is run
   once per record, as its row's button runs it.
4. **The table is read again**, and says what became of the run.

The rows are not looked up among those of the page, since a selection
outlives its page. What the browser sends is taken as a claim: a key that
names nothing this person may read through the table's read action is not
run on, and counts as a record that is no longer available.

### How Ash is asked

| Option | Why |
| --- | --- |
| `strategy: :stream` | One changeset per record, which is how an action runs on one record. Any update or destroy action can run this way, atomic or not. |
| `batch_size: 1`, `transaction: :batch` | A transaction per record. A record that fails in the database does not take others with it. |
| `return_errors?: true`, `stop_on_error?: false` | Every record is tried, and each one's errors come back. |
| `return_records?: true` | The records the action ran on come back, which is how the table knows on which it did not. |
| `notify?: true` | The resource's notifiers hear of each record, as they do when the action runs on one. Ash's default for bulk actions is not to notify. |
| `actor`, `tenant` or `scope`, `authorize?` | As for every call of the table. |

Ash's atomic strategies run one statement over all records, and are not
used:

- an action that cannot be written as one statement would not run at all;
- a record that a policy refuses is left out without a word, or, with the
  other setting, fails every record with it;
- one record that a validation refuses fails all the others, and nothing
  says which record it was.

None of that is what a person expects who could run the action on each row
by itself. So a bulk action does to each record what the row's button does
to one, and costs a statement per record. A run on thousands of records
takes as long as that many updates take; the page stays in use meanwhile,
and its rows are dimmed until the run is over.

Ash is given the records and not the query that found them. A query is
read while its records are changed: "Archive" on all tasks that are "In
progress" would take each page out of the filter before the next is read,
and skip records.

## Afterwards

The table reads its page again, and says above the grid, under the line of
the buttons, what the action came to:

| What happened | The table says |
| --- | --- |
| It ran on every record | "Archive: 3 done." |
| It ran on some | "Archive: 2 done, 1 not done.", and after it each message of the action with the number of records it is about: "You are not allowed to do this. (1)" |
| It ran on none | "Archive: 0 done, 3 not done.", with the messages. |

The same is read out to screen readers, through the table's live region.

| A record was not done because | The message |
| --- | --- |
| A policy refuses the action on it | "You are not allowed to do this." |
| The action's validation refuses it | The action's message, with the field's column label when the person has a column for the field: "Progress: must be 100 when the task is done" |
| It was deleted, or the person can no longer read it, or it is no row of this table | "This record is no longer available." |
| Anything that is not of the action's making: a failure in the database, an error in a change | "This could not be done." The cause is in the server's log, not on the page. |

These are the messages of a row action that failed, counted. Several
messages about one record are one line, joined by a semicolon.

**The rows on which the action did not run stay selected**, and no others.
So what is left selected is what is left to deal with, on whatever page.
The result stays above the grid until the selection changes, the filters
change, or another bulk action runs. A sort and a change of page leave it.

A record that is gone, or not this person's to read, counts as not done. It
is not an error page, and it is not told apart from a record that never
existed.

**Try it:** `/tasks` as Max Member. Tick the box in the header and use
"Archive". The tasks that are neither assigned to him nor reported by him
are refused: "Archive: 2 done, 23 not done." (the numbers depend on the
page), "You are not allowed to do this. (23)", and 23 rows are still
selected.

As Ada Admin, select a task that is "Done" and one that is not, "Set
progress", 50: "Set progress: 1 done, 1 not done.", "Progress: must be 100
when the task is done (1)".

### Focus

| After | Focus is |
| --- | --- |
| A question answered with Cancel or Escape | On the button that asked. |
| A run that left rows selected | On the button that was used. |
| A run that left nothing selected | On the grid's current cell: the buttons are gone. |
| "Clear selection" | On the grid's current cell. |
| "Select all … that match" | On "Clear selection". |

## Who may run what

The table adds no rule. A bulk action is the row action, run on each record
as the person, and each record is read first as the person.

- **A person is never able to change in bulk what they could not change
  from its row.** The action's policies are asked for every record, and a
  record they refuse is not changed.
- **A person never changes a record they cannot read through the table.**
  Each record is read through the table's read action first: another
  tenant's record, a record the read policy hides and a record the read
  action's own filter leaves out are not found, by any key.
- **An action the person can never run has no button on the line**, as it
  has none in the rows. If that is every bulk action, the table has no
  boxes.
- **An attribute the person can never see is no field of the panel, and
  one they see on some records only is none either.** On one record the
  table knows whether they see it. Over a selection it does not, and does
  not read the records to find out.
- **Only `public?` actions run**, as everywhere in a table. See
  [Authorization](authorization.md#every-action-a-table-runs-is-public).

The demo's tasks say who may change which
([`demo/lib/demo/tracker/task.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/task.ex)):

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
policy action_type([:update, :destroy]) do
  description """
  Admins may run every action and viewers none (actor only). A member may
  change only the tasks they are assigned to or reported (record-dependent).
  """

  forbid_if actor_attribute_equals(:role, :viewer)
  authorize_if actor_attribute_equals(:role, :admin)
  authorize_if expr(assignee_id == ^actor(:id) or reporter_id == ^actor(:id))
end
```

| Actor on `/tasks` | Boxes | A bulk action |
| --- | --- | --- |
| Ada Admin | Yes | Runs on every selected task of Acme. |
| Max Member | Yes | Runs on the selected tasks he is assigned to or reported; the others are "not done". |
| Vera Viewer | No | Nothing to use; an event sent by other means runs nothing. |
| Olga Outsider | Yes | As the member, on Globex's tasks. A key of an Acme task names nothing for her. |
| Nobody | No | Nothing. |

## Nested tables

A nested table is the table of the destination resource, so it has that
table's boxes and bulk actions. Its selection is its own:

- Selecting in a nested table selects nothing in the table around it, and
  the other way round. Each has its own line and its own count.
- Its line is above its own grid, inside the row it is under.
- A bulk action in a nested table runs on the records under that row and
  on no others. The records are read through the row, as the nested table's
  rows are, so a key of a record that is not related to the row names
  nothing there, whoever may read that record elsewhere.
- "All that match" in a nested table are the records under its row that its
  own filters match. The same holds on the page a nested table's link leads
  to: a table limited to the records of one parent selects among those.
- Closing the line or the row takes the nested table away, with its
  selection.

**Try it:** `/tasks` as Ada Admin. Expand a row and open "Comments". The
comments have their own boxes; tick two and use "Destroy" on the line above
them.

## The keyboard

| Key | Where | Effect |
| --- | --- | --- |
| Space | On a cell of a row of records | Selects the row, or takes it out. |
| Space | On the cell of the box in the header | Selects the rows of the page, or takes them out. |
| Shift+Down Arrow, Shift+Up Arrow | On a cell of a row of records | Moves to the next or previous row of records and selects as it goes. What is open under a row is passed over. |
| Left Arrow | On the first data cell of a row | Moves to the row's expander, where rows expand, and from there to its box. Home goes to the box at once. Tab still enters the grid on the first column of the table. |
| Shift+Tab | On a cell of the grid | Leaves the grid backwards: to "Columns", then to the buttons of the line above the grid, the last first: the bulk actions, "Clear selection", "Select all … that match". |
| Enter, Space | On a button of the line | Uses it. |

When the question opens, focus moves to Cancel, Tab reaches Confirm, and
Escape is Cancel, whether it opens over the page or in it.

In a nested table the buttons of its line are tab stops as well, while that
table has a selection. Without one, the tree of grids is one tab stop.

All keys of a table are in
[Keyboard and accessibility](keyboard-and-accessibility.md).

## What assistive technology is told

| What | How |
| --- | --- |
| That rows can be selected | `aria-multiselectable="true"` on the grid. |
| Whether a row is selected | `aria-selected` on the row, `true` or `false`, on every row of records. |
| The box of a row | A checkbox named "Select row", in a cell of the grid that is counted in `aria-colcount` and `aria-colindex`. |
| The box of the page | A checkbox named "Select all rows of this page"; mixed when some rows of the page are selected. |
| The line above the grid | A group (`role="group"`) named "Selected rows". |
| The number of selected records | A live region in that group: "3 selected". |
| A run in progress | `aria-busy` on the grid; the buttons of the line are `aria-disabled`. |
| What a run came to | The table's live region: "Archive: 2 done, 1 not done. You are not allowed to do this. (1)". |

The mark of a selected row that a person sees is its ticked box. Rows have
no other mark, and no colour of their own.

## Edge cases

- **A selection can hold rows that are gone.** Another person deleted
  them, or the page was read again without them. They are counted until an
  action runs, which says "This record is no longer available." for each.
- **The count of "all that match" is the count of the last read.** What
  matches when the action runs is read then, and may be more or fewer.
- **With all that match selected, every row of the page is shown as
  selected**, a row that was just created at the top among them. Whether
  the action runs on it is whether it matches when the action runs.
- **One run at a time.** While a bulk action runs the buttons of the line
  do nothing, and the server refuses a second run of that table.
- **A run that the page does not live to see the end of stops.** It runs
  beside the page's process and ends with it. The records it had reached
  are changed, each in its own transaction; the others are not.
- **A new read closes the panel**, as for a row: the selection the panel
  was opened for is kept by the panel, not by the page.
- **A record that somebody else changed between its read and its turn** is
  run on as it was read. One that was deleted in between counts as no
  longer available.
- **A bulk action does not use `AshPhoenix.Form` for the run.** The panel's
  form collects and checks the inputs; the run is Ash's bulk action. An
  action's `require_atomic?` and `atomic_upgrade?` play no part in it.
- **A table inside your own LiveView** has its selection like any other.
  It is not in the page's URL either.

## Things people trip over

- **No boxes.** The table has no row action that this person can run on
  several rows; or its records have no primary key.
- **An action's button is in the rows and not on the line.** It says
  `bulk? false`, or it accepts a value that only one record can hold.
- **Expecting an empty field to leave a value alone.** It gives the action
  an empty value, for every record.
- **Expecting a field to show the selected records' value.** The fields of
  a selection start empty.
- **Expecting a bulk action to be one statement.** It is one per record.
  See [How Ash is asked](#how-ash-is-asked).
- **Expecting a filter change to keep the selection.** It gives it up. A
  sort and a change of page keep it.
- **Expecting Space to toggle a boolean.** Enter and F2 do. Space selects
  the row.
- **Expecting the question of `confirm false` to be skipped.** A bulk
  action always asks.
- **Expecting rows to be highlighted.** A selected row has a ticked box.

## Not in the first version

No selection across the tables of a page, no selection that survives a
reload, no inversion of a selection, no progress while a run is on its way
and no way to stop one, no undo, no bulk edit of cells, no bulk create, no
per-row inputs, and no export of the selected rows. The later slices are
listed in the
[specification](https://github.com/StefanRoesch/ash_data_table/issues/21).
