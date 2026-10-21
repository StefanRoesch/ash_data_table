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

  Over the table, with no socket (stage 9g), its entry made by hand. What
  the host is told (`:requested`, `:request_ended`) is among the effects
  the table gathers (`{:tell, top, message}`), which the test reads there,
  in their order.
  """
  use ExUnit.Case, async: true

  alias AshDataTable.Live.Core
  alias AshDataTable.Live.Core.Nesting
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
      check(@name, @adapter, table(Keyword.fetch!(@adapters, @adapter)))
    end
  end

  # the table on the page, "t", with one row ("1"), told what the host
  # draws itself, every event to its host
  defp table(controlled) do
    %{entry: entry, caller: caller, options: options} = table = Table.new()

    %{
      table
      | options: %{options | draws: Opener.draws!(controlled: controlled)},
        caller: %{caller | notify: true},
        entry: %{entry | id: "t", path: ["t"], rows: %{"1" => %{pk: %{id: 1}, rowindex: 2}}}
    }
  end

  test "what the host draws itself is the opener's to say, of attach/4's option" do
    assert Opener.option() == [controlled: []]
    assert Opener.draws!(controlled: []) == %{confirm: true, panel: true, picker: true}
    assert Opener.draws!(controlled: [:panel]) == %{confirm: true, panel: false, picker: true}
    assert_raise ArgumentError, ~r/`controlled`/, fn -> Opener.draws!(controlled: [:nested]) end
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

  defp request(table), do: table.entry.request

  defp cell(table, column, typed),
    do:
      Opener.ask(table, {:save, "1", "title", typed}, "Change it?", %{
        action: :update,
        key: %{id: 1},
        column: column,
        value: typed
      })

  # what the host was told so far, in the order told
  defp told(table) do
    for {:tell, "t", {event, %{ref: ref, kind: kind}}} <- Enum.reverse(table.effects),
        do: {event, ref, kind}
  end

  # a panel opened, as the step `:tidy` tells it after a callback
  defp opened(table, panel, picker \\ nil) do
    table
    |> Table.put(panel: panel, picker: picker)
    |> Opener.opened(:panel, panel)
    |> Opener.opened(:picker, picker)
  end

  defp check("a cell's question", :table, table) do
    assert {:run, table} = cell(table, column(), "new")
    assert request(table) == nil
    assert told(table) == []
  end

  defp check("a cell's question", :host, table) do
    assert {:held, %{held: true, ref: ref}, table} = cell(table, column(), "new")

    assert %{kind: :confirm, ref: ^ref, for: {:save, "1", "title"}, key: %{id: 1}} =
             request = request(table)

    assert %{action: :update, column: :title, value: "new", question: "Change it?"} = request
    assert request.run == {:save, "1", "title", "new"}
    assert told(table) == [{:requested, ref, :confirm}]

    # Confirm: the request ends, and the intent it was held for runs as
    # answered
    assert {:ok, {:confirmed, {:save, "1", "title", "new"}}, table} =
             Opener.answer(table, ref, {[:confirm], &Host.confirmed/2})

    assert request(table) == nil
    assert told(table) == [{:requested, ref, :confirm}, {:request_ended, ref, :confirm}]
  end

  defp check("a sensitive cell's question", :table, table) do
    assert {:run, _table} = cell(table, column(true), "secret")
  end

  defp check("a sensitive cell's question", :host, table) do
    assert {:held, _reply, table} = cell(table, column(true), "secret")
    # the host is not shown what was typed; the table holds it to save it
    assert %{value: nil, run: {:save, "1", "title", "secret"}} = request(table)
  end

  defp check("an action's question", adapter, table) do
    asked =
      Opener.ask(table, {:act, "1", "approve"}, "Sure?", %{action: :approve, key: %{id: 1}})

    case adapter do
      :table ->
        assert {:run, table} = asked
        assert request(table) == nil

      :host ->
        assert {:held, %{held: true, ref: ref}, table} = asked

        assert %{kind: :confirm, ref: ^ref, for: {:act, "1", "approve"}, action: :approve} =
                 request(table)

        assert %{column: nil, value: nil, key: %{id: 1}} = request(table)

        # Cancel: nothing runs, the request ends
        assert {:ok, nil, table} = Opener.answer(table, ref, {:any, &Host.cancelled/2})
        assert request(table) == nil
        assert told(table) == [{:requested, ref, :confirm}, {:request_ended, ref, :confirm}]
    end
  end

  defp check("a run's question on the selection", adapter, table) do
    question = {:text, :bulk_question, count: 2, action: "Archive"}
    asked = Opener.ask(table, {:bulk_run, "archive", "token"}, question, %{action: "archive"})

    case adapter do
      :table ->
        assert {:run, _table} = asked

      :host ->
        # the request holds the token of the selection the question names
        assert {:held, _reply, table} = asked

        assert %{run: {:bulk_run, "archive", "token"}, question: ^question, key: nil} =
                 request(table)
    end
  end

  defp check("a panel", adapter, table) do
    table = opened(table, panel(:approve))

    case adapter do
      :table ->
        assert request(table) == nil
        assert told(table) == []
        assert Opener.draws?(table.options, :panel)

      :host ->
        assert %{kind: :panel, ref: ref, for: {:row, :approve, "1", nil}} = request(table)
        refute Opener.draws?(table.options, :panel)

        # the same panel again is the same request; another is a new one
        table = opened(table, panel(:approve))
        assert %{ref: ^ref} = request(table)
        table = opened(table, panel(:reject))
        assert %{kind: :panel, ref: other} = request(table)
        assert other != ref

        # closed: the request ends
        table = opened(table, nil)
        assert request(table) == nil

        assert told(table) == [
                 {:requested, ref, :panel},
                 {:request_ended, ref, :panel},
                 {:requested, other, :panel},
                 {:request_ended, other, :panel}
               ]
    end
  end

  defp check("a question in a panel's place", adapter, table) do
    table = opened(table, panel(:approve))
    asked = Opener.ask(table, {:table_run, "greet"}, "Greet?", %{action: :greet})

    case adapter do
      :table ->
        # the table draws both: the panel stays, nothing is held
        assert {:run, table} = asked
        assert %Panel{} = table.entry.panel

      :host ->
        # the panel held ends, cancelled as the person's Cancel would
        assert {:held, %{ref: ref}, table} = asked
        assert table.entry.panel == nil
        assert %{kind: :confirm, ref: ^ref, key: nil} = request(table)

        assert [
                 {:requested, _panel, :panel},
                 {:request_ended, _ended, :panel},
                 {:requested, ^ref, :confirm}
               ] = told(table)
    end
  end

  defp check("a picker over a panel", adapter, table) do
    picker = %{for: {:input, :helpers}}
    table = table |> opened(panel(:staff)) |> opened(panel(:staff), picker)

    case adapter do
      :table ->
        assert request(table) == nil
        assert Opener.draws?(table.options, :picker)

      :host ->
        # the picker comes first, the panel waits while it is open
        assert %{kind: :picker, ref: ref, for: {:input, :helpers}} = request(table)
        table = opened(table, panel(:staff), picker)
        assert %{ref: ^ref} = request(table)
        refute Opener.draws?(table.options, :picker)

        # the picker closes: the panel is held again, a new request
        table = opened(table, panel(:staff))
        assert %{kind: :panel, ref: panel_ref} = request(table)

        assert [
                 {:requested, _first, :panel},
                 {:request_ended, _first_ended, :panel},
                 {:requested, ^ref, :picker},
                 {:request_ended, ^ref, :picker},
                 {:requested, ^panel_ref, :panel}
               ] = told(table)
    end
  end

  defp check("a nested table's question, answered from the table on the page", adapter, table) do
    table =
      table
      |> Registry.add("t-n", {"t-row-1-n-c-c", nil})
      |> Registry.within("t-n", fn table ->
        table = Table.put(table, path: ["t", "t-n"])

        {_run_or_held, _reply_or_table, table} =
          held(Opener.ask(table, {:act, "1", "go"}, "Go?", %{action: :go}))

        table
      end)

    %{entry: top, entries: %{"t-n" => nested}} = table
    assert top.request == nil

    case adapter do
      :table ->
        # nothing is held, so no answer finds anything: the tables are as
        # they were
        assert nested.request == nil
        assert {^table, nil} = Core.run({:answer, "r0", :any, &Host.cancelled/2}, table)
        assert told(table) == []

      :host ->
        assert %{kind: :confirm, ref: ref} = nested.request
        {table, nil} = Core.run({:answer, ref, :any, &Host.cancelled/2}, table)
        assert table.entries["t-n"].request == nil
    end
  end

  defp check("a picker's table", adapter, table) do
    # a picker the host draws has no table of the table's: none is read
    options = table.options

    case adapter do
      :table ->
        assert Opener.draws?(options, :picker) and Opener.draws?(options, :confirm)

      :host ->
        refute Opener.draws?(options, :picker) or Opener.draws?(options, :confirm)
        table = Table.put(table, picker: %{for: {:cell, "1", :owner}})
        assert Nesting.children(table, "t") == []
    end
  end

  defp check("a stale ref", adapter, table) do
    {_run_or_held, _reply_or_table, table} =
      held(Opener.ask(table, {:act, "1", "go"}, "Go?", %{action: :go}))

    for kinds <- [:any, [:confirm]] do
      assert Opener.answer(table, "r0", {kinds, &Host.confirmed/2}) == :none
    end

    assert request(table) != nil == (adapter == :host)
  end

  defp check("a ref of another kind", adapter, table) do
    {_run_or_held, _reply_or_table, table} =
      held(Opener.ask(table, {:act, "1", "go"}, "Go?", %{action: :go}))

    ref = request(table) && request(table).ref

    for kinds <- [[:panel], [:picker]] do
      assert Opener.answer(table, ref, {kinds, &Host.confirmed/2}) == :none
    end

    if adapter == :host, do: assert(%{ref: ^ref} = request(table))
  end

  # `ask/4`'s answer as one shape: what ran on, or what was held
  defp held({:run, table}), do: {:run, nil, table}
  defp held({:held, reply, table}), do: {:held, reply, table}
end
