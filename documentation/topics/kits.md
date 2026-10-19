# Kits

Every table is drawn by a **kit**: a module with one function component per
**part** of the table (the grid, a row, a cell, the action panel, the
pagination, …), the classes of the parts drawn once per table, and whether
what opens is a modal dialog or part of the page. `AshDataTable.Kit.Default`
is the kit a table has unless another is named; it draws with the Tailwind
and daisyUI classes of a new Phoenix app. After reading this guide you can
restyle a few parts, draw any part with your own markup, open the panel, the
picker and the question in the page, and check your kit in your tests.

A kit changes how the table looks, never what it does: it reads, sorts,
filters, writes and checks the same with any kit. To change how one column's
cells look, a [column's component](custom-components.md) is enough. To run
the questions, panels and pickers in your own page, see
[Controlled mode](controlled-mode.md).

## A kit of your own

<!-- sketch -->
```elixir
defmodule MyAppWeb.TableKit do
  use AshDataTable.Kit, contract: 2

  # restyle a part drawn once per table
  def class(:panel, _state), do: "my-panel"
  def class(part, state), do: super(part, state)

  # open the action panel in the page, not over it
  def presentation(:panel), do: :inline
  def presentation(thing), do: super(thing)
end
```

`use AshDataTable.Kit, contract: 2` makes every part the default kit's. A kit
defines the parts it draws itself, and calls `super` for what the default kit
draws. It is checked as it compiles: another contract number than this
version's, a public function of one argument that is no part (a typo such as
`pagniation/1`), and a `class` or `presentation` of another number of
arguments fail to compile.

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

The tables a table shows, nested in its rows and in its pickers, are drawn
with its kit. A module that is no kit, or whose `presentation/1` answers
neither `:modal` nor `:inline`, raises an `ArgumentError` where it is named
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

The default kit opens all three as modal dialogs. A kit says otherwise with
`presentation/1`, and one table can say otherwise again with `presentation`,
on the router line, the tag or `attach/4`. The demo mounts its tasks once
more with everything in the page
([`demo/lib/demo_web/router.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo_web/router.ex)):

<!-- source: demo/lib/demo_web/router.ex -->
```elixir
ash_data_table "/inline/tasks", Demo.Tracker.Task,
  presentation: [panel: :inline, picker: :inline, confirm: :inline]
```

They can be mixed. A question in the page that is asked from a panel or
picker open over the page is shown inside that panel or picker, where it can
be answered; a picker in the page that a field of a modal panel opens is
drawn inside the panel. One question at a time per table: a question asked
while another is still open gives the first up, as Cancel does.

## The look of a table

The default kit draws rows with a line under each and no stripes, a tint
under the pointer, the header and the filter row as one group under a
stronger rule, numbers at the end of their cells in digits of one width,
and square boxes that select a row. The row whose relationships are open
stays tinted, with a bar at its left edge, and the area under it has a line
in the primary colour down its left (see
[Nested tables](nested-tables.md#how-a-nested-table-looks)). Every tint is
mixed from the daisyUI theme's colours, so it follows the host's theme,
light and dark; there is no colour among the options.

Six options, in five rows, can be changed, as **the look** of a table:

| Option | What it does | Default kit |
| --- | --- | --- |
| `density` | How high the rows are, with the same text size: `:compact`, `:normal`, `:roomy`. | `:normal` |
| `stripes` | Every other record faintly tinted, counted over the records only: the lines and nested tables under an open row are no stripe. | `false` |
| `column_lines` | A line between the columns, besides the line under each row. | `false` |
| `sticky_header` | The table gets a height of its own and only its rows scroll in it; its header and filter row stay in view. See [Layout and embedding](layout-and-embedding.md#a-header-that-stays-in-view). | `false` |
| `height`, `nested_height` | With `sticky_header`: how high a table, and a table nested in a row, is at most, as a CSS length. | `min(75dvh, 48rem)`, `28rem` (about ten rows) |

As with the presentation, a kit says its own with `look/1`, and one table
says otherwise again with `look`, on the router line, the tag or
`attach/4`. The look is drawing, not data: it is no option of the
resource's `table` block (`sticky_label?` stays there, as it says which
column a record is called by). Every table a table shows, nested at any
depth or in a picker, looks the same. The demo mounts its projects once
more with the header that stays in view, and its tasks with the other three
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

A kit says its own, for every table drawn with it:

<!-- sketch -->
```elixir
def look(:stripes), do: true
def look(option), do: super(option)
```

and one table in a LiveView of your own:

<!-- sketch -->
```heex
<AshDataTable.table resource={MyApp.Tracker.Task} look={[density: :compact, sticky_header: true, height: "60vh"]} />
```

A look of another shape is refused where the table is placed: an option
that is none, a value of another kind, a height that is no CSS length. A kit
of your own is given the resolved look, a map of all six, as `look` in its
`root/1` and in `class(:root, …)`; what it draws of it is up to it.

## Drawing a part

A part is a function component of the kit, named after the part
(`AshDataTable.Kit.parts/0` lists the 32 of contract 2). It is given values,
never a record, an `AshPhoenix.Form`, a changeset or the actor, and never the
value of a `sensitive?` field. The moduledoc of `AshDataTable.Kit` says, part
by part, what each is given, which elements it must draw with which markers,
and the fields of every value it is given ("Kit contract 2").

The demo has a kit of its own, `DemoWeb.DivKit`, which draws the grid, its
rows, cells and footer with `div`s in place of a `<table>`, and opens
everything in the page
([`demo/lib/demo_web/div_kit.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo_web/div_kit.ex)):

