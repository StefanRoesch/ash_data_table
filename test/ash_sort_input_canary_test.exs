defmodule AshDataTable.AshSortInputCanaryTest do
  @moduledoc """
  A canary for a defect of Ash that the table works around (internal ticket
  #31): `Ash.Query.sort_input/2` through a relationship path
  ("assignee.name") applies no policy of the related resource, so the rows
  are ordered by values the actor may not read. This test passes while Ash
  still has it, and fails once Ash is fixed.
  """
  use ExUnit.Case, async: true

  require Ash.Query

  defmodule User do
    @moduledoc false
    use Ash.Resource,
      domain: AshDataTable.Test.Domain,
      data_layer: Ash.DataLayer.Ets,
      authorizers: [Ash.Policy.Authorizer]

    attributes do
      integer_primary_key :id
      attribute :name, :string, public?: true
      attribute :hidden, :boolean, public?: true, default: false
    end

    actions do
      defaults [:read]
    end

    policies do
      policy action_type(:read) do
        authorize_if expr(hidden == false)
      end
    end
  end

  defmodule Ticket do
    @moduledoc false
    use Ash.Resource,
      domain: AshDataTable.Test.Domain,
      data_layer: Ash.DataLayer.Ets,
      authorizers: [Ash.Policy.Authorizer]

    attributes do
      integer_primary_key :id
      attribute :title, :string, public?: true
    end

    relationships do
      belongs_to :assignee, User, public?: true, attribute_type: :integer
    end

    actions do
      defaults [:read]
    end

    policies do
      policy action_type(:read) do
        authorize_if always()
      end
    end
  end

  @fixed """
  Ash fixed internal ticket #31: remove the workaround at \
  `known_sort/2` and `known/2` in lib/ash_data_table/query.ex (and their comment), \
  the reference column that is never sortable in lib/ash_data_table/model.ex (`column/5` \
  for a belongs-to) and lib/ash_data_table/resource/verifiers/verify_columns.ex \
  (`reference_errors/4`), the sentence on it in documentation/topics/nested-tables.md, \
  and this test.\
  """

  test "a sort through a relationship still orders by values the actor may not read" do
    for {id, name, hidden} <- [
          {1, "Alice", false},
          {2, "Bob", true},
          {3, "Carol", false},
          {4, "Dave", true}
        ],
        do: Ash.Seed.seed!(User, %{id: id, name: name, hidden: hidden})

    for {id, assignee_id} <- [{1, 4}, {2, 1}, {3, 2}, {4, 3}],
        do: Ash.Seed.seed!(Ticket, %{id: id, title: "Ticket #{id}", assignee_id: assignee_id})

    order =
      Ticket
      |> Ash.Query.sort_input("assignee.name")
      |> Ash.read!(actor: %{id: 99})
      |> Enum.map(& &1.assignee_id)

    # Alice, Bob, Carol, Dave: Bob and Dave are hidden, and still sorted in
    # between. With the related policy applied the two would sort together.
    assert order == [1, 2, 3, 4], @fixed
  end
end
