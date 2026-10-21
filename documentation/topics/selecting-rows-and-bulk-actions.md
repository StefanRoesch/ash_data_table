# Selecting rows and bulk actions

A person can select rows and run one of the table's row actions on all of
them at once. A "bulk action" is a row action run on the selected rows:
the same action of the resource, not a second kind to declare. The actions
and the action panel are in [Row actions and create](row-actions-and-create.md);
who may do what in [Authorization](authorization.md).

## The smallest example

Nothing to declare: a table with a row action has the boxes, and every
row action is offered for a selection. The demo's tasks declare five; the
first four
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

**Try it:** `/tasks` as Ada Admin. Tick three boxes: the line above the
grid reads "3 selected", with "Clear selection", "Archive", "Reassign",
"Set progress", "Destroy" and "Set labels". "Archive" asks "Run “Archive”
on 3 records?". Confirm: the three rows read "Archived", nothing is
selected, and above the grid: "Archive: 3 done."

## Which tables have the boxes

A table has boxes when it has a row action that this person can ever run
and that runs on several rows. Otherwise it has no boxes and no line above
the grid.

| Demo page | As | Boxes |
| --- | --- | --- |
| `/tasks` | Ada Admin, Max Member, Olga Outsider | Yes: five actions. |
| `/tasks` | Vera Viewer, nobody | No: they can run no action. |
| `/projects` | Ada Admin, Max Member | Yes: "Set status". "Destroy" is kept to one row; see [Keeping an action to one row](#keeping-an-action-to-one-row). |
| `/comments`, `/task_labels` | Ada Admin, Max Member | Yes: "Destroy", and "Remove". |
| `/labels` | Ada Admin | Yes: "Destroy". |
| `/labels` | Max Member, Vera Viewer | No. |
| `/specimens` | anyone | No: the table has no row action. |

- The boxes are the grid's first column; where rows expand, the expander
  is the second cell and the table's first column the third.
- The box in the header stands for the rows of the page. The cell under it
  in the filter row is empty; Tab passes over it.
- Each box is a Tab stop.
- Records without a primary key give no boxes: a row that cannot be named
  cannot be told from another.
- A nested table has its own boxes, line and selection; see
  [Nested tables](#nested-tables).

## Selecting

| With | Effect |
| --- | --- |
| A click on a row's box, or beside it in its cell | Selects the row, or takes it out. |
| A click on the box in the header | Selects every row of the page; when all are selected, takes them out. |
| Shift and a click, anywhere on a row | Adds the rows from the one selected or clicked last to this one; takes nothing out. |
| Space, on a row's box | Selects the row, or takes it out. |
| Space, on the box in the header | As a click on that box. |

- No key selects a range. From the keyboard: Space on each box, the box in
  the header, or "Select all … that match".
- The box in the header is ticked when every row of the page is selected,
  and mixed (a dash) when some are.
- Space selects only on a box. On a button it uses it, in an input it
  types, on an editable cell it acts as Enter: starts editing with the
  value as it is, and toggles a boolean.
- The selection is held on the server. The box ticks in the browser at
  once; each change is sent to the server, which brings no row back but
  draws the line from what it holds, so the count and buttons follow a
  moment later.

**Try it:** `/tasks` as Ada Admin. Tab to a row's box, Space: "1
selected". Tab to the next box, Space: "2 selected".

## What is selected, and for how long

A selection is a set of records, remembered by their primary keys.

| When | The selection |
| --- | --- |
| Another page is opened | Stays, rows of the page left behind included; the count says so. |
| The table is sorted | Stays. |
| A filter is set, changed or cleared | Given up: the selected rows may no longer be among the rows. |
| An [argument](arguments.md) of the table is changed | Given up, likewise. "All that match" is what the filters match of what the read action returns for its arguments. |
| The record the table is limited to (`of`) changes | Given up, likewise. |
| A cell is saved, a row action runs on one row | Stays, less a row the action took away. |
| The page is reloaded, or left | Gone. It is not in the URL; the table holds it only while the page is open. |
| An action ran on it | The rows it did not run on stay selected; the others are taken out. |

The count on the line above the grid covers this page and the others, in
the plural forms of the page's language (see
[Messages and translations](messages-and-translations.md#counts-plural-forms)).
It is a live region: read out when it appears and whenever it changes;
focus stays where it is.

A page hears of a selection through the events `:selection_changed` and
`:bulk_ran`, and reads or clears it with the commands
`selected_records/2` and `clear_selection/2`: see
[Events and commands](events-and-commands.md).

## All that match

Once every row of the page is selected and the filters match more than
the page shows, the line offers "Select all 320 that match": every record
the table's read action returns for this person under the current filters,
on every page.

- The count then reads "All 320 that match are selected".
- This selection is not a list of rows but "whatever matches", worked out
  when an action runs: the server reads the records through the table's
  read action, with the filters, as the person.
- Taking one row out turns it back into a list: the other rows of this
  page stay selected, those of other pages no longer.
- The box in the header clears it.
- Where the read action does not count (`countable: false`), there is no
  number: the button reads "Select all that match", the count "All that
  match are selected". It is offered whenever there is another page.

**Try it:** `/tasks` as Ada Admin. Tick the header box: "25 selected" and
"Select all 320 that match". Use it, then filter "Title" by `email`: the
selection is given up.

## The line above the grid

The line is under the table's heading line. From the left:

| | Shown |
| --- | --- |
| The count: "1 selected", "3 selected", or "All 320 that match are selected" | While anything is selected. |
| "Select all 320 that match" | While every row of the page is selected and there is more than the page. |
| "Clear selection" | While anything is selected. |
| One button per bulk action, in the declared order; of more than three, the first two, and the others in a menu that "More" opens | While anything is selected. |

- An action that destroys has the error colour's outline.
- "Clear filters" is at the other end of the line.
- The line takes room only while something is on it: selected rows, a
  filter, or the [notice of changes](live-updates.md). No room is kept, on
  a table of its own or a nested one, so the grid moves down a line when
  the first row is selected. The count's live region is always there,
  empty and of no height while nothing is selected.
- The buttons are ordinary buttons in the page's tab order, right before
  the grid. "More" opens a menu (the browser's popover) whose buttons are
  Tab stops after it; a click elsewhere or Escape closes it, and an action
  used from it closes it with focus on "More".

## Which actions are offered

Every row action of the table that this person can ever run, except:

| The action | For a selection |
| --- | --- |
| A public update or destroy action declared with `action` | Offered. |
| A generic action declared with `record_argument` | Offered; runs once per selected record, given its key. See [Table actions](table-actions.md#a-generic-action-in-a-row). |
| A generic action without it: a table action | Never: it runs on no record. `bulk? true` on it is reported. |
| The same, declared with `bulk? false` | Not offered; stays a row action. |
| One that accepts an attribute of the primary key, or an attribute that is an identity by itself | Not offered; stays a row action. |
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

**Try it:** `/projects` as Ada Admin: each row has "Set status" and
"Destroy"; with two rows selected the line has "Set status" alone.

### Actions that cannot run on several rows

A bulk action's inputs are given once and applied to every record, so a
value only one record can hold cannot be given. An action that accepts
such an attribute is not offered for a selection:

- an attribute of the primary key;
- an attribute that is an identity by itself (`identity :unique_name,
  [:name]`).

An identity of several attributes is no reason: each of them can be the
same on many records. The demo has no such action; the library's tests do
([`test/support/acting.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/test/support/acting.ex),
`AshDataTable.Test.Acting.Sheet`).

`bulk? true` on such an action switches nothing on and is reported when
the resource is compiled. See
[Mistakes at compile time](mistakes-at-compile-time.md#row-actions-and-the-create-action).

## The question

Every bulk action asks first, with or without a `confirm`: one click must
not change a page of records. The question opens over the page or in it,
as the table's [presentation](layout-and-embedding.md) says. A table asks
one question at a time; a new one gives the open one up, as Cancel.

| The action | The question |
| --- | --- |
| Has no `confirm` | "Run “Archive” on 3 records?" |
| Has a `confirm` | Its own question, then the number: "Delete this task? This cannot be undone. 3 records are selected." |
| Says `confirm false` | As an action without one. |
| All that match are selected | The number is the total the table counted: "Run “Archive” on 320 records?" |
| All that match, and the read action does not count | "Run “Archive” on all records that match?" |

- The buttons are Cancel and Confirm; Confirm is in the error colour for a
  destroy action, as for a row.
- Cancel and Escape run nothing and put focus back on the button.
- For an action with inputs, the question is asked on top of the panel
  when "Run" is used.
- The number is worked out on the server when the button is used. Confirm
  runs the action on exactly the selection the question named.
- The page stays in use while the question is open. If the selection
  changed before Confirm, nothing runs, and the table says: "Nothing was
  run: the selection changed after the question was asked."

Like every question of a table, it guards against slips and is no check:
the server does not enforce it, and an event sent by other means can skip
it. Rules belong in the resource's policies. See [Confirm](confirm.md).

## Inputs

An action with inputs opens the action panel once, for the whole
selection. It is headed by the action and the number of records
("Reassign: 3 records"; "Reassign: all records that match" where the table
has no number) and has the fields of a row's panel, with these
differences:

| | In the panel of a row | In the panel of a selection |
| --- | --- | --- |
| An attribute starts with | The record's value | Nothing: there is no one record to take it from. Not the attribute's default either. |
| An argument starts with | Its default, when that is a fixed value | The same. |
| An argument that is everything a relationship is to hold starts with | The records that are related now | Nothing: what is chosen is given to every selected record, in place of what each had. See [Relationships an action manages](managing-relationships.md#on-the-selected-rows-in-a-create-in-a-nested-table). |
| A union starts with | The kind and the value the record holds | No kind, which is given to every selected record as no value. See [Unions](unions.md#in-the-action-panel). |
| A file | Is given to the action on this record | Is given to the action on every selected record: the same file each time. See [Files](files.md#on-the-selected-rows). |
| A field of an attribute the person sees on some records only | Is there where they see it on this record | Is never there. |
| What the fields hold | Is given to the action on this record | Is given to the action on every selected record. |

**An empty field is an empty value**, as in a row's panel, not "leave as
it is": on `/tasks`, "Reassign" with "Assignee ID" empty takes the
assignee off every selected task. An action for a selection should accept
what it is meant to change, and no more.

**Errors while typing** show at the fields. The form behind them is the
action's on a record that holds nothing, so it catches what depends on the
value alone: text that is no number, an argument too short, a required
input empty. Such an error after "Run" keeps the panel open and runs
nothing. What depends on the record (a validation that looks at another
field, a policy) is said after the run.

**Try it:** `/tasks` as Ada Admin. Select two rows, "Reassign", type `No`
into "Reason": "length must be greater than or equal to 3". Fix it, "Run":
the question, then "Reassign: 2 done."

## What running does

On the server, a bulk action is these steps:

1. **The action is looked up by name among those this table offers this
   person for a selection.** An event that names anything else runs
   nothing.
2. **The records are read**, as the person, in their tenant, through the
   table's read action, a hundred at a time. Named rows are read by their
   primary keys. For "all that match", the keys of everything the filters
   match are read first, before anything is changed.
3. **The action runs on each record read**, as the person, with
   authorization, through `Ash.bulk_update/4` or `Ash.bulk_destroy/4`. A
   generic action that takes a row's key has no bulk call in Ash: it runs
   once per record, as its row's button runs it.
4. **The table is read again** and says what the run came to.

Rows are not looked up on the page, since a selection outlives its page.
What the browser sends is a claim: a key naming nothing this person may
read through the table's read action is not run on, and counts as no
longer available.

### How Ash is asked

| Option | Why |
| --- | --- |
| `strategy: :stream` | One changeset per record, which is how an action runs on one record. Any update or destroy action can run this way, atomic or not. |
| `batch_size: 1`, `transaction: :batch` | A transaction per record. A record that fails in the database does not take others with it. |
| `return_errors?: true`, `stop_on_error?: false` | Every record is tried, and each one's errors come back. |
| `return_records?: true` | The records the action ran on come back, which is how the table knows on which it did not. |
| `notify?: true` | The resource's notifiers hear of each record, as they do when the action runs on one. Ash's default for bulk actions is not to notify. |
| `actor`, `tenant` or `scope`, `authorize?` | As for every call of the table. |

Ash's atomic strategies (one statement over all records) are not used:

- an action that cannot be written as one statement would not run at all;
- a record a policy refuses is left out silently or, with the other
  setting, fails every record with it;
- one record a validation refuses fails all the others, and nothing says
  which record it was.

So a bulk action does to each record what the row's button does to one,
at a statement per record: thousands of records take as long as that many
updates. The page stays in use meanwhile; its rows are dimmed until the
run is over.

Ash is given the records, not the query: a query is read while its
records change, so "Archive" on all tasks "In progress" would take each
page out of the filter before the next is read, and skip records.

## Afterwards

The table reads its page again and says, above the grid under the line of
the buttons, what the action came to:

| What happened | The table says |
| --- | --- |
| It ran on every record | "Archive: 3 done." |
| It ran on some | "Archive: 2 done, 1 not done.", then each message of the action with the number of records it is about: "You are not allowed to do this. (1)" |
| It ran on none | "Archive: 0 done, 3 not done.", with the messages. |

The same is read out to screen readers through the table's live region.

| A record was not done because | The message |
| --- | --- |
| A policy refuses the action on it | "You are not allowed to do this." |
| The action's validation refuses it | The action's message, with the field's column label when the person has a column for the field: "Progress: must be 100 when the task is done" |
| It was deleted, or the person can no longer read it, or it is no row of this table | "This record is no longer available." |
| Anything not of the action's making: a failure in the database, an error in a change | "This could not be done." The cause is in the server's log, not on the page. |

These are the messages of a failed row action, counted. Several messages
about one record are one line, joined by a semicolon.

- **The rows the action did not run on stay selected**, and no others: what
  is left selected is what is left to deal with, on whatever page.
- The result stays above the grid until the selection changes, the filters
  change, or another bulk action runs. A sort and a change of page leave
  it.
- A record that is gone, or not this person's to read, counts as not done.
  It is no error page, and is not told apart from a record that never
  existed.

**Try it:** `/tasks` as Max Member: header box, "Archive". Tasks neither
assigned to him nor reported by him are refused: "Archive: 2 done, 23 not
done." (numbers depend on the page), "You are not allowed to do this.
(23)", and 23 rows stay selected. As Ada Admin, select a "Done" task and
one that is not, "Set progress", 50: "Set progress: 1 done, 1 not done.",
"Progress: must be 100 when the task is done (1)".

### Focus

| After | Focus is |
| --- | --- |
| A question answered with Cancel or Escape | On the button that asked; for an action of the menu, on "More". |
| A run that left rows selected | On the button that was used, or "More". |
| A run that left nothing selected | On the table's first stop: the buttons are gone, and the line with them. |
| "Clear selection" | On the table's first stop. |
| "Select all … that match" | On "Clear selection". |

## Who may run what

The table adds no rule: each record is read, then changed, as the person.

- **Nothing changes in bulk that could not change from its row**: the
  action's policies are asked for every record.
- **No record changes that the person cannot read through the table**:
  another tenant's record, one the read policy hides and one the read
  action's own filter leaves out are not found, by any key.
- **An action the person can never run has no button** on the line or in
  the rows; if that is every bulk action, there are no boxes.
- **An attribute the person can never see, or sees on some records only,
  is no field of the panel.** Over a selection the table does not know
  whether they see it, and does not read the records to find out.
- **Only `public?` actions run.** See
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

A nested table is the table of the destination resource, with that
table's boxes and bulk actions, and a selection of its own:

- Selecting in a nested table selects nothing in the table around it, and
  the other way round. Each has its own line and count.
- Its line is above its own grid, inside the row it is under.
- A bulk action in it runs on the records under that row and no others.
  The records are read through the row, as its rows are, so a key of a
  record not related to the row names nothing there, whoever may read that
  record elsewhere.
- "All that match" are the records under its row that its own filters
  match. The same holds on the page a nested table's link leads to: a
  table limited to the records of one parent selects among those.
- Closing the line or the row takes the nested table away, with its
  selection.

**Try it:** `/tasks` as Ada Admin: expand a row, open "Comments", tick two
and use "Destroy" on their line.

## The keyboard

| Key | Where | Effect |
| --- | --- | --- |
| Tab, Shift+Tab | Anywhere | The boxes are Tab stops: the box in the header, then each row's box at the start of its row. The buttons of the line above the grid come before "Skip table": "Select all … that match", "Clear selection", the bulk actions or "More". |
| Space | On a box | As a click on it; see [Selecting](#selecting). |
| Enter, Space | On a button of the line | Uses it. |

- When the question opens, over the page or in it, focus moves to Cancel,
  Tab reaches Confirm, and Escape is Cancel.
- A nested table's boxes and line buttons are Tab stops in the same order,
  where the nested table stands.
- All keys of a table:
  [Keyboard and accessibility](keyboard-and-accessibility.md).

## What assistive technology is told

| What | How |
| --- | --- |
| Whether a row is selected | Its box is ticked. |
| The box of a row | A checkbox named "Select row", in the first column, which is counted in `aria-colcount` and `aria-colindex`. |
| The box of the page | A checkbox named "Select all rows of this page"; mixed when some rows of the page are selected. |
| The line above the grid | A group (`role="group"`) named "Selected rows". |
| The number of selected records | A live region in that group: "3 selected". |
| A run in progress | `aria-busy` on the grid; the buttons of the line are `aria-disabled`. |
| What a run came to | The table's live region: "Archive: 2 done, 1 not done. You are not allowed to do this. (1)". |

A selected row's only visible mark is its ticked box; rows have no colour
of their own.

## Edge cases

- **A selection can hold rows that are gone**: another person deleted
  them, or the page was read again without them. They are counted until an
  action runs, which says "This record is no longer available." for each.
- **The count of "all that match" is that of the last read.** What matches
  when the action runs is read then, and may be more or fewer.
- **With all that match selected, every row of the page shows as
  selected**, including a row just created at the top. The action runs on
  it if it matches when the action runs.
- **One run at a time.** While a bulk action runs, the line's buttons do
  nothing, and the server refuses a second run of that table.
- **A run goes on to its end when the page is left.** It runs beside the
  page's process and finishes when that process is gone or its table
  closes (a nested table that is folded); what it came to is shown to
  nobody. Stopped, it would stop in the middle of a record's statement. A
  started run cannot be cancelled.
- **A new read closes the panel**, as for a row: the panel, not the page,
  keeps the selection it was opened for.
- **A record somebody else changed between its read and its turn** is run
  on as it was read. One deleted in between counts as no longer available.
- **A bulk action does not use `AshPhoenix.Form` for the run.** The panel's
  form collects and checks the inputs; the run is Ash's bulk action. An
  action's `require_atomic?` and `atomic_upgrade?` play no part in it.
- **A table inside your own LiveView** has its selection like any other,
  and not in the page's URL either.

## Things people trip over

- **No boxes**: no row action this person can run on several rows, or no
  primary key.
- **A button in the rows but not on the line**: `bulk? false`, or the
  action accepts a value only one record can hold.
- **An empty field** gives every record an empty value; it does not leave
  the value alone.
- **The fields of a selection start empty**; they do not show the selected
  records' value.
- **A bulk action is one statement per record**, not one in all. See
  [How Ash is asked](#how-ash-is-asked).
- **A filter change gives up the selection**; a sort and a change of page
  keep it.
- **Space selects on the box only**; on an editable cell it acts as Enter.
- **`confirm false` does not skip the question**: a bulk action always
  asks.
- **Rows are not highlighted**: a selected row has a ticked box.

## Not in the first version

No selection across the tables of a page, no selection that survives a
reload, no inversion of a selection, no progress while a run is on its way
and no way to stop one, no undo, no bulk edit of cells, no bulk create, no
per-row inputs, and no export of the selected rows. The later slices are
listed in the
[specification](https://github.com/StefanRoesch/ash_data_table/issues/21).
