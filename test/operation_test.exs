defmodule AshDataTable.OperationTest do
  @moduledoc """
  `AshDataTable.Operation`: every write runs the table's checks of what the
  browser named, then the veto, then the re-read as the person, then the
  action. A claim the model does not allow is refused before anything else
  is asked; a halt writes nothing; a record gone since the page was read is
  not written.
  """
  use ExUnit.Case, async: false

  alias AshDataTable.Model
  alias AshDataTable.Operation
  alias AshDataTable.Operation.{Failure, Input, Outcome}
  alias AshDataTable.Test.Guarded
  alias AshDataTable.Test.Sensitive, as: Vault
  alias AshDataTable.Test.TableActing

  @admin [actor: %{id: 1, role: :admin}]

  defp input(model, intent, rows, more \\ []) do
    struct!(
      %Input{
        intent: intent,
        model: model,
        state: %AshDataTable.State{},
        opts: @admin,
        rows: rows
      },
      more
    )
  end

  # the rows of a page, by the key in their DOM id
  defp rows(records), do: Map.new(records, &{&1.id, %{pk: %{id: &1.id}, rowindex: 3}})

  # a veto that says when it is asked
  defp veto(answer) do
    test = self()

    fn ->
      send(test, :veto_asked)
      answer
    end
  end

  describe "saving a cell" do
    setup do
      on_exit(fn -> AshDataTable.Test.Ets.stop(Guarded) end)
      record = Ash.Seed.seed!(Guarded, %{title: "Old", owner_id: 1})
      %{model: Model.build(Guarded), record: record}
    end

    defp title(record), do: Ash.get!(Guarded, record.id, authorize?: false).title

    test "refuses what the model does not allow, before the veto is asked, and writes nothing",
         %{model: model, record: record} do
      rows = rows([record])

      for intent <- [
            # no such column, and one that is not edited
            {:save, record.id, "nothing", "New"},
            {:save, record.id, "secret_shouted", "New"},
            # a row that is not on the page
            {:save, Ash.UUID.generate(), "title", "New"},
            # a list where a text is typed
            {:save, record.id, "title", ["New"]}
          ] do
        assert Operation.save(input(model, intent, rows, veto: veto(:cont))) == :refused
      end

      refute_received :veto_asked
      assert title(record) == "Old"
    end

    test "is halted by the veto, which is asked once the checks have passed, and writes nothing",
         %{model: model, record: record} do
      intent = {:save, record.id, "title", "New"}
      halt = {:text, :action_not_allowed, []}

      assert Operation.save(input(model, intent, rows([record]), veto: veto({:halt, halt}))) ==
               {:halted, halt}

      assert_received :veto_asked
      assert title(record) == "Old"
    end

    test "gives the record as the action returned it", %{model: model, record: record} do
      intent = {:save, record.id, "title", "New"}

      assert {:ok, %Outcome{record: %Guarded{title: "New"}, gone?: false}} =
               Operation.save(input(model, intent, rows([record])))

      assert title(record) == "New"
    end

    test "reads the record again first: one gone since the page was read is not written",
         %{model: model, record: record} do
      Ash.destroy!(record, action: :destroy, authorize?: false)
      intent = {:save, record.id, "title", "New"}

      assert Operation.save(input(model, intent, rows([record]))) ==
               {:error, %Failure{record: nil, message: {:text, :record_gone, []}}}

      assert Ash.read!(Guarded, authorize?: false) == []
    end

    test "gives the record as it is, with the action's message, where the action refuses",
         %{model: model, record: record} do
      intent = {:save, record.id, "title", "New"}
      member = input(model, intent, rows([record]), opts: [actor: %{id: 2, role: :member}])

      assert {:error, %Failure{record: %Guarded{title: "Old"}, message: message}} =
               Operation.save(member)

      assert message == {:text, :edit_not_allowed, []}
      assert title(record) == "Old"
    end
  end

  describe "revealing a sensitive cell" do
    setup do
      on_exit(fn -> AshDataTable.Test.Ets.stop(Vault) end)
      record = Ash.Seed.seed!(Vault, %{name: "Main", token: "tok-123", pin: 4711})
      %{model: Model.build(Vault), record: record}
    end

    test "gives the value of the record as it is read now", %{model: model, record: record} do
      Ash.update!(record, %{token: "tok-456"}, authorize?: false)
      intent = {:reveal, record.id, "token"}

      assert Operation.reveal(input(model, intent, rows([record]))) == {:ok, "tok-456"}
    end

    test "gives nothing of a cell that is not a sensitive one of a row of the page", %{
      model: model,
      record: record
    } do
      rows = rows([record])

      assert Operation.reveal(input(model, {:reveal, record.id, "name"}, rows)) == :refused

      assert Operation.reveal(input(model, {:reveal, Ash.UUID.generate(), "token"}, rows)) ==
               :refused
    end

    test "gives nothing Ash hides from the person, and nothing of a record that is gone", %{
      model: model,
      record: record
    } do
      rows = rows([record])
      member = [opts: [actor: %{role: :member}]]

      assert Operation.reveal(input(model, {:reveal, record.id, "pin"}, rows, member)) == :hidden

      Ash.destroy!(record, authorize?: false)

      assert Operation.reveal(input(model, {:reveal, record.id, "token"}, rows)) ==
               {:error, {:text, :record_gone, []}}
    end
  end

  describe "running an action" do
    setup do
      on_exit(fn -> AshDataTable.Test.Ets.stop(TableActing) end)
      record = Ash.create!(TableActing, %{title: "One", done: false}, authorize?: false)
      %{model: Model.build(TableActing), record: record}
    end

    defp titles,
      do: TableActing |> Ash.read!(authorize?: false) |> Enum.map(& &1.title) |> Enum.sort()

    test "runs a row action on a row of the page, and nothing on a row that is not",
         %{model: model, record: record} do
      assert {:ok, %Outcome{record: nil, value: nil}} =
               Operation.run(input(model, {:act, record.id, "copy"}, rows([record])))

      assert titles() == ["Copy of One", "One"]

      assert Operation.run(input(model, {:act, Ash.UUID.generate(), "copy"}, rows([record]))) ==
               :refused

      assert titles() == ["Copy of One", "One"]
    end

    test "runs a table action only once the table has read, and one with a question once it is answered",
         %{model: model} do
      offered = %{table: model.table_actions, bulk: []}
      count = {:table_run, "count"}

      assert Operation.run(input(model, count, %{}, offered: offered)) == :refused

      assert {:ok, %Outcome{value: 1}} =
               Operation.run(input(model, count, %{}, offered: offered, read?: true))

      assert Operation.run(input(model, {:table_act, "nothing_like_it"}, %{}, read?: true)) ==
               :refused
    end

    test "on a selection, hands the run back to be started, and it reads each row again",
         %{model: model, record: record} do
      gone = Ash.UUID.generate()
      offered = %{table: [], bulk: Model.bulk_actions(model)}
      intent = {:bulk_run, "copy", {:rows, [record.id, gone]}}

      assert {:start, run, %{}} = Operation.bulk(input(model, intent, %{}, offered: offered))
      assert titles() == ["One"]

      assert %{done: 1, failed: [%{id: ^gone}]} = run.()
      assert titles() == ["Copy of One", "One"]

      # an action that is not offered on a selection
      refused = input(model, {:bulk_run, "count", {:rows, [record.id]}}, %{}, offered: offered)
      assert Operation.bulk(refused) == :refused
    end
  end
end
