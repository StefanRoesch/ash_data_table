# ash_table

An Ash extension that presents a resource to people as a table in Phoenix
LiveView. It is an interface to Ash resources in the way `ash_json_api` and
`ash_graphql` are, for humans.

Add the extension to a resource, optionally describe the table in a
`table do … end` block, and mount it with one line in the router. You write
no HEEx.

> **This is a walking skeleton.** It reads, sorts and pages. Filtering, inline
> editing, the authorization states, nested tables and row actions are not
> built yet, and the package is not on Hex.

## Install

Requires Elixir 1.17, Ash 3.34, Phoenix 1.8 and LiveView 1.2. There is no
installer yet; the steps are manual.

1. Add the dependency in `mix.exs`:

   ```elixir
   {:ash_table, "~> 0.1"}
   ```

2. Register the table's JavaScript hook in `assets/js/app.js`. The hook ships
   with the library as a colocated hook; there is nothing to install from npm.

   ```js
   import {hooks as ashTableHooks} from "phoenix-colocated/ash_table"

   const liveSocket = new LiveSocket("/live", Socket, {
     hooks: {...colocatedHooks, ...ashTableHooks},
     // …
   })
   ```

3. Let Tailwind see the classes the table uses, in `assets/css/app.css`:

   ```css
   @source "../../deps/ash_table";
   ```

4. Add the DSL to the formatter in `.formatter.exs`:

   ```elixir
   import_deps: [:ash, :ash_table, …]
   ```

5. Name the layout the mounted tables are rendered in, in `config/config.exs`.
   A LiveView mounted from the router gets the root layout only; since
   Phoenix 1.8 the app layout is a function component each page calls itself,
   so the table's page has to be told which one:

   ```elixir
   config :ash_table, layout: {MyAppWeb.Layouts, :app}
   ```

   The component is called with the table as its inner block and the assigns
   `flash`, `current_scope` (nil when the socket has none) and, when the
   socket has it, `current_user`. Without this setting the tables are
   rendered bare in the root layout. One table can differ:
   `ash_table "/tasks", MyApp.Tracker.Task, layout: false`, or
   `layout: {Module, :function}`.

The table uses the Tailwind and daisyUI classes of a default new Phoenix app.

Notes on the steps:

- The hook is written into the host's build directory when the dependency is
  compiled, so `mix compile` has to run before the assets are built. The
  `assets.build` alias of a new Phoenix app already does that.
- The `@source` path is the dependency's directory relative to
  `assets/css`. For a path dependency (`{:ash_table, path: "../ash_table"}`)
  point it at that checkout's `lib` instead.

## A first table

List the extension on a resource:

```elixir
defmodule MyApp.Tracker.Task do
  use Ash.Resource,
    domain: MyApp.Tracker,
    extensions: [AshTable.Resource]

  # …
end
```

and mount it in the router:

```elixir
import AshTable.Router

scope "/", MyAppWeb do
  pipe_through :browser

  live_session :default, on_mount: [{MyAppWeb.UserAuth, :mount_current_scope}] do
    ash_table "/tasks", MyApp.Tracker.Task
  end
end
```

`/tasks` now shows the resource's public attributes as a table, read through
its primary read action. Headers sort on click or Enter; the arrow keys move
through the cells.

### Describing the table

```elixir
table do
  read_action :open        # default: the primary read action
  paginate_with :keyset    # default: offset if the action supports it, else keyset

  column :title

  column :status do
    label "State"
    sortable? false
  end

  column :comment_count    # an aggregate
end
```

- With no `column`, the table shows the resource's public attributes. Once one
  `column` is declared, the table is exactly the declared columns in the
  declared order.
- Calculations and aggregates appear only when named. A calculation with a
  required argument cannot be a column.
- Only `public?` fields and actions can appear.
- `sortable?` can only switch sorting off. Whether a column can be sorted is
  the resource's decision; under keyset pagination, calculations and
  aggregates cannot.

Mistakes in the block are reported when the resource is compiled. As with
every Ash extension's verifiers, they surface as compile warnings; they fail
the build under `mix compile --warnings-as-errors`.

### Page size and default sort live on the read action

They are not part of the `table` block:

```elixir
read :open do
  pagination offset?: true, default_limit: 25, countable: true
  prepare build(sort: [inserted_at: :desc])
end
```

The page size is the action's `default_limit`, or 25 when it has none, and
never above the action's `max_page_size`. A read action without pagination
loads every record.

### Who is reading

The mounted page reads with authorization on. It takes actor and tenant from
the socket assigns your `on_mount` hooks set: `current_scope` if it is
assigned (it must implement `Ash.Scope.ToOpts`), otherwise `current_user` and
`current_tenant`.

### The URL

Sort and page are kept in the URL, under the table's id, so reload, the back
button and shared links work:

```
/tasks?task[sort]=-title&task[page]=2
```

The id defaults to the last part of the resource's module name, underscored;
`ash_table "/tasks", MyApp.Tracker.Task, id: "tasks"` sets another.

### Inside an existing LiveView

```heex
<AshTable.table id="tasks" resource={MyApp.Tracker.Task} scope={@current_scope} />
```

It accepts `scope`, or `actor` and `tenant`. An embedded table keeps its sort
and page itself; pass the page's current URL as `url` to keep them in the URL.

## Licence

MIT
