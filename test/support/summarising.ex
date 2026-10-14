defmodule AshDataTable.Test.Summarising do
  @moduledoc """
  Resources for the tests of footer summaries: what a summary is over, and
  what it must not say to a person.

  The actors of these tests are maps: `%{name: "ann"}`.
  """
end

defmodule AshDataTable.Test.Summarising.Project do
  @moduledoc "The parent of tickets: its table nests them."
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end

  relationships do
    has_many :tickets, AshDataTable.Test.Summarising.Ticket, public?: true
  end

  actions do
    defaults [:read, create: :*]
  end

  table do
    column :name

    relationship :tickets
  end
end

defmodule AshDataTable.Test.Summarising.Ticket do
  @moduledoc """
  Tickets with a row policy and two field policies that depend on the read
  action:

    * a `private` ticket is read by its owner only;
    * `hours` is seen on every ticket through `:read`, the primary read
      action, and on a person's own tickets only through `:board` and
      `:longer`;
    * `cost` is the other way round: on a person's own tickets only through
      `:read`, on every ticket through `:board` and `:longer`;
    * `rate` is never seen by a guest.

  The default table reads through `:board`, the table `:primary` through
  `:read`, and the table `:longer` through an action with an argument.
  """
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshDataTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :hours, :integer, public?: true
    attribute :cost, :integer, public?: true
    attribute :rate, :decimal, public?: true
    attribute :due_on, :date, public?: true
    attribute :owner, :string, public?: true
    attribute :private, :boolean, public?: true, default: false
  end

  relationships do
    belongs_to :project, AshDataTable.Test.Summarising.Project, public?: true
  end

  actions do
    read :read do
      primary? true
      pagination offset?: true, default_limit: 2, countable: true, required?: false
    end

    read :board do
      pagination offset?: true, default_limit: 2, countable: true, required?: false
    end

    read :longer do
      argument :min, :integer, allow_nil?: false
      filter expr(hours >= ^arg(:min))
      pagination offset?: true, default_limit: 2, countable: true, required?: false
    end

    create :create do
      primary? true
      accept [:title, :hours, :cost, :rate, :due_on, :owner, :private, :project_id]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(private == false)
      authorize_if expr(owner == ^actor(:name))
    end

    policy action_type(:create) do
      authorize_if always()
    end
  end

  field_policies do
    field_policy :hours, action(:read) do
      authorize_if always()
    end

    field_policy :hours, action([:board, :longer]) do
      authorize_if expr(owner == ^actor(:name))
    end

    field_policy :cost, action(:read) do
      authorize_if expr(owner == ^actor(:name))
    end

    field_policy :cost, action([:board, :longer]) do
      authorize_if always()
    end

    field_policy :rate do
      forbid_if actor_attribute_equals(:role, :guest)
      authorize_if always()
    end

    field_policy :* do
      authorize_if always()
    end
  end

  table do
    read_action :board

    column :title do
      summary :count
    end

    column :hours do
      summary :sum
    end

    column :cost do
      summary :max
    end

    column :rate do
      summary :avg
    end

    column :due_on do
      summary :min
    end

    column :owner
  end

  tables do
    table :primary do
      column :title

      column :hours do
        summary :sum
      end

      column :cost do
        summary :sum
      end
    end

    table :longer do
      read_action :longer

      column :title

      column :cost do
        summary :sum
      end
    end

    table :plain do
      column :title
      column :hours
    end
  end
end

defmodule AshDataTable.Test.Summarising.Entry do
  @moduledoc "Entries of several organisations: a tenant reads its own."
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource]

  multitenancy do
    strategy :attribute
    attribute :org
  end

  attributes do
    uuid_primary_key :id
    attribute :org, :string, public?: true
    attribute :amount, :integer, public?: true
  end

  actions do
    defaults [:read, create: :*]
  end

  table do
    column :amount do
      summary :sum
    end
  end
end
