# Reading, sorting and pagination

This guide covers the read action behind a table, its page size and default
order, a page-size menu, offset and keyset pagination, and which columns sort.
[Filtering](filtering.md), [state in the URL](state-in-the-url.md) and
[arguments](arguments.md) have their own guides.

## The smallest example

A table reads through one read action of its resource: the primary one,
unless the block names another. How records are read is declared on that
action. The primary read action of the demo's tasks
([`demo/lib/demo/tracker/task.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/task.ex)):

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
read :read do
  primary? true
  # ...
  pagination offset?: true,
             keyset?: true,
             countable: true,
             default_limit: 25,
             max_page_size: 100,
             required?: false

  prepare build(sort: [inserted_at: :desc, id: :desc])
end
```

(Left out: the action's search-term argument, see [Arguments](arguments.md).)

**Try it:** `/tasks` in the demo, as Ada Admin: 25 tasks, newest first,
"1–25 of 320" under the table. None of this is in the `table` block.

## Everything runs on the server, through the read action

For every page, the table builds a query for the read action and runs it with:

- the person's arguments for the action, via `Ash.Query.for_read/4`;
- the person's sort, via `Ash.Query.sort_input/2`;
- the person's filters, via `Ash.Query.filter_input/2`;
- as loads: the calculation columns, each with its column's arguments, and
  the related records of
  [reference cells](columns-and-defaults.md#reference-cells);
- the page, as the read's `page` option;
- the actor, the tenant and `authorize?`.

Aggregate columns are loaded onto the page's records in a separate statement
after the read, as the same person (`Ash.load/3`). Sorting and filtering by an
aggregate stay in the query. The extra statement works around a SQL-layer
defect (#35): a statement that selects an aggregate beside a field a field
policy hides on some records is wrapped in a subquery, and the outer statement
returns the rows in no particular order. On the demo's `/tasks` (one
aggregate column) it costs about 1.5 ms per read.

`sort_input` and `filter_input` are Ash's functions for outside input, used by
the API extensions; they accept public fields only. The action's own filter,
preparations and policies apply as for any caller. Nothing is sorted,
filtered or paged in the browser.

## Page size and default sort live on the read action

The `table` block has no page-size option and no default-order option. This
is deliberate: a table is an interface to the resource, like `ash_json_api`
and `ash_graphql`, and in Ash the read action decides paging and order. A
page size in the block would make the same action behave differently per
caller, with two places to look.

**Page size** is the action's `default_limit`, 25 if it has none, and never
more than its `max_page_size` (250 unless the action says otherwise).

| The action's `pagination` | Rows per page |
| --- | --- |
| `default_limit: 25, max_page_size: 100` | 25 |
| neither option, as in `defaults [:read]` | 25 |
| `max_page_size: 10`, no `default_limit` | 10 |
| `default_limit: 500`, no `max_page_size` | 250 |

A person can change the page size only if the block offers a choice: see
[Letting a person choose the page size](#letting-a-person-choose-the-page-size).

**Default sort** is the sort the action's preparations build, such as
`prepare build(sort: [inserted_at: :desc, id: :desc])` above. When a person
sorts by a column, the action's sort still applies after theirs as a
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

The block names it with `read_action`. No demo page uses `open`, so this
example is from the library's test resources
([`test/support/reading.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/test/support/reading.ex)):

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

The action must be a `public?` read action of the resource, and so must the
primary read action when the block names none: a table runs no private
action. See
[Authorization](authorization.md#every-action-a-table-runs-is-public).

### Letting a person choose the page size

`page_sizes` in the block adds a "Rows per page" menu beside the pagination.
The demo's tasks offer three sizes:

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
page_sizes [10, 25, 50]
```

The read action stays the authority; the block only picks which allowed sizes
to offer. Checked at compile time (see
[Mistakes at compile time](mistakes-at-compile-time.md)):

- No size may exceed the action's `max_page_size` (250 if it names none).
- The action's `default_limit` must be one of the sizes; the table opens with it.
- Without a `default_limit`, the table opens with the first size as written.
  The default of 25 does not apply then, whether or not 25 is in the list.
- At least two sizes, each once.

The menu lists the sizes in ascending order, whatever order you wrote.

Choosing a size applies at once: the table goes to its first page and keeps
the sort, filters and arguments. This holds under keyset pagination too (a
cursor belongs to the size it was made with). The range ("1–50 of 320"),
page numbers and "Select all 320 that match" follow the new size.

The choice is table state, like the sort: `task[per]=50` in the URL of a table
that keeps its state there (the router page, a tag given `url`, a table
attached with `url: true`); otherwise the table keeps it itself (nested, or
keeping its own state). The opening size is left out of the URL. See
[State in the URL](state-in-the-url.md).

A size not in `page_sizes` (`/tasks?task[per]=1000`, or a made-up event) is
ignored and the table reads with its opening size. The server never reads a
larger page than the block offers.

`page_sizes` belongs to one table: a [named table](named-tables.md) has its
own or none. A nested table and a picker show the menu of the table they
show, except:

- A nested table without pages has no menu: a single related record, a
  relationship Ash cannot page, or a read action with a required argument
  (see [Nested tables](nested-tables.md)).
- A relationship with its own `read_action` is read through that action, which
  must allow the sizes too. For a relationship declared in a block, the
  compiler checks this. Where it is offered without being declared, or a
  picker reads through its own action, and that action does not allow the
  sizes, the table uses that action's page size and shows no menu.

The menu has a visible label and comes after Next, one more Tab stop, in a
nested table too.

**Try it:** on `/tasks` choose 50: the range says "1–50 of 320" and the
address ends in `?task[per]=50`. Open `/tasks?task[per]=1000`: 25 tasks.
`/comments` has the menu with keyset pagination; `/projects` has none.

## Pagination

When the read action supports pagination, the table always paginates. The
strategy follows from the action; `paginate_with` chooses when it supports
both:

| The action supports | `paginate_with` | The table pages by |
| --- | --- | --- |
| offset only | not set | offset |
| keyset only | not set | keyset |
| both | not set | offset |
| both | `:keyset` | keyset |
| neither | not set | nothing: every record is loaded |

Naming a strategy the action does not support is a compile error. The
option's name and values are those of `ash_graphql`. From the test resources:

<!-- source: test/support/reading.ex -->
```elixir
table do
  paginate_with :keyset

  column :title
  column :shouted_title
  column :comment_count
end
```

What a person gets per strategy:

| | Offset | Keyset | No pagination |
| --- | --- | --- | --- |
| Previous and Next | yes | yes | no controls |
| Page numbers | the first, the last and two either side of the current one, when the action is `countable`; else the current one only | no | |
| Position | "26–50 of 320" when the action is `countable`, else "26–50" | "320 records" when the action is `countable`, else nothing | |
| In the URL | the page number | a cursor | nothing |
| Sorting by a calculation or aggregate | yes | no | yes |
| Demo page | `/tasks`, `/projects`, `/specimens` | `/comments` | `/labels` |

The controls are a navigation landmark under the table: ordinary buttons, Tab
stops after the rows.

The table asks for the count only when the action is `countable`, under
either strategy:

- Offset uses it for the range, the last page number and the announcement
  after a filter change.
- Keyset shows only the total, "320 records", and announces it after a filter
  change; a cursor says where a page starts, not how many records precede it.
- Counting is an extra query on every read. `pagination countable: false`
  switches it off; the table then shows no total and announces "Results
  updated".

The demo's comments are read by keyset only, twenty to a page. The action
does not say `countable`, and in Ash an action counts unless it says
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
loads every record, without a warning, as with the other Ash interfaces:

<!-- source: demo/lib/demo/tracker/label.ex -->
```elixir
read :read do
  primary? true
  prepare build(sort: [name: :asc])
end
```

Pages over about a hundred rows are slow in the browser. There is no virtual
scrolling yet: keep `default_limit` moderate and give a table on a large
resource a paginated action.

## Sorting

A sortable column has a button in its heading. Click, Enter or Space cycles
ascending, descending, then off (the action's own order). One column is
sorted at a time. A sort change returns to the first page; filters stay.

**The resource decides which columns sort.** The table asks
`Ash.Resource.Info.sortable?/3` with its pagination strategy:

| Column | Offset or no pagination | Keyset |
| --- | --- | --- |
| An attribute | yes, unless it is declared `sortable?: false` or is an array, a map or an embedded resource. An array is never sorted by, whatever it holds: Ash says no for every array, as `ash_json_api` and `ash_graphql` do. For an embedded resource the table does not follow `sortable?/3`, which says yes: see below. | the same |
| A calculation with an expression | yes | no |
| A calculation computed in Elixir | no | no |
| An aggregate | yes | no |
| A reference cell | no | no |

An aggregate column can lose its sort for one person while others keep it:
when a field policy hides it from them on some records. See
[Columns and defaults](columns-and-defaults.md#what-a-table-does-not-sort-by).

An embedded resource is the one case where the table says no and
`sortable?/3` says yes: `Ash.Query.sort_input/2` refuses it ("is not
sortable"), and `ash_json_api` and `ash_graphql` leave embedded resources out
of sorting. The same goes for a NewType of a map. See
[Maps and embedded resources](maps-and-embedded-resources.md#sorting-and-filtering).

Under keyset pagination, `sortable?/3` says no for calculations and
aggregates, and the table follows Ash. To sort by an aggregate, page by
offset.

The block can switch sorting off for a column, never on:

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
# long text, with sorting and filtering switched off
column :description do
  sortable? false
  filterable? false
end
```

`sortable? true` on a column the resource does not allow to sort is a compile
error; see [Mistakes at compile time](mistakes-at-compile-time.md).

**Try it:** on `/tasks`, "Comments" (an aggregate) and "Overdue?" (an
expression calculation) sort. "Headline" (computed in Elixir) and
"Description" (`sortable? false`) do not: clicking their heading does nothing.

## Reading related records

A nested table, and a page limited to one parent's records, do not read their
resource's action directly. They read the **parent record by its primary key,
as the person**, with the relationship as a load carrying the query above:
sort, filters and page. The read action is the relationship's own
`read_action` if it has one, else the destination table's; either must be
`public?`. No total is asked for while a filter is set on a column the person
sees on some records only. The other differences (the relationship's own
`sort` first, pages only where Ash can page the relationship, records read
bare) are in
[Nested tables](nested-tables.md#how-a-nested-table-is-read-and-why).

## Loading, empty and failed reads

The table's first read on the page runs in place, before the first render, so
that render has its rows. Later reads, and every nested-table read, run
beside the LiveView process: the table is marked `aria-busy` and the previous
rows stay, dimmed, until the new ones arrive. A read still running when the
page is left or its table closes finishes its query and its result is
dropped; a running query is not cancelled, since that could cut a statement
off mid-way.

A successful read that finds nothing shows "No records".

A refused read is a matter of [authorization](authorization.md). Any other
failure replaces the rows with a message:

| The failure | What the person reads |
| --- | --- |
| An error the read action returned on purpose: Ash's "invalid" class, such as an argument it requires or an error a preparation added | The error's message. It names a field only if the person has a column for it. |
| Anything else: a database error, an exception in a preparation | "The records could not be loaded." The error itself is logged. |

No demo page fails; the tests use a test-only resource
([`demo/test/demo_web/tables/failed_read_test.exs`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/test/demo_web/tables/failed_read_test.exs)).

## Edge cases

- **A `sensitive?` field's column is not sorted by**: the row order would
  reveal what its masked cells hide. See
  [Sensitive columns](sensitive-columns.md).
- **A page beyond the last** (`/tasks?task[page]=99`) shows "No records" and
  "Page 99". With a `countable` action the page numbers are the existing pages
  plus the current one (1, 13 and 99), and Previous leads to the last page,
  not page 98. Without a count, Previous goes back one page at a time.
- **A keyset cursor altered in the URL** shows "The records could not be
  loaded."
- **An exception in the very first read** is not caught: the page fails like
  any LiveView that crashes on mount. The same exception on a later read shows
  the message above.
- **A read action with a required argument** is not run while that argument
  is empty; the table says "Fill in … to see records." in place of its rows.
  See [Arguments](arguments.md#a-required-argument).
- **An offset action that is not `countable`** has no total and no last page
  number. Next is offered as long as Ash reports more records.
- **A keyset table does not say where its page lies.** Its rows are numbered
  from the top of each page for assistive technology, even when the total is
  known; see [Keyboard and accessibility](keyboard-and-accessibility.md#what-assistive-technology-is-told).
- **Under keyset pagination a new sort starts at the first page**: a cursor
  belongs to the order it was made in.
- **A resource without a primary read action** needs `read_action`. With
  editable columns, row actions or a create action, and calculation,
  aggregate or reference columns, it still needs a primary read action; see
  [Inline editing](inline-editing.md).
- **A resource whose primary read action is private** needs a public
  `read_action`, and its table can then only read: Ash loads what a create,
  update or destroy returns through the primary read action. See
  [Authorization](authorization.md#every-action-a-table-runs-is-public).
- **Creating or deleting a row in the table changes the total by one**, and a
  new row stands at the top of the page, without a read. The next read counts
  and orders afresh. See
  [Row actions and create](row-actions-and-create.md#the-total).
- **Sorting by a field hidden from the person on some records** is possible
  and reveals nothing. See [Authorization](authorization.md).

## Things people trip over

- **Looking for `page_size` or `sort` in the block.** They are
  `pagination default_limit:` and `prepare build(sort:)` on the read action.
  `page_sizes` only offers a choice among sizes the action allows.
- **A custom read action is not paginated by default.** `defaults [:read]`
  supports both strategies; `read :name do … end` supports none until it has
  a `pagination` line. Without one the table loads every record.
- **250 rows per page.** A `default_limit` above `max_page_size` is capped,
  and the default maximum is 250.
- **No order at all.** Without a sort on the action, records come in whatever
  order the data layer returns, and pages are not stable.
- **Keyset loses sorts.** Calculations and aggregates stop being sortable. The
  compiler says so only where the block asks for `sortable? true`.

## Not in the first version

No sorting by several columns, no virtual scrolling, no search across
columns. Later slices and what is out of scope are in the
[specification](https://github.com/StefanRoesch/ash_data_table/issues/21).
