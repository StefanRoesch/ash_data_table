# Sensitive columns

A field the resource declares `sensitive? true` gets a masked column. Each
cell shows `••••••`, the same for every value, and a "Show" button. The value
is not in the page: the server sends it for that one cell when a person uses
the button. Nothing is declared in the `table` block; the table follows the
resource.

**Sensitive is not hidden.** In Ash `sensitive?` keeps a value out of logs
and `inspect` output; it says nothing about who may read it. That is a field
policy, as for every column (see [Authorization](authorization.md)). A
person who may read the field may use "Show".

Related: [Inline editing](inline-editing.md),
[Row actions and create](row-actions-and-create.md) for the action panel,
and [Keyboard and accessibility](keyboard-and-accessibility.md).

## The smallest example

The demo's projects have a budget
([`demo/lib/demo/tracker/project.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/project.ex)):

<!-- source: demo/lib/demo/tracker/project.ex -->
```elixir
# Sensitive: its cells are masked ("••••••") until somebody asks for
# one, and the table neither sorts nor filters by it.
attribute :budget, :decimal do
  public? true
  sensitive? true
  constraints min: 0
end
```

Who may see it is a separate rule, a field policy:

<!-- source: demo/lib/demo/tracker/project.ex -->
```elixir
field_policy :budget do
  authorize_if actor_attribute_equals(:role, :admin)
  authorize_if actor_attribute_equals(:role, :member)
end
```

**Try it:** open `/projects` in the demo as Max Member. Each project with a
budget shows `••••••` and "Show" under "Budget". "Show" on one row shows the
number and the button says "Hide"; click another cell and it is gone.
"Mobile app" has no budget, so its cell is empty. As Vera Viewer the column
is not there at all.

## What a masked cell shows

| The record | The cell |
| --- | --- |
| Has a value | `••••••` and a "Show" button |
| Has no value | Empty, with no button |
| Has a value that a field policy hides from the person | "Not available", as in every column |

- The mask is always six dots, whatever the value's length.
- An empty cell says only that there is no value: the one thing a person
  learns without asking.
- The row is as high as every other row.

## Showing a value

- **Pointer:** the "Show" button in the cell.
- **Keyboard:** Enter or Space on "Show" (a Tab stop, in a read-only cell
  too), or Shift+Enter on an editable cell.

The server reads the record again, as the person, and answers with the
value, so it is the record's current one.

The value is hidden again:

- when focus leaves the cell (Tab, a click elsewhere);
- with "Hide", Shift+Enter again, or Escape on the cell or its button;
- when the table reads again (a sort, a filter, another page), and when the
  row is saved.

One cell at a time shows its value. A screen reader hears "Hidden" for a
masked cell; the button is named with the column ("Show Budget"); the value
is read out when shown.

## What is not in the page

Before "Show", the value is not sent to the browser:

- not in the rows of the page, first rendered or later;
- not in a patch after a sort, a filter, a save or an action;
- not in the URL, a message of the table, or the table's logs;
- not in what the table tells the page: a record in an event, and in
  `AshDataTable.selected_records/2`, holds `%AshDataTable.Sensitive.Masked{}`
  for each sensitive value, and event arguments leave sensitive ones out
  (see [Events and commands](events-and-commands.md)). A page that needs the
  value reads the record itself.

The server does not keep it either: a record the table holds for a row has
every sensitive value replaced first. After "Show" the value is in the
browser, in that one cell, until hidden.

## Editing

A sensitive cell is edited in place like any other, except:

- **The editor hides what is typed** (a password input in the default kit).
- **The editor starts empty.** It never holds the current value.

Enter saves. The cell shows its mask again, also while the save is on its
way and when it fails. What was typed is not sent back or shown: a failed
save's message stands in the cell under the mask, and the cell keeps nothing
of the typed text. Enter opens the editor empty again.

**An editor left empty saves nothing**, so a value is never emptied by
accident. Emptying is asked for by name: see
[Emptying a value](#emptying-a-value).

Only text and numbers are edited this way, as a password input can hide
them. A sensitive column of another type (yes or no, date, choice, list,
value made of fields) is read-only in the table; a row action can still
change it.

## In the action panel

A sensitive input of an action, attribute or argument, is a password field
too. The demo's test support has an action with both
([`demo/test/support/sensitive_tables.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/test/support/sensitive_tables.ex)):

<!-- source: demo/test/support/sensitive_tables.ex -->
```elixir
# a sensitive attribute and a sensitive argument, beside a plain one
update :rotate do
  require_atomic? false
  accept [:token]
  argument :passphrase, :string, sensitive?: true, allow_nil?: false
  argument :note, :string, constraints: [max_length: 50]

  # ...
end
```

- The field starts empty, also for an attribute that has a value.
- **A field left empty gives the action nothing.** An update keeps what the
  record has; a required argument left empty gets the action's own "is
  required".
