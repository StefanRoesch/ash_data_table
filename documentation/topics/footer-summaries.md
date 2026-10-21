# Footer summaries

Show one number under a column: a sum, an average, the smallest or largest
value, or a count. This guide says what the number is over and what it never
shows.

## The smallest example

A column asks for its number with `summary`. The demo's tasks show the
average progress
([`demo/lib/demo/tracker/task.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/task.ex)):

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
column :progress do
  update_action :set_progress
  component DemoWeb.Cells.Progress
  # Footer summaries: one number under the column, over every task the
  # table matches and not only those of the page. Here the average.
  summary :avg
end
```

The table gets one more row after its last record. Under "Progress" it says
"Average 48.5": the kind's name, then the number. A column without a summary
has an empty cell there. A table with no summary has no such row.

**Try it:** `/tasks` in the demo, as Ada Admin. Below the last row: "Average …"
under Progress, "Sum …" under Estimate hours, "Max …" under Due on, "Count …"
under Completed at.

## The five kinds

One kind per column.

| Kind | What it is | Fits | With no record |
| --- | --- | --- | --- |
| `:count` | How many records have a value in this column. | Every column. | 0 |
| `:sum` | The values added up. | Integer, float and decimal attributes. | Empty |
| `:avg` | Their average, with two decimal places at most. | Integer, float and decimal attributes. | Empty |
| `:min` | The smallest value, or the earliest. | Numbers, dates, datetimes and times. | Empty |
| `:max` | The largest value, or the latest. | Numbers, dates, datetimes and times. | Empty |

`:count` counts the records in which this column is not empty, not the rows
(the row count is already under the table: "1–25 of 320").

A sum, minimum and maximum are formatted as the column's cells format a value.
A column with a `component` still gets plain text in the footer.

The demo's other three kinds:

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
column :estimate_hours do
  component DemoWeb.Cells.Hours
  # ...
  summary :sum
end
```

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
column :due_on do
  summary :max
end

column :completed_at do
  summary :count
end
```

## What the number is over

Every record the table matches, not only the current page: computed through
the table's read action, with the argument line's arguments and the filters.
Page 2 shows the same numbers as page 1; a filter changes them. Selecting rows
changes nothing.

**Try it:** on `/tasks`, note the sum under Estimate hours and go to page 2:
it is the same. Filter Title by a word: the sum now covers the matching tasks.

## What a person may see

A summary never tells a person more than the rows could.

- **Records the person may not read** are not counted. The number is read as
  that person, in their tenant, like the rows.
- **A field a field policy hides from the person on some records** has no
  number: the cell shows "–" and a screen reader says "Not available". A sum
  over only the visible values would look like the sum of all.
- **A field the person never sees** has no column, so no footer cell.
- **A page mounted with `authorize?: false`** sums everything, as it reads
  everything.

**Try it:** `/tasks` as Max Member. A member sees only the estimates of tasks
assigned to them, so the footer says "Sum –" under Estimate hours. The average
under Progress shows as for everybody.

The table calls `Ash.aggregate/3` once for all summaries of the table:

<!-- sketch -->
```elixir
Ash.aggregate(
  query,
  [{:estimate_hours, :sum, field: :estimate_hours, read_action: :read}],
  actor: actor,
  tenant: tenant,
  authorize_fields?: true
)
```

- `authorize_fields?: true` makes Ash leave out every value a field policy
  hides from the person; Ash does not do that by default.
- Each aggregate names the table's own read action. Otherwise Ash checks the
  field policies as the primary read action meets them, which can differ for a
  table that reads through another action.

## When it is computed

- **With every read of the table:** a filter, an argument, another page. Not
  when only the sort changes: the same records match.
- **After the table has written:** a saved cell, a row action, a new record,
  an action on the selected rows.
- **When other people change records**, in a table with live updates: once
  per batch the table hears of. See [Live updates](live-updates.md).

The rows never wait for the numbers: these are fetched beside the rows, in one
more query. Until the new number arrives the old one stays, marked `aria-busy`
(the default kit dims it). A query still running when the page is left or its
table closes finishes, and its answer is dropped.

If the numbers cannot be computed, every summary shows "–", the reason is
logged, and the rows are unaffected.

**Try it:** on `/tasks` as Ada Admin, change an estimate (Enter, a number,
Enter). The sum follows a moment later.

## Where it shows

The footer is a row of the table like the others.

- **Keyboard:** no Tab stops; Tab goes from the last record on to the
  pagination. A screen reader reads it with its table keys.
- **Hidden columns:** a summary is hidden and shown with its column. See
  [Columns and defaults](columns-and-defaults.md).
- **Nested tables and pickers** show their table's summaries. A nested table
  sums only the related records of its row.
- **Named tables** declare their own and take none over from the default
  table. See [Named tables](named-tables.md).

**Try it:** `/projects` as Ada Admin. Expand "Mobile app" and open "Tasks":
the nested table ends with the summaries of that project's tasks, above its
pages.

## Mistakes at compile time

Reported when the resource compiles, at the column's `summary`. See
[Mistakes at compile time](mistakes-at-compile-time.md).

- `summary` on a column that shows a **calculation, an aggregate or a related
  record**. A summary is over an attribute.
- A kind that **does not fit the type**, such as `:sum` on a text.
- `summary` on a **`sensitive?` column**, `:count` included. The cells are
  masked, and a sum would reveal them.
- `summary` in a table whose **read action is manual**. The number comes from
  the data layer, which a manual action is not read through, so it could
  disagree with the rows.
- A **data layer that cannot compute the kind** over a query.

## Edge cases

- **An empty result** shows "Count 0" and nothing after "Sum", "Average", "Min"
  and "Max". Empty is not 0: there is nothing to add up.
- **A required read argument is empty:** nothing is read, and there is no
  footer row until it is filled in.
- **The read is refused or fails:** the table shows its message and no footer
  row.
- **An average** is rounded to two decimal places. A sum of floats is shown as
  the cells show a float, with every digit.
- **A nested table** reads the keys of all matching related records before it
  sums them: one more read, growing with the number of related records.
- **A nested table or picker that reads through a manual action** shows "–"
  for every summary. The compile-time check looks only at the table's own read
  action.
- **A resource on a data layer that cannot aggregate**, compiled despite the
  finding, shows "–".

## Things people trip over

- **"The sum is not the sum of the page."** It is the sum of all pages.
- **"The count is lower than the number of records."** `:count` counts only
  non-empty values.
- **"I see a dash."** A field policy hides the field from you on some records
  (a demo admin sees the number), or the numbers could not be computed.
- **Cost.** Each read runs one more query over everything the filters match,
  like the count of a countable read action. A table over millions of records
  pays for it on every filter change; declare no summary there.
- **A `LiveViewTest`** waits for the numbers with `render_async/2`, as for the
  rows of a later read.

## Not in the first version

- **Summaries of calculation and aggregate columns.** In a trial, `Ash.sum/3`
  over a calculation raised on the ETS data layer; Postgres is untried. So
  `summary` is for attributes only.
- **Several summaries in one column**, or a second footer row.
- **The viewer choosing the kind**, and other kinds: median, unique values,
  percent filled.
- **A summary of the selected rows**, or one per group.
- **A footer that stays in view** while the rows scroll.
- **Another source for the numbers**, for a table with a manual read action.

Further work is in the
[specification](https://github.com/StefanRoesch/ash_data_table/issues/21).
