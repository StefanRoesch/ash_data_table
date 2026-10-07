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
          editor: atom | nil,
          required?: boolean,
          default: term
        }

  @type reason ::
          {:not_found, atom}
          | {:not_public, atom}
          | {:not_a_row_action, atom, atom}
          | {:declared_twice, atom}
          | {:no_field, :row | :create, atom, input}
          | {:not_a_create_action, atom, atom}

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
        input(:attribute, attribute, required_attribute?(action, attribute))
      end

    arguments =
      for %{public?: true} = argument <- action.arguments do
        input(:argument, argument, argument.allow_nil? == false and not computed?(argument))
      end

    attributes ++ arguments
  end

  # Whether the action takes the attribute empty. A create action fills in a
  # default that is computed, so nothing has to be given for it.
  defp required_attribute?(action, attribute) do
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
      editor: editor(cell_type, type, constraints),
      required?: required?,
      default: if(computed?(field), do: nil, else: field.default)
    }
  end

  # The control of a cell of that type, or a plain field for a value that
  # is written as one line of text. Nothing for the rest: arrays, maps,
  # embedded resources and so on.
  defp editor(:other, {:array, _type}, _constraints), do: nil

  defp editor(:other, type, constraints) do
    if Ash.Type.storage_type(type, constraints) in @plain, do: :plain
  end

  defp editor(cell_type, _type, _constraints), do: Editing.editor(cell_type)

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

  def message({:no_field, what, name, %{name: input, type: {type, _constraints}}}),
    do:
      "The #{what} action `#{name}` cannot be run from a table: its input `#{input}` is " <>
        "required, and a table has no field for its type (#{inspect(type)}). The action panel " <>
        "has fields for text, numbers, booleans, dates, datetimes, choices, and for values " <>
        "written as one line of text, such as a key."

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
