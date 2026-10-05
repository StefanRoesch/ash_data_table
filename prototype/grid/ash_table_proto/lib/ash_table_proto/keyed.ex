defmodule AshTableProto.Keyed do
  @moduledoc """
  THROWAWAY PROTOTYPE (#11). Variant A `keyed`: the page of rows lives in a
  plain assign and is rendered with a keyed `:for` (LiveView 1.1+ change
  tracking). The server keeps the records.
  """
  use Phoenix.LiveComponent
  alias AshTableProto.{Data, Model, Parts, State}

  @impl true
  def update(%{poke: poke}, socket) do
    # A change that did not come from this grid's keyboard: for the
    # "does an open editor survive an unrelated patch" check.
    row = Enum.at(socket.assigns.rows, poke["index"])
    {_reply, socket} = save(socket, Map.put(poke, "row", row.id))
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
        <Parts.row
          :for={row <- @rows}
          :key={row.id}
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
  def handle_event("save", params, socket) do
    {reply, socket} = save(socket, params)
    {:reply, reply, socket}
  end

  def handle_event("clear", %{"row" => pk, "col" => name}, socket) do
    col = State.column(socket.assigns.columns, name)
    {:noreply, update_row(socket, pk, &%{&1 | errs: Map.delete(&1.errs, col.name)})}
  end

  def handle_event("toggle", %{"row" => pk}, socket) do
    {:noreply, update_row(socket, pk, &%{&1 | open: !&1.open})}
  end

  def handle_event("expand_first", %{"n" => n}, socket) do
    n = String.to_integer(n)

    rows =
      for {row, i} <- Enum.with_index(socket.assigns.rows), do: %{row | open: row.open or i < n}

    {:noreply, assign(socket, rows: rows)}
  end

  def handle_event("sort", %{"col" => name}, socket) do
    sort = State.next_sort(socket.assigns.sort, socket.assigns.columns, name)
    {:reply, %{}, socket |> assign(sort: sort, page: 1) |> load()}
  end

  def handle_event("page", %{"to" => to}, socket) do
    {:noreply, socket |> assign(page: State.next_page(socket.assigns, to)) |> load()}
  end

  defp save(socket, %{"row" => pk, "col" => name, "value" => value}) do
    col = State.column(socket.assigns.columns, name)
    row = Enum.find(socket.assigns.rows, &(to_string(&1.id) == to_string(pk)))

    case Data.save(row.rec, col, value, socket.assigns.cfg[:load] || []) do
      {:ok, rec} ->
        row = %{row | rec: rec, errs: Map.delete(row.errs, col.name)}
        {%{ok: true}, update_row(socket, pk, fn _ -> row end)}

      {:error, message} ->
        row = %{row | errs: Map.put(row.errs, col.name, {value, message})}
        {%{ok: false}, update_row(socket, pk, fn _ -> row end)}
    end
  end

  defp update_row(socket, pk, fun) do
    rows =
      Enum.map(socket.assigns.rows, fn row ->
        if to_string(row.id) == to_string(pk), do: fun.(row), else: row
      end)

    assign(socket, rows: rows)
  end
end
