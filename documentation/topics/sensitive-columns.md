# Sensitive columns

A field that the resource declares `sensitive? true` gets a column whose
cells are masked. Each cell shows `••••••`, the same for every value, and a
"Show" button. The value itself is not in the page: the table asks the
server for it when a person uses the button, for that one cell. This guide
covers what a masked cell shows, how a value is shown and hidden again, how
such a cell is edited and emptied, and what a table no longer does with the
column.

Nothing is declared in the `table` block for this. The table follows what
the resource says.

**Sensitive is not hidden.** In Ash `sensitive?` keeps a value out of logs
and out of what `inspect` prints. It says nothing about who may read it.
Who may read a field is said by a field policy, as for every column: see
[Authorization](authorization.md). A person who may read the field may use
"Show".

Related: [Inline editing](inline-editing.md),
[Row actions and create](row-actions-and-create.md) for the action panel,
and [Keyboard and accessibility](keyboard-and-accessibility.md).

## The smallest example

The demo's projects have a budget
([`demo/lib/demo/tracker/project.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo/tracker/project.ex)):

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

**Try it:** open `/projects` in the demo as Max Member. Every project with a
budget shows `••••••` and "Show" in the "Budget" column. Use "Show" on one
row: the cell shows the number and the button says "Hide". Click another
cell: the number is gone again. "Mobile app" has no budget, and its cell is
empty. Then switch to Vera Viewer: the column is not there at all.

## What a masked cell shows

| The record | The cell |
| --- | --- |
| Has a value | `••••••` and a "Show" button |
| Has no value | Empty, with no button |
| Has a value that a field policy hides from the person | "Not available", as in every column |

The mask is always six dots. It does not follow the length of the value.

An empty cell says one thing: that there is no value. That is the only
thing a person learns about a sensitive value without asking.

The row is as high as every other row.

## Showing a value

- **With the pointer:** the "Show" button in the cell.
- **With the keyboard:** Shift+Enter on the cell.

The table then asks the server for this one cell. The server reads the
record again, as the person, and answers with the value. So the value shown
is the one the record has now.

The value is hidden again:

- when focus leaves the cell (another cell, Tab, a click elsewhere);
- with "Hide", with Shift+Enter again, or with Escape;
- when the table reads again (a sort, a filter, another page), and when the
  row is saved.

One cell at a time shows its value.

A screen reader hears "Hidden" for a masked cell, and the button is named
with the column: "Show Budget". The value is read out when it is shown.

## What is not in the page

Before somebody uses "Show", the value is not sent to the browser at all:

- not in the rows of the page, as it is first rendered or later;
- not in a patch after a sort, a filter, a save or an action;
- not in the URL, in a message of the table, or in what the table logs.

The server does not keep it either. A record that the table holds for a row
has every sensitive value replaced first.

After "Show" the value is in the browser, in that one cell, until it is
hidden.

## Editing

A sensitive cell is edited in place like any other, with two differences:

- **The editor hides what is typed.** It is a password input.
- **The editor starts empty.** It never holds the current value.

Enter saves what was typed. The cell shows its mask again, also while the
save is on its way and when the save fails. What was typed is not sent back
and not shown.

**An editor that is left empty saves nothing.** Enter on an empty editor
changes nothing, so a value is never emptied by accident. Emptying is asked
for by name: see [Emptying a value](#emptying-a-value).

Only text and numbers are edited this way, as a password input can hide
them. A sensitive column of another type (a yes or no, a date, a choice, a
list, a value made of fields) is read-only in the table. A row action can
still change it.

## In the action panel

An input of an action that is sensitive, an attribute or an argument, is a
password field too. The demo's test support has an action with both
([`demo/test/support/sensitive_tables.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/test/support/sensitive_tables.ex)):

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
- **A field that is left empty gives the action nothing.** An update keeps
  what the record has. A required argument that is left empty gets the
  action's own "is required".
