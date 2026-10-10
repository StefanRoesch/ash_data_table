# Arguments

After reading this guide you can put a table over a read action that takes
arguments, show a calculation that takes arguments as a column, fixed by you
or asked from the person, and say what the table does while an argument is
missing or wrong.

## The smallest example

A read action with an argument needs nothing in the `table` block. The
demo's tasks are read through an action that takes a search term
([`demo/lib/demo/tracker/task.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo/tracker/task.ex)):

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
read :read do
  primary? true

  # case-insensitive, as a `:ci_string` compares
  argument :search, :ci_string

  filter expr(
           is_nil(^arg(:search)) or contains(title, ^arg(:search)) or
             contains(description, ^arg(:search))
         )
  # ...
end
```

The table of the tasks has a line of inputs above its grid, the **argument
line**, with one input for `search`, labelled "Search".

**Try it:** `/tasks` in the demo, as Ada Admin. Type `login` into "Search"
and press Enter: the rows are the tasks with "login" in their title or their
description, the line under the table counts them, and the address is
`/tasks?task[a][search]=login`.

## The arguments of the read action

Every `public?` argument of the action the table reads through has an input
on the argument line, in the action's order. Nothing is declared for it.

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

- An input is called by the argument's name in words ("Search"), which a
  host translates as it translates a column's label (see
  [Messages and translations](messages-and-translations.md)). An `argument`
  in the block gives another label, and nothing else.
- An input starts with the default the argument has in the action, where
  that is a value. A box that is not ticked gives `false`.
- An argument that is `allow_nil? false` is marked with `*` and
  `aria-required`, as a required field of the action panel is.
- An argument that is `public? false` is never on the line and never given.
- An optional argument of a type without an input (a map, a union, a file)
  is left out. A read action that *requires* such an argument cannot be
  behind a table: the compiler says so.

The demo's deadlines are the tasks that are due by a day, read through an
action with three arguments
([`demo/lib/demo/tracker/deadline.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo/tracker/deadline.ex)):

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

and its block names that action and gives one argument a label:

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

As a filter is: when its input is left, or when Enter is used in it; a
choice, a box and a list's buttons at once. There is no button that runs the
line. Typing sends nothing.

What the person gave is part of the table's state, with the sort and the
filters:

- a mounted table, and a placed one that is given `url`, keeps it in the
  address, so the page can be reloaded, linked, and stepped back through;
- a table that keeps its state itself (a placed table without `url`, a
  nested table, a picker) keeps the arguments there too.

| In the address | Example |
| --- | --- |
| An argument of the read action | `task[a][search]=login` |
| An argument a column asks for | `task[c][due_within][days]=14` |
| A list | `deadline[a][tags][]=api&deadline[a][tags][]=mobile` |
| A list that was emptied, where its default is not empty | `deadline[a][tags]=` |

An argument that is as its input shows it with nothing chosen is not in the
address: the action's default is left to the action.

A change of an argument starts at the first page again, keeps the sort and
the filters, is read out as a change of the filters is ("12 results"), and
gives up the selection of rows.

## A required argument

Whether an argument can be left out is the action's to say: Ash reports an
argument that is `allow_nil? false` and missing, and applies a `default`.
The table adds no rule.

While such an argument is empty the read action is **not run**. In place of
the rows the table says which argument to fill in:

<!-- sketch -->
```text
Fill in Due by to see records.
```

That is neither an error nor "No records", and it is read out. The grid
keeps its header and its filter row, and the table has no pages and no
create button until it has read.

**Try it:** `/deadlines` in the demo. Give "Due by" a day: the rows appear,
and the address carries the day. Empty it again: the rows go.

A person who can never run the read action is not asked to fill in anything.
Ash is asked first, without a read, and such a person is answered as when
the read is refused: a page that does not exist, or the message of
`on_forbidden :message` (see [Authorization](authorization.md)).

## A value Ash refuses

What a person types is given to the action as they typed it, and Ash casts
it. A value that is none of the argument's type, or that its constraints
refuse, is not applied:

- it stays in its input, which is marked (`aria-invalid`) and described by
  the action's message ("must be greater than or equal to 0"), in the words
  of the host's error translator;
- the message is read out, with the input's label;
- the argument keeps the value it had, the rows stay as they are, and the
  address does not change. No error takes the place of the rows.

**Try it:** `/tasks`, "Due within: Days": type `-1` and press Enter.

A value in an address that Ash refuses is treated the same way when the page
is opened: shown in its input with the message, and not applied.

## Where the arguments are given

Wherever the table runs its read action for the person on the page, it runs
it with what they gave:

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

The record of a row is therefore one the action returns *for these
arguments*. A row that an edit takes out of them (a task whose title no
longer holds the search term) stays where it is, shown from what the action
returned, until the table reads again. A second edit of that row finds no
record and says "This record is no longer available."

## The arguments of a calculation

A column that names a calculation with arguments says what they are. Either
the block fixes them, or it asks the person. The demo's tasks have a
calculation that needs a number of days:

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

- **`arguments`** fixes values: a keyword list by argument name. Nobody
  changes them, and nothing of them is on the page.
- **`ask`** puts the argument on the argument line, after the read action's.
  Its input is called by the column's label and the argument's name ("Due
  within: Days"), so that it says which column it belongs to; `label` on the
  `ask` replaces all of that.
- **`as`** gives the column another name. A calculation can be a column more
  than once, with other arguments, and the second column needs a name of its
  own, as a calculation that is loaded twice does in Ash (`as:`). The column
  is that name everywhere a column is named: in the address
  (`task[sort]=due_within`), in the ids of the page, and in its header
  unless `label` says otherwise.
- An argument that is neither fixed nor asked keeps the default it has in
  the resource.

Each column is loaded, sorted and filtered by with its own arguments. On
`/tasks`, "Due within" can be filtered to "Yes" while "Due within 7 days"
is filtered to "No".

### What an asked argument starts with

The first of these that there is:

1. what the person chose (the address);
2. the `default` of the `ask`: a value, or a function of the page's assigns;
3. the default the argument has in the resource.

A column never starts without a value: an asked argument that cannot be
empty and has neither default is a mistake the compiler reports.

A function is given the assigns of the page. For a mounted table those are
the assigns of its socket, which the host's `on_mount` hooks set. A table
placed with `<AshTable.table>` is given them as `assigns`. The example is
from a domain that exists for the demo's tests
([`demo/test/support/argument_tables.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/test/support/argument_tables.ex)):

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
<AshTable.table
  id="held"
  resource={Stock}
  actor={assigns[:reader]}
  assigns={%{rate: assigns[:rate]}}
/>
```

The table works nothing out by itself: not from the locale, not from who is
asking. An MFA is taken as well (`default: {MyApp.Defaults, :rate, []}`) and
is called with the assigns before its own arguments.

## Nested tables, the full view and the picker

A nested table is the table of its resource, read through the action its
relationship runs: the relationship's own `read_action`, else the read
action of the destination's table. It has the argument line of *that*
action, above its own grid, and keeps what a person gave there with its own
sort and filters: not in the address.

- Its inputs are ordinary tab stops, as those of the table on the page are.
- A required argument that is empty is asked for in place of the nested
  rows, as above.
- A nested table whose action requires an argument has no pages: Ash cannot
  page related records through such an action (see "Edge cases"), so the
  related records are shown in full.
- The row a nested table belongs to is read again with the arguments of the
  table that row is in.

**Try it:** `/projects`, expand a project, open "Tasks": the nested table
has "Search" and "Due within: Days" of its own.

The full view of a nested table is the destination's page with the limit in
its address, and with its own arguments beside it. It reads the row it is
limited to through the read action of that row's table *as it runs without
arguments*: a link cannot say what that table was given. So a table whose
read action requires an argument has no "Open in full view" under its nested
tables.

A picker shows the table of the records to choose from, with the argument
line of the action it reads them through. The record a person chooses is
read once more by its key, through that action and with what the picker's
line held, before anything is saved.

**Try it:** `/comments`, "New comment", "Choose" beside "Task": the tasks
to choose from can be searched.

## Mistakes the compiler reports

[Mistakes at compile time](mistakes-at-compile-time.md) has every message.
In short: a calculation's required argument that is given neither way; an
argument the calculation or the read action does not have; a fixed value, or
the default of an `ask`, that is none of the argument's type; an argument
that is both fixed and asked, or asked twice; an asked argument that cannot
be empty and has no default; `arguments`, `ask` or `as` on a column that is
no calculation; an `as` that is a field's name, or that two columns share;
a read action that requires an argument the line has no input for.

## Edge cases

- **A page of related records through an action that requires an argument
  fails in Ash** (3.34.4): beside the load that is given the arguments, Ash
  runs the action once more without any, and that one's "is required" is the
  answer. Without a page the same load works. This is why such a nested
  table is shown in full.
- **Two filters on one calculation with different arguments** ("Due within"
  and "Due within 7 days" at once) are right on a SQL data layer. A data
  layer that filters in memory (ETS) computes the calculation once for both
  in Ash 3.34.4, and so does the same filter written with
  `Ash.Query.filter/2`.
- **A constraint of a calculation's argument** is reported by Ash without
  the argument's name. The table puts the message at the asked argument
  whose own value its type refuses, and at all of the column's asked
  arguments when it cannot tell.
- **A default that is computed** (`default: &Date.utc_today/0` on the
  action's argument) is applied by Ash, and its input starts empty: the
  table does not call it to show it. For an asked argument the table does
  call it, as it has to give the calculation a value.
- **An input with the focus keeps what it holds.** LiveView does not write
  into an input a person is in. After the back button the argument is what
  the address says, though the input that still has the focus shows what was
  typed last.
- **A table that changes records** needs a primary read action that runs
  without arguments, because Ash loads what an action returned through it.
  The compiler reports a primary read action with a required argument under
  such a table.
- **The table to choose from in a picker** is read with what its line
  holds. A key that is already in a field of the action panel when "Run" is
  used, and that was not chosen in the picker, is looked up through the
  action as it runs without arguments.

## Things people trip over

- **Declaring the read action's arguments.** There is nothing to declare;
  `argument` only relabels. `ask` is for a calculation's.
- **Expecting a "Run" button.** Leave the input, or press Enter.
- **Two columns of one calculation without `as`.** The compiler reports the
  second as a duplicate.
- **`ask` without a default on a required argument.** The column would start
  without a value; the compiler asks for `default:`.
- **Expecting an edited row to vanish at once.** It stays until the next
  read, as under a filter; then the action decides.
- **A primary read action with arguments.** Ash warns about it
  (`primary_read_warning?`), since it also loads relationships and results
  through that action. An optional argument is harmless there; a required
  one belongs on a read action of its own, which the block names with
  `read_action`.

## Not in the first version

No input on the argument line for a value made of fields (an embedded
resource, a map), no picker for an argument that is the key of a related
record, no arguments of an aggregate, and no memory of what a person gave
beyond the address. The roadmap is in the
[specification](https://github.com/StefanRoesch/ash_table/issues/21).
