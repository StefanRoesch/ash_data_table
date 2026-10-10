defmodule AshTable.Test.Limiting.Percent do
  @moduledoc "A type made of an integer, with the limits it gives it."
  use Ash.Type.NewType, subtype_of: :integer, constraints: [min: 0, max: 100]
end

defmodule AshTable.Test.Limiting.Place do
  @moduledoc "An embedded resource with a number that has limits."
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :street, :string, public?: true, constraints: [max_length: 40]
    attribute :floor, :integer, allow_nil?: false, public?: true, constraints: [min: -2, max: 40]
  end
end

defmodule AshTable.Test.Limiting do
  @moduledoc """
  A resource for the tests of what an input says of its limits before
  anything is saved (`AshTable.Model.Limits`): numbers of every type with
  the constraints Ash has for them, text with its own, values inside a map,
  an embedded resource, a union and an array, and actions that take the same
  field under other rules.
  """
  use Ash.Resource,
    domain: AshTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTable.Resource]

  alias AshTable.Test.Limiting.Percent
  alias AshTable.Test.Limiting.Place

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
      constraints min_length: 3, max_length: 20, match: ~r/^[a-z ]+$/
    end

    # may be empty on the resource; one action requires it
    attribute :note, :string, public?: true

    attribute :count, :integer, allow_nil?: false, public?: true, constraints: [min: 0, max: 10]
    attribute :ratio, :float, public?: true, constraints: [min: 0.0, max: 1.5]

    # bounds that exclude their own value
    attribute :open_ratio, :float, public?: true, constraints: [greater_than: 0.0, less_than: 1.0]
    attribute :price, :decimal, public?: true, constraints: [min: 0, max: Decimal.new("99.50")]
    # one bound that excludes its own value, and one that includes it
    attribute :above, :decimal, public?: true, constraints: [greater_than: 0, max: 5]
    # bounds a decimal can write with an exponent
    attribute :fine, :decimal,
      public?: true,
      constraints: [min: Decimal.new("0.0000001"), max: Decimal.new("1E+3")]

    attribute :free, :integer, public?: true
    attribute :percent, Percent, public?: true
    attribute :due_on, :date, public?: true

    attribute :scores, {:array, :integer},
      public?: true,
      constraints: [min_length: 1, max_length: 3, items: [min: 1, max: 5]]

    attribute :settings, :map do
      public? true

      constraints fields: [
                    every: [type: :integer, allow_nil?: false, constraints: [min: 1, max: 365]],
                    note: [type: :string, constraints: [max_length: 10]]
                  ]
    end

    attribute :place, Place, public?: true

    attribute :value, :union,
      public?: true,
      constraints: [
        types: [amount: [type: :integer, constraints: [min: 0]], text: [type: :string]]
      ]
  end

  calculations do
    calculate :count_times, :integer, expr(count * ^arg(:factor)) do
      public? true
      argument :factor, :integer, allow_nil?: false, constraints: [min: 1, max: 12]
    end
  end

  actions do
    defaults [:destroy]

    read :read do
      primary? true
    end

    read :search do
      argument :at_least, :integer, allow_nil?: false, default: 0, constraints: [min: 0, max: 9]
      argument :term, :string, constraints: [max_length: 5]
      argument :among, {:array, :integer}, constraints: [items: [min: 1, max: 5]]
      filter expr(count >= ^arg(:at_least))
    end

    create :create do
      primary? true
      accept [:title, :count, :note]
      # the attribute cannot be empty, and this action takes it empty
      allow_nil_input [:title]
    end

    update :update do
      primary? true
      require_atomic? false

      accept [
        :title,
        :note,
        :count,
        :ratio,
        :open_ratio,
        :price,
        :above,
        :fine,
        :free,
        :percent,
        :due_on,
        :scores,
        :settings,
        :place,
        :value
      ]
    end

    # the attribute may be empty, and this action requires it
    update :settle do
      accept [:note]
      require_attributes [:note]
    end

    # an argument of the attribute's name in all but its limits
    update :rate do
      accept [:count]
      argument :by, :integer, allow_nil?: false, constraints: [min: 5, max: 7]
      argument :share, :float, constraints: [greater_than: 0.0, max: 0.5]
      change atomic_update(:count, expr(count + ^arg(:by)))
    end
  end

  table do
    read_action :search
    update_action :update

    column :title

    column :note do
      update_action :settle
    end

    column :count
    column :ratio
    column :open_ratio
    column :price
    column :above
    column :fine
    column :free
    column :percent
    column :due_on
    column :scores
    column :settings
    column :place
    column :value

    column :count_times do
      ask :factor, default: 2
    end

    action :rate
    action :settle
    action :update
    create_action(:create)
  end
end

defmodule AshTable.Test.Limiting.Guarded do
  @moduledoc "A required attribute behind an update action that only an admin may run."
  use Ash.Resource,
    domain: AshTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
  end

  actions do
    defaults [:read, update: [:name]]
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action(:update) do
      authorize_if actor_attribute_equals(:role, :admin)
    end
  end

  table do
    update_action :update
    column :name
  end
end
