defmodule AshDataTable.PanelTest do
  @moduledoc """
  The action panel (`AshDataTable.Panel`, stage 9d), per kind, below the
  live layer: what it opens with (refused, gone, with the page's
  arguments), what its form holds and says as the person types (errors at
  fields, a wall time the page's zone does not have, the places of an
  array's values), a group added and taken away, "Clear" and "Keep" of a
  sensitive field, a record chosen in the picker, what its button runs
  (`submission/2`: nothing sensitive in it but what was typed in this
  panel) and what came of it (`outcome/2`).

  Pure over the model, the form and what was typed: the forms are built
  through `AshDataTable.Act` and `AshDataTable.Edit`, reading the records
  as the person; no socket.
  """
  use ExUnit.Case, async: false

  import AshDataTable.Test.Sensitive.Vaults, only: [vault: 0]

  alias AshDataTable.Model
  alias AshDataTable.Panel
  alias AshDataTable.Present
  alias AshDataTable.Test.Acting
  alias AshDataTable.Test.Exposing.Kept
  alias AshDataTable.Test.Given.Note
  alias AshDataTable.Test.Resource
  alias AshDataTable.Test.Sensitive, as: Vault
  alias AshDataTable.Test.Sensitive.Owner, as: VaultOwner

  @admin %{role: :admin}
  @berlin "Europe/Berlin"

  # every sensitive value of the vault (`Vaults.vault/1`)
  @secrets ~r/tok-123|4711|hunter2|swordfish|letmein|wax|B-7|2027/

  defp seen(term), do: inspect(term, limit: :infinity, printable_limit: :infinity, structs: false)

  defp named(model, name),
    do: Enum.find(model.actions ++ model.table_actions, &(&1.name == name))

  defp column(model, name), do: Enum.find(model.columns, &(&1.name == name))

  defp input(panel, name), do: Enum.find(panel.inputs, &(&1.name == name))

  defp opts(reader, more \\ []),
    do: [id: "t", time_zone: "Etc/UTC", reader: reader] ++ more

  describe "a row action's panel" do
    setup do
      on_exit(fn -> AshDataTable.Test.Ets.stop([Vault, VaultOwner]) end)

      record =
        Ash.Seed.seed!(Vault, %{name: vault().name, token: vault().token, pin: vault().pin})

      model = Model.build(Vault)
      %{model: model, pk: %{id: record.id}, rotate: named(model, :rotate)}
    end

    defp rotate(%{model: model, pk: pk, rotate: rotate}, more \\ []) do
      {:ok, panel} =
        Panel.open(:row, %{key: "k1", pk: pk, action: rotate}, model, opts([actor: @admin], more))

      panel
    end

    test "opens with the form of the action on the record, read as the person", context do
      panel = rotate(context, named: fn record -> record.name end)

      assert %Panel{kind: :row, for: %{key: "k1", action: %{name: :rotate}}} = panel
      assert {:text, :action_on, [action: _label, record: "Main"]} = panel.title
      assert panel.submit == {:text, :run, []}
      # the sensitive field the update action can empty on this record
      assert panel.clearable == [:token]
      # a sensitive field holds nothing of the record
      assert Panel.held(panel, input(panel, :token)) == ""
      refute seen(Panel.shown(panel)) =~ @secrets
    end

    test "is called nothing but its action where the record is called nothing", context do
      assert rotate(context).title == context.rotate.label
    end

    test "says so of a record that is gone", %{model: model, rotate: rotate} do
      pk = %{id: Ash.UUID.generate()}

      assert Panel.open(:row, %{key: "k1", pk: pk, action: rotate}, model, opts(actor: @admin)) ==
               {:error, {:text, :record_gone, []}}
    end

    test "says what the action makes of what was typed, at its field once it was used", context do
      panel = rotate(context)
      panel = Panel.validate(panel, context.model, %{"passphrase" => "wrong", "note" => "n"})

      assert panel.errors[:passphrase] == [{:ash, "is not the passphrase", []}]
      assert MapSet.member?(panel.used, "passphrase")

      assert Panel.field(panel, input(panel, :passphrase), %{}).errors ==
               panel.errors[:passphrase]

      # a field the person has not been in shows nothing yet
      panel = Panel.validate(panel, context.model, %{"note" => "n", "_unused_passphrase" => ""})
      assert Panel.field(panel, input(panel, :passphrase), %{}).errors == []
    end

    test "Clear asks for a sensitive field to be emptied, and Keep takes it back", context do
      panel = rotate(context)

      assert {:ok, cleared, :token} = Panel.clear(panel, "token")
      assert MapSet.member?(cleared.cleared, :token)
      assert Panel.field(cleared, input(cleared, :token), %{}).clear == :asked

      assert {:ok, kept, :token} = Panel.clear(cleared, "token")
      assert kept.cleared == MapSet.new()
      assert Panel.field(kept, input(kept, :token), %{}).clear == :offered

      # only a field the panel offers it for
      assert Panel.clear(panel, "passphrase") == :error
      assert Panel.clear(panel, "nothing") == :error
    end

    test "runs what was typed in it, and nothing sensitive besides", context do
      panel = rotate(context)
      {:ok, cleared, :token} = Panel.clear(panel, "token")
      typed = %{"passphrase" => "typed-pass", "note" => "n"}

      assert {:submit_row, "k1", %{name: :rotate}, held} = Panel.submission(cleared, typed)
      assert held.params == typed
      assert held.cleared == [:token]
      assert held.inputs == panel.inputs
      refute seen(held.params) =~ @secrets
      refute seen(Map.delete(held, :form)) =~ @secrets
    end

    test "is closed or stays open with what came of its action", context do
      panel = rotate(context)

      assert Panel.outcome(panel, :refused) == :closed
      assert Panel.outcome(panel, {:halted, "Not now."}) == {:open, panel, "Not now."}

      ran = {:ok, %AshDataTable.Operation.Outcome{gone?: true}}

      assert Panel.outcome(panel, ran) == {:closed, {:ran, "k1", context.rotate, ran}}

      failed = %AshDataTable.Operation.Failure{form: panel.form}
      assert {:open, ^panel, nil} = Panel.outcome(panel, {:error, failed})

      gone = %AshDataTable.Operation.Failure{message: {:text, :record_gone, []}}

      assert Panel.outcome(panel, {:error, gone}) ==
               {:open, panel, {:text, :record_gone, []}}

      unchosen = %AshDataTable.Operation.Failure{unchosen: [%{label: "Owner"}]}

      assert {:open, ^panel,
              {:join, " ", [{:text, :error_on_field, [field: "Owner", message: _]}]}} =
               Panel.outcome(panel, {:error, unchosen})
    end

    test "stays open with every error shown once it failed, and says why", context do
      panel = rotate(context)
      panel = Panel.validate(panel, context.model, %{"passphrase" => "wrong"})
      failed = Panel.failed(panel, context.model, "Not now.", nil)

      assert failed.submitted?
      assert failed.errors[nil] == ["Not now."]

      said = [{nil, "Not now."}, {input(failed, :passphrase), "is not the passphrase"}]

      assert {:text, :action_not_done, [action: _label, message: {:join, "; ", [_, _]}]} =
               Panel.said(failed, said)
    end
  end

  describe "a cell's panel" do
    setup do
      tenant = "panel-#{System.unique_integer([:positive])}"
      on_exit(fn -> AshDataTable.KitCase.clean(tenant) end)

      record =
        Ash.create!(
          Resource,
          %{name: "Anchor", place: %{city: "Kiel", zip: "24103"}, stops: [%{city: "Bonn"}]},
          tenant: tenant,
          authorize?: false
        )

      %{model: Model.build(Resource), pk: %{id: record.id}, reader: [tenant: tenant]}
    end

    defp cell(%{model: model, pk: pk, reader: reader}, name) do
      Panel.open(:cell, %{key: "k1", pk: pk, column: column(model, name)}, model, opts(reader))
    end

    test "opens with the column's one field, as its form sends what the record holds", context do
      assert {:ok, panel} = cell(context, :place)
      assert %Panel{kind: :cell, for: %{key: "k1", column: :place}} = panel
      assert panel.submit == {:text, :save, []}
      assert [%{name: :place}] = panel.inputs
      assert %{"city" => "Kiel", "zip" => "24103"} = panel.groups["place"]
      assert Panel.column(panel) == :place
      assert Panel.made_for(panel) == {:cell, :update, "k1", :place}
    end

    test "adds a group and takes one away, by a path of names; a forged path does nothing",
         context do
      {:ok, panel} = cell(context, :stops)

      assert {:ok, added, ["stops" | _focus]} =
               Panel.change(panel, context.model, ["stops"], :add)

      assert map_size(Map.delete(added.groups["stops"], "_present")) == 2
      assert MapSet.member?(added.used, "stops")

      [first | _] = added.groups["stops"] |> Map.delete("_present") |> Map.keys() |> Enum.sort()

      assert {:ok, removed, _focus} =
               Panel.change(added, context.model, ["stops", first], :remove)

      assert map_size(Map.delete(removed.groups["stops"], "_present")) == 1

      assert Panel.change(panel, context.model, ["stops", "nowhere", "city"], :remove) == :error
      assert Panel.change(panel, context.model, ["name"], :add) == :error
      assert Panel.change(panel, context.model, [], :add) == :error
    end

    test "runs the save of the cell, and is closed once it is saved", context do
      {:ok, panel} = cell(context, :place)
      typed = %{"place" => %{"city" => "Ulm", "zip" => ""}}

      assert {:submit_cell, "k1", :place, %{params: ^typed}} = Panel.submission(panel, typed)

      saved = {:ok, %AshDataTable.Operation.Outcome{}}
      assert Panel.outcome(panel, saved) == {:closed, {:saved, "k1", elem(saved, 1)}}
    end

    test "says at an array's field which of its values the action's errors are about", context do
      {:ok, panel} = cell(context, :tags)
      panel = Panel.validate(panel, context.model, %{"tags" => ["", "ok", "far-too-long"]})

      assert [_ | _] = panel.errors[:tags]
      assert panel.places == %{tags: [1]}
      # shown once the field was used, with its places
      assert %{places: [1]} = Panel.field(panel, input(panel, :tags), %{})
    end

    test "is refused for a cell whose value the person may not see on its record" do
      on_exit(fn -> AshDataTable.Test.Ets.stop([Kept]) end)
      record = Ash.Seed.seed!(Kept, %{name: "One", tags: ["a"]})
      model = Model.build(Kept)
      for = %{key: "k1", pk: %{id: record.id}, column: column(model, :tags)}

      assert Panel.open(:cell, for, model, opts(actor: %{role: :member})) == :refused
      assert {:ok, %Panel{kind: :cell}} = Panel.open(:cell, for, model, opts(actor: @admin))
    end

    test "says what is not saved as a cell says it", context do
      {:ok, panel} = cell(context, :place)
      failed = Panel.failed(panel, context.model, nil, nil)

      assert {:text, :not_saved, [column: _label, message: {:join, "; ", []}]} =
               Panel.said(failed, [])
    end
  end

  describe "a create's panel" do
    setup do
      on_exit(fn -> AshDataTable.Test.Ets.stop([Acting]) end)
      model = Model.build(Acting)
      %{model: model}
    end

    defp create(model, zone) do
      {:ok, panel} =
        Panel.open(:create, %{action: model.create}, model,
          id: "t",
          time_zone: zone,
          reader: [],
          given: %{"board_id" => "b"}
        )

      panel
    end

    test "opens with the defaults, and with what the table gives the action", %{model: model} do
      panel = create(model, "Etc/UTC")

      assert %Panel{kind: :create, given: %{"board_id" => "b"}} = panel
      assert panel.submit == {:text, :create, []}
      assert Panel.values(panel.inputs, %{}, panel.given, "Etc/UTC")["board_id"] == "b"
    end

    test "says at its field that a wall time the page's zone does not have runs nothing",
         %{model: model} do
      panel = create(model, @berlin)
      typed = %{"title" => "T", "seen_at" => "2026-03-29T02:30"}
      panel = Panel.validate(panel, model, typed)

      assert panel.errors[:seen_at] == [{:text, :no_such_time, zone: @berlin}]
      assert {:gaps, gapped} = Panel.submitted(panel, typed)
      assert gapped.typed == typed

      assert {:ok, _panel} =
               Panel.submitted(panel, %{"title" => "T", "seen_at" => "2026-03-29T03:30"})
    end

    test "is closed once the record is created", %{model: model} do
      panel = create(model, "Etc/UTC")
      created = %AshDataTable.Operation.Outcome{gone?: true}

      assert {:submit_create, %{name: :create}, _held} = Panel.submission(panel, %{})
      assert Panel.outcome(panel, {:ok, created}) == {:closed, {:created, created}}
    end
  end

  describe "a table action's panel" do
    setup do
      on_exit(fn -> AshDataTable.Test.Ets.stop([Note]) end)
      %{model: Model.build(Note)}
    end

    test "takes the arguments the page fills from the page, and opens without them only with them",
         %{model: model} do
      tally = named(model, :tally)

      assert_raise ArgumentError, ~r/takes its argument `by` from the page/, fn ->
        Panel.open(:table, %{action: tally}, model, opts(authorize?: false))
      end

      page = [authorize?: false, page_values: %{page_arguments: %{by: "eve"}}]
      assert {:ok, panel} = Panel.open(:table, %{action: tally}, model, opts(page))
      assert %Panel{kind: :table, for: %{action: %{name: :tally}}} = panel
      assert Panel.action(panel) == tally
      assert Panel.row(panel) == nil

      done = %AshDataTable.Operation.Outcome{value: 1}
      assert Panel.outcome(panel, {:ok, done}) == {:closed, {:done, tally, done}}
    end
  end

  describe "a selection's panel" do
    setup do
      tenant = "panel-#{System.unique_integer([:positive])}"
      on_exit(fn -> AshDataTable.KitCase.clean(tenant) end)
      model = Model.build(Resource)

      %{
        model: model,
        reader: [tenant: tenant],
        destroy: Enum.find(model.actions, &(&1.name == :destroy))
      }
    end

    test "is headed by how many records it is about, asks its question, and runs beside the process",
         %{model: model, reader: reader, destroy: destroy} do
      for {count, title} <- [
            {3, {:text, :bulk_on, count: 3, action: destroy.label}},
            {nil, {:text, :bulk_on_all, action: destroy.label}}
          ] do
        {:ok, panel} =
          Panel.open(
            :bulk,
            %{action: destroy, selection: :all, count: count},
            model,
            opts(reader, question: "Delete them?")
          )

        assert panel.title == title
        assert panel.question == "Delete them?"
        assert Panel.outlasts?(panel)
        assert {:submit_bulk, ^destroy, :all, %{params: %{}}} = Panel.submission(panel, %{})

        run = fn -> :ran end

        assert Panel.outcome(panel, {:start, run, %{}}) ==
                 {:closed, {:start, destroy, run, %{}}}
      end
    end
  end

  describe "a filter's panel" do
    setup do
      model = Model.build(Resource)
      tier = column(model, :tier)
      operator = Enum.find(tier.operators, &(Map.get(tier.takes, &1) == :many))
      %{model: model, tier: tier, operator: operator}
    end

    test "ticks values as they are sent, and filters by them once it is", context do
      %{model: model, tier: tier, operator: operator} = context

      {:ok, panel} =
        Panel.open(:filter, %{column: tier, operator: operator, values: ["low"]}, model,
          id: "t",
          time_zone: "Etc/UTC"
        )

      assert %Panel{kind: :filter, for: %{column: :tier, operator: ^operator}} = panel
      assert Panel.held(panel, hd(panel.inputs)) == ["low"]
      assert Panel.action(panel) == nil
      refute Panel.outlasts?(panel)

      panel = Panel.validate(panel, model, %{"tier" => ["", "low", "high"]})
      assert panel.values == ["low", "high"]

      assert %Present.Panel{ask: nil, method: "post", question: nil} = Panel.shown(panel)

      assert Panel.submitted(panel, %{"tier" => ["", "high"]}) ==
               {:filter, %{column: :tier, operator: operator, values: ["high"]}}
    end
  end

  describe "a field given by choosing records in the picker" do
    setup do
      tenant = "panel-#{System.unique_integer([:positive])}"
      on_exit(fn -> AshDataTable.KitCase.clean(tenant) end)
      opts = [tenant: tenant, authorize?: false]
      Ash.create!(Resource.Owner, %{name: "Ann Lee"}, opts)
      record = Ash.create!(Resource, %{name: "Anchor"}, opts)
      model = Model.build(Resource)

      {:ok, panel} =
        Panel.open(
          :row,
          %{key: "k1", pk: %{id: record.id}, action: named(model, :staff)},
          model,
          opts(tenant: tenant)
        )

      %{model: model, panel: panel}
    end

    test "holds the records chosen, after those it held, with what the picker was given",
         %{model: model, panel: panel} do
      helpers = Panel.reference(panel, "helpers")
      assert %{editor: :references} = helpers
      assert Panel.keys(panel, :helpers) == []

      known = %{label: nil, row: nil}
      panel = Panel.choose(panel, model, helpers, [], [{"Ann Lee", known}], %{"near" => "x"})

      assert Panel.keys(panel, :helpers) == ["Ann Lee"]
      assert Panel.keys(panel, "helpers") == ["Ann Lee"]
      assert Panel.known(panel, :helpers) == %{"Ann Lee" => known}
      assert panel.picked_with == %{helpers: %{"Ann Lee" => %{"near" => "x"}}}
      assert MapSet.member?(panel.used, "helpers")
      assert Panel.held(panel, helpers) == ["Ann Lee"]

      # a key taken out again
      panel = Panel.hold(panel, model, helpers, [])
      assert Panel.keys(panel, :helpers) == []

      assert {:submit_row, "k1", _action, %{picked_with: %{helpers: _}}} =
               Panel.submission(panel, panel.typed)
    end
  end
end
