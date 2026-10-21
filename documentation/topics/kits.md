# Kits

Every table is drawn by a **kit**: a module with one function component per
**part** of the table (the grid, a row, a cell, the action panel, the
pagination, …), the classes of the parts drawn once per table, and whether
what opens is a modal dialog or part of the page. `AshDataTable.Kit.Default`
is the kit unless another is named; it draws with the Tailwind and daisyUI
classes of a new Phoenix app. This guide shows how to restyle parts, draw any
part with your own markup, open the panel, the picker and the question in
the page, and test your kit.

A kit changes how the table looks, never what it does: reading, sorting,
filtering, writing and checks are the same with any kit. To change one
column's cells, use a [column's component](custom-components.md). To run the
questions, panels and pickers in your own page, see
[Controlled mode](controlled-mode.md).

## A kit of your own

<!-- sketch -->
```elixir
defmodule MyAppWeb.TableKit do
  use AshDataTable.Kit, contract: 6

  # restyle a part drawn once per table
  def class(:panel, _state), do: "my-panel"
  def class(part, state), do: super(part, state)

  # open the action panel in the page, not over it
  def presentation(:panel), do: :inline
  def presentation(thing), do: super(thing)
end
```

`use AshDataTable.Kit, contract: 6` makes every part the default kit's. A kit
defines the parts it draws and calls `super` for the rest. These fail to
compile:

- another contract number than this version's;
- a public function of one argument that is no part (a typo such as
  `pagniation/1`);
- a `class` or `presentation` of another number of arguments.

Name it for every table in the configuration:

<!-- sketch -->
```elixir
config :ash_data_table, kit: MyAppWeb.TableKit
```

or for one table, which wins: on the router line, on the tag, or for
`attach/4`. From the demo's tests
([`demo/lib/demo_web/router.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo_web/router.ex)
and
[`demo/test/support/kit_tables.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/test/support/kit_tables.ex)):

<!-- source: demo/lib/demo_web/router.ex -->
```elixir
ash_data_table "/kit/memos", Demo.Support.Plain.Memo,
  layout: false,
  id: "kitmemo",
  kit: DemoWeb.DivKit
```

<!-- source: demo/test/support/kit_tables.ex -->
```heex
<AshDataTable.table
  id="tagged"
  resource={Demo.Support.Plain.Memo}
  actor={assigns[:current_user]}
  kit={DemoWeb.DivKit}
/>
```

Nested tables and pickers' tables are drawn with their table's kit. A module
that is no kit, or whose `presentation/1` answers neither `:modal` nor
`:inline`, raises an `ArgumentError` where it is named
(`AshDataTable.Kit.check!/2`).

## Modal or inline

The action panel, the picker and the question each open in one of two
**presentations**:

| | `:modal` | `:inline` |
| --- | --- | --- |
| Where | Over the page, as a modal dialog | In the page, as a part of it |
| The rest of the page | Inert while it is open | Usable: Tab leaves it |
| Focus | Moves into it, and back to what opened it | The same |
| Escape | Cancel | Cancel, unless what has the focus takes it |

