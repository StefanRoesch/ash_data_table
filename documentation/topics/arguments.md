# Arguments

This guide covers a table over a read action that takes arguments, a
calculation with arguments as a column (fixed by you or asked from the
person), and what the table does while an argument is missing or wrong.

## The smallest example

A read action with an argument needs nothing in the `table` block. The demo's
tasks are read through an action that takes a search term
([`demo/lib/demo/tracker/task.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/task.ex)):

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
read :read do
  primary? true

  # case-insensitive, as a `:ci_string` compares; its input counts
  # what is typed, as every text with a `max_length` does
  argument :search, :ci_string, constraints: [max_length: 60]

  filter expr(
           is_nil(^arg(:search)) or contains(title, ^arg(:search)) or
             contains(description, ^arg(:search))
         )
  # ...
end
```

The tasks table gets the **argument line**: one input for `search`, labelled
"Search", on the table's heading line after its name and "Columns". A nested
table's inputs stand on the line that opens it.

**Try it:** `/tasks` in the demo, as Ada Admin. Type `login` into "Search"
and press Enter: the rows are the tasks with "login" in title or description,
the line under the table counts them, and the address is
`/tasks?task[a][search]=login`.

## The arguments of the read action

Every `public?` argument of the table's read action gets an input on the
argument line, in the action's order. Nothing is declared.

| The argument | Its input |
| --- | --- |
| a string, a ci_string | a text input, of one line |
| an integer, a float, a decimal | a number input |
| a boolean | a box |
| a date, a datetime | the browser's date and datetime inputs |
| an enum, an `:atom` with `one_of` | a menu of its values, with their labels |
| an array of enum values | a box per value |
| an array of text, numbers, dates or datetimes | an input per value, with a button that adds one and one each that takes it away |
| a UUID, a time, and what else is written as one line of text | a text input |

- The input's label is the argument's name in words ("Search"), translated
  like a column label (see
  [Messages and translations](messages-and-translations.md)). An `argument`
  in the block only changes the label.
- An input starts with the argument's default in the action, where that is a
  value. An unticked box gives `false`.
- An `allow_nil? false` argument is marked with `*` and `aria-required`, like
  a required field of the action panel.
- A text argument with a `max_length` has a counter after its input ("5/60")
  that follows typing. See
  [Inline editing](inline-editing.md#the-counter-of-a-text).
- A `public? false` argument is never on the line and never given.
- An optional argument of a type without an input (a map, a union, a file) is
  left out. A read action that *requires* one cannot be behind a table: the
  compiler says so.

The demo's deadlines are the tasks due by a day, read through an action with
three arguments
([`demo/lib/demo/tracker/deadline.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/deadline.ex)):

<!-- source: demo/lib/demo/tracker/deadline.ex -->
```elixir
read :due do
  # the table cannot read without it
  argument :by, :date, allow_nil?: false
  # has a default, which its input starts with
  argument :include_done?, :boolean, allow_nil?: false, default: false
  # a list, given value by value: the tasks that have one of these tags
  argument :tags, {:array, :string}
  # ...
end
```

Its block names that action and relabels one argument:

<!-- source: demo/lib/demo/tracker/deadline.ex -->
```elixir
table do
  # Requires `by`: until a person has given it, the table says "Fill in Due
  # by to see records." in place of its rows.
  read_action :due

  # What an argument of the read action is called. Without this it is its
  # name in words: "By".
  argument :by do
    label "Due by"
  end
  # ...
end
```

## When an argument is applied

Like a filter: when its input is left or Enter is pressed in it; a choice, a
box and a list's buttons apply at once. There is no button that runs the
line, and typing sends nothing.

The arguments are table state, with the sort and filters:

- a table with its state in the address (the router page, a tag given `url`,
  a table attached with `url: true`) keeps them there, so the page can be
  reloaded, linked and stepped back through (see
  [State in the URL](state-in-the-url.md));
- a table that keeps its state itself (a tag without `url`, a table attached
  without `url: true`, a nested table, a picker) keeps them itself.

| In the address | Example |
| --- | --- |
| An argument of the read action | `task[a][search]=login` |
| An argument a column asks for | `task[c][due_within][days]=14` |
| A list | `deadline[a][tags][]=api&deadline[a][tags][]=mobile` |
| A list that was emptied, where its default is not empty | `deadline[a][tags]=` |

An argument whose input shows nothing chosen is not in the address: the
action's default is left to the action.

Changing an argument returns to the first page, keeps sort and filters, is
announced like a filter change ("12 results"), and clears the row selection.

## A required argument

Ash decides whether an argument may be left out: it reports a missing
`allow_nil? false` argument and applies a `default`. The table adds no rule.

While such an argument is empty the read action is **not run**. In place of
the rows the table names the argument to fill in:

<!-- sketch -->
```text
Fill in Due by to see records.
```

This is neither an error nor "No records", and it is announced. The grid
keeps its header and filter row; there are no pages and no create button
until the table has read.

**Try it:** `/deadlines`: give "Due by" a day and the rows appear, with the
day in the address. Empty it again: the rows go.

A person who can never run the read action is not asked to fill anything in.
Ash is asked first, without a read, and the person is answered as for a
refused read: a page that does not exist, or the `on_forbidden :message`
message (see [Authorization](authorization.md)).

## A value Ash refuses

What a person types goes to the action as typed, and Ash casts it. A value
that does not fit the argument's type or constraints is not applied:

- it stays in its input, marked `aria-invalid` and described by the action's
  message ("must be greater than or equal to 0") in the host's error
  translator's words;
- the message is announced with the input's label;
- the argument keeps its previous value, the rows stay, the address does not
  change, and no error replaces the rows.

A number input shows the constraints' `min`, `max` and `step`: the arrows of
"Due within: Days" stop at 0. This only describes; a number past the limit
can still be typed and is refused by Ash as above. See
[Limits an editor shows before saving](inline-editing.md#limits-an-editor-shows-before-saving).

**Try it:** `/tasks`, "Due within: Days": type `-1` and press Enter.

A refused value in an opened address is treated the same: shown in its input
with the message, not applied.

## Where the arguments are given

Every read the table runs for the person on the page uses their arguments:

| The read | With the arguments |
| --- | --- |
| A page, and its count | yes |
| What is loaded onto the rows of a page after it was read (aggregates) | yes |
| The record of a row, read again before a cell is saved, an action runs or a panel opens | yes |
| Every record that matches, for an action on "all that match" | yes |
| The selected records, read before an action runs on them | yes |
| The row a nested table belongs to, read again each time the nested table reads | yes: those of the table the row is in |
| What an action returned, loaded for the row to be shown again | no: Ash loads that through the primary read action, without arguments |
| The related record of a reference cell, a picker's record by its key | those of that table, not of this one |

So a row's record is one the action returns *for these arguments*. A row an
edit takes out of them (a task whose title no longer holds the search term)
stays, shown from what the action returned, until the next read. A second
edit of that row finds no record and says "This record is no longer
available."

## The arguments of a calculation

A column of a calculation with arguments either fixes them or asks the
person. The demo's tasks have a calculation that needs a number of days:

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
# A calculation with a required argument: a column of it has to say what
# the argument is, or ask for it.
calculate :due_within?,
          :boolean,
          expr(not is_nil(due_on) and due_on <= date_add(today(), ^arg(:days), :day)) do
  public? true

  argument :days, :integer do
    allow_nil? false
    constraints min: 0
  end
end
```

and show it twice:

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
column :due_within? do
  label "Due within 7 days"
  arguments days: 7
end

column :due_within? do
  as :due_within
  ask :days, default: 30
end
```

- **`arguments`** fixes values, as a keyword list by argument name. Nobody
  changes them and they are not shown.
- **`ask`** puts the argument on the argument line, after the read action's.
  Its label is the column label plus the argument name ("Due within: Days");
  `label` on the `ask` replaces all of it.
- **`as`** renames the column. A calculation can be a column more than once
  with other arguments, and the second needs its own name, like a calculation
  loaded twice in Ash (`as:`). That name is used everywhere a column is
  named: the address (`task[sort]=due_within`), the page's ids, and its header
  unless `label` says otherwise.
- An argument neither fixed nor asked keeps its default in the resource.

Each column is loaded, sorted and filtered with its own arguments. On
`/tasks`, "Due within" can be filtered to "Yes" while "Due within 7 days" is
filtered to "No".

### What an asked argument starts with

The first that exists of:

1. what the person chose (the address);
2. the `ask`'s `default`: a value, or a function of the page's assigns;
3. the argument's default in the resource.

A column never starts without a value: an asked argument that cannot be
empty and has neither default is a compile error.

A function gets the page's assigns:

- on the router page, its socket's assigns, set by the host's `on_mount` hooks;
- for a table attached with `AshDataTable.attach/4`, the host LiveView's
  assigns as they are when it is called;
- for a tag (`<AshDataTable.table>`), the `assigns` attribute.

The example is from a domain that exists for the demo's tests
([`demo/test/support/argument_tables.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/test/support/argument_tables.ex)):

<!-- source: demo/test/support/argument_tables.ex -->
```elixir
@doc "A default of an asked argument that looks at the assigns of the page."
def rate(assigns), do: Map.get(assigns, :rate, 5)
```

<!-- source: demo/test/support/argument_tables.ex -->
```elixir
column :amount_in do
  as :amount_fn
  label "Converted"
  arguments currency: :usd
  ask :rate, default: &Demo.Support.Asked.rate/1, label: "Exchange rate"
end
```

<!-- source: demo/test/support/argument_tables.ex -->
```heex
<AshDataTable.table
  id="held"
  resource={Stock}
  actor={assigns[:reader]}
  assigns={%{rate: assigns[:rate]}}
/>
```

The table works nothing out itself: not from the locale, not from who is
asking. An MFA also works (`default: {MyApp.Defaults, :rate, []}`); it is
called with the assigns before its own arguments.

## Nested tables, the full view and the picker

A nested table is its resource's table, read through the action its
relationship runs: the relationship's own `read_action`, else the
destination table's read action. It has *that* action's argument line above
its grid and keeps what a person gave there with its own sort and filters,
not in the address.

- Its inputs are ordinary Tab stops, like the page table's.
- An empty required argument is asked for in place of the nested rows, as
  above.
- A nested table whose action requires an argument has no pages: Ash cannot
  page related records through such an action (see "Edge cases"), so they are
  shown in full.
- The row a nested table belongs to is read again with the arguments of the
  table that row is in.

**Try it:** `/projects`, expand a project, open "Tasks": the nested table has
its own "Search" and "Due within: Days".

The full view of a nested table is the destination's page with the limit in
its address and its own arguments. It reads the row it is limited to through
that row's table's read action *without arguments*, because a link cannot
carry what that table was given. So a table whose read action requires an
argument has no "Open in full view" under its nested tables.

A picker shows the table of records to choose from, with the argument line of
the action it reads through. The chosen record is read once more by its key,
through that action and with the picker line's arguments, before anything is
saved.

**Try it:** `/comments`, "New comment", "Choose" beside "Task": the tasks can
be searched.

## Mistakes the compiler reports

Every message is in [Mistakes at compile time](mistakes-at-compile-time.md).
In short:

- a calculation's required argument given neither way;
- an argument the calculation or read action does not have;
- a fixed value, or an `ask` default, not of the argument's type;
- an argument both fixed and asked, or asked twice;
- an asked argument that cannot be empty and has no default;
- `arguments`, `ask` or `as` on a column that is not a calculation;
- an `as` that is a field's name, or that two columns share;
- a read action that requires an argument the line has no input for.

## Edge cases

- **A `sensitive?` argument has no input on the line**, since the line is kept
  in the URL. A read action that requires one cannot be behind a table. See
  [Sensitive columns](sensitive-columns.md).
- **A counted page of related records through an action that requires an
  argument fails in Ash** (3.36.1): besides the load that gets the arguments,
  Ash counts the page through the action again without any, and that count's
  "is required" is the answer. Without a page the same load works, and a
  table counts wherever the action can. Hence such a nested table is shown in
  full.
- **Two filters on one calculation with different arguments** ("Due within"
  and "Due within 7 days" at once) are correct on a SQL data layer. An
  in-memory data layer (ETS) computes the calculation once for both in Ash
  3.36.1, as does the same filter written with `Ash.Query.filter/2`.
- **A constraint of a calculation's argument** is reported by Ash without the
  argument's name. The table puts the message at the asked argument whose own
  value its type refuses, or at all the column's asked arguments when it
  cannot tell.
- **A computed default** (`default: &Date.utc_today/0` on the action's
  argument) is applied by Ash; its input starts empty because the table does
  not call it. For an asked argument the table does call it, since the
  calculation needs a value.
- **A focused input keeps what it holds.** LiveView does not write into an
  input a person is in. After the back button the argument is what the
  address says, though the focused input still shows what was typed last.
- **A table that changes records** needs a primary read action that runs
  without arguments, because Ash loads action results through it. The
  compiler reports a primary read action with a required argument under such
  a table.
- **A picker's table** is read with what its line holds. A key already in a
  field of the action panel when "Run" is used, not chosen in the picker, is
  looked up through the action without arguments.

## Things people trip over

- **Declaring the read action's arguments.** Nothing to declare; `argument`
  only relabels. `ask` is for a calculation's arguments.
- **Expecting a "Run" button.** Leave the input or press Enter.
- **Two columns of one calculation without `as`.** The compiler reports the
  second as a duplicate.
- **`ask` without a default on a required argument.** The column would start
  without a value; the compiler asks for `default:`.
- **Expecting an edited row to vanish at once.** It stays until the next
  read, as under a filter; then the action decides.
- **A primary read action with arguments.** Ash warns
  (`primary_read_warning?`), since it also loads relationships and results
  through it. An optional argument is harmless; a required one belongs on a
  separate read action, named with `read_action`.

## Not in the first version

No argument-line input for a value made of fields (an embedded resource, a
map), no picker for an argument that is a related record's key, no aggregate
arguments, and no memory of what a person gave beyond the address. The
roadmap is in the
[specification](https://github.com/StefanRoesch/ash_data_table/issues/21).
