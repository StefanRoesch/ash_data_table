defmodule AshDataTable.PageValuesTest do
  @moduledoc """
  What a page gives a table (stage 6, groups P and Q of its note), below
  the live layer: the `context` of every call to Ash, the private
  arguments an action declares, the arguments a `page_argument` names, and
  the veto, asked after the checks and before anything is read again.

  The resources tell the test process what each call was given
  (`AshDataTable.Test.Given`).
  """
  use ExUnit.Case, async: false

  alias AshDataTable.Act
  alias AshDataTable.Bulk
  alias AshDataTable.Edit
  alias AshDataTable.Model
  alias AshDataTable.Operation
  alias AshDataTable.Operation.Input
  alias AshDataTable.Operation.Outcome
  alias AshDataTable.Pick
  alias AshDataTable.Query
  alias AshDataTable.Request
  alias AshDataTable.State
  alias AshDataTable.Test.Given.Note
  alias AshDataTable.Test.Given.Remark
  alias AshDataTable.Test.Submitting

  @page %{
    context: %{shared: %{project: 7}},
    # `shown` is a public argument of the read action, `other` no action's
    private_arguments: %{secret: "s3", shown: "no", other: 1},
    page_arguments: %{to: "ann", by: "bob"}
  }

  @opts [authorize?: false, page_values: @page]

  setup do
    on_exit(fn -> AshDataTable.Test.Ets.stop([Note, Remark]) end)
    note = Ash.Seed.seed!(Note, %{title: "One"})
    other = Ash.Seed.seed!(Note, %{title: "Two"})
    remark = Ash.Seed.seed!(Remark, %{body: "Hm", note_id: note.id})
    %{model: Model.build(Note), note: note, other: other, remark: remark}
  end

  defp action(model, name),
    do: Enum.find(model.actions ++ model.table_actions, &(&1.name == name))

  defp column(model, name), do: Enum.find(model.columns, &(&1.name == name))

  # what the reads of `resource` were given, in their order. Ash reads once
  # more by itself to count a page, as a load (`query_for: :load`), and
  # gives that read nothing of the call's
  defp reads(resource) do
    receive do
      {:read, ^resource, _action, %{query_for: :load}, _secret, _shown} ->
        reads(resource)

      {:read, ^resource, _action, context, secret, shown} ->
        [{context, secret, shown} | reads(resource)]
    after
      0 -> []
    end
  end

  defp writes do
    receive do
      {:write, resource, action, context, arguments} ->
        [{resource, action, context, arguments} | writes()]
    after
      0 -> []
    end
  end

  describe "the context and the private arguments" do
    test "a read is given the page's context, and the private arguments its action declares only",
         %{model: model} do
      assert {:ok, %{records: [_, _]}} = Query.read(model, %State{}, @opts)

      assert [{context, "s3", nil} | _] = reads(Note)
      assert context.shared == %{project: 7}
      refute Map.has_key?(context, :ash_data_table_origin)
    end

    test "the page cannot set the table's own key: it is the listener's, or not there",
         %{model: model} do
      page = put_in(@page, [:context, :ash_data_table_origin], :faked)

      Query.read(model, %State{}, authorize?: false, page_values: page, origin: self())
      assert [{%{ash_data_table_origin: origin, shared: _}, _, _} | _] = reads(Note)
      assert origin == self()

      Query.read(model, %State{}, authorize?: false, page_values: page)
      assert [{context, _, _} | _] = reads(Note)
      refute Map.has_key?(context, :ash_data_table_origin)
    end

    test "a nested table's read, and the read of the row it belongs to", %{
      model: model,
      note: note
    } do
      via = Model.relationship(model, "remarks")
      nested = Model.build(Remark, table: via.table, via: via)

      assert {:ok, %{records: [_]}} =
               Query.read_related(nested, %State{}, %{id: note.id}, @opts)

      assert [{parent, "s3", nil} | _] = reads(Note)
      assert parent.shared == %{project: 7}
      assert [{remark, "s3", nil} | _] = reads(Remark)
      assert remark.shared == %{project: 7}
    end

    test "a picker's read of the record chosen", %{note: note} do
      reference = Enum.find(Model.build(Remark).columns, &(&1.name == :note)).reference

      assert {:ok, %Note{}} = Pick.chosen(reference, note.id, @opts)
      assert [{context, "s3", nil} | _] = reads(Note)
      assert context.shared == %{project: 7}
    end

    test "a save reads the record again with them, and its action is given them", %{
      model: model,
      note: note
    } do
      assert {:ok, %Note{title: "New"}} =
               Edit.save(model, column(model, :title), %{id: note.id}, "New", @opts)

      assert [{context, "s3", nil} | _] = reads(Note)
      assert context.shared == %{project: 7}

      assert [{Note, :update, context, arguments}] = writes()
      assert context.shared == %{project: 7}
      assert arguments == %{secret: "s3"}
    end

    test "a create", %{model: model} do
      assert {:ok, %Outcome{record: %Note{title: "Three"}}} =
               Submitting.create(model, model.create, %{"title" => "Three"}, @opts)

      assert [{Note, :create, context, %{secret: "s3"}}] = writes()
      assert context.shared == %{project: 7}
    end

    test "a summary keeps the page's context, and not the table's own key", %{model: model} do
      assert {:ok, %{score: {:ok, 2}}} =
               Query.summaries(model, %State{}, nil, [origin: self()] ++ @opts)

      assert [{context, "s3", nil} | _] = reads(Note)
      assert context.shared == %{project: 7}
      refute Map.has_key?(context, :ash_data_table_origin)
    end

    test "without page values a call is given nothing of the page", %{model: model} do
      Query.read(model, %State{}, authorize?: false)
      assert [{context, nil, nil} | _] = reads(Note)
      refute Map.has_key?(context, :shared)
    end
  end

  describe "page arguments" do
    test "are no inputs of the action: the panel never asks for them", %{model: model} do
      assert %{inputs: [], panel?: false, page_arguments: [:to]} = action(model, :assign)
      assert %{inputs: [], panel?: false, page_arguments: [:by]} = action(model, :tally)
    end

    test "a row action is given the page's value, and nothing from the browser replaces it", %{
      model: model,
      note: note
    } do
      assert {:ok, %Note{assignee: "ann"}} =
               Act.run(model, action(model, :assign), %{id: note.id}, %{}, @opts)

      assert [{Note, :assign, context, %{to: "ann", secret: "s3"}}] = writes()
      assert context.shared == %{project: 7}
    end

    test "a table action", %{model: model} do
      assert {:done, 1} = Act.run_generic(model, action(model, :tally), %{"by" => "eve"}, @opts)
      assert [{Note, :tally, context, %{by: "bob", secret: "s3"}}] = writes()
      assert context.shared == %{project: 7}
    end

    test "a run on a selection gives every record the same value", %{
      model: model,
      note: note,
      other: other
    } do
      outcome =
        Bulk.run(
          model,
          action(model, :assign),
          {:rows, [note.id, other.id]},
          %{},
          [state: %State{}] ++ @opts
        )

      assert outcome.done == 2

      assert [{Note, :assign, _, %{to: "ann"}}, {Note, :assign, _, %{to: "ann"}}] = writes()
      assert Enum.map(Ash.read!(Note), & &1.assignee) == ["ann", "ann"]
    end

    test "a page that gives no value raises when the action opens or runs", %{
      model: model,
      note: note
    } do
      opts = [authorize?: false, page_values: %{@page | page_arguments: %{}}]

      assert_raise ArgumentError, ~r/`assign`.*`to`.*page_arguments/, fn ->
        Act.run(model, action(model, :assign), %{id: note.id}, %{}, opts)
      end

      assert_raise ArgumentError, ~r/`tally`.*`by`.*page_arguments/, fn ->
        Act.open_generic(model, action(model, :tally), "p", opts)
      end

      assert writes() == []
      assert Ash.get!(Note, note.id).assignee == nil
    end
  end

  describe "`page_argument` at compile time" do
    import Spark.Test

    test "names a public argument of the action, other than its `record_argument`, once" do
      [{AshDataTable.PageValuesTest.Misnamed, errors}] =
        dsl_errors do
          defmodule Elixir.AshDataTable.PageValuesTest.Misnamed do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            actions do
              defaults [:read]

              update :rename do
                accept [:title]
              end

              update :hide do
                argument :reason, :string, public?: false
              end

              update :twice do
                argument :by, :string
              end

              action :stamp do
                argument :record_id, :uuid
                run fn _input, _context -> :ok end
              end
            end

            table do
              action :rename do
                page_argument :title
              end

              action :hide do
                page_argument :reason
              end

              action :twice do
                page_argument :by
                page_argument :by
              end

              action :stamp do
                record_argument :record_id
                page_argument :record_id
              end
            end
          end
        end

      assert Enum.map(errors, &{&1.path, &1.message}) == [
               {[:table, :action, :rename],
                "The action `rename` says `page_argument :title`, and has no argument named `title`. A page argument is an argument of the action that the page fills."},
               {[:table, :action, :hide],
                "The action `hide` says `page_argument :reason`, and its argument `reason` is not public. A page gives a private argument through `private_arguments`, without a declaration; `page_argument` is for a public one that the panel is not to ask for."},
               {[:table, :action, :twice],
                "The action `twice` says `page_argument :by` more than once."},
               {[:table, :action, :stamp],
                "The action `stamp` says `page_argument :record_id`, and `record_id` is its `record_argument`, which the table gives the row's primary key. It cannot be both."}
             ]
    end

    test "a required argument the page fills needs no field" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.PageValuesTest.Required do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
          end

          actions do
            defaults [:read]

            update :move do
              argument :to, :map, allow_nil?: false
            end
          end

          table do
            action :move do
              page_argument :to
            end
          end
        end
      end

      assert %{inputs: [], page_arguments: [:to]} =
               hd(Model.build(AshDataTable.PageValuesTest.Required).actions)
    end
  end

  describe "the veto" do
    defp input(model, intent, rows, veto, selection \\ nil) do
      %Input{
        selection: selection,
        intent: intent,
        model: model,
        state: %State{},
        opts: [authorize?: false],
        rows: rows,
        veto: veto,
        page_values: @page,
        read?: true,
        offered: %{table: model.table_actions, bulk: Model.bulk_actions(model)}
      }
    end

    defp rows(records), do: Map.new(records, &{&1.id, %{pk: %{id: &1.id}, rowindex: 3}})

    defp veto(answer) do
      test = self()

      fn request ->
        send(test, {:asked, request})
        answer
      end
    end

    test "is told what the checks found, and asked before the record is read again", %{
      model: model,
      note: note
    } do
      halt = {:halt, "Not today."}
      intent = {:save, note.id, "title", "New"}

      assert Operation.save(input(model, intent, rows([note]), veto(halt))) ==
               {:halted, "Not today."}

      assert_received {:asked,
                       %Request{
                         resource: Note,
                         action: :update,
                         type: :update,
                         from: :cell,
                         column: :title,
                         key: key,
                         selection: nil
                       }}

      assert key == %{id: note.id}
      # nothing was read, and nothing written
      assert reads(Note) == []
      assert writes() == []
      assert Ash.get!(Note, note.id).title == "One"
    end

    test "is not asked for what the checks refuse", %{model: model, note: note} do
      intent = {:save, Ash.UUID.generate(), "title", "New"}
      assert Operation.save(input(model, intent, rows([note]), veto(:cont))) == :refused
      refute_received {:asked, _}
    end

    test "a write it lets go on is given what the page gives", %{model: model, note: note} do
      intent = {:act, note.id, "assign"}

      assert {:ok, %{record: %Note{assignee: "ann"}}} =
               Operation.run(input(model, intent, rows([note]), veto(:cont)))

      assert_received {:asked, %Request{action: :assign, type: :update, from: :row}}
      assert [{Note, :assign, _context, %{to: "ann", secret: "s3"}}] = writes()
    end

    test "a run on a selection asks once, before it starts", %{
      model: model,
      note: note,
      other: other
    } do
      selection = {:rows, [note.id, other.id]}

      assert {:start, run, %{}} =
               Operation.bulk(
                 input(model, {:bulk_run, "assign"}, rows([note, other]), veto(:cont), selection)
               )

      assert_received {:asked, %Request{from: :bulk, selection: selection}}
      assert selection == [note.id, other.id]
      refute_received {:asked, _}
      assert writes() == []

      assert %{done: 2} = run.()
      refute_received {:asked, _}
      assert length(writes()) == 2
    end

    test "a halted run on a selection starts nothing", %{model: model, note: note} do
      input =
        input(
          model,
          {:bulk_run, "assign"},
          rows([note]),
          veto({:halt, "No."}),
          {:rows, [note.id]}
        )

      assert Operation.bulk(input) == {:halted, "No."}

      assert reads(Note) == []
      assert writes() == []
    end
  end
end
