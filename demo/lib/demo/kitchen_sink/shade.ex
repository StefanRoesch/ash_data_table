defmodule Demo.KitchenSink.Shade do
  @moduledoc "An `Ash.Type.Enum` with labels and descriptions."
  use Ash.Type.Enum,
    values: [
      light: [label: "Light", description: "Barely there."],
      medium: [label: "Medium"],
      dark: [label: "Dark", description: "Almost black."]
    ]
end
