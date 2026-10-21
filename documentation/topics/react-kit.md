# A kit drawn in React

A kit (see [Kits](kits.md)) can draw its parts in the browser with a client
framework instead of HEEx. The demo's `DemoWeb.ReactKit` draws every part of
a table with React and [shadcn/ui](https://ui.shadcn.com), on the table's own
hooks, through [live_react](https://hex.pm/packages/live_react) 2.0. The
library stays npm-free: the React kit lives in the demo
(`demo/lib/demo_web/react_kit.ex`, `demo/assets/islands/table/`), and this
guide is its recipe and the contracts it builds on. The demo shows it at
`/react/tasks`.

The rows stay a LiveView stream, the server holds none of them, and every
write still goes through the table's checks. Only the drawing changes: each
part of the kit is an island, a React component that live_react gives the
part's values as props.

## The recipe

live_react renders a component in the browser only (no server rendering, so
no Node at runtime):

<!-- source: demo/mix.exs -->
```elixir
{:live_react, "~> 2.0"}
```

<!-- source: demo/config/config.exs -->
```elixir
config :live_react, ssr: false
```

esbuild (the Hex package) bundles the TSX with `--jsx=automatic`, and finds
live_react's JS in `deps/` and React in `assets/node_modules` through
`NODE_PATH`:

<!-- source: demo/config/config.exs -->
```elixir
env: %{
  "NODE_PATH" => [
    Path.expand("../deps", __DIR__),
    Mix.Project.build_path(),
    Path.expand("../assets/node_modules", __DIR__)
  ]
}
```

The LiveSocket gets the kit's islands through the kit's own wrapper of
live_react's hook, `reactKitHooks`, which commits each update at once and
destroys the table's hooks in an island as the island goes:

<!-- source: demo/assets/js/app.js -->
```javascript
import islands from "../islands"
import {reactKitHooks} from "../islands/table"
// ...
  hooks: {
    ...colocatedHooks,
    ...ashDataTableHooks,
    // the demo's own hook of its browser tests (mounted_grid.js)
    MountedGrid,
    ...reactKitHooks(islands),
  },
```

A table uses the kit like any other, here attached to a LiveView:

<!-- source: demo/lib/demo_web/live/react_tasks_live.ex -->
```elixir
|> AshDataTable.attach(:table, Demo.Tracker.Task,
  kit: DemoWeb.ReactKit,
  heading: 1,
  url: true,
  actor: socket.assigns.current_user,
  tenant: socket.assigns.current_tenant,
  time_zone: socket.assigns.time_zone
```

The kit is of contract 6. Each part it draws is an island, given the part's
projection (`AshDataTable.Kit.Projection`) with each key as its own prop, and
its bundles as props through one rule, the kit's `props/1`:

<!-- source: demo/lib/demo_web/react_kit.ex -->
```elixir
use AshDataTable.Kit, contract: 6
# ...
def status(assigns) do
  ~H"""
  <LiveReact.react
    id={"#{@id}-status-island"}
    name="AshStatus"
    class="contents"
    region={props(@region)}
    again?={@again?}
    result={@result}
    texts={@texts}
    messages={@messages}
  />
  """
end
```

## The contracts it draws on

Everything the React kit does rests on library contracts, each documented in
a moduledoc or a JS file of the package and checked by a test:

- **The stream's items** (`AshDataTable.Item`): plain maps whose cells hold
  their finished, translated text. The `grid` part hands `rows` (the stream)
  to its island unchanged.
- **What each part is given** (`AshDataTable.Kit.Projection`, ADR 0004): its
  projection, finished plain data with every text (`texts`, `messages`),
  every bundle and every number, plus the projections of the parts inside
  it. The islands read the same shapes as the HEEx kit's parts and compute
  nothing (not even a counter's `length`, which the hook recounts as a
  person types).
- **The bundles** (`AshDataTable.Attrs`): `Attrs.props/1` turns a bundle into
  text props (`true` as `""`, nil and false left out); the JS half maps the
  names React wants (`class` to `className`, …). A kit never renders a
  bundle's `phx-hook`: it mounts the hook itself.
- **The events** (`Attrs`, "Events"): every event goes through a bundle
  (`phx-click`, a form's `phx-change` and `phx-submit`); LiveView hears them
  from its root and runs a JS command one holds ("Read again" and "Clear
  filters" send focus on).
- **The hooks, mounted by the kit** (`assets/js/mount.js`): `mountGrid`,
  `mountPanel`, `mountPicker` and `mountPagination`, each
  `(el, transport, options) -> {beforeUpdate, updated, destroy}`, and
  `liveViewTransport` of the hook functions live_react gives an island.
  `options.onEdit` tells the kit which cell is being edited.
- **What the hooks own** (`assets/js/owned.js`): the attributes and contents
  they write after the kit drew an element, which a kit renders never, once,
  or only as the table gives them.
- **The ids** (`AshDataTable.Ids`, mirrored by `assets/js/ids.js`).
- **The geometry** (`AshDataTable.Geometry`, mirrored by
  `assets/js/geometry.js`): where columns and rows stand, which the hooks
  count with; the islands get each cell's place in its projection
  (`colindex`) and count nothing.
- **The places what opens is moved into**: LiveView
  (`Phoenix.Component.portal/1`) moves a nested table, its heading line, the
  picker's table, a picker a field opened and the question's copy into a
  place a part draws, in the patch that opens them. A kit that draws in the
  browser draws after that patch, so it draws every place ahead: the places
  of an expanded row's lines, and the `panel` and `picker` parts closed, with
  their places in them (the table always draws both, given nil while
  closed).
- **The sender** (`Attrs.sender/1`): drawn as LiveView markup, outside every
  island, so LiveView mounts its hook and locks it while a grid's event is
  out, never the grid.

## Customizing

Every part an island draws is a React component taken by name, the island's
own outer part too. A host replaces one with its own, as a kit replaces a
part of the default kit:

<!-- sketch -->
```javascript
import {reactKit} from "../islands/table"
import {MyCell} from "./my_cell"

export default reactKit({Cell: MyCell})
```

Columns' components are found by the module a column names (`components`,
`editors`); a column without one shows its text and logs that to the console
in development. On the server a part is a function of the kit's module, as in
any kit: your own kit draws a part as its own island or in HEEx, and the
others as the React kit does.

## Testing it

`AshDataTable.KitCase` checks a kit that draws in the browser with
`client: true`: every part's texts and messages, and that no page holds the
test resource's sensitive value, meaning no prop and no item got it
(live_react writes them into the page's HTML):

<!-- source: demo/test/demo_web/kits/react_kit_case_test.exs -->
```elixir
use AshDataTable.KitCase, kit: DemoWeb.ReactKit, endpoint: DemoWeb.Endpoint, client: true
```

Markers, ids, element kinds and Tab stops are checked on what the browser
drew: `AshDataTable.KitCase.problems/4` over a page's HTML, for a state and a
presentation. A page of your own tests:

1. seeds the state with `AshDataTable.KitCase.given/4` (the records, in a
   tenant of their own);
2. attaches the table of `AshDataTable.Test.Resource` (id `"kit"`) in that
   tenant with your kit;
3. cleans the tenant with `AshDataTable.KitCase.clean/1` as it ends.

<!-- source: demo/e2e/server/kit_states_live.ex -->
```elixir
{tenant, key, _session} = KitCase.given(nil, state, presentation)
```

The demo's browser suite drives each state with the table's controls and
checks each page (`demo/e2e/kit_check.spec.ts`), and runs the whole suite a
second time with every table drawn by the React kit (the Playwright project
`react`).

## Edge cases

- **The panel and the picker are always drawn.** Closed, they draw only their
  element and its place; the table's panel and picker hooks are mounted as
  they open and destroyed as they close.
- **A file field.** LiveView tracks files only through its own file input.
  The React kit draws it beside the island, hidden and in the panel's form
  (`form=`); its visible file control hands it the chosen files with
  `uploadTo` (LiveView's documented hook function, which live_react gives an
  island).
- **A cell the hook holds** (being edited, or busy while its save is on its
  way) stays as it was until the hook gives it back: React never draws into
  children the hook replaced.
- **Controlled mode** works as with any kit: the table does not draw what the
  host draws itself.

## Things people trip over

- **A folder named `assets/react/`** shadows the `react` package (esbuild
  honours `baseUrl` in `tsconfig.json`): the demo's islands are in
  `assets/islands/`.
- **daisyUI's `--border` is a width, shadcn's a colour**: the demo renames
  shadcn's variables `--sh-*`, set only under the class `shadcn`. A Radix
  primitive that portals its content to `document.body` leaves that scope,
  so its portalled element carries the class itself.
- **Late commits.** React draws an update when it gets to it; the kit's hook
  commits each live_react update at once (`flushSync`), so two patches in a
  row are both drawn.
- **A form's controls are uncontrolled**: what is typed belongs to the
  browser, and a value from the server is set where it changes unless the
  person is in the control, as LiveView patches a form.
- **React's development build** checks and renders twice (StrictMode): the
  table's hooks survive being mounted, destroyed and mounted again. Measure
  with the production build.

## Not in the first version

The React kit is the demo's, not a package: there is no npm package of it,
and the library ships no kit for another UI technology. See the
[specification](https://github.com/StefanRoesch/ash_data_table/issues/21).
