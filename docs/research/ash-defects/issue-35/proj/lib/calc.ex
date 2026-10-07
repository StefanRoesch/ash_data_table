defmodule Bug.TitleCalc do
  use Ash.Resource.Calculation
  def load(_, _, _), do: [:title]
  def calculate(records, _, _), do: Enum.map(records, &("T:" <> to_string(&1.title)))
end
