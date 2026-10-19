# Filtering

After reading this guide you know which filter each column gets, which
operators it offers, when a filter applies, what a text filter matches and
why, and how to leave a column without a filter.

How the filters appear in the address is part of
[State in the URL](state-in-the-url.md). The keys that work in the filter row
are in [Keyboard and accessibility](keyboard-and-accessibility.md).

## The smallest example

There is nothing to declare. Under the column headings a table has a
filter row: one filter per column that the resource allows to be filtered,
always visible. The filter's kind follows from the column's type. A table
none of whose columns can be filtered has no filter row (the people under
a task on `/tasks`).

**Try it:** `/tasks` in the demo, as Ada Admin. Type `session` into the
filter under "Title" and press Enter. The table shows the tasks whose title
contains "session", the line under the table gives the new total, and the
address becomes:

<!-- sketch -->
```text
/tasks?task[f][title]=session
```

## Filters run on the server

A filter is never applied in the browser. The table turns the filters of the
row into one filter for `Ash.Query.filter_input/2` and reads the page again
through the table's read action. So a filter searches all records the action
can reach and not the rows on screen, the action's own filter and the
policies still apply, and a field that Ash does not let a person filter by
cannot be searched through the table either.

Filters are combined with AND: a row has to match all of them. They combine
with the sort. Any change of a filter returns to the first page; the sort
stays.

