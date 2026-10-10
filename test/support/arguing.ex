defmodule AshTable.Test.Arguing do
  @moduledoc """
  Resources for the tests of the argument line: a read action that takes
  arguments of every kind, and a calculation with arguments that is a column
  three times over.
  """

  @doc "A default of an asked argument that is a function of the page's assigns."
  def rate(assigns), do: Map.get(assigns, :rate, 5)

  @doc "The same as an MFA, which is called with the assigns before its own arguments."
  def rate(assigns, more), do: Map.get(assigns, :rate, 5) + more
end

defmodule AshTable.Test.Arguing.Priced do
  @moduledoc """
  `use AshTable.Test.Arguing.Priced` gives a resource a name, an amount, a
  count aggregate, and a calculation with three arguments: `rate`, which it
  cannot be computed without; `currency`, which has a default; and `places`,
  which may be empty and has none. For the tests of the `table` block.
  """

  defmacro __using__(_opts) do
    quote do
      use Ash.Resource,
        domain: AshTable.Test.Domain,
        data_layer: Ash.DataLayer.Ets,
        extensions: [AshTable.Resource]

      attributes do
        uuid_primary_key :id
        attribute :name, :string, public?: true
        attribute :amount, :integer, public?: true
        attribute :owner_id, :uuid, public?: true
      end

      relationships do
        has_many :comments, AshTable.Test.Comment, destination_attribute: :issue_id
      end

      aggregates do
        count :comment_count, :comments, public?: true
      end

      calculations do
        calculate :amount_in, :integer, expr(^ref(:amount) * ^arg(:rate)) do
          public? true

          argument :rate, :integer do
            allow_nil? false
            constraints min: 1
          end

          argument :currency, :atom do
            allow_nil? false
            constraints one_of: [:eur, :usd]
            default :eur
          end

          argument :places, :integer
          argument :shape, :map
        end
      end
    end
  end
end

defmodule AshTable.Test.Arguing.Kind do
  @moduledoc false
  use Ash.Type.Enum, values: [plain: [label: "Plain"], fancy: [label: "Fancy"]]
end

defmodule AshTable.Test.Arguing.Price do
  @moduledoc false
  use Ash.Resource,
    domain: AshTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTable.Resource]

  alias AshTable.Test.Arguing.Kind

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :amount, :integer, public?: true
    attribute :kind, Kind, public?: true
  end

  calculations do
    calculate :amount_in, :integer, expr(amount * ^arg(:rate)) do
      public? true

      argument :rate, :integer do
        allow_nil? false
        constraints min: 1
      end

      argument :currency, :atom do
        constraints one_of: [:eur, :usd]
        default :eur
      end
    end
  end

  actions do
    read :read do
      primary? true
    end

    create :create do
      primary? true
      accept [:name, :amount, :kind]
    end

    read :search do
      # may be left empty
      argument :term, :string
      # may not, and has no default: the table cannot read without it
      argument :at_least, :integer do
        allow_nil? false
        constraints min: 0
      end

      # a choice with a default
      argument :kind, Kind, default: :plain
      argument :strict?, :boolean
      argument :on, :date
      argument :names, {:array, :string}
      argument :kinds, {:array, Kind}
      # never given from the outside
      argument :secret, :string, public?: false
      # optional, and of a type the line has no input for: left out
      argument :where, :map

      filter expr(
               amount >= ^arg(:at_least) and
                 (is_nil(^arg(:term)) or contains(name, ^arg(:term))) and
                 (is_nil(^arg(:names)) or name in ^arg(:names)) and
                 (is_nil(^arg(:kinds)) or kind in ^arg(:kinds))
             )

      pagination offset?: true, countable: true, default_limit: 10, required?: false
      prepare build(sort: [name: :asc])
    end
  end

  table do
    read_action :search

    argument :term do
      label "Search for"
    end

    column :name
    column :amount

    # the argument that has no default is fixed; the other keeps its default
    column :amount_in do
      arguments rate: 2
    end

    # asked, with a value and with the default of the resource
    column :amount_in do
      as :amount_asked
      ask :rate, default: 3
      ask :currency
    end

    # fixed and asked, with a function of the page's assigns and a label
    column :amount_in do
      as :amount_fn
      label "Converted"
      arguments currency: :usd
      ask :rate, default: &AshTable.Test.Arguing.rate/1, label: "Exchange rate"
    end
  end
end

defmodule AshTable.Test.Arguing.Guarded do
  @moduledoc false
  # A calculation with an argument that only an admin sees, as a column
  # twice: each column, and what it asks for, goes with the field.
  use Ash.Resource,
    domain: AshTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTable.Resource]

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :amount, :integer, public?: true
  end

  calculations do
    calculate :amount_in, :integer, expr(amount * ^arg(:rate)) do
      public? true
      argument :rate, :integer, allow_nil?: false, default: 1
    end
  end

  actions do
    defaults [:read, create: [:name, :amount]]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  field_policies do
    field_policy :amount_in do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    field_policy :* do
      authorize_if always()
    end
  end

  table do
    column :name
    column :amount_in

    column :amount_in do
      as :amount_asked
      ask :rate
    end
  end
end
