defmodule AshDataTable.Live.Hooks do
  @moduledoc false
  # A table attached to a LiveView (`AshDataTable.attach/4`): what
  # the socket keeps of its tables, and the four hooks through which their
  # events, async results, batches of live updates and URLs reach them.
  #
  # The socket's private data, under `:ash_data_table`:
  #
  #   * `current`: the name of the table the callback works on, nil between
  #     callbacks (`AshDataTable.Live.Core.table/1`);
  #   * `tables`: the attached tables, by the name of their assign, each
  #     with what it was told (`given`, as the tag's attributes are given)
  #     and whether its state is in the URL (`url?`);
  #   * `streams`: by a table's id, the stream names it has configured and
  #     that are free: given back to a table of that id that is attached
  #     again, as LiveView cannot undo `stream_configure/3`;
  #   * `url`: the URL the last `handle_params/3` was given, for a table
  #     that keeps its state there and is attached after it;
  #   * `hooks`: the stages whose hooks are attached. They stay for the life
  #     of the socket: a late event, result or batch of a table that
  #     is gone is answered or dropped here, and never reaches the host.
  #
  # One set of hooks for all the tables of a socket. Each finds the
  # table by the id an event's name, an async key or a batch says; what
  # names a table no one knows is the table's all the same, and halted.

  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  alias AshDataTable.Live.Core
  alias AshDataTable.Live.Registry
  alias AshDataTable.Table

  @doc """
  Attaches the table `given` describes under the assign `name`, or tells
  the table attached there again. With `url?` the first read waits for
  the first `handle_params`; else it is done here, in place.
  """
  def attach(socket, name, given, url?) do
    if url? and is_nil(socket.router) do
      raise ArgumentError,
            "AshDataTable.attach/4 was given `url: true` in a LiveView that is not mounted by " <>
              "the router (`live/3`): only a routed LiveView has a URL to keep the table's " <>
              "state in. Leave `url` out to keep it in the table."
    end

    private = private(socket)

    case {Map.fetch(private.tables, name), socket.assigns[name]} do
      {{:ok, attached}, %Table{} = table} ->
        again(socket, name, attached, table, given, url?)

      {_none, nil} ->
        new(socket, name, given, url?)

      {_none, other} ->
        raise ArgumentError,
              "AshDataTable.attach/4 cannot put a table under the assign #{inspect(name)}: it " <>
                "holds #{inspect(other, limit: 3)}. Choose another name."
    end
  end

  # Attaching again with the same name tells the table again: who is asking
  # may have changed (`AshDataTable.Live.Core.asker/2`). What it is may not.
  defp again(socket, name, attached, table, given, url?) do
    same? =
      attached.given.resource == given.resource and attached.given.table == given.table and
        attached.given.id == given.id and attached.url? == url?

    if not same? do
      raise ArgumentError,
            "AshDataTable.attach/4: the assign #{inspect(name)} holds the table " <>
              "#{inspect(attached.given.id)} of #{inspect(attached.given.resource)}; to put " <>
              "another there, detach it first (`AshDataTable.detach(socket, #{inspect(name)})`)."
    end

    socket = put_table(socket, name, %{attached | given: given})

    # a table whose state is in the URL keeps the URL it was told last
    given = Map.put(given, :url, table.options.url)

    if url? and is_nil(table.options.url),
      do: socket,
      else: within(socket, name, &Core.tell(&1, given))
  end

  defp new(socket, name, given, url?) do
    private = private(socket)

    for {other, %{given: %{id: id}}} <- private.tables, id == given.id do
      raise ArgumentError,
            "AshDataTable.attach/4: the id #{inspect(id)} is the table's under " <>
              "#{inspect(other)}; two tables of a page need an id each (`id: \"...\"`)."
    end

    # the tables a table shows are named after it (`ID-row-…`, `ID-pick-…`):
    # an id that one of them may have is no other table's
    for {other, %{given: %{id: id}}} <- private.tables,
        inside?(given.id, id) or inside?(id, given.id) do
      raise ArgumentError,
            "AshDataTable.attach/4: the id #{inspect(given.id)} and the id #{inspect(id)} of " <>
              "the table under #{inspect(other)} clash: the tables a table shows have ids " <>
              "that begin with its own and `-row-` or `-pick-`. Choose another id."
    end

    table =
      Table.new()
      |> Table.put(target: nil, router: socket.router)
      |> Map.put(:pool, Map.get(private.streams, given.id, %{free: [], next: 0}))

    socket =
      socket
      |> assign(name, table)
      |> put_table(name, %{given: given, url?: url?})
      |> hooks(url?)

    # with its state in the URL it reads in the first `handle_params/3`,
    # or at once where that has run, with the URL it was given
    case {url?, private(socket).url} do
      {false, _url} -> within(socket, name, &Core.tell(&1, given))
      {true, nil} -> socket
      {true, url} -> within(socket, name, &Core.tell(&1, Map.put(given, :url, url)))
    end
  end

  @doc """
  Closes the table under `name`: every table it shows, and its own
  listener, tasks, uploads and stream, and sets the assign to nil. The
  names of its streams are kept for a table of the same id; the hooks
  stay.
  """
  def detach(socket, name) do
    private = private(socket)

    case {Map.fetch(private.tables, name), socket.assigns[name]} do
      {{:ok, %{given: %{id: id}}}, %Table{}} ->
        socket = within(socket, name, &Registry.close_all/1)
        %Table{pool: pool} = socket.assigns[name]
        private = private(socket)

        socket
        |> put_private(:ash_data_table, %{
          private
          | tables: Map.delete(private.tables, name),
            streams: Map.put(private.streams, id, pool)
        })
        |> assign(name, nil)

      _not_attached ->
        raise ArgumentError,
              "AshDataTable.detach/2: no table is attached under the assign #{inspect(name)}."
    end
  end

  @doc """
  Runs `fun` with the table under `name` as the one the callback works on,
  for a command of the host's (`AshDataTable.refresh/2` and the others),
  and returns what it returns. `where` names the command for the error of
  a name no table is attached under.
  """
  def command(socket, name, where, fun) do
    case {Map.fetch(private(socket).tables, name), socket.assigns[name]} do
      {{:ok, _attached}, %Table{}} ->
        within(socket, name, fun)

      _not_attached ->
        raise ArgumentError,
              "#{where}: no table is attached under the assign #{inspect(name)}. Commands " <>
                "are for a table attached with `AshDataTable.attach/4`, and the router " <>
                "page's (`:table`); a table placed with the tag takes none."
    end
  end

  defp inside?(id, top),
    do: String.starts_with?(id, top <> "-row-") or String.starts_with?(id, top <> "-pick-")

  # What the socket keeps of its tables.
  defp private(socket),
    do:
      Map.get(socket.private, :ash_data_table) ||
        %{current: nil, tables: %{}, streams: %{}, hooks: [], url: nil}

  defp put_table(socket, name, attached) do
    private = private(socket)

    put_private(socket, :ash_data_table, %{
      private
      | tables: Map.put(private.tables, name, attached)
    })
  end

  # The hooks, each attached once: those of events, results and
  # batches with the first table, the one of the URL with the first table
  # that keeps its state there.
  defp hooks(socket, url?) do
    %{hooks: hooks} = private(socket)

    socket =
      if :handle_event in hooks,
        do: socket,
        else:
          socket
          |> attach_hook(:ash_data_table, :handle_event, &event/3)
          |> attach_hook(:ash_data_table, :handle_async, &async/3)
          |> attach_hook(:ash_data_table, :handle_info, &info/2)

    socket =
      if url? and :handle_params not in hooks,
        do: attach_hook(socket, :ash_data_table, :handle_params, &params/3),
        else: socket

    wanted =
      [:handle_event, :handle_async, :handle_info] ++ if(url?, do: [:handle_params], else: [])

    put_private(socket, :ash_data_table, %{private(socket) | hooks: Enum.uniq(hooks ++ wanted)})
  end

  # Runs `fun` with the table under `name` as the one the callback works on.
  defp within(socket, name, fun) do
    private = private(socket)
    before = private.current
    socket = put_private(socket, :ash_data_table, %{private | current: name})
    back = &put_private(&1, :ash_data_table, %{private(&1) | current: before})

    case fun.(socket) do
      {:noreply, socket} -> {:noreply, back.(socket)}
      {:reply, reply, socket} -> {:reply, reply, back.(socket)}
      socket -> back.(socket)
    end
  end

  # The name of the table that knows the table `id`: the table under it, or
  # one it shows.
  defp named(socket, id) do
    Enum.find_value(private(socket).tables, fn {name, _attached} ->
      case socket.assigns[name] do
        %Table{entry: %{id: ^id}} -> name
        %Table{entries: %{^id => _}} -> name
        _other -> nil
      end
    end)
  end

  # ---- the hooks ----------------------------------------------------------

  # An event named for a table (`ash_data_table:ID:event`) is the table's,
  # whichever: one for a table that is gone gets the answer of an event of
  # another shape (`AshDataTable.Live.Core.unknown/2`).
  defp event("ash_data_table:" <> _ = event, params, socket) do
    {id, _plain} = Core.addressed(event)

    result =
      case named(socket, id) do
        nil -> Core.unknown(event, socket)
        name -> within(socket, name, &Core.handle_event(event, params, &1))
      end

    case result do
      {:noreply, socket} -> {:halt, socket}
      {:reply, reply, socket} -> {:halt, reply, socket}
    end
  end

  defp event(_event, _params, socket), do: {:cont, socket}

  # The answer of a task of a table; one of a table that is gone is dropped.
  defp async({:ash_data_table, id, _kind} = key, result, socket) do
    case named(socket, id) do
      nil ->
        {:halt, socket}

      name ->
        {:noreply, socket} = within(socket, name, &Core.handle_async(key, result, &1))
        {:halt, socket}
    end
  end

  defp async(_key, _result, socket), do: {:cont, socket}

  # What a listener hands over (`AshDataTable.Listener`); a batch of a
  # table that is gone is dropped.
  defp info({:ash_data_table_heard, id, batch}, socket) do
    case named(socket, id) do
      nil -> {:halt, socket}
      name -> {:halt, within(socket, name, &Core.heard(&1, id, batch))}
    end
  end

  defp info(_message, socket), do: {:cont, socket}

  # Every table whose state is in the URL is told it; the LiveView's own
  # `handle_params/3` runs after, where it has one: LiveView calls it on
  # a patch whether the module defines it or not, so for a LiveView without
  # one the hook halts. A table reads only when its own parameters changed.
  defp params(_params, url, socket) do
    socket = told_url(socket, url)

    if function_exported?(socket.view, :handle_params, 3),
      do: {:cont, socket},
      else: {:halt, socket}
  end

  @doc """
  Tells every table whose state is in the URL the URL: what the hook of
  `handle_params/3` does, and `AshDataTable.Live.Page` in the call that
  attaches its table.
  """
  def told_url(socket, url) do
    socket = put_private(socket, :ash_data_table, %{private(socket) | url: url})

    Enum.reduce(private(socket).tables, socket, fn
      {name, %{url?: true, given: given}}, socket ->
        within(socket, name, &Core.tell(&1, Map.put(given, :url, url)))

      _in_memory, socket ->
        socket
    end)
  end
end
