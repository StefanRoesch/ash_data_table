defmodule AshTableProto.Components do
  @moduledoc """
  THROWAWAY PROTOTYPE (#11). Variant C `components`: one stateful
  LiveComponent PER ROW (not per cell, which is what Backpex does), as the
  baseline many libraries use. The grid keeps the page of records to render
  the row components; each row component keeps its own record, open state and
  failed edits and handles its own events.
  """
  use Phoenix.LiveComponent
  alias AshTableProto.{Data, Model, Parts, State}
  alias AshTableProto.Components.Row

  @impl true
  def update(%{poke: poke}, socket) do
    row = Enum.at(socket.assigns.rows, poke["index"])
    send_update(Row, id: "#{socket.assigns.id}-#{row.id}", poke: poke)
    {:ok, socket}
  end

  def update(assigns, socket) do
    case State.assign_inputs(socket, assigns, __MODULE__) do
      {:reload, socket} -> {:ok, load(socket)}
      {:keep, socket} -> {:ok, socket}
    end
  end

  defp load(socket) do
    {records, total} = Data.fetch(socket.assigns)
    assign(socket, rows: Model.rows(records, socket.assigns), total: total)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} data-grid phx-hook={Parts.hook()} class="overflow-x-auto">
      <table
        role="grid"
        aria-label={State.label(assigns)}
        aria-rowcount={@total + 1}
        style={Parts.table_style(@cfg, @columns, @nested)}
        class="w-full border-collapse text-sm"
      >
        <Parts.thead
          gid={@id}
          columns={@columns}
          sort={@sort}
          nested={@nested}
          layout={@cfg[:layout]}
        />
        <.live_component
          :for={row <- @rows}
          :key={row.id}
          module={Row}
          id={"#{@id}-#{row.id}"}
          gid={@id}
          row={row}
          columns={@columns}
          nested={@nested}
        />
      </table>
      <Parts.pager page={@page} page_size={@page_size} total={@total} myself={@myself} />
      <Parts.editors gid={@id} columns={@columns} />
    </div>
    """
  end

  @impl true
  def handle_event("expand_first", %{"n" => n}, socket) do
    for row <- Enum.take(socket.assigns.rows, String.to_integer(n)) do
      send_update(Row, id: "#{socket.assigns.id}-#{row.id}", open: true)
    end

    {:noreply, socket}
  end

  def handle_event("sort", %{"col" => name}, socket) do
    sort = State.next_sort(socket.assigns.sort, socket.assigns.columns, name)
    {:reply, %{}, socket |> assign(sort: sort, page: 1) |> load()}
  end

  def handle_event("page", %{"to" => to}, socket) do
    {:noreply, socket |> assign(page: State.next_page(socket.assigns, to)) |> load()}
  end
end

defmodule AshTableProto.Components.Row do
  @moduledoc "THROWAWAY PROTOTYPE (#11). The per-row LiveComponent of variant C."
  use Phoenix.LiveComponent
  alias AshTableProto.{Data, Parts, State}

  @impl true
  def update(%{open: open}, socket), do: {:ok, update(socket, :row, &%{&1 | open: open})}
  def update(%{poke: poke}, socket), do: {:ok, elem(save(socket, poke), 1)}
  # A fresh row from the grid (first render, page or sort change) resets the row's state.
  def update(assigns, socket), do: {:ok, assign(socket, assigns)}

  @impl true
  def render(assigns) do
    ~H"""
    <tbody id={@id} class="border-t border-base-300">
      <Parts.row_inner gid={@gid} row={@row} columns={@columns} nested={@nested} />
    </tbody>
    """
  end

  @impl true
  def handle_event("save", params, socket) do
    {reply, socket} = save(socket, params)
    {:reply, reply, socket}
  end

  def handle_event("clear", %{"col" => name}, socket) do
    col = State.column(socket.assigns.columns, name)
    {:noreply, update(socket, :row, &%{&1 | errs: Map.delete(&1.errs, col.name)})}
  end

  def handle_event("toggle", _params, socket) do
    {:noreply, update(socket, :row, &%{&1 | open: !&1.open})}
  end

  defp save(socket, %{"col" => name, "value" => value}) do
    col = State.column(socket.assigns.columns, name)
    row = socket.assigns.row

    case Data.save(row.rec, col, value, socket.assigns[:load] || []) do
      {:ok, rec} ->
        {%{ok: true}, assign(socket, row: %{row | rec: rec, errs: Map.delete(row.errs, col.name)})}

      {:error, message} ->
        {%{ok: false}, assign(socket, row: %{row | errs: Map.put(row.errs, col.name, {value, message})})}
    end
  end
end
