defmodule Demo.Tracker.TaskCheck do
  @moduledoc "What has been done to a task besides the work itself. A task has any number of them."
  use Ash.Type.Enum,
    values: [
      reviewed: [label: "Reviewed", description: "Somebody else has read it."],
      tested: [label: "Tested"],
      documented: [label: "Documented"],
      released: [label: "Released", description: "It is out."]
    ]
end
