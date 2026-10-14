defmodule DemoWeb.Cells.Progress do
  @moduledoc """
  How the demo shows and edits a task's progress: two of the components that
  `ash_data_table` ships, put together. A column names one module, so a module
  that takes its two parts from two others is how they are combined.
  """
  use AshDataTable.Component, commit: :change

  # a bar with the number beside it
  defdelegate cell(assigns), to: AshDataTable.Components.Progress
  # a slider, which saves when it is let go
  defdelegate editor(assigns), to: AshDataTable.Components.Slider
  # both need the same of a field: a number with a minimum and a maximum
  defdelegate verify(column), to: AshDataTable.Components.Slider
end
