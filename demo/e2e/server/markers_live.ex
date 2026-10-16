defmodule DemoWeb.E2E.MarkersLive do
  @moduledoc """
  A page for the browser tests of the grid's hook on its markers alone (the
  design note of stage 7, test group Y): a grid drawn with `div`s and
  `span`s, no `table`, `tr` or `td`, that carries the table's markers (the
  roles of the grid, its rows, row groups and cells, `aria-colindex`, the
  `data-*` of `AshDataTable.Attrs`) and the grid's hook, with a table nested
  in a cell. The page answers the hook's events itself, as a table would:
  a save is kept and drawn, a selection is heard. If the hook relied on a
  tag, it would fail here.

  The header of each grid is a row group too, as a kit may draw it: the
  hook must not take it for a record.

  `?missing=colindex` draws one cell without its place (`aria-colindex`),
  for the development check of the hook (D13). Compiled and routed in the
  e2e environment only; stage 7b replaces it with a kit of the demo's.
  """
  use DemoWeb, :live_view

  @columns [name: "Name", size: "Size", note: "Note"]
  @rows [
    {"a", %{name: "Anchor", size: "12", note: "first"}},
    {"b", %{name: "Bolt", size: "3", note: "second"}},
    {"c", %{name: "Cog", size: "40", note: "third"}}
  ]
  @parts [{"p1", "Pin"}, {"p2", "Plate"}]

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Markers",
       columns: @columns,
       rows: @rows,
       parts: @parts,
       missing: params["missing"]
     )}
  end

  @impl true
  def handle_event(
        "ash_data_table:kit:save",
        %{"row" => key, "column" => column, "value" => value},
        socket
      ) do
    field = Enum.find_value(@columns, fn {name, _label} -> to_string(name) == column && name end)

    rows =
      for {row, values} <- socket.assigns.rows do
        if row == key and field, do: {row, Map.put(values, field, value)}, else: {row, values}
      end

    {:reply, %{ok: true}, assign(socket, rows: rows)}
  end

  def handle_event("ash_data_table:" <> _event, _payload, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 class="text-2xl font-semibold">Markers</h1>
      <%!-- The grid's look, as a kit would give it: of no weight
      (`:where`), so that the hook's own rules (widths, hidden columns)
      come first, as they do over the classes of the table's own look. --%>
      <style>
        :where(#kit [role=grid]) { display: table; border-collapse: collapse }
        :where(#kit [role=rowgroup]) { display: table-row-group }
        :where(#kit-head, #kit-row-a-t-parts-head) { display: table-header-group }
        :where(#kit [role=row]) { display: table-row }
        :where(#kit [role=gridcell], #kit [role=columnheader]) { display: table-cell; padding: 2px 8px; border: 1px solid; position: relative }
        :where(#kit [data-resize]) { position: absolute; top: 0; bottom: 0; right: 0; width: 8px; cursor: col-resize }
        :where(#kit-grid) { overflow-x: auto }
      </style>
      <div id="kit">
        <div id="kit-columns-control">
          <button
            type="button"
            id="kit-columns-button"
            aria-expanded="false"
            aria-controls="kit-columns"
            data-columns-button
            data-text="Columns"
            data-text-with="Columns ({details})"
            data-text-hidden="{n} hidden"
            data-text-filtered="{n} filtered"
            data-text-sorted="{n} sorted"
            data-say-hidden="{column} hidden"
            data-say-shown="{column} shown"
          >
            <span id="kit-columns-text" phx-update="ignore">Columns</span>
          </button>
          <div
            id="kit-columns"
            role="group"
            aria-label="Columns"
            popover="manual"
            phx-mounted={JS.ignore_attributes(["style"])}
            data-columns-list
          >
            <label :for={{name, label} <- @columns} id={"kit-column-#{name}-entry"}>
              <input
                type="checkbox"
                id={"kit-column-#{name}"}
                checked
                data-head={"kit-head-#{name}"}
                data-label={label}
              />
              <span>{label}</span>
            </label>
          </div>
          <span id="kit-columns-status" role="status" phx-update="ignore"></span>
        </div>
        <div id="kit-sender" phx-hook="AshDataTable.Sender" data-sender data-table="kit" hidden></div>
        <div
          id="kit-grid"
          phx-hook="AshDataTable.Grid"
          data-ash-data-table
          data-table="kit"
          data-lead="1"
          data-select="multi"
          tabindex="-1"
        >
          <div
            id="kit-table"
            role="grid"
            aria-label="Kit"
            aria-rowcount="5"
            aria-colcount="4"
            aria-multiselectable="true"
          >
            <div id="kit-head" role="rowgroup">
              <div id="kit-head-row" role="row" aria-rowindex="1">
                <span
                  id="kit-select-head"
                  role="columnheader"
                  aria-colindex="1"
                  tabindex="-1"
                  data-select-page
                >
                  <input type="checkbox" tabindex="-1" aria-label="Select all rows of this page" />
                </span>
                <span
                  :for={{{name, label}, index} <- Enum.with_index(@columns)}
                  id={"kit-head-#{name}"}
                  role="columnheader"
                  aria-colindex={index + 2}
                  aria-label={label}
                  tabindex="-1"
                >
                  {label}<span
                    id={"kit-resize-#{name}"}
                    role="separator"
                    aria-orientation="vertical"
                    aria-label={"Resize #{label}"}
                    aria-valuemin="48"
                    aria-valuemax="1000"
                    tabindex="-1"
                    data-resize
                  ></span>
                </span>
              </div>
              <div id="kit-filter-row" role="row" aria-rowindex="2">
                <span
                  id="kit-select-filter"
                  role="gridcell"
                  aria-colindex="1"
                  tabindex="-1"
                ></span>
                <span
                  :for={{{name, _label}, index} <- Enum.with_index(@columns)}
                  id={"kit-filter-#{name}"}
                  role="gridcell"
                  aria-colindex={index + 2}
                  tabindex="-1"
                ></span>
              </div>
            </div>
            <%= for {{key, values}, at} <- Enum.with_index(@rows) do %>
              <div id={"kit-row-#{key}"} role="rowgroup">
                <div id={"kit-row-#{key}-r"} role="row" aria-rowindex={at + 3}>
                  <span
                    id={"kit-row-#{key}-s"}
                    role="gridcell"
                    aria-colindex="1"
                    tabindex="-1"
                    data-selector
                  >
                    <input type="checkbox" tabindex="-1" aria-label="Select row" />
                  </span>
                  <span
                    :for={{{name, _label}, index} <- Enum.with_index(@columns)}
                    id={"kit-row-#{key}-c-#{name}"}
                    role="gridcell"
                    aria-colindex={
                      if @missing == "colindex" and key == "b" and name == :size,
                        do: nil,
                        else: index + 2
                    }
                    aria-readonly={name != :name && "true"}
                    data-value={name == :name && values[name]}
                    tabindex="-1"
                  >
                    {values[name]}
                  </span>
                </div>
              </div>
              <div
                :if={key == "a"}
                id={"kit-row-#{key}-x"}
                role="rowgroup"
                data-detail
                data-row={key}
              >
                <div id={"kit-row-#{key}-n-parts"} role="row">
                  <span
                    id={"kit-row-#{key}-n-parts-c"}
                    role="gridcell"
                    colspan="4"
                    aria-colindex="1"
                    tabindex="-1"
                    data-nested
                  >
                    <div
                      id={"kit-row-#{key}-t-parts-sender"}
                      phx-hook="AshDataTable.Sender"
                      data-sender
                      data-table={"kit-row-#{key}-t-parts"}
                      hidden
                    >
                    </div>
                    <div
                      id={"kit-row-#{key}-t-parts-grid"}
                      phx-hook="AshDataTable.Grid"
                      data-ash-data-table
                      data-table={"kit-row-#{key}-t-parts"}
                      data-lead="0"
                      tabindex="-1"
                    >
                      <div
                        id={"kit-row-#{key}-t-parts-table"}
                        role="grid"
                        aria-label="Parts"
                        aria-colcount="1"
                      >
                        <div id={"kit-row-#{key}-t-parts-head"} role="rowgroup">
                          <div
                            id={"kit-row-#{key}-t-parts-head-row"}
                            role="row"
                            aria-rowindex="1"
                          >
                            <span
                              id={"kit-row-#{key}-t-parts-head-title"}
                              role="columnheader"
                              aria-colindex="1"
                              tabindex="-1"
                            >
                              Part
                            </span>
                          </div>
                        </div>
                        <div
                          :for={{{part, title}, at} <- Enum.with_index(@parts)}
                          id={"kit-row-#{key}-t-parts-row-#{part}"}
                          role="rowgroup"
                        >
                          <div
                            id={"kit-row-#{key}-t-parts-row-#{part}-r"}
                            role="row"
                            aria-rowindex={at + 2}
                          >
                            <span
                              id={"kit-row-#{key}-t-parts-row-#{part}-c-title"}
                              role="gridcell"
                              aria-colindex="1"
                              aria-readonly="true"
                              tabindex="-1"
                            >
                              {title}
                            </span>
                          </div>
                        </div>
                      </div>
                    </div>
                  </span>
                </div>
              </div>
            <% end %>
          </div>
          <template id="kit-editor-name" data-editor="text">
            <textarea rows="1" aria-label="Name"></textarea>
          </template>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
