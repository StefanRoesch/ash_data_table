# Footer summaries

After reading this guide you can show one number under a column: a sum, an
average, the smallest or the largest value, or a count. You also know what
the number is over, and what it never shows.

## The smallest example

A column says which number it wants with `summary`. The demo's tasks show
the average progress
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

The table then has one more row after its last record. Under "Progress" it
says "Average 48.5": the kind's name, then the number. Under a column
without a summary the cell of that row is empty. A table in which no column
has a summary has no such row.

**Try it:** `/tasks` in the demo, as Ada Admin. Look under the last row:
"Average …" under Progress, "Sum …" under Estimate hours, "Max …" under Due
on and "Count …" under Completed at.

## The five kinds

One kind per column.

| Kind | What it is | Fits | With no record |
| --- | --- | --- | --- |
| `:count` | How many records have a value in this column. | Every column. | 0 |
| `:sum` | The values added up. | Integer, float and decimal attributes. | Empty |
| `:avg` | Their average, with two decimal places at most. | Integer, float and decimal attributes. | Empty |
| `:min` | The smallest value, or the earliest. | Numbers, dates, datetimes and times. | Empty |
| `:max` | The largest value, or the latest. | Numbers, dates, datetimes and times. | Empty |

`:count` does not count the rows: how many records there are is said under
the table already ("1–25 of 320"). It counts the records in which this
column is not empty.

A sum, a minimum and a maximum are shown as a cell of the column shows a
value. A column with a `component` still gets plain text in the footer.

The demo uses the other three kinds on the same table:

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

Every record the table matches, not only the page you look at. It is
computed through the table's read action, with the arguments of the
argument line and with the filters you set. Page 2 shows the same numbers as
page 1. A filter changes them.

It is not over the selected rows. Ticking rows changes nothing in the
footer.

**Try it:** on `/tasks`, note the sum under Estimate hours and go to page 2:
it is the same. Then filter Title by a word: the sum is now the sum of the
tasks that match.

## What a person may see

A summary never tells a person more than the rows could.

- **Records the person may not read** are not counted. The number is read
  as that person, in their tenant, as the rows are.
- **A field that a field policy hides from the person on some records**
  has no number. The cell shows "–", and a screen reader says "Not
  available". A sum over the values they do see would look like the sum of
  all.
- **A field the person never sees** has no column, and so no footer cell.
- **A page mounted with `authorize?: false`** sums everything, as it reads
  everything.

**Try it:** `/tasks` as Max Member. A member sees the estimate of the tasks
assigned to them and of no other. Under Estimate hours the footer says
"Sum –". The average under Progress is there, as for everybody.

Under the hood the table calls `Ash.aggregate/3`, once for all summaries of
the table:

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

`authorize_fields?: true` makes Ash leave out every value that a field
policy hides from the person. Ash does not do that by itself. The table
also names its own read action for every aggregate: Ash would otherwise
look at the field policies as the primary read action meets them, which can
differ for a table that reads through another action.

## When it is computed

- **With every read of the table:** a filter, an argument, another page.
  Not when only the sort changes: the same records match.
- **After the table has written:** a saved cell, a row action, a new
  record, an action on the selected rows.
- **When other people change records,** in a table with live updates: once
  for each batch the table hears of. See [Live updates](live-updates.md).

The rows never wait for the numbers: they are asked for beside the rows, in
one more query. Until the new number is there the old one stays, marked
`aria-busy` (the default kit dims it a little). A query for the numbers
that is on its way when the page is left, or its table closes, finishes,
and its answer is dropped.

If the numbers cannot be computed, every summary shows "–", the reason is
logged, and the rows are as they are.

**Try it:** on `/tasks` as Ada Admin, change an estimate with Enter, a
number, Enter. The sum under the column follows a moment later.

## Where it shows

The footer row is a row of the table like the others.

- **Keyboard:** it has no Tab stops: Tab goes from the last record on to
  the pagination. A screen reader reads it with its table keys.
- **Hidden columns:** a summary is hidden with its column, and comes back
  with it. See [Columns and defaults](columns-and-defaults.md).
- **Nested tables and pickers** show the summaries of their table. A nested
  table sums the related records of its row only.
- **Named tables** declare their own. A named table takes no summary over
  from the default table. See [Named tables](named-tables.md).

**Try it:** `/projects` as Ada Admin. Expand "Mobile app" and open "Tasks":
the nested table ends with the summaries of that project's tasks, above its
pages.

## Mistakes at compile time

These are reported when the resource is compiled, at the column's
`summary`. See [Mistakes at compile time](mistakes-at-compile-time.md).

- `summary` on a column that shows a **calculation, an aggregate or a
  related record**. A summary is over an attribute.
- A kind that **does not fit the type**, such as `:sum` on a text.
- `summary` on a **`sensitive?` column**, also `:count`. The table masks
  such a column's cells, and a sum would say what they hold.
- `summary` in a table whose **read action is manual**. The number comes
  from the data layer, which a manual action is not read through, so it
  could disagree with the rows.
- A **data layer that cannot compute the kind** over a query.

## Edge cases

- **An empty result** shows "Count 0", and nothing after "Sum", "Average",
  "Min" and "Max". Empty is not 0: there is nothing to add up.
- **An argument the read action requires, and that is empty:** nothing is
  read, and there is no footer row until it is filled in.
- **The read is refused or fails:** the table shows its message, and no
  footer row.
- **An average** is rounded to two decimal places. A sum of floats is shown
  as the cells show a float, with every digit.
- **A nested table** reads the keys of all related records that match
  before it sums them. That is one more read, and it grows with the number
  of related records.
- **A nested table or a picker that reads through a manual action** shows
  "–" for every summary. The compile-time check looks at the table's own
  read action only.
- **A resource on a data layer that cannot aggregate** shows "–", should it
  be compiled despite the finding.

## Things people trip over

- **"The sum is not the sum of the page."** It is the sum of all pages.
- **"The count is lower than the number of records."** `:count` counts the
  records that have a value in that column.
- **"I see a dash."** A field policy hides the field from you on some
  records. An admin of the demo sees the number.
- **Cost.** Each read of the table runs one more query over everything the
  filters match, like the count of a countable read action. A table over
  millions of records pays for it on every filter change. Declare no
  summary there.
- **A `LiveViewTest`** waits for the numbers with `render_async/2`, as for
  the rows of a later read.

## Not in the first version

- **Summaries of calculation and aggregate columns.** In a trial,
  `Ash.sum/3` over a calculation raised on the ETS data layer; on Postgres
  it has not been tried. So `summary` is for attributes only.
- **Several summaries in one column,** and a second footer row.
- **The viewer choosing the kind,** and other kinds: median, unique values,
  percent filled.
- **A summary of the selected rows,** or one per group.
- **A footer that stays in view** while the rows scroll.
- **Another source for the numbers,** for a table with a manual read
  action.

Further work on what a table offers is in the
[specification](https://github.com/StefanRoesch/ash_data_table/issues/21).
