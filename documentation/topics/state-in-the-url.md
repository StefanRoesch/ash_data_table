# State in the URL

After reading this guide you can read and write a table's address by hand,
know what a shared link carries and what it does not, and decide whether a
table placed in one of your own pages keeps its state in the URL.

## The smallest example

A table mounted in the router keeps its sort, its filters and its page in the
address, with no setup. Reload, the back button and shared links work.

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
| The sorted column and its direction | Which cell has focus |
| Every filter that applies: column, operator, value | A filter value that was rejected as invalid |
| The page number (offset) or the cursor (keyset) | An open editor and what is typed in it |
| | Cells whose save failed |

A default is left out: no sort, no filters and the first page give the plain
path, `/tasks`.

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
| A filter with the column's default operator | `ID[f][COLUMN]=VALUE` | `task[f][title]=report` |
| A filter with another operator | `ID[f][COLUMN][OPERATOR]=VALUE` | `task[f][progress][at_least]=50` |
| A filter whose operator takes no value | `ID[f][COLUMN][OPERATOR]=` | `task[f][due_on][is_empty]=` |
| A yes-or-no choice | `ID[f][COLUMN]=yes` or `=no` | `task[f][billable%3F]=yes` |
| A choice of an enum value | `ID[f][COLUMN]=VALUE` | `task[f][status]=in_review` |

`COLUMN` is the field's name. The operators are named `contains`, `equals`,
`starts_with`, `is_empty`, `greater_than`, `less_than`, `at_least`,
`at_most`, `on`, `before` and `after`; [Filtering](filtering.md) says which
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

## The table's id

The id of a mounted table defaults to the last part of the resource's module
name, underscored. The demo's router
([`demo/lib/demo_web/router.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo_web/router.ex)):

<!-- source: demo/lib/demo_web/router.ex -->
```elixir
ash_table "/tasks", Demo.Tracker.Task
ash_table "/projects", Demo.Tracker.Project
ash_table "/comments", Demo.Tracker.Comment
ash_table "/labels", Demo.Tracker.Label
ash_table "/task_labels", Demo.Tracker.TaskLabel
ash_table "/specimens", Demo.KitchenSink.Specimen
```

The ids are `task`, `project`, `comment`, `label`, `task_label` and
`specimen`. The path plays no part: `/tasks` has the id `task`.

`ash_table "/tasks", Demo.Tracker.Task, id: "tasks"` sets another id. It is
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
| A filter on a column without a filter | `task[f][description]=x` | No filter |
| An operator the column does not offer | `task[f][title][at_least]=x` | No filter |
| A value that is not one of the column's type | `task[f][progress]=abc` | No filter |
| Two operators for one column | `task[f][title][contains]=a&task[f][title][equals]=b` | No filter |
| A column the person can never see | `task[f][external_ref]=EXT`, as Max Member | No filter |
| Parameters that are not the table's | `utm=mail` | Left as they are, and kept when the table patches the URL |

Nothing in the page says that a parameter was ignored. The next change the
person makes writes a clean address.

## Shared links

A link carries the sort, the filters and the page. It does not carry the
person. Whoever opens it sees the table as the resource lets them see it:
their records, their columns. A link that sorts or filters by a column the
receiver has no access to shows them the table without that sort or filter.
[Authorization](authorization.md) has the details.

In the demo, the "Acting as" switcher returns to the address you were at, so
you can watch one link change with the person.

## A table inside your own LiveView

A table placed with `<AshTable.table>` does **not** use the URL by default.
The host page owns its address, and the table cannot know whether the page
wants table parameters in it. Such a table keeps its sort, filters and page
in its own component state. They last as long as the LiveView does and are
gone after a reload.

The demo's dashboard has two tables of this kind
([`demo/lib/demo_web/live/dashboard_live.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo_web/live/dashboard_live.ex)):

<!-- source: demo/lib/demo_web/live/dashboard_live.ex -->
```heex
<AshTable.table
  id="dashboard-tasks"
  resource={Demo.Tracker.Task}
  actor={@current_user}
  tenant={@current_tenant}
/>
```

**Try it:** `/dashboard` in the demo. Sort one table and page the other: the
address stays `/dashboard`, and neither table moves when the other does.

To keep an embedded table's state in the URL, pass the page's current URL as
`url`. The demo does not do this, so the following is a sketch and not demo
code. The LiveView assigns the URL that `handle_params/3` receives:

<!-- sketch -->
```elixir
def handle_params(_params, url, socket) do
  {:noreply, assign(socket, :url, url)}
end
```

and hands it to the table:

<!-- sketch -->
```heex
<AshTable.table
  id="dashboard-tasks"
  resource={Demo.Tracker.Task}
  actor={@current_user}
  tenant={@current_tenant}
  url={@url}
/>
```

The table then patches the page's URL, with its parameters under its id
(`?dashboard-tasks[sort]=title`), and reads its state from the URL on every
update. This is the mechanism the mounted page uses.

## Several tables on one page

Each table needs an `id` that is unique on the page. Because the parameters
are nested under the id, several tables with `url` share one address without
touching each other's state, and each leaves the other's parameters and the
page's own in place when it patches.

## Edge cases

- **A page number beyond the last page** is a valid page number. The table
  shows "No records"; see
  [Reading, sorting and pagination](reading-sorting-and-pagination.md).
- **A cursor that was altered** is not dropped, because the table cannot tell
  a valid cursor from an invalid one without reading. The read fails and the
  table says "The records could not be loaded."
- **A filter change removes the page.** Any change of sort or filter starts
  again at the first page, so `page`, `after` and `before` disappear from the
  address.
- **An ignored parameter stays in the address** until the person changes
  something. Then the table writes its state afresh and the stray parameter
  is gone.
- **A refused read keeps the address.** When a mounted table's read comes to
  be refused while the page is open, the browser is sent to the same URL
  again, which then answers 404.
- **The locale and the actor are not in the URL.** They come from the
  session.

## Things people trip over

- **The id is `task`, not `tasks`.** It comes from the module name, not from
  the path.
- **An embedded table forgets its state on reload.** That is the default.
  Pass `url` if the state should survive.
- **Passing `url` without `handle_params/3`.** The table patches the URL,
  but the LiveView has to receive the patch and hand the new URL down, or the
  table never sees its new state.
- **Building a link with an unknown operator or column.** Nothing fails; the
  filter is not there. Check the column's name and its operators.
- **Expecting a link to show the sender's rows.** It shows the receiver's.

## Not in the first version

No saved views, no per-user memory of a table's state, and no sort by
several columns in the address. The roadmap is in the
[specification](https://github.com/StefanRoesch/ash_table/issues/21).
