# State in the URL

After reading this guide you can read and write a table's address by hand,
know what a shared link carries and what it does not, and decide whether a
table in one of your own pages keeps its state in the URL.

## The smallest example

The page of a router line (`ash_data_table "/tasks", MyApp.Tracker.Task`)
keeps its table's sort, filters and page in the address, always, with no
setup. Reload, the back button and shared links work.

**Try it:** `/tasks` in the demo, as Ada Admin. Click the heading "Title",
then "Next" under the table. The address is now:

<!-- sketch -->
```text
/tasks?task[page]=2&task[sort]=title
```

Open that address in a new tab: the same rows, the same heading marked as
sorted.

## What is kept, and what is not

| Kept in the URL | Not kept |
| --- | --- |
| The sorted column and its direction | What has focus |
| Every filter that applies: column, operator, value | A filter value that was rejected as invalid |
| What the person gave the arguments of the read action, and those a column asks for | An argument's value that Ash refused; an argument that is as its input shows it with nothing chosen |
| The page number (offset) or the cursor (keyset) | An open editor, an open action panel, and what is typed in them |
| The page size a person chose under "Rows per page" | |
| The parent a table is limited to: the full view of a nested table | Cells whose save failed |
| | Which rows are expanded, and the sort, filters and page of the tables nested in them |
| | The mark of a row action that failed, and a row that was created and still stands at the top |
| | The widths a person gave the columns. They last until the page is reloaded or left: see [Columns and defaults](columns-and-defaults.md#column-widths) |
| | The columns a person hid. They are shown again when the page is reloaded or left: see [Columns and defaults](columns-and-defaults.md#hiding-columns) |
| | Which rows are selected. A selection lasts through a sort and a change of page, is given up when a filter, an argument or the limit to one parent changes, and is gone after a reload: see [Selecting rows and bulk actions](selecting-rows-and-bulk-actions.md#what-is-selected-and-for-how-long) |

A default is left out: no sort, no filters, the first page and the page size
the table opens with give the plain path, `/tasks`.

Every change is a live patch (`push_patch`), so each one is an entry in the
browser's history and the back button steps through them.

## The parameter format

All parameters of a table are nested under the table's id, so that they
cannot collide with the page's own parameters or with another table's.

| State | Parameter | Example |
| --- | --- | --- |
| Sorted ascending | `ID[sort]=COLUMN` | `task[sort]=title` |
| Sorted descending | `ID[sort]=-COLUMN` | `task[sort]=-title` |
| Page, under offset pagination | `ID[page]=N` | `task[page]=2` |
| Position, under keyset pagination | `ID[after]=CURSOR` or `ID[before]=CURSOR` | `comment[after]=…` |
| A page size the person chose, one of `page_sizes` | `ID[per]=N` | `task[per]=50` |
| A filter with the column's default operator | `ID[f][COLUMN]=VALUE` | `task[f][title]=report` |
| A filter with another operator | `ID[f][COLUMN][OPERATOR]=VALUE` | `task[f][progress][at_least]=50` |
| A filter whose operator takes no value | `ID[f][COLUMN][OPERATOR]=` | `task[f][due_on][is_empty]=` |
| A yes-or-no choice | `ID[f][COLUMN]=yes` or `=no` | `task[f][billable%3F]=yes` |
| A choice of an enum value | `ID[f][COLUMN]=VALUE` | `task[f][status]=in_review` |
| Several enum values | `ID[f][COLUMN][any_of][]=VALUE`, once per value; `none_of` likewise | `task[f][status][any_of][]=todo&task[f][status][any_of][]=done` |
| A range | `ID[f][COLUMN][between][from]=VALUE` and `[to]=VALUE`; an end left open is left out | `task[f][progress][between][from]=10&task[f][progress][between][to]=50` |
| An argument of the read action | `ID[a][ARGUMENT]=VALUE` | `task[a][search]=login` |
| An argument a column asks for | `ID[c][COLUMN][ARGUMENT]=VALUE` | `task[c][due_within][days]=14` |
| An argument that is a list | `ID[a][ARGUMENT][]=VALUE`, once per value | `deadline[a][tags][]=api` |
| Limited to the records related to one record | `ID[of][PARENT][RELATIONSHIP]=KEY` | `comment[of][task][comments]=3f649715-…` |

`COLUMN` is the field's name, or the name its column gives itself with `as`;
[Arguments](arguments.md) has what an argument's value is and when it is
applied. The operators are named `contains`, `equals`,
`starts_with`, `is_empty`, `greater_than`, `less_than`, `at_least`,
`at_most`, `on`, `before`, `after`, `between`, `is`, `any_of` and `none_of`;
[Filtering](filtering.md) says which
column offers which, and which one is the default. A cursor is the opaque
value Ash returns for a record and is not meant to be written by hand.

A complete example, with four filters and a sort:

<!-- sketch -->
```text
/tasks?task[f][billable%3F]=yes&task[f][due_on][is_empty]=&task[f][progress][at_least]=50&task[f][title]=report&task[sort]=-title
```

The table writes the parameters in alphabetical order and percent-encodes
what a query string requires, such as the `?` in `billable?`. When it reads
them the order does not matter, and it accepts the default operator spelled
out (`task[f][title][contains]=report`).

## A table limited to the records of one parent

The parameter `of` limits a table to the records related to one record:
`/comments?comment[of][task][comments]=KEY` shows the comments of one task,
under a heading that says so. This is the full view of a nested table, and
the link in the last row of a nested table writes it.

- `PARENT` is the short name of the parent's resource (followed by `_` and
  the table's name where a [named table](named-tables.md) of the parent
  offers the relationship: `task_board`), `RELATIONSHIP` the
  name of its relationship, and `KEY` its primary key. A key of several
  attributes is written by attribute:
  `ID[of][PARENT][RELATIONSHIP][ATTRIBUTE]=VALUE`.
- Sort, filters and page are written beside it, and it stays through every
  change of them. It is part of a shared link.
- "Show all records" above the table removes it, together with the sort,
  the filters and the page that were chosen under it.

What the parameter can name, how the parent is looked up and read, and what
the page shows for a parent that is not the person's to read, is in
[Nested tables](nested-tables.md#the-full-view).

## The table's id

The id of a mounted table defaults to the last part of the resource's module
name, underscored. The demo's router
([`demo/lib/demo_web/router.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo_web/router.ex)):

<!-- source: demo/lib/demo_web/router.ex -->
```elixir
ash_data_table "/tasks", Demo.Tracker.Task
ash_data_table "/projects", Demo.Tracker.Project
ash_data_table "/comments", Demo.Tracker.Comment
ash_data_table "/labels", Demo.Tracker.Label
ash_data_table "/task_labels", Demo.Tracker.TaskLabel
ash_data_table "/specimens", Demo.KitchenSink.Specimen
```

The ids are `task`, `project`, `comment`, `label`, `task_label` and
`specimen`. The path plays no part: `/tasks` has the id `task`.

A [named table](named-tables.md) has the resource's id followed by `_` and
the table's name: `ash_data_table "/tasks/board", Demo.Tracker.Task, table:
:board` has the id `task_board`, and its parameters are
`task_board[sort]=title`.

`ash_data_table "/tasks", Demo.Tracker.Task, id: "tasks"` sets another id. It is
a string of lower-case letters, digits, `_` and `-` that starts with a
letter; anything else raises when the router is compiled. The id also
prefixes every DOM id of the table, so changing it changes both the links
people have saved and the selectors of your tests.

## What is ignored

The address is input from outside. Whatever does not fit the table as the
person meets it is dropped silently, and the rest is applied.

| In the URL | Example | Result |
| --- | --- | --- |
| A sort by a column that does not exist, is not sortable or is private | `task[sort]=internal_note` | No sort |
| A page that is not a positive whole number | `task[page]=zero` | The first page |
| A cursor on a table paged by offset, or a page number on a keyset table | `task[after]=abc` | Ignored |
| A page size that is not one of the table's `page_sizes` | `task[per]=1000` | The size the table opens with |
| A filter on a column without a filter | `task[f][description]=x` | No filter |
| An operator the column does not offer | `task[f][title][at_least]=x` | No filter |
| A value that is not one of the column's type | `task[f][progress]=abc` | No filter |
| A list with a value the column does not have, or a range with an end that is no value | `task[f][status][any_of][]=todo&task[f][status][any_of][]=closed` | No filter |
| Two operators for one column | `task[f][title][contains]=a&task[f][title][equals]=b` | No filter |
| A column the person can never see | `task[f][external_ref]=EXT`, as Max Member | No filter |
| An argument the read action does not take from the outside, or a column does not ask for | `task[a][secret]=x`, `task[c][due_within%3F][days]=1` | Not given |
| An argument's value that Ash refuses | `task[c][due_within][days]=-1` | Not applied; shown in its input with Ash's message |
| A limit that names no relationship the person is offered to this table: an unknown resource, a relationship to another table, a private one, a key that is not one | `comment[of][task][labels]=…` | The table, not limited |
| Parameters that are not the table's | `utm=mail` | Left as they are, and kept when the table patches the URL |

Nothing in the page says that a parameter was ignored. The next change the
person makes writes a clean address.

## Shared links

A link carries the sort, the filters, the arguments and the page. It does
not carry the person. Whoever opens it sees the table as the resource lets them see it:
their records, their columns. A link that sorts or filters by a column the
receiver has no access to shows them the table without that sort or filter.
[Authorization](authorization.md) has the details.

In the demo, the "Acting as" switcher returns to the address you were at, so
you can watch one link change with the person.

## A table inside your own LiveView

A tag (`<AshDataTable.table>`) or a table attached with
`AshDataTable.attach/4` does **not** use the URL by default. The host page
owns its address, and the table cannot know whether the page wants table
parameters in it. Such a table keeps its sort, filters and page itself.
They last as long as the LiveView does and are gone after a reload. (See
[Layout and embedding](layout-and-embedding.md) for the three ways to place
a table.)

The demo's dashboard has two tables of this kind
([`demo/lib/demo_web/live/dashboard_live.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo_web/live/dashboard_live.ex)):

<!-- source: demo/lib/demo_web/live/dashboard_live.ex -->
```heex
<AshDataTable.table
  id="dashboard-tasks"
  resource={Demo.Tracker.Task}
  heading={2}
  actor={@current_user}
  tenant={@current_tenant}
  time_zone={@time_zone}
/>
```

Neither is given `url`. (`heading` is about the line above the table; see
[Layout and embedding](layout-and-embedding.md).)

**Try it:** `/dashboard` in the demo. Sort one table and page the other: the
address stays `/dashboard`, and neither table moves when the other does.

### An attached table: `url: true`

A table attached with `AshDataTable.attach/4` keeps its state in the URL
with `url: true`. That needs a LiveView mounted by the router (`live/3`),
not one rendered inside another, which has no URL of its own; elsewhere
`attach/4` raises an `ArgumentError`. The LiveView needs no
`handle_params/3` of its own: the table hears every patch itself. The
example is from a LiveView that exists for the demo's tests
([`demo/test/support/attached_tables.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/test/support/attached_tables.ex)),
which has no `handle_params/3`:

<!-- source: demo/test/support/attached_tables.ex -->
```elixir
def mount(_params, _session, socket),
  do:
    {:ok,
     AshDataTable.attach(socket, :bulletins, Bulletin,
       actor: socket.assigns[:reader],
       url: true
     )}
```

<!-- source: demo/test/support/attached_tables.ex -->
```heex
<AshDataTable.attached table={@bulletins} streams={@streams} />
```

Where the LiveView has a `handle_params/3`, it runs after the table has
taken its parameters. Call `attach/4` in `mount/3`: the table then reads
once LiveView hands the LiveView its URL, before the first render.

### A tag: `url`

To keep a tag's state in the URL, pass the page's current URL as `url`.
The demo's own pages do not do this, so the example is from a LiveView
that exists for the demo's tests
([`demo/test/support/plain_tables.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/test/support/plain_tables.ex)).
The LiveView assigns the URL that `handle_params/3` receives:

<!-- source: demo/test/support/plain_tables.ex -->
```elixir
@impl true
def handle_params(_params, url, socket) do
  {:noreply, assign(socket, :url, url)}
end
```

and hands it to its tables:

<!-- source: demo/test/support/plain_tables.ex -->
```heex
<AshDataTable.table id="entries" resource={Plain.Entry} url={@url} />
<AshDataTable.table id="tickets" resource={Plain.Ticket} url={@url} />
```

Each table then patches the page's URL, with its parameters under its id
(`?entries[sort]=title`), and reads its state from the URL on every update.
Everything above holds for it, as for the router page and an attached
table with `url: true`: the format, what is ignored, reload, the back
button and shared links.
The tests of this page
([`demo/test/demo_web/tables/embedded_url_table_test.exs`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/test/demo_web/tables/embedded_url_table_test.exs))
sort, filter and page both tables and open the addresses they arrive at.

`handle_params/3` is called for a LiveView that is mounted in the router. A
LiveView rendered inside another one has no URL of its own to hand down.

### Setting the state from the page

A LiveView can give an attached table, or the router page's table, a sort,
filters, arguments or a page itself with the command
`AshDataTable.put_state/3`, in the format of this guide's parameters; with
the state in the URL that patches the URL. See
[Events and commands](events-and-commands.md).

## Several tables on one page

Each table needs an `id` that is unique on the page. Two tables of one
resource, its default table and a named one, have different ids without one
being written (`comment` and `comment_compact`); the same table placed
twice needs an `id` for each. Because the parameters
are nested under the id, several tables with their state in the URL share
one address without
touching each other's state, and each leaves the other's parameters and the
page's own in place when it patches. On the page above, paging the tickets
and then the entries gives:

<!-- sketch -->
```text
/support/url?entries[page]=2&tickets[after]=…
```

## Edge cases

- **A page number beyond the last page** is a valid page number. The table
  shows "No records" and a way to the last page; see
  [Reading, sorting and pagination](reading-sorting-and-pagination.md).
- **A cursor that was altered** is not dropped, because the table cannot tell
  a valid cursor from an invalid one without reading. The read fails and the
  table says "The records could not be loaded."
- **A filter change removes the page.** Any change of sort, filters,
  arguments or page size starts again at the first page, so `page`, `after`
  and `before` disappear from the address.
- **An ignored parameter stays in the address** until the person changes
  something. Then the table writes its state afresh and the stray parameter
  is gone.
- **A refused read keeps the address.** When the router page's read comes
  to be refused while the page is open, the browser is sent to the same URL
  again, which then answers 404.
- **The locale and the actor are not in the URL.** They come from the
  session.
- **A limit names a record, and gives no access to it.** The parent is read
  as the person on every read. A key of a record that is not theirs shows
  "This record is no longer available." and no rows.
- **Going back from a full view** returns to the page the link was on, with
  the state in its address. The rows that were expanded there are closed.

## Things people trip over

- **The id is `task`, not `tasks`.** It comes from the module name, not from
  the path.
- **A table in your own LiveView forgets its state on reload.** That is
  the default. Pass `url` to a tag, or `url: true` to `attach/4`, if the
  state should survive.
- **Passing `url` to a tag without `handle_params/3`.** The table patches
  the URL, but the LiveView has to receive the patch and hand the new URL
  down, or the table never sees its new state. An attached table with
  `url: true` needs none of this.
- **Building a link with an unknown operator or column.** Nothing fails; the
  filter is not there. Check the column's name and its operators.
- **Expecting a link to show the sender's rows.** It shows the receiver's.

## Not in the first version

No saved views, no per-user memory of a table's state, no sort by several
columns in the address, and nothing of a nested table in the address but its
full view. The roadmap is in the
[specification](https://github.com/StefanRoesch/ash_data_table/issues/21).