The default kit opens all three as modal dialogs. A kit overrides this with
`presentation/1`; one table overrides it again with `presentation` on the
router line, the tag or `attach/4`. The demo mounts its tasks once more with
everything in the page
([`demo/lib/demo_web/router.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo_web/router.ex)):

<!-- source: demo/lib/demo_web/router.ex -->
```elixir
ash_data_table "/inline/tasks", Demo.Tracker.Task,
  presentation: [panel: :inline, picker: :inline, confirm: :inline]
```

They can be mixed:

- An inline question asked from a modal panel or picker is shown inside it,
  where it can be answered.
- An inline picker opened by a field of a modal panel is drawn inside the
  panel.

One question at a time per table: a new question gives up the open one, as
Cancel does.

## The look of a table

The default kit draws:

- a line under each row, no stripes, and a tint under the pointer;
- the header and the filter row as one group under a stronger rule;
- numbers at the end of their cells, in digits of one width;
- square boxes to select a row;
- the row whose relationships are open tinted, with a bar at its left edge,
  and a primary-colour line down the left of the area under it (see
  [Nested tables](nested-tables.md#how-a-nested-table-looks)).

Every tint is mixed from the daisyUI theme's colours, so it follows the
host's theme, light and dark; no option sets a colour.

Six options, in five rows, make up **the look** of a table:

| Option | What it does | Default kit |
| --- | --- | --- |
| `density` | How high the rows are, with the same text size: `:compact`, `:normal`, `:roomy`. | `:normal` |
| `stripes` | Every other record faintly tinted, counted over the records only: the lines and nested tables under an open row are no stripe. | `false` |
| `column_lines` | A line between the columns, besides the line under each row. | `false` |
| `sticky_header` | The table gets a height of its own and only its rows scroll in it; its header and filter row stay in view. See [Layout and embedding](layout-and-embedding.md#a-header-that-stays-in-view). | `false` |
| `height`, `nested_height` | With `sticky_header`: how high a table, and a table nested in a row, is at most, as a CSS length. | `min(75dvh, 48rem)`, `28rem` (about ten rows) |

As with the presentation, a kit sets its own with `look/1`, and one table
overrides it with `look` on the router line, the tag or `attach/4`. The look
is drawing, not data, so it is no option of the resource's `table` block
(`sticky_label?` stays there: it says which column a record is called by).
Every table a table shows, nested at any depth or in a picker, looks the
same. The demo mounts its projects once more with the sticky header, and its
tasks with the other three
([`demo/lib/demo_web/router.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo_web/router.ex)):

<!-- source: demo/lib/demo_web/router.ex -->
```elixir
ash_data_table "/projects/sticky", Demo.Tracker.Project,
  id: "project-sticky",
  look: [sticky_header: true]

ash_data_table "/tasks/striped", Demo.Tracker.Task,
  id: "task-striped",
  look: [density: :compact, stripes: true, column_lines: true]
```

A kit's own, for every table drawn with it:

<!-- sketch -->
```elixir
def look(:stripes), do: true
def look(option), do: super(option)
```

One table in a LiveView of your own:

<!-- sketch -->
```heex
<AshDataTable.table resource={MyApp.Tracker.Task} look={[density: :compact, sticky_header: true, height: "60vh"]} />
```

A malformed look is refused where the table is placed: an unknown option, a
value of the wrong kind, a height that is no CSS length. A kit of your own
gets the resolved look, a map of all six, as `look` in its `root/1` and in
`class(:root, …)`; what it draws of it is up to the kit.

## Drawing a part

A part is a function component of the kit, named after the part
(`AshDataTable.Kit.parts/0` lists the 32 of contract 6). It is given its
*projection* (`AshDataTable.Kit.Projection`, ADR 0004): what it draws,
finished, as plain data, one assign per key: values already looked up, its
texts in the person's language, the bundles of its elements, the facts
derived from them, and the projections of the parts it draws inside it.
Never a record, an `AshPhoenix.Form`, a changeset, the actor, the value of a
`sensitive?` field, or a struct of the table's: a kit only draws.

