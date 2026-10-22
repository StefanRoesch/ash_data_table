# Get started with AshDataTable

By the end, one of your resources is a page in your Phoenix app: a table
people sort, filter and page through, with the columns you chose, one column
editable in place, and a save the resource's policy refuses for the wrong
person. No HEEx.

Each step shows the code of the demo app in
[`demo/`](https://github.com/StefanRoesch/ash_data_table/tree/main/demo), an issue
tracker that ships with the library, and names the demo page where the step
works. Do the same in your app with your resource.
[The demo's README](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/README.md)
says how to start it; it runs at `http://localhost:4478`, and "Acting as" in
the page header chooses who you are.

The code blocks are excerpts of the demo's files; `# ...` (`// ...` in
JavaScript) stands for lines left out.

## Before you start

An existing Phoenix and Ash application with at least one resource.

| Requirement | Version |
| --- | --- |
| Elixir | 1.17 or later |
| Ash | 3.36.1 or later |
| `ash_phoenix` | 2.3 or later |
| Phoenix | 1.8 |
| Phoenix LiveView | 1.2.12 or later |

- The default kit uses the Tailwind 4 and daisyUI classes of a new Phoenix
  1.8 app; texts go through Gettext.
- The resource needs a primary read action and at least one `public?`
  attribute; for the last step also an update action and a policy.
- An older Phoenix 1.8 installer writes `{:phoenix_live_view, "~> 1.1.0"}`.
  Change it to `"~> 1.2"` in `mix.exs` first, or the dependencies do not
  resolve.

## 1. Install

Not on Hex yet, so give the installer the repository:

<!-- sketch -->
```sh
mix igniter.install ash_data_table@github:StefanRoesch/ash_data_table
```

Once published: `mix igniter.install ash_data_table`. With the dependency
already in `mix.exs` and [Igniter](https://hexdocs.pm/igniter) among your
dependencies, `mix ash_data_table.install` does the same. It can be run
again: it takes only the steps not yet taken. It adds the dependency, the
formatter entry, Spark's section order, the hooks in `assets/js/app.js`, a
Tailwind `@source` line and three configuration keys. A configuration key is
written only when your app has what it names (`MyAppWeb.Layouts.app/1`,
`MyAppWeb.Gettext`, `MyAppWeb.CoreComponents.translate_error/1`) and the key
is not set yet. A file that does not look like a new Phoenix 1.8 app's is
left alone, and the step is printed for you to take by hand.
[Installation](../topics/installation.md#with-the-installer) has the table of
changes, [the manual steps](../topics/installation.md#by-hand) and the
setting left to you: compressing LiveView's websocket.

The result in the demo. The hooks, in
[`demo/assets/js/app.js`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/assets/js/app.js):

<!-- source: demo/assets/js/app.js -->
```js
import {hooks as colocatedHooks} from "phoenix-colocated/demo"
import {hooks as ashDataTableHooks} from "phoenix-colocated/ash_data_table"
// ...
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  // ...
  hooks: {
    ...colocatedHooks,
    ...ashDataTableHooks,
    // ...
  },
})
```

Five hooks (the grid, the pagination, the action panel, the picker and the
grid's sender) ship as colocated hooks behind the one import. Nothing to
install from npm.

The configuration, in
[`demo/config/config.exs`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/config/config.exs):

<!-- source: demo/config/config.exs -->
```elixir
config :ash_data_table,
  layout: {DemoWeb.Layouts, :app},
  gettext_backend: DemoWeb.Gettext,
  translate_error: {DemoWeb.CoreComponents, :translate_error}
```

All three keys are optional:
[Layout and embedding](../topics/layout-and-embedding.md) explains the first,
[Messages and translations](../topics/messages-and-translations.md) the other
two.

The Tailwind source differs from the demo, which depends on the library by
path. For a package from Hex the installer writes this into
`assets/css/app.css` (a sketch, not the demo's line):

<!-- sketch -->
```css
@source "../../deps/ash_data_table/lib";
```

The hooks are generated when the dependency compiles, so `mix compile` must
run before the assets are built; a new Phoenix app's `assets.build` alias
does that. Run `mix assets.build` now.

## 2. Give a resource a table

List the extension on the resource. This is all `Demo.Tracker.Project` needs,
in
[`demo/lib/demo/tracker/project.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/project.ex):

<!-- source: demo/lib/demo/tracker/project.ex -->
```elixir
defmodule Demo.Tracker.Project do
  # ...
  use Ash.Resource,
    otp_app: :demo,
    domain: Demo.Tracker,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshDataTable.Resource],
    # The default sort of a table lives on its read action, on purpose.
    primary_read_warning?: false
```

Only a resource that lists the extension has a table. Without a `table`
block it shows the public attributes, read through the primary read action,
and nothing is editable. (The demo's projects have a block, but it declares
no column, so the columns are these defaults. The block switches on editing,
declares two row actions and a create button, and says what a project is
called in other resources' tables. See step 5,
[Row actions and create](../topics/row-actions-and-create.md) and
[Columns and defaults](../topics/columns-and-defaults.md#reference-cells).)

## 3. Mount it in the router

Import `AshDataTable.Router` and add one line per table, inside the
`live_session` whose `on_mount` hooks assign who is logged in. From
[`demo/lib/demo_web/router.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo_web/router.ex):

<!-- source: demo/lib/demo_web/router.ex -->
```elixir
import AshDataTable.Router
# ...
scope "/", DemoWeb do
  pipe_through :browser
  # ...
  live_session :default, on_mount: [DemoWeb.Actor, DemoWeb.Locale, DemoWeb.Zone] do
    # ...
    ash_data_table "/tasks", Demo.Tracker.Task, layout: {DemoWeb.Layouts, :tasks}
    ash_data_table "/projects", Demo.Tracker.Project
    # ...
  end
end
```

`ash_data_table/3` expands to a `live` route for a ready-made LiveView.
Write the resource in full: the surrounding `scope`'s alias is not applied
to it. A table can also go in your own LiveView, with a tag or with
`AshDataTable.attach/4`: [Layout and embedding](../topics/layout-and-embedding.md)
compares the three.

Open `/projects` as Ada Admin: columns ID, Name, Description, Status, Starts
on, Budget, Client, Milestones and Inserted at; ten projects a page, sorted by
name. A click on a heading sorts, the row under the headings filters, and
Tab moves from control to control and to each editable cell. Page size and
order are the `default_limit` and the sort of the primary read action, not
the table's: [Reading, sorting and pagination](../topics/reading-sorting-and-pagination.md)
explains why.

The marks at the start of the rows, the "Actions" column and the "New
project" button come from the relationships and the `table` block: see
[Nested tables](../topics/nested-tables.md) and
[Row actions and create](../topics/row-actions-and-create.md).

The table reads as the person your `on_mount` hook assigns as
`current_user` and `current_tenant` (or `current_scope`); in the demo that
hook is `DemoWeb.Actor`. Other names: see
[Authorization](../topics/authorization.md).

## 4. Declare columns

The default columns rarely fit: they include `id` and leave out every
calculation and aggregate. `column` entries in a `table` block say exactly
which columns, in which order. Part of `Demo.Tracker.Task`'s block, in
[`demo/lib/demo/tracker/task.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/task.ex):

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
table do
  # ...
  # text
  column :title

  # enums, each shown as a badge. A change of state asks first.
  column :status do
    label "State"
    confirm "Change the state of this task?"
    component AshDataTable.Components.Badge
  end
  # ...
  # an aggregate: sortable and filterable, never editable
  column :comment_count do
    label "Comments"
  end
  # ...
end
```

- Once one `column` is declared, the table has the declared columns only.
- `label` replaces the heading (otherwise the field's name in words).
- `component` shows the state as a badge instead of plain text
  ([Custom components](../topics/custom-components.md)).
- `comment_count` is an aggregate; it is a column because the block names it.

`/tasks` shows the full block at work;
[Columns and defaults](../topics/columns-and-defaults.md) has the rules.

## 5. Switch on editing for a column

Nothing is editable until the block names an update action. A column can
name its own; a task's priority is edited through `reprioritise`:

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
# edited through an action of its own
column :priority do
  update_action :reprioritise
  component AshDataTable.Components.Badge
end
```

The action is an ordinary update action that accepts the column's attribute:

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
# Leaves a trace of its own, so that it can be told apart from `update`.
update :reprioritise do
  accept [:priority]
  change set_attribute(:internal_note, "Reprioritised")
end
```

On `/tasks` as Ada Admin, move to a Priority cell and press Enter. The cell
becomes a choice of priorities; choose one and it is saved. The table ran
`reprioritise` on that task with one input, the priority, and shows the row
as the action returned it.

The demo's block also has `update_action :update` at the top: every column
whose attribute `update` accepts is editable.
[Inline editing](../topics/inline-editing.md) covers both levels, each type's
editor and what a failed save looks like.

## 6. See a policy refuse a save

The table has no authorization rules of its own: it runs the action as the
logged-in person, and the resource decides. The demo's task policy for
update actions:

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
policy action_type([:update, :destroy]) do
  description """
  Admins may run every action and viewers none (actor only). A member may
  change only the tasks they are assigned to or reported (record-dependent).
  """

  forbid_if actor_attribute_equals(:role, :viewer)
  authorize_if actor_attribute_equals(:role, :admin)
  authorize_if expr(assignee_id == ^actor(:id) or reporter_id == ^actor(:id))
end
```

Switch to Max Member and open `/tasks`.

1. Change a task's priority. Unless Max is its assignee or reporter, the
   cell turns the error colour and says "You are not allowed to change
   this." Nothing is saved. Escape on the cell brings back the saved value.
2. Switch to Vera Viewer. No cell opens: a viewer can never run an update
   action, so the table offers no editing.

The first is refused on save, the second before anything is typed; the
difference is whether the policy depends on the record.
[Authorization](../topics/authorization.md) explains it, with hidden columns
and refused reads.

## Where to go next

- [Columns and defaults](../topics/columns-and-defaults.md)
- [Reading, sorting and pagination](../topics/reading-sorting-and-pagination.md)
- [Filtering](../topics/filtering.md)
- [State in the URL](../topics/state-in-the-url.md)
- [Inline editing](../topics/inline-editing.md)
- [Confirm](../topics/confirm.md)
- [Row actions and create](../topics/row-actions-and-create.md): buttons in
  a row that run an action on its record, and a button that creates one
- [Nested tables](../topics/nested-tables.md)
- [Authorization](../topics/authorization.md)
- [Keyboard and accessibility](../topics/keyboard-and-accessibility.md)
- [Messages and translations](../topics/messages-and-translations.md)
- [Layout and embedding](../topics/layout-and-embedding.md): the router line,
  the tag and `attach/4`
- [Events and commands](../topics/events-and-commands.md)
- [Kits](../topics/kits.md): how the table looks
- [Testing](../topics/testing.md)
- [Mistakes at compile time](../topics/mistakes-at-compile-time.md)

Every option of the two extensions is in the DSL reference:
[`AshDataTable.Resource`](../dsls/DSL-AshDataTable.Resource.md) and
[`AshDataTable.Domain`](../dsls/DSL-AshDataTable.Domain.md).

## Edge cases

- **The installer without Igniter, no app layout:** see
  [Installation](../topics/installation.md#edge-cases). **A path
  dependency:** the Tailwind source is the checkout's `lib` directory, seen
  from `assets/css`, not a directory under `deps`
  ([Installation](../topics/installation.md#by-hand)); the installer writes
  the dependency's path as it finds it, and the demo's line is
  `@source "../../../lib";`.
- **No primary read action:** no table until the block names one with
  `read_action`. The compiler reports it: see
  [Mistakes at compile time](../topics/mistakes-at-compile-time.md).

## Things people trip over

- **Unstyled table, Enter does nothing, `esbuild` can't find the hooks, a
  path dependency not reloading:** see
  [Installation](../topics/installation.md#things-people-trip-over).
- **Nobody is logged in.** A table mounted outside the `live_session` that
  assigns the user reads as nobody. With a filtering policy that is an empty
  table, not an error.

## Not in the first version

This tutorial stops at reading and editing cells. Row actions, creating
records, nested tables and a column's own component are built and have
their own guides, linked above. Later slices are listed in order in the
[specification](https://github.com/StefanRoesch/ash_data_table/issues/21).
