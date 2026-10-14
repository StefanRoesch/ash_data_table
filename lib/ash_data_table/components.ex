defmodule AshDataTable.Components do
  @moduledoc false
  # What the components that are shipped have in common:
  # `AshDataTable.Components.Badge`, `AshDataTable.Components.Image`,
  # `AshDataTable.Components.Progress` and `AshDataTable.Components.Slider`.

  @doc false
  # What a field of a cell type is shown as, in a sentence.
  def shown_as(:text), do: "text"
  def shown_as(:number), do: "a number"
  def shown_as(:boolean), do: "a boolean"
  def shown_as(:date), do: "a date"
  def shown_as(:datetime), do: "a date and time"
  def shown_as(:enum), do: "a choice"
  def shown_as({:array, _item}), do: "a list of values"
  def shown_as(:map), do: "a value made of fields"
  def shown_as(:union), do: "a value of one of several kinds"
  def shown_as(:other), do: "read-only text"
end