- The `AshDataTable.Kit.Projection` moduledoc lists every part's keys.
- The `AshDataTable.Kit` moduledoc says which elements each part must draw
  with which markers, and what a part is given beside its projection (`kit`,
  `id`, a row's item, the stream, the panel's uploads, the root's slots).

The demo's own kit, `DemoWeb.DivKit`, draws the grid, its rows, cells and
footer with `div`s instead of a `<table>`, and opens everything in the page
([`demo/lib/demo_web/div_kit.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo_web/div_kit.ex)):

<!-- source: demo/lib/demo_web/div_kit.ex -->
```elixir
use AshDataTable.Kit, contract: 6

alias AshDataTable.Ids
alias AshDataTable.Kit

def presentation(_thing), do: :inline
```

Its summary cell, one cell of the footer row:

<!-- source: demo/lib/demo_web/div_kit.ex -->
```elixir
def summary_cell(assigns) do
  ~H"""
  <div {@element} role="cell" class="table-cell whitespace-nowrap">
    <span :if={@summary?}>{@texts.kind}{@text && " " <> @text}</span>
  </div>
  """
end
```

Five things are at work there.

**Markers.** The table's hooks find its elements by markers, never by tags:
an ARIA role where the element has one (`table`, `rowgroup`, `row`, `cell`,
`rowheader`, `columnheader`, `dialog`, `region`), else a `data-*` attribute,
and ids that begin with the table's id. A part may draw any elements that
carry the markers. `AshDataTable.Attrs.markers/0` names every marker.

**Bundles.** Most markers come in bundles: maps of attributes (made by
`AshDataTable.Attrs`) that the projection holds and a part spreads on its
element (`{@element}`). In a part drawn once per row, cell or column, the
part writes the attributes that are the same on every one itself, as `role`
above (a bundle would resend it with every row); the bundle holds what
varies. Every event a part sends, every name a control is sent under and
every id is in a bundle or in the projection: a part writes none of its own.
A panel field holding a value made of fields (a map, a list of maps, a union)
gets its hidden entries the same way, each a bundle spread on an
`<input type="hidden">`, plus the bundles of its buttons and of its kind's
choice; what those entries are called and hold is the table's.

**Numbers.** A cell's position (`aria-colindex`) and the grid's column and
row counts are the table's: they are in the bundles (`element` above) and the
projections (`colindex`, `colspan`, `lead`). A kit counts no column.

**Tab stops.** A table is a table (`role="table"`), not an ARIA grid: Tab
moves the focus from control to control in document order, nested tables
included. So a part writes no `tabindex` on a control: a box, button, link,
menu or input is a stop by itself. A cell is no stop, except an editable one,
whose item's `attrs` hold `tabindex="0"`; a summary cell, as above, has none.
A header is no stop either: a sortable column has a button in its header,
which is the stop. The `grid` part draws a "Skip table …" link before the
header row (`skip`), and the `root` part draws its target after the table's
pages (`skip_target`). The `Kit` moduledoc, "Tab stops", has the rule;
`KitCase` checks it.

**Texts.** A part shows the texts it is given, in the person's language:
`texts` by name (`@texts.kind`), or `text` for a part of one text. Beside
them it gets `messages`, what each text is made of (a map
`%{key: key, values: values}` of a key of `AshDataTable.Messages`), and
`locale`, for a kit that translates or formats for itself. LiveView resends a
text only when what it is made of changed. See
[Messages and translations](messages-and-translations.md).

### The rows: items of the stream

The rows are a LiveView stream; the server keeps none of them. The `grid`
part gets the stream as `rows` and hands it on unchanged. Each item is a
plain map made by `AshDataTable.Item`: either a record's row, with each cell's
finished text (in the person's language and the page's time zone) and the
attributes that vary by row or cell, or the detail under an expanded row
with its lines. The `DivKit` draws a row group per item and spreads its
`attrs`:

<!-- source: demo/lib/demo_web/div_kit.ex -->
```elixir
<div
  :for={{dom_id, row} <- @rows}
  id={dom_id}
  role="rowgroup"
  {row.attrs}
  class="table-row-group"
  phx-no-format
```

and a cell with its column's attributes and the item cell's:

<!-- source: demo/lib/demo_web/div_kit.ex -->
```elixir
{Map.merge(column.attrs, @row.cells[column.name].attrs)}
```

A cell's `text` is what it shows; a masked cell has no text and no value. The
item's moduledoc lists every key. Ids of what a part draws per row are made
with `AshDataTable.Ids` from the row's `dom_id`, as the table makes them
(`Ids.record/1`, `Ids.cell/2`, `Ids.actions_cell/1`, …).

### A part inside a part

A part draws the parts inside it through the kit, with `Kit.part/1`, never by
calling another part's function, so a kit that replaces one part keeps the
others. It passes each inner part its projection, which is in its own. The
`DivKit`'s grid draws a header cell per column:

<!-- source: demo/lib/demo_web/div_kit.ex -->
```elixir
<Kit.part :for={cell <- @head.cells} part={:header_cell} kit={@kit} {cell} />
```

A spread (`{cell}`) turns off LiveView's change tracking for that part: it is
resent whole each time. Where only some of an inner part's keys change, pass
them one by one (`element={cell.element}` …), as `Kit.Default` draws its
footer and summary cells; LiveView then resends only what changed. The table
passes each part its keys the same way, with each key's previous value (out
of a comprehension of one), so a part redraws only what changed of a key, and
a kit drawing in the browser with LiveReact gets a patch of a prop, not the
whole prop.

A cell's content and a column's editor are drawn with `Kit.cell/1` and
`Kit.editor/1`, which call the column's component before the kit's `cell`
and `editor`. A part called through the kit gets every assign from its
caller: its own `attr` defaults are not applied.

The heading line above the grid is the `heading` part. It draws the `columns`
part ("Columns") and the `argument_line` part, so a kit moves or redraws
either by replacing `heading`. A nested table draws its `heading` too, moved
onto the line that opens it (a portal of its own, as the nested table is
moved into the cell under the line): a kit's `line` part draws the empty
element `Ids.line_heading/2` where it wants it, as it draws the cell
`Ids.nested_cell/2`. The line names the nested table; the nested table's
controls there are Tab stops after the line's button.

The selection line (`selection_line`) says whether anything is on it
(`shown?`): the default kit gives it no room while nothing is selected, no
filter is set and no notice shows. With more than three actions on the
selected rows it shows the first two and puts the rest in a "More" menu (the
browser's popover, its projection's `more`); a destroying action has the
error colour's outline.

## A kit that draws in the browser

A kit may draw a part with a client framework (React in a LiveView, through
`live_react`). The table stays the same: its rows a stream, every write
through the server's checks. Such a kit relies only on public contracts:

- **The projections.** Each projection is plain data that goes to JSON as it
  is; the kit hands each key to its island as a prop.
  `AshDataTable.Attrs.props/1` turns a bundle into what a framework takes:
  `true` as `""`, `false` and nil left out, a JS command as its JSON, every
  other value as text. The kit renames what its framework names otherwise
  (`class` to `className`, `tabindex` to `tabIndex`, …) and never renders a
  bundle's `phx-hook`. An item's `attrs` have the same form.
- **Events.** Every event goes through a bundle. `phx-click` and a form's
  `phx-change`/`phx-submit` work from a client framework's elements: LiveView
  hears them at its root and runs a JS command it is given (as "Clear
  filters" sends focus on). The `Attrs` moduledoc ("Events") lists every
  event, what sends it, its payload and its answer.
- **The hooks.** LiveView mounts no hook inside an island, so the kit mounts
  them with the package's JS entries `mountGrid`, `mountPanel`,
  `mountPicker` and `mountPagination`, given a transport that
  `liveViewTransport` makes of LiveView's hook functions. Call
  `beforeUpdate()` before each commit that may change the element and
  `updated()` after it (as LiveView calls a hook's), and `destroy()` when the
  element goes; mounting again after `destroy()` works (React's StrictMode).
  `onEdit` tells the kit which cell is being edited: the kit keeps that
  cell's content as it is until the edit ends. The comment at the top of
  `assets/js/mount.js` is the contract.
- **What the hooks own.** The hooks write some attributes of the kit's
  elements (a busy cell, a failed one, a box's state); `assets/js/owned.js`
  lists them and what a kit may render of each.
- **Ids.** `assets/js/ids.js` makes the ids of `AshDataTable.Ids`, function
  by function, for what a kit draws per row; `assets/js/geometry.js` counts
  columns and rows as `AshDataTable.Geometry` and the hooks do.
- **Two rules of the `Kit` moduledoc.**
  - The place a nested table is moved into must be in the page before the
    patch that opens it: a kit that draws after LiveView's patch draws the
    place of every line of an expanded row ahead of time, hidden while
    closed.
  - The grid's `sender` is drawn as LiveView markup, outside the island, so
    LiveView mounts its hook and locks it, never the grid.

The demo checks the JS entries in the browser
([`demo/e2e/contract.spec.ts`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/e2e/contract.spec.ts)):
the grid's hook mounted by hand on a grid of `div`s with a pagination beside
it, and `ids.js` and `geometry.js` against the server's. Its hook mounts the
grid like this:

<!-- source: demo/assets/js/mounted_grid.js -->
```javascript
const transport = el =>
  liveViewTransport({
    el,
    pushEventTo: (target, event, payload) => this.pushEventTo(target, event, payload),
    handleEvent: (event, handler) => this.handleEvent(event, handler),
    removeHandleEvent: ref => this.removeHandleEvent(ref),
    liveSocket: this.liveSocket
  })
const grid = document.getElementById(this.el.dataset.grid)
const edits = []
const mount = () => mountGrid(grid, transport(grid), {onEdit: cellId => edits.push(cellId)})
```

## The development check

While LiveView's client debug is on, each hook logs to the browser console
which marker its part lacks: `ash_data_table: the grid ID-grid has no …`.
LiveView turns debug on by itself on `localhost` (and `*.localhost`) unless
it was turned off, so the check usually runs in development. It walks every
cell of every grid after every patch, which is slow on a large page;
`liveSocket.disableDebug()` turns it off. A table whose question element is
missing runs nothing it would ask about, and logs that too.

## Testing a kit

`AshDataTable.KitCase` draws a table of `AshDataTable.Test.Resource` (shipped
with the library, with a column of every kind) through your kit, in twenty
states and four presentations. It checks every marker, id and `data-*` value
the hooks rely on, the element kinds they need, the texts each part is
given, and that no page holds the test resource's sensitive value. The
library runs it against the default kit, on its own tests' endpoint
([`test/kit/default_kit_test.exs`](https://github.com/StefanRoesch/ash_data_table/blob/main/test/kit/default_kit_test.exs)):

<!-- source: test/kit/default_kit_test.exs -->
```elixir
use AshDataTable.KitCase,
  kit: AshDataTable.Kit.Default,
  endpoint: AshDataTable.Test.LiveHost.Endpoint
```

Keyboard use and what a screen reader announces are not checked there; that
needs a browser. See [Testing](testing.md).

## Contract versions

A part added later comes with a default in `use AshDataTable.Kit`, and a
marker added later is in a bundle: existing kits keep working and the
contract keeps its number. When a part's assigns change in a way an existing
part cannot follow, or a bundle goes away, the number goes up, and a kit of
the old number fails to compile with a message naming what changed.

## Edge cases

- **A kit that keeps the default kit's root classes**
  (`super(:root, state)`) keeps its look too: the rules find the grid's parts
  by role, not tag, so a grid of `div`s looks the same.
- **A column's component wins in a cell.** A value the person may see is
  drawn by the column's component if it has one, else by the kit's `cell`. A
  masked or hidden cell is always the kit's.
- **The root of every table is the kit's.** `root/1` draws the root element
  of the table on the page, of each nested table and of each picker's table.
  The tag keeps a plain element of its own around it (a live component's
  root must be static).
- **Nested tables are moved into their cells** by LiveView portals; a
  picker's table into the picker's place; what opens inside a modal panel or
  picker into its place (`AshDataTable.Kit`, "The places a nested table is
  moved into"). The wrapper LiveView puts around each takes the kit's
  `class(:portal, …)`; the elements inside it are styled by their markers
  (`data-ash-data-table-portal`, `data-ash-data-table-view`), as the default
  kit's root rules do.
- **`class/2` is called once per table**, never per row or cell: per-row
  browser state (selected, busy, invalid) is an attribute, for the root's
  style to reach.

## Things people trip over

- **Editing does not start in a kit's grid.** A marker is missing: check the
  browser console with LiveView's debug on, and run `KitCase`.
- **Tab stops at a cell it should pass, or twice in one cell.** A part wrote
  its own `tabindex`: only the item's `attrs` give one, to an editable cell.
  `KitCase` names the element.
- **A part of your own gets an assign as nil.** A part called through the kit
  gets what its caller passes; its `attr` defaults are not applied.
- **A part draws a fact it has not got.** A part gets its projection and
  nothing it is made of: a missing fact is asked for as a new key (a contract
  change), not worked out of other keys.
- **A part of your own is told it is given something beside its
  projection.** `KitCase` checks that a part gets every key of its projection
  and nothing else: a kit's own part that draws another through `Kit.part/1`
  passes that part's projection, which is in its own.
- **A kit of contract 2 no longer compiles.** Contract 3 draws a table, not
  an ARIA grid:
  - `role="table"`, `"cell"` and `"rowheader"` (the label column's cell, the
    `row` part's `label`);
  - no `tabindex="-1"` on cells and controls;
  - a sort button in a sortable header (`Attrs.sort/3`, the `header_cell`
    part's `button`);
  - the skip link and its target;
  - `data-failed` instead of `aria-invalid`;
  - none of the grid's attributes of selection and of read-only cells
    (`Attrs.table/8`, `Attrs.empty_cell/2`, `Attrs.column_header/3`).

  The compile error names what changed. A kit of contract 1 is told both
  steps.
- **A kit of contract 3 no longer compiles.** Contract 4 gives `heading` and
  `argument_line` no `lines` and `refused`, and `argument_line` no `state`:
  an argument's input is drawn from `arguments`, which holds what it shows
  and what Ash said of it. A part of your own that read them reads
  `arguments` instead.
- **A kit of contract 4 no longer compiles.** Contract 5 always draws the
  `panel` and `picker` parts, given nil while closed, and gives them no
  `inner_block`: what opens inside them (the picker's table, a picker a field
  opened, the question's copy) is moved into the empty element they draw
  (`Ids.panel_place/1`, `Ids.picker_place/1`). A panel of your own draws its
  fields from `fields`; a field of your own gets `path`, `table`, `limits`,
  `counted` and what a value made of fields holds (`members`, `items`,
  `kind`, `single`) instead of `inside`.
- **A kit of contract 5 no longer compiles.** Contract 6 changes:
  - A panel field gets its hidden entries as bundles (`hidden`, and
    `members.hidden` instead of `members.keys`). A union gets the name of its
    kind's choice (`kind_name`, `kind_path`) and the ids of the kind's choice
    and of the group buttons (`kind_id`, `add_id`, `remove_id`, an item's
    `remove_id`); `Attrs.add_group/4` and `Attrs.remove_group/4` take the
    button's id. A field of your own spreads each entry of `hidden` on an
    `<input type="hidden">`, names the kind's choice `kind_name` with the id
    `kind_id`, and passes the ids to the group bundles, instead of writing
    names and ids itself.
  - `grid`, `row`, `footer` and `full_view` get the `geometry` instead of
    `lead` and `acting?` (its `trail`), `label_column` and `editing?` as
    fields of `model`, and `geometry.summary?` instead of `summarised?`. The
    header rows' bundles are `Attrs.head_row/2` and `Attrs.filter_row/2`.
    `Attrs.table/6` (instead of `/8`), `Attrs.grid/6`, `Attrs.spanning/3`
    and `Attrs.summaries/3` take the geometry; `Attrs.colcount/3` and
    `Attrs.filter_row?/1` are gone: a grid of your own reads `colcount` and
    `header_rows`.
  - The panel (`AshDataTable.Present.Panel`) has `ask` (`"changed"` or nil,
    written by `Attrs.panel/5` as `data-ask`) instead of `kind`.
  - Last, every part gets its projection (`AshDataTable.Kit.Projection`), an
    assign per key, instead of `model`, `state`, `page`, `geometry`,
    `panel`, `picker`, `fields`, `arguments`, `editors`, `filters` and the
    texts of `Kit.Words`, which is gone. A part of your own reads its
    projection's keys, spreads its bundles, and calls no function of `Attrs`
    but `props/1`.
  - A cell of a row's item says whether the column's component draws it
    (`component`): a row of your own asks it, not the column and the cell's
    state.

## Not in the first version

No kit for another UI technology ships with the library; the demo has a
React kit, built on the contract of "A kit that draws in the browser" (see
[A kit drawn in React](react-kit.md)). There is no kit other than the default
and the demo's. See the
[specification](https://github.com/StefanRoesch/ash_data_table/issues/21).
