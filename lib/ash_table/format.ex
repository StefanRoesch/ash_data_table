defmodule AshTable.Format do
  @moduledoc false
  # How a cell's value is shown: one clause of `format/2` per cell type.
  # Text, numbers, dates and datetimes are shown in the format of the matching
  # native HTML input. Parsing joins this module with inline editing.

  alias AshTable.Model.Column
  alias AshTable.Text

  @doc """
  The text shown for `value` in a cell of `column`.

  For a boolean it is the accessible text ("Yes" or "No"); the check indicator
  is markup and belongs to the component. Nil is empty.
  """
  @spec format(Column.t(), term) :: String.t()
  def format(_column, nil), do: ""
  # Slice 4 gives fields the actor may not see a placeholder of their own.
  def format(_column, %Ash.ForbiddenField{}), do: ""
  def format(_column, %Ash.NotLoaded{}), do: ""

  def format(%Column{cell_type: :text}, value), do: to_string(value)

  def format(%Column{cell_type: :number}, %Decimal{} = value),
    do: Decimal.to_string(value, :normal)

  def format(%Column{cell_type: :number}, value), do: to_string(value)

  def format(%Column{cell_type: :boolean}, true), do: Text.t(:yes)
  def format(%Column{cell_type: :boolean}, false), do: Text.t(:no)

  def format(%Column{cell_type: :date}, %Date{} = value), do: Date.to_iso8601(value)

  def format(%Column{cell_type: :datetime}, %struct{} = value)
      when struct in [DateTime, NaiveDateTime],
      do: Calendar.strftime(value, "%Y-%m-%dT%H:%M:%S")

  def format(%Column{cell_type: :enum, values: values}, value) do
    case List.keyfind(values || [], value, 0) do
      {_value, label} -> label
      nil -> other(value)
    end
  end

  def format(%Column{}, value), do: other(value)

  # Read-only text for everything without a cell type of its own.
  defp other(value) when is_binary(value) do
    if String.valid?(value), do: value, else: inspect(value)
  end

  defp other(value) when is_atom(value) or is_number(value), do: to_string(value)
  defp other(value) when is_list(value), do: Enum.map_join(value, ", ", &other/1)

  defp other(%_{} = value) do
    if String.Chars.impl_for(value), do: to_string(value), else: inspect(value)
  end

  defp other(value), do: inspect(value)
end
