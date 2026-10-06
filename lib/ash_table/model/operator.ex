defmodule AshTable.Model.Operator do
  @moduledoc false
  # The filter operators a table offers for a field, and what each of them is
  # in Ash. Shared by the verifiers (which report `filterable? true` on a field
  # without any) and the table model.

  alias AshTable.Model.CellType

  @type t ::
          :contains
          | :equals
          | :starts_with
          | :is_empty
          | :greater_than
          | :less_than
          | :at_least
          | :at_most
          | :on
          | :before
          | :after
          | :yes
          | :no
          | :is

  # Per cell type, the default operator first.
  @of_cell_type %{
    text: [:contains, :equals, :starts_with, :is_empty],
    number: [:equals, :greater_than, :less_than, :at_least, :at_most, :is_empty],
    date: [:on, :before, :after, :is_empty],
    datetime: [:before, :after, :is_empty],
    boolean: [:yes, :no],
    enum: [:is]
  }

  # What each operator is in Ash: the operator or function module, whose
  # signatures and data layer support decide whether it can be offered, and
  # the key it has in a filter given to `Ash.Query.filter_input/2`.
  @in_ash %{
    contains: {Ash.Query.Function.Contains, :contains},
    starts_with: {Ash.Query.Function.StringStartsWith, :string_starts_with},
    equals: {Ash.Query.Operator.Eq, :eq},
    on: {Ash.Query.Operator.Eq, :eq},
    is: {Ash.Query.Operator.Eq, :eq},
    yes: {Ash.Query.Operator.Eq, :eq},
    no: {Ash.Query.Operator.Eq, :eq},
    greater_than: {Ash.Query.Operator.GreaterThan, :greater_than},
    after: {Ash.Query.Operator.GreaterThan, :greater_than},
    less_than: {Ash.Query.Operator.LessThan, :less_than},
    before: {Ash.Query.Operator.LessThan, :less_than},
    at_least: {Ash.Query.Operator.GreaterThanOrEqual, :greater_than_or_equal},
    at_most: {Ash.Query.Operator.LessThanOrEqual, :less_than_or_equal},
    is_empty: {Ash.Query.Operator.IsNil, :is_nil}
  }

  # Operators that are complete without a value.
  @without_value [:is_empty, :yes, :no]

  @doc """
  The operators the resource allows a person to filter `field` by, the default
  one first. An empty list means the field cannot be filtered.

  They are the operators of the field's cell type, less what Ash does not
  support for the field:

    * none when the field is declared `filterable?: false`, and only the
      equality ones when it is declared `filterable?: :simple_equality`;
    * none for a calculation without an expression (one computed in Elixir),
      and none for a calculation or aggregate the data layer cannot filter by;
    * only those whose Ash operator or function accepts the field's type and
      is supported by the data layer;
    * "is empty" only when the field can be nil.
  """
  @spec available(Ash.Resource.t(), struct) :: [t]
  def available(resource, field) do
    {type, _constraints} = CellType.type(resource, field)
    {cell_type, _values} = CellType.of(resource, field)

    if filterable?(resource, field) do
      @of_cell_type
      |> Map.get(cell_type, [])
      |> Enum.filter(fn operator ->
        {module, _key} = Map.fetch!(@in_ash, operator)

        (operator != :is_empty or allow_nil?(field)) and
          (field.filterable? != :simple_equality or module == Ash.Query.Operator.Eq) and
          accepts?(module, type) and
          Ash.DataLayer.data_layer_can?(resource, {:filter_expr, struct(module)})
      end)
    else
      []
    end
  end

  @doc "Whether the operator needs a value from the person, unlike \"is empty\"."
  @spec takes_value?(t) :: boolean
  def takes_value?(operator), do: operator not in @without_value

  @doc """
  The operator with its value as the predicate of a field in a filter given
  to `Ash.Query.filter_input/2`: `%{field => %{key => value}}`. The value is
  passed on as it was typed; casting it is Ash's.
  """
  @spec to_ash(t, String.t() | nil) :: {atom, term}
  def to_ash(:is_empty, _value), do: {:is_nil, true}
  def to_ash(:yes, _value), do: {:eq, true}
  def to_ash(:no, _value), do: {:eq, false}
  def to_ash(operator, value), do: {elem(Map.fetch!(@in_ash, operator), 1), value}

  defp filterable?(_resource, %{filterable?: false}), do: false

  # As `Ash.Resource.Info.sortable?/3` decides for sorting: a calculation can
  # be used in the data layer only when its module has an expression.
  defp filterable?(resource, %Ash.Resource.Calculation{calculation: {module, _opts}}) do
    Code.ensure_compiled(module)

    function_exported?(module, :expression, 2) and
      Ash.DataLayer.data_layer_can?(resource, :expression_calculation)
  end

  defp filterable?(resource, %Ash.Resource.Aggregate{}),
    do: Ash.DataLayer.data_layer_can?(resource, :aggregate_filter)

  defp filterable?(resource, _attribute), do: Ash.DataLayer.data_layer_can?(resource, :filter)

  # Counting, existence and lists have a value for no related records; every
  # other kind of aggregate is nil then, unless it declares a default.
  defp allow_nil?(%Ash.Resource.Aggregate{kind: kind}) when kind in [:count, :exists, :list],
    do: false

  defp allow_nil?(%Ash.Resource.Aggregate{default: default}),
    do: is_nil(default) or is_function(default)

  defp allow_nil?(field), do: field.allow_nil?

  # Whether one of the signatures of an Ash operator (`types/0`) or function
  # (`args/0`) takes the type as its first argument. A NewType counts as the
  # type it is made of.
  defp accepts?(_module, nil), do: false

  defp accepts?(module, type) do
    Code.ensure_loaded(module)

    signatures =
      if function_exported?(module, :types, 0), do: module.types(), else: module.args()

    types = type_and_subtypes(Ash.Type.get_type(type))

    is_list(signatures) and
      Enum.any?(signatures, fn
        [first | _rest] -> first in [:any, :same] or Ash.Type.get_type(first) in types
        signature -> signature in [:any, :same]
      end)
  end

  defp type_and_subtypes(type) do
    if is_atom(type) and Ash.Type.NewType.new_type?(type),
      do: [type | type_and_subtypes(Ash.Type.get_type(type.subtype_of()))],
      else: [type]
  end
end
