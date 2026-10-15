defmodule AshDataTable.Live.Registry do
  @moduledoc false
  # The tables one `AshDataTable.Table` shows (target.md 4.4, stage 5): the
  # table on the page, its `entry`, and every other in `entries`, by id. One
  # id names all that LiveView keeps of a table on the socket: its stream
  # (a name from the pool), its async tasks (`async/2`), its uploads
  # (`id <> "-file-" <> argument`) and its listener's batches.
  #
  # The modules of the live core read and change `table.entry`.
  # `within/3` checks another entry out into that place, runs a function,
  # and puts it back: outside it, `table.entry` is the table on the page.

  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 2]

  # ---- one entry at a time --------------------------------------------

  @doc """
  Runs `fun` on the socket with the entry `id` as `table.entry`, and puts it
  back. `fun` returns the socket, or `{:noreply, socket}` or
  `{:reply, reply, socket}`, which is returned the same way.

  A table other than the one on the page is placed by the table it is in:
  it is shown the options of a table without a URL, a heading or a page of
  its own.
  """
  def within(%{assigns: %{table: %{entry: %{id: id}}}} = socket, id, fun), do: fun.(socket)

  def within(socket, id, fun) do
    %{entry: current, entries: %{^id => entry} = entries, options: options} =
      table = socket.assigns.table

    checked_out = %{
      table
      | entry: entry,
        entries: entries |> Map.delete(id) |> Map.put(current.id, current),
        options: placed(current, entry, options)
    }

    back = fn socket ->
      %{entry: entry, entries: entries} = table = socket.assigns.table

      assign(socket,
        table: %{
          table
          | entry: Map.fetch!(entries, current.id),
            entries: entries |> Map.delete(current.id) |> Map.put(entry.id, entry),
            options: options
        }
      )
    end

    case fun.(assign(socket, table: checked_out)) do
      {:noreply, socket} -> {:noreply, back.(socket)}
      {:reply, reply, socket} -> {:reply, reply, back.(socket)}
      socket -> back.(socket)
    end
  end

  # The options a table is shown: the page's own for the table on the page,
  # those of a table placed in another for every other.
  defp placed(_current, %{path: [_top]}, options), do: options

  defp placed(_current, _entry, options),
    do: %{options | url: nil, heading: false, mounted?: false}

  @doc "Whether the table `id` is one of these: the one on the page or another."
  def known?(socket, id),
    do: socket.assigns.table.entry.id == id or is_map_key(socket.assigns.table.entries, id)

  @doc "The key of an async task of the current entry: `:read`, `:summary` or `:bulk`."
  def async(socket, kind), do: {:ash_data_table, socket.assigns.table.entry.id, kind}

  # ---- streams ----------------------------------------------------------

  @doc """
  A stream name for a table that opens, empty: one no open table uses, or
  a new one, configured once (`stream_configure/3` cannot be undone, so the
  socket holds as many streams as tables were ever open at once).
  """
  def take_stream(socket) do
    %{pool: pool} = table = socket.assigns.table

    {name, socket, pool} =
      case pool do
        %{free: [name | free]} ->
          {name, socket, %{pool | free: free}}

        %{next: next} ->
          name = if next == 0, do: "rows", else: "rows_#{next}"
          {name, stream_configure(socket, name, dom_id: & &1.dom_id), %{pool | next: next + 1}}
      end

    {name, socket |> assign(table: %{table | pool: pool}) |> stream(name, [], reset: true)}
  end
end
