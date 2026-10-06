defmodule AshTable.Live.TableComponent do
  @moduledoc false
  # The table itself: a grid whose rows live in a LiveView stream.
  #
  # The server keeps the table model, the state (sort, filters and position)
  # and what the last read said about the pages; it does not keep the records.
  # A change of sort, filter or page reads again and resets the stream.
  #
  # Markup contract (spec sections 7.2 and 13):
  #
  #   * the `<table role="grid">` is the stream container; the header is a
  #     child with its own id and every row is one `<tbody>`;
  #   * the header has two rows, the column headers and the filter row, which
  #     are not part of the stream. The controls of the filter row belong to
  #     the form `ID-filters`, which sits outside the table;
  #   * ids are stable and built from names, never from positions:
  #     `ID-head-FIELD` for a header cell, `ID-filter-FIELD` for a filter cell
  #     (its controls end in `-operator`, `-value` and `-clear`), `ID-row-KEY`
  #     for a row's `<tbody>` and `ID-row-KEY-c-FIELD` for a cell;
  #   * `aria-colindex` is computed through `colindex/1`, which is where a
  #     leading expander column will be counted in; an actions column goes
  #     after the last data column. Neither position holds a cell yet.
  #
  # Use it through `AshTable.table/1`.
  use Phoenix.LiveComponent

  alias AshTable.Format
  alias AshTable.Model
  alias AshTable.Model.Operator
  alias AshTable.Query
  alias AshTable.State
  alias AshTable.Text
  alias Phoenix.LiveView.JS

  # Columns before the first data column: none until rows can be expanded.
  @leading_columns 0

  # The rows above the data rows: the header and the filter row.
  @header_rows 2

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> stream_configure(:rows, dom_id: & &1.dom_id)
     |> assign(state: %State{}, page: nil, error: nil, row_count: 0, busy?: false, read: nil)
     # What the live region says, and how often it has spoken. `announce?` is
     # set by a filter change and answered by the read that follows it.
     |> assign(announce?: false, announcement: nil, announcements: 0)
     # What a person typed into a filter that is not a value of its column:
     # shown in the filter, marked, and not applied.
     |> assign(rejected: %{})}
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
          # 1-based, the header rows counted
          rowindex: (page.offset || 0) + index + @header_rows + 1
        }
      end)

    socket
    |> assign(page: %{page | records: []}, row_count: length(rows), error: nil)
    |> announce(page)
    |> stream(:rows, rows, reset: true)
  end

  # The error is an alert of its own.
  defp show(socket, {:error, error}) do
    socket
    |> assign(page: nil, row_count: 0, error: error_text(error), announce?: false)
    |> stream(:rows, [], reset: true)
  end

  # After a filter change, the result is put into the live region: the count
  # when the read action counts, else only that the rows have changed.
  defp announce(%{assigns: %{announce?: true}} = socket, page) do
    text =
      case page.total do
        nil -> Text.t(:results_updated)
        1 -> Text.t(:one_result)
        total -> Text.t(:results, count: total)
      end

    assign(socket,
      announce?: false,
      announcement: text,
      announcements: socket.assigns.announcements + 1
    )
  end

  defp announce(socket, _page), do: socket

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

  # Sent by the form of the filter row when a filter is left or a choice is
  # made, with every filter of the row.
  def handle_event("filter", params, socket) do
    %{state: state, model: model} = socket.assigns
    {state, rejected} = State.filter(state, model, Map.get(params, "filter", %{}))

    {:noreply, socket |> assign(rejected: rejected) |> refilter(state)}
  end

  def handle_event("clear_filter", %{"column" => name}, socket) do
    {:noreply, refilter(socket, State.clear_filter(socket.assigns.state, name))}
  end

  def handle_event("clear_filters", _params, socket) do
    state = State.clear_filters(socket.assigns.state)

    {:noreply, socket |> assign(rejected: %{}) |> refilter(state)}
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

  # A change of the filters is announced once its rows have been read.
  defp refilter(%{assigns: %{state: state}} = socket, state), do: socket
  defp refilter(socket, state), do: socket |> assign(announce?: true) |> go(state)

  # With the state in the URL the change is a patch, and the new state comes
  # back through `update/2`. Otherwise the component holds it.
  defp go(%{assigns: %{state: state}} = socket, state), do: socket

  defp go(%{assigns: %{url: url, id: id}} = socket, state) when is_binary(url) do
    params =
      case State.to_params(state, socket.assigns.model) do
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
      <%!-- The form of the filter row. A form cannot sit inside a table around
      its cells, so the controls name it instead. --%>
      <form
        id={"#{@id}-filters"}
        phx-change="filter"
        phx-submit="filter"
        phx-target={@myself}
      >
      </form>
      <%!-- as high as its button, so that the table does not move when it appears --%>
      <div class="mb-2 flex min-h-8 items-center justify-end">
        <%!-- the button goes away with the filters, so focus is sent on to the grid --%>
        <button
          :if={@state.filters != %{}}
          type="button"
          id={"#{@id}-clear-filters"}
          class="btn btn-sm"
          phx-click={
            JS.push("clear_filters", target: @myself)
            |> JS.focus(to: "##{@id}-table [tabindex='0']")
          }
        >
          {Text.t(:clear_filters)}
        </button>
      </div>
      <%!-- Read out after each filter change. A live region is only read when its
      content changes, so every other announcement ends in a no-break space. --%>
      <p id={"#{@id}-status"} role="status" aria-live="polite" class="sr-only" phx-no-format>{@announcement}{if rem(@announcements, 2) == 1, do: "\u00A0"}</p>
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
              # what every cell looks like is set once here, to keep each cell's markup small:
              # the focus ring
              "[&_:is(td,th):focus]:outline-2 [&_:is(td,th):focus]:-outline-offset-2 [&_:is(td,th):focus]:outline-primary",
              # one line per row: long text is cut off, not wrapped
              "[&_tbody_td]:max-w-80 [&_tbody_td]:truncate"
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
            <tr id={"#{@id}-filter-row"} role="row" aria-rowindex="2">
              <td
                :for={{column, index} <- Enum.with_index(@model.columns)}
                id={"#{@id}-filter-#{column.name}"}
                role="gridcell"
                aria-colindex={colindex(index)}
                tabindex="-1"
                data-filter={column.operators != []}
              >
                <.filter
                  :if={column.operators != []}
                  id={"#{@id}-filter-#{column.name}"}
                  form={"#{@id}-filters"}
                  column={column}
                  filter={@rejected[column.name] || @state.filters[column.name]}
                  rejected?={is_map_key(@rejected, column.name)}
                  target={@myself}
                />
              </td>
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
        // Enter on a sortable header clicks it, Enter in a filter submits the
        // filter row's form, and both are the server's from there.
        export default {
          mounted() {
            // the cell arrow keys start from: the first cell of the first data
            // row, or of the last header row while there are no rows
            this.pos = {r: this.headRows(), c: 0}
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
            // HTMLTableElement.rows lists the header rows first, wherever the
            // header sits among the stream's rows in the DOM.
            const table = this.el.querySelector("table")
            return table ? table.rows : []
          },

          // The rows above the data rows: the header and the filter row.
          headRows() {
            const table = this.el.querySelector("table")
            return table && table.tHead ? table.tHead.rows.length : 1
          },

          // The input, menu or button of a filter that a node is or is in.
          controlOf(node) {
            const control = node && node.closest ? node.closest("input,select,button") : null
            return control && this.el.contains(control) ? control : null
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
            // a click on a filter's control leaves focus in the control
            if (this.controlOf(e.target)) return
            if (document.activeElement !== cell) cell.focus()
          },

          // Into a filter cell: to where its value is typed or chosen, or to
          // its menu when the operator needs no value.
          enter(cell) {
            const control = cell.querySelector("[id$='-value']") || cell.querySelector("select,button")
            if (!control) return
            control.focus()
            if (control.select) control.select()
          },

          // Inside a filter the keys belong to its controls, the arrow keys
          // among them. The grid keeps three.
          onControlKeydown(e, control) {
            const cell = this.cellOf(control)
            const input = control.tagName === "INPUT"
            switch (e.key) {
              // back to the cell, giving up what was typed and not applied
              case "Escape":
                if (input) control.value = control.defaultValue
                cell.focus()
                e.preventDefault()
                break
              // applies the filter now; focus stays where the person is typing.
              // A patch leaves the value attribute of a focused input alone,
              // so what Escape restores is noted here.
              case "Enter":
                if (input && control.form) {
                  e.preventDefault()
                  if (control.form.reportValidity()) {
                    control.defaultValue = control.value
                    control.form.requestSubmit()
                  }
                }
                break
              // through the controls of this filter; from its last one Tab
              // leaves the grid, as it does from a cell
              case "Tab": {
                const controls = Array.from(cell.querySelectorAll("input,select,button"))
                const next = controls[controls.indexOf(control) + (e.shiftKey ? -1 : 1)]
                if (next) {
                  next.focus()
                  e.preventDefault()
                }
                break
              }
            }
          },

          onKeydown(e) {
            const cell = this.cellOf(e.target)
            if (!cell || e.altKey) return
            const control = this.controlOf(e.target)
            if (control) return this.onControlKeydown(e, control)
            const rows = this.rows()
            const head = this.headRows()
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
              // from the first data row this reaches the filter row, then the header
              case "ArrowUp": this.move(r - 1, this.col); break
              case "PageDown": this.move(Math.min(r + this.pageRows(cell), lastR), this.col); break
              // stays in the data rows; the header rows are an Arrow Up further
              case "PageUp": this.move(r < head ? r : Math.max(r - this.pageRows(cell), head), this.col); break
              case "Home":
                this.col = 0
                this.move(ctrl ? Math.min(head, lastR) : r, 0)
                break
              case "End": {
                const row = ctrl ? rows[lastR] : cell.parentElement
                this.col = row.cells.length - 1
                this.move(row.rowIndex, this.col)
                break
              }
              case "Enter":
                if (cell.tagName === "TH" && cell.dataset.sort !== undefined) cell.click()
                else if (cell.dataset.filter !== undefined) this.enter(cell)
                else handled = false
                break
              case "F2":
                if (cell.dataset.filter !== undefined) this.enter(cell)
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

  # The controls of one column's filter, showing the filter that applies.
  # They are out of the tab order: the grid is one tab stop, and the hook
  # moves focus into a filter cell.
  defp filter(assigns) do
    {operator, value} = assigns.filter || {nil, nil}
    assigns = assign(assigns, operator: operator, value: value)

    ~H"""
    <div class="flex items-center gap-1">
      <select
        :if={@column.cell_type == :boolean}
        id={"#{@id}-value"}
        name={"filter[#{@column.name}][o]"}
        form={@form}
        tabindex="-1"
        aria-label={Text.t(:filter, column: @column.label)}
        class="select select-xs w-auto"
      >
        <option value="">{Text.t(:any)}</option>
        <option :for={choice <- @column.operators} value={choice} selected={choice == @operator}>
          {Text.t(choice)}
        </option>
      </select>
      <select
        :if={@column.cell_type != :boolean and match?([_, _ | _], @column.operators)}
        id={"#{@id}-operator"}
        name={"filter[#{@column.name}][o]"}
        form={@form}
        tabindex="-1"
        aria-label={Text.t(:filter_operator, column: @column.label)}
        class="select select-xs w-auto"
      >
        <option :for={choice <- @column.operators} value={choice} selected={choice == @operator}>
          {operator_text(choice)}
        </option>
      </select>
      <select
        :if={@column.cell_type == :enum}
        id={"#{@id}-value"}
        name={"filter[#{@column.name}][v]"}
        form={@form}
        tabindex="-1"
        aria-label={Text.t(:filter, column: @column.label)}
        class="select select-xs w-auto"
      >
        <option value="">{Text.t(:any)}</option>
        <option
          :for={{choice, label} <- @column.values}
          value={choice}
          selected={to_string(choice) == @value}
        >
          {label}
        </option>
      </select>
      <%!-- an operator such as "is empty" is complete without a value --%>
      <input
        :if={
          @column.cell_type not in [:boolean, :enum] and
            (is_nil(@operator) or Operator.takes_value?(@operator))
        }
        type={input_type(@column.cell_type)}
        step={input_step(@column.cell_type)}
        id={"#{@id}-value"}
        name={"filter[#{@column.name}][v]"}
        form={@form}
        value={@value}
        phx-debounce="blur"
        tabindex="-1"
        aria-label={Text.t(:filter, column: @column.label)}
        aria-invalid={@rejected? && "true"}
        aria-describedby={@rejected? && "#{@id}-error"}
        class={["input input-xs w-32", @rejected? && "input-error"]}
      />
      <button
        :if={@filter && not @rejected?}
        type="button"
        id={"#{@id}-clear"}
        tabindex="-1"
        aria-label={Text.t(:clear_filter, column: @column.label)}
        class="btn btn-ghost btn-xs"
        phx-click="clear_filter"
        phx-value-column={@column.name}
        phx-target={@target}
      >
        <span aria-hidden="true">✕</span>
      </button>
    </div>
    <%!-- in the text colour: the error colour is too faint for small text --%>
    <p :if={@rejected?} id={"#{@id}-error"} class="mt-1 text-xs">
      {Text.t(:invalid_filter)}
    </p>
    """
  end

  defp operator_text(operator), do: Text.t(String.to_existing_atom("operator_#{operator}"))

  # The native input of each cell type that is filtered by a typed value.
  defp input_type(:text), do: "text"
  defp input_type(:number), do: "number"
  defp input_type(:date), do: "date"
  defp input_type(:datetime), do: "datetime-local"

  # Any number, not only whole ones; and a datetime to the second, as it is shown.
  defp input_step(:number), do: "any"
  defp input_step(:datetime), do: "1"
  defp input_step(_cell_type), do: nil

  # 1-based position of a data column among all columns of the grid.
  defp colindex(index), do: @leading_columns + index + 1

  # The header rows are counted. -1 says the total is not known.
  defp aria_rowcount(%{total: total}) when is_integer(total), do: total + @header_rows
  defp aria_rowcount(_page), do: -1

  defp aria_sort({name, :asc}, %{name: name}), do: "ascending"
  defp aria_sort({name, :desc}, %{name: name}), do: "descending"
  defp aria_sort(_sort, _column), do: "none"

  defp sort_mark({name, :asc}, %{name: name}), do: " ▲"
  defp sort_mark({name, :desc}, %{name: name}), do: " ▼"
  defp sort_mark(_sort, _column), do: ""

  # A field the actor may not see on this row looks empty and is announced.
  defp cell(_column, %Ash.ForbiddenField{}) do
    {:safe, [~s(<span class="sr-only">), escape(Text.t(:not_available)), "</span>"]}
  end

  # A boolean is a check indicator with its accessible text beside it;
  # everything else is plain text.
  defp cell(%{cell_type: :boolean} = column, value) when is_boolean(value) do
    mark = if value, do: "✓", else: "–"

    {:safe,
     [
       ~s(<span aria-hidden="true">),
       mark,
       ~s(</span><span class="sr-only">),
       escape(Format.format(column, value)),
       "</span>"
     ]}
  end

  defp cell(column, value), do: Format.format(column, value)

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

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
