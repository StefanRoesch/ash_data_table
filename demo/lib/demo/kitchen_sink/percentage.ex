defmodule Demo.KitchenSink.Percentage do
  @moduledoc "An `Ash.Type.NewType`: an integer from 0 to 100."
  use Ash.Type.NewType, subtype_of: :integer, constraints: [min: 0, max: 100]
end
