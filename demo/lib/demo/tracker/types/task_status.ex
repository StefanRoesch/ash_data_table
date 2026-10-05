defmodule Demo.Tracker.TaskStatus do
  @moduledoc false
  use Ash.Type.Enum,
    values: [
      backlog: [label: "Backlog", description: "Not planned yet."],
      todo: [label: "To do", description: "Planned, not started."],
      in_progress: [label: "In progress", description: "Being worked on."],
      in_review: [label: "In review", description: "Waiting for a review."],
      done: [label: "Done", description: "Finished."],
      archived: [label: "Archived", description: "Put away; no longer open."]
    ]

  @doc "The statuses that count as open."
  def open, do: [:backlog, :todo, :in_progress, :in_review]
end
