# State in the URL

This guide covers reading and writing a table's address by hand, what a
shared link carries, and whether a table in your own page keeps its state in
the URL.

## The smallest example

The page of a router line (`ash_data_table "/tasks", MyApp.Tracker.Task`)
always keeps its table's sort, filters and page in the address, with no
setup. Reload, the back button and shared links work.

**Try it:** `/tasks` in the demo, as Ada Admin. Click the heading "Title",
then "Next" under the table. The address is now:

<!-- sketch -->
```text
/tasks?task[page]=2&task[sort]=title
```

Open it in a new tab: the same rows, the same heading marked as sorted.

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

Defaults are left out: no sort, no filters, the first page and the opening
page size give the plain path, `/tasks`.

Every change is a live patch (`push_patch`), so each is a browser history
entry and the back button steps through them.

## The parameter format

A table's parameters are nested under its id, so they cannot collide with the
page's own parameters or another table's.

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

- `COLUMN` is the field's name, or the column's `as` name.
  [Arguments](arguments.md) covers argument values and when they apply.
- The operators are `contains`, `equals`, `starts_with`, `is_empty`,
  `greater_than`, `less_than`, `at_least`, `at_most`, `on`, `before`, `after`,
  `between`, `is`, `any_of` and `none_of`; [Filtering](filtering.md) says
  which column offers which and which is the default.
- A cursor is the opaque value Ash returns for a record, not meant to be
  written by hand.

A complete example, with four filters and a sort:

<!-- sketch -->
```text
/tasks?task[f][billable%3F]=yes&task[f][due_on][is_empty]=&task[f][progress][at_least]=50&task[f][title]=report&task[sort]=-title
```

The table writes parameters in alphabetical order and percent-encodes what a
query string requires, such as the `?` in `billable?`. When reading, order
does not matter, and the default operator may be spelled out
(`task[f][title][contains]=report`).

## A table limited to the records of one parent

`of` limits a table to the records related to one record:
`/comments?comment[of][task][comments]=KEY` shows one task's comments, under a
heading that says so. This is a nested table's full view; the link in a
nested table's last row writes it.

- `PARENT` is the short name of the parent's resource (plus `_` and the table
  name where a [named table](named-tables.md) of the parent offers the
  relationship: `task_board`), `RELATIONSHIP` its relationship's name, and
  `KEY` its primary key. A key of several attributes is written per
  attribute: `ID[of][PARENT][RELATIONSHIP][ATTRIBUTE]=VALUE`.
- Sort, filters and page are written beside it, and it stays through every
  change of them. It is part of a shared link.
- "Show all records" above the table removes it, with the sort, filters and
  page chosen under it.

