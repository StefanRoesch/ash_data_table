defmodule Demo.Support.Limits do
  @moduledoc """
  A domain for the tests of what an input says of its limits before
  anything is saved, where the demo has no such input: an array of numbers
  as an argument of a row action and of the read action, and numbers whose
  bounds exclude their own value. Its resource exists for the tests only
  and keeps its records in memory.
  """
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource Demo.Support.Limits.Meter
  end
end

defmodule Demo.Support.Limits.Meter do
  @moduledoc false
  use Ash.Resource,
    domain: Demo.Support.Limits,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTable.Resource]

  table do
    read_action :within
    column :name
    column :level
    action :tune
  end

  actions do
    defaults [:destroy, create: [:name, :level]]

    read :read do
      primary? true
    end

    read :within do
      # each value from 1 to 5
      argument :among, {:array, :integer}, constraints: [items: [min: 1, max: 5]]
      # more than 0, and 2.5 at most
      argument :over, :float, constraints: [greater_than: 0.0, max: 2.5]
      filter expr(is_nil(^arg(:among)) or level in ^arg(:among))
    end

    update :tune do
      accept [:marks]
      require_atomic? false
      # each value from 0 to 9
      argument :steps, {:array, :integer},
        allow_nil?: false,
        constraints: [items: [min: 0, max: 9]]

      # between 0 and 1, neither of them
      argument :share, :decimal, constraints: [greater_than: 0, less_than: 1]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :level, :integer, public?: true, constraints: [min: 0, max: 10]
    # each value from 1 to 6; the panel starts with those the record has
    attribute :marks, {:array, :integer}, public?: true, constraints: [items: [min: 1, max: 6]]
  end
end
