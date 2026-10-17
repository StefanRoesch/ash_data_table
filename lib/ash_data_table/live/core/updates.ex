defmodule AshDataTable.Live.Core.Updates do
  @moduledoc false
  # Live updates: the listener, what was announced, the rows read
  # again, held back, or on their way out, and the notice.

  import Phoenix.LiveView

  alias AshDataTable.Ids
  alias AshDataTable.Listener
  alias AshDataTable.Live.Core
  alias AshDataTable.Live.Core.Reading
  alias AshDataTable.Query
  alias AshDataTable.Resource.Listening
  alias AshDataTable.Resource.Notifier

  require AshDataTable.Live.Current, as: Current

  # ---- live updates ----------------------------------------------------
  #
  # See "Live updates" at the top.

  # Starts to listen where the table follows live updates, on the topic of
  # its resource and of the tenant it reads in; stops where it no longer
  # does, and listens anew when the topic is another. Only once the page is
  # connected: the request that renders it first has nothing to update.
  def listen(socket) do
    %{resource: resource, model: model, live: live} = Core.table(socket).entry

    topic =
      if connected?(socket) and model.live? and model.primary_key != [],
        do: Notifier.topic(resource, tenant(Core.table(socket).caller))

    if (live && live.topic) == topic and (is_nil(live) or Process.alive?(live.pid)) do
      socket
    else
      if live, do: Listener.stop(live.pid)
      Core.put(socket, live: topic && listener(socket, topic))
    end
  end

  defp listener(socket, topic) do
    %{entry: %{id: id, resource: resource}, options: %{target: target}} = Core.table(socket)
    view = self()

    pub_sub =
      case Listening.pub_sub(resource) do
        {:ok, pub_sub} ->
          pub_sub

        {:error, reason} ->
          raise ArgumentError,
                "cannot follow the changes of #{inspect(resource)}: " <> Listening.message(reason)
      end

    # to the component that draws the table (the tag), or to the LiveView
    # it is attached to, whose hook takes it (`AshDataTable.Live.Hooks`)
    relay =
      case target do
        nil -> fn batch -> send(view, {:ash_data_table_heard, id, batch}) end
        cid -> fn batch -> Phoenix.LiveView.send_update(view, cid, live: {:heard, id, batch}) end
      end

    case Listener.start(pub_sub, topic, relay) do
      {:ok, pid} ->
        %{pid: pid, topic: topic}

      {:error, _not_running} ->
        raise ArgumentError,
              "cannot follow the changes of #{inspect(resource)}: the `table` block of " <>
                "#{inspect(Ash.Resource.Info.domain(resource))} names the Phoenix.PubSub server " <>
                "`#{inspect(pub_sub)}`, and no server of that name is running. Start it in the " <>
                "application's supervisor, before the endpoint: " <>
                "`{Phoenix.PubSub, name: #{inspect(pub_sub)}}`."
    end
  end

  # The tenant the table reads in.
  defp tenant(%{scope: nil, tenant: tenant}), do: tenant

  defp tenant(%{scope: scope}), do: Keyword.get(Ash.Scope.to_opts(scope), :tenant)

  # Looks at what was announced. Nothing of an announcement is shown: it
  # names records, and each is read again as the person
  # (`AshDataTable.Query.rows/4`).
  #
  #   * A record that is a row of the page is read again, without the
  #     person's filters, as a row is before something is done with it: what
  #     comes back is put in its place, and a row that does not come back
  #     goes, once the hook has said that no cell of it is being edited
  #     (`leave/2`). All of them in one read.
  #   * The row the action panel or the picker is open for, or under which
  #     one is open in a nested table, is left as it is until that is
  #     closed (`held`, `working/1`). Which cell a person is editing is
  #     the hook's to know, and the server never hears of it: the row is
  #     put back, and the hook leaves the cell that is being edited alone,
  #     as it does when another cell's save puts the row back
  #     (`beforeUpdate`).
  #   * A record that is no row of the page is never put into it. The table
  #     says that there are new or changed records, once, and only when at
  #     least one of them is a record this person would be shown: one more
  #     read, with their filters, that asks for one record.
  #
  # While a read is on its way, or an action on the selected rows, which
  # ends in one, it waits for that: the rows are then other rows. A table
  # that shows no rows has nothing to follow.
  def follow(socket)
      when Current.entry(socket, :waiting) == [] and Current.entry(socket, :held) == [],
      do: socket

  def follow(socket)
      when Current.entry(socket, :busy?) or not is_nil(Current.entry(socket, :running)),
      do: socket

  def follow(socket) when is_nil(Current.entry(socket, :page)),
    do: Core.put(socket, waiting: [], held: [])

  def follow(socket) do
    %{model: model, rows: rows, waiting: waiting, held: held} = Core.table(socket).entry

    {shown, others} =
      Enum.split_with(waiting, fn {_type, key} -> shown?(model, rows, key) end)

    working = working(Core.table(socket))

    {held, free} =
      (held ++ Enum.map(shown, &elem(&1, 1)))
      |> Enum.uniq()
      |> Enum.filter(&shown?(model, rows, &1))
      |> Enum.split_with(&(Reading.row_key(model, &1, 0) in working))

    socket
    |> Core.put(waiting: [], held: held)
    # whatever was announced may have changed what the summaries are of,
    # on this page or another: they are asked for again, once per batch
    |> Reading.due(if(waiting != [], do: :force))
    |> refresh(free)
    |> notice(for {type, key} <- others, type != :destroy, uniq: true, do: key)
  end

  # Whether the record with this primary key is a row of the page.
  defp shown?(model, rows, key), do: match?(%{pk: ^key}, rows[Reading.row_key(model, key, 0)])

  # The rows a person is working on, by the key in their id: the row the
  # action panel or the picker of this table is open for, and every row
  # under which a panel or a picker is open, in a table at whatever depth
  # below it (by `path`, in the registry).
  defp working(%{entry: %{id: id, open: open, panel: panel, picker: picker}, entries: entries}) do
    of_panel =
      case panel do
        %{key: key} when is_binary(key) -> [key]
        _no_row -> []
      end

    of_picker =
      case picker do
        %{for: {:cell, key, _column}} -> [key]
        _no_row -> []
      end

    shown =
      for {other, entry} <- entries,
          into: %{},
          do:
            {other,
             %{path: entry.path, open?: not is_nil(entry.panel) or not is_nil(entry.picker)}}

    under =
      for {other, %{open?: true, path: path}} <- shown,
          other != id,
          [^id, child | _] <- [Enum.drop_while(path, &(&1 != id))],
          {key, lines} <- open,
          name <- lines,
          child == Ids.nested_table(Ids.row(id, key), name),
          do: key

    of_panel ++ of_picker ++ under
  end

  # Reads rows of the page again, by their primary keys, and shows what
  # comes back. A read that fails says nothing about any of them: the page
  # is read again, which says what a read of it says.
  defp refresh(socket, []), do: socket

  defp refresh(socket, keys) do
    %{model: model, parent_key: parent} = Core.table(socket).entry

    case Query.rows(model, parent, keys, Reading.read_opts(socket)) do
      {:ok, records} ->
        found = Map.new(records, &{Reading.primary_key(model, &1), &1})

        Enum.reduce(keys, socket, fn key, socket ->
          row = Reading.row_key(model, key, 0)

          cond do
            # the page is being read again: a row before this one was its last
            not is_map_key(Core.table(socket).entry.rows, row) -> socket
            record = found[key] -> socket |> stay(row) |> put_fresh(row, record)
            true -> leave(socket, row)
          end
        end)

      {:error, _error} ->
        Reading.reread(socket)
    end
  end

  # A row whose record the read did not return: gone, or no longer this
  # person's to read. It is not taken away at once. Only the hook knows
  # whether a cell of the row is being edited, and the server is not to
  # learn which cell is (see "Editing" at the top): so the hook is asked
  # for this one row, and answers `left` at once, or when the editor in the
  # row is gone without a save. Until then the row is `leaving`. Nothing of
  # the record is sent again meanwhile, and whatever the person does with
  # the row reads the record first, and finds it gone.
  defp leave(socket, row) do
    %{id: id, leaving: leaving} = Core.table(socket).entry

    socket
    |> Core.put(leaving: MapSet.put(leaving, row))
    |> push_event("ash_data_table:leaving", %{table: id, row: row})
  end

  # A row that was on its way out, and whose record is the person's to read
  # again.
  defp stay(socket, row),
    do: Core.put(socket, leaving: MapSet.delete(Core.table(socket).entry.leaving, row))

  # A row with its record as it was read again. What has failed in the row
  # is still shown, on the record as it is now.
  defp put_fresh(socket, key, record), do: Reading.put_row(socket, key, record)

  # Says that there are new or changed records, when at least one of these
  # is a record the person would be shown; nothing otherwise, and nothing
  # twice. A page that is being read again will show what there is.
  defp notice(socket, []), do: socket

  defp notice(socket, _keys) when Current.entry(socket, :notice?), do: socket

  defp notice(socket, _keys) when Current.entry(socket, :busy?), do: socket

  defp notice(socket, keys) do
    %{model: model, state: state, parent_key: parent} = Core.table(socket).entry

    if Query.any?(model, state, parent, keys, Reading.read_opts(socket)),
      do: socket |> Core.put(notice?: true) |> Core.say({:text, :changed_records, []}),
      else: socket
  end

  # Sent by the hook for a row it was asked about (`ash_data_table:leaving`): no
  # cell of the row is being edited, and it can go. Only a row that is on
  # its way out is taken away, and only while nothing is open in it or
  # under it: then it waits, and is asked about again when that is closed.
  def on({:left, row}, socket) do
    %{leaving: leaving, rows: rows} = Core.table(socket).entry

    cond do
      not MapSet.member?(leaving, row) or not is_map_key(rows, row) ->
        {:noreply, socket}

      row in working(Core.table(socket)) ->
        held = Enum.uniq([rows[row].pk | Core.table(socket).entry.held])
        {:noreply, socket |> stay(row) |> Core.put(held: held)}

      true ->
        {:noreply, socket |> stay(row) |> Reading.remove_row(row)}
    end
  end

  # Sent by "Read again", beside the notice that there are new or changed
  # records: the page is read again as it is asked for now, with its sort,
  # filters and position.
  def on(:read_again, socket), do: {:noreply, Reading.reread(socket)}
end