What the parameter can name, how the parent is looked up and read, and what
the page shows for a parent the person may not read: see
[Nested tables](nested-tables.md#the-full-view).

## The table's id

A mounted table's id defaults to the last part of the resource's module name,
underscored. The demo's router
([`demo/lib/demo_web/router.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo_web/router.ex)):

<!-- source: demo/lib/demo_web/router.ex -->
```elixir
ash_data_table "/tasks", Demo.Tracker.Task, layout: {DemoWeb.Layouts, :tasks}
ash_data_table "/projects", Demo.Tracker.Project
ash_data_table "/comments", Demo.Tracker.Comment
ash_data_table "/labels", Demo.Tracker.Label
ash_data_table "/task_labels", Demo.Tracker.TaskLabel
ash_data_table "/specimens", Demo.KitchenSink.Specimen
```

The ids are `task`, `project`, `comment`, `label`, `task_label` and
`specimen`. The path plays no part: `/tasks` has the id `task`.

A [named table](named-tables.md)'s id is the resource's id plus `_` and the
table name: `ash_data_table "/tasks/board", Demo.Tracker.Task, table: :board`
has the id `task_board`, with parameters like `task_board[sort]=title`.

`ash_data_table "/tasks", Demo.Tracker.Task, id: "tasks"` sets another id: lower-case
letters, digits, `_` and `-`, starting with a letter; anything else raises
when the router is compiled. The id also prefixes every DOM id of the table,
so changing it changes both saved links and your tests' selectors.

## What is ignored

The address is outside input. Whatever does not fit the table as the person
meets it is dropped silently; the rest applies.

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

The page does not say a parameter was ignored. The person's next change
writes a clean address.

## Shared links

A link carries the sort, filters, arguments and page, not the person. Whoever
opens it sees the table as the resource lets them: their records, their
columns. A sort or filter by a column the receiver cannot access is dropped
for them. Details: [Authorization](authorization.md).

In the demo, the "Acting as" switcher returns to the current address, so you
can watch one link change with the person.

## A table inside your own LiveView

A tag (`<AshDataTable.table>`) or a table attached with
`AshDataTable.attach/4` does **not** use the URL by default: the host page
owns its address, and the table cannot know whether it wants table parameters
there. Such a table keeps its sort, filters and page itself, for as long as
the LiveView lives; they are gone after a reload. (The three ways to place a
table: [Layout and embedding](layout-and-embedding.md).)

The demo's dashboard has two such tables
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

Neither is given `url`. (`heading` concerns the line above the table; see
[Layout and embedding](layout-and-embedding.md).)

**Try it:** `/dashboard`: sort one table and page the other. The address
stays `/dashboard`, and neither table moves when the other does.

### An attached table: `url: true`

An attached table keeps its state in the URL with `url: true`. This needs a
LiveView mounted by the router (`live/3`); one rendered inside another has no
URL of its own, and there `attach/4` raises an `ArgumentError`. The LiveView
needs no `handle_params/3`: the table hears every patch itself. The example
is from a test LiveView without `handle_params/3`
([`demo/test/support/attached_tables.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/test/support/attached_tables.ex)):

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

If the LiveView has a `handle_params/3`, it runs after the table has taken
its parameters. Call `attach/4` in `mount/3`: the table then reads when
LiveView hands over the URL, before the first render.

### A tag: `url`

To keep a tag's state in the URL, pass the page's current URL as `url`. The
demo's own pages don't, so the example is from a test LiveView
([`demo/test/support/plain_tables.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/test/support/plain_tables.ex)).
It assigns the URL `handle_params/3` receives:

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

Each table then patches the page's URL with its parameters under its id
(`?entries[sort]=title`) and reads its state from the URL on every update.
Everything above holds, as for the router page and an attached table with
`url: true`: format, what is ignored, reload, back button, shared links. The
page's tests
([`demo/test/demo_web/tables/embedded_url_table_test.exs`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/test/demo_web/tables/embedded_url_table_test.exs))
sort, filter and page both tables and open the resulting addresses.

`handle_params/3` is called for a LiveView mounted in the router. A LiveView
rendered inside another has no URL of its own to hand down.

### Setting the state from the page

A LiveView can set an attached table's, or the router page table's, sort,
filters, arguments or page with the command `AshDataTable.put_state/3`, in
this guide's parameter format; with the state in the URL, that patches the
URL. See [Events and commands](events-and-commands.md).

## Several tables on one page

Each table needs an `id` unique on the page. Two tables of one resource, its
default and a named one, differ without an `id` being written (`comment` and
`comment_compact`); the same table placed twice needs an `id` for each.
Because parameters are nested under the id, several URL-state tables share one
address without touching each other's state, and each leaves the others' and
the page's parameters in place when it patches. On the page above, paging the
tickets and then the entries gives:

<!-- sketch -->
```text
/support/url?entries[page]=2&tickets[after]=…
```

## Edge cases

- **A page number beyond the last page** is valid: "No records" and a way to
  the last page; see
  [Reading, sorting and pagination](reading-sorting-and-pagination.md).
- **An altered cursor** is not dropped, since the table cannot tell a valid
  cursor from an invalid one without reading. The read fails: "The records
  could not be loaded."
- **A filter change removes the page.** Any change of sort, filters,
  arguments or page size starts at the first page, so `page`, `after` and
  `before` leave the address.
- **An ignored parameter stays in the address** until the person changes
  something; then the table writes its state afresh without it.
- **A refused read keeps the address.** When the router page's read becomes
  refused while the page is open, the browser is sent to the same URL again,
  which then answers 404.
- **The locale and the actor are not in the URL.** They come from the session.
- **A limit names a record but gives no access to it.** The parent is read as
  the person on every read. A key of a record that is not theirs shows "This
  record is no longer available." and no rows.
- **Going back from a full view** returns to the page the link was on, with
  its address state. Rows expanded there are closed.

## Things people trip over

- **The id is `task`, not `tasks`.** It comes from the module name, not the
  path.
- **A table in your own LiveView forgets its state on reload.** That is the
  default. Pass `url` to a tag, or `url: true` to `attach/4`, to keep it.
- **Passing `url` to a tag without `handle_params/3`.** The table patches the
  URL, but the LiveView must receive the patch and hand the new URL down, or
  the table never sees its new state. An attached table with `url: true`
  needs none of this.
- **A link with an unknown operator or column.** Nothing fails; the filter is
  simply absent. Check the column's name and operators.
- **Expecting a link to show the sender's rows.** It shows the receiver's.

## Not in the first version

No saved views, no per-user memory of table state, no multi-column sort in
the address, and nothing of a nested table in the address except its full
view. The roadmap is in the
[specification](https://github.com/StefanRoesch/ash_data_table/issues/21).