<!-- source: demo/lib/demo_web/div_kit.ex -->
```elixir
use AshDataTable.Kit, contract: 2

alias AshDataTable.Attrs
alias AshDataTable.Ids
alias AshDataTable.Kit
alias AshDataTable.Kit.Words

def presentation(_thing), do: :inline
```

Its summary cell, one cell of the footer row:

<!-- source: demo/lib/demo_web/div_kit.ex -->
```elixir
def summary_cell(assigns) do
  ~H"""
  <div
    id={@id}
    role="gridcell"
    aria-colindex={@colindex}
    tabindex="-1"
    {Attrs.summary(@column, @summing?)}
    class="table-cell whitespace-nowrap"
  >
    <span :if={@column.summary}>{@texts.kind}{@text && " " <> @text}</span>
  </div>
  """
end
```

Four things are at work there.

**Markers.** The table's behaviour in the browser (its hooks) finds the
elements of a table by their markers, never by their tags: an ARIA role where
the element has one (`grid`, `rowgroup`, `row`, `gridcell`, `columnheader`,
`dialog`, `region`), else a `data-*` attribute, and the ids that begin with
the table's id. So a part may draw any elements, as long as they carry the
markers. `AshDataTable.Attrs.markers/0` names every marker.

**Bundles.** Most markers come in bundles: the functions of
`AshDataTable.Attrs`, maps of attributes a part spreads on its element
(`{Attrs.summary(@column, @summing?)}`), made of the values the part is
given. Where a part is drawn once per row, cell or column, the attributes that
are the same on every one are written by the part itself, as `role` and
`tabindex` above (a bundle would send them again with every row), and the
bundle holds what varies. The `Attrs` moduledoc is the contract.

**Ids.** Where the table names an element a part draws (focus goes to it, a
nested table is moved into it), the part makes its id with
`AshDataTable.Ids`, as the table does: `Ids.cell/2`, `Ids.line_button/2` and
the others. Every other id is the table's id and a suffix, listed per part in
the `AshDataTable.Kit` moduledoc.

**Texts.** A part shows the texts it is given, in the person's language:
`texts` by name (`@texts.kind`), and for a part of one text or value `text`.
Beside them it is given `messages`, what each text is made of, a map
`%{key: key, values: values}` of a key of `AshDataTable.Messages`, and
`locale`, for a kit that translates or formats for itself. They are made by `AshDataTable.Kit.Words`
and passed as attributes, so LiveView sends a text again only when what it
is made of changed. See
[Messages and translations](messages-and-translations.md).

### The rows: items of the stream

