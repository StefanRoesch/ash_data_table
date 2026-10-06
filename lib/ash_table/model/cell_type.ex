defmodule AshTable.Model.CellType do
  @moduledoc false
  # Our own classification of an Ash type into the cell type a table shows and
  # (later) edits and filters it as. `Ash.Info.Manifest` is not consulted at
  # runtime (ADR 0001); the test suite compares this module's answers with it.

  @type t :: :text | :number | :boolean | :date | :datetime | :enum | :other

  @typedoc "The values of an enum cell with their labels, in declared order."
  @type values :: [{atom | String.t(), String.t()}]

  @builtin %{
    Ash.Type.String => :text,
    Ash.Type.CiString => :text,
    Ash.Type.Integer => :number,
    Ash.Type.Float => :number,
    Ash.Type.Decimal => :number,
    Ash.Type.Boolean => :boolean,
    Ash.Type.Date => :date,
    Ash.Type.DateTime => :datetime,
    Ash.Type.UtcDatetime => :datetime,
    Ash.Type.UtcDatetimeUsec => :datetime,
    Ash.Type.NaiveDatetime => :datetime
  }

  @doc "The cell type of a field of a resource: an attribute, calculation or aggregate."
  @spec of(Ash.Resource.t(), struct) :: {t, values | nil}
  def of(resource, field) do
    {type, constraints} = type(resource, field)
    classify(type, constraints)
  end

  @doc "The Ash type of a field with its constraints."
  @spec type(Ash.Resource.t(), struct) :: {Ash.Type.t() | nil, keyword}
  # An aggregate has no type of its own: it follows from its kind and the
  # field it aggregates.
  def type(resource, %Ash.Resource.Aggregate{} = aggregate) do
    case Ash.Resource.Info.aggregate_type(resource, aggregate) do
      {:ok, type} -> {type, []}
      {:error, _reason} -> {nil, []}
    end
  end

  def type(_resource, field), do: {field.type, field.constraints || []}

  @doc """
  Classifies an Ash type with its constraints.

  Returns the cell type and, for `:enum`, the values with their labels.
  Everything a table has no dedicated cell for is `:other`: arrays, maps,
  embedded resources, unions, keys, times, durations and so on.
  """
  @spec classify(Ash.Type.t(), keyword) :: {t, values | nil}
  def classify({:array, _type}, _constraints), do: {:other, nil}

  def classify(type, constraints) do
    type = Ash.Type.get_type(type)

    cond do
      # Before NewTypes are unwrapped: built-in types such as
      # `Ash.Type.UtcDatetime` are themselves NewTypes.
      cell_type = @builtin[type] ->
        {cell_type, nil}

      enum?(type) ->
        {:enum, Enum.map(type.values(), &{&1, type.label(&1) || humanize(&1)})}

      type == Ash.Type.Atom ->
        case constraints[:one_of] do
          [_ | _] = values -> {:enum, Enum.map(values, &{&1, humanize(&1)})}
          _ -> {:other, nil}
        end

      Ash.Type.NewType.new_type?(type) ->
        classify(type.subtype_of(), Ash.Type.NewType.constraints(type, constraints))

      true ->
        {:other, nil}
    end
  end

  defp enum?(type), do: Spark.implements_behaviour?(type, Ash.Type.Enum)

  defp humanize(value) do
    value |> to_string() |> String.replace("_", " ") |> String.capitalize()
  end
end
