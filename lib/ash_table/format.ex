defmodule AshTable.Format do
  @moduledoc false
  # How a cell's value is shown: one clause of `format/2` per cell type.
  # Text, numbers, dates and datetimes are shown in the format of the matching
  # native HTML input, so what a cell shows is what its editor holds
  # (`input/2`). An array is its values, each as its own cell type shows it.
  # A map cell (an embedded resource, a map) is its fields on one line,
  # `field: value, field: value`, each value as its own cell type shows it.
  # A union is the value it holds, shown as its kind's type is shown.
  # A field of a map cell that its embedded resource declares `sensitive?`
  # is a mask (`AshTable.Sensitive`).
  # Nothing is parsed here: what a person types goes to the resource's action
  # as typed.

  alias AshTable.Model
  alias AshTable.Model.Column
  alias AshTable.Resource.Embedding
  alias AshTable.Sensitive
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
  # what a table keeps in place of a sensitive value: never the value
  def format(_column, %Sensitive.Masked{}), do: Sensitive.mask()

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

  # A value of named fields: those that hold something, in their order,
  # each called what a column of that name is called. Plain text, with
  # nothing around it; a field that is itself such a value follows its name
  # the same way.
  def format(%{cell_type: :map} = field, value) when is_map(value) do
    parts =
      case fields(field, value) do
        nil ->
          for {key, held} <- undeclared(value), text = other(held), text != "" do
            {Text.label(Model.humanize(key)), text}
          end

        fields ->
          # not the key Ash tells the values of an array apart by, when
          # nobody gives it: it says which value this is, not what it holds
          for %{name: name, label: label, key?: false} = inner <- fields,
              text = shown(inner, held(value, name)),
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
  def format(%{cell_type: :union} = field, %Ash.Union{type: kind, value: value}) do
    case Enum.find(members(field) || [], &(&1.name == kind)) do
      nil -> other(value)
      member -> format(member, value)
    end
  end

  # the values of an array of unions, set apart as those of an array of
  # values made of fields are: one of them may be such a value
  def format(%{cell_type: {:array, :union}} = column, values) when is_list(values) do
    column = %{cell_type: :union, members: members(column) || []}

    values
    |> Enum.map(&format(column, &1))
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("; ")
  end

  # the values of an array, each as a cell of its type shows it; values
  # that are made of fields themselves are set apart from each other
  def format(%{cell_type: {:array, :map}} = column, values) when is_list(values) do
    values
    |> Enum.map(&format(%{column | cell_type: :map}, &1))
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("; ")
  end

  def format(%{cell_type: {:array, item}} = column, values) when is_list(values),
    do: Enum.map_join(values, ", ", &format(%{column | cell_type: item}, &1))

  def format(%{cell_type: _}, value), do: other(value)

  @doc """
  The text shown for the summary of `column`, of the kind its `summary`
  says: a sum, a minimum and a maximum as a cell of the column shows a
  value, a count as a whole number, and an average as a number with two
  decimal places at most. Nil, the summary of no values, is empty.
  """
  @spec summary(Column.t(), term) :: String.t()
  def summary(_column, nil), do: ""
  def summary(%{summary: :count}, value) when is_integer(value), do: Integer.to_string(value)

  def summary(%{summary: :avg}, %Decimal{} = value),
    do: format(%{cell_type: :number}, value |> Decimal.round(2) |> Decimal.normalize())

  def summary(%{summary: :avg}, value) when is_float(value) do
    rounded = Float.round(value, 2)

    # a whole number without ".0"
    if rounded == Float.round(rounded),
      do: Integer.to_string(round(rounded)),
      else: format(%{cell_type: :number}, rounded)
  end

  def summary(%{summary: :avg}, value) when is_integer(value), do: Integer.to_string(value)
  def summary(column, value), do: format(column, value)

  @doc """
  The text the editor of a cell holds for `value`: what the cell shows, the
  value itself for a choice, and `"true"` or `"false"` for a boolean. Nil is
  empty.

  The editor of an array holds a list: the text of each of its values. Nil
  is the empty list there. A value that is text already is what a person
  typed, and is held as it is.
  """
  @spec input(Column.t() | AshTable.Model.Input.t() | Model.Field.t(), term) ::
          String.t() | [String.t()] | map | [map] | nil
  # The editor of a map cell holds its inputs by name, each as the editor of
  # its type holds it, and with them the primary key of an embedded resource
  # that is no input: Ash tells by it which value is which. Nil is no value.
  def input(%{cell_type: :map, fields: [_ | _] = fields}, value) when is_map(value) do
    for %{name: name} = inner <- fields, inner.input? or inner.key?, into: %{} do
      held = held(value, name)

      {Atom.to_string(name),
       if(inner.cell_type in [:map, :union],
         do: input(inner, held),
         else: input(inner, held) || ""
       )}
    end
  end

  def input(%{cell_type: :map}, _value), do: nil

  # The editor of a union holds the kind and that kind's value, as the
  # editor of its type holds it. Nil is no value, and so is a kind that
  # holds nothing: Ash keeps the kind of a value that was taken away.
  def input(%{cell_type: :union} = field, %Ash.Union{type: kind, value: value})
      when not is_nil(value) do
    case Enum.find(members(field) || [], &(&1.name == kind)) do
      nil ->
        nil

      member ->
        held = input(member, value)

        %{
          "_union_type" => Atom.to_string(kind),
          "_union_value" => if(member.cell_type == :map, do: held, else: held || "")
        }
    end
  end

  def input(%{cell_type: :union}, _value), do: nil

  def input(%{cell_type: {:array, :map}} = column, values) when is_list(values),
    do: Enum.map(values, &input(%{column | cell_type: :map}, &1))

  def input(%{cell_type: {:array, item}} = column, values) when is_list(values) do
    Enum.map(values, fn
      typed when is_binary(typed) -> typed
      value -> input(%{column | cell_type: item}, value)
    end)
  end

  def input(%{cell_type: {:array, _item}}, _value), do: []

  def input(%{cell_type: :boolean}, value) when is_boolean(value), do: to_string(value)

  def input(%{cell_type: :enum}, value) when is_atom(value) and not is_nil(value),
    do: Atom.to_string(value)

  def input(%{cell_type: :enum}, value) when is_binary(value), do: value
  def input(%{cell_type: cell_type}, _value) when cell_type in [:boolean, :enum], do: ""
  def input(%{cell_type: _} = column, value), do: format(column, value)

  # A field of such a value that is declared `sensitive?` is a mask where it
  # holds something, the same for every value, and nothing where it does
  # not: the line says that there is a value, never which.
  defp shown(%{sensitive?: true} = inner, held) do
    cond do
      is_struct(held, Ash.ForbiddenField) -> format(inner, held)
      Sensitive.empty?(held) -> ""
      true -> Sensitive.mask()
    end
  end

  defp shown(inner, held), do: format(inner, held)

  # The fields of a map cell: those its column or field says, else those of
  # its type. An embedded resource that holds a value of its own type is
  # looked at when it is shown, one value at a time. Nil for a map that
  # declares none.
  defp fields(%{fields: [_ | _] = fields}, _value), do: fields

  defp fields(%{type: {type, constraints}}, _value) when not is_nil(type) do
    case Embedding.of(type, constraints) do
      %{fields: [_ | _] = fields} -> Enum.map(fields, &%{&1 | label: Text.label(&1.label)})
      _none -> nil
    end
  end

  defp fields(_field, _value), do: nil

  # The kinds of a union: those its column or field says, else those of its
  # type.
  defp members(%{members: [_ | _] = members}), do: members

  defp members(%{type: {type, constraints}}) when not is_nil(type) do
    case Embedding.of(type, constraints) do
      %{members: [_ | _] = members} -> Enum.map(members, &%{&1 | label: Text.label(&1.label)})
      _none -> nil
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
  defp other(nil), do: ""

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

  # a union whose kinds are not known here: the value it holds
  defp other(%Ash.Union{value: value}), do: other(value)

  defp other(%_{} = value) do
    if String.Chars.impl_for(value), do: to_string(value), else: inspect(value)
  end

  # a map inside a map that declares no fields: the same one line
  defp other(%{} = value), do: format(%{cell_type: :map, fields: nil, type: {nil, []}}, value)

  defp other(value), do: inspect(value)
end