The rows of a table are a LiveView stream, and the server keeps none of
them. The `grid` part is given the stream as `rows` and hands it on as it
is; each item is a plain map made by `AshDataTable.Item`: a record's row,
each of its cells with its finished text (in the person's language and the
page's time zone) and the attributes that vary by row or cell, or the
detail under an expanded row with its lines. The `DivKit` draws a row group
per item and spreads its `attrs`:

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

and a cell with `Attrs.cell/2`, the column's attributes and the cell's:

<!-- source: demo/lib/demo_web/div_kit.ex -->
```elixir
{Attrs.cell(column, @row.cells[column.name])}
```

A cell's `text` is what the cell shows; a masked cell has none, and no
value. The item's moduledoc lists every key.

### A part inside a part

A part draws the parts inside it through the kit, with `Kit.part/1`, never by
calling another part's function, so that a kit that replaces one part keeps
the others. It passes each part the assigns the `Kit` moduledoc lists, and
its texts made with `Kit.Words`. The `DivKit`'s grid draws a header cell per
column, with the id `AshDataTable.Ids` makes for it:

<!-- source: demo/lib/demo_web/div_kit.ex -->
```elixir
<Kit.part
  :for={{column, index} <- Enum.with_index(@model.columns)}
  part={:header_cell}
  kit={@kit}
  id={Ids.header_cell(@id, column.name)}
  column={column}
  colindex={@lead + index + 1}
  attrs={
    Attrs.column_header(
      @id,
      column,
      @state.sort,
      @model.sticky_label? and column == @label_column,
      @myself
    )
  }
  sort={@state.sort}
  resizer={"#{@id}-resize-#{column.name}"}
  texts={Words.texts(:header_cell, %{column: column, editing?: @editing?})}
  messages={Words.messages(:header_cell, %{column: column, editing?: @editing?})}
/>
```

What a cell holds and a column's editor are drawn with `Kit.cell/1` and
`Kit.editor/1`, which call the column's component before the kit's `cell` and
`editor`. A part called through the kit is given every assign by its caller:
the defaults of its own `attr`s are not applied.

The heading line above the grid is the `heading` part, and it draws the
`columns` part ("Columns") and the `argument_line` part inside it, so a kit
moves or redraws either by replacing it, and `heading` places them. A nested
table draws its `heading` too, and it is moved onto the line that opens it
(a portal of its own, as the nested table is moved into the cell under the
line): a kit's `line` part draws the empty element `Ids.line_heading/2`
where it wants it, as it draws the cell `Ids.nested_cell/2`. The line gives
the nested table its name; the nested table's buttons there are no tab
stops, as the line's are not.

The line of the selection (`selection_line`) says in its class's `state`
whether anything is on it (`shown?`): the default kit gives it no room
while nothing is selected, no filter is set and no notice shows. Of more
than three actions on the selected rows it shows the first two and puts
the others in a menu, "More" (the browser's popover); an action that
destroys has the error colour's outline.

## A kit that draws in the browser

A kit may draw a part with a client framework (React in a LiveView,
through `live_react`). The table stays the same: its rows a stream, every
write through the server's checks. What such a kit relies on is public:

- **Props.** `AshDataTable.Attrs.props/1` turns a bundle into what a
  framework takes: `true` as `""`, `false` and nil left out, every other
  value as text; the kit renames what its framework names otherwise
  (`class` to `className`, `tabindex` to `tabIndex`, …) and never renders a
  bundle's `phx-hook`. An item's `attrs` are of the same form.
- **Events.** A kit sends an event through a bundle wherever one exists
  (`phx-click` and a form's `phx-change`/`phx-submit` work from a client
  framework's elements: LiveView hears them at its root). The `Attrs`
  moduledoc lists every event ("Events"), what sends it, its payload and its
  answer; a kit sends by name only those it marks "a kit may send it".
- **The hooks.** Inside an island LiveView mounts no hook, so the kit mounts
  them itself with the package's JS entries, `mountGrid`, `mountPanel`,
  `mountPicker` and `mountPagination`, given a transport that
  `liveViewTransport` makes of LiveView's hook functions. `beforeUpdate()`
  before each commit that may change the element and `updated()` after it
  (as LiveView calls a hook's), `destroy()` when the element goes; mounted again after
  `destroy()` it works (React's StrictMode). `onEdit` tells the kit which
  cell is being edited: it keeps that cell's content as it is until the
  edit ends. The comment at the top of `assets/js/mount.js` is the contract.
- **What the hooks own.** The hooks write some attributes of the elements a
  kit draws (where the tab stop is, what is selected, a busy cell);
  `assets/js/owned.js` lists them, and what a kit may render of each.
- **Ids.** `assets/js/ids.js` makes the ids of `AshDataTable.Ids`, function
  by function.
- **Two rules of the `Kit` moduledoc.** The place a nested table is moved
  into must be in the page before the patch that opens it: a kit that
  draws after LiveView's patch draws the place of every line of an expanded
  row ahead of time, hidden while it is closed. And the grid's sender
  (`Attrs.sender/1`) is drawn as LiveView's markup, outside the island, so
  that LiveView mounts its hook and locks it, never the grid.

The demo checks the JS entries in the browser
([`demo/e2e/contract.spec.ts`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/e2e/contract.spec.ts)):
the grid's hook mounted by hand on a grid of `div`s and a pagination's beside it,
and `ids.js` against the server's ids. Its hook mounts the grid so:

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

While LiveView's client debug is on, each hook says on the browser's console
which marker its part lacks: `ash_data_table: the grid ID-grid has no …`.
LiveView turns the debug on by itself on `localhost` (and `*.localhost`),
unless it was turned off, so in a usual development setup the check runs. It
walks every cell of every grid after every patch, which is slow on a large
page; `liveSocket.disableDebug()` turns it off. A table whose question
element is missing runs nothing it would ask about, and says so there.

## Testing a kit

`AshDataTable.KitCase` draws a table of `AshDataTable.Test.Resource`, a
resource that ships with the library and has a column of every kind, through
your kit, in twenty states and four presentations. It checks every marker,
id and `data-*` value the hooks rely on, the kinds of elements they need,
the texts each part is given, and that no page holds the test resource's
sensitive value. The demo runs it against the default kit
([`demo/test/demo_web/kits/default_kit_test.exs`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/test/demo_web/kits/default_kit_test.exs)):

<!-- source: demo/test/demo_web/kits/default_kit_test.exs -->
```elixir
use AshDataTable.KitCase, kit: AshDataTable.Kit.Default, endpoint: DemoWeb.Endpoint
```

What a person does with the keyboard and hears from a screen reader is not
checked there: that needs a browser. See [Testing](testing.md).

## Contract versions

A part added later comes with a default in `use AshDataTable.Kit`, and a
marker added later is in a bundle: an existing kit keeps working, and the
contract keeps its number. When the assigns of a part change in a way an
existing part cannot follow, or a bundle goes away, the number goes up, and a
kit of the old number fails to compile with a message that names what
changed.

## Edge cases

- **A kit of your own that keeps the default kit's classes of the root**
  (`super(:root, state)`) keeps its look too: the rules find the grid's
  parts by their roles, not their tags, so a grid of `div`s looks the same.

- **A column's component wins in a cell.** A value the person may see is
  drawn by the column's component, if it has one, and only otherwise by the
  kit's `cell`. A masked or hidden cell is always the kit's.
- **The root of every table is the kit's.** `root/1` draws the root element
  of the table on the page, of each nested table and of each picker's table.
  The tag keeps a plain element of its own around it (a live component's
  root must be static).
- **Nested tables are moved into their cells** by LiveView portals. The
  wrapper LiveView puts around each takes the kit's `class(:portal, …)`;
  the elements inside it are styled by their markers
  (`data-ash-data-table-portal`, `data-ash-data-table-view`), which the
  default kit's root rules do.
- **`class/2` is called once per table**, never per row or cell: what
  changes there in the browser (selected, busy, invalid) is an attribute,
  for the root's style to reach.

## Things people trip over

- **The arrow keys do nothing in a kit's grid.** A marker is missing: look
  at the browser's console with LiveView's debug on, and run `KitCase`.
- **A part of your own gets an assign as nil.** A part called through the
  kit is given what its caller passes, and its `attr` defaults are not
  applied.
- **A text that never changes.** A kit's own part that draws a part of the
  table through `Kit.part/1` has to pass that part's `texts` and `messages`
  made with `Kit.Words`.
- **Reading a function of the table's structs.** A kit reads the fields
  "Kit contract 2" lists; their modules' functions are the table's own, and
  may change.
- **A kit of contract 1 no longer compiles.** Contract 2 draws the rows
  from the items of `AshDataTable.Item` (`row.open`, `cell.text`,
  `row.failure`, `{row.attrs}`, `Attrs.cell/2`) and gives every message as a
  map: the compile error names what changed.

## Not in the first version

No kit for another UI technology ships with the library; a React kit is
being built in the demo, on the contract of "A kit that draws in the
browser". No kit other than the default and the demo's. See the
[specification](https://github.com/StefanRoesch/ash_data_table/issues/21).
