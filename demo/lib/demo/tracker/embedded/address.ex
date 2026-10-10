defmodule Demo.Tracker.Address do
  @moduledoc "A postal address: an embedded resource, held inside a client."
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :street, :string, allow_nil?: false, public?: true
    attribute :city, :string, allow_nil?: false, public?: true

    attribute :postcode, :string do
      public? true
      constraints match: ~r/^\d{5}$/
    end
  end
end
