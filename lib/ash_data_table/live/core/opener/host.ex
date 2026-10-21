defmodule AshDataTable.Live.Core.Opener.Host do
  @moduledoc false
  # The page draws what the table opens (controlled mode, the adapter of
  # `AshDataTable.Live.Core.Opener` for a kind the table was attached
  # `controlled:` with). A table holds a request in place of what it would
  # draw (`entry.request`, with a `ref` of its own; no other module reads
  # or writes it), tells the page (`:requested`), and the host answers
  # with commands, each of which goes the way the person's own answer
  # would: through `AshDataTable.Operation`, with its checks, the veto and
  # the record read again.
  #
  #   * `:confirm` - every question outside a panel: before a row action, a
  #     table action or an action on the selection, before a save of a cell whose column
  #     asks (`{:save, …}`, `{:clear, …}`, the typed text held here, never
  #     in the projection of a sensitive column; the hook is told the cell
  #     waits) and before the choice for a reference cell (`{:refer, …}`).
  #     `AshDataTable.confirm_request/3` runs it, `cancel_request/3` gives
  #     it up and the hook puts the cell back. A panel's own question (a row
  #     action with inputs, a selection panel's count) is asked with the
  #     panel: by the table, or by the host with `:panel`;
  #   * `:panel` - every action panel: of a row action, a table action, a
  #     create, an action on the selection and a map cell, with files,
  #     groups, unions and chosen records;
  #   * `:picker` - the picker: `AshDataTable.pick_request/4` chooses.
  #
  # The question is no safety check: the
  # hook sends no `table_run`, `bulk_run`, `picked` with `confirmed` or
  # `panel_submit` for what the host holds, but the browser can, and the
  # write then runs without it, through the checks, the veto, the re-read
  # and Ash's policies all the same. Not enforced here, as in the table's
  # own mode.
  #
  # One request at a time per table: a new one takes the old one's place,
  # with a `ref` and a `:requested` of its own, and an answer to another
  # `ref` does nothing. A request holds what it was made for (`for`), so
  # that a panel or picker that opens in another's place is a new request. A
  # question asked while a panel or picker is held ends that one: it is
  # cancelled, as the person's Cancel would (`:panel_cancel`,
  # `:picker_cancel`, run through `AshDataTable.Live.Core.run/2`).
  #
  # Every table the table on the page shows is controlled as it is: a
  # nested table holds requests of its own, at once with its parent's
  # (`AshDataTable.requests/1` lists them). An answer is looked for in
  # every table (the step `{:answer, …}` of `AshDataTable.Live.Core`), and found in the one
  # that holds its `ref`. A request ends, `:request_ended`, when it
  # is answered, given up, taken over by another, or when its table closes
  # (its row collapsed, or the nested table went with its parent's rows).
  # A picker's table opens nothing (`Model`'s chooser), so holds nothing.
  #
  # An answer of the host is the intent it stands for (`confirmed/2`,
  # `cancelled/2`, `group/2`): `answer/3` gives it, and
  # the step `{:answer, …}` of `AshDataTable.Live.Core` runs it within the table that holds
  # the request, through the module of its topic, as it runs a browser's
  # (stage 9d). This module calls no topic.

  @behaviour AshDataTable.Live.Core.Opener

  alias AshDataTable.Event
  alias AshDataTable.Ids
  alias AshDataTable.Live.Core
  alias AshDataTable.Live.Core.Files
  alias AshDataTable.Panel
  alias AshDataTable.Table

  @doc "The host draws every kind this adapter is chosen for: the table, none."
  @impl true
  def draws?(_options, _kind), do: false

  @doc """
  Holds the question before `intent` instead of asking it: `intent` is
  what the person's Confirm would send (`{:act, key, name}`, `{:table_run,
  name}`, `{:bulk_run, name, token}`: the token of the selection the
  question names; a cell's `{:save, key, name, typed}`, `{:clear, key,
  name}`, `{:refer, key, name, named, arguments}`), `about` the action's
  name, the row's primary key (nil for none) and, of a cell, its column
  and what the host is shown of the value (nil for a sensitive column).
  A panel or picker held ends first. The reply holds the `ref`.
  """
  @impl true
  def ask(table, intent, question, about) do
    column = about[:column]

    table =
      table
      |> yield()
      |> held(%{
        for: made_for(intent),
        run: intent,
        action: about.action,
        key: about[:key],
        column: column && column.name,
        value: if(column && not column.sensitive?, do: about[:value]),
        question: question,
        ref: new_ref(),
        kind: :confirm
      })

    {:held, %{held: true, ref: table.entry.request.ref}, table}
  end

  # What a question is made for: a cell's by its row and column, so that
  # another value for the same cell is the same question's place.
  defp made_for(intent) do
    case Tuple.to_list(intent) do
      [kind, key, name | _rest] when kind in [:save, :clear, :refer] -> {kind, key, name}
      _action -> intent
    end
  end

  # A panel or a picker held for the host ends as a question takes its
  # place: cancelled, as the person's Cancel would (the panel's adapter
  # closes the panel, and the picker over it).
  defp yield(table) do
    case table.entry.request do
      %{kind: :panel} -> cancel(table, :panel_cancel)
      %{kind: :picker} -> cancel(table, :picker_cancel)
      _confirm_or_none -> table
    end
  end

  defp cancel(table, intent) do
    {table, nil} = Core.run(intent, table)
    table
  end

  @doc """
  After every callback (`AshDataTable.Live.Core.tidy/1`, through
  `Opener.opened/3`): a panel or a picker that is open is held as a
  request, a new one with a `ref` of its own when it is another than the
  one held. A picker the host draws comes before the panel it was opened
  from: a panel waits while the picker held is open. A question held
  stays until a panel or picker opens after it.
  """
  @impl true
  def opened(table, kind, value) do
    %{request: request, picker: picker} = table.entry
    made_for = made_for(kind, value)

    case request do
      %{kind: ^kind, for: ^made_for} -> table
      %{kind: :picker} when kind == :panel and picker != nil -> table
      _other -> held(table, %{ref: new_ref(), kind: kind, for: made_for})
    end
  end

  # What a panel or picker the host draws is made for.
  defp made_for(:panel, %Panel{} = panel), do: Panel.made_for(panel)
  defp made_for(:picker, %{for: made_for}), do: made_for

  @doc """
  None of `kind` is open: a request of that kind ends (after every
  callback, `Opener.opened/3`); and as the table closes
  (`AshDataTable.Live.Registry.close/2`, every kind) a question too, and
  the hook puts back a cell that waited for it.
  """
  @impl true
  def closed(table, kind) do
    case table.entry.request do
      %{kind: ^kind} -> table |> let_go() |> done()
      _other_or_none -> table
    end
  end

  defp held(table, request) do
    table
    |> let_go()
    |> done()
    |> Table.put(request: request)
    |> Core.notify({:requested, %{ref: request.ref, kind: request.kind}})
  end

  # The request is held no more: the host is told it (`:request_ended`).
  defp done(table) do
    case table.entry.request do
      %{ref: ref, kind: kind} ->
        table
        |> Table.put(request: nil)
        |> Core.notify({:request_ended, %{ref: ref, kind: kind}})

      nil ->
        table
    end
  end

  # The question of a cell that a new request takes the place of, or that
  # is given up: the hook puts the cell back.
  defp let_go(table) do
    case table.entry.request do
      %{kind: :confirm, for: {kind, key, name}, ref: ref} when kind in [:save, :clear, :refer] ->
        answered(table, ref, key, name, %{ok: false})

      _other ->
        table
    end
  end

  @doc """
  Tells the hook what came of a cell whose save waited for the host's
  answer to the request `ref` (`ash_data_table:answered`): saved, or not
  (and why, where the row could not be sent).
  """
  def answered(table, ref, key, name, reply) do
    id = table.entry.id

    Core.effect(
      table,
      {:push, "ash_data_table:answered",
       %{
         table: id,
         ref: ref,
         cell: Ids.cell(Ids.row(id, key), name),
         saved: Map.get(reply, :ok) == true,
         error: Map.get(reply, :error)
       }}
    )
  end

  @doc """
  The host's answer to the request `ref`, where the table the callback
  works on holds it as one of `kinds` (`:any` for every kind): the intent
  `fun` gives of the request (`confirmed/2`, `cancelled/2`, …), nil for
  none. `:none` for a stale or forged `ref`, one another table holds, or
  one of another kind: nothing is done.
  """
  @impl true
  def answer(table, ref, {kinds, fun}) do
    with %{ref: ^ref, kind: kind} = request <- table.entry.request,
         true <- kinds == :any or kind in kinds do
      {intent, table} = fun.(table, request)
      {:ok, intent, table}
    else
      _stale_other_or_none -> :none
    end
  end

  @doc """
  The person's Confirm, given by the host: the request ends, and the intent
  of what the question was held for, as the hook's Confirm would have sent
  it, marked as answered (`{:confirmed, intent}`, which the module of its
  topic runs without asking again).
  """
  def confirmed(table, %{run: run}), do: {{:confirmed, run}, done(table)}

  @doc """
  Gives the request up, as Cancel does: the intent of Cancel for a panel or
  a picker; for a question nothing runs, and a cell is put back.
  """
  def cancelled(table, %{kind: :panel}), do: {:panel_cancel, table}

  def cancelled(table, %{kind: :picker}), do: {:picker_cancel, table}

  def cancelled(table, _question), do: {nil, table |> let_go() |> done()}

  @doc """
  What came of the intent the answer to the request `ref` stood for
  (`reply`, nil for none): the hook is told of a cell whose save waited
  for the host's Confirm (the step `{:answer, …}` of `AshDataTable.Live.Core`).
  """
  def replied(table, ref, {:confirmed, run}, reply)
      when elem(run, 0) in [:save, :clear, :refer] do
    [_kind, key, name | _rest] = Tuple.to_list(run)
    answered(table, ref, key, name, reply || %{})
  end

  def replied(table, _ref, _intent, _reply), do: table

  @doc """
  Adds a value to a field made of groups of the panel the host draws, or
  takes one away: the intent (`{:panel_add, path}`, `{:panel_remove,
  path}`). `path` is the field's name and, inside it, the way to the value,
  as the panel's own buttons name it. A name is an atom, as the request's
  fields have it, or a string; a value of a list is the key it is sent
  under.
  """
  def group(change, path) when change in [:panel_add, :panel_remove] do
    if not (is_list(path) and path != [] and Enum.all?(path, &name?/1)) do
      raise ArgumentError,
            "the path of a group is a list of names, the field's first, got: " <>
              inspect(path, limit: 5)
    end

    {change, Enum.map(path, &to_string/1)}
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

  defp projection(%{request: request} = entry) do
    held = %{
      table: entry.id,
      path: entry.path,
      panel: entry.panel,
      picker: entry.picker,
      key: request && row_key(request, entry)
    }

    case Event.request(request, held) do
      %{kind: :panel} = request ->
        Map.put(request, :uploads, uploads(entry))

      request ->
        request
    end
  end

  # The primary key of the row a request is about: a question names it, a
  # panel and a cell's picker name the row by the key of its DOM id.
  defp row_key(%{kind: :confirm, key: key}, _entry), do: key

  defp row_key(%{kind: :panel}, %{panel: %Panel{} = panel, rows: rows}) do
    case Panel.row(panel) do
      nil -> nil
      key -> get_in(rows, [key, :pk])
    end
  end

  defp row_key(%{kind: :picker}, %{picker: %{for: {:cell, key, _name}}, rows: rows}),
    do: get_in(rows, [key, :pk])

  defp row_key(_request, _entry), do: nil

  # The uploads of the open panel's file fields, by the name of each: the
  # page hands its files to them.
  defp uploads(entry) do
    for input <- Panel.file_inputs(entry.panel),
        into: %{},
        do: {Atom.to_string(input.name), Files.upload_name(entry.id, input)}
  end

  defp new_ref, do: "r" <> Integer.to_string(System.unique_integer([:positive]))
end
