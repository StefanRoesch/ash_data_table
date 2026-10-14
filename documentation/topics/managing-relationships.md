# Relationships an action manages

An action can take the records of a relationship as an argument and hand
them to the relationship: `change manage_relationship(:labels, …)`. A table
lets a person give such an argument by choosing existing records from the
related resource's own table, in the picker: one record, or several. After
reading this guide you can say which arguments are chosen and which are
typed, predict what a field starts with, choose several records with the
pointer and from the keyboard, edit a reference cell through such an
argument, say what a choice can and cannot do to a relationship, and say
what a table leaves to a nested table.

The picker itself, for one record, is in
[Choosing a related record](choosing-a-related-record.md). The action panel
and its fields are in [Row actions and create](row-actions-and-create.md).

A table chooses **existing records only**. It has no form for a related
record that is to be created or changed with the action; an argument that
holds such records (a map, or a list of maps) is what it would be without
the change. A new related record is created in the
[nested table](nested-tables.md) of its relationship.

A note on words: "key" is the value a related record is named by. For an
argument that is the related resource's primary key, unless the change names
another attribute with `value_is_key`.

## The smallest example

Nothing is declared for the picker. The demo's tasks have an action that
takes a task's labels
([`demo/lib/demo/tracker/task.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/task.ex)):

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
# The argument holds the keys of labels, and the change hands them to
# the relationship: these labels and no others. A table lets a person
# choose them from the table of the labels.
update :set_labels do
  accept []
  require_atomic? false

  argument :labels, {:array, :uuid}, allow_nil?: false

  change manage_relationship(:labels, type: :append_and_remove)
end
```

and the table offers it as a row action:

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
# An argument that the action hands to a relationship: the panel lists
# the task's labels, and "Choose" opens the table of the labels, in which
# any number of them is selected.
action :set_labels
```

**Try it:** `/tasks` in the demo, as Ada Admin. Use "Set labels" in the
first row. The panel lists the task's labels under "Labels", each with a
button "✕" that takes it out, and has a button "Choose". Use it: a dialog
opens at the right edge, headed "Labels: choose label", with the table of
the labels, and the rows of the task's labels are selected. Select another
row, use "Choose": the label is listed in the panel. "Run" saves it.

## Which arguments are chosen

An argument is given by choosing when all of this holds. The first two are
about the argument, the others about there being something to choose from.

| | |
| --- | --- |
| A change of the action hands it to a relationship | The first `manage_relationship` change of the action that names the argument. This is how Ash's other interface extensions find it too. |
| It holds a key, or a list of keys | Its type is stored as the related resource's key is: `:uuid` for a UUID primary key, or `{:array, :uuid}`. Not: a map, a list of maps, text for a UUID key. |
| The related resource has one attribute to name a record by | Its primary key, where that is one attribute, else the attribute the change names with `value_is_key`. |
| The relationship is public, and is not manual | A table shows nothing of a relationship the resource keeps to itself, and Ash manages no manual one. |
| The change makes no record for a key | `on_no_match` is not `:create`. `type: :direct_control` and `type: :create` make a new record for a key that names none of the related ones, and a table chooses existing records only. |
| The destination has a table | It lists `AshDataTable.Resource`. Its table is what the picker shows. |
| The relationship has no `filter` | As for a reference cell. |
| The records can be read through a `public?` action | The relationship's own `read_action`, else the read action of the destination's table. |
| A list of keys is for a relationship of several records | A list for a belongs-to or a has-one is not chosen: there is one record to choose. |
| What is related now can be read through a `public?` action | Only where the field starts with the related records: see [What a field starts with](#what-a-field-starts-with). |

An argument for which one of these does not hold is the input it would be
without the change:

| The argument | Its field |
| --- | --- |
| One key whose records cannot be chosen | A plain text field into which the key is typed, as before. |
| A list of keys whose records cannot be chosen | None: a table has no field for a list of keys. An action that requires it is reported when the resource is compiled, with the reason; see [Mistakes at compile time](mistakes-at-compile-time.md#row-actions-and-the-create-action). |
| A map, or a list of maps: records to create or to change | None, unless the map declares its fields: then the group of fields a map has anywhere. A table creates no related record through it. |
| A list of text for a relationship whose key is a UUID | A list of text values, typed. |

What the change does with the keys does not decide whether they are chosen.
It decides what the field starts with.

The library's tests have an argument of each kind
([`test/support/managing.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/test/support/managing.ex)):