A calculation column that gives its calculation arguments is filtered by
with them, and two columns of one calculation each by their own: see
[Arguments](arguments.md#the-arguments-of-a-calculation). What a person
gives the read action itself is not a filter of the row, though it is
applied like one: it is on the argument line above the table.

## Operators per type

Each filter has a short list of operators. The first one applies when a value
is simply typed; a small menu in the filter cell changes it.

| Cell type | Control | Operators, the default first | In Ash |
| --- | --- | --- | --- |
| text | text input | contains, equals, starts with, is empty | `contains`, `eq`, `string_starts_with`, `is_nil` |
| number | number input | equals, greater than, less than, at least, at most, between, is empty | `eq`, `greater_than`, `less_than`, `greater_than_or_equal`, `less_than_or_equal`, the last two together, `is_nil` |
| date | date input | on, before, after, between, is empty | `eq`, `less_than`, `greater_than`, `greater_than_or_equal` with `less_than_or_equal`, `is_nil` |
| datetime | datetime input, to the second | before, after, between, is empty | `less_than`, `greater_than`, `greater_than_or_equal` with `less_than_or_equal`, `is_nil` |
| boolean | a choice of Any, Yes, No | | `eq` |
| enum | a choice of Any and the values, by their labels | is, is any of, is none of | `eq`, `in`, `not` around `in` |

"between", "is any of" and "is none of" take more than one value and have
controls of their own: see
[Several values, and a range](#several-values-and-a-range).

[Columns and defaults](columns-and-defaults.md#how-each-type-is-displayed)
says which Ash types belong to which cell type. A NewType filters as the type
it is made of. A calculation or an aggregate gets the filter of its type: on
`/tasks`, "Overdue?" is a choice of Any, Yes and No, and "Comments" is a
number.

The list is shortened to what Ash supports for the field:

- **"is empty" is offered only when the field can be nil.** `progress` on
  `/tasks` is `allow_nil? false` and has no "is empty"; `estimate_hours`
  has. A count aggregate is never nil. A boolean or an enum column has no
  "is empty", whether or not it can be nil.
- **A field declared `filterable?: :simple_equality`** is offered "equals"
  only, and an enum "is" only: Ash takes neither a range nor a list for it.
- **An operator the data layer cannot run** for the field is left out.

A datetime is filtered in the terms it is shown in: in the page's time zone
(UTC unless the page gives one; see [Time zones](time-zones.md)), to the
second. A value picked to the minute means the start of that minute.

## When a filter applies

| Control | Applies |
| --- | --- |
| A text, number, date or datetime input | On Enter, and when the input is left. Not while typing. |
| A choice (boolean, enum) | When it is picked. |
| The operator menu | When another operator is picked and the input holds a value. An operator picked while the input is empty changes nothing yet. |
| "is empty" | When it is picked. It needs no value, so the input goes away. |
| An end of a range ("between") | As an input: on Enter, and when it is left. |
| The side panel of "is any of" and "is none of" | On "Apply". Not on each tick; Cancel applies nothing. |

After each change the result is put into a live region for screen readers:
"12 results" when the table knows the total, otherwise "Results updated". The
table knows the total when the read action is `countable`, under offset and
under keyset pagination, and when the action has no pagination.

## Several values, and a range

Two kinds of filter take more than one value. Nothing is declared for them:
they are operators in the menu of the columns that can have them.

### Is any of, is none of

A column with a known set of values, an `Ash.Type.Enum` or an `:atom` with
`one_of`, offers "is any of" and "is none of" beside "is". Picking one puts
a button in place of the single choice; picking the operator alone filters
nothing. The button opens the table's action panel, the one that
[row actions](row-actions-and-create.md) open, titled "Filter State" for a
column headed "State", with a box for each value. The boxes that apply are
ticked. Tick the values and press "Apply": the filter applies then, once,
the panel goes, and the button says what is chosen: "Any" while nothing
is, the value's label for one, "2 selected" for more, with the labels as
its tooltip. "Apply" with no box ticked takes that column's filter away;
the other columns' filters stay.

Ticking alone changes nothing, as typing into a text filter changes nothing
before Enter. Cancel, or Escape, closes the panel and filters nothing: what
applied before still applies. Space ticks a box, Tab goes from box to box
and on to Cancel and "Apply", and focus goes back to the button when the
panel closes. The panel opens over the page or in it, as the table's
[presentation](layout-and-embedding.md) says for its panel.

**Try it:** `/tasks` in the demo. Under "State", pick "is any of", press the
button beside it, tick "To do" and "Done", and press "Apply". The table
shows the tasks in one of the two states, and the address ends in:

<!-- sketch -->
```text
/tasks?task[f][status][any_of][]=todo&task[f][status][any_of][]=done
```

"is none of" finds the records that have a value and it is not one of the
ticked ones. A record without a value is found by neither of the two; "is
empty" is for those, where the column offers it.

The values in the panel come from the column's type. Nothing is read from
the database for them, so the panel tells nobody which values the records
hold.

In [controlled mode](controlled-mode.md) the panel is a `:panel` request
without an action, answered like any other.

### Between

A number, a date and a datetime offer "between". Picking it shows two
inputs, one above the other: "from" and "to".

- **Both ends belong to the range.** "from 10 to 50" finds 10 and finds 50.
  In Ash it is `greater_than_or_equal` and `less_than_or_equal` on the one
  field.
- **Either end may stay empty.** Only "from" means at least, only "to"
  means at most. With both empty there is no filter.
- **A "from" past the "to" is not a mistake.** It finds nothing, and the
  table says "0 results".
- **Each end is checked as any filter value is.** One that is not a value of
  the column's type is marked, and nothing of the range applies.
- **A datetime end is a moment, to the second.** "to 10:00" ends at
  10:00:00, so a record of 10:00:30 is outside.

**Try it:** on `/tasks`, pick "between" under "Due on", give a date as
"from" and press Enter: every task due on that day or later. Give a second
date as "to": the tasks due from the first day to the second. `/specimens`
has the same for "A decimal" and for every kind of datetime.

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

A filter that applies has a small ✕ button beside it, named "Clear the Title
filter" for a column headed "Title". It removes that filter alone. While any
filter applies, a button "Clear filters" above the table removes all of them.
That includes the filter of a column a person has
[hidden](columns-and-defaults.md#hiding-columns): a hidden column keeps its
filter, and the "Columns" button says that it has one.
Choosing "Any", or emptying an input and pressing Enter, clears that filter
as well.

## What a text filter matches

**Text matching is the resource's decision, not the table's.** The table
passes on what was typed, unchanged. For a `:string` attribute a filter is
case-sensitive: "report" does not find "Report". For a `:ci_string`
attribute it is not.

The kitchen-sink resource of the demo has one of each
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

**Try it:** on `/specimens`, type `ALPHA` under "A string" and under "A ci
string" in turn. The first finds only text that contains these capitals; the
second also finds "Alpha" and "alpha".

The table does not lower-case what is typed and does not swap in a
case-insensitive operator, for the reason that page size lives on the read
action: the table is one interface to the resource among several. A filter
for "report" has to find the same records whether it arrives through the
table, through `ash_json_api` or from your own code. If people should find
text whatever its case, make the attribute a `:ci_string`.

## A column without a filter

A column has no filter, and an empty cell in the filter row, which Tab
passes over (see
[Keyboard and accessibility](keyboard-and-accessibility.md#the-tab-order)),
when

- its cell type is "other": UUIDs, times and the rest of the types shown
  as read-only text;
- it is an embedded resource or a map: Ash's interface extensions filter by
  neither, and what Ash can compare inside one it compares without casting
  what was typed. See
  [Maps and embedded resources](maps-and-embedded-resources.md#sorting-and-filtering);
- it is an array, whatever it holds: see
  [Why an array has no filter](#why-an-array-has-no-filter);
- the resource declares the field `filterable?: false`;
- it is a calculation computed in Elixir, without an expression: the data
  layer cannot filter by it. `headline` on `/tasks` is one;
- it is a calculation or aggregate the data layer cannot filter by;
- the block says `filterable? false`.

The last is the only one decided in the block. From the task table:

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
# long text, with sorting and filtering switched off
column :description do
  sortable? false
  filterable? false
end
```

The demo has no field that the resource itself declares unfilterable. The
library's test resources have
([`test/support/filtering.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/test/support/filtering.ex)):

<!-- source: test/support/filtering.ex -->
```elixir
attribute :secret, :string, public?: true, filterable?: false
```

`filterable?` in the block can only switch a filter off. `filterable? true`
on a column the resource does not allow to be filtered is reported when the
resource is compiled; see
[Mistakes at compile time](mistakes-at-compile-time.md).

### Why an array has no filter

Ash can ask whether an array holds a value: `has(tags, "api")` in an
expression. The table does not offer it, for two reasons.

- **The other interfaces offer no filter for an array.** `ash_json_api` and
  `ash_graphql` leave every array attribute out of the filters they
  generate, whatever the array holds. A table offers what the resource's
  other interfaces offer.
- **A typed value is not cast.** A table gives Ash a filter from outside
  through `Ash.Query.filter_input/2`, with the value as it was typed. For
  the other operators Ash casts that text to the column's type. For `has`
  it does not cast it to the type of the array's values: `42` typed for an
  array of integers arrives as text, finds nothing in a table kept in
  memory, and fails the read on Postgres. The table would have to cast the
  value itself, which it does for no filter.

So an array column has an empty cell in the filter row, and
`filterable? true` on it is reported as on any column without a filter. A
resource that should be searched by its tags can offer a read action with
an argument and a filter of its own; a table does not show such arguments
yet.

## Values that are not valid

The native inputs keep most invalid values from being typed: a number input
takes no letters, a date input no thirty-first of February. What still gets
through is checked against the column's type with Ash's own casting, before
the read:

- A value that is not one of the column's type is **not applied**. On
  `/tasks`, `1.5` under "Progress" is such a value, because `progress` is an
  integer.
- Its input is marked (`aria-invalid`, the error colour) and says "Not a
  valid value" underneath.
- The filter that applied to that column before is gone. The other filters
  go on applying.
- Typing a valid value removes the mark.

Text is always valid. A choice is valid when it is one of the column's
values.

## Edge cases

- **A column of a `sensitive?` field has no filter.** Which rows a filter
  leaves would say what its masked cells hide. See
  [Sensitive columns](sensitive-columns.md).
- **A hidden value counts as empty.** For a field that a field policy hides
  on some records, a filter by a value finds only records whose value the
  person sees, and "is empty" also finds every record whose value is hidden.
  This is Ash's behaviour, and it means that a filter gives nothing away.
  See [Authorization](authorization.md).
- **A column the person can never see has no filter**, and a filter for it in
  the URL is ignored.
- **An invalid value in the URL is dropped without a mark.** Only a value
  typed into the row is shown as rejected. A list in the URL with one value
  the column does not have is dropped as a whole, and so is a range with
  one end that is no value of the column's type.
- **A list has one way to be written.** The values are kept in the order
  the column has them, each once, whatever order they were ticked in. The
  same filter gives the same address.
- **A table whose read action is not `countable` announces "Results
  updated".** It has no total to report. That holds under offset and under
  keyset pagination alike; the demo's keyset table, `/comments`, counts.
- **The row stays after an edit.** A row whose new value no longer matches
  the filter stays on the page until the next read. See
  [Inline editing](inline-editing.md).
- **An empty text is not "is empty".** Emptying the input clears the filter.
  To find records without a value, pick "is empty", which finds nil.
- **Decimal numbers are typed with a point.** `1,5` is not a number for Ash.

## Things people trip over

- **Text filters are case-sensitive for `:string`.** This is the most common
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

No search across columns, no filter builder with OR, no filter for an array,
no "is any of" for typed text or numbers, no filter by a related record
("Assignee is Ada or Max"), and no filters from the arguments of a
read action. Search, facets and a filter builder are expected from a separate
extension. See the
[specification](https://github.com/StefanRoesch/ash_data_table/issues/21).
