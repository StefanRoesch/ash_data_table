defmodule AshTable.Format do
  @moduledoc false
  # How a cell's value is shown: one clause of `format/2` per cell type.
  # Text, numbers, dates and datetimes are shown in the format of the matching
  # native HTML input, so what a cell shows is what its editor holds
  # (`input/2`). Nothing is parsed here: what a person types goes to the
  # resource's action as typed.

  alias AshTable.Model.Column
  alias AshTable.Text

  @doc """
  The text shown for `value` in a cell of `column`.

  For a boolean it is the accessible text ("Yes" or "No"); the check indicator
  is markup and belongs to the component. Nil is empty.
  """
  @spec format(Column.t() | AshTable.Model.Input.t(), term) :: String.t()
  def format(_column, nil), do: ""
  # A field the actor may not see has a placeholder, which is markup and
  # belongs to the component.
  def format(_column, %Ash.ForbiddenField{}), do: ""
  def format(_column, %Ash.NotLoaded{}), do: ""

  def format(%{cell_type: :text}, value), do: to_string(value)

  def format(%{cell_type: :number}, %Decimal{} = value),
    do: Decimal.to_string(value, :normal)

  def format(%{cell_type: :number}, value), do: to_string(value)

  def format(%{cell_type: :boolean}, true), do: Text.t(:yes)
  def format(%{cell_type: :boolean}, false), do: Text.t(:no)

  def format(%{cell_type: :date}, %Date{} = value), do: Date.to_iso8601(value)

  def format(%{cell_type: :datetime}, %struct{} = value)
      when struct in [DateTime, NaiveDateTime],
      do: Calendar.strftime(value, "%Y-%m-%dT%H:%M:%S")

  def format(%{cell_type: :enum, values: values}, value) do
    case List.keyfind(values || [], value, 0) do
      {_value, label} -> label
      nil -> other(value)
    end
  end

  def format(%{cell_type: _}, value), do: other(value)

  @doc """
  The text the editor of a cell holds for `value`: what the cell shows, the
  value itself for a choice, and `"true"` or `"false"` for a boolean. Nil is
  empty.
  """
  @spec input(Column.t() | AshTable.Model.Input.t(), term) :: String.t()
  def input(%{cell_type: :boolean}, value) when is_boolean(value), do: to_string(value)

  def input(%{cell_type: :enum}, value) when is_atom(value) and not is_nil(value),
    do: Atom.to_string(value)

  def input(%{cell_type: :enum}, value) when is_binary(value), do: value
  def input(%{cell_type: cell_type}, _value) when cell_type in [:boolean, :enum], do: ""
  def input(%{cell_type: _} = column, value), do: format(column, value)

  # Read-only text for everything without a cell type of its own.
  defp other(value) when is_binary(value) do
    if String.valid?(value), do: value, else: inspect(value)
  end

  defp other(value) when is_number(value), do: to_string(value)

  # A module is shown as it is written, without the `Elixir.` of its atom.
  defp other(value) when is_atom(value) do
    case Atom.to_string(value) do
      "Elixir." <> _ -> inspect(value)
      text -> text
    end
  end

  defp other(value) when is_list(value), do: Enum.map_join(value, ", ", &other/1)

  defp other(%_{} = value) do
    if String.Chars.impl_for(value), do: to_string(value), else: inspect(value)
  end

  defp other(value), do: inspect(value)
end
