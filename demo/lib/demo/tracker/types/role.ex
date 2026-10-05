defmodule Demo.Tracker.Role do
  @moduledoc "What a user may do inside their organization."
  use Ash.Type.Enum,
    values: [
      admin: [label: "Admin", description: "May run every action."],
      member: [label: "Member", description: "May change tasks they are assigned to or reported."],
      viewer: [label: "Viewer", description: "May read, and nothing else."]
    ]
end
