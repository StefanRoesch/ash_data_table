# Filtering

This guide covers which filter each column gets, its operators, when a filter
applies, what a text filter matches, and how to leave a column without a
filter. Filters in the address are in [State in the URL](state-in-the-url.md);
the filter row's keys are in
[Keyboard and accessibility](keyboard-and-accessibility.md).

## The smallest example

Nothing to declare. Under the column headings is an always-visible filter
row: one filter per column the resource allows to be filtered, its kind
following from the column's type. A table with no filterable column has no
filter row (the people under a task on `/tasks`).

**Try it:** `/tasks` in the demo, as Ada Admin. Type `session` under "Title"
and press Enter: the tasks whose title contains "session", the new total
under the table, and this address:

<!-- sketch -->
```text
/tasks?task[f][title]=session
```

## Filters run on the server

A filter is never applied in the browser. The table turns the row's filters
into one filter for `Ash.Query.filter_input/2` and reads the page again
through its read action. So:

- a filter searches every record the action can reach, not the rows on screen;
- the action's own filter and the policies still apply;
- a field Ash does not let a person filter by cannot be searched through the
  table either.

Filters combine with AND and with the sort. A filter change returns to the
first page; the sort stays.

A calculation column with arguments is filtered with them, and two columns of
one calculation each with their own: see
[Arguments](arguments.md#the-arguments-of-a-calculation). The read action's
own arguments are not filters of the row, though applied like them: they are
on the argument line above the table.

## Operators per type

Each filter has a short operator list. The first applies when a value is
simply typed; a small menu in the filter cell changes it.

| Cell type | Control | Operators, the default first | In Ash |
| --- | --- | --- | --- |
| text | text input | contains, equals, starts with, is empty | `contains`, `eq`, `string_starts_with`, `is_nil` |
| number | number input | equals, greater than, less than, at least, at most, between, is empty | `eq`, `greater_than`, `less_than`, `greater_than_or_equal`, `less_than_or_equal`, the last two together, `is_nil` |
| date | date input | on, before, after, between, is empty | `eq`, `less_than`, `greater_than`, `greater_than_or_equal` with `less_than_or_equal`, `is_nil` |
| datetime | datetime input, to the second | before, after, between, is empty | `less_than`, `greater_than`, `greater_than_or_equal` with `less_than_or_equal`, `is_nil` |
| boolean | a choice of Any, Yes, No | | `eq` |
| enum | a choice of Any and the values, by their labels | is, is any of, is none of | `eq`, `in`, `not` around `in` |

"between", "is any of" and "is none of" take several values and have their
own controls: see [Several values, and a range](#several-values-and-a-range).

[Columns and defaults](columns-and-defaults.md#how-each-type-is-displayed)
maps Ash types to cell types. A NewType filters as its underlying type. A
calculation or aggregate gets its type's filter: on `/tasks`, "Overdue?" is a
choice of Any, Yes and No, and "Comments" is a number.

The list is cut to what Ash supports for the field:

- **"is empty" only when the field can be nil.** `progress` on `/tasks` is
  `allow_nil? false` and has none; `estimate_hours` has it. A count aggregate
  is never nil. A boolean or enum column never has "is empty", nil or not.
- **A field declared `filterable?: :simple_equality`** gets "equals" only (an
  enum "is" only): Ash takes neither a range nor a list for it.
- **An operator the data layer cannot run** for the field is left out.

A datetime is filtered as it is shown: in the page's time zone (UTC unless
the page gives one; see [Time zones](time-zones.md)), to the second. A value
picked to the minute means the start of that minute.

## When a filter applies

| Control | Applies |
| --- | --- |
| A text, number, date or datetime input | On Enter, and when the input is left. Not while typing. |
| A choice (boolean, enum) | When it is picked. |
| The operator menu | When another operator is picked and the input holds a value. An operator picked while the input is empty changes nothing yet. |
| "is empty" | When it is picked. It needs no value, so the input goes away. |
| An end of a range ("between") | As an input: on Enter, and when it is left. |
| The side panel of "is any of" and "is none of" | On "Apply". Not on each tick; Cancel applies nothing. |

After each change the result goes to a live region for screen readers: "12
results" when the table knows the total, else "Results updated". It knows the
total when the read action is `countable` (offset or keyset) and when the
action has no pagination.

## Several values, and a range

Two kinds of filter take more than one value. Nothing is declared: they are
operators in the menu of the columns that can have them.

### Is any of, is none of

A column with a known value set (an `Ash.Type.Enum` or an `:atom` with
`one_of`) offers "is any of" and "is none of" beside "is". Picking one
replaces the single choice with a button; the operator alone filters nothing.

The button opens the table's action panel (the one
[row actions](row-actions-and-create.md) open), titled "Filter State" for a
column headed "State", with a box per value; the applied values are ticked.
On "Apply" the filter applies once, the panel closes, and the button shows
the choice: "Any" for none, the value's label for one, "2 selected" for more,
with the labels as tooltip. "Apply" with no box ticked removes that column's
filter; other columns' filters stay.

- Ticking alone changes nothing, as typing does before Enter.
- Cancel or Escape closes the panel without filtering; the previous filter
  still applies.
- Space ticks a box, Tab moves box to box and on to Cancel and "Apply"; focus
  returns to the button when the panel closes.
- The panel opens over the page or in it, as the table's
  [presentation](layout-and-embedding.md) says for its panel.

**Try it:** `/tasks`, under "State": pick "is any of", press the button, tick
"To do" and "Done", press "Apply". The tasks in either state, and the address
ends in:

<!-- sketch -->
```text
/tasks?task[f][status][any_of][]=todo&task[f][status][any_of][]=done
```

"is none of" finds records that have a value not among the ticked ones. A
record without a value is found by neither; "is empty" finds those, where the
column offers it.

The panel's values come from the column's type, not the database, so the
panel reveals nothing about which values the records hold.

In [controlled mode](controlled-mode.md) the panel is a `:panel` request
without an action, answered like any other.

### Between

A number, date or datetime offers "between", which shows two inputs, one above
the other: "from" and "to".

- **Both ends are included.** "from 10 to 50" finds 10 and 50: in Ash
  `greater_than_or_equal` and `less_than_or_equal` on the one field.
- **Either end may stay empty.** Only "from" means at least, only "to" at
  most. Both empty: no filter.
- **A "from" past the "to" is not a mistake.** It finds nothing; the table
  says "0 results".
- **Each end is checked like any filter value.** One not of the column's type
  is marked, and nothing of the range applies.
- **A datetime end is a moment, to the second.** "to 10:00" ends at 10:00:00,
  so a record at 10:00:30 is outside.

**Try it:** on `/tasks`, pick "between" under "Due on", give a "from" date
and press Enter: every task due that day or later. Add a "to" date: the tasks
due between the two. `/specimens` has the same for "A decimal" and every kind
of datetime.

<!-- sketch -->
```text
/tasks?task[f][due_on][between][from]=2026-03-01&task[f][due_on][between][to]=2026-03-31
```

### Which columns have them

| Column | Is any of, is none of | Between |
| --- | --- | --- |
| enum (`Ash.Type.Enum`, `:atom` with `one_of`) | yes | no |
| number, date, datetime | no | yes |
| a calculation or an aggregate of such a type, a calculation with arguments among them | as its type | as its type |
| text, boolean | no | no |
| a reference column ("Assignee"), an array, a map, an embedded resource, a union | no: these have no filter at all | no |
| a `sensitive?` column, a column declared `filterable? false` | no | no |
| a field declared `filterable?: :simple_equality` | no | no |

## Clearing

- An applied filter has a small ✕ button beside it ("Clear the Title filter"
  for a column headed "Title") that removes that filter alone.
- While any filter applies, "Clear filters" above the table removes all of
  them, including the filter of a
  [hidden](columns-and-defaults.md#hiding-columns) column: a hidden column
  keeps its filter, and the "Columns" button says it has one.
- Choosing "Any", or emptying an input and pressing Enter, also clears that
  filter.

## What a text filter matches

**Text matching is the resource's decision, not the table's.** The table
passes on what was typed, unchanged. On a `:string` attribute a filter is
case-sensitive ("report" does not find "Report"); on a `:ci_string` it is
not.

The demo's kitchen-sink resource has one of each
([`demo/lib/demo/kitchen_sink/specimen.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/kitchen_sink/specimen.ex)):

<!-- source: demo/lib/demo/kitchen_sink/specimen.ex -->
```elixir
attribute :a_string, :string do
  allow_nil? false
  public? true
  constraints min_length: 2, max_length: 50, trim?: true
end

attribute :a_ci_string, :ci_string do
  allow_nil? false
  public? true
  constraints max_length: 50
end
```

**Try it:** on `/specimens`, type `ALPHA` under "A string", then under "A ci
string". The first finds only text containing these capitals; the second also
finds "Alpha" and "alpha".

The table neither lower-cases the input nor swaps in a case-insensitive
operator, for the same reason page size lives on the read action: the table
is one interface to the resource among several. "report" must find the same
records through the table, `ash_json_api` or your own code. To match
regardless of case, make the attribute a `:ci_string`.

## A column without a filter

A column has no filter (an empty filter-row cell that Tab skips; see
[Keyboard and accessibility](keyboard-and-accessibility.md#the-tab-order))
when:

- its cell type is "other": UUIDs, times and the other types shown as
  read-only text;
- it is an embedded resource or a map: Ash's interface extensions filter by
  neither, and what Ash can compare inside one it compares without casting the
  typed value. See
  [Maps and embedded resources](maps-and-embedded-resources.md#sorting-and-filtering);
- it is an array, whatever it holds: see
  [Why an array has no filter](#why-an-array-has-no-filter);
- the resource declares the field `filterable?: false`;
- it is a calculation computed in Elixir, without an expression (the data
  layer cannot filter by it), such as `headline` on `/tasks`;
- it is a calculation or aggregate the data layer cannot filter by;
- the block says `filterable? false`.

Only the last is decided in the block. From the task table:

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
# long text, with sorting and filtering switched off
column :description do
  sortable? false
  filterable? false
end
```

The demo has no field its resource declares unfilterable; the library's test
resources do
([`test/support/filtering.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/test/support/filtering.ex)):

<!-- source: test/support/filtering.ex -->
```elixir
attribute :secret, :string, public?: true, filterable?: false
```

`filterable?` in the block can only switch a filter off. `filterable? true` on
a column the resource does not allow to filter is a compile error; see
[Mistakes at compile time](mistakes-at-compile-time.md).

### Why an array has no filter

Ash can ask whether an array holds a value (`has(tags, "api")`). The table
does not offer it:

- **The other interfaces offer no array filter.** `ash_json_api` and
  `ash_graphql` leave every array attribute out of their generated filters,
  whatever it holds. A table offers what the resource's other interfaces
  offer.
- **A typed value is not cast.** The table gives Ash an outside filter through
  `Ash.Query.filter_input/2`, with the value as typed. For the other
  operators Ash casts it to the column's type; for `has` it does not cast it
  to the array's value type. `42` typed for an array of integers arrives as
  text, finds nothing in a table kept in memory, and fails the read on
  Postgres. The table would have to cast the value itself, which it does for
  no filter.

So an array column has an empty filter-row cell, and `filterable? true` on it
is reported as on any column without a filter. A resource that should be
searchable by its tags can offer a read action with an argument and its own
filter; a table does not show such arguments yet.

## Values that are not valid

Native inputs block most invalid values (no letters in a number input, no 31
February in a date input). What gets through is checked against the column's
type with Ash's casting, before the read:

- A value not of the column's type is **not applied**: on `/tasks`, `1.5`
  under "Progress", since `progress` is an integer.
- Its input is marked (`aria-invalid`, the error colour) with "Not a valid
  value" underneath.
- That column's previous filter is gone; the other filters still apply.
- Typing a valid value removes the mark.

Text is always valid. A choice is valid when it is one of the column's values.

## Edge cases

- **A `sensitive?` field's column has no filter**: the rows a filter leaves
  would reveal what its masked cells hide. See
  [Sensitive columns](sensitive-columns.md).
- **A hidden value counts as empty.** For a field a field policy hides on
  some records, a filter by value finds only records whose value the person
  sees, and "is empty" also finds every record whose value is hidden. This is
  Ash's behaviour, and the filter reveals nothing. See
  [Authorization](authorization.md).
- **A column the person can never see has no filter**, and a filter for it in
  the URL is ignored.
- **An invalid value in the URL is dropped without a mark.** Only a value
  typed into the row is shown as rejected. A URL list with one value the
  column does not have is dropped whole, as is a range with one end not of
  the column's type.
- **A list has one way to be written.** Values are kept in the column's order,
  each once, whatever order they were ticked in, so the same filter gives the
  same address.
- **A read action that is not `countable` announces "Results updated"**, with
  no total, under offset and keyset alike. The demo's keyset table,
  `/comments`, counts.
- **A row stays after an edit** that makes it no longer match, until the next
  read. See [Inline editing](inline-editing.md).
- **An empty text is not "is empty".** Emptying the input clears the filter;
  to find records without a value, pick "is empty", which finds nil.
- **Decimals are typed with a point.** `1,5` is not a number for Ash.

## Things people trip over

- **Text filters are case-sensitive for `:string`.** The most common
  surprise. Use `:ci_string`.
- **A filter seems to do nothing.** It applies on Enter or when the input is
  left, not on every key.
- **"is empty" is missing.** The attribute is `allow_nil? false`, or the
  column is a boolean or an enum.
- **A calculation has no filter.** It is computed in Elixir. Write it as an
  expression if the data layer should filter and sort by it.
- **Expecting `filterable? true` to add a filter.** The block can only take
  filters away.

## Not in the first version

No search across columns, no filter builder with OR, no array filter, no "is
any of" for typed text or numbers, no filter by a related record ("Assignee
is Ada or Max"), and no filters from a read action's arguments. Search,
facets and a filter builder are expected from a separate extension. See the
[specification](https://github.com/StefanRoesch/ash_data_table/issues/21).
