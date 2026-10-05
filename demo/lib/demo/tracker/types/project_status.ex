defmodule Demo.Tracker.ProjectStatus do
  @moduledoc false
  use Ash.Type.Enum,
    values: [
      planned: [label: "Planned"],
      active: [label: "Active"],
      on_hold: [label: "On hold"],
      completed: [label: "Completed"]
    ]
end
