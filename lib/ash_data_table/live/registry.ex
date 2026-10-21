defmodule AshDataTable.Live.Registry do
  @moduledoc false
  # The tables one `AshDataTable.Table` shows: the
  # table on the page, its `entry`, and every other in `entries`, by id. One
  # id names all that LiveView keeps of a table on the socket: its stream
  # (a name from the pool), its async tasks (`async/2`), its uploads
  # (`id <> "-file-" <> argument`) and its listener's batches.
  #
  # The modules of the live core read and change `table.entry`.
  # `within/3` checks another entry out into that place, runs a function,
  # and puts it back: outside it, `table.entry` is the table on the page.
  # All of it is over the table (stage 9g): what LiveView keeps on the
  # socket is changed through the table's effects (`Live.Core.effect/2`).

  alias AshDataTable.Live.Core
  alias AshDataTable.Table

  # ---- one entry at a time --------------------------------------------

  @doc """
  Runs `fun` on the table with the entry `id` as `table.entry`, and puts
  it back. `fun` returns the table, or `{table, reply}`, which is returned
  the same way.

  A table other than the one on the page is placed by the table it is in:
  it is shown the options of a table without a URL, a heading or a page of
  its own.
  """
  def within(%Table{entry: %{id: id}} = table, id, fun), do: fun.(table)

  def within(%Table{} = table, id, fun) do
    %{entry: current, entries: %{^id => entry} = entries, options: options} = table

    checked_out = %{
      table
      | entry: entry,
        entries: entries |> Map.delete(id) |> Map.put(current.id, current),
        options: placed(current, entry, options)
    }

    back = fn %{entry: entry, entries: entries} = table ->
      %{
        table
        | entry: Map.fetch!(entries, current.id),
          entries: entries |> Map.delete(current.id) |> Map.put(entry.id, entry),
          options: options
      }
    end

    case fun.(checked_out) do
      {%Table{} = table, reply} -> {back.(table), reply}
      %Table{} = table -> back.(table)
    end
  end

  # The options a table is shown: the page's own for the table on the page,
  # those of a table placed in another for every other.
  defp placed(_current, %{path: [_top]}, options), do: options

  defp placed(_current, _entry, options),
    do: %{options | url: nil, heading: false, mounted?: false}

  @doc "Whether the table `id` is one of these: the one on the page or another."
  def known?(%Table{} = table, id), do: table.entry.id == id or is_map_key(table.entries, id)

  @doc """
  The key of an async task of the current entry, of the kind `:read`,
  `:summary` or `:bulk`: its id, and the kind with the entry's token, so
  that an answer is known as this entry's (`current?/2`).
  """
  def async(%Table{entry: %{id: id, token: token}}, kind),
    do: {:ash_data_table, id, {kind, token}}

  @doc """
  The function of an async task that runs a query (`start_async/3`, the
  effect `{:async, key, fun}`, `AshDataTable.Live.Core.effects/2`): it
  finishes its query whatever happens to the LiveView meanwhile. The task
  traps exits, so neither the end of the LiveView it is linked to nor
  `Phoenix.LiveView.cancel_async/3` would stop it (a table that closes
  leaves its tasks be); what it answers then is dropped, by LiveView when
  the LiveView is gone, else by `current?/2`.

  Stopped in the middle of a statement, it would take down the database
  connection it holds, and in a browser test the sandbox's transaction
  with it (#66). A running query cannot be cancelled in exchange.
  """
  def finishing(fun) when is_function(fun, 0) do
    fn ->
      Process.flag(:trap_exit, true)
      fun.()
    end
  end

  @doc """
  A task's function that owns files of the calling process before its work
  starts (#66): `{fun, hand_over}`. The task (`fun`, started with
  `start_async/3`) first says which process it is and waits; `hand_over`,
  called by the starting process right after, gives it the files
  (`Plug.Upload.give_away/3`, temporary files of `Plug.Upload.random_file!/1`)
  and lets it go on with `work`. So the files are the run's before the
  callback that starts it is over, and the page can go any time after
  without taking them along. A page that goes before the hand-over takes
  them with it, and the work never starts: the task sees it go and ends.
  """
  def owned(work) when is_function(work, 0) do
    view = self()
    ref = make_ref()

    task = fn ->
      watch = Process.monitor(view)
      send(view, {ref, self()})

      receive do
        {^ref, :yours} ->
          Process.demonitor(watch, [:flush])
          work.()

        {:DOWN, ^watch, :process, _view, reason} ->
          exit({:shutdown, {:page_gone, reason}})
      end
    end

    hand_over = fn paths ->
      receive do
        {^ref, pid} ->
          Enum.each(paths, fn path -> :ok = Plug.Upload.give_away(path, pid, view) end)
          send(pid, {ref, :yours})
      after
        # a task says who it is as it starts: one that does not was never
        # started, and its files are not given to anyone
        5_000 -> raise "ash_data_table: the run on the selection did not start"
      end
    end

    {task, hand_over}
  end

  @doc """
  Whether an async key is of a table that is shown now: its id known and
  its token that table's. A task of a table that closed answers all the
  same once its query is done (`finishing/1`), maybe after a table of the
  same id has opened.
  """
  def current?(%Table{} = table, {:ash_data_table, id, {_kind, token}}) do
    case table do
      %{entry: %{id: ^id, token: ^token}} -> true
      %{entries: %{^id => %{token: ^token}}} -> true
      _gone -> false
    end
  end

  def current?(_table, _key), do: false

  # ---- streams ----------------------------------------------------------

  @doc """
  A stream name for a table that opens, empty: one no open table uses, or
  a new one, configured once (`stream_configure/3` cannot be undone, so the
  socket holds as many streams as tables were ever open at once). The
  stream's effects (`{:stream, …}`) are the table's.
  """
  def take_stream(%Table{pool: pool} = table) do
    # named after the table on the page, which takes the first: the
    # streams of two tables of one LiveView, and the host's own, never clash
    prefix = Map.get(pool, :prefix) || table.entry.id
    pool = Map.put(pool, :prefix, prefix)

    {name, table, pool} =
      case pool do
        %{free: [name | free]} ->
          {name, table, %{pool | free: free}}

        %{next: next} ->
          name = if next == 0, do: "#{prefix}:rows", else: "#{prefix}:rows_#{next}"
          {name, Core.effect(table, {:stream, {:configure, name}}), %{pool | next: next + 1}}
      end

    {name, Core.effect(%{table | pool: pool}, {:stream, {:reset, name, []}})}
  end

  @doc "Gives a stream name back to the pool, emptied."
  def give_back(%Table{pool: pool} = table, name) do
    %{table | pool: %{pool | free: [name | pool.free]}}
    |> Core.effect({:stream, {:reset, name, []}})
  end

  # ---- opening and closing --------------------------------------------

  @doc """
  Adds the table `id`, placed in the cell of the table it is in and with
  its heading on the line above it (`{cell, heading}`, nil for a picker's
  table), with a stream of its own and nothing else yet: it is told what it
  is with `within/3`.
  """
  def add(%Table{} = table, id, place) do
    {stream, %{entries: entries} = table} = take_stream(table)
    {target, heading} = place || {nil, nil}

    entry = %{
      AshDataTable.Live.Entry.new()
      | id: id,
        target: target,
        heading_target: heading,
        stream: stream
    }

    %{table | entries: Map.put(entries, id, entry)}
  end

  @doc """
  Closes the table `id`, which is not the one on the page: its listener
  stopped, its tasks left to finish their query with their answer dropped
  (`finishing/1`, `current?/2`), a run on the selection keeping its own
  copies of its files, its uploads cancelled and given up (an upload whose file is on its way when
  the table closes stays allowed: LiveView drops its entry once the upload
  has stopped, and a table of the same id takes the name again), its
  stream emptied and its name back in the pool, its request ended (the
  host is told, `:request_ended`), its entry gone. What closes a table closes the tables under it
  too (`reconcile`): a table is never left without the one it is in.
  """
  def close(%Table{} = table, id) do
    table = within(table, id, &(&1 |> Core.Opener.closed(:all) |> shut()))
    %{entries: %{^id => %{stream: stream}} = entries} = table

    give_back(%{table | entries: Map.delete(entries, id)}, stream)
  end

  @doc """
  Closes every table, the one on the page too (`AshDataTable.detach/2`):
  each as `close/2` closes one, the table on the page last. Its stream is
  emptied and back in the pool, which keeps every name it configured.
  """
  def close_all(%Table{} = table) do
    table =
      table.entries
      |> Map.keys()
      |> Enum.reduce(table, fn id, table ->
        if is_map_key(table.entries, id), do: close(table, id), else: table
      end)
      |> shut()

    give_back(table, table.entry.stream)
  end

  # What closes with a table: its listener, its uploads (`{:uploads,
  # {:close, names}}`). Its async tasks are not stopped: each finishes its
  # query (`finishing/1`), and its answer is dropped (`current?/2`); a run
  # on the selection goes on to its end with the copies of its files,
  # which are its own.
  defp shut(%Table{} = table) do
    %{updates: %{live: live}, uploads: uploads} = table.entry

    if live, do: AshDataTable.Listener.stop(live.pid)

    if uploads == [], do: table, else: Core.effect(table, {:uploads, {:close, uploads}})
  end

  @doc """
  The tables drawn into a cell of another's row, in the order they opened:
  parents before their children, as a table opens after the one it is in
  (LiveView moves the portals of one patch in the order of the page, and a
  portal whose cell is not there yet fails), and a table that opens comes
  last, so that no other portal moves for it.
  """
  def portals(%{entries: entries}) do
    entries
    |> Map.values()
    |> Enum.filter(& &1.target)
    |> Enum.sort_by(& &1.opened)
  end
end
