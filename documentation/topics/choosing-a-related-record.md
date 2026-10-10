# Choosing a related record

A reference cell shows the record a belongs-to relationship points at. A
person changes which record that is by choosing one from the related
resource's own table, in a dialog at the side of the window: the picker.
After reading this guide you can say which reference cells are edited and
which are not, predict what the picker shows and to whom, choose a record
with the pointer and from the keyboard, say what a choice saves and what it
never can, and tell the fields of the action panel that open the picker from
those that are typed.

What a reference cell shows, and how its label is read, is in
[Nested tables](nested-tables.md#the-reference-cell). The rules of editing
a cell are in [Inline editing](inline-editing.md), and the action panel in
[Row actions and create](row-actions-and-create.md).

A note on words: this guide says "key" for the foreign key of a
relationship, the attribute of this resource that holds which record it
points at (`assignee_id`). Ash calls it the relationship's
`source_attribute`.

## The smallest example

There is nothing to declare for the picker itself. A reference column is
edited when an update action of the table accepts its key. The demo's tasks
have three reference columns, of which two are edited
([`demo/lib/demo/tracker/task.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo/tracker/task.ex)):

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

The table's `update_action :update` is what saves them:

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
    :checks
  ]
end
```

**Try it:** `/tasks` in the demo, as Ada Admin. Move to a cell of
"Assignee" and press Enter. A dialog opens at the right edge, headed
"Assignee: choose user", with the table of the people in it. The row of the
task's assignee is selected. Press Down Arrow, then Space: another row is
selected. Use "Choose": the dialog closes, the cell shows the new name, and
focus is on the cell again.

## Which reference cells are edited

A reference cell is edited when all of this holds. The first four are the
conditions of any editable cell, said for a relationship; the last four are
about there being something to choose from.

| | |
| --- | --- |
| An update action is behind the column | The column's own `update_action`, else the table's. `update_action false` on the column switches it off. |
| That action accepts the key | The relationship's `source_attribute` is in its `accept`. Not: the relationship's name. |
| That action needs nothing else | No required argument without a default, as for any column. |
| The person may run it | One they can never run leaves the cell read-only for them. See [Authorization](authorization.md). |
| The key is a public, writable attribute | `attribute_public?` and `attribute_writable?` of the relationship. A public relationship has a public key unless it says otherwise. |
| The destination has a table | It lists `AshTable.Resource`. A reference column needs that anyway, for the label. |
| The relationship has no `filter` | See [Which records are offered](#which-records-are-offered). |
| The records can be read through a `public?` action | The relationship's own `read_action`, else the read action of the destination's table. |

A cell for which one of these does not hold stays read-only, as every
reference cell was before: it shows the label and says `aria-readonly`.
Under the table's `update_action` that is nothing to report. A column's own
`update_action` that cannot save the column, and a `confirm` on a column
nobody edits, are reported when the resource is compiled; see
[Mistakes at compile time](mistakes-at-compile-time.md#a-column-that-names-a-relationship).

| Column of `/tasks` | Edited | Why |
| --- | --- | --- |
| Project | Yes, after a question | `update` accepts `project_id`. |
| Assignee | Yes | `update` accepts `assignee_id`. |
| Reported by | No | No update action accepts `reporter_id`: it is set when a task is created. |

## Opening the picker

| With | Effect |
| --- | --- |
| Enter or F2 on the cell | Opens the picker. |
| A double click on the cell | Opens the picker. |
| A printable key on the cell | Nothing. There is nothing to type into. |

The picker is a second panel: a native modal `<dialog>` at the right edge of
the window, as high as the window, as the action panel is. It is wider than
the action panel (up to 48rem), because it holds a table, and the table
scrolls sideways in it as it does on a page. It has:

- a heading that says what is chosen for which column: the column's label,
  and what one record of the related resource is called ("Assignee: choose
  user", "Project: choose project");
- the table of the related resource;
- the buttons "Cancel", "None" where the key can be empty, and "Choose".

Nothing of a picker is in the page until one is opened. The table is
rendered when the picker opens, and read then.

Focus moves into the table: to the row of the record the cell points at
now, when that record is on the page shown, else to the first row. The
table does not go looking for the page that record is on.

## The table in the picker

It is the table of the destination resource as that resource declares it:
its columns and their labels, its filter row, its sorting and its pages. A
person filters and sorts it as they would on its own page. Its state is its
own: nothing of it is in the address, and closing the picker forgets it.

It is a table to choose from, and for nothing else:

| On its own page | In the picker |
| --- | --- |
| Cells are edited | No cell is edited, whatever the table's `update_action`. |
| Row actions, the create button | None. |
| Boxes, and actions on the selected rows | A radio button per row: one row is selected at a time. |
| Rows expand into nested tables | They do not. |
| Its name is a heading above it | The picker's heading stands above it. Its grid is named as the table is ("User", "Projects"). |

An event that asks for any of the left column in the picker's table is
refused, as an event is that names a column nobody edits.

## Which records are offered

Those the destination's read action returns for this person: with their
actor and tenant, and with authorization as a nested table has it (as the
table around it was told, else as the destination's own domain says). A
record they may not read is not in the picker, and a field of the
destination they never see is no column of it.

Which read action that is follows the relationship, as it does for a nested
table:

| The relationship | The picker reads through | Why |
| --- | --- | --- |
| Names no `read_action` | The read action of the destination's table (`read_action` in its block, else its primary read action) | The table in the picker is that table. |
| Names its own `read_action` | That action | It says which records the relationship means, and Ash loads the cell's label through it. A record it does not return could be saved and never shown. |
| Has a `filter` | Nothing: the cell is read-only, and a field of the action panel is a typed key | Which records such a relationship can hold is for Ash's loader to say, from the record the relationship starts at. Ash has no public way to ask it for the candidates. |

The destination being multitenant changes nothing in these rules. The
picker reads in the person's tenant, as every read of a table does, so the
records of another tenant are not on offer and cannot be chosen.

The library's tests have a relationship of each kind
([`test/support/picking.ex`](https://github.com/StefanRoesch/ash_table/blob/main/test/support/picking.ex)):

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

Selecting a row and choosing it are two steps. A row is selected in the
table, which changes nothing, and "Choose" takes the selected row.

| With | Effect |
| --- | --- |
| A click anywhere on a row | Selects the row. |
| Space on a cell of a row | Selects the row. |
| "Choose" | Takes the selected row. It is not to be used while no row is selected (`aria-disabled`). |
| Enter on a cell of a row | Chooses that row at once: selects it and takes it. |
| A double click on a row | The same. |
| "None" | Chooses no record: the key is emptied. Only where the key can be empty (`allow_nil?`). |
| "Cancel", Escape | Closes the picker. Nothing is saved. |

One row is selected at a time. Selecting another row takes the first one's
place, and selecting the selected row again leaves it selected, as a radio
button does. Selecting sends nothing to the server.

Why two steps: in a dialog, a person who moves through the rows with a
screen reader or the keyboard has to be able to look at a row, and at
another, without changing the task. Space is the key of selection in every
table of the library, and it must not save. "Choose" is the dialog's one
action, and Enter on a row is its shortcut, as in a file dialog.

**Try it:** `/tasks` as Ada Admin. Enter on a "Project" cell, then click
"Mobile app" and use "Choose". The table's dialog asks "Move this task to
another project?" on top of the picker. Cancel returns to the picker with
the row still selected; Confirm saves.

## What a choice saves

A choice is the save of a cell, with the rules of
[Inline editing](inline-editing.md#what-a-save-does):

1. **The row's record is read again**, as the person, by its primary key.
2. **The chosen record is read**, as the person, by the key the browser
   named it by and through the read action the picker shows its rows
   through. See [Who may choose what](#who-may-choose-what).
3. **The record the cell points at already saves nothing.** The picker
   closes, and no action runs.
4. **A column with `confirm` asks first**, once the choice would change the
   row: the question stands on top of the picker.
5. **The column's update action runs with exactly one input**, the key,
   through `AshPhoenix.Form`. Its value is the chosen record's value of the
   relationship's `destination_attribute`; for "None" it is empty.
6. **The row is shown from what the action returns**, with the label of the
   new record in the cell, and focus is on the cell.

| What happened | The page |
| --- | --- |
| Saved | The picker closes; the cell shows the new label. |
| The action refused it (a validation, a policy) | The picker closes; the cell is marked as failed, shows what the chosen record is called, and holds the action's message. Escape on the cell gives it up. |
| The chosen record is none this person may read | The picker stays open and says "This record is no longer available." Nothing is saved. |
| The row's record is gone | The picker closes; the cell holds "This record is no longer available." |

**Try it:** `/tasks` as Max Member. Choose another assignee for a task that
is neither assigned to him nor reported by him: the cell reads the chosen
name, is marked, and says "You are not allowed to change this."

## In the action panel

An input of an action that is such a key is given the same way: in the
panel of a row action, of an action on the selected rows, and of the create
action. The demo's "Reassign" takes one
([`demo/lib/demo/tracker/task.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo/tracker/task.ex)):

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
| Any other key: its destination has no table, the relationship has a `filter` or is not public, or there is no relationship | A plain text field into which the key is typed, as before. |

The field is called what the table's column of the relationship is called
("Assignee"), else by the relationship's name in words. Where the table has
a column for the key itself, it is called what that column is ("Task ID" on
`/comments`).

The record is called by its `label_field`, else by the first column of its
table that holds something this person may see on it, as the heading of a
[full view](nested-tables.md#the-heading) is.

The picker opens **on top of the panel**: both are modal dialogs, and the
panel stays as it is underneath, with everything that was typed into it. A
choice puts the key into the field and closes the picker; focus is on the
field's button again. Nothing runs until the panel's own button is used.
Escape closes the picker alone.

"None" is offered where the action takes the input empty. A field that is
required says so in its label, with a `*` and, for a screen reader, the
word "required".

**Try it:** `/tasks` as Ada Admin, "New task". Type a title, use "Choose"
under "Project", double-click "Mobile app": the field reads "Mobile app",
and the title is still there. "Create".

## Who may choose what

The table adds no rule of its own. It reads as the person, and what it is
told by the browser it takes as a claim.

- **A person is offered the records they may read**, through the read
  action above, in their tenant. The destination's policies and field
  policies apply to the picker's table as they do on its own page.
- **A person saves the key of a record they may read, and of no other.**
  The row the picker's hook sends is a primary key from the browser. The
  server reads the record by it, as the person, through the same read
  action, and saves that record's value. A key that names nothing they may
  read there (a record of another tenant, one a policy hides, one the
  relationship's read action does not return, or no key at all) saves
  nothing, by whatever event it was sent.
- **The same holds for a field of the action panel.** When the panel's
  button is used, a key that the form sends in such a field is looked up
  the same way before the action runs. One that names nothing the person
  could have chosen runs nothing, and the panel says so above its fields
  ("Assignee: This record is no longer available."). The key the record
  held when the panel opened is nobody's choice: it is given back to the
  action as it is, whether or not the person may read that record.
- **Whether the key may be changed at all is the action's to say.** A
  person who can never run the column's update action has no editor, and
  one who may run it on some records only is told on the cell.
- **A person who can never read the destination through the picker's read
  action has no editor for the cell.** Nor has one who can never see the
  key. Where they see the key on some records only, the cell is read-only
  on the others.
- **Only `public?` actions run**, as everywhere in a table. See
  [Authorization](authorization.md#every-action-a-table-runs-is-public).

A value that is typed into a plain key field is not looked up: the action
is given it, as before.

## Keys that are not one UUID

The picker names a row by the destination's primary key, whatever that is,
and saves the attribute the relationship names. The two need not be the
same. In the demo's tests a stop points at its zone by the zone's code,
while a zone's primary key is a country and a number; and at its bay by a
number
([`demo/test/support/picker_tables.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/test/support/picker_tables.ex)):

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

A destination without a primary key has no rows to select, and so its
picker has nothing to choose.

## The keyboard

| Key | Where | Effect |
| --- | --- | --- |
| Enter, F2 | On a reference cell that is edited | Opens the picker. |
| Arrow keys, Home, End, Page Up, Page Down | In the picker's grid | Move, as in any grid. They send nothing. |
| Space | On a cell of a row | Selects the row. |
| Enter | On a cell of a row | Chooses the row. |
| Enter | On a heading, on a filter cell | Sorts; goes into the filter. As in any grid. |
| Escape | In a filter of the picker's grid | Back to the filter's cell. The picker stays open. |
| Escape | Anywhere else in the picker | Closes the picker. |
| Tab | In the picker | Leaves the grid for the table's pages and the picker's buttons, and stays in the dialog. |
| Enter, Space | On "Cancel", "None", "Choose" | Uses the button. |

The grid in the picker is a grid like any other, with one tab stop. It is a
tree of grids of its own: while the dialog is open, nothing outside it can
be reached, by Tab or by the pointer.

When the picker closes, focus is back where it was opened from: on the
cell, or on the "Choose" button of the panel's field.

All keys of a table are in
[Keyboard and accessibility](keyboard-and-accessibility.md).

## What assistive technology is told

| What | How |
| --- | --- |
| The picker | A modal dialog (`<dialog>`, shown with `showModal`), named by its heading (`aria-labelledby`). |
| Its table | A grid, named as the destination's table is. |
| That one row is selected at a time | `aria-multiselectable="false"` on the grid. |
| Whether a row is selected | `aria-selected` on the row, `true` or `false`. |
| The control of a row | A radio button named "Select row". The radio buttons of the table are one group (one `name`): one of a set. |
| That "Choose" has nothing to take yet | `aria-disabled="true"` on it. It is not `disabled`, so it keeps its place in the tab order. |
| A choice that was not taken | An alert in the picker (`role="alert"`), and the table's live region. |
| A save that failed | The cell, as for any cell: `aria-invalid`, described by the action's message, which is read out. |
| A field of the panel that holds a key | A group named by the field's label, with what the record is called and the button "Choose", which is described by that text. |

axe-core reports no violations with the picker open, with a failed choice
shown on the cell, with the column's question on top of the picker, and
with the picker on top of the action panel, in the light and the dark
theme. No screen reader has been tried.

## Edge cases

- **The record the cell points at is not on the picker's page.** No row is
  selected, and "Choose" has nothing to take. Filtering or paging to the
  record shows it selected, until the person selects another row.
- **A row that was selected and is no longer on the page shown**, after a
  filter or on another page, is not taken either: "Choose" takes a row that
  is in view. It is selected again when it comes back into view.
- **A record that is offered by the destination's table and not returned by
  the destination's primary read action.** Where the relationship names no
  `read_action`, Ash loads the cell's label through the primary read action,
  and the picker reads through the one of the destination's table. A table
  whose read action returns more than the primary one offers records that
  are saved and then not shown: the cell is empty. Give the relationship
  the `read_action` it means.
- **The label of the record is hidden from the person on that record.** The
  cell shows "Not available", and is still edited: what decides is whether
  they see the key.
- **A new read of the table closes its picker**, as it closes its panel: a
  sort, a filter or a change of page while a picker is open is not possible
  from the page, as the dialog is modal, and a read that the server starts
  takes the picker away.
- **A read of the destination that is refused while the page is open.** The
  picker opens and says "These records are not available.", or "You are not
  allowed to see these records." where the destination's table says
  `on_forbidden :message`. There is nothing to choose.
- **A choice in a nested table** is saved in the nested table. A task that
  is moved to another project from under its project stays in view until
  that table reads again.
- **The question of `confirm` guards against slips**, as everywhere: an
  event that says it was confirmed is taken at its word.

## Things people trip over

- **A reference cell that stays read-only.** No update action behind the
  column accepts the key; or the key is not public or not writable; or the
  relationship has a `filter`. `reporter_id` on `/tasks` is the first case.
- **Accepting the relationship's name.** An action accepts attributes:
  `accept [:assignee_id]`, not `accept [:assignee]`.
- **Expecting to type a name.** The picker has no search box of its own. The
  filter row of the table in it is the search: Up Arrow from the first row,
  or a click.
- **Expecting Space to choose.** Space selects. "Choose", or Enter on the
  row, chooses.
- **Expecting a second click on the selected row to take it out.** It stays
  selected. "None" chooses no record.
- **A field of the panel that is still a typed key.** The destination has no
  table, or the relationship is not public, has a `filter`, or does not
  exist: the attribute is a key by name only.
- **A field called "Task ID" that opens a picker.** The table has a column
  for the key itself, and the field is called what that column is.
- **Expecting the picker to show what the cell's relationship can hold when
  it has a `filter`.** It does not open for such a relationship.

## Not in the first version

No type-ahead in the cell, no search box besides the table's filters, no
choosing several records, no relationship managed through an argument
(`manage_relationship`), no creating a record from the picker, no picker
for a relationship with a `filter`, no going to the page of the record that
is chosen now, and no link from a reference cell to its record. The later
slices are listed in the
[specification](https://github.com/StefanRoesch/ash_table/issues/21).
