defmodule AshTableProto.Streams do
  @moduledoc """
  THROWAWAY PROTOTYPE (#11). Variant B `streams`: rows live in a LiveView
  stream. The server does not keep the records, so an edit re-fetches the
  record by primary key and re-inserts the row with `stream_insert`.

  What the server does keep: the page's primary keys in order (for
  `aria-rowindex` and "open first N"), which rows are open, and failed edits.
  """
  use Phoenix.LiveComponent
  alias AshTableProto.{Data, Parts, State}

  @impl true
  def mount(socket) do
    {:ok, stream_configure(socket, :rows, dom_id: & &1.dom)}
  end

  @impl true
  def update(%{poke: poke}, socket) do
    pk = Enum.at(socket.assigns.ids, poke["index"])
    {_reply, socket} = save(socket, Map.put(poke, "row", pk))
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
    ids = Enum.map(records, & &1.id)

    socket =
      assign(socket,
        ids: ids,
        index: ids |> Enum.with_index() |> Map.new(),
        open: MapSet.new(),
        errs: %{},
        total: total
      )

    stream(socket, :rows, Enum.map(records, &item(socket, &1)), reset: true)
  end

  defp item(socket, rec) do
    a = socket.assigns

    %{
      id: rec.id,
      dom: "#{a.id}-#{rec.id}",
      idx: (a.page - 1) * a.page_size + Map.fetch!(a.index, rec.id) + 2,
      rec: rec,
      open: MapSet.member?(a.open, rec.id),
      errs: Map.get(a.errs, rec.id, %{})
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} data-grid phx-hook={Parts.hook()} class="overflow-x-auto">
      <table
        id={"#{@id}-t"}
        role="grid"
        aria-label={State.label(assigns)}
        aria-rowcount={@total + 1}
        style={Parts.table_style(@cfg, @columns, @nested)}
        class="w-full border-collapse text-sm"
        phx-update="stream"
      >
        <Parts.thead
          gid={@id}
          columns={@columns}
          sort={@sort}
          nested={@nested}
          layout={@cfg[:layout]}
        />
        <Parts.row
          :for={{dom_id, row} <- @streams.rows}
          id={dom_id}
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
    rec = Data.get!(socket.assigns.cfg, pk)
    {:noreply, socket |> put_err(rec.id, col.name, nil) |> reinsert(rec)}
  end

  def handle_event("toggle", %{"row" => pk}, socket) do
    rec = Data.get!(socket.assigns.cfg, pk)
    open = socket.assigns.open

    open =
      if MapSet.member?(open, rec.id),
        do: MapSet.delete(open, rec.id),
        else: MapSet.put(open, rec.id)

    {:noreply, socket |> assign(open: open) |> reinsert(rec)}
  end

  def handle_event("expand_first", %{"n" => n}, socket) do
    ids = Enum.take(socket.assigns.ids, String.to_integer(n))
    socket = assign(socket, open: MapSet.union(socket.assigns.open, MapSet.new(ids)))
    records = Data.get_many!(socket.assigns.cfg, ids)
    {:noreply, Enum.reduce(records, socket, &reinsert(&2, &1))}
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
    rec = Data.get!(socket.assigns.cfg, pk)

    case Data.save(rec, col, value, socket.assigns.cfg[:load] || []) do
      {:ok, rec} ->
        {%{ok: true}, socket |> put_err(rec.id, col.name, nil) |> reinsert(rec)}

      {:error, message} ->
        {%{ok: false}, socket |> put_err(rec.id, col.name, {value, message}) |> reinsert(rec)}
    end
  end

  defp put_err(socket, id, col_name, err) do
    row_errs = Map.get(socket.assigns.errs, id, %{})

    row_errs =
      if err, do: Map.put(row_errs, col_name, err), else: Map.delete(row_errs, col_name)

    errs =
      if row_errs == %{},
        do: Map.delete(socket.assigns.errs, id),
        else: Map.put(socket.assigns.errs, id, row_errs)

    assign(socket, errs: errs)
  end

  defp reinsert(socket, rec), do: stream_insert(socket, :rows, item(socket, rec))
end
