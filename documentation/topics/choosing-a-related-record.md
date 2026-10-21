# Choosing a related record

A reference cell shows the record a belongs-to relationship points at. A
person changes it by choosing a record from the related resource's own table,
in the picker, which opens over the page or in it. This guide covers which
reference cells are edited, what the picker shows and to whom, choosing by
pointer and keyboard, what a choice saves and never can, and which action
panel fields open the picker and which are typed.

Elsewhere:

- what a reference cell shows and how its label is read:
  [Nested tables](nested-tables.md#the-reference-cell);
- the rules of editing a cell: [Inline editing](inline-editing.md);
- the action panel: [Row actions and create](row-actions-and-create.md);
- choosing several records, and a reference cell whose action takes the
  related record through an argument:
  [Relationships an action manages](managing-relationships.md).

"Key" here means the relationship's foreign key: the attribute of this
resource that holds which record it points at (`assignee_id`). Ash calls it
the relationship's `source_attribute`.

## The smallest example

The picker itself needs no declaration. A reference column is edited when an
update action of the table accepts its key. The demo's tasks have three
reference columns, two of them edited
([`demo/lib/demo/tracker/task.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/task.ex)):

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
# A reference cell is edited where the column's update action accepts
# the relationship's foreign key: a person chooses the related record
# from that resource's own table, in the picker. `update` accepts
# `project_id` and `assignee_id`. Moving a task asks first.
column :project do
  confirm "Move this task to another project?"
end

column :assignee

# No update action accepts `reporter_id`: read-only.
column :reporter do
  label "Reported by"
end
```

The table's `update_action :update` saves them:

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
update :update do
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
    :completed_at,
    :external_ref,
    :project_id,
    :assignee_id,
    :tags,
    :checks,
    :recurrence
  ]
end
```

**Try it:** `/tasks` in the demo, as Ada Admin. Tab to an "Assignee" cell and
press Enter. A dialog opens at the right edge, headed "Assignee: choose user",
with the people's table. The assignee's row is selected and its radio button
has the focus. Press Down Arrow: the next row is selected. Use "Choose": the
dialog closes, the cell shows the new name, and focus is back on the cell.

## Which reference cells are edited

When all of this holds. The first four are the conditions of any editable
cell, applied to a relationship; the last four are about there being
something to choose from.

| | |
| --- | --- |
| An update action is behind the column | The column's own `update_action`, else the table's. `update_action false` on the column switches it off. |
| That action accepts the key | The relationship's `source_attribute` is in its `accept`. Not: the relationship's name. Or the action takes the related record through an argument: see [A reference cell that is edited through an argument](managing-relationships.md#a-reference-cell-that-is-edited-through-an-argument). |
| That action needs nothing else | No required argument without a default, as for any column. |
| The person may run it | One they can never run leaves the cell read-only for them. See [Authorization](authorization.md). |
| The key is a public, writable attribute | `attribute_public?` and `attribute_writable?` of the relationship. A public relationship has a public key unless it says otherwise. Not needed where the action takes the record through an argument. |
| The destination has a table | It lists `AshDataTable.Resource`. A reference column needs that anyway, for the label. |
| The relationship has no `filter` | See [Which records are offered](#which-records-are-offered). |
| The records can be read through a `public?` action | The relationship's own `read_action`, else the read action of the destination's table. |

Otherwise the cell is read-only: it shows the label and is no Tab stop. Under
the table's `update_action` that is not reported. A column's own
`update_action` that cannot save the column, and a `confirm` on a column
nobody edits, are reported at compile time; see
[Mistakes at compile time](mistakes-at-compile-time.md#a-column-that-names-a-relationship).

| Column of `/tasks` | Edited | Why |
| --- | --- | --- |
| Project | Yes, after a question | `update` accepts `project_id`. |
| Assignee | Yes | `update` accepts `assignee_id`. |
| Reported by | No | No update action accepts `reporter_id`: it is set when a task is created. |

## Opening the picker

| With | Effect |
| --- | --- |
| Enter or Space on the cell | Opens the picker. |
| A double click on the cell | Opens the picker. |
| A printable key on the cell | Nothing. There is nothing to type into. |

The picker opens as the table's [presentation](layout-and-embedding.md) says:

- **Over the page** (`:modal`, the default kit's choice): a modal dialog at
  the window's right edge, full height, like the action panel. The rest of the
  page cannot be used while it is open.
- **In the page** (`:inline`, set with `presentation: [picker: :inline]`): a
  part of the page. Focus moves into it and back to where it was opened from;
  the rest of the page stays in use.

Either way it is wider than the action panel, since it holds a table, and the
table scrolls sideways in it as on a page. It has:

- a heading naming the column's label and what one related record is called
  ("Assignee: choose user", "Project: choose project");
- the related resource's table;
- the buttons "Cancel", "None" where the key can be empty, and "Choose".

No picker is in the page until one is opened. Its table is rendered and read
when it opens.

A table attached with `controlled: [:picker]` draws no picker: it holds it as
a request, which the page draws and answers with `pick_request/4`. See
[Controlled mode](controlled-mode.md).

Focus moves into the table: to the row of the record the cell points at, when
that record is on the page shown, else to the first row. The table does not
look for the page that record is on.

## The table in the picker

It is the destination's default table (its `table` block, never one of its
[named tables](named-tables.md), whichever table opens the picker), as that
resource declares it: its columns and labels, filter row, sorting, pages, and
[argument line](arguments.md) where its read action takes arguments (in the
demo the tasks to choose from can be searched). A person filters and sorts
it as on its own page. Its state is its own: none of it is in the address,
and closing the picker forgets it.

It is a table to choose from and nothing else:

| On its own page | In the picker |
| --- | --- |
| Cells are edited | No cell is edited, whatever the table's `update_action`. |
| Row actions, the create button | None. |
| Boxes, and actions on the selected rows | A radio button per row: one row is selected at a time. |
| Rows expand into nested tables | They do not. |
| Its name is a heading above it | The picker's heading stands above it. Its table is named as the table is ("User", "Projects"). |

An event asking for anything in the left column in the picker's table is
refused, like an event naming a column nobody edits.

## Which records are offered

Those the destination's read action returns for this person: with their actor
and tenant, and authorization as a nested table has it (as the surrounding
table was told, else as the destination's own domain says). A record they may
not read is not in the picker; a destination field they never see is no
column of it.

Which read action follows the relationship, as for a nested table:

| The relationship | The picker reads through | Why |
| --- | --- | --- |
| Names no `read_action` | The read action of the destination's table (`read_action` in its block, else its primary read action) | The table in the picker is that table. |
| Names its own `read_action` | That action | It says which records the relationship means, and Ash loads the cell's label through it. A record it does not return could be saved and never shown. |
| Has a `filter` | Nothing: the cell is read-only, and a field of the action panel is a typed key | Which records such a relationship can hold is for Ash's loader to say, from the record the relationship starts at. Ash has no public way to ask it for the candidates. |

A multitenant destination changes none of this. The picker reads in the
person's tenant, like every table read, so another tenant's records are not
offered and cannot be chosen.

The library's tests have a relationship of each kind
([`test/support/picking.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/test/support/picking.ex)):

