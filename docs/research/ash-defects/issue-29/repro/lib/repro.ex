defmodule Repro.Domain do
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    allow_unregistered? true
  end
end

# Control: identical to Repro.WithFlag except for the flag.
defmodule Repro.Plain do
  use Ash.Resource, domain: Repro.Domain, data_layer: Ash.DataLayer.Ets

  attributes do
    uuid_primary_key :id
    attribute :code, :string, public?: true
  end

  actions do
    defaults [:read]
  end
end

defmodule Repro.NotFilterable do
  use Ash.Resource, domain: Repro.Domain, data_layer: Ash.DataLayer.Ets

  attributes do
    uuid_primary_key :id
    attribute :code, :string, public?: true, filterable?: false
  end

  actions do
    defaults [:read]
  end
end

defmodule Repro.WithFlag do
  use Ash.Resource, domain: Repro.Domain, data_layer: Ash.DataLayer.Ets

  attributes do
    uuid_primary_key :id
    attribute :code, :string, public?: true, filterable?: :simple_equality
  end

  actions do
    defaults [:read, create: [:code]]
  end
end

defmodule Repro.IntFlag do
  use Ash.Resource, domain: Repro.Domain, data_layer: Ash.DataLayer.Ets

  attributes do
    uuid_primary_key :id
    attribute :n, :integer, public?: true, filterable?: :simple_equality
  end

  actions do
    defaults [:read]
  end
end

defmodule Repro.CalcFlag do
  use Ash.Resource, domain: Repro.Domain, data_layer: Ash.DataLayer.Ets

  attributes do
    uuid_primary_key :id
    attribute :code, :string, public?: true
  end

  calculations do
    calculate :upper, :string, expr(code <> "!"), public?: true, filterable?: :simple_equality
  end

  actions do
    defaults [:read]
  end
end

defmodule Repro.Child do
  use Ash.Resource, domain: Repro.Domain, data_layer: Ash.DataLayer.Ets

  attributes do
    uuid_primary_key :id
  end

  relationships do
    belongs_to :parent, Repro.AggFlag, public?: true
  end

  actions do
    defaults [:read]
  end
end

defmodule Repro.AggFlag do
  use Ash.Resource, domain: Repro.Domain, data_layer: Ash.DataLayer.Ets

  attributes do
    uuid_primary_key :id
  end

  relationships do
    has_many :children, Repro.Child, destination_attribute: :parent_id, public?: true
  end

  aggregates do
    count :child_count, :children, public?: true, filterable?: :simple_equality
  end

  actions do
    defaults [:read]
  end
end

# No data layer given (Ash.DataLayer.Simple).
defmodule Repro.SimpleDL do
  use Ash.Resource, domain: Repro.Domain

  attributes do
    uuid_primary_key :id
    attribute :code, :string, public?: true, filterable?: :simple_equality
  end

  actions do
    defaults [:read]
  end
end
