defmodule AshDataTable.Live.Core.Requests do
  @moduledoc false
  # Controlled mode (stage 6 D14): what the table would open, the host
  # draws. A table attached with `controlled: [:confirm, :panel]` does not
  # ask its questions before an action (`:confirm`) and does not draw the
  # panel of a row action, a table action, a create or an action on the
  # selection (`:panel`): it holds the request (`entry.request`, with a
  # `ref` of its own), tells the page (`:requested`), and the host answers
  # with commands (`AshDataTable.confirm_request/3`, `validate_request/4`,
  # `submit_request/4`, `cancel_request/3`), each of which goes the way
  # the person's own answer would: through `AshDataTable.Operation`, with
  # its checks, the veto and the record read again. One request at a time;
  # a new one takes the old one's place, with a `ref` and a `:requested` of
  # its own, and an answer to another `ref` does nothing. A request holds
  # what it was made for (`for`: of a panel its kind, action and row, of a
  # question what Confirm runs), so that a panel that opens in another's
  # place is a new request, not the old one's `ref` over other fields.
  #
  # Only for the table on the page; a nested table and a picker's table
  # draw what they open themselves, as does a map cell's panel: a panel of
  # such a kind ends a request held, and is never handed to the host.

  alias AshDataTable.Event
  alias AshDataTable.Live.Core
  alias AshDataTable.Live.Core.Bulk
  alias AshDataTable.Live.Core.Notify
  alias AshDataTable.Live.Core.Panel

  # the panels a host can draw: those of actions with plain fields
  @kinds [:row, :table, :create, :bulk]

  @doc "Whether the table on the page hands requests of `kind` to the host."
  def controlled?(socket, kind) do
    %{entry: %{path: path}, options: options} = Core.table(socket)
    length(path) == 1 and kind in Map.get(options, :controlled, [])
  end

  @doc """
  Holds the question before an action instead of asking it: `run` is what
  the person's Confirm would send (`{:act, key, name}`, `{:table_run,
  name}`, `{:bulk_run, name, token}`: the token of the selection the
  question names), `action` the action and `key` its row's
  primary key, nil for none.
  """
  def ask(socket, run, action, key) do
    request = %{
      ref: ref(),
      kind: :confirm,
      for: run,
      run: run,
      action: action.name,
      key: key,
      question: action.confirm
    }

    # a panel held for the host is the old request, which this one ends
    socket =
      if match?(%{kind: :panel}, Core.table(socket).entry.request),
        do: Core.put(socket, panel: nil, picker: nil),
        else: socket

    held(socket, request)
  end

  @doc """
  After every callback (`AshDataTable.Live.Core.tidy/1`): a panel that
  opened is held as a request, a new one with a `ref` of its own when it
  is another panel than the one held; one that closed, or opened of a kind
  the table draws itself, ends the panel's request. A question held stays
  until a panel opens after it.
  """
  def follow(socket) do
    %{panel: panel, request: request} = Core.table(socket).entry

    case {controlled?(socket, :panel) && handed(panel), request} do
      {false, _request} -> socket
      {nil, %{kind: :panel}} -> Core.put(socket, request: nil)
      {nil, _confirm_or_none} -> socket
      {made_for, %{kind: :panel, for: made_for}} -> socket
      {made_for, _other} -> held(socket, %{ref: ref(), kind: :panel, for: made_for})
    end
  end

  # What a panel the host draws is made for; nil for none, and for one the
  # table draws itself.
  defp handed(%{kind: kind, action: action, key: key}) when kind in @kinds,
    do: {kind, action.name, key}

  defp handed(_none_or_drawn_by_the_table), do: nil

  defp held(socket, request) do
    socket
    |> Core.put(request: request)
    |> Notify.told({:requested, %{ref: request.ref, kind: request.kind}})
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

    result =
      case run do
        {:act, key, name} -> Panel.act(socket, key, name, true)
        {:table_run, _name} = intent -> Panel.on(intent, socket)
        {:bulk_run, _name, _token} = intent -> Bulk.on(intent, socket)
      end

    case result do
      {:noreply, socket} -> socket
      {:reply, _reply, socket} -> socket
    end
  end

  @doc "An event of the panel, given by the host for the panel it draws."
  def panel(socket, intent) do
    case Panel.on(intent, socket) do
      {:noreply, socket} -> socket
      {:reply, _reply, socket} -> socket
    end
  end

  @doc "What the host may read of the request held, as `AshDataTable.Event` makes it."
  def projection(table), do: Event.request(table.entry)

  defp ref, do: "r" <> Integer.to_string(System.unique_integer([:positive]))
end
