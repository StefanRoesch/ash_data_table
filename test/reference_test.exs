defmodule AshDataTable.ReferenceTest do
  @moduledoc """
  `reference` in an `action` of the table block: the resource an argument
  of the action refers to, where nothing in Ash says it. The argument is
  then chosen in the picker, as one that a `manage_relationship` change
  hands to a relationship is, and a key that names no record the person
  could have chosen runs nothing.
  """
  use ExUnit.Case, async: true

  import Spark.Test

  alias AshDataTable.Bulk
  alias AshDataTable.Model
  alias AshDataTable.Operation.{Failure, Outcome}
  alias AshDataTable.Panel
  alias AshDataTable.Test.Referring.{Job, Member}
  alias AshDataTable.Test.Submitting

  @admin [actor: %{role: :admin}, authorize_given: nil]
  @member [actor: %{role: :member}, authorize_given: nil]

  defp member(name, more \\ %{}), do: Ash.Seed.seed!(Member, Map.merge(%{name: name}, more))
  defp job(title, more \\ %{}), do: Ash.Seed.seed!(Job, Map.merge(%{title: title}, more))
  defp stored(job), do: Ash.get!(Job, job.id, authorize?: false)

  defp model, do: Model.build(Job)
  defp row_action(name), do: Enum.find(model().actions, &(&1.name == name))
  defp table_action(name), do: Enum.find(model().table_actions, &(&1.name == name))
  defp input(action, name), do: Enum.find(action.inputs, &(&1.name == name))

  describe "the declaration" do
    test "is kept with its action, in the declared order" do
      assert [
               %AshDataTable.Resource.Action{
                 name: :give_all,
                 references: [%AshDataTable.Resource.Reference{name: :to_id, destination: Member}]
               },
               %{name: :hand_over, references: [%{name: :to_id}]},
               %{name: :give},
               %{name: :staff, references: [%{name: :helper_ids, destination: Member}]},
               %{name: :close},
               %{name: :note, references: []}
             ] = AshDataTable.Resource.Info.actions(Job)
    end
  end

  describe "an argument with a `reference`" do
    test "is chosen in the picker: one record for a key" do
      assert %Model.Input{
               kind: :argument,
               editor: :reference,
               label: "To ID",
               required?: true,
               reference: %{
                 relationship: nil,
                 destination: Member,
                 destination_attribute: :id,
                 choose_action: :read,
                 source_attribute: nil,
                 several?: false,
                 allow_nil?: false,
                 related?: false
               }
             } = input(table_action(:give_all), :to_id)
    end

    test "is chosen in the picker: any number of records for a list of keys" do
      assert %Model.Input{
               editor: :references,
               reference: %{destination: Member, several?: true, related?: false}
             } = input(row_action(:staff), :helper_ids)
    end

    test "can be left empty where the argument can" do
      assert %{required?: false, reference: %{allow_nil?: true}} =
               input(row_action(:give), :to_id)
    end

    test "is one of a table action, a generic row action, an update and a destroy action" do
      assert %{editor: :reference} = input(table_action(:give_all), :to_id)
      assert %{editor: :reference} = input(row_action(:give), :to_id)
      assert %{editor: :reference} = input(row_action(:close), :for_id)

      # the argument that takes the row's key is the table's, and no input
      hand_over = row_action(:hand_over)
      assert hand_over.record_argument == :job_id
      assert Enum.map(hand_over.inputs, &{&1.name, &1.editor}) == [to_id: :reference]
    end

    test "opens the action panel, also where it can be left empty: choosing is what it is for" do
      assert row_action(:give).panel?
      assert row_action(:hand_over).panel?
      assert table_action(:give_all).panel?
    end

    test "is offered for the selected rows as any row action is" do
      assert Enum.map(Model.bulk_actions(model()), & &1.name) ==
               [:hand_over, :give, :staff, :close, :note]
    end

    test "without one, a key argument is the plain field it was" do
      assert %{editor: :plain, reference: nil} = input(row_action(:note), :seen_by_id)
    end
  end

  describe "a key that is sent for such an argument" do
    setup do
      %{ada: member("Ada"), away: member("Bo", %{away?: true})}
    end

    defp unchosen(action, params, opts) do
      for input <- Panel.unchosen(action.inputs, params, nil, opts), do: input.name
    end

    test "is a claim: one of a record the person may not read is theirs to give nowhere",
         %{ada: ada, away: away} do
      give = row_action(:give)

      assert unchosen(give, %{"to_id" => ada.id}, @member) == []
      assert unchosen(give, %{"to_id" => away.id}, @admin) == []
      assert unchosen(give, %{"to_id" => away.id}, @member) == [:to_id]
      assert unchosen(give, %{"to_id" => Ash.UUID.generate()}, @admin) == [:to_id]
      # empty, and no key at all: the action's to say
      assert unchosen(give, %{"to_id" => ""}, @member) == []
      assert unchosen(give, %{"to_id" => "no key"}, @member) == []

      staff = row_action(:staff)
      assert unchosen(staff, %{"helper_ids" => ["", ada.id]}, @member) == []
      assert unchosen(staff, %{"helper_ids" => ["", ada.id, away.id]}, @member) == [:helper_ids]
    end

    test "runs an update action with the record that was chosen", %{ada: ada, away: away} do
      job = job("Paint")

      assert {:ok, %Outcome{record: %Job{}}} =
               Submitting.row(
                 model(),
                 row_action(:give),
                 %{id: job.id},
                 %{"to_id" => ada.id},
                 @admin
               )

      assert stored(job).owner_id == ada.id

      # and nothing with a key of a record that could not have been chosen
      assert {:error, %Failure{unchosen: [%{name: :to_id}]}} =
               Submitting.row(
                 model(),
                 row_action(:give),
                 %{id: job.id},
                 %{"to_id" => away.id},
                 @member
               )

      assert stored(job).owner_id == ada.id
    end

    test "runs an update action with several chosen records", %{ada: ada, away: away} do
      job = job("Paint")

      assert {:ok, %Outcome{record: %Job{}}} =
               Submitting.row(
                 model(),
                 row_action(:staff),
                 %{id: job.id},
                 %{"helper_ids" => ["", ada.id, away.id]},
                 @admin
               )

      assert stored(job).helper_ids == [ada.id, away.id]

      assert {:error, %Failure{unchosen: [%{name: :helper_ids}]}} =
               Submitting.row(
                 model(),
                 row_action(:staff),
                 %{id: job.id},
                 %{"helper_ids" => ["", away.id]},
                 @member
               )

      assert stored(job).helper_ids == [ada.id, away.id]
    end

    test "runs a table action, and not with a key that could not have been chosen",
         %{ada: ada, away: away} do
      job = job("Paint")

      assert {:error, %Failure{unchosen: [%{name: :to_id}]}} =
               Submitting.table(model(), table_action(:give_all), %{"to_id" => away.id}, @member)

      assert stored(job).owner_id == nil

      assert {:ok, %Outcome{value: 1}} =
               Submitting.table(model(), table_action(:give_all), %{"to_id" => ada.id}, @member)

      assert stored(job).owner_id == ada.id
    end

    test "runs a generic row action, which the table gives the row's key besides",
         %{ada: ada, away: away} do
      job = job("Paint")
      hand_over = row_action(:hand_over)

      assert {:error, %Failure{unchosen: [%{name: :to_id}]}} =
               Submitting.row(model(), hand_over, %{id: job.id}, %{"to_id" => away.id}, @member)

      assert stored(job).owner_id == nil

      # a key for the row that the form sends is not taken
      other = job("Other")

      assert {:ok, %Outcome{value: nil}} =
               Submitting.row(
                 model(),
                 hand_over,
                 %{id: job.id},
                 %{"to_id" => ada.id, "job_id" => other.id},
                 @member
               )

      assert stored(job).owner_id == ada.id
      assert stored(other).owner_id == nil
    end

    test "runs a destroy action", %{ada: ada} do
      job = job("Paint")

      assert {:ok, %Outcome{gone?: true}} =
               Submitting.row(
                 model(),
                 row_action(:close),
                 %{id: job.id},
                 %{"for_id" => ada.id},
                 @admin
               )

      assert Ash.read!(Job, authorize?: false) == []
    end

    test "is given once for all the selected rows", %{ada: ada} do
      one = job("One")
      two = job("Two")
      opts = [authorize?: false, state: %AshDataTable.State{}]

      assert %{done: 2, failed: []} =
               Bulk.run(
                 model(),
                 row_action(:give),
                 {:rows, [one.id, two.id]},
                 %{"to_id" => ada.id},
                 opts
               )

      assert %{done: 2, failed: []} =
               Bulk.run(
                 model(),
                 row_action(:hand_over),
                 {:rows, [one.id, two.id]},
                 %{"to_id" => nil},
                 opts
               )

      assert stored(one).owner_id == nil

      assert %{done: 2, failed: []} =
               Bulk.run(
                 model(),
                 row_action(:hand_over),
                 {:rows, [one.id, two.id]},
                 %{"to_id" => ada.id},
                 opts
               )

      assert stored(one).owner_id == ada.id
      assert stored(two).owner_id == ada.id
    end
  end

  describe "a `reference` that cannot be used is reported, and the table refused" do
    defp errors_of(module, errors) do
      for {^module, found} <- errors, error <- found, do: {error.path, error.message}
    end

    test "an argument that is not there, not public, the table's own, sensitive, or named twice" do
      errors =
        dsl_errors do
          defmodule Elixir.AshDataTable.ReferenceTest.Arguments do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :owner_id, :uuid, public?: true
            end

            actions do
              defaults [:read]

              action :unknown do
                argument :to_id, :uuid
                run fn _input, _context -> :ok end
              end

              update :accepted do
                accept [:owner_id]
              end

              action :hidden do
                argument :to_id, :uuid, public?: false
                run fn _input, _context -> :ok end
              end

              action :own do
                argument :record_id, :uuid, allow_nil?: false
                run fn _input, _context -> :ok end
              end

              action :secret do
                argument :to_id, :uuid, sensitive?: true
                run fn _input, _context -> :ok end
              end

              action :twice do
                argument :to_id, :uuid
                run fn _input, _context -> :ok end
              end
            end

            table do
              action :unknown do
                reference :other_id, AshDataTable.Test.Referring.Member
              end

              action :accepted do
                reference :owner_id, AshDataTable.Test.Referring.Member
              end

              action :hidden do
                reference :to_id, AshDataTable.Test.Referring.Member
              end

              action :own do
                record_argument :record_id
                reference :record_id, AshDataTable.Test.Referring.Member
              end

              action :secret do
                reference :to_id, AshDataTable.Test.Referring.Member
              end

              action :twice do
                reference :to_id, AshDataTable.Test.Referring.Member
                reference :to_id, AshDataTable.Test.Referring.Member
              end
            end
          end
        end

      assert errors_of(AshDataTable.ReferenceTest.Arguments, errors) == [
               {[:table, :action, :unknown],
                "The action `unknown` says `reference :other_id`, and has no argument named `other_id`."},
               {[:table, :action, :accepted],
                "The action `accepted` says `reference :owner_id`, and `owner_id` is an attribute the action accepts, not one of its arguments. A `reference` is for an argument. The foreign key of a public belongs-to relationship is chosen in the picker without one: the relationship says which resource it points at."},
               {[:table, :action, :hidden],
                "The action `hidden` says `reference :to_id`, and its argument `to_id` is not public. A private argument is not given from the outside, and a table is the outside."},
               {[:table, :action, :own],
                "The action `own` says `reference :record_id`, and `record_id` is its `record_argument`: the table gives it the key of the row, and nobody chooses it. Leave the `reference` out."},
               {[:table, :action, :secret],
                "The action `secret` says `reference :to_id`, and its argument `to_id` is declared `sensitive?: true`. A picker shows what is chosen, and a table shows nothing of a sensitive input: it has no field for this one."},
               {[:table, :action, :twice],
                "The action `twice` has more than one `reference :to_id`. An argument refers to one resource."}
             ]

      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.ReferenceTest.Arguments: its action `unknown` cannot be used. The action `unknown` says `reference :other_id`, and has no argument named `other_id`.",
                   fn -> Model.build(AshDataTable.ReferenceTest.Arguments) end
    end

    test "a destination without a table, without a public read action, or with a key the argument cannot hold" do
      errors =
        dsl_errors do
          # a resource whose table would read through a private action,
          # which is reported for it as well
          defmodule Elixir.AshDataTable.ReferenceTest.Closed do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            actions do
              read :read do
                primary? true
                public? false
              end
            end
          end

          defmodule Elixir.AshDataTable.ReferenceTest.Destinations do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            actions do
              defaults [:read]

              for name <- [:bare, :no_resource, :closed, :composite, :stored_as_key] do
                action name do
                  argument :to_id, :uuid
                  run fn _input, _context -> :ok end
                end
              end

              action :numbered do
                argument :to_id, :integer
                run fn _input, _context -> :ok end
              end

              action :texts do
                argument :to_ids, {:array, :string}
                run fn _input, _context -> :ok end
              end

              action :nested do
                argument :to_ids, {:array, {:array, :uuid}}
                run fn _input, _context -> :ok end
              end
            end

            table do
              action :bare do
                reference :to_id, AshDataTable.Test.Referring.Bare
              end

              action :no_resource do
                reference :to_id, AshDataTable.Test.Referring
              end

              action :closed do
                reference :to_id, AshDataTable.ReferenceTest.Closed
              end

              action :composite do
                reference :to_id, AshDataTable.Test.Picking.Zone
              end

              action :numbered do
                reference :to_id, AshDataTable.Test.Referring.Member
              end

              action :texts do
                reference :to_ids, AshDataTable.Test.Referring.Member
              end

              action :nested do
                reference :to_ids, AshDataTable.Test.Referring.Member
              end

              # stored as the key is, under another type: accepted
              action :stored_as_key do
                reference :to_id, AshDataTable.Test.Referring.Member
              end
            end
          end
        end

      assert errors_of(AshDataTable.ReferenceTest.Destinations, errors) == [
               {[:table, :action, :bare],
                "The action `bare` says `reference :to_id, AshDataTable.Test.Referring.Bare`, and AshDataTable.Test.Referring.Bare has no table: it is no resource that lists `AshDataTable.Resource` in its extensions. The records of a reference are chosen from the table of their resource."},
               {[:table, :action, :no_resource],
                "The action `no_resource` says `reference :to_id, AshDataTable.Test.Referring`, and AshDataTable.Test.Referring has no table: it is no resource that lists `AshDataTable.Resource` in its extensions. The records of a reference are chosen from the table of their resource."},
               {[:table, :action, :closed],
                "The action `closed` says `reference :to_id, AshDataTable.ReferenceTest.Closed`, and the table of AshDataTable.ReferenceTest.Closed has no public read action to read the records to choose from: the `read_action` of its `table` block, else its primary read action. A table only runs `public?` actions: a private action is not meant for interfaces, and may be exempt from policies."},
               {[:table, :action, :composite],
                "The action `composite` says `reference :to_id, AshDataTable.Test.Picking.Zone`, and the primary key of AshDataTable.Test.Picking.Zone is `country`, `number`: several attributes. One argument holds the primary key of a record only where that is one attribute."},
               {[:table, :action, :numbered],
                "The action `numbered` says `reference :to_id, AshDataTable.Test.Referring.Member`, and the argument is of the type Ash.Type.Integer, which is not stored as the primary key `id` of AshDataTable.Test.Referring.Member is (Ash.Type.UUID), nor a list of it. The argument is given the primary key of the chosen record as it is."},
               {[:table, :action, :texts],
                "The action `texts` says `reference :to_ids, AshDataTable.Test.Referring.Member`, and the argument is of the type {:array, Ash.Type.String}, which is not stored as the primary key `id` of AshDataTable.Test.Referring.Member is (Ash.Type.UUID), nor a list of it. The argument is given the primary key of the chosen record as it is."},
               {[:table, :action, :nested],
                "The action `nested` says `reference :to_ids, AshDataTable.Test.Referring.Member`, and the argument is of the type {:array, {:array, Ash.Type.UUID}}, which is not stored as the primary key `id` of AshDataTable.Test.Referring.Member is (Ash.Type.UUID), nor a list of it. The argument is given the primary key of the chosen record as it is."}
             ]
    end

    test "an argument that a `manage_relationship` change hands to a relationship: the relationship says it" do
      errors =
        dsl_errors do
          defmodule Elixir.AshDataTable.ReferenceTest.Managed do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            relationships do
              belongs_to :owner, AshDataTable.Test.Referring.Member, public?: true
            end

            actions do
              defaults [:read]

              update :assign do
                require_atomic? false
                argument :owner, :uuid
                change manage_relationship(:owner, type: :append_and_remove)
              end
            end

            table do
              action :assign do
                reference :owner, AshDataTable.Test.Referring.Member
              end
            end
          end
        end

      assert errors_of(AshDataTable.ReferenceTest.Managed, errors) == [
               {[:table, :action, :assign],
                "The action `assign` says `reference :owner`, and a `manage_relationship` change of the action hands `owner` to the relationship `owner`. The relationship says which resource the argument refers to, and the change how it is read. Leave the `reference` out."}
             ]
    end
  end
end
