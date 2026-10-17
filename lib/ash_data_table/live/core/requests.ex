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
  # One request at a time per table: a new one takes the old one's place,
  # with a `ref` and a `:requested` of its own, and an answer to another
  # `ref` does nothing. A request holds what it was made for (`for`), so
  # that a panel or picker that opens in another's place is a new request. A
  # question asked while a panel or picker is held ends that one.
  #
  # Every table the table on the page shows is controlled as it is: a
  # nested table holds requests of its own, at once with its parent's
  # (`AshDataTable.requests/1` lists them). An answer finds the table that
  # holds its `ref` (`answer/4`). A request ends, `:request_ended`, when it
  # is answered, given up, taken over by another, or when its table closes
  # (its row collapsed, or the nested table went with its parent's rows).
  # A picker's table opens nothing (`Model`'s chooser), so holds nothing.

  import Phoenix.LiveView, only: [push_event: 3]

  alias AshDataTable.Event
  alias AshDataTable.Live.Core
  alias AshDataTable.Live.Core.Bulk
  alias AshDataTable.Live.Core.Cells
  alias AshDataTable.Live.Core.Files
  alias AshDataTable.Live.Core.Notify
  alias AshDataTable.Live.Core.Panel
  alias AshDataTable.Live.Core.Picker
  alias AshDataTable.Live.Registry
  alias AshDataTable.Present

  @doc "Whether the table the callback works on hands requests of `kind` to the host."
  def controlled?(socket, kind) do
    %{entry: entry, options: options} = Core.table(socket)
    host?(options, entry, kind)
  end

  @doc """
  Whether the host draws what `entry` opens of `kind`: where the table on
  the page was attached `controlled:` so, for every table it shows.
  """
  def host?(options, _entry, kind), do: kind in Map.get(options, :controlled, [])

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

    held(socket, Map.merge(request, %{ref: new_ref(), kind: :confirm}))
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
      {nil, %{kind: kind}} when kind in [:panel, :picker] -> done(socket)
      {nil, _confirm_or_none} -> socket
      {{kind, made_for}, %{kind: kind, for: made_for}} -> socket
      {{kind, made_for}, _other} -> held(socket, %{ref: new_ref(), kind: kind, for: made_for})
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
    |> done()
    |> Core.put(request: request)
    |> Notify.told({:requested, %{ref: request.ref, kind: request.kind}})
  end

  # The request is held no more: the host is told it (`:request_ended`).
  defp done(socket) do
    case Core.table(socket).entry.request do
      %{ref: ref, kind: kind} ->
        socket
        |> Core.put(request: nil)
        |> Notify.told({:request_ended, %{ref: ref, kind: kind}})

      nil ->
        socket
    end
  end

  @doc """
  The table the callback works on closes (`AshDataTable.Live.Registry.close/2`):
  its request ends, and the hook puts back a cell that waited for it.
  """
  def closing(socket), do: socket |> let_go() |> done()

  # The question of a cell that a new request takes the place of, or that
  # is given up: the hook puts the cell back.
  defp let_go(socket) do
    case Core.table(socket).entry.request do
      %{kind: :confirm, for: {kind, key, name}, ref: ref} when kind in [:save, :clear, :refer] ->
        answered(socket, ref, key, name, %{ok: false})

      _other ->
        socket
    end
  end

  @doc """
  Tells the hook what came of a cell whose save waited for the host's
  answer to the request `ref` (`ash_data_table:answered`): saved, or not
  (and why, where the row could not be sent).
  """
  def answered(socket, ref, key, name, reply) do
    id = Core.table(socket).entry.id

    push_event(socket, "ash_data_table:answered", %{
      table: id,
      ref: ref,
      cell: Present.cell_id(id, key, name),
      saved: Map.get(reply, :ok) == true,
      error: Map.get(reply, :error)
    })
  end

  @doc """
  Runs `fun` on the socket for the request `ref`, within the table that
  holds it, where it is of one of `kinds` (`:any` for every kind); else the
  socket as it is: a stale or forged `ref` does nothing.
  """
  def answer(socket, ref, kinds, fun) do
    %{entry: entry, entries: entries} = Core.table(socket)

    with %{id: id, request: %{kind: kind} = request} <-
           Enum.find([entry | Map.values(entries)], &match?(%{request: %{ref: ^ref}}, &1)),
         true <- kinds == :any or kind in kinds do
      Registry.within(socket, id, &fun.(&1, request))
    else
      _stale_or_none -> socket
    end
  end

  @doc """
  The person's Confirm, given by the host: what the question was held for
  runs, as it would have from the hook.
  """
  def confirmed(socket, %{run: run, ref: ref}) do
    socket = done(socket)

    case run do
      {:act, key, name} ->
        reply(Panel.act(socket, key, name, true))

      {:table_run, _name} = intent ->
        reply(Panel.on(intent, socket))

      {:bulk_run, _name, _token} = intent ->
        reply(Bulk.on(intent, socket))

      {:save, key, name, _typed} = intent ->
        {:reply, said, socket} = Cells.write(intent, socket)
        answered(socket, ref, key, name, said)

      {:clear, key, name} = intent ->
        {:reply, said, socket} = Cells.write(intent, socket)
        answered(socket, ref, key, name, said)

      {:refer, key, name, named, arguments} ->
        {_reply, said, socket} = Picker.refer(socket, key, name, named, arguments, true)
        answered(socket, ref, key, name, said)
    end
  end

  @doc "Gives the request up, as Cancel does: nothing runs, a cell is put back."
  def cancelled(socket, %{kind: :panel}), do: panel(socket, :panel_cancel)

  def cancelled(socket, %{kind: :picker}), do: socket |> Core.put(picker: nil) |> done()

  def cancelled(socket, _question), do: socket |> let_go() |> done()

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
  own buttons name it. A name is an atom, as the request's fields have it,
  or a string; a value of a list is the key it is sent under.
  """
  def group(socket, change, path) when change in [:panel_add, :panel_remove] do
    if not (is_list(path) and path != [] and Enum.all?(path, &name?/1)) do
      raise ArgumentError,
            "the path of a group is a list of names, the field's first, got: " <>
              inspect(path, limit: 5)
    end

    panel(socket, {change, Enum.map(path, &to_string/1)})
  end

  defp name?(name) when is_binary(name), do: true
  defp name?(name) when is_atom(name), do: name not in [nil, true, false]
  defp name?(_other), do: false

  @doc """
  What the host may read of the requests held by the tables of `table`,
  the one on the page first, then the nested ones, parents first: each as
  `AshDataTable.Event` makes it, with what a file field's upload is called
  among the LiveView's uploads (`upload`), which the page draws
  `live_file_input/1` of.
  """
  def projections(%{entry: entry, entries: entries}) do
    [entry | entries |> Map.values() |> Enum.sort_by(&{length(&1.path), &1.id})]
    |> Enum.flat_map(&List.wrap(projection(&1)))
  end

  defp projection(entry) do
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

  @doc "The `ref` of the request the table the callback works on holds."
  def ref(socket), do: Core.table(socket).entry.request.ref

  defp new_ref, do: "r" <> Integer.to_string(System.unique_integer([:positive]))
end
