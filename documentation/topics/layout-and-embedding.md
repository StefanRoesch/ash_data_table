# Layout and embedding

A table reaches a page in one of two ways: mounted as a page of its own, with
one line in the router, or embedded in a LiveView of yours, with one tag.
After reading this guide you can put a mounted table into your app's layout,
place tables in your own pages, and say how the two differ, down to what a
refused read does in each.

## The smallest examples

**Mounted.** A line in the router, and one setting so that the page gets your
app's layout
([`demo/config/config.exs`](https://github.com/StefanRoesch/ash_table/blob/main/demo/config/config.exs)):

<!-- source: demo/config/config.exs -->
```elixir
config :ash_table,
  layout: {DemoWeb.Layouts, :app},
  # ...
```

(A line `# ...` stands for lines that are left out: here, the two settings
for translations.)

**Embedded.** A tag in a LiveView's template
([`demo/lib/demo_web/live/dashboard_live.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo_web/live/dashboard_live.ex)):

<!-- source: demo/lib/demo_web/live/dashboard_live.ex -->
```heex
<AshTable.table
  id="dashboard-projects"
  resource={Demo.Tracker.Project}
  heading={2}
  actor={@current_user}
  tenant={@current_tenant}
/>
```

**Try it:** `/tasks` is a mounted table and `/dashboard` a page with two
embedded ones.

## The layout of a mounted table

A LiveView mounted by the router is rendered in the root layout only. Since
Phoenix 1.8 the app layout is a function component that each page calls
itself, so the table's ready-made page cannot pick yours up. It has to be
told which component to call. That is the `layout` setting above: a
`{module, function}` pair naming a function component.

The component is called with the table as its inner block and with these
assigns:

| Assign | Value |
| --- | --- |
| `flash` | The socket's flash. |
| `current_scope` | The socket's `current_scope`, or nil when it has none. |
| `current_user`, `current_tenant` | The socket's, each only when the socket has that assign. |
| The assigns the resource's domain names as `scope_assign`, `actor_assign` and `tenant_assign` | The socket's, under those names, each only when the socket has that assign. |

This fits the `app/1` that Phoenix 1.8 generates. With the default names the
last row adds nothing to the two above it. A domain that names its own
assigns has a layout that expects them under those names, and gets them. The
demo's domains keep the defaults, so this example is from the demo's tests
([`demo/test/support/guarded_tables.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/test/support/guarded_tables.ex)).
The domain:

<!-- source: demo/test/support/guarded_tables.ex -->
```elixir
table do
  scope_assign :viewer_scope
  actor_assign :reader
  tenant_assign :reader_organization
end
```

and a layout that is called with `reader`, `reader_organization` and
`viewer_scope`, as far as the socket has them:

<!-- source: demo/test/support/guarded_tables.ex -->
```heex
<p :if={assigns[:reader]} id="frame-reader">{@reader.name}</p>
<p :if={assigns[:reader_organization]} id="frame-organization">{@reader_organization}</p>
<p :if={assigns[:viewer_scope]} id="frame-scope">{@viewer_scope.user.name}</p>
{render_slot(@inner_block)}
```

A layout that needs anything else gets a small wrapper component of yours
that supplies it.

The setting is read when the page is rendered, so it can be changed without
recompiling the dependency. `mix ash_table.install` sets it when your app has
`MyAppWeb.Layouts.app/1`.

Inside the layout the page is the table, and the first line of the table is
the page's heading: the table's name as an `h1` at the left and, where the
table has a create action that the person may run, its create button at the
right. The name is the resource's `plural_name`, or its short name, in
words: "Tasks", "Task labels". It is also the page title and the accessible
name of the table.

### One table with another layout, or none

The router line overrides the setting for its table. The demo mounts its
labels a second time without the layout
([`demo/lib/demo_web/router.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo_web/router.ex)):

<!-- source: demo/lib/demo_web/router.ex -->
```elixir
# The labels once more, without the app layout that the configuration
# (`config :ash_table, layout: …`) puts around the tables above.
ash_table "/bare/labels", Demo.Tracker.Label, layout: false
```

| On the router line | The page is rendered in |
| --- | --- |
| nothing | The component named by `config :ash_table, layout:`; bare when there is no such setting. |
| `layout: {Module, :function}` | That component. |
| `layout: false` | No layout: bare, in the root layout. |

**Try it:** compare `/labels` and `/bare/labels` in the demo.

A bare table is its heading and the table, with nothing around them. It
brings no landmark of its own, because it cannot know which landmarks the
page already has. If your `<main>` is in the app layout, as Phoenix
generates it, a bare page has none, and accessibility checkers report it.
Either put `<main>` around `{@inner_content}` in the root layout, as the demo
does, or give the table a layout that has one.

### The router line

`ash_table path, resource, options` expands to a `live` route. It sits in
whichever `scope`, pipeline and `live_session` surround it, so the page gets
your plugs and your `on_mount` hooks like any LiveView of your own.

| Option | Default | Meaning |
| --- | --- | --- |
| `id` | The last part of the resource's module name, underscored | The table's id: the prefix of its DOM ids and the name of its URL parameters. See [State in the URL](state-in-the-url.md). |
| `layout` | The configuration's | See above. |

The resource is written in full. The alias of a surrounding
`scope "/", MyAppWeb` is not applied to it. Any other option raises when the
router is compiled.

## Embedding a table in your own LiveView

`<AshTable.table>` renders the same table inside a page you own. The demo's
dashboard places two of them in its own layout, under its own `h1`, each in
a section of its own:

<!-- source: demo/lib/demo_web/live/dashboard_live.ex -->
```heex
<section id="dashboard-tasks-section" aria-labelledby="dashboard-tasks-name">
  <AshTable.table
    id="dashboard-tasks"
    resource={Demo.Tracker.Task}
    heading={2}
    actor={@current_user}
    tenant={@current_tenant}
  />
</section>
```

| Attribute | Required | Meaning |
| --- | --- | --- |
| `id` | yes | Unique on the page. It prefixes every DOM id of the table. |
| `resource` | yes | A resource that lists `AshTable.Resource`. |
| `scope` | | An `Ash.Scope` carrying actor and tenant. |
| `actor`, `tenant` | | Used when no `scope` is given. |
| `authorize?` | | Overrides the domain's `authorize?` for this table, either way. |
| `url` | | The page's current URL. When given, the table keeps its state in it. See [State in the URL](state-in-the-url.md#a-table-inside-your-own-liveview). |
| `label` | | The table's name: the accessible name of the grid, and the text of the line above it. Defaults to the name described above. |
| `heading` | | How the name is shown on the line above the table: `true` (the default), a number from 1 to 6, or `false`. See below. |

The table is a LiveComponent, so the page has to be a LiveView. It renders
no layout; that is yours.

### The line of the table's name

Above its grid a table has one line: its name at the left and its create
button at the right. On a mounted page that line is the page's `h1`. An
embedded table cannot know the outline of the page it is in, so `heading`
says what the name is:

| `heading` | The name is | The line |
| --- | --- | --- |
| `true`, the default | Text that is no heading. | The name, and the create button where there is one. |
| A number from 1 to 6 | A heading of that level: `heading={2}` renders an `h2`. | The same. |
| `false` | Left out, for a page that names the table itself. | The create button alone, where there is one; else no line at all. |

The element of the name has the id of the table followed by `-name`. The
dashboard uses it to name each section by its table
(`aria-labelledby="dashboard-tasks-name"`), so the page has no heading of
its own to keep in step with the table.

The create button is there for a table whose block names a `create_action`
that the person may run; see
[Row actions and create](row-actions-and-create.md#creating-records). The
line is the table's and is rendered by it. There is no slot in it.

**Try it:** `/dashboard` as Ada Admin: "Projects" with "New project" and
"Tasks" with "New task", each on one line. As Max Member the first line is
"Projects" alone: a member may not create projects.

### Passing scope, actor and tenant

An embedded table does not look at socket assigns. It reads and saves as
whoever its attributes say: `scope`, or `actor` and `tenant`. With none of
them, nobody is asking. The assign names of the domain section are for
mounted tables only.

The dashboard passes the actor and the tenant. A page whose app has a scope
passes that instead. The demo's own pages have no scope, so this example is
from a LiveView that exists for the demo's tests
([`demo/test/support/plain_tables.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/test/support/plain_tables.ex)):

<!-- source: demo/test/support/plain_tables.ex -->
```heex
<%!-- a domain with `authorize? false`, and the table told nothing --%>
<AshTable.table id="open" resource={Unguarded.Note} />
<%!-- the same resource, the table told to authorize --%>
<AshTable.table id="checked" resource={Unguarded.Note} authorize?={true} />
<%!-- who is asking as a scope --%>
<AshTable.table id="scoped" resource={Guarded.Note} scope={assigns[:viewer_scope]} />
```

The first two tables show `authorize?`. An embedded table authorizes as its
resource's domain says, which is `true` unless the domain says otherwise;
`authorize?={true}` or `authorize?={false}` on the tag wins over the domain.
See [Authorization](authorization.md) for what `authorize? false` means.

## Mounted against embedded

| | Mounted | Embedded |
| --- | --- | --- |
| Declared in | the router, with `ash_table` | a template, with `<AshTable.table>` |
| The page | the library's, in your layout | yours |
| The table's name, above the grid | an `h1` | text, a heading of the level `heading` gives, or left out |
| `id` | defaults to the resource's name | required |
| Who is asking | the socket assigns the domain names | the attributes `scope`, or `actor` and `tenant` |
| `authorize?` | the domain's | the domain's, unless the attribute is given |
| Sort, filters and page | in the URL | in the component, unless `url` is given |
| Several on one page | no: one table per route | yes, each with its own `id` |
| A read refused outright | the page answers 404 | the table renders nothing |
| A read refused outright, with `on_forbidden :message` | "You are not allowed to see these records." | the same message |

Everything else is the same table: columns, sorting, filtering, pagination,
inline editing, row actions and create, nested tables, what each person may
see and do, the keyboard, the translations.

### What a refused read does

A mounted table whose read the resource refuses outright makes its page
answer as if it did not exist. An embedded table cannot do that: the page is
yours, and one table in it has no business turning it into a 404. So it
renders nothing at all. Nothing in the page says that a table would be
there.

**Try it:** `/dashboard` in the demo, as nobody. The projects' read is
refused, so nothing of that table is there: no grid, and no line with its
name either, since the table renders that line. The tasks' read is only
filtered, so the tasks table is there, under its name, and says "No
records".

With `on_forbidden :message` in the resource's `table` block, both kinds of
table show the message in place of the rows.

## Edge cases

- **The embedded table is asked again when its attributes change.** What a
  person can never see or do is asked of Ash when the table is first rendered
  and whenever the attributes it is given change. Pass a new `actor` and the
  table follows.
- **Nothing remains of a refused embedded table but an empty, hidden
  element** with the table's id. The name the table renders is gone with
  it. A heading of your own stays, and so does what points at the table's
  name: on the demo's dashboard, the projects' section is then labelled by
  an element that is not there. Consider what the page should show a person
  who gets no table.
- **`heading` is not checked.** A number outside 1 to 6 is rendered as it
  is given, which is no HTML heading.
- **The full view in an embedded table.** A table with `url` that is limited
  to the records of one parent has a second line under its name, which says
  what it is limited to. The create button is then on that line.
- **A domain that names its own assigns** changes where the mounted table
  finds the actor, and adds those assigns to what the layout is given. The
  layout still receives `current_scope`, and `current_user` and
  `current_tenant` when the socket has them: a host's `on_mount` hooks may
  set them for its own layout whatever the domain says.
- **An assign the socket does not have is not passed**, so a layout declares
  a default for what may be missing (`attr :reader, :map, default: nil`) or
  asks with `assigns[:reader]`. `current_scope` is the exception: it is
  always passed, as nil when the socket has none.
- **`layout:` on the router line is checked when the router is compiled**: it
  has to be `{module, function}` or `false`. That the function exists is
  found out when the page is rendered.
- **Route helpers.** For apps that still generate them, the route is named
  after the id: `ash_table_task` for the id `task`.
- **Two routes for one resource**, as `/labels` and `/bare/labels` in the
  demo, are two pages of the same table with the same id. Give one of them
  another `id` if their saved links should differ.

## Things people trip over

- **The mounted table has no navigation and no flash.** No `layout` is
  configured, so the page is bare.
- **Using an alias in the router line.** `ash_table "/tasks", Task` inside
  `scope "/", MyAppWeb` does not become `MyAppWeb.Task`; write the resource's
  full name.
- **An embedded table shows nothing to anyone.** It was given no `actor` or
  `scope`. The socket assigns are not read for it.
- **Two embedded tables with the same `id`.** The id is the component's
  identity and the prefix of every DOM id of the table, so each table on a
  page needs its own.
- **Expecting a 404 from an embedded table.** It renders nothing; decide in
  your LiveView who may open the page.
- **A custom `<h1>` above a mounted table.** The page already has one with
  the table's name. For a page with your own headings, embed the table.
- **The name twice over an embedded table.** Your own heading and the
  table's line both show it. Pass `heading={false}`, or drop your heading
  and give the table its level.

## Not in the first version

No slots for a toolbar or a custom heading on the mounted page, no theming,
and no single router line for all resources of a domain. See
the [specification](https://github.com/StefanRoesch/ash_table/issues/21).
