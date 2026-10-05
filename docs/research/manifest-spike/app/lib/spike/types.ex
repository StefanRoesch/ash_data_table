defmodule Spike.Types.Status do
  use Ash.Type.Enum,
    values: [
      draft: [label: "Draft", description: "Not yet visible"],
      active: [label: "On sale", description: "Visible in the shop"],
      retired: "No longer sold"
    ]
end

defmodule Spike.Types.Sku do
  use Ash.Type.NewType,
    subtype_of: :string,
    constraints: [min_length: 4, max_length: 12, match: ~r/^[A-Z0-9-]+$/]
end

defmodule Spike.Types.Dimensions do
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :width_mm, :integer, public?: true, constraints: [min: 0]
    attribute :height_mm, :integer, public?: true, constraints: [min: 0]
    attribute :unit_note, :string, public?: true
  end
end
