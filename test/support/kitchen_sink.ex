defmodule AshTable.Test.Slug do
  @moduledoc "A NewType of a string."
  use Ash.Type.NewType, subtype_of: :string, constraints: [match: ~r/^[a-z0-9-]+$/]
end

defmodule AshTable.Test.Percentage do
  @moduledoc "A NewType of an integer."
  use Ash.Type.NewType, subtype_of: :integer, constraints: [min: 0, max: 100]
end

defmodule AshTable.Test.Priority do
  @moduledoc "A NewType of an atom limited to a set of values."
  use Ash.Type.NewType, subtype_of: :atom, constraints: [one_of: [:low, :high]]
end

defmodule AshTable.Test.Address do
  @moduledoc false
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :city, :string, public?: true
  end
end

defmodule AshTable.Test.KitchenSink do
  @moduledoc "One public attribute per type the table model classifies."
  use Ash.Resource,
    domain: AshTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :string, :string, public?: true
    attribute :ci_string, :ci_string, public?: true
    attribute :slug, AshTable.Test.Slug, public?: true
    attribute :integer, :integer, public?: true
    attribute :float, :float, public?: true
    attribute :decimal, :decimal, public?: true
    attribute :percentage, AshTable.Test.Percentage, public?: true
    attribute :boolean, :boolean, public?: true
    attribute :date, :date, public?: true
    attribute :datetime, :datetime, public?: true
    attribute :utc_datetime, :utc_datetime, public?: true
    attribute :utc_datetime_usec, :utc_datetime_usec, public?: true
    attribute :naive_datetime, :naive_datetime, public?: true
    attribute :status, AshTable.Test.Status, public?: true
    attribute :size, :atom, public?: true, constraints: [one_of: [:small, :extra_large]]
    attribute :priority, AshTable.Test.Priority, public?: true
    attribute :duration_unit, :duration_name, public?: true
    attribute :atom, :atom, public?: true
    attribute :uuid, :uuid, public?: true
    attribute :uuid_v7, :uuid_v7, public?: true
    attribute :time, :time, public?: true
    attribute :time_usec, :time_usec, public?: true
    attribute :duration, :duration, public?: true
    attribute :binary, :binary, public?: true
    attribute :map, :map, public?: true
    attribute :keyword, :keyword, public?: true, constraints: [fields: [a: [type: :string]]]
    attribute :tuple, :tuple, public?: true, constraints: [fields: [a: [type: :string]]]
    attribute :struct, :struct, public?: true
    attribute :term, :term, public?: true
    attribute :module, :module, public?: true
    attribute :address, AshTable.Test.Address, public?: true
    # arrays of values that have a cell type of their own
    attribute :strings, {:array, :string}, public?: true
    attribute :slugs, {:array, AshTable.Test.Slug}, public?: true
    attribute :integers, {:array, :integer}, public?: true
    attribute :decimals, {:array, :decimal}, public?: true
    attribute :booleans, {:array, :boolean}, public?: true
    attribute :dates, {:array, :date}, public?: true
    attribute :datetimes, {:array, :utc_datetime}, public?: true
    attribute :statuses, {:array, AshTable.Test.Status}, public?: true

    attribute :sizes, {:array, :atom},
      public?: true,
      constraints: [items: [one_of: [:small, :extra_large]]]

    attribute :priorities, {:array, AshTable.Test.Priority}, public?: true
    # arrays of everything else
    attribute :atoms, {:array, :atom}, public?: true
    attribute :uuids, {:array, :uuid}, public?: true
    attribute :times, {:array, :time}, public?: true
    attribute :maps, {:array, :map}, public?: true
    attribute :addresses, {:array, AshTable.Test.Address}, public?: true
    attribute :lists, {:array, {:array, :string}}, public?: true

    attribute :unions, {:array, :union},
      public?: true,
      constraints: [items: [types: [text: [type: :string], number: [type: :integer]]]]

    attribute :union, :union,
      public?: true,
      constraints: [types: [text: [type: :string], number: [type: :integer]]]

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    defaults [:read]
  end
end
