# A kit drawn in React

A kit (see [Kits](kits.md)) can draw its parts in the browser with a client
framework instead of HEEx. The demo has one: `DemoWeb.ReactKit`, which draws
every part of a table with React and [shadcn/ui](https://ui.shadcn.com), on
the table's own hooks, through [live_react](https://hex.pm/packages/live_react)
2.0. The library itself stays free of npm: the React kit lives in the demo
(`demo/lib/demo_web/react_kit.ex`, `demo/assets/islands/table/`), and this
guide is its recipe and the contracts it is built on. The demo shows it at
`/react/tasks`.

The rows stay a LiveView stream and the server holds none of them; every
write still goes through the table's checks. What changes is who draws:
each part of the kit is an island, a React component that live_react gives
the part's values as props.

## The recipe

live_react renders a component in the browser only (no server rendering,
so no Node at runtime):

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

The LiveSocket is given the kit's islands through the kit's own wrapper of
live_react's hook (`reactKitHooks`, which commits each update at once and
destroys the table's hooks in an island as the island goes):

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

A table is drawn with the kit as with any other, here attached to a
LiveView:

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

The kit is a kit of contract 6. Each part it draws is an island, given the
part's assigns picked as plain data (`DemoWeb.ReactKit.Props`):

<!-- source: demo/lib/demo_web/react_kit.ex -->
```elixir
use AshDataTable.Kit, contract: 6
# ...
def picker(assigns) do
  ~H"""
  <LiveReact.react
    id={"#{@id}-picker-island"}
    name="AshPicker"
    class="contents"
    picker={Props.picker(@id, @picker, @target, @presentation, @takes?, @texts)}
  />
  """
end
```

## The contracts it draws on

Everything the React kit does rests on contracts of the library, each
documented in a moduledoc or a JS file of the package and checked by a test:

- **The stream's items** (`AshDataTable.Item`): plain maps whose cells hold
  their finished, translated text. The `grid` part hands `rows` (the
  stream) to its island as it is.
- **What each part is given** (`AshDataTable.Kit`, "Kit contract 6"): plain
  values and the documented fields of the table's structs, with every text
  said (`texts`, `messages`). The `editor`, `argument_line` and `field`
  parts are given what their controls say (`limits`, `counted`), and
  `Kit.count/2` counts a text as the counter does.
- **The bundles** (`AshDataTable.Attrs`): `Attrs.props/1` turns a bundle
  into text props (`true` as `""`, nil and false left out); the JS half maps
  the names React wants (`class` to `className`, …). A kit never renders a
  bundle's `phx-hook`: it mounts the hook itself.
- **The events** (`Attrs`, "Events"): a kit sends an event through a
  bundle (`phx-click`, a form's `phx-change` and `phx-submit`) wherever one
  exists; LiveView hears them from its root.
- **The hooks, mounted by the kit** (`assets/js/mount.js`): `mountGrid`,
  `mountPanel`, `mountPicker` and `mountPagination`, each
  `(el, transport, options) -> {beforeUpdate, updated, destroy}`, and
  `liveViewTransport` of the hook functions live_react gives an island.
  `options.onEdit` tells the kit which cell is being edited.
- **What the hooks own** (`assets/js/owned.js`): the attributes and
  contents they write after the kit drew an element, which a kit renders
  never, once, or only as the table gives them.
- **The ids** (`AshDataTable.Ids`, mirrored by `assets/js/ids.js`).
- **The geometry** (`AshDataTable.Geometry`, mirrored by
  `assets/js/geometry.js`): where the columns and rows stand. The islands
  are given `lead` and place each column's cell with `geometry.colindex`.
- **The places what opens is moved into**: a nested table, its heading
  line, the picker's table, a picker a field opened and the question's copy
  are moved by LiveView (`Phoenix.Component.portal/1`) into a place a part
  draws, in the patch that opens them. A kit that draws in the browser draws
  after that patch, so it draws every place ahead: the places of the lines
  of an expanded row, and the `panel` and `picker` parts closed, with their
  places in them (the table draws both always, given nil while closed).
- **The sender** (`Attrs.sender/1`): drawn as markup of the LiveView's,
  outside every island, so that LiveView mounts its hook and locks it while
  a grid's event is out, never the grid.

## Customizing

Every part an island draws is a React component taken by name, the island's
own outer part too. A host replaces one with its own, as a kit of its own
replaces a part of the default kit:

<!-- sketch -->
```javascript
import {reactKit} from "../islands/table"
import {MyCell} from "./my_cell"

export default reactKit({Cell: MyCell})
```

The columns' components are found by the module a column names
(`components`, `editors`); a column without one shows its text and says so
on the console in development. On the server side a part is a function of
the kit's module, as in any kit: a kit of one's own draws a part as an
island of its own, or in HEEx, and the others as the React kit does.

## Testing it

`AshDataTable.KitCase` checks a kit that draws in the browser with
`client: true`: every part's texts and messages, and that no page holds the
test resource's sensitive value, which is that no prop and no item was given
it (live_react writes them into the page's HTML):

<!-- source: demo/test/demo_web/kits/react_kit_case_test.exs -->
```elixir
use AshDataTable.KitCase, kit: DemoWeb.ReactKit, endpoint: DemoWeb.Endpoint, client: true
```

The markers, ids, element kinds and Tab stops are checked on what the
browser drew: `AshDataTable.KitCase.problems/4` over a page's HTML, for a
state and a presentation. A page of your tests' own seeds the state with
`AshDataTable.KitCase.given/4` (the records, in a tenant of their own),
attaches the table of `AshDataTable.Test.Resource` (id `"kit"`) in that
tenant with your kit, and `AshDataTable.KitCase.clean/1`s the tenant as it
ends:

<!-- source: demo/e2e/server/kit_states_live.ex -->
```elixir
{tenant, key, _session} = KitCase.given(nil, state, presentation)
```

The demo's browser suite drives each state with the table's controls and
checks each page (`demo/e2e/kit_check.spec.ts`), and runs the whole suite a
second time with every table drawn by the React kit (the Playwright project
`react`).

## Edge cases

- **The panel and the picker are drawn always.** Closed, they draw only
  their element and its place; the table's panel and picker hooks are
  mounted as they open and destroyed as they close.
- **A file field.** LiveView tracks files only through its own file input.
  The React kit draws it beside the island, out of sight and in the panel's
  form (`form=`), and its visible file control hands it the files a person
  chooses with `uploadTo` (LiveView's documented hook function, which
  live_react gives an island).
- **A cell the hook holds** (being edited, or busy while its save is on
  its way) is drawn as it was until the hook gives it back: React never
  draws into children the hook replaced.
- **Controlled mode** works as with any kit: what the host draws itself
  the table does not draw.

## Things people trip over

- **A folder named `assets/react/`** shadows the `react` package (esbuild
  honours `baseUrl` in `tsconfig.json`): the demo's islands are in
  `assets/islands/`.
- **daisyUI's `--border` is a width, shadcn's a colour**: the demo renames
  shadcn's variables `--sh-*`, set only under the class `shadcn`. A Radix
  primitive that portals its content to `document.body` leaves that scope:
  its portalled element carries the class itself.
- **Commits that come later.** React draws an update when it gets to it;
  the kit's hook commits each of live_react's updates at once
  (`flushSync`), so that two patches in a row are both drawn.
- **A form's controls are uncontrolled**: what is typed is the browser's,
  and what the server gives is set where it changes, unless the person is in
  the control, as LiveView patches a form.
- **React's development build** checks and renders twice (StrictMode): the
  table's hooks take being mounted, destroyed and mounted again. Measure
  with the production build.

## Not in the first version

The React kit is the demo's, not a package: there is no npm package of it,
and the library ships no kit of its own for another UI technology. See the
[specification](https://github.com/StefanRoesch/ash_data_table/issues/21).
