defmodule DemoWeb.E2E.IdsLive do
  @moduledoc """
  A page for the browser test of the ids in the browser (`e2e/contract.spec.ts`):
  every function of `AshDataTable.Ids`, called with sample values, and
  what it made, as JSON (`ids`); and the names of all of its functions
  (`functions`), so that the test finds one without a sample.
  `assets/js/ids.js` must make the same ids. Compiled and routed in the e2e
  environment only.

  And the same of the grid's geometry (`geometry`): what
  `AshDataTable.Geometry` counts for a sample of geometries and pages,
  each as `assets/js/geometry.js` is given it (`colindex` a column's index
  and `lead`, `rowindex` the page's first row and a record's place), and
  for `lead` and `firstRow` an element of the grid with the attributes the
  bundles write (`data-lead` of `Attrs.grid/6`, the `role=table` with
  `data-first-row` of `Attrs.table/6`), which the test reads them from.
  """
  use DemoWeb, :live_view

  alias AshDataTable.Attrs
  # Its functions are the table's own (`@doc false`): this page calls them
  # on purpose, to compare the server's counts with the browser's.
  alias AshDataTable.Geometry
  alias AshDataTable.Ids

  @samples [
    {:row, ["tasks", "42"]},
    {:row, ["tasks-row-1-t-comments", "c-9"]},
    {:cell, ["tasks-row-42", "title"]},
    {:record, ["tasks-row-42"]},
    {:actions_cell, ["tasks-row-42"]},
    {:action, ["tasks-row-42-a", "archive"]},
    {:open, ["tasks-row-42-a"]},
    {:selector, ["tasks-row-42"]},
    {:expander, ["tasks-row-42"]},
    {:detail, ["tasks-row-42"]},
    {:line, ["tasks-row-42", "comments"]},
    {:line_cell, ["tasks-row-42", "comments"]},
    {:line_button, ["tasks-row-42", "comments"]},
    {:line_heading, ["tasks-row-42", "comments"]},
    {:nested_row, ["tasks-row-42", "comments"]},
    {:nested_cell, ["tasks-row-42", "comments"]},
    {:nested_table, ["tasks-row-42", "comments"]},
    {:error, ["tasks-row-42-c-title"]},
    {:head, ["tasks"]},
    {:head_row, ["tasks"]},
    {:header_cell, ["tasks", "title"]},
    {:sort, ["tasks", "title"]},
    {:skip, ["tasks"]},
    {:skip_target, ["tasks"]},
    {:filter_row, ["tasks"]},
    {:filters, ["tasks"]},
    {:editor, ["tasks", "title"]},
    {:dialog, ["tasks"]},
    {:panel_place, ["tasks"]},
    {:picker_place, ["tasks"]},
    {:field, ["tasks", ["place"]]},
    {:field, ["tasks", ["stops", "0", "city"]]},
    {:clear, ["tasks-panel-f-pin"]},
    {:choose, ["tasks-panel-f-owner"]},
    {:unpick, ["tasks-panel-f-helpers", 2]},
    {:argument, ["tasks", "since"]},
    {:argument_value, ["tasks-arg-tags", 0]},
    {:argument_value, ["tasks-arg-tags", "add"]}
  ]

  # a grid without and with columns before its data columns, a filter row
  # and a page under offset pagination, and a keyset page (no offset)
  @geometries [
    %Geometry{lead: 0, trail: 0, columns: 3, colcount: 3, header_rows: 1},
    %Geometry{lead: 2, trail: 1, columns: 3, colcount: 6, header_rows: 2, summary?: true}
  ]
  @pages [%{offset: 0, total: 9}, %{offset: 20, total: 42}, %{offset: nil, total: nil}]

  @impl true
  def mount(_params, _session, socket) do
    ids =
      for {function, args} <- @samples do
        # `:add` is an atom on the server, the text "add" in the browser
        called = Enum.map(args, &if(&1 == "add", do: :add, else: &1))
        %{function: function, args: args, id: apply(Ids, function, called)}
      end

    functions =
      for {name, _arity} <- Ids.module_info(:exports),
          not String.starts_with?(Atom.to_string(name), "_"),
          name != :module_info,
          do: name

    grids = grids()

    {:ok,
     assign(socket,
       page_title: "Ids",
       ids: Jason.encode!(ids),
       functions: Jason.encode!(Enum.uniq(functions)),
       grids: grids,
       geometry: Jason.encode!(geometry(grids))
     )}
  end

  # a grid's element per geometry and page, with what the hooks read of it
  defp grids do
    for {geometry, g} <- Enum.with_index(@geometries),
        {page, p} <- Enum.with_index(@pages) do
      grid = Attrs.grid("g#{g}-#{p}", nil, geometry, nil, nil, texts())
      table = Attrs.table("g#{g}-#{p}", "Sample", nil, geometry, page, false)

      %{
        id: grid["id"],
        geometry: geometry,
        page: page,
        grid: Map.take(grid, ["id", "data-lead"]),
        table: Map.take(table, ["id", "role", "data-first-row"])
      }
    end
  end

  defp geometry(grids) do
    columns =
      for geometry <- @geometries, index <- [0, 2] do
        %{
          function: :colindex,
          args: [index, geometry.lead],
          value: Geometry.colindex(geometry, index)
        }
      end

    rows =
      for geometry <- @geometries, page <- @pages, n <- [0, 4] do
        %{
          function: :rowindex,
          args: [Geometry.first_row(geometry, page), n],
          value: Geometry.rowindex(geometry, page, n)
        }
      end

    elements =
      for grid <- grids, function <- [:lead, :first_row] do
        value =
          if function == :lead,
            do: grid.geometry.lead,
            else: Geometry.first_row(grid.geometry, grid.page)

        %{function: function, grid: grid.id, value: value}
      end

    columns ++ rows ++ elements
  end

  defp texts,
    do: %{show_whole: "", show_less: "", show_whole_of: "", show_less_of: ""}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 class="text-2xl font-semibold">Ids</h1>
      <script id="ids" type="application/json">
        <%= Phoenix.HTML.raw(@ids) %>
      </script>
      <script id="functions" type="application/json">
        <%= Phoenix.HTML.raw(@functions) %>
      </script>
      <script id="geometry" type="application/json">
        <%= Phoenix.HTML.raw(@geometry) %>
      </script>
      <div :for={grid <- @grids} {grid.grid}>
        <div {grid.table}></div>
      </div>
    </Layouts.app>
    """
  end
end
