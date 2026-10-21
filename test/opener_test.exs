defmodule AshDataTable.OpenerTest do
  @moduledoc """
  Who draws what a table opens (`AshDataTable.Live.Core.Opener`, stage
  9e): one table of cases, run through the opener's interface for both
  adapters, the table's (`Opener.Table`, `controlled: []`) and the host's
  (`Opener.Host`, `controlled: [:confirm, :panel, :picker]`), each giving
  its own answer: a cell's question, an action's, a run's on the selection,
  a panel, a picker over a panel, a question in a nested table answered
  from the table on the page, a picker's table, a stale `ref` and a `ref`
  of another kind.

  On the socket of a LiveView (`AshDataTable.Test.LiveHost`), in its
  process, with the table's entry made by hand. What the host is told
  (`:requested`, `:request_ended`) comes to that process, which the test
  reads there.
  """
  use ExUnit.Case, async: true

  alias AshDataTable.Live.Core
  alias AshDataTable.Live.Core.Opener
  alias AshDataTable.Live.Core.Opener.Host
  alias AshDataTable.Live.Registry
  alias AshDataTable.Model.Action
  alias AshDataTable.Model.Column
  alias AshDataTable.Panel
  alias AshDataTable.Table

  @adapters [table: [], host: [:confirm, :panel, :picker]]

  @cases [
    "a cell's question",
    "a sensitive cell's question",
    "an action's question",
    "a run's question on the selection",
    "a panel",
    "a question in a panel's place",
    "a picker over a panel",
    "a nested table's question, answered from the table on the page",
    "a picker's table",
    "a stale ref",
    "a ref of another kind"
  ]

  for {adapter, _controlled} <- @adapters, name <- @cases do
    @adapter adapter
    @name name
    test "#{name}: the #{adapter}'s answer" do
      controlled = Keyword.fetch!(@adapters, @adapter)
      # what the host was told and the case did not read is read here: the
      # LiveView has no clause for it
      AshDataTable.Test.LiveHost.run(fn live ->
        check(@name, @adapter, socket(live, controlled))
        told()
      end)
    end
  end

  # the table on the page, "t", with one row ("1"), told what the host
  # draws itself, every event to its host
  defp socket(socket, controlled) do
    socket =
      socket
      |> Phoenix.LiveView.put_private(:ash_data_table, %{current: :table})
      |> Phoenix.Component.assign(table: Table.new())

    %{entry: entry, caller: caller, options: options} = table = socket.assigns.table

    Core.put(socket, %{
      table
      | options: %{options | controlled: controlled},
        caller: %{caller | notify: true},
        entry: %{entry | id: "t", path: ["t"], rows: %{"1" => %{pk: %{id: 1}, rowindex: 2}}}
    })
  end

  defp column(sensitive? \\ false),
    do:
      struct!(Column,
        name: :title,
        kind: :attribute,
        label: "Title",
        cell_type: :text,
        sortable?: true,
        operators: [],
        update_action: :update,
        sensitive?: sensitive?
      )

  defp action(name), do: struct!(Action, name: name, type: :update, label: "#{name}")

  defp panel(name), do: %Panel{kind: :row, for: %{key: "1", action: action(name)}}

  defp request(socket), do: Core.table(socket).entry.request

  defp cell(socket, column, typed),
    do:
      Opener.ask(socket, {:save, "1", "title", typed}, "Change it?", %{
        action: :update,
        key: %{id: 1},
        column: column,
        value: typed
      })

  # what the host was told, in the order told
  defp told do
    receive do
      {:ash_data_table, "t", {event, %{ref: ref, kind: kind}}} -> [{event, ref, kind} | told()]
    after
      0 -> []
    end
  end

  # a panel opened, as `tidy/1` tells it after a callback
  defp opened(socket, panel, picker \\ nil) do
    socket
    |> Core.put(panel: panel, picker: picker)
    |> Opener.opened(:panel, panel)
    |> Opener.opened(:picker, picker)
  end

  defp check("a cell's question", :table, socket) do
    assert {:run, socket} = cell(socket, column(), "new")
    assert request(socket) == nil
    assert told() == []
  end

  defp check("a cell's question", :host, socket) do
    assert {:held, %{held: true, ref: ref}, socket} = cell(socket, column(), "new")

    assert %{kind: :confirm, ref: ^ref, for: {:save, "1", "title"}, key: %{id: 1}} =
             request = request(socket)

    assert %{action: :update, column: :title, value: "new", question: "Change it?"} = request
    assert request.run == {:save, "1", "title", "new"}
    assert told() == [{:requested, ref, :confirm}]

    # Confirm: the request ends, and the intent it was held for runs as
    # answered
    assert {:ok, {:confirmed, {:save, "1", "title", "new"}}, socket} =
             Opener.answer(socket, ref, {[:confirm], &Host.confirmed/2})

    assert request(socket) == nil
    assert told() == [{:request_ended, ref, :confirm}]
  end

  defp check("a sensitive cell's question", :table, socket) do
    assert {:run, _socket} = cell(socket, column(true), "secret")
  end

  defp check("a sensitive cell's question", :host, socket) do
    assert {:held, _reply, socket} = cell(socket, column(true), "secret")
    # the host is not shown what was typed; the table holds it to save it
    assert %{value: nil, run: {:save, "1", "title", "secret"}} = request(socket)
  end

  defp check("an action's question", adapter, socket) do
    asked =
      Opener.ask(socket, {:act, "1", "approve"}, "Sure?", %{action: :approve, key: %{id: 1}})

    case adapter do
      :table ->
        assert {:run, socket} = asked
        assert request(socket) == nil

      :host ->
        assert {:held, %{held: true, ref: ref}, socket} = asked

        assert %{kind: :confirm, ref: ^ref, for: {:act, "1", "approve"}, action: :approve} =
                 request(socket)

        assert %{column: nil, value: nil, key: %{id: 1}} = request(socket)

        # Cancel: nothing runs, the request ends
        assert {:ok, nil, socket} = Opener.answer(socket, ref, {:any, &Host.cancelled/2})
        assert request(socket) == nil
        assert told() == [{:requested, ref, :confirm}, {:request_ended, ref, :confirm}]
    end
  end

  defp check("a run's question on the selection", adapter, socket) do
    question = {:text, :bulk_question, count: 2, action: "Archive"}
    asked = Opener.ask(socket, {:bulk_run, "archive", "token"}, question, %{action: "archive"})

    case adapter do
      :table ->
        assert {:run, _socket} = asked

      :host ->
        # the request holds the token of the selection the question names
        assert {:held, _reply, socket} = asked

        assert %{run: {:bulk_run, "archive", "token"}, question: ^question, key: nil} =
                 request(socket)
    end
  end

  defp check("a panel", adapter, socket) do
    socket = opened(socket, panel(:approve))

    case adapter do
      :table ->
        assert request(socket) == nil
        assert told() == []
        assert Opener.draws?(Core.table(socket).options, :panel)

      :host ->
        assert %{kind: :panel, ref: ref, for: {:row, :approve, "1", nil}} = request(socket)
        refute Opener.draws?(Core.table(socket).options, :panel)

        # the same panel again is the same request; another is a new one
        socket = opened(socket, panel(:approve))
        assert %{ref: ^ref} = request(socket)
        socket = opened(socket, panel(:reject))
        assert %{kind: :panel, ref: other} = request(socket)
        assert other != ref

        # closed: the request ends
        socket = opened(socket, nil)
        assert request(socket) == nil

        assert told() == [
                 {:requested, ref, :panel},
                 {:request_ended, ref, :panel},
                 {:requested, other, :panel},
                 {:request_ended, other, :panel}
               ]
    end
  end

  defp check("a question in a panel's place", adapter, socket) do
    socket = opened(socket, panel(:approve))
    asked = Opener.ask(socket, {:table_run, "greet"}, "Greet?", %{action: :greet})

    case adapter do
      :table ->
        # the table draws both: the panel stays, nothing is held
        assert {:run, socket} = asked
        assert %Panel{} = Core.table(socket).entry.panel

      :host ->
        # the panel held ends, cancelled as the person's Cancel would
        assert {:held, %{ref: ref}, socket} = asked
        assert Core.table(socket).entry.panel == nil
        assert %{kind: :confirm, ref: ^ref, key: nil} = request(socket)

        assert [
                 {:requested, _panel, :panel},
                 {:request_ended, _ended, :panel},
                 {:requested, ^ref, :confirm}
               ] =
                 told()
    end
  end

  defp check("a picker over a panel", adapter, socket) do
    picker = %{for: {:input, :helpers}}
    socket = socket |> opened(panel(:staff)) |> opened(panel(:staff), picker)

    case adapter do
      :table ->
        assert request(socket) == nil
        assert Opener.draws?(Core.table(socket).options, :picker)

      :host ->
        # the picker comes first, the panel waits while it is open
        assert %{kind: :picker, ref: ref, for: {:input, :helpers}} = request(socket)
        socket = opened(socket, panel(:staff), picker)
        assert %{ref: ^ref} = request(socket)
        refute Opener.draws?(Core.table(socket).options, :picker)

        # the picker closes: the panel is held again, a new request
        socket = opened(socket, panel(:staff))
        assert %{kind: :panel, ref: panel_ref} = request(socket)

        assert [
                 {:requested, _first, :panel},
                 {:request_ended, _first_ended, :panel},
                 {:requested, ^ref, :picker},
                 {:request_ended, ^ref, :picker},
                 {:requested, ^panel_ref, :panel}
               ] = told()
    end
  end

  defp check("a nested table's question, answered from the table on the page", adapter, socket) do
    socket =
      socket
      |> Registry.add("t-n", {"t-row-1-n-c-c", nil})
      |> Registry.within("t-n", fn socket ->
        %{entry: entry} = table = Core.table(socket)
        socket = Core.put(socket, %{table | entry: %{entry | path: ["t", "t-n"]}})

        {_run_or_held, _reply_or_socket, socket} =
          held(Opener.ask(socket, {:act, "1", "go"}, "Go?", %{action: :go}))

        socket
      end)

    %{entry: top, entries: %{"t-n" => nested}} = Core.table(socket)
    assert top.request == nil

    case adapter do
      :table ->
        assert nested.request == nil

      :host ->
        assert %{kind: :confirm, ref: ref} = nested.request
        socket = Core.answer(socket, ref, :any, &Host.cancelled/2)
        assert Core.table(socket).entries["t-n"].request == nil
    end
  end

  defp check("a picker's table", adapter, socket) do
    # a picker the host draws has no table of the table's: none is read
    options = Core.table(socket).options

    case adapter do
      :table -> assert Opener.draws?(options, :picker) and Opener.draws?(options, :confirm)
      :host -> refute Opener.draws?(options, :picker) or Opener.draws?(options, :confirm)
    end
  end

  defp check("a stale ref", adapter, socket) do
    {_run_or_held, _reply_or_socket, socket} =
      held(Opener.ask(socket, {:act, "1", "go"}, "Go?", %{action: :go}))

    for kinds <- [:any, [:confirm]] do
      assert Opener.answer(socket, "r0", {kinds, &Host.confirmed/2}) == :none
    end

    assert request(socket) != nil == (adapter == :host)
  end

  defp check("a ref of another kind", adapter, socket) do
    {_run_or_held, _reply_or_socket, socket} =
      held(Opener.ask(socket, {:act, "1", "go"}, "Go?", %{action: :go}))

    ref = request(socket) && request(socket).ref

    for kinds <- [[:panel], [:picker]] do
      assert Opener.answer(socket, ref, {kinds, &Host.confirmed/2}) == :none
    end

    if adapter == :host, do: assert(%{ref: ^ref} = request(socket))
  end

  # `ask/4`'s answer as one shape: what ran on, or what was held
  defp held({:run, socket}), do: {:run, nil, socket}
  defp held({:held, reply, socket}), do: {:held, reply, socket}
end
