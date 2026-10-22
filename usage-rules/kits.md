# Kits

A kit draws every table: one function component per **part** (the grid, a
row, a cell, the action panel, the pagination, …). `AshDataTable.Kit.Default`
draws with the Tailwind and daisyUI classes of a new Phoenix app. A kit
changes how the table looks, never what it does. One column's cells are a
component's (`ash_data_table:custom_components`); running the questions,
panels and pickers in your own page is controlled mode
(`ash_data_table:controlled_mode`). Details:
[Kits](https://github.com/StefanRoesch/ash_data_table/blob/main/documentation/topics/kits.md).

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

- Define the parts you draw and call `super` for the rest; `class/2`,
  `presentation/1` (`:modal` or `:inline`) and `look/1` (`density`,
  `stripes`, `column_lines`, `sticky_header`) work the same way. `AshDataTable.Kit.parts/0` lists the parts.
- **The default look is a style sheet**, `priv/static/ash_data_table.css`,
  imported in the host's `app.css` after Tailwind. It keys on the root class
  `ash-data-table` (`super(:root, state)`), the root's look attributes
  (`data-density`, `data-stripes`, `data-column-lines`,
  `data-sticky-header`) and the markers, in `@layer components`: a
  utility class on a part wins over it, so leave padding, borders and
  alignment off the cells it styles. To change the look, write CSS after the
  import, never a long `[&_…]` class on the root.
- Name it for every table with `config :ash_data_table, kit: MyAppWeb.TableKit`,
  or for one table with `kit:` on the router line, the tag or `attach/4`.
  Nested tables and pickers' tables are drawn with the same kit.

## Drawing a part

- **Draw from the projection.** A part is given its projection
  (`AshDataTable.Kit.Projection`), an assign per key: finished plain data,
  texts in the person's language. A fact the part lacks is asked for as a
  new key, never worked out of other keys.
- **Spread the bundles** (`{@element}`): every event, control name and id
  comes from a bundle or the projection. Attributes that are the same on
  every row, such as `role`, the part writes itself.
- **Markers, not tags.** The hooks find elements by ARIA role or `data-*`
  marker (`AshDataTable.Attrs.markers/0`), so any element that carries them
  works: `DemoWeb.DivKit` draws the grid with `div`s.
- **Tab stops come from the controls.** A part writes no `tabindex`; an
  editable cell gets `tabindex="0"` from its item's `attrs`.
- **Inner parts through the kit:** `<Kit.part part={:header_cell} kit={@kit} {cell} />`,
  passing the inner part's projection, and `Kit.cell/1`, `Kit.editor/1` for
  what a cell holds. Every assign comes from the caller: `attr` defaults are
  not applied. Pass keys one by one (`element={cell.element}`) where only
  some change, so LiveView's change tracking sends less.
- **Rows** are a LiveView stream of `AshDataTable.Item` maps; ids per row
  come from `AshDataTable.Ids` of the row's `dom_id`.

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

## A kit that draws in the browser

A kit can draw its parts with React through `live_react`, as the demo's
`DemoWeb.ReactKit` does
([A kit drawn in React](https://github.com/StefanRoesch/ash_data_table/blob/main/documentation/topics/react-kit.md)):

- hand each projection key to the island as a prop, bundles through
  `AshDataTable.Attrs.props/1`, and never render a bundle's `phx-hook`;
- mount the hooks with the package's JS entries (`mountGrid`, `mountPanel`,
  `mountPicker`, `mountPagination`, `liveViewTransport`; the contract is the
  comment at the top of `assets/js/mount.js`);
- draw the grid's `sender` as LiveView markup outside every island, and
  draw ahead the places that nested tables and what opens are moved into;
- no React kit ships with the library: the demo's (`demo/lib/demo_web/react_kit.ex`,
  `demo/assets/islands/table/`) is the recipe.

A file an action returns is saved by the library's own window listener,
which importing the hooks sets up: a kit draws and hears nothing for it.

## Check it

<!-- source: demo/test/demo_web/kits/div_kit_test.exs -->
```elixir
use AshDataTable.KitCase, kit: DemoWeb.DivKit, endpoint: DemoWeb.Endpoint
```

`KitCase` draws `AshDataTable.Test.Resource` through the kit in every state
and presentation and checks markers, ids, texts, Tab stops and that no
sensitive value is on the page. For a kit that draws in the browser,
`client: true` checks the texts and the sensitive value, and
`AshDataTable.KitCase.problems/4` checks markers, ids and Tab stops on the
HTML the browser drew. While LiveView's debug is on, the browser console names the
marker a part lacks.
