# Layout and embedding

A table reaches a page in one of three ways, and all three are the same
table underneath:

- **Mounted**: a page of its own, with one line in the router.
- **Embedded**: placed in a LiveView of yours with the tag
  `<AshDataTable.table>`.
- **Attached**: put on a LiveView of yours with `AshDataTable.attach/4`, and
  drawn with the plain function component `<AshDataTable.attached>`.

After reading this guide you can put a mounted table into your app's layout,
place tables in your own pages either way, and say what each way can do that
the others cannot.

## The smallest examples

**Mounted.** A line in the router
([`demo/lib/demo_web/router.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo_web/router.ex)),
and one setting so that the page gets your app's layout
([`demo/config/config.exs`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/config/config.exs)):

<!-- source: demo/lib/demo_web/router.ex -->
```elixir
ash_data_table "/tasks", Demo.Tracker.Task
```

<!-- source: demo/config/config.exs -->
```elixir
config :ash_data_table,
  layout: {DemoWeb.Layouts, :app},
  # ...
```

(A line `# ...` stands for lines that are left out: here, the two settings
for translations.)

**Embedded.** A tag in a LiveView's template
([`demo/lib/demo_web/live/dashboard_live.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo_web/live/dashboard_live.ex)):

<!-- source: demo/lib/demo_web/live/dashboard_live.ex -->
```heex
<AshDataTable.table
  id="dashboard-projects"
  resource={Demo.Tracker.Project}
  heading={2}
  actor={@current_user}
  tenant={@current_tenant}
  time_zone={@time_zone}
/>
```

**Attached.** The same dashboard with its tables attached, from a page of the
demo's tests
([`demo/test/support/modes_tables.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/test/support/modes_tables.ex)):

<!-- source: demo/test/support/modes_tables.ex -->
```elixir
def mount(_params, _session, socket) do
  %{current_user: actor, current_tenant: tenant, time_zone: zone} = socket.assigns

  {:ok,
   socket
   |> assign(page_title: "Dashboard")
   |> AshDataTable.attach(:projects, Demo.Tracker.Project,
     id: "dashboard-projects",
     heading: 2,
     actor: actor,
     tenant: tenant,
     time_zone: zone
   )
   # ...
end
```

and, in its template:

<!-- source: demo/test/support/modes_tables.ex -->
```heex
<section id="dashboard-projects-section" aria-labelledby="dashboard-projects-name">
  <AshDataTable.attached table={@projects} streams={@streams} uploads={assigns[:uploads]} />
</section>
```

**Try it:** `/tasks` is a mounted table and `/dashboard` a page with two
embedded ones.

## Which way to choose

| | Mounted | Embedded | Attached |
| --- | --- | --- | --- |
| Declared in | the router, with `ash_data_table` | a template, with `<AshDataTable.table>` | `mount/3`, with `AshDataTable.attach/4`, drawn with `<AshDataTable.attached>` |
| The page | the library's, in your layout | yours | yours |
| The table's name, above the grid | an `h1` | text, a heading of the level `heading` gives, or left out | the same as embedded |
| `id` | defaults to the resource's name | defaults to the resource's name | defaults to the resource's name |
| Who is asking | the socket assigns the domain names | the attributes `scope`, or `actor` and `tenant` | the options `scope`, or `actor` and `tenant` |
| The time zone | the socket assign the domain names | the attribute `time_zone` | the option `time_zone` |
| Sort, filters and page | in the URL | in the table, unless `url` is given | in the table, unless `url: true` |
| Several on one page | no: one table per route | yes, each with its own `id` | yes, each under its own name and `id` |
| [Events](events-and-commands.md) the page hears | in an `on_mount` hook of its `live_session` | in `handle_info/2` | in `handle_info/2` |
| [Page values and the veto](events-and-commands.md) | on the router line | as attributes | as options |
| [Commands](events-and-commands.md) | in an `on_mount` hook, to the table `:table` | none | yes |
| [Controlled mode](controlled-mode.md) | no | no | yes |
| A read refused outright | the page answers 404 | the table renders nothing | the table renders nothing |

Everything else is the same table: columns, sorting, filtering, pagination,
inline editing, row actions and create, nested tables, what each person may
see and do, the keyboard, the translations, the [kit](kits.md) it is drawn
with.

So: mount a table when it is the whole page. Embed it when it is part of a
page and the page only needs to hear what happens. Attach it when the page
also tells the table what to do, or draws its questions, panels or pickers
itself.

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
| The assign it names as `time_zone_assign` (`time_zone` by default) | The socket's, when it has it: the zone the table's datetimes are in ([Time zones](time-zones.md)). |

This fits the `app/1` that Phoenix 1.8 generates. With the default names the
last rows add nothing to the ones above them. A domain that names its own
assigns has a layout that expects them under those names, and gets them. The
demo's domains keep the defaults, so this example is from the demo's tests
([`demo/test/support/guarded_tables.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/test/support/guarded_tables.ex)).
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
recompiling the dependency. `mix ash_data_table.install` sets it when your
app has `MyAppWeb.Layouts.app/1`.

Inside the layout the page is the table, and the first line of the table is
the page's heading: the table's name as an `h1` at the left and, where the
table has a create action that the person may run, its create button at the
right, followed by the buttons of its [table actions](table-actions.md). The
name is the resource's `plural_name`, or its short name, in words: "Tasks",
"Task labels". It is also the page title and the accessible name of the
table.

### One table with another layout, or none

The router line overrides the setting for its table. The demo mounts its
labels a second time without the layout:

<!-- source: demo/lib/demo_web/router.ex -->
```elixir
# The labels once more, without the app layout that the configuration
# (`config :ash_data_table, layout: …`) puts around the tables above.
ash_data_table "/bare/labels", Demo.Tracker.Label, layout: false
```

| On the router line | The page is rendered in |
| --- | --- |
| nothing | The component named by `config :ash_data_table, layout:`; bare when there is no such setting. |
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

`ash_data_table path, resource, options` expands to a `live` route. It sits in
whichever `scope`, pipeline and `live_session` surround it, so the page gets
your plugs and your `on_mount` hooks like any LiveView of your own.

| Option | Default | Meaning |
| --- | --- | --- |
| `table` | the default table | A [named table](named-tables.md) of the resource. |
| `id` | The last part of the resource's module name, underscored | The table's id: the prefix of its DOM ids and the name of its URL parameters. See [State in the URL](state-in-the-url.md). |
| `layout` | The configuration's | See above. |
| `authorize?` | What the resource's domain says | `false` mounts the page without authorization. Only for a page your own code protects: see [Authorization](authorization.md#authorize-false-on-one-page). |
| `live?` | What the resource's `table` block says | `false` mounts the table without [live updates](live-updates.md). |
| `kit`, `presentation` | The configuration's kit | The [kit](kits.md) the table is drawn with, and whether what opens is modal or inline. |
| `notify`, `open`, `context`, `private_arguments`, `page_arguments`, `before_action` | none | What the page hears of the table and gives it: see [Events and commands](events-and-commands.md). A function is written as `{module, function}`. |

The resource is written in full. The alias of a surrounding
`scope "/", MyAppWeb` is not applied to it. Any other option raises when the
router is compiled.

## Embedding a table in your own LiveView

`<AshDataTable.table>` renders the same table inside a page you own. The
demo's dashboard places two of them in its own layout, under its own `h1`,
each in a section of its own:

<!-- source: demo/lib/demo_web/live/dashboard_live.ex -->
```heex
<section id="dashboard-tasks-section" aria-labelledby="dashboard-tasks-name">
  <AshDataTable.table
    id="dashboard-tasks"
    resource={Demo.Tracker.Task}
    heading={2}
    actor={@current_user}
    tenant={@current_tenant}
    time_zone={@time_zone}
  />
</section>
```

| Attribute | Required | Meaning |
| --- | --- | --- |
| `id` | | Unique on the page. It prefixes every DOM id of the table. Defaults to the last part of the resource's module name, underscored (`task`), followed by `_` and the table's name for a named table (`task_board`). |
| `resource` | yes | A resource that lists `AshDataTable.Resource`. |
| `table` | | Which of the resource's tables is placed: the name of a [named table](named-tables.md). Left out, it is the default table. |
| `scope` | | An `Ash.Scope` carrying actor and tenant. |
| `actor`, `tenant` | | Used when no `scope` is given. |
| `authorize?` | | Overrides the domain's `authorize?` for this table, either way. |
| `live?` | | `false` places the table without [live updates](live-updates.md). |
| `url` | | The page's current URL. When given, the table keeps its state in it. See [State in the URL](state-in-the-url.md#a-table-inside-your-own-liveview). |
| `label` | | The table's name: the accessible name of the grid, and the text of the line above it. Defaults to the name described above. |
| `heading` | | How the name is shown on the line above the table: `true` (the default), a number from 1 to 6, or `false`. See below. |
| `time_zone` | | The zone its datetimes are shown, typed and filtered in. Nil is UTC. See [Time zones](time-zones.md). |
| `assigns` | | What a default of an asked argument that is a function is given. See below. |
| `kit`, `presentation` | | The [kit](kits.md) the table is drawn with, and whether what opens is modal or inline. |
| `notify`, `open`, `context`, `private_arguments`, `page_arguments`, `before_action` | | What the page hears of the table and gives it: see [Events and commands](events-and-commands.md). |

The tag is one live component, so the page has to be a LiveView. It renders
no layout; that is yours. It takes no commands: a page that needs them
attaches its table instead.

### The line of the table's name

Above its grid a table has one line: its name at the left and its create
button at the right. On a mounted page that line is the page's `h1`. An
embedded or attached table cannot know the outline of the page it is in, so
`heading` says what the name is:

| `heading` | The name is | The line |
| --- | --- | --- |
| `true`, the default | Text that is no heading. | The name, and the create button and the buttons of the table actions, where there are any. |
| A number from 1 to 6 | A heading of that level: `heading={2}` renders an `h2`. | The same. |
| `false` | Left out, for a page that names the table itself. | The buttons alone, where there are any; else no line at all. |

Anything else raises an `ArgumentError` when the table is rendered.

The element of the name has the id of the table followed by `-name`. The
dashboard uses it to name each section by its table
(`aria-labelledby="dashboard-tasks-name"`), so the page has no heading of
its own to keep in step with the table.

The create button is there for a table whose block names a `create_action`
that the person may run; see
[Row actions and create](row-actions-and-create.md#creating-records). The
line is the table's and is rendered by it. There is no slot in it; a
[kit](kits.md) can draw it differently.

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
([`demo/test/support/plain_tables.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/test/support/plain_tables.ex)):

<!-- source: demo/test/support/plain_tables.ex -->
```heex
<%!-- a domain with `authorize? false`, and the table told nothing --%>
<AshDataTable.table id="open" resource={Unguarded.Note} />
<%!-- the same resource, the table told to authorize --%>
<AshDataTable.table id="checked" resource={Unguarded.Note} authorize?={true} />
<%!-- who is asking as a scope --%>
<AshDataTable.table id="scoped" resource={Guarded.Note} scope={assigns[:viewer_scope]} />
```

The first two tables show `authorize?`. An embedded table authorizes as its
resource's domain says, which is `true` unless the domain says otherwise;
`authorize?={true}` or `authorize?={false}` on the tag wins over the domain.
See [Authorization](authorization.md) for what `authorize? false` means.

One more attribute, `assigns`, is for a table one of whose columns asks for
an argument with a default that is a function
(`ask :rate, default: &MyApp.Defaults.rate/1`): the function is given this
map, where a mounted or attached table gives it the assigns of its socket.
Pass what the function looks at, such as
`assigns={%{current_user: @current_user}}`; see
[Arguments](arguments.md#what-an-asked-argument-starts-with).

## Attaching a table to your own LiveView

`AshDataTable.attach/4` puts a table on the socket of your LiveView, under an
assign of the name you give it, and reads it. `<AshDataTable.attached>` draws
it where your template says. There is no live component: the table's events,
async reads and live updates reach it through hooks on your LiveView
(`Phoenix.LiveView.attach_hook/4`), which take what is the table's and let
everything else through to your own callbacks.

A page of the demo's browser tests attaches two tables, one of which keeps
its state in the URL
([`demo/e2e/server/attached_live.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/e2e/server/attached_live.ex)):

<!-- source: demo/e2e/server/attached_live.ex -->
```elixir
def mount(_params, _session, socket) do
  {:ok,
   socket
   |> assign(page_title: "Attached", notes: 0)
   |> stream(:notes, [])
   |> AshDataTable.attach(:labels, Demo.Tracker.Label,
     id: "label",
     table: :imports,
     heading: 2,
     url: true,
     actor: socket.assigns.current_user,
     tenant: socket.assigns.current_tenant
   )
   |> tasks(socket.assigns.current_user)}
end
```

<!-- source: demo/e2e/server/attached_live.ex -->
```heex
<AshDataTable.attached table={@labels} streams={@streams} uploads={assigns[:uploads]} />
<AshDataTable.attached table={@tasks} streams={@streams} uploads={assigns[:uploads]} />
```

- **The options** are the attributes of the tag, as a keyword list, and
  `controlled` ([Controlled mode](controlled-mode.md)). `url: true` keeps
  sort, filters and page in the page's URL; that needs a LiveView mounted by
  the router, not one inside another, and no `handle_params/3` of its own.
- **The assign** holds an `AshDataTable.Table`. Only the table changes it.
  Read what a page may know of it with `AshDataTable.status/1`, and give it
  [commands](events-and-commands.md#commands).
- **`streams` and `uploads`.** Pass `@streams`, and `assigns[:uploads]` where
  an action of the table takes a file (LiveView has the assign only once an
  upload is allowed).
- **Call it in `mount/3`.** The table then reads before the first render.
- **Attaching again** under the same name tells the table again, and it
  reads anew when who is asking changed: the demo page above attaches its
  tasks again as another person. Another resource, table or id under that
  name raises; `AshDataTable.detach/2` takes the table off first.
- **Names it takes.** The table uses events named `ash_data_table:…`, async
  keys `{:ash_data_table, _, _}` and messages `{:ash_data_table_heard, _, _}`
  on your LiveView; keep your own to other names.

**Try it:** the demo's browser tests drive this page at `/e2e/attached`, in
the e2e environment.

## Scrolling sideways

A table is as wide as the place it is in. When its columns need more, it
scrolls sideways in an area of its own, and the page around it does not.

- **Every table has its own area**: the table on a page, each
  [nested table](nested-tables.md) at every depth, and the table of a
  [picker](choosing-a-related-record.md). The scrollbar of a table is
  directly under its own rows.
- **A nested table is as wide as what is seen of the table around it**, less
  the one inset of its level (the default kit's look), not as wide as that
  table. It stays in place while the table around it
  scrolls under it, and scrolls by itself: a wide nested table in a wide
  table are two things to scroll, each without the other. So do the line
  that opens it, its "Columns" button and its pages.
- **Shift and the mouse wheel** (or a sideways swipe) scroll the table under
  the pointer, as the browser has it. A nested table that is scrolled to its
  end does not go on to scroll the table around it. The wheel alone scrolls
  the page, as everywhere.
- **A scrollbar that stays in reach.** (Not with a [header that stays in
  view](#a-header-that-stays-in-view): there the table's own scrollbar is
  in view.) A table that is higher than the window
  has its scrollbar below the window. While that is so, the table has a
  second scrollbar at the bottom edge of the window, as wide as the table's
  area. The two move together. It goes when the table's own scrollbar comes
  into view, and it is not there for a table that has nothing to scroll.
  Where tables are nested, the one bar belongs to the innermost table that is
  cut off at the bottom edge and has something to scroll: the table whose
  rows are seen above it. It is the browser's own scrollbar and looks like
  it; where the system's scrollbars lie over the content and show only while
  they are used, so does this one.
- **With the keyboard** nothing is scrolled by hand: the table scrolls with
  the focus. See
  [Keyboard and accessibility](keyboard-and-accessibility.md#scrolling).
- **Keeping a column in view** while the table scrolls is an option of the
  table: `sticky_label?`, see
  [Columns and defaults](columns-and-defaults.md#keeping-the-label-column-in-view).

Nothing of this is declared, and the server does not know where a table is
scrolled to: after a reload every table starts at its left edge.

Three things a host can say in CSS, on the table's element or anything
around it:

| Custom property | What it says | Default |
| --- | --- | --- |
| `--ash-data-table-ground` | The colour behind the cells that stay in view with `sticky_label?`: they have to cover what scrolls under them. | The default kit's theme colour `--color-base-100`, else the browser's `Canvas` |
| `--ash-data-table-line` | The colour of the edge beside those cells. | The default kit's `--color-base-content`, else `CanvasText` |
| `--ash-data-table-bottom` | How much of the bottom of the window the host covers with something of its own (a fixed footer), in pixels. The second scrollbar stays above it. | `0` |

<!-- sketch -->
```css
/* a table on a card of another colour, in an app with a footer 48px high */
.my-card { --ash-data-table-ground: var(--color-base-200); }
:root { --ash-data-table-bottom: 48px; }
```

The second scrollbar is placed in the window (`position: fixed`), within
what a scrolling element around the table shows of it. An element around the
table that has a `transform`, a `filter` or `contain: paint` makes the
browser place it relative to that element instead, which puts it in the
wrong place: keep those off the elements around a table.

**Try it:** `/tasks` in the demo. Expand the first row and open "Comments":
the comments scroll under their own rows, and the tasks stay. Scroll the
page until the comments reach below the window, and the scrollbar at the
bottom edge is theirs.

## A header that stays in view

`look: [sticky_header: true]` (see [Kits](kits.md#the-look-of-a-table))
gives a table a height of its own, as Airtable does: only the rows scroll,
up and down and sideways, inside the table, and the header with the filter
row stays at its top. It is plain CSS (`position: sticky` on the header
group, in the table's own scroll area); no script places anything.

- **How high.** The table on a page is at most `min(75dvh, 48rem)` high, a
  nested table about ten rows (`28rem`); `height` and `nested_height` say
  otherwise, as CSS lengths. A table with fewer rows is as high as its rows.
- **Nested tables and pickers' tables** have their own height and header
  that stays, each in a scroll area of its own. Each nested scroll area is a
  layer of its own, so its header never rises over the header of the table
  it is in; the header of the table on the page is drawn over everything
  nested. With `sticky_label?`, the label column's header is the corner, over
  both.
- **The focus is never hidden under the header.** A cell the keyboard moves
  to is scrolled into view below the header group (`scroll-padding-top`).
- **No second scrollbar** at the bottom edge of the window: the table's own
  is in view.
- **Square corners.** A scroll area whose header stays in view has square
  corners: a rounded corner clips the header and the rows under it alike,
  and the rows would show through its edge while they scroll.

A known browser limitation: in Firefox, while it scrolls on the graphics
card, the header of a table nested two levels deep can show for a moment
above the scroll area of the table it is in, outside it.

**Try it:** `/projects/sticky` in the demo. Expand a project, open its tasks and a
task's comments, and scroll inside the projects or inside the tasks: only the
rows move.

## What a refused read does

A mounted table whose read the resource refuses outright makes its page
answer as if it did not exist. An embedded or attached table cannot do that:
the page is yours, and one table in it has no business turning it into a
404. So it renders nothing at all. Nothing in the page says that a table
would be there.

**Try it:** `/dashboard` in the demo, as nobody. The projects' read is
refused, so nothing of that table is there: no grid, and no line with its
name either, since the table renders that line. The tasks' read is only
filtered, so the tasks table is there, under its name, and says "No
records".

With `on_forbidden :message` in the resource's `table` block, every kind of
table shows the message in place of the rows.

## Edge cases

- **An embedded table is asked again when its attributes change**, and an
  attached one when it is attached again. What a person can never see or
  do is asked of Ash then. Pass a new `actor` and the table follows.
- **A mounted table follows its socket.** When an `on_mount` hook of yours
  assigns another person while the page is open, the table reads again as
  them, and the layout is given the new assigns.
- **Nothing remains of a refused table but an empty, hidden element** with
  the table's id. The name the table renders is gone with it. A heading of
  your own stays, and so does what points at the table's name: on the demo's
  dashboard, the projects' section is then labelled by an element that is
  not there. Consider what the page should show a person who gets no table.
- **The full view in an embedded table.** A table with `url` that is limited
  to the records of one parent has a second line under its name, which says
  what it is limited to. The create button is then on that line, and so
  are the buttons of the table actions.
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
  after the id: `ash_data_table_task` for the id `task`.
- **Two routes for one resource**, as `/labels` and `/bare/labels` in the
  demo, are two pages of the same table with the same id. Give one of them
  another `id` if their saved links should differ.
- **Ids on one page.** No table's id may begin with another's followed by
  `-row-` or `-pick-`: those are the ids of the tables a table shows.

## Things people trip over

- **The mounted table has no navigation and no flash.** No `layout` is
  configured, so the page is bare.
- **Using an alias in the router line.** `ash_data_table "/tasks", Task` inside
  `scope "/", MyAppWeb` does not become `MyAppWeb.Task`; write the resource's
  full name.
- **An embedded table shows nothing to anyone.** It was given no `actor` or
  `scope`. The socket assigns are not read for it.
- **Two tables with the same `id`.** The id is the prefix of every DOM id of
  the table and the name of its URL parameters, so each table on a page
  needs its own.
- **Expecting a 404 from an embedded or attached table.** It renders nothing;
  decide in your LiveView who may open the page.
- **A custom `<h1>` above a mounted table.** The page already has one with
  the table's name. For a page with your own headings, embed or attach the
  table.
- **The name twice over an embedded table.** Your own heading and the
  table's line both show it. Pass `heading={false}`, or drop your heading
  and give the table its level.
- **An attached table inside a stream item.** The tables nested in its rows
  are drawn elsewhere and moved into their cells, and LiveView patches a
  stream item without them. Put `<AshDataTable.attached>` outside your own
  streams.
- **A height of your own around a table with `sticky_header`.** The table
  scrolls in its own area; a parent with a fixed height and `overflow: auto`
  makes two areas that scroll up and down, one in the other. Give the table
  its `height` instead.
- **A component of yours renders again on every event of an attached
  table.** Every event of the table renders the LiveView again. Give your
  components named assigns, not `assigns` whole or spread attributes.

## Not in the first version

No slots for a toolbar or a custom heading on the mounted page, no single
router line for all resources of a domain, and no commands for an embedded
table. See the
[specification](https://github.com/StefanRoesch/ash_data_table/issues/21).
