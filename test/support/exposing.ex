defmodule AshDataTable.Test.Exposing do
  @moduledoc """
  Destinations for the tests of what an aggregate or a calculation column
  shows of a field that a field policy protects on the related resource.
  The resources that declare such columns are written in the tests, which
  look at what compiling them says.

  The actors of these tests are maps: `%{role: :admin}`.
  """
end

defmodule AshDataTable.Test.Exposing.Member do
  @moduledoc "A member whose salary an admin alone sees: a field policy protects it."
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshDataTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :salary, :integer, public?: true
    attribute :team_id, :uuid, public?: true
  end

  actions do
    defaults [:read]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  field_policies do
    field_policy :salary do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    field_policy :* do
      authorize_if always()
    end
  end

  table do
    label_field :name
  end
end

defmodule AshDataTable.Test.Exposing.Guest do
  @moduledoc "A guest with field policies that protect nothing: every field is seen by everybody."
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshDataTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :salary, :integer, public?: true
    attribute :team_id, :uuid, public?: true
  end

  actions do
    defaults [:read]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  field_policies do
    field_policy :* do
      authorize_if always()
    end
  end
end

defmodule AshDataTable.Test.Exposing.BossSalary do
  @moduledoc "A calculation computed in Elixir, from what it loads of a related record."
  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [boss: [:salary]]

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, &(&1.boss && to_string(&1.boss.salary)))
  end
end

defmodule AshDataTable.Test.Exposing.Team do
  @moduledoc """
  A team with aggregate columns, read in pages. Its headcount and its budget
  are seen by an admin, and by the team's own lead: by anybody else on some
  records only. The number of its guests is seen by everybody.
  """
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshDataTable.Resource],
    primary_read_warning?: false

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :budget, :integer, public?: true
    attribute :lead_id, :integer, public?: true
    attribute :league_id, :uuid, public?: true
  end

  relationships do
    has_many :members, AshDataTable.Test.Exposing.Member, destination_attribute: :team_id
    has_many :guests, AshDataTable.Test.Exposing.Guest, destination_attribute: :team_id
  end

  aggregates do
    count :headcount, :members, public?: true
    count :guest_count, :guests, public?: true
  end

  calculations do
    calculate :loud_name, :string, expr(name <> "!"), public?: true
  end

  actions do
    read :read do
      primary? true
      pagination offset?: true, default_limit: 10, countable: true, required?: false
    end

    # the same records in full
    read :all
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  field_policies do
    field_policy [:headcount, :budget] do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if expr(lead_id == ^actor(:id))
    end

    field_policy :* do
      authorize_if always()
    end
  end

  table do
    column :name
    column :headcount
    column :guest_count
    column :loud_name
  end
end

defmodule AshDataTable.Test.Exposing.League do
  @moduledoc "A league, whose rows expand into its teams: in pages, and in full."
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end

  relationships do
    has_many :teams, AshDataTable.Test.Exposing.Team, public?: true

    has_many :all_teams, AshDataTable.Test.Exposing.Team do
      read_action :all
      public? true
    end

    has_many :guests, AshDataTable.Test.Exposing.Guest,
      destination_attribute: :team_id,
      public?: true
  end

  actions do
    defaults [:read]
  end
end
