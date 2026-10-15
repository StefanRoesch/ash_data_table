defmodule AshDataTable.Format do
  @moduledoc false
  # How a cell's value is shown: one clause of `format/2` per cell type.
  # Text, numbers, dates and datetimes are shown in the format of the matching
  # native HTML input, so what a cell shows is what its editor holds
  # (`AshDataTable.Typed.of/3`). An array is its values, each as its own cell type shows it.
  # A map cell (an embedded resource, a map) is its fields on one line,
  # `field: value, field: value`, each value as its own cell type shows it.
  # A union is the value it holds, shown as its kind's type is shown.
  # A field of a map cell that its embedded resource declares `sensitive?`
  # is a mask (`AshDataTable.Sensitive`).
  # Nothing is parsed here: what a person types goes to the resource's action
  # as typed, but for a wall time, which `AshDataTable.Zone` gives as its instant.
  #
  # Every function takes the zone of the page (`AshDataTable.Zone`): a datetime
  # that is an instant (a `DateTime`) is shown as the clocks of that zone
  # show it, without the zone, which the page states once if it wants to. A
  # naive datetime has no zone and is shown as it is.

  alias AshDataTable.Model
  alias AshDataTable.Model.Column
  alias AshDataTable.Present
  alias AshDataTable.Resource.Embedding
  alias AshDataTable.Resource.Exposing
  alias AshDataTable.Sensitive
  alias AshDataTable.Text
  alias AshDataTable.Zone

  @utc Zone.utc()

  @doc """
  The text shown for `value` in a cell of `column`.

  For a boolean it is the accessible text ("Yes" or "No"); the check indicator
  is markup and belongs to the component. Nil is empty. A datetime that is
  an instant is shown in `zone`, the time zone of the page; `format/2` in
  UTC.
  """
  @spec format(Column.t() | AshDataTable.Model.Input.t(), term) :: String.t()
  def format(column, value), do: format(column, value, @utc)

  @spec format(Column.t() | AshDataTable.Model.Input.t(), term, Zone.t()) :: String.t()
  def format(_column, nil, _zone), do: ""
  # A field the actor may not see has a placeholder, which is markup and
  # belongs to the component.
  def format(_column, %Ash.ForbiddenField{}, _zone), do: ""
  def format(_column, %Ash.NotLoaded{}, _zone), do: ""
  # what a table keeps in place of a sensitive value: never the value
  def format(_column, %Sensitive.Masked{}, _zone), do: Present.mask()

  def format(%{cell_type: :text}, value, _zone), do: to_string(value)

  def format(%{cell_type: :number}, %Decimal{} = value, _zone),
    do: Decimal.to_string(value, :normal)

  def format(%{cell_type: :number}, value, _zone), do: to_string(value)

  def format(%{cell_type: :boolean}, true, _zone), do: Text.t(:yes)
  def format(%{cell_type: :boolean}, false, _zone), do: Text.t(:no)

  def format(%{cell_type: :date}, %Date{} = value, _zone), do: Date.to_iso8601(value)

  # an instant as the clocks of the page's zone show it
  def format(%{cell_type: :datetime}, %DateTime{} = value, zone),
    do: value |> Zone.local(zone) |> Calendar.strftime("%Y-%m-%dT%H:%M:%S")

  def format(%{cell_type: :datetime}, %NaiveDateTime{} = value, _zone),
    do: Calendar.strftime(value, "%Y-%m-%dT%H:%M:%S")

  def format(%{cell_type: :enum, values: values}, value, zone) do
    case List.keyfind(values || [], value, 0) do
      {_value, label} -> label
      nil -> other(value, zone)
    end
  end

  # A value of named fields: those that hold something, in their order,
  # each called what a column of that name is called. Plain text, with
  # nothing around it; a field that is itself such a value follows its name
  # the same way.
  def format(%{cell_type: :map} = field, value, zone) when is_map(value) do
    parts =
      case fields(field, value) do
        nil ->
          for {key, held} <- undeclared(value), text = other(held, zone), text != "" do
            {Text.label(AshDataTable.Resource.Words.humanize(key)), text}
          end

        fields ->
          # not the key Ash tells the values of an array apart by, when
          # nobody gives it: it says which value this is, not what it holds
          for %{name: name, label: label, key?: false} = inner <- fields,
              text = shown(inner, held(value, name), zone),
              text != "" do
            {label, text}
          end
      end

    Enum.map_join(parts, ", ", fn {label, text} ->
      Text.t(:field_value, field: label, value: text)
    end)
  end

  # A union is shown as the value it holds, as a value of that kind's type
  # is shown: a number as a number, a value made of fields as its one line.
  # Nothing says which kind it is.
  def format(%{cell_type: :union} = field, %Ash.Union{type: kind, value: value}, zone) do
    case Enum.find(members(field) || [], &(&1.name == kind)) do
      nil -> other(value, zone)
      member -> format(member, value, zone)
    end
  end

  # the values of an array of unions, set apart as those of an array of
  # values made of fields are: one of them may be such a value
  def format(%{cell_type: {:array, :union}} = column, values, zone) when is_list(values) do
    column = %{cell_type: :union, members: members(column) || []}

    values
    |> Enum.map(&format(column, &1, zone))
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("; ")
  end

  # the values of an array, each as a cell of its type shows it; values
  # that are made of fields themselves are set apart from each other
  def format(%{cell_type: {:array, :map}} = column, values, zone) when is_list(values) do
    values
    |> Enum.map(&format(%{column | cell_type: :map}, &1, zone))
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("; ")
  end

  def format(%{cell_type: {:array, item}} = column, values, zone) when is_list(values),
    do: Enum.map_join(values, ", ", &format(%{column | cell_type: item}, &1, zone))

  def format(%{cell_type: _}, value, zone), do: other(value, zone)

  @doc """
  The text shown for the summary of `column`, of the kind its `summary`
  says: a sum, a minimum and a maximum as a cell of the column shows a
  value, a count as a whole number, and an average as a number with two
  decimal places at most. Nil, the summary of no values, is empty.
  """
  @spec summary(Column.t(), term) :: String.t()
  # in UTC
  def summary(column, value), do: summary(column, value, @utc)

  @spec summary(Column.t(), term, Zone.t()) :: String.t()
  def summary(_column, nil, _zone), do: ""

  def summary(%{summary: :count}, value, _zone) when is_integer(value),
    do: Integer.to_string(value)

  def summary(%{summary: :avg}, %Decimal{} = value, zone),
    do: format(%{cell_type: :number}, value |> Decimal.round(2) |> Decimal.normalize(), zone)

  def summary(%{summary: :avg}, value, zone) when is_float(value) do
    rounded = Float.round(value, 2)

    # a whole number without ".0"
    if rounded == Float.round(rounded),
      do: Integer.to_string(round(rounded)),
      else: format(%{cell_type: :number}, rounded, zone)
  end

  def summary(%{summary: :avg}, value, _zone) when is_integer(value),
    do: Integer.to_string(value)

  def summary(column, value, zone), do: format(column, value, zone)

  # A field of such a value that is declared `sensitive?` is a mask where it
  # holds something, the same for every value, and nothing where it does
  # not: the line says that there is a value, never which.
  defp shown(%{sensitive?: true} = inner, held, zone) do
    cond do
      is_struct(held, Ash.ForbiddenField) -> format(inner, held, zone)
      Exposing.empty?(held) -> ""
      true -> Present.mask()
    end
  end

  defp shown(inner, held, zone), do: format(inner, held, zone)

  # The fields of a map cell: those its column or field says, else those of
  # its type. An embedded resource that holds a value of its own type is
  # looked at when it is shown, one value at a time. Nil for a map that
  # declares none.
  defp fields(%{fields: [_ | _] = fields}, _value), do: fields

  defp fields(%{type: {type, constraints}}, _value) when not is_nil(type) do
    case Embedding.of(type, constraints) do
      %{fields: [_ | _] = fields} ->
        Enum.map(Model.Field.from(fields), &%{&1 | label: Text.label(&1.label)})

      _none ->
        nil
    end
  end

  defp fields(_field, _value), do: nil

  # The kinds of a union: those its column or field says, else those of its
  # type.
  defp members(%{members: [_ | _] = members}), do: members

  defp members(%{type: {type, constraints}}) when not is_nil(type) do
    case Embedding.of(type, constraints) do
      %{members: [_ | _] = members} ->
        Enum.map(Model.Field.from(members), &%{&1 | label: Text.label(&1.label)})

      _none ->
        nil
    end
  end

  defp members(_field), do: nil

  # What a value holds for a field: a map that declares its fields has them
  # by name, and one that was not cast by text.
  defp held(value, name) do
    case Map.fetch(value, name) do
      {:ok, held} -> held
      :error -> Map.get(value, Atom.to_string(name))
    end
  end

  # What a map that declares no fields holds, by key. Never the fields of a
  # struct: what a table shows of one is said by its type.
  defp undeclared(%_{}), do: []
  defp undeclared(value), do: Enum.sort_by(value, fn {key, _held} -> to_string(key) end)

  # Read-only text for everything without a cell type of its own.
  defp other(nil, _zone), do: ""

  defp other(value, _zone) when is_binary(value) do
    if String.valid?(value), do: value, else: inspect(value)
  end

  defp other(value, _zone) when is_number(value), do: to_string(value)

  # A module is shown as it is written, without the `Elixir.` of its atom.
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
  # datetime cell shows it. (In UTC it is the text of the struct, as it was
  # before there were zones.)
  defp other(%DateTime{} = value, zone) when zone != @utc,
    do: format(%{cell_type: :datetime}, value, zone)

  defp other(%_{} = value, _zone) do
    if String.Chars.impl_for(value), do: to_string(value), else: inspect(value)
  end

  # a map inside a map that declares no fields: the same one line
  defp other(%{} = value, zone),
    do: format(%{cell_type: :map, fields: nil, type: {nil, []}}, value, zone)

  defp other(value, _zone), do: inspect(value)
end
