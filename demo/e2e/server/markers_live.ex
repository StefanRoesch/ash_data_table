defmodule DemoWeb.E2E.MarkersLive do
  @moduledoc """
  A page for the browser tests of the grid's hook on its markers alone: a
  grid drawn with `div`s and
  `span`s, no `table`, `tr` or `td`, that carries the table's markers (the
  roles of the grid, its rows, row groups and cells, `aria-colindex`, the
  `data-*` of `AshDataTable.Attrs`) and the grid's hook, with a table nested
  in a cell. The page answers the hook's events itself, as a table would:
  a save is kept and drawn, a selection is heard. If the hook relied on a
  tag, it would fail here.

  The note of the first record shows two lines of its text (`data-lines`,
  its paragraph `data-paragraph`) and shows its whole text in place by the
  button the hook puts into it (`data-whole`, its texts on the grid's
  element); under the first record is the line of its parts, which
  opens and closes the nested table (`toggle`).

  The header of each grid is a row group too, as a kit may draw it: the
  hook must not take it for a record.

  `?mount=1` draws the grid without its `phx-hook`: the demo's hook
  `MountedGrid` (`assets/js/mounted_grid.js`) mounts the grid's hook by
  hand through the package's public entries (`mountGrid`,
  `liveViewTransport`), as a kit that draws in the browser does
  (`e2e/contract.spec.ts`), and the hook of a pagination beside it
  (`mountPagination`).

  `?missing=colindex` draws one cell without its place (`aria-colindex`),
  for the development check of the hook. `?asks=1` has the column
  "Name" ask before a save, in the question dialog (`kit-dialog`), which
  `?missing=dialog` leaves out: then nothing is saved. `?panel=1` draws an
  action panel in the page whose action asks before it runs (`kit-panel`);
  with `?missing=grid` it finds no grid of its table, and nothing runs. Compiled and routed in the
  e2e environment only. A whole table drawn with the demo's kit of `div`s
  is `/e2e/kit` (`DemoWeb.E2E.KitLive`); this page stays for what
  a kit can leave out, which the development check names.
  """
  use DemoWeb, :live_view

  @columns [name: "Name", size: "Size", note: "Note"]
  @rows [
    {"a",
     %{
       name: "Anchor",
       size: "12",
       note:
         "first, and a note long enough to be cut off after the two lines its column shows: " <>
           "it goes on about the anchor, its chain, its weight and where it is kept"
     }},
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
       missing: params["missing"],
       asks: params["asks"] == "1",
       panel: params["panel"] == "1",
       mount: params["mount"] == "1",
       open: true
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

  # the line of the parts under the first record: opened and closed
  def handle_event(
        "ash_data_table:kit:toggle",
        %{"row" => "a", "relationship" => "parts"},
        socket
      ),
      do: {:noreply, assign(socket, open: not socket.assigns.open)}

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
        :where(#kit [role=table]) { display: table; border-collapse: collapse }
        :where(#kit [role=rowgroup]) { display: table-row-group }
        :where(#kit-head, #kit-row-a-t-parts-head) { display: table-header-group }
        :where(#kit [role=row]) { display: table-row }
        :where(#kit [role=cell], #kit [role=columnheader]) { display: table-cell; padding: 2px 8px; border: 1px solid; position: relative }
        :where(#kit [data-lines] > [data-paragraph]) { margin: 0; max-width: 16rem; display: -webkit-box; -webkit-box-orient: vertical; -webkit-line-clamp: 2; overflow: hidden }
        :where(#kit [role=cell]:has(> [data-whole][aria-expanded=true]) > [data-paragraph]) { display: block; -webkit-line-clamp: unset }
        :where(#kit [data-whole])::before { content: attr(data-whole) }
        :where(#kit [data-resize]) { position: absolute; top: 0; bottom: 0; right: 0; width: 8px; cursor: col-resize }
        :where(#kit-grid) { overflow-x: auto }
      </style>
      <div id="kit">
        <div id="kit-columns-control">
          <button
            type="button"
            id="kit-columns-button"
            popovertarget="kit-columns"
            data-columns-button
            data-text="Columns"
            data-text-with="Columns ({details})"
            data-text-hidden={Jason.encode!(for n <- 1..3, do: "#{n} hidden")}
            data-text-filtered={Jason.encode!(for n <- 1..3, do: "#{n} filtered")}
            data-text-sorted={Jason.encode!(for n <- 1..3, do: "#{n} sorted")}
          >
            <span id="kit-columns-text" phx-update="ignore">Columns</span>
          </button>
          <div
            id="kit-columns"
            role="group"
            aria-label="Columns"
            popover="auto"
            data-columns-list
          >
            <div :for={{name, label} <- @columns}>
              <label id={"kit-column-#{name}-entry"}>
                <input
                  type="checkbox"
                  id={"kit-column-#{name}"}
                  checked
                  data-head={"kit-head-#{name}"}
                  data-say-hidden={"#{label} hidden"}
                  data-say-shown={"#{label} shown"}
                />
                <span>{label}</span>
              </label>
              <input
                id={"kit-column-#{name}-width"}
                type="number"
                min="48"
                max="1000"
                aria-label={"Width of #{label}"}
                data-width={"kit-head-#{name}"}
              />
            </div>
            <button id="kit-reset-widths" type="button" data-reset-widths>Reset widths</button>
          </div>
          <span id="kit-columns-status" role="status" phx-update="ignore"></span>
        </div>
        <div id="kit-sender" phx-hook="AshDataTable.Sender" data-sender data-table="kit" hidden></div>
        <div
          :if={@mount}
          id="kit-mount"
          phx-hook="MountedGrid"
          data-grid="kit-grid"
          data-pagination="kit-pagination"
          hidden
        >
        </div>
        <div
          id="kit-grid"
          phx-hook={if @mount, do: nil, else: "AshDataTable.Grid"}
          data-ash-data-table
          data-table="kit"
          data-lead="1"
          data-select="multi"
          data-show-whole="Show all"
          data-show-less="Show less"
          tabindex="-1"
        >
          <div
            id="kit-table"
            role="table"
            aria-label="Kit"
            aria-rowcount="5"
            aria-colcount="4"
          >
            <div id="kit-head" role="rowgroup">
              <div id="kit-head-row" role="row" aria-rowindex="1">
                <span
                  id="kit-select-head"
                  role="columnheader"
                  aria-colindex="1"
                  data-select-page
                >
                  <input type="checkbox" aria-label="Select all rows of this page" />
                </span>
                <span
                  :for={{{name, label}, index} <- Enum.with_index(@columns)}
                  id={"kit-head-#{name}"}
                  role="columnheader"
                  aria-colindex={index + 2}
                  aria-label={label}
                >
                  {label}<span id={"kit-resize-#{name}"} aria-hidden="true" data-resize></span>
                </span>
              </div>
              <div id="kit-filter-row" role="row" aria-rowindex="2">
                <span
                  id="kit-select-filter"
                  role="cell"
                  aria-colindex="1"
                ></span>
                <span
                  :for={{{name, _label}, index} <- Enum.with_index(@columns)}
                  id={"kit-filter-#{name}"}
                  role="cell"
                  aria-colindex={index + 2}
                ></span>
              </div>
            </div>
            <%= for {{key, values}, at} <- Enum.with_index(@rows) do %>
              <div id={"kit-row-#{key}"} role="rowgroup">
                <div id={"kit-row-#{key}-r"} role="row" aria-rowindex={at + 3}>
                  <span
                    id={"kit-row-#{key}-s"}
                    role="cell"
                    aria-colindex="1"
                    data-selector
                  >
                    <input type="checkbox" aria-label="Select row" />
                  </span>
                  <span
                    :for={{{name, _label}, index} <- Enum.with_index(@columns)}
                    id={"kit-row-#{key}-c-#{name}"}
                    role="cell"
                    aria-colindex={
                      if @missing == "colindex" and key == "b" and name == :size,
                        do: nil,
                        else: index + 2
                    }
                    data-value={name == :name && values[name]}
                    data-lines={name == :note && "2"}
                    tabindex={name == :name && "0"}
                  ><p :if={name == :note} data-paragraph>{values[name]}</p>
                  <%= if name != :note do %>
                    {values[name]}
                  <% end %></span>
                </div>
              </div>
              <div
                :if={key == "a"}
                id={"kit-row-#{key}-x"}
                role="rowgroup"
                data-detail
                data-row={key}
              >
                <div id={"kit-row-#{key}-l-parts"} role="row">
                  <span
                    id={"kit-row-#{key}-l-parts-c"}
                    role="cell"
                    colspan="4"
                    aria-colindex="1"
                    data-line="parts"
                  >
                    <button type="button" aria-expanded={to_string(@open)}>
                      Parts
                    </button>
                  </span>
                </div>
                <div :if={@open} id={"kit-row-#{key}-n-parts"} role="row">
                  <span
                    id={"kit-row-#{key}-n-parts-c"}
                    role="cell"
                    colspan="4"
                    aria-colindex="1"
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
                        role="table"
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
                              role="cell"
                              aria-colindex="1"
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
          <template
            id="kit-editor-name"
            data-editor="text"
            data-confirm={@asks && "Rename this part?"}
          >
            <textarea rows="1" aria-label="Name"></textarea>
          </template>
        </div>
        <%!-- with `?mount=1`, a pagination whose hook is mounted by hand
        too; its buttons are the test's to change, as a kit's commit does --%>
        <nav
          :if={@mount}
          id="kit-pagination"
          data-table="kit"
          aria-label="Pages"
          phx-update="ignore"
        >
          <button type="button" id="kit-page-1" aria-current="page">1</button>
          <button type="button" id="kit-page-2">2</button>
        </nav>
        <%!-- an action panel in the page whose action asks before it
        runs; with `?missing=grid` it names a table whose grid is not on
        the page, so there is nobody to ask --%>
        <div
          :if={@panel}
          id="kit-panel"
          role="region"
          aria-label="Stamp"
          phx-hook="AshDataTable.Panel"
          data-table={if @missing == "grid", do: "elsewhere", else: "kit"}
          data-presentation="inline"
          data-question="Stamp this part?"
        >
          <form id="kit-panel-form" phx-submit="ash_data_table:kit:panel_submit" novalidate>
            <input type="text" name="form[note]" aria-label="Note" />
            <button type="submit">Run</button>
          </form>
        </div>
        <dialog
          :if={@missing != "dialog"}
          id="kit-dialog"
          role="dialog"
          aria-labelledby="kit-dialog-question"
          phx-update="ignore"
        >
          <form method="dialog">
            <p id="kit-dialog-question"></p>
            <button value="cancel">Cancel</button>
            <button value="confirm">Confirm</button>
          </form>
        </dialog>
      </div>
    </Layouts.app>
    """
  end
end
