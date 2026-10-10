defmodule AshTable.Resource.Acting do
  @moduledoc false
  # What a table lets a person run: its row actions and its create action,
  # and what each asks of the person. Shared by the verifiers (which report a
  # mistake) and the table model (which builds on the answer).

  alias Ash.Resource.Info
  alias AshTable.Model.CellType
  alias AshTable.Resource.Editing

  # What a value that has no editor of its own is stored as, where it can be
  # written as one line of text: a key, a time, an atom.
  @plain [:uuid, :string, :ci_string, :citext, :text, :time, :time_usec, :duration]

  @typedoc """
  An input of an action: an attribute it accepts or one of its arguments,
  with the control a table has for it (`editor`, nil when it has none).
  """
  @type input :: %{
          name: atom,
          kind: :attribute | :argument,
          type: {Ash.Type.t(), keyword},
          cell_type: CellType.t(),
          values: CellType.values() | nil,
          editor: Editing.editor() | :plain | nil,
          fields: [AshTable.Model.Field.t()] | nil,
          required?: boolean,
          default: term
        }

  @type reason ::
          {:not_found, atom}
          | {:not_public, atom}
          | {:not_a_row_action, atom, atom}
          | {:declared_twice, atom}
          | {:not_bulk, atom, [atom]}
          | {:no_field, :row | :create, atom, input}
          | {:not_a_create_action, atom, atom}
          | {:result_read_not_public, atom}
          | {:result_read_needs_argument, atom, atom}

  @doc "The action a row action of the block names, or what is wrong with it."
  @spec row_action(Ash.Resource.t() | Spark.Dsl.t(), atom) :: {:ok, struct} | {:error, reason}
  def row_action(resource, name) do
    case Info.action(resource, name) do
      nil ->
        {:error, {:not_found, name}}

      %{type: type} when type not in [:update, :destroy] ->
        {:error, {:not_a_row_action, name, type}}

      %{public?: false} ->
        {:error, {:not_public, name}}

      action ->
        {:ok, action}
    end
  end

  @doc "The create action of the table: `:none` when the block names none."
  @spec create_action(Ash.Resource.t() | Spark.Dsl.t()) ::
          {:ok, Ash.Resource.Actions.Create.t()} | :none | {:error, reason}
  def create_action(resource) do
    case AshTable.Resource.Info.table_create_action(resource) do
      {:ok, name} ->
        case Info.action(resource, name) do
          nil -> {:error, {:not_found, name}}
          %{type: type} when type != :create -> {:error, {:not_a_create_action, name, type}}
          %{public?: false} -> {:error, {:not_public, name}}
          action -> {:ok, action}
        end

      :error ->
        :none
    end
  end

  @doc """
  The inputs of an action, in its own order: the public attributes it
  accepts, then its public arguments. A private attribute or argument is
  never given from the outside.
  """
  @spec inputs(Ash.Resource.t() | Spark.Dsl.t(), struct) :: [input]
  def inputs(resource, action) do
    attributes =
      for name <- Map.get(action, :accept) || [],
          attribute = Info.attribute(resource, name),
          attribute.public? do
        input(:attribute, attribute, required?(action, attribute))
      end

    arguments = for %{public?: true} = argument <- action.arguments, do: argument(argument)

    attributes ++ arguments
  end

  @doc """
  An argument as an input: one of an action, or of a calculation. It is
  required when it cannot be empty, unless it has a default that is computed.
  """
  @spec argument(struct) :: input
  def argument(argument),
    do: input(:argument, argument, argument.allow_nil? == false and not computed?(argument))

  @doc """
  Whether the action takes the attribute empty. A create action fills in a
  default that is computed, so nothing has to be given for it.
  """
  @spec required?(struct, Ash.Resource.Attribute.t()) :: boolean
  def required?(action, attribute) do
    name = attribute.name

    name in (Map.get(action, :require_attributes) || []) or
      (attribute.allow_nil? == false and name not in (Map.get(action, :allow_nil_input) || []) and
         not (action.type == :create and computed?(attribute)))
  end

  defp computed?(%{default: default}), do: is_function(default) or match?({_m, _f, _a}, default)

  defp input(kind, %{name: name, type: type} = field, required?) do
    constraints = field.constraints || []
    {cell_type, values} = CellType.classify(type, constraints)

    %{
      name: name,
      kind: kind,
      type: {type, constraints},
      cell_type: cell_type,
      values: values,
      editor: control(cell_type, type, constraints),
      fields: fields(cell_type, type, constraints),
      required?: required?,
      default: if(computed?(field), do: nil, else: field.default)
    }
  end

  @doc """
  The control a table has for a value of a type, where a person gives one
  in a form: that of a cell of that type (a group of fields for a map cell),
  or a plain field for a value that is written as one line of text. Nil for
  the rest: unions and so on, the arrays of anything without a cell type,
  and a map cell with an input a person cannot give.
  """
  @spec control(CellType.t(), Ash.Type.t(), keyword) :: Editing.editor() | :plain | nil
  def control(:other, {:array, _type}, _constraints), do: nil

  def control(:other, type, constraints) do
    if Ash.Type.storage_type(type, constraints) in @plain, do: :plain
  end

  def control(cell_type, type, constraints), do: Editing.editor(cell_type, type, constraints)

  # The fields of an input that is a map cell, or an array of them.
  defp fields(cell_type, type, constraints) when cell_type in [:map, {:array, :map}] do
    case AshTable.Resource.Embedding.of(type, constraints) do
      %{fields: fields} -> fields
      nil -> nil
    end
  end

  defp fields(_cell_type, _type, _constraints), do: nil

  @doc """
  The required inputs of an action that a table has no field for. An action
  with one cannot be run from a table.
  """
  @spec unusable(Ash.Resource.t() | Spark.Dsl.t(), struct) :: [input]
  def unusable(resource, action) do
    for %{editor: nil, required?: true} = input <- inputs(resource, action), do: input
  end

  @doc """
  Whether using an action opens the action panel first. It does when the
  person has something to give: an attribute the action accepts, which is
  what such an action is for, or an argument it does not run without. An
  action without inputs, or with optional arguments only, runs straight
  away: those keep their defaults. `inputs` are the ones a table has a field
  for.
  """
  @spec panel?([input]) :: boolean
  def panel?(inputs) do
    # an argument with a default runs with it
    Enum.any?(inputs, &(&1.kind == :attribute or (&1.required? and is_nil(&1.default))))
  end

  @doc """
  The attributes an action accepts of which no two records can hold the
  same value: those of the primary key, and those that are an identity by
  themselves. An action that accepts one cannot run on several records at
  once: its inputs are given once and applied to every record, and such a
  value can be given to one record only.
  """
  @spec unrepeatable(Ash.Resource.t() | Spark.Dsl.t(), struct) :: [atom]
  def unrepeatable(resource, action) do
    unique =
      Info.primary_key(resource) ++
        for(%{keys: [key]} <- Info.identities(resource), do: key)

    for name <- Map.get(action, :accept) || [], name in unique, do: name
  end

  @doc """
  Whether a row action is also offered for the rows a person has selected:
  unless its declaration says `bulk? false`, and unless it accepts an
  attribute that is `unrepeatable/2`.
  """
  @spec bulk?(Ash.Resource.t() | Spark.Dsl.t(), struct, boolean | nil) :: boolean
  def bulk?(resource, action, declared),
    do: declared != false and unrepeatable(resource, action) == []

  @doc """
  The calculation, aggregate and reference columns that a row could not be
  shown with after an action: those of a table with row actions or a create
  action whose resource has no primary read action, which is what Ash loads
  them through. Empty when nothing is wrong, and when the table has editable
  columns besides, for which `AshTable.Resource.Editing` says the same.

  `columns` are the fields of the table's columns, each with its column as
  written in the block (nil for a column of the default set).
  """
  @spec unloadable_after_action(Ash.Resource.t(), [{struct, struct | nil}]) :: [atom]
  def unloadable_after_action(resource, columns) do
    loaded =
      for {%struct{name: name}, _declared} <- columns,
          struct in [
            Ash.Resource.Calculation,
            Ash.Resource.Aggregate,
            Ash.Resource.Relationships.BelongsTo
          ],
          do: name

    acting? =
      AshTable.Resource.Info.actions(resource) != [] or
        AshTable.Resource.Info.table_create_action(resource) != :error

    if acting? and is_nil(Info.primary_action(resource, :read)) and
         Editing.unloadable_after_save(resource, columns) == [],
       do: loaded,
       else: []
  end

  @doc """
  The primary read action of a resource whose table changes records, when
  that action is private; nil when nothing is wrong.

  Ash loads what a create, an update or a destroy action returns through
  the primary read action (ash 3.34.4: `Ash.Actions.Create`, `Update` and
  `Destroy` name it themselves), and asks its policies and field policies
  what of the result the person may have. No option of a call says
  otherwise, so a table that runs such an action runs the primary read
  action with it, whichever read action its block names. A table that only
  reads runs none of this.

  The table changes records when it has an editable column, a row action
  or a create action.
  """
  @spec private_result_read(Ash.Resource.t()) :: atom | nil
  def private_result_read(resource) do
    with %{public?: false, name: name} <- Info.primary_action(resource, :read),
         true <- changes?(resource) do
      name
    else
      _public_or_none_or_read_only -> nil
    end
  end

  @doc """
  The primary read action of a resource whose table changes records and
  shows something that is loaded (a calculation, an aggregate, a reference
  column), when that action cannot run without an argument: the action and
  the argument. Nil when nothing is wrong.

  Ash loads what a create, an update or a destroy action returns through
  the primary read action, without arguments (`private_result_read/1`), so
  a row could never be shown again after one.
  """
  @spec unanswered_result_read(Ash.Resource.t()) :: {atom, atom} | nil
  def unanswered_result_read(resource) do
    with %{name: name, arguments: arguments} <- Info.primary_action(resource, :read),
         %{name: argument} <-
           Enum.find(arguments, &(&1.allow_nil? == false and is_nil(&1.default))),
         true <- changes?(resource),
         true <- Enum.any?(columns(resource), fn {field, _declared} -> loaded?(field) end) do
      {name, argument}
    else
      _nothing_wrong -> nil
    end
  end

  defp loaded?(%struct{}),
    do:
      struct in [
        Ash.Resource.Calculation,
        Ash.Resource.Aggregate,
        Ash.Resource.Relationships.BelongsTo
      ]

  # The fields of the table's columns, each with its column as written in
  # the block (nil for a column of the default set).
  defp columns(resource) do
    case AshTable.Resource.Info.columns(resource) do
      [] ->
        Enum.map(Info.public_attributes(resource), &{&1, nil})

      declared ->
        for column <- declared, field = Info.field(resource, column.name), do: {field, column}
    end
  end

  defp changes?(resource) do
    columns = columns(resource)

    AshTable.Resource.Info.actions(resource) != [] or
      AshTable.Resource.Info.table_create_action(resource) != :error or
      Enum.any?(columns, fn {field, declared} ->
        Editing.update_action(resource, field, declared) != :none
      end)
  end

  @doc "What is wrong with a declared action, for a diagnostic."
  @spec message(reason) :: String.t()
  def message({:not_found, name}), do: "The resource has no action named `#{name}`."

  def message({:not_public, name}),
    do: "The action `#{name}` is not public. Only `public?` actions can be behind a table."

  def message({:not_a_row_action, name, type}),
    do:
      "`#{name}` is #{kind(type)} action. A row action runs on the record of its row, so it " <>
        "has to be an update or a destroy action." <> hint(type, name)

  def message({:declared_twice, name}), do: "`#{name}` is declared more than once."

  def message({:not_bulk, name, attributes}),
    do:
      "The row action `#{name}` says `bulk? true`, and cannot run on several records at once: " <>
        "it accepts #{Enum.map_join(attributes, ", ", &"`#{&1}`")}, of which no two records can " <>
        "hold the same value (an attribute of the primary key, or an identity by itself), and the " <>
        "inputs of an action that runs on the selected rows are given once for all of them. " <>
        "Leave `bulk?` out: the action stays an action of one row."

  def message({:no_field, what, name, %{name: input, type: {type, _constraints}}}),
    do:
      "The #{what} action `#{name}` cannot be run from a table: its input `#{input}` is " <>
        "required, and a table has no field for its type (#{inspect(type)}). The action panel " <>
        "has fields for text, numbers, booleans, dates, datetimes, choices, arrays of those, " <>
        "values written as one line of text, such as a key, and for embedded resources and " <>
        "maps whose every field is one of these."

  def message({:result_read_not_public, name}),
    do:
      "The table changes records: it has editable columns, row actions or a create action. " <>
        "Ash loads what a create, an update or a destroy action returns through the primary read action, " <>
        "and the primary read action `#{name}` is not public. " <>
        AshTable.Resource.Reading.private_action() <>
        " Make `#{name}` public, or leave the table read-only: without `update_action`, `action` and `create_action`."

  def message({:result_read_needs_argument, name, argument}),
    do:
      "The table changes records: it has editable columns, row actions or a create action. " <>
        "Ash loads what a create, an update or a destroy action returns through the primary read action, " <>
        "without arguments, and the primary read action `#{name}` requires the argument `#{argument}`, " <>
        "so a row could not be shown again after one. Give the argument a default, make another " <>
        "read action the primary one, or leave the table read-only."

  def message({:not_a_create_action, name, type}),
    do: "`#{name}` is #{kind(type)} action, not a create action."

  defp kind(:action), do: "a generic"
  defp kind(:update), do: "an update"
  defp kind(type), do: "a #{type}"

  defp hint(:create, name),
    do: " A create action is offered with `create_action :#{name}` in the `table` block."

  defp hint(:action, _name), do: " A generic action takes no record."
  defp hint(_type, _name), do: ""
end