<!-- source: test/support/picking.ex -->
```elixir
# read through an action of its own, which the picker reads through too
belongs_to :relay, Depot do
  read_action :open
  public? true
end

# with a filter: a table cannot say which records it can hold
belongs_to :haven, Depot do
  filter expr(open? == true)
  public? true
end
```

The read action's pages are the picker's pages. A relationship's own action
need not support the pagination strategy the destination's block names: the
picker then uses what that action supports, and shows every record when it
declares no pagination.

## Choosing

Selecting a row and choosing it are two steps: selecting changes nothing,
"Choose" takes the selected row.

| With | Effect |
| --- | --- |
| A click anywhere on a row | Selects the row. |
| Space on a row's radio button | Selects the row. |
| "Choose" | Takes the row the picker's table holds as selected. It is not to be used while no row is selected (`aria-disabled`). |
| Enter on a row's radio button | Chooses that row at once: selects it, and takes it once the server holds it as selected. |
| A double click on a row | The same. |
| "None" | Chooses no record: the key is emptied. Only where the key can be empty (`allow_nil?`). |
| "Cancel", Escape | Closes the picker. Nothing is saved. |

One row is selected at a time. Selecting another replaces it; selecting the
selected row again leaves it selected, as a radio button does. The picker's
table holds the selection on the server, like every table (see
[Selecting rows](selecting-rows-and-bulk-actions.md#selecting)), and draws
"Choose" from it. "Choose", Enter and a double click take the row the server
holds as selected, only while that row is in view; nothing they send names a
row.

Why two steps: in a dialog, a person moving through the rows with a screen
reader or keyboard must be able to look at rows without changing the task.
Space selects in every table of the library and must not save. "Choose" is the
dialog's one action, and Enter on a row its shortcut, as in a file dialog.

**Try it:** `/tasks` as Ada Admin. Enter on a "Project" cell, click "Mobile
app" and use "Choose". The table's dialog asks "Move this task to another
project?" on top of the picker. Cancel returns to the picker with the row
still selected; Confirm saves.

## What a choice saves

A choice is a cell save, with the rules of
[Inline editing](inline-editing.md#what-a-save-does):

1. **The row's record is read again**, as the person, by its primary key.
2. **The chosen record is read**, as the person, by the key the browser named
   it by, through the read action the picker shows its rows through. See
   [Who may choose what](#who-may-choose-what).
3. **Choosing the record the cell already points at saves nothing.** The
   picker closes; no action runs.
4. **A column with `confirm` asks first** when the choice would change the
   row; the question stands on top of the picker.
5. **The column's update action runs with exactly one input**, the key,
   through `AshPhoenix.Form`. Its value is the chosen record's value of the
   relationship's `destination_attribute`; for "None" it is empty.
6. **The row is shown from what the action returns**, with the new record's
   label in the cell, and focus on the cell.

| What happened | The page |
| --- | --- |
| Saved | The picker closes; the cell shows the new label. |
| The action refused it (a validation, a policy) | The picker closes; the cell is marked as failed, shows what the chosen record is called, and holds the action's message. Escape on the cell gives it up. |
| The chosen record is none this person may read | The picker stays open and says "This record is no longer available." Nothing is saved. |
| The row's record is gone | The picker closes; the cell holds "This record is no longer available." |

**Try it:** `/tasks` as Max Member. Choose another assignee for a task neither
assigned to nor reported by him: the cell shows the chosen name, is marked,
and says "You are not allowed to change this."

## In the action panel

An action input that is such a key is given the same way, in the panel of a
row action, an action on the selected rows and the create action. The demo's
"Reassign" takes one
([`demo/lib/demo/tracker/task.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/task.ex)):

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
update :reassign do
  accept [:assignee_id]

  argument :reason, :string do
    allow_nil? false
    constraints min_length: 3, max_length: 200
  end

  change set_attribute(:internal_note, arg(:reason))
end
```

| The input | Its field |
| --- | --- |
| An attribute that is the key of a public belongs-to relationship whose related record can be chosen (the last four rows of [the first table](#which-reference-cells-are-edited)) | What the record is called, as plain text, and a button "Choose" that opens the picker. Empty while the field holds no key, and where it holds the key of a record this person may not read. |
| Any other key: its destination has no table, the relationship has a `filter` or is not public, or there is no relationship | A plain text field into which the key is typed. |
| An argument that holds a key and that no relationship explains, where the `action` of the block says which resource it refers to (`reference`) | The same field and the same picker, with the table of that resource. See [Table actions](table-actions.md#an-argument-that-holds-the-key-of-a-record). |

The field is named like the table's column of the relationship ("Assignee"),
else by the relationship's name in words. Where the table has a column for
the key itself, it takes that column's name ("Task ID" on `/comments`).

The record is called by its `label_field`, else by the first column of its
table that holds something this person may see on it, like the heading of a
[full view](nested-tables.md#the-heading).

The picker opens **on top of the panel** where pickers open over the page, and
**inside the panel** where they open in the page and the panel opens over it.
Either way the panel keeps everything typed into it. A choice puts the key
into the field and closes the picker; focus returns to the field's button.
Nothing runs until the panel's own button is used. Escape closes only the
picker.

"None" is offered where the action takes the input empty. A required field
says so in its label: a `*` and, for a screen reader, "required".

**Try it:** `/tasks` as Ada Admin, "New task". Type a title, use "Choose"
under "Project", double-click "Mobile app": the field reads "Mobile app" and
the title is still there. "Create".

## Who may choose what

The table adds no rule of its own. It reads as the person and treats what the
browser sends as a claim.

- **A person is offered the records they may read**, through the read action
  above, in their tenant. The destination's policies and field policies apply
  in the picker as on its own page.
- **A person saves the key of a record they may read, and no other.** The
  browser names the selected row by its primary key. The server reads the
  record by it, as the person, through the same read action, and saves that
  record's value. A key naming nothing they may read there (another tenant's
  record, one a policy hides, one the relationship's read action does not
  return, or no key at all) saves nothing, whatever event sent it.
- **The same holds for an action panel field.** When the panel's button is
  used, a key sent in such a field is looked up the same way before the
  action runs. One naming nothing the person could have chosen runs nothing,
  and the panel says so above its fields ("Assignee: This record is no longer
  available."). The key the record held when the panel opened is nobody's
  choice: it is passed back to the action unchanged, whether or not the person
  may read that record.
- **Whether the key may change at all is the action's to say.** A person who
  can never run the column's update action has no editor; one who may run it
  on some records only is told on the cell.
- **A person who can never read the destination through the picker's read
  action has no editor for the cell**, nor has one who can never see the key.
  Where they see the key on some records only, the cell is read-only on the
  others.
- **Only `public?` actions run**, as everywhere in a table. See
  [Authorization](authorization.md#every-action-a-table-runs-is-public).

A value typed into a plain key field is not looked up: the action gets it as
it is.

## Keys that are not one UUID

The picker names a row by the destination's primary key, whatever it is, and
saves the attribute the relationship names; the two may differ. In the demo's
tests a stop points at its zone by the zone's code, while a zone's primary key
is a country and a number; and at its bay by a number
([`demo/test/support/picker_tables.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/test/support/picker_tables.ex)):

<!-- source: demo/test/support/picker_tables.ex -->
```elixir
belongs_to :zone, Demo.Support.Route.Zone do
  source_attribute :zone_code
  destination_attribute :code
  attribute_type :string
  public? true
end

belongs_to :bay, Demo.Support.Route.Bay do
  source_attribute :bay_number
  destination_attribute :number
  attribute_type :integer
  read_action :free
  public? true
end
```

| | Zone | Bay |
| --- | --- | --- |
| A row of the picker is named by | Country and number | Number |
| A choice saves | The zone's `code`, into `zone_code` | The bay's `number`, into `bay_number` |
| The row selected as the picker opens | The zone whose `code` the stop holds | The bay whose `number` the stop holds |

A destination without a primary key has no rows to select, so its picker has
nothing to choose.

## The keyboard

| Key | Where | Effect |
| --- | --- | --- |
| Enter, Space | On a reference cell that is edited | Opens the picker. Focus goes to the radio button of the row chosen now, else of the first row. |
| Tab, Shift+Tab | In the picker | Through the table's stops, as in any table: "Skip table", the sort buttons, the filters, the radio buttons (one stop for the group), the pages; then the picker's buttons. Over the page it stays in the picker; in the page it goes on to the page after the last button. |
| Up and Down Arrow | On a row's radio button | The radio group's own keys: the next or the previous row is selected. They send nothing but what is selected. |
| Space | On a row's radio button | Selects the row. |
| Enter | On a row's radio button | Chooses the row, as "Choose" does. |
| Enter | In a filter's input | Applies the filter. |
| Escape | In a filter's input | Gives up what was typed. The picker stays open. |
| Escape | Anywhere else in the picker | Closes the picker. |
| Enter, Space | On "Cancel", "None", "Choose" | Uses the button. |

While a picker over the page is open, nothing outside it can be reached, by
Tab or pointer. When the picker closes, focus returns to where it was opened
from: the cell, or the "Choose" button of the panel's field.

All keys of a table are in
[Keyboard and accessibility](keyboard-and-accessibility.md).

## What assistive technology is told

| What | How |
| --- | --- |
| The picker | Over the page, a modal dialog; in the page, a region. Either is named by its heading. |
| Its table | A table (`role="table"`), named as the destination's table is. |
| Whether a row is selected | Its radio button is on. |
| The control of a row | A radio button named "Select row". The radio buttons of the table are one group (one `name`): one of a set. |
| That "Choose" has nothing to take yet | `aria-disabled="true"` on it. It is not `disabled`, so it keeps its place in the tab order. |
| A choice that was not taken | An alert in the picker (`role="alert"`), and the table's live region. |
| A save that failed | The cell, as for any cell: described by the action's message, which is read out. |
| A field of the panel that holds a key | A group named by the field's label, with what the record is called and the button "Choose", which is described by that text. |

axe-core reports no violations with the picker open, with a failed choice on
the cell, with the column's question on top of the picker, and with the
picker on top of the action panel, in light and dark theme. A screen reader
check is pending: see
[What has been tested](keyboard-and-accessibility.md#what-has-been-tested).

## Edge cases

- **The record the cell points at is not on the picker's page.** No row is
  selected and "Choose" has nothing to take. Filtering or paging to the
  record shows it selected, until the person selects another row.
- **A selected row no longer on the page shown** (after a filter, or on
  another page) is not taken either: "Choose" takes a row in view. It is
  selected again when it comes back into view.
- **A record the destination's table offers but its primary read action does
  not return.** Where the relationship names no `read_action`, Ash loads the
  cell's label through the primary read action, while the picker reads
  through the destination table's. If that returns more, a record can be
  saved and then not shown: the cell is empty. Give the relationship the
  `read_action` it means.
- **The record's label is hidden from the person on that record.** The cell
  shows "Not available" and is still edited: what decides is whether they see
  the key.
- **A new read of the table closes its picker**, as it closes its panel: a
  sort, filter or page change of the picker's table (from the page, where the
  picker is in the page) and a read the server starts.
- **The destination's read is refused while the page is open.** The picker
  opens and says "These records are not available.", or "You are not allowed
  to see these records." where the destination's table says
  `on_forbidden :message`. There is nothing to choose.
- **A choice in a nested table** is saved in the nested table. A task moved to
  another project from under its project stays in view until that table reads
  again.
- **`confirm` guards against slips**, as everywhere: an event saying it was
  confirmed is taken at its word.

## Things people trip over

- **A reference cell stays read-only.** No update action behind the column
  accepts the key or takes the record through an argument; or the key is not
  public or not writable; or the relationship has a `filter`. `reporter_id`
  on `/tasks` is the first case.
- **Accepting the relationship's name.** An action accepts attributes:
  `accept [:assignee_id]`, not `accept [:assignee]`.
- **Expecting to type a name.** The picker has no search box of its own; the
  filter row of its table is the search: Shift+Tab from the rows, or a click.
- **Expecting Space to choose, or a second click to deselect.** Space and a
  click select; see [Choosing](#choosing). "None" chooses no record.
- **A panel field that is still a typed key**, or **a field called "Task ID"
  that opens a picker**: see [In the action panel](#in-the-action-panel).
- **Expecting a picker for a relationship with a `filter`.** It does not open
  for one.

## Not in the first version

- type-ahead in the cell, or a search box besides the table's filters;
- creating a record from the picker;
- a picker for a relationship with a `filter`;
- going to the page of the record chosen now;
- a link from a reference cell to its record.

The later slices are in the
[specification](https://github.com/StefanRoesch/ash_data_table/issues/21).
