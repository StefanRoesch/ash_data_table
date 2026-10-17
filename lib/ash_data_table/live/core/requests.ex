defmodule AshDataTable.Live.Core.Requests do
  @moduledoc false
  # Controlled mode (stage 6 D14, widened in stage 7c, D17): what the
  # table would open, the host draws. A table attached with `controlled:`
  # holds a request in place of what it would draw (`entry.request`, with a
  # `ref` of its own), tells the page (`:requested`), and the host answers
  # with commands, each of which goes the way the person's own answer
  # would: through `AshDataTable.Operation`, with its checks, the veto and
  # the record read again.
  #
  #   * `:confirm` - every question: before a row action, a table action or
  #     an action on the selection, before a save of a cell whose column
  #     asks (`{:save, …}`, `{:clear, …}`, the typed text held here, never
  #     in the projection of a sensitive column; the hook is told the cell
  #     waits) and before the choice for a reference cell (`{:refer, …}`).
  #     `AshDataTable.confirm_request/3` runs it, `cancel_request/3` gives
  #     it up and the hook puts the cell back;
  #   * `:panel` - every action panel: of a row action, a table action, a
  #     create, an action on the selection and a map cell, with files,
  #     groups, unions and chosen records;
  #   * `:picker` - the picker: `AshDataTable.pick_request/4` chooses.
  #
  # One request at a time: a new one takes the old one's place, with a
  # `ref` and a `:requested` of its own, and an answer to another `ref`
  # does nothing. A request holds what it was made for (`for`), so that a
  # panel or picker that opens in another's place is a new request. A
  # question asked while a panel or picker is held ends that one.
  #
  # Only for the table on the page; a nested table and a picker's table
  # draw what they open themselves.

  import Phoenix.LiveView, only: [push_event: 3]

  alias AshDataTable.Event
  alias AshDataTable.Live.Core
  alias AshDataTable.Live.Core.Bulk
  alias AshDataTable.Live.Core.Cells
  alias AshDataTable.Live.Core.Files
  alias AshDataTable.Live.Core.Notify
  alias AshDataTable.Live.Core.Panel
  alias AshDataTable.Live.Core.Picker

  @doc "Whether the table on the page hands requests of `kind` to the host."
  def controlled?(socket, kind) do
    %{entry: entry, options: options} = Core.table(socket)
    host?(options, entry, kind)
  end

  @doc """
  Whether the host draws what `entry` opens of `kind`: the table on the
  page's, where it was attached `controlled:` so.
  """
  def host?(options, %{path: path}, kind),
    do: length(path) == 1 and kind in Map.get(options, :controlled, [])

  @doc """
  Holds the question before an action instead of asking it: `run` is what
  the person's Confirm would send (`{:act, key, name}`, `{:table_run,
  name}`, `{:bulk_run, name, token}`: the token of the selection the
  question names), `action` the action and `key` its row's
  primary key, nil for none.
  """
  def ask(socket, run, action, key) do
    question(socket, %{
      for: run,
      run: run,
      action: action.name,
      key: key,
      column: nil,
      value: nil,
      question: action.confirm
    })
  end

  @doc """
  Holds the question of a column before a cell's value is given to it:
  `run` is what Confirm runs (`{:save, key, name, typed}`, `{:clear, key,
  name}`, `{:refer, key, name, named, arguments}`), `pk` the row's primary
  key, `value` what the host is shown of it (nil for a sensitive column).
  """
  def ask_cell(socket, run, column, pk, value) do
    [kind, key, name | _rest] = Tuple.to_list(run)

    question(socket, %{
      for: {kind, key, name},
      run: run,
      action: column.update_action,
      key: pk,
      column: column.name,
      value: if(column.sensitive?, do: nil, else: value),
      question: column.confirm
    })
  end

  defp question(socket, request) do
    # a panel or picker held for the host is the old request, which this
    # one ends: it closes
    socket =
      case Core.table(socket).entry.request do
        %{kind: :panel} -> Core.put(socket, panel: nil, picker: nil)
        %{kind: :picker} -> Core.put(socket, picker: nil)
        _confirm_or_none -> socket
      end

    held(socket, Map.merge(request, %{ref: ref(), kind: :confirm}))
  end

  @doc """
  After every callback (`AshDataTable.Live.Core.tidy/1`): a panel or a
  picker that opened is held as a request, a new one with a `ref` of its
  own when it is another than the one held; one that closed ends the
  request. A picker the host draws comes before the panel it was opened
  from. A question held stays until a panel or picker opens after it.
  """
  def follow(socket) do
    %{panel: panel, picker: picker, request: request} = Core.table(socket).entry

    made_for =
      (controlled?(socket, :picker) && picked(picker)) ||
        (controlled?(socket, :panel) && handed(panel)) || nil

    case {made_for, request} do
      {nil, %{kind: kind}} when kind in [:panel, :picker] -> Core.put(socket, request: nil)
      {nil, _confirm_or_none} -> socket
      {{kind, made_for}, %{kind: kind, for: made_for}} -> socket
      {{kind, made_for}, _other} -> held(socket, %{ref: ref(), kind: kind, for: made_for})
    end
  end

  # What a panel the host draws is made for; nil for none.
  defp handed(%{kind: kind, action: action, key: key} = panel),
    do: {:panel, {kind, action.name, key, Map.get(panel, :column)}}

  defp handed(_none), do: nil

  # What a picker the host draws is made for; nil for none.
  defp picked(%{for: made_for}), do: {:picker, made_for}
  defp picked(_none), do: nil

  defp held(socket, request) do
    socket
    |> let_go()
    |> Core.put(request: request)
    |> Notify.told({:requested, %{ref: request.ref, kind: request.kind}})
  end

  # The question of a cell that a new request takes the place of, or that
  # is given up: the hook puts the cell back.
  defp let_go(socket) do
    case Core.table(socket).entry.request do
      %{kind: :confirm, for: {kind, key, name}} when kind in [:save, :clear, :refer] ->
        answered(socket, key, name, %{ok: false})

      _other ->
        socket
    end
  end

  @doc """
  Tells the hook what came of a cell whose save waited for the host
  (`ash_data_table:answered`): saved, or not (and why, where the row could
  not be sent).
  """
  def answered(socket, key, name, reply) do
    id = Core.table(socket).entry.id

    push_event(socket, "ash_data_table:answered", %{
      table: id,
      cell: "#{id}-row-#{key}-c-#{name}",
      saved: Map.get(reply, :ok) == true,
      error: Map.get(reply, :error)
    })
  end

  @doc """
  Runs `fun` on the socket for the request `ref`, where it is the one held
  and of `kind`; else the socket as it is.
  """
  def answer(socket, ref, kind, fun) do
    case Core.table(socket).entry.request do
      %{ref: ^ref, kind: ^kind} = request -> fun.(socket, request)
      _stale_or_none -> socket
    end
  end

  @doc """
  The person's Confirm, given by the host: what the question was held for
  runs, as it would have from the hook.
  """
  def confirmed(socket, %{run: run}) do
    socket = Core.put(socket, request: nil)

    case run do
      {:act, key, name} ->
        reply(Panel.act(socket, key, name, true))

      {:table_run, _name} = intent ->
        reply(Panel.on(intent, socket))

      {:bulk_run, _name, _token} = intent ->
        reply(Bulk.on(intent, socket))

      {:save, key, name, _typed} = intent ->
        {:reply, said, socket} = Cells.write(intent, socket)
        answered(socket, key, name, said)

      {:clear, key, name} = intent ->
        {:reply, said, socket} = Cells.write(intent, socket)
        answered(socket, key, name, said)

      {:refer, key, name, named, arguments} ->
        {_reply, said, socket} = Picker.refer(socket, key, name, named, arguments, true)
        answered(socket, key, name, said)
    end
  end

  @doc "Gives the request up, as Cancel does: nothing runs, a cell is put back."
  def cancelled(socket, %{kind: :panel}), do: panel(socket, :panel_cancel)

  def cancelled(socket, %{kind: :picker}),
    do: socket |> Core.put(picker: nil) |> Core.put(request: nil)

  def cancelled(socket, _question), do: socket |> let_go() |> Core.put(request: nil)

  @doc "An event of the panel, given by the host for the panel it draws."
  def panel(socket, intent), do: reply(Panel.on(intent, socket))

  @doc """
  The host's choice for the picker it draws: one key, several, or nil for
  none. Each key is a claim, read again as the person through the picker's
  read action, as a row the browser names.
  """
  def pick(socket, keys), do: reply(Picker.picked(socket, keys))

  defp reply({:noreply, socket}), do: socket
  defp reply({:reply, _reply, socket}), do: socket

  @doc """
  Adds a value to a field made of groups of the panel the host draws, or
  takes one away (`{:panel_add, path}`, `{:panel_remove, path}`): `path`
  is the field's name and, inside it, the way to the value, as the panel's
  own buttons name it.
  """
  def group(socket, change, path) when change in [:panel_add, :panel_remove] do
    if not (is_list(path) and path != [] and Enum.all?(path, &is_binary/1)) do
      raise ArgumentError,
            "the path of a group is a list of names, the field's first, got: " <>
              inspect(path, limit: 5)
    end

    panel(socket, {change, path})
  end

  @doc """
  What the host may read of the request held, as `AshDataTable.Event`
  makes it, with what a file field's upload is called among the LiveView's
  uploads (`upload`), which the page draws `live_file_input/1` of.
  """
  def projection(%{entry: entry}) do
    case Event.request(entry) do
      %{kind: :panel, fields: fields} = request ->
        %{request | fields: Enum.map(fields, &upload(&1, entry))}

      request ->
        request
    end
  end

  defp upload(%{editor: :file} = field, entry),
    do: Map.put(field, :upload, Files.upload_name(entry.id, field))

  defp upload(field, _entry), do: field

  defp ref, do: "r" <> Integer.to_string(System.unique_integer([:positive]))
end