- An attribute of an update action that has a value can be emptied with the
  button beside its field: see [Emptying a value](#emptying-a-value).
- A sensitive input that is not text or a number has no field. It is left
  out when the action runs without it. An action that requires it cannot be
  run from a table.

## Emptying a value

An empty editor means "no change", so nothing typed can say "no value". A
button says it: **"Clear"**. The demo's projects have a row action whose
one input is the budget
([`demo/lib/demo/tracker/project.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo/tracker/project.ex)):

<!-- source: demo/lib/demo/tracker/project.ex -->
```elixir
update :set_budget do
  accept [:budget]
end
```

**When "Clear" is offered.**

| | The editor of a cell | A field of the action panel |
| --- | --- | --- |
| The action takes the attribute without a value (`allow_nil?`, and not in the action's `require_attributes`) | needed | needed |
| The record has a value | needed: an empty cell has no button | needed |
| The action | the column's update action | an update action of a row. Not a create, not a destroy, not an action on the selected rows, and not an argument |

Nothing is declared for it.

**In the editor of a cell** the button stands after the input and is named
with the column: "Clear Budget".

- Using it empties the cell at once, as a save does. A column with
  `confirm` asks its question first.
- What was typed into the input is given up.
- The cell is then empty, with no mask and no button.

| Key | In the editor of a sensitive cell |
| --- | --- |
| Tab, from the input | Goes to "Clear". The editor stays open and nothing is saved. |
| Shift+Tab, from "Clear" | Goes back to the input, with what was typed. |
| Enter or Space, on "Clear" | Empties the cell. Focus is on the cell. |
| Escape, on "Clear" | Gives the edit up, as on the input. |
| Tab, from "Clear" | Leaves the grid and saves what was typed, as Tab from any editor does. An empty input saves nothing. |

A cell without a value has no "Clear": Tab from its input leaves the grid.

**In the action panel** the button stands under the field: "Clear", named
"Clear Budget".

- Using it changes nothing yet. The field says "Will be cleared." in place
  of its input, and the button says "Keep".
- "Keep" takes it back: the input is there again, empty.
- "Run" then runs the action with the attribute given without a value.
  Cancel runs nothing.

**The server decides.** "Clear" is an event of its own, and the panel keeps
what was asked for: it is never read from an empty input, and nothing a form
sends can ask for it. The record is read again, as the person, as for every
save. The action is the one to say no: its message is shown at the cell or
at the field, as for any save that fails. The value itself is still never
sent to the browser.

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

Calculations and aggregates can be `sensitive?` as well, and their columns
are masked the same way. They are never edited.

## Inside a value made of fields

An embedded resource can have a sensitive attribute. On the one line that a
cell shows of such a value, that field is a mask:

<!-- sketch -->
```text
Dial: left, Digits: ••••••
```

Such a field has no "Show" button. A value with a sensitive field that a
person would have to give is not edited in a table: its form would have to
hold what the mask hides. A value whose actions do not accept the sensitive
field is edited as usual, and the field keeps what it holds.

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
  again, so it shows the new value.
- **The record is gone when "Show" is used.** The cell says "This record is
  no longer available."
- **A field policy hides the value on some records.** Those cells say "Not
  available" and have no button. Asking for one all the same is answered
  with nothing.
- **A `false` is a value.** A sensitive yes or no that is "No" shows the
  mask, not an empty cell.
- **A new record** created from the panel has its mask at once.
- **A table without authorization** (`authorize?: false`) still masks.
- **In a picker and in a nested table** the column is masked as well.

## Things people trip over

- **"Sensitive" does not hide the column from anybody.** Add a field policy
  for that.
- **An empty editor does not empty the value.** It means "no change". Use
  "Clear" in the editor.
- **No "Clear" in the editor.** The cell has no value, or the column's
  action does not take the attribute without one.
- **The column lost its sort and its filter.** That is on purpose: both
  would give the values away.
- **A `sensitive?` date or yes/no is read-only.** A table can hide typing
  for text and numbers only.
- **What is typed in the action panel comes back to the same field** while
  the form is checked, as in every form, so that the browser does not lose
  it. The value the record had is never sent.
- **A value that is shown can be copied.** Showing is showing: the mask
  protects against a look over the shoulder, not against the person who may
  read the field.

## Not in the first version

- **Emptying a sensitive value on the selected rows**, and emptying a
  sensitive argument, which holds nothing between two runs.
- **Editing a sensitive date, choice, yes or no, or list in place.**
- **Editing a value made of fields that has a sensitive input.**
- **Showing every value of a column at once**, and showing a value for a
  set time.
- **A record of who asked for which value.** A resource that needs one
  writes it in its own read action.
- **A setting that switches the mask off for a column.** Take `sensitive?`
  off the field instead.

Further work on what a table offers is in the
[specification](https://github.com/StefanRoesch/ash_table/issues/21).
