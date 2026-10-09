# Reading, sorting and pagination

After reading this guide you can choose the read action behind a table, set
its page size and default order, pick between offset and keyset pagination,
and say which columns a person can sort by and why.

Filtering has [its own guide](filtering.md), and so has
[what is kept in the URL](state-in-the-url.md).

## The smallest example

A table reads through one read action of its resource: the primary read
action, unless the block names another. Everything about how the records are
read is declared on that action. The primary read action of the demo's tasks
([`demo/lib/demo/tracker/task.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo/tracker/task.ex)):

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
read :read do
  primary? true

  pagination offset?: true,
             keyset?: true,
             countable: true,
             default_limit: 25,
             max_page_size: 100,
             required?: false

  prepare build(sort: [inserted_at: :desc, id: :desc])
end
```

**Try it:** `/tasks` in the demo, as Ada Admin. The page holds 25 tasks,
newest first, and says "1–25 of 320" under the table. None of the three
facts is in the `table` block.

## Everything runs on the server, through the read action

For every page it shows, the table builds a query for the read action and
runs it:

- the sort the person chose, with `Ash.Query.sort_input/2`;
- the filters the person set, with `Ash.Query.filter_input/2`;
- the calculations among the columns, and the related records of its
  [reference cells](columns-and-defaults.md#reference-cells), as loads;
- the page, as the `page` option of the read;
- the actor, the tenant and `authorize?`.

The aggregates among the columns are loaded onto the records of the page in
a statement of their own, after the page is read, as the same person
(`Ash.load/3`). Sorting and filtering by an aggregate are part of the
query all the same. The extra statement is there for a defect in the SQL
layer (tracked as #35): a statement that selects an aggregate beside a field
that a field policy hides on some records can fail as a page. On the demo's
`/tasks`, which has one aggregate column, it costs a statement of about a
millisecond and a half per read.

`sort_input` and `filter_input` are the functions Ash has for input from
outside, the ones the API extensions use. They accept public fields only.
The action's own filter, preparations and policies apply as they do for any
other caller. Nothing is sorted, filtered or cut into pages in the browser.

The table passes no arguments to the action.

## Page size and default sort live on the read action

The `table` block has no option for the page size and none for the default
order. This is the rule people least expect, and it is deliberate. A table is
an interface to the resource, as `ash_json_api` and `ash_graphql` are, and in
Ash it is the read action that says how records are paged and ordered. If the
block had its own page size, the same action would behave differently
depending on who called it, and there would be two places to look.

**Page size.** It is the action's `default_limit`. When the action has none
it is 25. It is never more than the action's `max_page_size`, which is 250
unless the action says otherwise.

| The action's `pagination` | Rows per page |
| --- | --- |
| `default_limit: 25, max_page_size: 100` | 25 |
| neither option, as in `defaults [:read]` | 25 |
| `max_page_size: 10`, no `default_limit` | 10 |
| `default_limit: 500`, no `max_page_size` | 250 |

A person cannot change the page size in the table.

**Default sort.** It is the sort the action's preparations build, such as
`prepare build(sort: [inserted_at: :desc, id: :desc])` above. While a person
sorts by a column, the action's sort still applies after theirs, as a
tie-breaker.

### A read action for the table

A table that needs its own page size, order or selection of records gets its
own read action. The demo's tasks have one for open tasks:

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
# A table with its own page size and default sort gets its own read action.
read :open do
  filter expr(status in ^TaskStatus.open())

  pagination offset?: true,
             keyset?: true,
             countable: true,
             default_limit: 10,
             max_page_size: 100

  prepare build(sort: [due_on: :asc_nils_last, id: :asc])
end
```

The block names the action with `read_action`. No demo page is mounted on
`open`, so this example is from the library's own test resources
([`test/support/reading.ex`](https://github.com/StefanRoesch/ash_table/blob/main/test/support/reading.ex)):

<!-- source: test/support/reading.ex -->
```elixir
  read :paged do
    pagination offset?: true, default_limit: 10, countable: true
  end
end

table do
  read_action :paged
end
```

The action has to be a `public?` read action of the resource. So has the
primary read action, where the block names none: a table runs no private
action, however it came by it. See
[Authorization](authorization.md#every-action-a-table-runs-is-public).

## Pagination

When the read action supports pagination, the table always paginates. Which
strategy it uses follows from the action, and `paginate_with` chooses when
the action supports both:

| The action supports | `paginate_with` | The table pages by |
| --- | --- | --- |
| offset only | not set | offset |
| keyset only | not set | keyset |
| both | not set | offset |
| both | `:keyset` | keyset |
| neither | not set | nothing: every record is loaded |

Naming a strategy the action does not support is a mistake the compiler
reports. The option's name and values are those of `ash_graphql`.

From the library's test resources:

<!-- source: test/support/reading.ex -->
```elixir
table do
  paginate_with :keyset

  column :title
  column :shouted_title
  column :comment_count
end
```

What a person gets differs by strategy:

| | Offset | Keyset | No pagination |
| --- | --- | --- | --- |
| Previous and Next | yes | yes | no controls |
| Page numbers | the first, the last and two either side of the current one, when the action is `countable`; else the current one only | no | |
| Position | "26–50 of 320" when the action is `countable`, else "26–50" | "320 records" when the action is `countable`, else nothing | |
| In the URL | the page number | a cursor | nothing |
| Sorting by a calculation or aggregate | yes | no | yes |
| Demo page | `/tasks`, `/projects`, `/specimens` | `/comments` | `/labels` |

The controls are a navigation landmark under the table. They are ordinary
buttons, and tab stops of their own after the table's.

Under either strategy the table asks the read for the count when the action
is `countable`, and only then. An offset table uses it for the range, the
last page number and the announcement after a filter change. A keyset table
has the total and nothing else: a cursor says where a page starts, not how
many records lie before it. So it shows the total alone, "320 records", and
announces it after a filter change. Counting is a query of its own on every
read; `pagination countable: false` on the action switches it off, and the
table then shows no total and announces "Results updated".

The comments in the demo are read by keyset only, twenty to a page. The
action does not say `countable`, and in Ash an action counts unless it says
`countable: false`:

<!-- source: demo/lib/demo/tracker/comment.ex -->
```elixir
read :read do
  primary? true
  pagination keyset?: true, default_limit: 20, max_page_size: 100, required?: false
  prepare build(sort: [inserted_at: :desc, id: :desc])
end
```

The labels are read without pagination. A read action that declares none
loads every record, without a warning, as it does for the other Ash
interfaces:

<!-- source: demo/lib/demo/tracker/label.ex -->
```elixir
read :read do
  primary? true
  prepare build(sort: [name: :asc])
end
```

Pages of more than a hundred rows or so are slow in the browser. There is no
virtual scrolling yet, so keep `default_limit` moderate and give a table on a
large resource a paginated action.

## Sorting

A click on a column's heading, or Enter while the heading has focus, sorts by
that column: ascending first, then descending, then not at all, which leaves
the action's own order. One column is sorted at a time. Any change of sort
returns to the first page; the filters stay.

**Which columns can be sorted is the resource's decision.** The table asks
`Ash.Resource.Info.sortable?/3`, with the pagination strategy the table uses:

| Column | Offset or no pagination | Keyset |
| --- | --- | --- |
| An attribute | yes, unless it is declared `sortable?: false` or is an array or a map | the same |
| A calculation with an expression | yes | no |
| A calculation computed in Elixir | no | no |
| An aggregate | yes | no |
| A reference cell | no | no |

For one person an aggregate column can be without its sort where the table
has it for others: an aggregate that a field policy hides from them on some
records. See
[Columns and defaults](columns-and-defaults.md#what-a-table-does-not-sort-by).

A calculation or an aggregate cannot be sorted under keyset pagination
because that is Ash's answer: `sortable?/3` says no for both when the
pagination type is keyset, and the table does not second-guess it. If a table
has to sort by an aggregate, page it by offset.

The block can switch sorting off for a column, and cannot switch it on:

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
# long text, with sorting and filtering switched off
column :description do
  sortable? false
  filterable? false
end
```

`sortable? true` on a column the resource does not allow to be sorted is
reported when the resource is compiled. See
[Mistakes at compile time](mistakes-at-compile-time.md).

**Try it:** on `/tasks`, "Comments" (an aggregate) and "Overdue?" (an
expression calculation) sort. "Headline" (computed in Elixir) and
"Description" (`sortable? false`) do not: a click on their heading does
nothing.

## Reading related records

A nested table, and a page limited to the records of one parent, do not
read their resource's action directly. They read the **parent record by its
primary key, as the person**, with the relationship as a load that carries
the query described above: the sort, the filters and the page.

What differs from a table of its own:

- The read action is the relationship's own `read_action` when it has one,
  else the one of the destination's table. Either has to be `public?`.
- The parent record is read through the read action of the table that
  shows it.
- With no sort chosen by the person, the relationship's own `sort` comes
  first.
- There are pages only where Ash can page the relationship. A single related
  record has no sort, no filters and no pages.
- The records are read bare, and everything the columns show besides
  attributes is loaded onto them afterwards.
- No total is asked for while a filter is set on a column the person sees
  on some records only.

Each of these is explained in [Nested tables](nested-tables.md).

## Loading, empty and failed reads

The first read runs while the page is mounted, so the first render already
has its rows. Later reads run beside the LiveView process: the table is
marked `aria-busy`, and the previous rows stay in view, dimmed, until the
new ones arrive.

A read that succeeds and finds nothing shows "No records".

A read that is refused is a matter of [authorization](authorization.md). Any
other failure takes the rows away and puts a message in their place:

| The failure | What the person reads |
| --- | --- |
| An error the read action returned on purpose: Ash's "invalid" class, such as an argument it requires or an error a preparation added | The error's message. It names a field only if the person has a column for it. |
| Anything else: a database error, an exception in a preparation | "The records could not be loaded." The error itself is logged. |

The demo has no page that fails. The library's tests use a test-only
resource for it
([`demo/test/demo_web/tables/failed_read_test.exs`](https://github.com/StefanRoesch/ash_table/blob/main/demo/test/demo_web/tables/failed_read_test.exs)).

## Edge cases

- **A page beyond the last** (`/tasks?task[page]=99`) shows "No records" and
  "Page 99". When the action is `countable`, the page numbers are the pages
  there are and the one the person is at (1, 13 and 99), and Previous leads
  to the last page, not to page 98. Without a count the table does not know
  where the last page is: Previous goes back one page at a time.
- **A keyset cursor that somebody altered in the URL** shows "The records
  could not be loaded."
- **An exception raised by the very first read** is not caught: the page
  fails as any LiveView does that crashes in `mount`. The same exception on a
  later read shows the message above.
- **A read action with a required argument** fails every read, since the
  table supplies none. The person reads the action's message, "is required".
- **An offset action that is not `countable`** has no total and no last page
  number. Next is offered as long as Ash reports more records.
- **A keyset table does not say where its page lies.** Its rows are numbered
  from the top of each page for assistive technology, also when the total is
  known; see [Keyboard and accessibility](keyboard-and-accessibility.md#what-assistive-technology-is-told).
- **Under keyset pagination a new sort starts at the first page.** A cursor
  belongs to the order it was made in.
- **A resource without a primary read action** needs `read_action`. With
  editable columns, row actions or a create action, and calculation,
  aggregate or reference columns, it needs a primary read action all the
  same; see [Inline editing](inline-editing.md).
- **A resource whose primary read action is private** needs `read_action`
  with a public one, and its table can then only read: Ash loads what a
  create, an update or a destroy action returns through the primary read
  action. See
  [Authorization](authorization.md#every-action-a-table-runs-is-public).
- **A row that a person creates or deletes in the table changes the total
  by one**, and a new row stands at the top of the page, without a read.
  The next read counts and orders afresh. See
  [Row actions and create](row-actions-and-create.md#the-total).
- **Sorting by a field that is hidden from the person on some records** is
  possible and gives nothing away. See [Authorization](authorization.md).

## Things people trip over

- **Looking for `page_size` or `sort` in the block.** They are
  `pagination default_limit:` and `prepare build(sort:)` on the read action.
- **A custom read action is not paginated by default.** `defaults [:read]`
  supports both strategies; `read :name do … end` supports none until it has
  a `pagination` line. Without one the table loads every record.
- **250 rows per page.** A `default_limit` above the action's
  `max_page_size` is capped at it, and the default maximum is 250.
- **No order at all.** Without a sort on the action, records come in whatever
  order the data layer returns them, and pages are not stable.
- **Choosing keyset and losing a sort.** Calculations and aggregates stop
  being sortable. The compiler says so only where the block asks for
  `sortable? true`.

## Not in the first version

No sorting by several columns, no page-size control for the person, no
virtual scrolling and no search across columns. The later slices and what is
out of scope are listed in the
[specification](https://github.com/StefanRoesch/ash_table/issues/21).