<!-- source: test/support/managing.ex -->
```elixir
# a list of keys that is added, under a name of its own
update :add_tags do
  require_atomic? false
  argument :add, {:array, :uuid}
  change manage_relationship(:add, :tags, type: :append)
end

# a list of keys that is taken away
update :drop_tags do
  require_atomic? false
  argument :drop, {:array, :uuid}
  change manage_relationship(:drop, :tags, type: :remove)
end

# one key into a relationship of many, added
update :tag do
  require_atomic? false
  argument :tag, :uuid, allow_nil?: false
  change manage_relationship(:tag, :tags, type: :append)
end
```

## The field

| The argument holds | Its field |
| --- | --- |
| One key | What the record is called, as plain text, and a button "Choose", as for a [key the action accepts](choosing-a-related-record.md#in-the-action-panel). Its picker selects one row, and offers "None" where the argument can be empty. |
| A list of keys | What each record is called, one under the other, each with a button "✕" that takes it out of the list; and under them a button "Choose". Its picker selects any number of rows. |

The field is called by the argument's name in words: "Labels" for `labels`,
"Add" for `add`. Name the argument for what a person gives.

A record is called as everywhere: by the `label_field` of its table, else
by the first column of its table that holds something this person may see
on it. A key the field holds of a record they may not read (the argument's
default, say, or a key that was sent by hand) is listed as "Not available".

**A field of several records is the server's to keep.** The list is
rendered from what the table holds for the open panel. The button of a
record sends one event and the list comes back without it, with focus on
what stands in its place: the next record's button, else the one before,
else "Choose". Nothing of the action runs.

**The list is given in every case.** As a field of an array does, it gives
the action a list: the keys of the records, and the empty list when there
are none. So it has no mark of a required field.

**An action with such an argument opens the panel**, whether the argument
is required or not: choosing the records is what the action is for. An
argument whose key is typed is an argument like any other, and an action
with nothing but optional ones runs when its button is used.

## What a field starts with

What the change does with a record that is left out decides it (`on_missing`
of `manage_relationship`):

| The change | A record that is left out | The field starts with |
| --- | --- | --- |
| `type: :append_and_remove` | Is unrelated | The records that are related now. |
| Its own options with `on_missing` set (`on_missing: :destroy`, say) | Is unrelated or destroyed, or refused | The records that are related now. |
| `type: :append` | Stays | Nothing. What is chosen is added. |
| `type: :remove` | Stays | Nothing. What is chosen is taken away. |

Where a record that is left out is acted on, the argument is everything the
relationship is to hold. A field that started empty would take every record
away, so it starts with them.

| Where | The field starts with |
| --- | --- |
| The panel of a row action | As above. |
| The panel of an action on the selected rows | Nothing, or the argument's default: there is no one record to take the related ones from. What is chosen is given to the action on every record. |
| The panel of the create action | The argument's default, where it has one that is not computed. |
| A field of one key for a relationship of several | The related record where there is exactly one, else nothing. |

**How the related records are read.** As Ash reads them when the action
runs: the relationship is loaded onto the row's record, for the same
person, through the relationship's own `read_action`, else through the
destination's primary read action. That is on purpose, and it is not the
read action of the picker's table:

- A record Ash will find related is in the field, whether the picker's
  table lists it or not. Its row cannot be seen there and counts as
  selected, so "Choose" leaves it in the list. Its own button takes it
  out, and so does "Clear selection" in the picker, which clears every
  row.
- A record this person may not read is not in the field, and Ash does not
  find it either when the action runs for them. It stays related. The demo
  has no such label; the tests have a skill that is secret
  ([`demo/test/support/relation_tables.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/test/support/relation_tables.ex)).

The table runs that read itself, so both read actions have to be
`public?`, and for a many-to-many the one of the join resource. Where one
is not, the argument is not chosen.

**Try it:** `/tasks` as Ada Admin, "Set labels" on a task with labels. Take
one out with "✕" and use "Run". Open the panel again: the label is gone.

## Choosing several records

The picker of a field that holds a list of keys is the picker of
[Choosing a related record](choosing-a-related-record.md#the-table-in-the-picker),
with these differences:

| For one record | For several |
| --- | --- |
| A radio button per row | A box per row, and one in the header for the rows of the page. |
| It opens with the row selected of the record the field holds, where that is on the page | It opens with the rows selected of every record the field holds, on whatever page they are. |
| "Choose" is not to be used while no row is selected | "Choose" is always to be used: no row selected is the choice of no record. |
| "None" where the field can be empty | No "None". |
| Enter on a row, and a double click, choose that row at once | Neither chooses: there is no one row to take. Space and a click select a row, and take it out again. |
| A row that a filter takes out of view is not taken | What is selected is taken, in view or not. |

Above its grid the table says how many rows are selected ("3 selected") and
has "Clear selection", as a table with boxes has on a page. A selection is
kept while the person filters, sorts and pages the picker's table: that is
how a record is found. "Select all that match" is not offered: it names no
rows.

"Choose" puts the selection into the field: the records it held whose rows
are still selected, in their order, and after them those that were selected
besides. "Cancel" and Escape close the picker and leave the field as it
was.

**Try it:** `/tasks` as Ada Admin, "Set labels", "Choose". Type into the
filter of "Name": the count above the grid stays. Select the row that is
left and use "Choose": the labels that the filter hid are still in the
list.

## A reference cell that is edited through an argument

A reference cell is edited when the column's update action accepts the
relationship's key, or when it has such an argument. The demo's deadlines
edit their assignee the second way
([`demo/lib/demo/tracker/deadline.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/deadline.ex)):

<!-- source: demo/lib/demo/tracker/deadline.ex -->
```elixir
# A reference cell that is edited through an argument: `hand_over` does
# not accept `assignee_id`, it takes the person as an argument and hands
# it to the relationship. The cell opens the picker all the same.
column :assignee do
  update_action :hand_over
end
```

<!-- source: demo/lib/demo/tracker/deadline.ex -->
```elixir
# The argument holds the key of a person, and the change hands it to
# the relationship: this person and no other. Empty, it takes the
# assignee away.
update :hand_over do
  accept []
  require_atomic? false

  argument :assignee, :uuid

  change manage_relationship(:assignee, type: :append_and_remove)
end
```

The table looks at the action behind the column (its own `update_action`,
else the table's) and takes the first way that holds:

1. **The action accepts the key**, and the key is a public, writable
   attribute. The choice is given as that attribute, as before.
2. **The action has an argument that hands one key to the column's
   relationship and relates the record it names** (`on_lookup`:
   `:append`, `:append_and_remove`). The choice is given as that argument.
   Where the action has several, the first in the action's order.

So an action that does both is given the key. Either way the action is
given one input and no other; an action that needs another argument cannot
serve a cell, and the argument the cell gives does not count as one.

| | Through the key | Through an argument |
| --- | --- | --- |
| What the action is given | The relationship's `source_attribute` | The argument |
| Its value | The chosen record's `destination_attribute` | The chosen record's key: its primary key, else `value_is_key` |
| The key has to be public and writable | Yes | No: nothing sets it from the outside. |
| "None" is offered | Where the key can be empty | Where the key can be empty, the argument can, and a record that is left out is unrelated (`:append_and_remove`). With `:append`, no record changes nothing, so it is not offered. |
| The row the picker opens with | The record the key points at | The same: read from the key. |

Everything else is the reference cell of
[Choosing a related record](choosing-a-related-record.md): Enter opens the
picker, a choice of the record the row already has runs nothing, a column
with `confirm` asks first, and a refused save marks the cell.

**Try it:** `/deadlines` as Ada Admin. Give "Due by" a day some weeks from
now. Press Enter on an "Assignee" cell: the picker opens on that person.
Choose another: the cell shows the new name. As Max Member, on a task that
is not his: the cell is marked and says "You are not allowed to change
this."

## Who may choose what

The table adds no rule of its own, as for one record.

- **A person is offered the records they may read**, through the picker's
  read action, in their tenant.
- **A row is a claim.** "Choose" sends the rows that are selected. A row of
  a record the field holds already is that record. Any other is read, as
  the person, through the picker's read action; one that names nothing they
  may read chooses nothing at all, and the picker says "This record is no
  longer available."
- **A key is a claim too.** When the panel's button is used, every key the
  form sends is looked up the same way before the action runs. One that
  names nothing they could have chosen runs nothing, and the panel says so
  above its fields ("Labels: This record is no longer available.").
- **What the record held when the panel is used is nobody's choice.** The
  keys of the records that are related now, read again as the person, are
  given back to the action as they are, where the argument is everything
  the relationship is to hold. An argument that adds or takes away holds
  nothing already: every key in it is looked up.
- **Whether the relationship may be changed is the action's to say**, and
  the policies of what it runs on the way: the join resource of a
  many-to-many, the destination of a has-many. A refusal leaves the panel
  open with "You are not allowed to do this.", and a cell marked.
- **What the action looks a record up through is the action's own**
  (`on_lookup`: the destination's primary read action, unless the change
  names another). The picker may offer a record that this action does not
  find. Ash then says that it was not found, and the field says "This
  record is no longer available."

**Try it:** `/tasks` as Max Member, "Set labels" on a task that is neither
assigned to him nor reported by him. The panel lists the labels; choose
another and use "Run": "You are not allowed to do this.", and the panel
stays open.

## On the selected rows, in a create, in a nested table

The field is a field of the action panel, wherever the panel is opened
from.

| Where | What is the same, and what is not |
| --- | --- |
| An action on the selected rows | The field starts empty. With `:append_and_remove`, every selected record is given exactly the records that are chosen: what each had before is taken away. With `:append` they are added to each. |
| The create action | The field starts with the argument's default. Every key is looked up. |
| A nested table | The same panel and the same picker, under the row. |
| A table action | A generic action has no changes, and so manages no relationship. Its key arguments are chosen in the picker where the `action` of the block says which resource they refer to (`reference`): see [Table actions](table-actions.md#an-argument-that-holds-the-key-of-a-record). |

**Try it:** `/tasks` as Ada Admin. Select two rows, use "Set labels" on the
line above the grid: the panel is headed "Set labels: 2 records" and its
field is empty. Choose a label, "Run", confirm: both tasks carry that label
and no other.

## The keyboard, and what assistive technology is told

| Key | Where | Effect |
| --- | --- | --- |
| Enter, Space | On the field's "Choose" | Opens the picker. |
| Enter, Space | On a record's "✕" | Takes the record out of the list. |
| Space | On a cell of a row of the picker | Selects the row, or takes it out. |
| Shift and Down Arrow, Up Arrow | On a row of the picker | Selects a range, as in any table with boxes. |
| Enter | On a row of the picker for several | Nothing. |
| Tab | In the picker | Leaves the grid for the buttons, and stays in the dialog. |
| Escape | In the picker | Closes the picker alone. |

| What | How |
| --- | --- |
| The field | A group named by its label (`role="group"`, `aria-labelledby`). |
| A record's button | Named by what it does to which record: "Remove ops". For a record that is called "Not available", by its place: "Remove Labels 2". |
| The picker's table | A grid that says `aria-multiselectable="true"`, with a box named "Select row" per row. |
| How many rows are selected | A status above the grid, read out when it changes. |

axe-core reports no violations with the panel open on such a field, with a
record taken out, and with the picker for several on top of the panel, in
the light and the dark theme; nor with a refused action shown in the panel.
No screen reader has been tried.

All keys of a table are in
[Keyboard and accessibility](keyboard-and-accessibility.md).

## Edge cases

- **The related records come in the order Ash loads them**: the
  relationship's own `sort`, else whatever the data layer gives.
- **A change that manages without authorization** (`authorize?: false` among
  its options) sees every related record, where the field shows the ones
  this person may read. What they could not see is then taken away with
  everything else that was left out. That is what such a change says, for
  every interface.
- **`type: :remove` offers every record of the destination**, not the
  related ones alone. Ash says of a record that is not related that it was
  not found, and the field shows it.
- **`type: :direct_control` is not chosen.** Under it Ash makes a new
  record for a key that names none of the related ones, and does not even
  keep the key. A list of keys under direct control has no field, and one
  key is typed. To keep some related records and destroy the others, give
  the change its own options: `on_lookup: :relate, on_no_match: :error,
  on_match: :ignore, on_missing: :destroy`.
- **Many related records are all in the field.** An argument that is
  everything a relationship holds is given every key, by any interface.
- **Each new key is read once when it is chosen and once when the action
  runs**, one read per key.
- **A relationship that two changes of one action manage** through two
  arguments has two fields. Each is looked at by itself.
- **A new read of the table closes the panel and its picker**, as always.

## Things people trip over

- **A list of keys with no field.** The relationship is not public, has a
  `filter`, or its destination has no table. Relationships are private
  unless they say `public? true`.
- **An argument of text for a UUID key.** It is typed. Declare it as the
  key's type.
- **Expecting "Add labels" to show the labels a task has.** `:append` adds:
  its field starts empty. Use `:append_and_remove` for a field that shows
  what is there.
- **Expecting a selection of rows to keep their own labels.** With
  `:append_and_remove` every selected record ends up with the same ones.
- **Expecting Enter on a row to choose it, where several are chosen.**
  Space selects; "Choose" takes.
- **A reference cell that stays read-only though its action has an
  argument.** The argument holds a list, or its change does not relate the
  record (`type: :remove`), or the action needs another argument. A
  column's own `update_action` says which when the resource is compiled.
- **`require_atomic? false`.** Ash asks for it on an update action with a
  `manage_relationship` change. That is Ash's, not the table's.

## Not in the first version

No form for a related record that is created or changed with the action, no
fields of the join resource of a many-to-many, no picker limited to the
records that are related now, no picker for a relationship with a `filter`,
no order the person gives the chosen records, and no editing of several
related records in a cell. The
later slices are listed in the
[specification](https://github.com/StefanRoesch/ash_data_table/issues/21).
