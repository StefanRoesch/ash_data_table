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

  alias AshDataTable.Live.Core

  # ---- one entry at a time --------------------------------------------

  @doc """
  Runs `fun` on the socket with the entry `id` as `table.entry`, and puts it
  back. `fun` returns the socket, or `{:noreply, socket}` or
  `{:reply, reply, socket}`, which is returned the same way.

  A table other than the one on the page is placed by the table it is in:
  it is shown the options of a table without a URL, a heading or a page of
  its own.
  """
  def within(socket, id, fun) do
    case Core.table(socket) do
      %{entry: %{id: ^id}} -> fun.(socket)
      table -> within(socket, table, id, fun)
    end
  end

  defp within(socket, table, id, fun) do
    %{entry: current, entries: %{^id => entry} = entries, options: options} = table

    checked_out = %{
      table
      | entry: entry,
        entries: entries |> Map.delete(id) |> Map.put(current.id, current),
        options: placed(current, entry, options)
    }

    back = fn socket ->
      %{entry: entry, entries: entries} = table = Core.table(socket)

      Core.put(socket, %{
        table
        | entry: Map.fetch!(entries, current.id),
          entries: entries |> Map.delete(current.id) |> Map.put(entry.id, entry),
          options: options
      })
    end

    case fun.(Core.put(socket, checked_out)) do
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
    do: Core.table(socket).entry.id == id or is_map_key(Core.table(socket).entries, id)

  @doc "The key of an async task of the current entry: `:read`, `:summary` or `:bulk`."
  def async(socket, kind), do: {:ash_data_table, Core.table(socket).entry.id, kind}

  # ---- streams ----------------------------------------------------------

  @doc """
  A stream name for a table that opens, empty: one no open table uses, or
  a new one, configured once (`stream_configure/3` cannot be undone, so the
  socket holds as many streams as tables were ever open at once).
  """
  def take_stream(socket) do
    %{pool: pool} = table = Core.table(socket)

    {name, socket, pool} =
      case pool do
        %{free: [name | free]} ->
          {name, socket, %{pool | free: free}}

        %{next: next} ->
          name = if next == 0, do: "rows", else: "rows_#{next}"
          {name, stream_configure(socket, name, dom_id: & &1.dom_id), %{pool | next: next + 1}}
      end

    {name, socket |> Core.put(%{table | pool: pool}) |> stream(name, [], reset: true)}
  end

  @doc "Gives a stream name back to the pool, emptied."
  def give_back(socket, name) do
    %{pool: pool} = table = Core.table(socket)

    socket
    |> stream(name, [], reset: true)
    |> Core.put(%{table | pool: %{pool | free: [name | pool.free]}})
  end

  # ---- opening and closing --------------------------------------------

  @doc """
  Adds the table `id`, placed in the cell `target` of the table it is in,
  with a stream of its own and nothing else yet: it is told what it is with
  `within/3`.
  """
  def add(socket, id, target) do
    {stream, socket} = take_stream(socket)
    %{entries: entries} = table = Core.table(socket)
    entry = %{AshDataTable.Live.Entry.new() | id: id, target: target, stream: stream}

    Core.put(socket, %{table | entries: Map.put(entries, id, entry)})
  end

  @doc """
  Closes the table `id`, which is not the one on the page: its listener
  stopped, its tasks cancelled, the copies of a run's files removed, its
  uploads cancelled and given up (an upload whose file is on its way when
  the table closes stays allowed: LiveView drops its entry once the upload
  has stopped, and a table of the same id takes the name again), its
  stream emptied and its name back in the pool, its entry gone. What closes a table closes the tables under it
  too (`reconcile`): a table is never left without the one it is in.
  """
  def close(socket, id) do
    socket =
      within(socket, id, fn socket ->
        %{live: live, uploads: uploads} = Core.table(socket).entry

        if live, do: AshDataTable.Listener.stop(live.pid)

        socket =
          [:read, :summary, :bulk]
          |> Enum.reduce(socket, &cancel_async(&2, async(&2, &1)))
          |> AshDataTable.Live.Core.Files.drop_copies()

        # an upload with entries cannot be given up: they are cancelled
        # first. One that is being sent is only told to stop, and is there
        # until it has: LiveView refuses to give up its upload till then.
        Enum.reduce(uploads, socket, fn name, socket ->
          case socket.assigns[:uploads] do
            %{^name => %{entries: entries}} ->
              socket = Enum.reduce(entries, socket, &cancel_upload(&2, name, &1.ref))

              if socket.assigns.uploads[name].entries == [],
                do: disallow_upload(socket, name),
                else: socket

            _gone ->
              socket
          end
        end)
      end)

    %{entries: %{^id => %{stream: stream}} = entries} = table = Core.table(socket)

    socket
    |> Core.put(%{table | entries: Map.delete(entries, id)})
    |> give_back(stream)
  end

  @doc """
  The tables drawn into a cell of another's row, parents before their
  children: LiveView moves the portals of one patch in the order of the
  page, and a portal whose cell is not there yet fails.
  """
  def portals(%{entries: entries}) do
    entries
    |> Map.values()
    |> Enum.filter(& &1.target)
    |> Enum.sort_by(&{length(&1.path), &1.id})
  end
end
