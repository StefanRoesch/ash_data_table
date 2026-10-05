defmodule AshTable.Live.TableComponent do
  @moduledoc false
  # The table itself: a grid whose rows live in a LiveView stream.
  #
  # The server keeps the table model, the state (sort and position) and what
  # the last read said about the pages; it does not keep the records. A change
  # of sort or page reads again and resets the stream.
  #
  # Markup contract (spec sections 7.2 and 13):
  #
  #   * the `<table role="grid">` is the stream container; the header is a
  #     child with its own id and every row is one `<tbody>`;
  #   * ids are stable and built from names, never from positions:
  #     `ID-head-FIELD` for a header cell, `ID-row-KEY` for a row's `<tbody>`
  #     and `ID-row-KEY-c-FIELD` for a cell;
  #   * `aria-colindex` is computed through `colindex/1`, which is where a
  #     leading expander column will be counted in; an actions column goes
  #     after the last data column. Neither position holds a cell yet.
  #
  # Use it through `AshTable.table/1`.
  use Phoenix.LiveComponent

  alias AshTable.Format
  alias AshTable.Model
  alias AshTable.Query
  alias AshTable.State
  alias AshTable.Text

  # Columns before the first data column: none until rows can be expanded.
  @leading_columns 0

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> stream_configure(:rows, dom_id: & &1.dom_id)
     |> assign(state: %State{}, page: nil, error: nil, row_count: 0, busy?: false, read: nil)}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      assign(
        socket,
        Map.take(assigns, [:id, :resource, :scope, :actor, :tenant, :authorize?, :url, :label])
      )

    model = Model.build(socket.assigns.resource)
    state = current_state(socket.assigns, model)

    {:ok, socket |> assign(model: model, state: state) |> read()}
  end

  # A table whose state lives in the URL takes it from there on every update;
  # an embedded table keeps what its own events set.
  defp current_state(%{url: url, id: id}, model) when is_binary(url) do
    State.from_params(model, url |> query_params() |> Map.get(id))
  end

  defp current_state(%{state: state}, _model), do: state

  # Reads again only when something a read depends on has changed. The first
  # read is done in place, so that the first render has rows; later ones run
  # beside the process, with the previous rows left in view and the grid
  # marked busy.
  defp read(socket) do
    %{model: model, state: state} = socket.assigns
    opts = Map.to_list(Map.take(socket.assigns, [:scope, :actor, :tenant, :authorize?]))
    read = {model, state, opts}

    cond do
      read == socket.assigns.read ->
        socket

      is_nil(socket.assigns.read) ->
        socket |> assign(read: read) |> show(Query.read(model, state, opts))

      true ->
        socket
        |> assign(read: read, busy?: true)
        |> start_async(:read, fn -> Query.read(model, state, opts) end)
    end
  end

  @impl true
  def handle_async(:read, {:ok, result}, socket) do
    {:noreply, socket |> assign(busy?: false) |> show(result)}
  end

  def handle_async(:read, {:exit, reason}, socket) do
    {:noreply, socket |> assign(busy?: false) |> show({:error, reason})}
  end

  defp show(socket, {:ok, %Query.Page{} = page}) do
    %{id: id, model: model} = socket.assigns

    rows =
      page.records
      |> Enum.with_index()
      |> Enum.map(fn {record, index} ->
        %{
          dom_id: "#{id}-row-#{row_key(model, record, index)}",
          record: record,
          # 1-based, the header row counted
          rowindex: (page.offset || 0) + index + 2
        }
      end)

    socket
    |> assign(page: %{page | records: []}, row_count: length(rows), error: nil)
    |> stream(:rows, rows, reset: true)
  end

  defp show(socket, {:error, error}) do
    socket
    |> assign(page: nil, row_count: 0, error: error_text(error))
    |> stream(:rows, [], reset: true)
  end

  defp error_text(%Ash.Error.Forbidden{}), do: Text.t(:not_allowed)
  defp error_text(_error), do: Text.t(:read_failed)

  # The primary key as a DOM id. A resource without one falls back to the
  # position in the page.
  defp row_key(%{primary_key: []}, _record, index), do: "n#{index}"

  defp row_key(%{primary_key: primary_key}, record, _index) do
    Enum.map_join(primary_key, "-", fn field ->
      value = record |> Map.get(field) |> to_string()

      if value =~ ~r/\A[A-Za-z0-9_-]+\z/,
        do: value,
        else: "b" <> Base.url_encode64(value, padding: false)
    end)
  end

  @impl true
  def handle_event("sort", %{"column" => name}, socket) do
    %{state: state, model: model} = socket.assigns
    {:noreply, go(socket, State.cycle_sort(state, model, name))}
  end

  def handle_event("page", %{"to" => to}, socket) do
    {:noreply, go(socket, target(socket.assigns, to))}
  end

  defp target(%{page: %{previous: %State{} = state}}, "previous"), do: state
  defp target(%{page: %{next: %State{} = state}}, "next"), do: state

  defp target(%{state: state, model: %{pagination: %{strategy: :offset}}} = assigns, to) do
    with {number, ""} when number > 0 <- Integer.parse(to),
         true <-
           is_nil(assigns.page) or is_nil(assigns.page.pages) or number <= assigns.page.pages do
      State.to_page(state, number)
    else
      _ -> state
    end
  end

  defp target(%{state: state}, _to), do: state

  # With the state in the URL the change is a patch, and the new state comes
  # back through `update/2`. Otherwise the component holds it.
  defp go(%{assigns: %{state: state}} = socket, state), do: socket

  defp go(%{assigns: %{url: url, id: id}} = socket, state) when is_binary(url) do
    params =
      case State.to_params(state) do
        empty when empty == %{} -> Map.delete(query_params(url), id)
        params -> Map.put(query_params(url), id, params)
      end

    path = URI.parse(url).path || "/"

    to =
      if params == %{}, do: path, else: path <> "?" <> Plug.Conn.Query.encode(params)

    push_patch(socket, to: to)
  end

  defp go(socket, state), do: socket |> assign(state: state) |> read()

  defp query_params(url) do
    case URI.parse(url).query do
      nil -> %{}
      query -> Plug.Conn.Query.decode(query)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="ash-table">
      <div id={"#{@id}-grid"} phx-hook=".Grid" class="overflow-x-auto">
        <table
          id={"#{@id}-table"}
          role="grid"
          aria-label={@label}
          aria-rowcount={aria_rowcount(@page)}
          aria-colcount={length(@model.columns)}
          aria-busy={@busy? && "true"}
          class={
            [
              "table aria-busy:opacity-60",
              # the focus ring of the cells, set once here to keep each cell's markup small
              "[&_:is(td,th):focus]:outline-2 [&_:is(td,th):focus]:-outline-offset-2 [&_:is(td,th):focus]:outline-primary"
            ]
          }
          phx-update="stream"
        >
          <thead id={"#{@id}-head"}>
            <tr id={"#{@id}-head-row"} role="row" aria-rowindex="1">
              <th
                :for={{column, index} <- Enum.with_index(@model.columns)}
                id={"#{@id}-head-#{column.name}"}
                role="columnheader"
                scope="col"
                aria-colindex={colindex(index)}
                aria-sort={column.sortable? && aria_sort(@state.sort, column)}
                tabindex="-1"
                data-sort={column.sortable?}
                phx-click={column.sortable? && "sort"}
                phx-value-column={column.sortable? && column.name}
                phx-target={column.sortable? && @myself}
                class={["whitespace-nowrap", column.sortable? && "cursor-pointer select-none"]}
                phx-no-format
              >{column.label}<span :if={column.sortable?} aria-hidden="true">{sort_mark(@state.sort, column)}</span></th>
            </tr>
          </thead>
          <%!-- Written without whitespace on purpose: every byte of a row is sent again
          whenever the row is, and a cell's text must not be padded. --%>
          <tbody :for={{dom_id, row} <- @streams.rows} id={dom_id} phx-no-format><tr
            id={"#{dom_id}-r"}
            role="row"
            aria-rowindex={row.rowindex}
          ><td
            :for={{column, index} <- Enum.with_index(@model.columns)}
            id={"#{dom_id}-c-#{column.name}"}
            role="gridcell"
            aria-colindex={colindex(index)}
            tabindex="-1"
          >{cell(column, Map.get(row.record, column.name))}</td></tr></tbody>
        </table>
      </div>
      <p :if={@error} id={"#{@id}-error"} role="alert" class="py-8 text-center text-sm text-error">
        {@error}
      </p>
      <p
        :if={is_nil(@error) and @row_count == 0}
        id={"#{@id}-empty"}
        class="py-8 text-center text-sm opacity-70"
      >
        {Text.t(:no_records)}
      </p>
      <nav
        :if={@page && @model.pagination.strategy != :none}
        id={"#{@id}-pagination"}
        aria-label={Text.t(:pagination)}
        class="mt-4 flex flex-wrap items-center justify-between gap-4"
      >
        <p id={"#{@id}-range"} class="text-sm">{range_text(@page, @row_count, @state)}</p>
        <div class="join">
          <button
            type="button"
            id={"#{@id}-previous"}
            class="join-item btn btn-sm"
            disabled={is_nil(@page.previous)}
            phx-click="page"
            phx-value-to="previous"
            phx-target={@myself}
          >
            {Text.t(:previous)}
          </button>
          <button
            :for={number <- page_numbers(@page, @state)}
            :if={@model.pagination.strategy == :offset}
            type="button"
            id={"#{@id}-page-#{number}"}
            class={["join-item btn btn-sm", number == @state.page && "btn-active"]}
            aria-label={Text.t(:go_to_page, page: number)}
            aria-current={number == @state.page && "page"}
            phx-click="page"
            phx-value-to={number}
            phx-target={@myself}
          >
            {number}
          </button>
          <button
            type="button"
            id={"#{@id}-next"}
            class="join-item btn btn-sm"
            disabled={is_nil(@page.next)}
            phx-click="page"
            phx-value-to="next"
            phx-target={@myself}
          >
            {Text.t(:next)}
          </button>
        </div>
      </nav>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".Grid">
        // Keyboard and focus for one grid: a single tab stop with a roving
        // tabindex, moved by the arrow keys. Nothing here talks to the server;
        // Enter on a sortable header clicks it, and the click is the server's.
        export default {
          mounted() {
            // the cell arrow keys start from: the first cell of the first data
            // row, or of the header while there are no rows
            this.pos = {r: 1, c: 0}
            this.col = 0
            this.activeId = null
            this.hadFocus = false
            this.el.addEventListener("keydown", e => this.onKeydown(e))
            this.el.addEventListener("focusin", e => this.onFocusin(e))
            this.el.addEventListener("focusout", e => this.onFocusout(e))
            this.el.addEventListener("click", e => this.onClick(e))
            // updated() only runs when this element itself is patched; a
            // stream insert or reset touches the rows alone.
            this.observer = new MutationObserver(() => this.sync())
            this.observer.observe(this.el, {
              subtree: true,
              childList: true,
              attributes: true,
              attributeFilter: ["tabindex"]
            })
            this.sync()
          },

          updated() { this.sync() },

          destroyed() { this.observer && this.observer.disconnect() },

          rows() {
            // HTMLTableElement.rows lists the header row first, wherever the
            // header sits among the stream's rows in the DOM.
            const table = this.el.querySelector("table")
            return table ? table.rows : []
          },

          cellOf(node) {
            const cell = node && node.closest ? node.closest("td,th") : null
            return cell && this.el.contains(cell) ? cell : null
          },

          cellAt(r, c) {
            const rows = this.rows()
            if (rows.length === 0) return null
            const row = rows[Math.max(0, Math.min(r, rows.length - 1))]
            return row.cells[Math.max(0, Math.min(c, row.cells.length - 1))] || null
          },

          setActive(cell) {
            const previous = this.activeId && document.getElementById(this.activeId)
            if (previous && previous !== cell && previous.tabIndex !== -1) previous.tabIndex = -1
            this.activeId = cell.id
            this.pos = {r: cell.parentElement.rowIndex, c: cell.cellIndex}
            if (cell.tabIndex !== 0) cell.tabIndex = 0
          },

          // After every patch: the server renders each cell with tabindex -1,
          // so the one tab stop has to be put back, and so has focus when the
          // focused cell did not survive the patch.
          sync() {
            let cell = this.activeId && document.getElementById(this.activeId)
            if (cell && !this.el.contains(cell)) cell = null
            if (!cell) cell = this.cellAt(this.pos.r, this.pos.c)
            if (!cell) return
            this.setActive(cell)
            if (this.hadFocus && !this.el.contains(document.activeElement)) {
              cell.focus({preventScroll: true})
            }
          },

          move(r, c) {
            const cell = this.cellAt(r, c)
            if (cell) cell.focus()
          },

          onFocusin(e) {
            const cell = this.cellOf(e.target)
            if (!cell) { this.hadFocus = false; return }
            this.hadFocus = true
            this.col = cell.cellIndex
            this.setActive(cell)
          },

          onFocusout(e) {
            if (e.relatedTarget) {
              if (!this.el.contains(e.relatedTarget)) this.hadFocus = false
            } else {
              // No new target: either focus really left (a click on nothing),
              // or a patch removed the focused cell and sync() puts it back.
              const target = e.target
              setTimeout(() => {
                if (target.isConnected && !this.el.contains(document.activeElement)) this.hadFocus = false
              }, 0)
            }
          },

          onClick(e) {
            const cell = this.cellOf(e.target)
            if (!cell) return
            this.col = cell.cellIndex
            if (document.activeElement !== cell) cell.focus()
          },

          onKeydown(e) {
            const cell = this.cellOf(e.target)
            if (!cell || e.altKey) return
            const rows = this.rows()
            const r = cell.parentElement.rowIndex
            const c = cell.cellIndex
            const lastC = cell.parentElement.cells.length - 1
            const lastR = rows.length - 1
            const ctrl = e.ctrlKey || e.metaKey
            let handled = true
            switch (e.key) {
              case "ArrowRight": this.col = Math.min(c + 1, lastC); this.move(r, this.col); break
              case "ArrowLeft": this.col = Math.max(c - 1, 0); this.move(r, this.col); break
              case "ArrowDown": this.move(r + 1, this.col); break
              // from the first data row this reaches the header
              case "ArrowUp": this.move(r - 1, this.col); break
              case "PageDown": this.move(Math.min(r + this.pageRows(cell), lastR), this.col); break
              // stays in the data rows; the header is one Arrow Up further
              case "PageUp": this.move(r === 0 ? 0 : Math.max(r - this.pageRows(cell), 1), this.col); break
              case "Home":
                this.col = 0
                this.move(ctrl ? Math.min(1, lastR) : r, 0)
                break
              case "End": {
                const row = ctrl ? rows[lastR] : cell.parentElement
                this.col = row.cells.length - 1
                this.move(row.rowIndex, this.col)
                break
              }
              case "Enter":
                if (cell.tagName === "TH" && cell.dataset.sort !== undefined) cell.click()
                else handled = false
                break
              // reserved for row selection; swallowed so the page does not scroll
              case " ": break
              default: handled = false
            }
            if (handled) e.preventDefault()
          },

          pageRows(cell) {
            return Math.max(1, Math.floor(window.innerHeight / (cell.offsetHeight || 24)) - 2)
          }
        }
      </script>
    </div>
    """
  end

  # 1-based position of a data column among all columns of the grid.
  defp colindex(index), do: @leading_columns + index + 1

  # The header row is counted. -1 says the total is not known.
  defp aria_rowcount(%{total: total}) when is_integer(total), do: total + 1
  defp aria_rowcount(_page), do: -1

  defp aria_sort({name, :asc}, %{name: name}), do: "ascending"
  defp aria_sort({name, :desc}, %{name: name}), do: "descending"
  defp aria_sort(_sort, _column), do: "none"

  defp sort_mark({name, :asc}, %{name: name}), do: " ▲"
  defp sort_mark({name, :desc}, %{name: name}), do: " ▼"
  defp sort_mark(_sort, _column), do: ""

  # A boolean is a check indicator with its accessible text beside it;
  # everything else is plain text.
  defp cell(%{cell_type: :boolean} = column, value) when is_boolean(value) do
    mark = if value, do: "✓", else: "–"

    {:safe,
     [
       ~s(<span aria-hidden="true">),
       mark,
       ~s(</span><span class="sr-only">),
       column
       |> Format.format(value)
       |> Phoenix.HTML.html_escape()
       |> Phoenix.HTML.safe_to_string(),
       "</span>"
     ]}
  end

  defp cell(column, value), do: Format.format(column, value)

  defp range_text(%{offset: offset, total: total}, row_count, _state)
       when is_integer(offset) and row_count > 0 do
    bindings = [from: offset + 1, to: offset + row_count, total: total]
    if total, do: Text.t(:range_of_total, bindings), else: Text.t(:range, bindings)
  end

  defp range_text(%{offset: offset}, _row_count, state) when is_integer(offset),
    do: Text.t(:page, page: state.page)

  defp range_text(_page, _row_count, _state), do: nil

  # The page numbers offered: the first, the last and those around the
  # current one. Without a total only the current page is known.
  defp page_numbers(%{pages: pages}, %{page: current}) when is_integer(pages) do
    [1, pages | Enum.to_list((current - 2)..(current + 2)//1)]
    |> Enum.filter(&(&1 >= 1 and &1 <= max(pages, current)))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp page_numbers(_page, %{page: current}), do: [current]
end
