defmodule AshDataTable.StepTest do
  @moduledoc """
  The step of the live core over the table (`AshDataTable.Live.Core.step/3`,
  stage 9g, the partial form of question 30 b): an intent of a topic that
  needs no stream, no async task and no upload gives the table as it is
  then, the effects the socket is to be told (`{:push, …}`, `{:tell, …}`,
  `{:patch, …}`, `:read`) and the reply to the hook, with no socket and
  no LiveView. Per topic: what is selected, sort, filters, page size and
  the URL, the argument line, a run's result seen, "Read again", the
  page's "Open", the panel's Cancel and a button of a panel that is no
  longer open, the picker's Cancel.

  The table is made by hand (`AshDataTable.Table.put/2`), its model built
  for the resource as for everybody (`AshDataTable.Model.build/2`); a
  step that reads nothing reads no record.
  """
  use ExUnit.Case, async: true

  alias AshDataTable.Ids
  alias AshDataTable.Live.Core
  alias AshDataTable.Model
  alias AshDataTable.State
  alias AshDataTable.Table
  alias AshDataTable.Test.Arguing.Price
  alias AshDataTable.Test.Resource

  @context %{page_assigns: %{}, uploads: %{}}

  # the table on the page, "t", of `resource`, its state the default
  defp table(resource \\ Resource, fields \\ []) do
    model = Model.build(resource)

    Table.new()
    |> Table.put(id: "t", path: ["t"], resource: resource, model: model, state: %State{})
    |> Table.put(fields)
  end

  describe "what is selected (Selection)" do
    test "the rows the hook names are selected, and the host is told it changed" do
      key = Ash.UUID.generate()
      {table, effects, nil} = Core.step(table(), {:select, {:rows, [key, key]}}, @context)

      assert %{selected: [^key], all?: false} = table.entry
      # the hook said it: it is not told back
      assert [{:tell, "t", {:selection_changed, %{selected: [_], all?: false, table: "t"}}}] =
               effects

      # the same selection again tells nothing
      assert {_table, [], nil} = Core.step(table, {:select, {:rows, [key]}}, @context)
    end

    test "every record that matches" do
      {table, effects, nil} = Core.step(table(), {:select, :all}, @context)

      assert %{selected: [], all?: true} = table.entry
      assert [{:tell, "t", {:selection_changed, %{all?: true}}}] = effects
    end

    test "a picker's table tells the host nothing" do
      table = table(Resource, choose: :one)
      assert {_table, [], nil} = Core.step(table, {:select, {:rows, ["k"]}}, @context)
    end

    test "a selection made under other filters is given up, and the hook told" do
      {table, _effects, nil} = Core.step(table(), {:select, {:rows, ["k"]}}, @context)
      {table, []} = Core.Selection.scoped(table)
      table = Table.put(table, state: %State{filters: %{name: {:eq, "x"}}})

      assert {table, [{:push, "ash_data_table:select", %{table: "t", rows: []}}, {:tell, _, _}]} =
               Core.Selection.scoped(table)

      assert table.entry.selected == []
    end
  end

  describe "sort, filters and page size (Reading, Url)" do
    test "a table that keeps its state takes the new sort and reads for it" do
      {table, effects, nil} = Core.step(table(), {:sort, "name"}, @context)

      assert table.entry.state.sort
      assert effects == [:read]
    end

    test "a table whose state is in the URL is patched, its state as it was" do
      before = table(Resource, url: "/tasks?other=1")
      {table, effects, nil} = Core.step(before, {:sort, "name"}, @context)

      assert table.entry.state == before.entry.state
      assert [{:patch, "/tasks?" <> query}] = effects
      assert %{"other" => "1", "t" => %{"sort" => _}} = Plug.Conn.Query.decode(query)
    end

    test "a page size the table does not offer changes nothing" do
      before = table()
      assert {^before, [], nil} = Core.step(before, {:page_size, "7"}, @context)
    end

    test "clearing the filters of a table that has none reads nothing" do
      before = table(Resource, rejected: %{name: "x"})
      {table, effects, nil} = Core.step(before, :clear_filters, @context)

      assert table.entry.rejected == %{}
      assert table.entry.pending == %{controls: %{}, among: []}
      assert effects == []
    end

    test "a filter that changes the state is announced and read for" do
      {table, effects, nil} =
        Core.step(table(), {:filter, %{"name" => %{"o" => "contains", "v" => "a"}}}, @context)

      assert table.entry.state.filters != %{}
      assert table.entry.announce?
      assert effects == [:read]
    end
  end

  describe "the argument line (Url)" do
    test "a value is added to an argument given value by value, and focus goes into it" do
      {table, effects, nil} = Core.step(table(Price), {:argument_add, "names"}, @context)

      assert table.entry.lines == %{{nil, :names} => [""]}

      assert effects == [
               {:push, "ash_data_table:focus",
                %{table: "t", cell: Ids.argument_value(Ids.argument("t", "names"), 0)}}
             ]
    end

    test "an argument that is not given value by value gets nothing" do
      before = table(Price)
      assert {^before, [], nil} = Core.step(before, {:argument_add, "term"}, @context)
    end
  end

  describe "the others" do
    test "a run's result, seen, is said no longer (Bulk)" do
      table = table(Resource, result: %{summary: {:text, :bulk_done, []}, failures: []})
      assert {%{entry: %{result: nil}}, [], nil} = Core.step(table, :bulk_seen, @context)
    end

    test "Read again reads the page again as it is (Updates)" do
      {table, effects, nil} = Core.step(table(), :read_again, @context)

      assert table.entry.read == :again
      assert effects == [:read]
    end

    test "the page's Open tells the host the row, whatever notify says (Panel)" do
      table =
        table(Resource, open_label: "Open", notify: [], rows: %{"1" => %{pk: %{id: 1}}})

      assert {^table, [{:tell, "t", {:row_opened, %{key: %{id: 1}, table: "t"}}}], nil} =
               Core.step(table, {:open, "1"}, @context)

      # a key that names no row of the page gets nothing
      assert {^table, [], nil} = Core.step(table, {:open, "2"}, @context)
    end

    test "Cancel closes the panel and its picker (Panel)" do
      table = table(Resource, panel: %{kind: :row}, picker: %{name: :owner})

      assert {%{entry: %{panel: nil, picker: nil}}, [], nil} =
               Core.step(table, :panel_cancel, @context)
    end

    test "a button of a panel that is no longer open does nothing (Panel)" do
      before = table()
      assert {^before, [], nil} = Core.step(before, {:panel_add, ["tags"]}, @context)
      assert {^before, [], nil} = Core.step(before, {:panel_clear, "secret"}, @context)
      assert {^before, [], nil} = Core.step(before, {:panel_validate, %{}}, @context)
      assert {^before, [], nil} = Core.step(before, {:pick_input, "owner"}, @context)
    end

    test "Cancel closes the picker, the panel stays (Picker)" do
      table = table(Resource, panel: %{kind: :row}, picker: %{name: :owner})

      assert {%{entry: %{panel: %{kind: :row}, picker: nil}}, [], nil} =
               Core.step(table, :picker_cancel, @context)
    end
  end
end
