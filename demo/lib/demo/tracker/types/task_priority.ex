defmodule Demo.Tracker.TaskPriority do
  @moduledoc false
  use Ash.Type.Enum,
    values: [
      low: [label: "Low"],
      medium: [label: "Medium"],
      high: [label: "High"],
      urgent: [label: "Urgent", description: "Drop everything."]
    ]
end
