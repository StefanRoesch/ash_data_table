defmodule AshDataTable.Resource.Operator do
  @moduledoc false
  # The filter operators a table offers for a field, and what each of them is
  # in Ash. Shared by the verifiers (which report `filterable? true` on a field
  # without any) and the table model.

  alias AshDataTable.Resource.CellType

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
          | :any_of
          | :none_of
          | :between

  # What a person gives an operator: nothing, one value as it was typed,
  # several values of the column's own ("is any of"), or the two ends of a
  # range, either of which may be nil ("between").
  @type value :: nil | String.t() | [String.t()] | {String.t() | nil, String.t() | nil}

  # Per cell type, the default operator first.
  @of_cell_type %{
    text: [:contains, :equals, :starts_with, :is_empty],
    number: [:equals, :greater_than, :less_than, :at_least, :at_most, :between, :is_empty],
    date: [:on, :before, :after, :between, :is_empty],
    datetime: [:before, :after, :between, :is_empty],
    boolean: [:yes, :no],
    enum: [:is, :any_of, :none_of]
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
    is_empty: {Ash.Query.Operator.IsNil, :is_nil},
    any_of: {Ash.Query.Operator.In, :in},
    none_of: {Ash.Query.Operator.In, :in}
  }

  # An operator that is several of Ash's at once, on the one field: a range
  # is "at least" its first end and "at most" its last.
  @made_of %{between: [:at_least, :at_most]}

  # Operators that are complete without a value.
  @without_value [:is_empty, :yes, :no]

  # Operators that take several of the column's values, and the one that
  # takes the two ends of a range.
  @with_values [:any_of, :none_of]
  @with_range [:between]

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
    * "is empty" only when the field can be nil;
    * "between" only when both of its ends can be asked for, and "is none
      of" only when the data layer can negate;
    * none for a field that is declared `sensitive?`: which rows a filter
      leaves would say what the mask in its cells hides
      (`AshDataTable.Sensitive`).
  """
  @spec available(Ash.Resource.t(), struct) :: [t]
  def available(resource, field) do
    {type, _constraints} = CellType.type(resource, field)
    {cell_type, _values} = CellType.of(resource, field)

    if filterable?(resource, field) and not AshDataTable.Resource.Exposing.sensitive?(field) do
      @of_cell_type
      |> Map.get(cell_type, [])
      |> Enum.filter(fn operator ->
        (operator != :is_empty or allow_nil?(field)) and
          (operator != :none_of or Ash.DataLayer.data_layer_can?(resource, :boolean_filter)) and
          Enum.all?(modules(operator), fn module ->
            (field.filterable? != :simple_equality or module == Ash.Query.Operator.Eq) and
              accepts?(module, type) and
              Ash.DataLayer.data_layer_can?(resource, {:filter_expr, struct(module)})
          end)
      end)
    else
      []
    end
  end

  @doc "Whether the operator needs a value from the person, unlike \"is empty\"."
  @spec takes_value?(t) :: boolean
  def takes_value?(operator), do: operator not in @without_value

  @doc """
  What a person gives the operator: `:none`, `:one` value, `:many` of the
  column's values, or the two ends of a `:range`.
  """
  @spec takes(t) :: :none | :one | :many | :range
  def takes(operator) when operator in @without_value, do: :none
  def takes(operator) when operator in @with_values, do: :many
  def takes(operator) when operator in @with_range, do: :range
  def takes(_operator), do: :one

  @doc """
  Whether the operator finds the records its predicates do not match: "is
  none of" is "is any of", negated.
  """
  @spec negated?(t) :: boolean
  def negated?(operator), do: operator == :none_of

  @doc """
  The operator with its value as the predicates of a field in a filter given
  to `Ash.Query.filter_input/2`: `%{field => %{key => value, …}}`, which Ash
  combines with AND. The values are passed on as they were typed; casting
  them is Ash's.

  A range is "at least" its first end and "at most" its last, so both ends
  are part of it; an end that is nil is left open. For a negated operator
  (`negated?/1`) they are the predicates of what it leaves out.
  """
  @spec predicates(t, value) :: [{atom, term}]
  def predicates(:between, {from, to}) do
    for {operator, end_of} <- [at_least: from, at_most: to],
        not is_nil(end_of),
        do: to_ash(operator, end_of)
  end

  def predicates(operator, value), do: [to_ash(operator, value)]

  @doc """
  An operator of one predicate with its value as that predicate: the key it
  has in a filter given to `Ash.Query.filter_input/2`, and the value.
  """
  @spec to_ash(t, String.t() | [String.t()] | nil) :: {atom, term}
  def to_ash(:is_empty, _value), do: {:is_nil, true}
  def to_ash(:yes, _value), do: {:eq, true}
  def to_ash(:no, _value), do: {:eq, false}
  def to_ash(operator, value), do: {elem(Map.fetch!(@in_ash, operator), 1), value}

  # The Ash operators and functions an operator is made of.
  defp modules(operator) do
    for part <- Map.get(@made_of, operator, [operator]),
        do: elem(Map.fetch!(@in_ash, part), 0)
  end

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