- An attribute of an update action that has a value can be emptied with the
  button beside its field: see [Emptying a value](#emptying-a-value).
- A sensitive input that is not text or a number has no field. The action
  runs without it; an action that requires it cannot be run from a table.

## Emptying a value

An empty editor means "no change", so a button says "no value":
**"Clear"**. The demo's projects have a row action whose one input is the
budget
([`demo/lib/demo/tracker/project.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/project.ex)):

<!-- source: demo/lib/demo/tracker/project.ex -->
```elixir
update :set_budget do
  accept [:budget]
end
```

**When "Clear" is offered** (nothing is declared for it):

| | The editor of a cell | A field of the action panel |
| --- | --- | --- |
| The action takes the attribute without a value (`allow_nil?`, and not in the action's `require_attributes`) | needed | needed |
| The record has a value | needed: an empty cell has no button | needed |
| The action | the column's update action | an update action of a row. Not a create, not a destroy, not an action on the selected rows, and not an argument |

**In the editor of a cell** the button stands after the input, named with
the column ("Clear Budget").

- It empties the cell at once, as a save does. A column with `confirm` asks
  its question first.
- What was typed is given up.
- The cell is then empty, with no mask and no button.

| Key | In the editor of a sensitive cell |
| --- | --- |
| Tab, from the input | Goes to "Clear". The editor stays open and nothing is saved. |
| Shift+Tab, from "Clear" | Goes back to the input, with what was typed. |
| Enter or Space, on "Clear" | Empties the cell. Focus is on the cell. |
| Escape, on "Clear" | Gives the edit up, as on the input. |
| Tab, from "Clear" | Saves what was typed and goes on to the next stop, as Tab from any editor does. An empty input saves nothing. |

A cell without a value has no "Clear": Tab from its input saves and goes on.

**In the action panel** the button stands under the field: "Clear", named
"Clear Budget".

- It changes nothing yet. The field shows "Will be cleared." in place of its
  input, and the button becomes "Keep".
- "Keep" takes it back: the input returns, empty.
- "Run" runs the action with the attribute given without a value. Cancel
  runs nothing.

**The server decides.** "Clear" is an event of its own and the panel keeps
what was asked for: it is never read from an empty input, and nothing a form
sends can ask for it. The record is read again, as the person, as for every
save. The action may say no; its message is shown at the cell or field, as
for any failed save. The value is still never sent to the browser.

**Try it:** `/projects` as Max Member. Press Enter on a budget, then Tab and
Enter: the cell is empty. On another row use "Set budget", then "Clear" and
"Run".

## What a table does not do with a sensitive column

| | Why |
| --- | --- |
| Sort by it | The order of the rows would say which value is larger |
| Filter by it | Which rows are left would say what the value is |
| Use a `component` on it | A component would be given the value to show |
| Use it as `label_field` | A label is shown wherever a record is named |
| Ask for a sensitive argument on the argument line | The line's values are kept in the URL |

A URL that sorts or filters by a sensitive column is not followed.

Calculations and aggregates can be `sensitive?` too; their columns are
masked the same way and are never edited.

## Inside a value made of fields

An embedded resource can have a sensitive attribute. On the one line a cell
shows of such a value, that field is a mask:

<!-- sketch -->
```text
Dial: left, Digits: ••••••
```

- Such a field has no "Show" button.
- A value with a sensitive field the person would have to give is not
  edited in a table: its form would have to hold what the mask hides.
- A value whose actions do not accept the sensitive field is edited as
  usual, and the field keeps what it holds.

## Mistakes the compiler reports

| Mistake | Where it is reported |
| --- | --- |
| A `component` on a sensitive column | at its `component` |
| A sensitive attribute as `label_field` | at `label_field`, and at a column that would show it |
| `sortable? true` or `filterable? true` on a sensitive column | at the option |
| A column's own `update_action` on a sensitive column that is not text or a number | at its `update_action` |
| An action that requires a sensitive input that is not text or a number | at the `action` |
| A read action that requires a sensitive argument | at `read_action` |
| An `ask` for a sensitive argument of a calculation | at the `ask` |

See [Mistakes at compile time](mistakes-at-compile-time.md#sensitive-fields).

## Edge cases

- **The value changed since the page was read.** "Show" reads the record
  again and shows the new value.
- **The record is gone when "Show" is used.** The cell says "This record is
  no longer available."
- **A field policy hides the value on some records.** Those cells say "Not
  available" and have no button; asking anyway is answered with nothing.
- **`false` is a value.** A sensitive yes or no that is "No" shows the mask,
  not an empty cell.
- **A new record** created from the panel has its mask at once.
- **A table without authorization** (`authorize?: false`) still masks.
- **Pickers and nested tables** mask the column too.

## Things people trip over

- **"Sensitive" hides the column from nobody.** Add a field policy for that.
- **An empty editor does not empty the value.** It means "no change"; use
  "Clear".
- **No "Clear" in the editor.** The cell has no value, or the column's
  action does not take the attribute without one.
- **The column lost its sort and filter.** On purpose: both would give the
  values away.
- **A `sensitive?` date or yes/no is read-only.** A table can hide typing
  for text and numbers only.
- **What is typed in the action panel comes back to the same field** while
  the form is checked, as in every form, so the browser does not lose it.
  The record's value is never sent.
- **A shown value can be copied.** The mask protects against a look over the
  shoulder, not against a person who may read the field.

## Not in the first version

- **Emptying a sensitive value on the selected rows**, and emptying a
  sensitive argument, which holds nothing between two runs.
- **Editing a sensitive date, choice, yes or no, or list in place.**
- **Editing a value made of fields that has a sensitive input.**
- **Showing every value of a column at once**, or for a set time.
- **A record of who asked for which value.** A resource that needs one
  writes it in its own read action.
- **A setting that switches the mask off for a column.** Take `sensitive?`
  off the field instead.

Further work is in the
[specification](https://github.com/StefanRoesch/ash_data_table/issues/21).
