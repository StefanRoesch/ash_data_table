defmodule AshTable.Resource.Acting do
  @moduledoc false
  # What a table lets a person run: its row actions, its table actions and
  # its create action, and what each asks of the person. Shared by the
  # verifiers (which report a mistake) and the table model (which builds on
  # the answer).
  #
  # An `action` of the block is one of two things, by what the action is on
  # the resource. An update or a destroy action is given a record: it is a
  # row action. A generic action is given arguments and nothing else: it is
  # a table action, run on the table as a whole, unless the block names the
  # argument that takes a row's primary key (`record_argument`), which makes
  # it a row action too.

  alias Ash.Resource.Info
  alias AshTable.Model.CellType
  alias AshTable.Resource.Editing
  alias AshTable.Resource.Managing
  alias AshTable.Resource.Referencing

  # What a value that has no editor of its own is stored as, where it can be
  # written as one line of text: a key, a time, an atom.
  @plain [:uuid, :string, :ci_string, :citext, :text, :time, :time_usec, :duration]

  @typedoc """
  An input of an action: an attribute it accepts or one of its arguments,
  with the control a table has for it (`editor`, nil when it has none).

  An argument that hands keys to a relationship, whose records can be
  chosen in a picker, is given by choosing them: its `editor` is
  `:reference` for one key and `:references` for a list of them, and
  `reference` says what is chosen from (`managing/3`). Nil for every other
  input.
  """
  @type input :: %{
          name: atom,
          kind: :attribute | :argument,
          type: {Ash.Type.t(), keyword},
          cell_type: CellType.t(),
          values: CellType.values() | nil,
          editor: Editing.editor() | :plain | :reference | :references | nil,
          fields: [AshTable.Model.Field.t()] | nil,
          reference: Referencing.managing() | nil,
          required?: boolean,
          default: term
        }

  @type reason ::
          {:not_found, atom}
          | {:not_public, atom}
          | {:not_a_row_action, atom, atom}
          | {:declared_twice, atom}
          | {:not_bulk, atom, [atom]}
          | {:table_action_not_bulk, atom}
          | {:record_argument_not_generic, atom, atom, atom}
          | {:record_argument_not_found, atom, atom}
          | {:record_argument_not_public, atom, atom}
          | {:record_argument_no_single_key, atom, atom, [atom]}
          | {:record_argument_not_a_key, atom, atom, term, atom, term}
          | {:no_field, :row | :table | :create, atom, input}
          | {:no_field, :row | :table | :create, atom, input, struct, Referencing.no_picker()}
          | {:not_a_create_action, atom, atom}
          | {:result_read_not_public, atom}
          | {:result_read_needs_argument, atom, atom}

  @doc """
  What an `action` of the block is, with the action it names, or what is
  wrong with it: `:row` for a row action, which runs on the record of a
  row, and `:table` for a table action, which runs on the table as a whole.

  `declaration` is the `action` as written in the block
  (`AshTable.Resource.Action`).
  """
  @spec offered(Ash.Resource.t() | Spark.Dsl.t(), struct) ::
          {:ok, :row | :table, struct} | {:error, reason}
  def offered(resource, %{name: name} = declaration) do
    record_argument = Map.get(declaration, :record_argument)

    case Info.action(resource, name) do
      nil ->
        {:error, {:not_found, name}}

      %{type: type} when type not in [:update, :destroy, :action] ->
        {:error, {:not_a_row_action, name, type}}

      %{public?: false} ->
        {:error, {:not_public, name}}

      %{type: :action} = action when is_nil(record_argument) ->
        {:ok, :table, action}

      %{type: :action} = action ->
        with :ok <- record_argument(resource, action, record_argument), do: {:ok, :row, action}

      %{type: type} when not is_nil(record_argument) ->
        {:error, {:record_argument_not_generic, name, type, record_argument}}

      action ->
        {:ok, :row, action}
    end
  end

  @doc """
  Whether an argument of a generic action can be given the primary key of
  a row: it is one of the action's arguments, public, and stored as the
  resource's primary key is, which has to be one attribute.
  """
  @spec record_argument(Ash.Resource.t() | Spark.Dsl.t(), struct, atom) :: :ok | {:error, reason}
  def record_argument(resource, %{name: action, arguments: arguments}, name) do
    case {Enum.find(arguments, &(&1.name == name)), Info.primary_key(resource)} do
      {nil, _key} ->
        {:error, {:record_argument_not_found, action, name}}

      {%{public?: false}, _key} ->
        {:error, {:record_argument_not_public, action, name}}

      {argument, [key]} ->
        attribute = Info.attribute(resource, key)

        if stored_as(argument) == stored_as(attribute),
          do: :ok,
          else:
            {:error,
             {:record_argument_not_a_key, action, name, argument.type, key, attribute.type}}

      {_argument, keys} ->
        {:error, {:record_argument_no_single_key, action, name, keys}}
    end
  end

  defp stored_as(%{type: type, constraints: constraints}),
    do: Ash.Type.storage_type(type, constraints || [])

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
  never given from the outside. Nor is the argument that takes a row's
  primary key (`record_argument`): the table gives it.

  An argument that hands keys to a relationship is given by choosing the
  related records, where there is something to choose them with
  (`managing/3`).
  """
  @spec inputs(Ash.Resource.t() | Spark.Dsl.t(), struct, atom | nil) :: [input]
  def inputs(resource, action, record_argument \\ nil) do
    attributes =
      for name <- Map.get(action, :accept) || [],
          attribute = Info.attribute(resource, name),
          attribute.public? do
        input(:attribute, attribute, required?(action, attribute))
      end

    arguments =
      for %{public?: true, name: name} = argument <- action.arguments,
          name != record_argument,
          do: argument |> argument() |> managing(resource, action)

    attributes ++ arguments
  end

  @doc """
  An argument as the input it is where a change of the action hands it to a
  relationship as keys (`AshTable.Resource.Managing`), and the related
  records can be chosen in a picker
  (`AshTable.Resource.Referencing.managing/1`): its control is the picker,
  for one record (`:reference`) or for several (`:references`), and
  `reference` says what is chosen from. Any other argument is the input it
  was: one whose keys cannot be chosen is typed, where a table has a field
  for its type.
  """
  @spec managing(input, Ash.Resource.t() | Spark.Dsl.t(), struct) :: input
  def managing(%{kind: :argument, name: name} = input, resource, action) do
    with {:ok, managed} <- Managing.managed(resource, action, name),
         {:ok, managing} <- Referencing.managing(managed) do
      %{
        input
        | editor: if(managing.several?, do: :references, else: :reference),
          reference: managing
      }
    else
      _not_managed_or_no_picker -> input
    end
  end

  def managing(input, _resource, _action), do: input

  @doc """
  Why an argument that hands keys to a relationship is not given by choosing
  the related records: the relationship, and what keeps it from having a
  picker. Nil for an argument that is given so, and for one that hands no
  keys to a relationship.
  """
  @spec unchosen(Ash.Resource.t() | Spark.Dsl.t(), struct, atom) ::
          {struct, Referencing.no_picker()} | nil
  def unchosen(resource, action, name) do
    with {:ok, managed} <- Managing.managed(resource, action, name),
         {:error, reason} <- Referencing.managing(managed) do
      {managed.relationship, reason}
    else
      _chosen_or_not_managed -> nil
    end
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
      reference: nil,
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
  @spec unusable(Ash.Resource.t() | Spark.Dsl.t(), struct, atom | nil) :: [input]
  def unusable(resource, action, record_argument \\ nil) do
    for %{editor: nil, required?: true} = input <- inputs(resource, action, record_argument),
        do: input
  end

  @doc """
  Whether using an action opens the action panel first. It does when the
  person has something to give: an attribute the action accepts, or an
  argument that hands the records they choose to a relationship, which is
  what such an action is for; or an argument it does not run without. An
  action without inputs, or with other optional arguments only, runs
  straight away: those keep their defaults. `inputs` are the ones a table
  has a field for.
  """
  @spec panel?([input]) :: boolean
  def panel?(inputs) do
    Enum.any?(inputs, fn input ->
      # an argument with a default runs with it
      input.kind == :attribute or not is_nil(input.reference) or
        (input.required? and is_nil(input.default))
    end)
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
      record_actions?(resource) or
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

    record_actions?(resource) or
      AshTable.Resource.Info.table_create_action(resource) != :error or
      Enum.any?(columns, fn {field, declared} ->
        Editing.update_action(resource, field, declared) != :none
      end)
  end

  # Whether the block names an action that returns a record, which the row
  # is then shown from: an update or a destroy action. A generic action
  # returns no row: the table reads again after it.
  defp record_actions?(resource) do
    Enum.any?(AshTable.Resource.Info.actions(resource), fn %{name: name} ->
      not match?(%{type: :action}, Info.action(resource, name))
    end)
  end

  @doc "What is wrong with a declared action, for a diagnostic."
  @spec message(reason) :: String.t()
  def message({:not_found, name}), do: "The resource has no action named `#{name}`."

  def message({:not_public, name}),
    do: "The action `#{name}` is not public. Only `public?` actions can be behind a table."

  def message({:not_a_row_action, name, type}),
    do:
      "`#{name}` is #{kind(type)} action. An `action` of a table is an update or a destroy " <>
        "action, which runs on the record of a row, or a generic action, which runs on the " <>
        "table as a whole." <> hint(type, name)

  def message({:declared_twice, name}), do: "`#{name}` is declared more than once."

  def message({:not_bulk, name, attributes}),
    do:
      "The row action `#{name}` says `bulk? true`, and cannot run on several records at once: " <>
        "it accepts #{Enum.map_join(attributes, ", ", &"`#{&1}`")}, of which no two records can " <>
        "hold the same value (an attribute of the primary key, or an identity by itself), and the " <>
        "inputs of an action that runs on the selected rows are given once for all of them. " <>
        "Leave `bulk?` out: the action stays an action of one row."

  def message({:table_action_not_bulk, name}),
    do:
      "The table action `#{name}` says `bulk? true`, and runs on the table as a whole: a generic " <>
        "action takes no record, so there are no selected rows to run it on. Leave `bulk?` out, or " <>
        "name the argument that takes a row's primary key with `record_argument`: the action is " <>
        "then a row action."

  def message({:record_argument_not_generic, name, type, argument}),
    do:
      "The action `#{name}` says `record_argument :#{argument}`, and is #{kind(type)} action, " <>
        "which runs on the record of its row already. `record_argument` is for a generic action, " <>
        "which takes no record: it names the argument that is given the row's primary key. " <>
        "Leave it out."

  def message({:record_argument_not_found, name, argument}),
    do:
      "The action `#{name}` says `record_argument :#{argument}`, and has no argument named " <>
        "`#{argument}`."

  def message({:record_argument_not_public, name, argument}),
    do:
      "The action `#{name}` says `record_argument :#{argument}`, and its argument `#{argument}` " <>
        "is not public. A private argument is not given from the outside, and a table is the outside."

  def message({:record_argument_no_single_key, name, argument, []}),
    do:
      "The action `#{name}` says `record_argument :#{argument}`, and the resource has no primary " <>
        "key: there is nothing of a row to give the argument."

  def message({:record_argument_no_single_key, name, argument, keys}),
    do:
      "The action `#{name}` says `record_argument :#{argument}`, and the primary key of the " <>
        "resource is #{Enum.map_join(keys, ", ", &"`#{&1}`")}: several attributes. One argument " <>
        "takes the primary key of a row only where that is one attribute."

  def message({:record_argument_not_a_key, name, argument, type, key, key_type}),
    do:
      "The action `#{name}` says `record_argument :#{argument}`, and that argument is of the type " <>
        "#{inspect(type)}, which is not stored as the primary key `#{key}` is (#{inspect(key_type)}). " <>
        "The argument is given the primary key of the row as it is, so it has to be of the key's type."

  def message({:no_field, what, name, %{name: input, type: {type, _constraints}}}),
    do:
      "The #{what} action `#{name}` cannot be run from a table: its input `#{input}` is " <>
        "required, and a table has no field for its type (#{inspect(type)}). The action panel " <>
        "has fields for text, numbers, booleans, dates, datetimes, choices, arrays of those, " <>
        "values written as one line of text, such as a key, and for embedded resources and " <>
        "maps whose every field is one of these."

  # a list of keys that is handed to a relationship, and cannot be chosen
  def message({:no_field, what, name, %{name: input}, relationship, reason}),
    do:
      "The #{what} action `#{name}` cannot be run from a table: its argument `#{input}` is " <>
        "required, and holds the keys of the records of `#{relationship.name}`. A table has a " <>
        "field for a list of keys only where the records can be chosen from the related " <>
        "resource's own table, and here they cannot. " <>
        Referencing.no_picker(relationship, reason)

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

  defp hint(_type, _name), do: ""
end
