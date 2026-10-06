# Filtering

After reading this guide you know which filter each column gets, which
operators it offers, when a filter applies, what a text filter matches and
why, and how to leave a column without a filter.

How the filters appear in the address is part of
[State in the URL](state-in-the-url.md). The keys that work in the filter row
are in [Keyboard and accessibility](keyboard-and-accessibility.md).

## The smallest example

There is nothing to declare. Under the column headings every table has a
filter row: one filter per column that the resource allows to be filtered,
always visible. The filter's kind follows from the column's type.

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

## Operators per type

Each filter has a short list of operators. The first one applies when a value
is simply typed; a small menu in the filter cell changes it.

| Cell type | Control | Operators, the default first | In Ash |
| --- | --- | --- | --- |
| text | text input | contains, equals, starts with, is empty | `contains`, `eq`, `string_starts_with`, `is_nil` |
| number | number input | equals, greater than, less than, at least, at most, is empty | `eq`, `greater_than`, `less_than`, `greater_than_or_equal`, `less_than_or_equal`, `is_nil` |
| date | date input | on, before, after, is empty | `eq`, `less_than`, `greater_than`, `is_nil` |
| datetime | datetime input, to the second | before, after, is empty | `less_than`, `greater_than`, `is_nil` |
| boolean | a choice of Any, Yes, No | | `eq` |
| enum | a choice of Any and the values, by their labels | | `eq` |

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
  only.
- **An operator the data layer cannot run** for the field is left out.

A datetime is filtered in the terms it is shown in: UTC, to the second. A
value picked to the minute means the start of that minute.

## When a filter applies

| Control | Applies |
| --- | --- |
| A text, number, date or datetime input | On Enter, and when the input is left. Not while typing. |
| A choice (boolean, enum) | When it is picked. |
| The operator menu | When another operator is picked and the input holds a value. An operator picked while the input is empty changes nothing yet. |
| "is empty" | When it is picked. It needs no value, so the input goes away. |

After each change the result is put into a live region for screen readers:
"12 results" when the table knows the total, otherwise "Results updated". The
table knows the total under offset pagination with a `countable` action, and
when the action has no pagination.

## Clearing

A filter that applies has a small ✕ button beside it, named "Clear the Title
filter" for a column headed "Title". It removes that filter alone. While any
filter applies, a button "Clear filters" above the table removes all of them.
Choosing "Any", or emptying an input and pressing Enter, clears that filter
as well.

## What a text filter matches

**Text matching is the resource's decision, not the table's.** The table
passes on what was typed, unchanged. For a `:string` attribute a filter is
case-sensitive: "report" does not find "Report". For a `:ci_string`
attribute it is not.

The kitchen-sink resource of the demo has one of each
([`demo/lib/demo/kitchen_sink/specimen.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo/kitchen_sink/specimen.ex)):

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

A column has no filter, and an empty cell in the filter row, when

- its cell type is "other": arrays, maps, embedded resources, UUIDs, times
  and the rest of the types shown as read-only text;
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
([`test/support/filtering.ex`](https://github.com/StefanRoesch/ash_table/blob/main/test/support/filtering.ex)):

<!-- source: test/support/filtering.ex -->
```elixir
attribute :secret, :string, public?: true, filterable?: false
```

`filterable?` in the block can only switch a filter off. `filterable? true`
on a column the resource does not allow to be filtered is reported when the
resource is compiled; see
[Mistakes at compile time](mistakes-at-compile-time.md).

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

- **A hidden value counts as empty.** For a field that a field policy hides
  on some records, a filter by a value finds only records whose value the
  person sees, and "is empty" also finds every record whose value is hidden.
  This is Ash's behaviour, and it means that a filter gives nothing away.
  See [Authorization](authorization.md).
- **A column the person can never see has no filter**, and a filter for it in
  the URL is ignored.
- **An invalid value in the URL is dropped without a mark.** Only a value
  typed into the row is shown as rejected.
- **A keyset table and an offset table that is not `countable` announce
  "Results updated".** They have no total to report.
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

No search across columns, no filter builder with OR, no multiple choice for
enums, no date ranges in one control, and no filters from the arguments of a
read action. Search, facets and a filter builder are expected from a separate
extension. See the
[specification](https://github.com/StefanRoesch/ash_table/issues/21).
