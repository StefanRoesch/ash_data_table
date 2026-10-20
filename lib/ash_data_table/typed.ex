defmodule AshDataTable.Typed do
  @moduledoc false
  # A value as the control of its type holds it, and as a person types it:
  # the text of a text, a number, a date or a datetime as the matching
  # native HTML input writes it, the value itself for a choice, `"true"` or
  # `"false"` for a boolean. An array is a list of such texts. What the form
  # holds for a value made of fields (a map cell, a list of them, a union)
  # is `AshDataTable.GroupValue.held/3`'s, which asks this module for the
  # text of each value in it.
  #
  # It is never a translation: the same in every locale, so that what a
  # person typed is told from what a field holds by comparing texts
  # (`AshDataTable.State`, `AshDataTable.Act`, `AshDataTable.Edit`), and a
  # control holds what a cell of its type shows (`AshDataTable.Format`).
  #
  # A datetime that is an instant (a `DateTime`) is written as the clocks of
  # the page's zone show it (`AshDataTable.Zone`); a naive one as it is.

  alias AshDataTable.Present
  alias AshDataTable.Sensitive
  alias AshDataTable.Zone

  @doc """
  The text the control of `field` (a column, an input, a field of a map
  cell) holds for `value`. Nil is empty.

  The control of an array holds a list: the text of each of its values. Nil
  is the empty list there. A value that is text already is what a person
  typed, and is held as it is. `of/2` writes an instant in UTC.
  """
  @spec of(map, term) :: String.t() | [String.t()]
  def of(field, value), do: of(field, value, Zone.utc())

  @spec of(map, term, Zone.t()) :: String.t() | [String.t()]
  def of(%{cell_type: {:array, item}} = field, values, zone) when is_list(values) do
    Enum.map(values, fn
      typed when is_binary(typed) -> typed
      value -> of(%{field | cell_type: item}, value, zone)
    end)
  end

  def of(%{cell_type: {:array, _item}}, _value, _zone), do: []

  def of(%{cell_type: :boolean}, value, _zone) when is_boolean(value), do: to_string(value)

  def of(%{cell_type: :enum}, value, _zone) when is_atom(value) and not is_nil(value),
    do: Atom.to_string(value)

  def of(%{cell_type: :enum}, value, _zone) when is_binary(value), do: value
  def of(%{cell_type: cell_type}, _value, _zone) when cell_type in [:boolean, :enum], do: ""
  def of(%{cell_type: _} = field, value, zone), do: written(field, value, zone)

  # A value of a type without a control of its own, as a cell shows it: a
  # text, a number, a date or a datetime is written as its native input
  # writes it.
  defp written(_field, nil, _zone), do: ""
  defp written(_field, %Ash.ForbiddenField{}, _zone), do: ""
  defp written(_field, %Ash.NotLoaded{}, _zone), do: ""
  # what a table keeps in place of a sensitive value: never the value
  defp written(_field, %Sensitive.Masked{}, _zone), do: Present.mask()
  defp written(%{cell_type: :text}, value, _zone), do: to_string(value)

  defp written(%{cell_type: :number}, %Decimal{} = value, _zone),
    do: Decimal.to_string(value, :normal)

  defp written(%{cell_type: :number}, value, _zone), do: to_string(value)
  defp written(%{cell_type: :date}, %Date{} = value, _zone), do: Date.to_iso8601(value)

  # an instant as the clocks of the page's zone show it
  defp written(%{cell_type: :datetime}, %DateTime{} = value, zone),
    do: value |> Zone.local(zone) |> Calendar.strftime("%Y-%m-%dT%H:%M:%S")

  defp written(%{cell_type: :datetime}, %NaiveDateTime{} = value, _zone),
    do: Calendar.strftime(value, "%Y-%m-%dT%H:%M:%S")

  defp written(_field, value, zone), do: other(value, zone)

  # Text for everything without a cell type of its own.
  defp other(nil, _zone), do: ""

  defp other(value, _zone) when is_binary(value) do
    if String.valid?(value), do: value, else: inspect(value)
  end

  defp other(value, _zone) when is_number(value), do: to_string(value)

  # A module is written as it is written, without the `Elixir.` of its atom.
  defp other(value, _zone) when is_atom(value) do
    case Atom.to_string(value) do
      "Elixir." <> _ -> inspect(value)
      text -> text
    end
  end

  defp other(value, zone) when is_list(value), do: Enum.map_join(value, ", ", &other(&1, zone))

  # a union whose kinds are not known here: the value it holds
  defp other(%Ash.Union{value: value}, zone), do: other(value, zone)

  # An instant without a type that says so, in a zone other than UTC: as a
  # datetime is written. (In UTC it is the text of the struct.)
  defp other(%DateTime{} = value, zone) do
    if zone == Zone.utc(),
      do: to_string(value),
      else: written(%{cell_type: :datetime}, value, zone)
  end

  defp other(%_{} = value, _zone) do
    if String.Chars.impl_for(value), do: to_string(value), else: inspect(value)
  end

  # A map that declares no fields: its keys that hold something, each with
  # its value, on one line. The names as they are written: nothing here is
  # translated.
  defp other(%{} = value, zone) do
    value
    |> Enum.sort_by(fn {key, _held} -> to_string(key) end)
    |> Enum.flat_map(fn {key, held} ->
      case other(held, zone) do
        "" -> []
        text -> ["#{AshDataTable.Resource.Words.humanize(key)}: #{text}"]
      end
    end)
    |> Enum.join(", ")
  end

  defp other(value, _zone), do: inspect(value)
end
