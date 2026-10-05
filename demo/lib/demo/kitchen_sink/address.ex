defmodule Demo.KitchenSink.Address do
  @moduledoc "An embedded resource."
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :street, :string, allow_nil?: false, public?: true
    attribute :city, :string, allow_nil?: false, public?: true
    attribute :postcode, :string, public?: true
    attribute :primary?, :boolean, default: false, public?: true
  end
end
