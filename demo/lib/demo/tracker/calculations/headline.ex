defmodule Demo.Tracker.Calculations.Headline do
  @moduledoc """
  A module calculation: one line describing a task. It is computed in Elixir,
  so the data layer can neither sort nor filter by it.
  """
  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:title, :priority, :progress]

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn task ->
      "#{Demo.Tracker.TaskPriority.label(task.priority)}: #{task.title} (#{task.progress}%)"
    end)
  end
end
