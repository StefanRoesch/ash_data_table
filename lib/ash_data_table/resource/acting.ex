defmodule AshDataTable.Resource.Acting do
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
  alias AshDataTable.Resource.CellType
  alias AshDataTable.Resource.Editing
  alias AshDataTable.Resource.Managing
  alias AshDataTable.Resource.Referencing
  alias AshDataTable.Resource.Table

  # What a value that has no editor of its own is stored as, where it can be
  # written as one line of text: a key, a time, an atom.
  @plain [:uuid, :string, :ci_string, :citext, :text, :time, :time_usec, :duration]

  # what is wrong with a `reference` of an action: `Referencing.undeclarable/0`
  @undeclarable [
    :reference_not_found,
    :reference_not_public,
    :reference_twice,
    :reference_record_argument,
    :reference_sensitive,
    :reference_managed,
    :reference_no_table,
    :reference_no_read_action,
    :reference_no_single_key,
    :reference_not_a_key
  ]

  @typedoc """
  An input of an action: an attribute it accepts or one of its arguments,
  with the control a table has for it (`editor`, nil when it has none).

  An argument that hands keys to a relationship, whose records can be
  chosen in a picker, is given by choosing them: its `editor` is
  `:reference` for one key and `:references` for a list of them, and
  `reference` says what is chosen from (`managing/3`). So is an argument
  whose resource the block names with a `reference` (`referring/5`). Nil
  for every other input.

  `sensitive?` is what the attribute or the argument says. Such an input
  has a control only where what is typed can be hidden
  (`hidden_as_typed/1`).
  """
  @type input :: %{
          name: atom,
          kind: :attribute | :argument,
          type: {Ash.Type.t(), keyword},
          cell_type: CellType.t(),
          values: CellType.values() | nil,
          editor: Editing.editor() | :plain | :file | :reference | :references | nil,
          fields: [AshDataTable.Resource.Embedding.field()] | nil,
          members: [AshDataTable.Resource.Embedding.field()] | nil,
          reference: Referencing.managing() | nil,
          required?: boolean,
          sensitive?: boolean,
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
          | {:page_argument_not_found, atom, atom}
          | {:page_argument_not_public, atom, atom}
          | {:page_argument_is_record_argument, atom, atom}
          | {:page_argument_twice, atom, atom}
          | {:record_argument_not_a_key, atom, atom, term, atom, term}
          | Referencing.undeclarable()
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
  (`AshDataTable.Resource.Action`). A `reference` of it that cannot be used is
  what is wrong with it, too (`AshDataTable.Resource.Referencing.declared/4`),
  and so is a `page_argument` (`page_arguments/2`).
  """
  @spec offered(Ash.Resource.t() | Spark.Dsl.t(), struct) ::
          {:ok, :row | :table, struct} | {:error, reason}
  def offered(resource, declaration) do
    with {:ok, kind, action} <- named(resource, declaration),
         :ok <- page_arguments(action, declaration),
         :ok <-
           Referencing.undeclarable(
             resource,
             action,
             Map.get(declaration, :references) || [],
             Map.get(declaration, :record_argument)
           ) do
      {:ok, kind, action}
    end
  end

  @doc """
  The names of the arguments the page fills, as an action's declaration
  says them (`page_argument`).
  """
  @spec page_names(struct) :: [atom]
  def page_names(declaration),
    do: for(%{name: name} <- Map.get(declaration, :page_arguments) || [], do: name)

  # A `page_argument` names a public argument of the action, other than the
  # one a row's key goes to, and that once.
  defp page_arguments(action, declaration) do
    names = page_names(declaration)
    twice = names -- Enum.uniq(names)
    record_argument = Map.get(declaration, :record_argument)

    Enum.find_value(names, :ok, fn name ->
      argument = Enum.find(action.arguments, &(&1.name == name))

      cond do
        name in twice ->
          {:error, {:page_argument_twice, action.name, name}}

        name == record_argument ->
          {:error, {:page_argument_is_record_argument, action.name, name}}

        is_nil(argument) ->
          {:error, {:page_argument_not_found, action.name, name}}

        not argument.public? ->
          {:error, {:page_argument_not_public, action.name, name}}

        true ->
          nil
      end
    end)
  end

  defp named(resource, %{name: name} = declaration) do
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

  @doc """
  The create action of `table` (an `AshDataTable.Resource.Table`): `:none` when
  its block names none.
  """
  @spec create_action(Ash.Resource.t() | Spark.Dsl.t(), Table.t()) ::
          {:ok, Ash.Resource.Actions.Create.t()} | :none | {:error, reason}
  def create_action(_resource, %Table{create_action: nil}), do: :none

  def create_action(resource, %Table{create_action: name}) do
    case Info.action(resource, name) do
      nil -> {:error, {:not_found, name}}
      %{type: type} when type != :create -> {:error, {:not_a_create_action, name, type}}
      %{public?: false} -> {:error, {:not_public, name}}
      action -> {:ok, action}
    end
  end

  @doc """
  The inputs of an action, in its own order: the public attributes it
  accepts, then its public arguments. A private attribute or argument is
  never given from the outside. Nor is the argument that takes a row's
  primary key (`record_argument`): the table gives it. Nor are those the
  page fills (`page`, the names of the action's `page_argument`s).

  An argument that hands keys to a relationship is given by choosing the
  related records, where there is something to choose them with
  (`managing/3`). So is one whose resource the block names: `references`
  are the `reference`s of the action's declaration (`referring/5`).
  """
  @spec inputs(Ash.Resource.t() | Spark.Dsl.t(), struct, atom | nil, [struct], [atom]) :: [input]
  def inputs(resource, action, record_argument \\ nil, references \\ [], page \\ []) do
    attributes =
      for name <- Map.get(action, :accept) || [],
          attribute = Info.attribute(resource, name),
          attribute.public? do
        input(:attribute, attribute, required?(action, attribute))
      end

    arguments =
      for %{public?: true, name: name} = argument <- action.arguments,
          name != record_argument,
          name not in page,
          do:
            argument
            |> argument()
            |> managing(resource, action)
            |> referring(resource, action, references, record_argument)

    Enum.map(attributes ++ arguments, &hidden_as_typed/1)
  end

  @doc """
  A sensitive input as a table offers it: with a control only where what is
  typed can be hidden, which is text and a number (`AshDataTable.Sensitive`).
  One of any other type has none, and so is no field of a form: it is left
  out where it can be, and an action that requires it is no action of a
  table.
  """
  @spec hidden_as_typed(input) :: input
  def hidden_as_typed(%{sensitive?: true, editor: editor} = input) do
    if AshDataTable.Resource.Exposing.typed?(editor),
      do: input,
      else: %{input | editor: nil, reference: nil}
  end

  def hidden_as_typed(input), do: input

  @doc """
  An argument as the input it is where a change of the action hands it to a
  relationship as keys (`AshDataTable.Resource.Managing`), and the related
  records can be chosen in a picker
  (`AshDataTable.Resource.Referencing.managing/1`): its control is the picker,
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
  An argument as the input it is where the block says which resource its
  keys belong to (`reference`), and the declaration can be used
  (`AshDataTable.Resource.Referencing.declared/4`): its control is the picker,
  as for an argument that hands keys to a relationship. Any other input is
  the input it was.
  """
  @spec referring(input, Ash.Resource.t() | Spark.Dsl.t(), struct, [struct], atom | nil) :: input
  def referring(%{kind: :argument, name: name} = input, resource, action, references, given) do
    with [reference] <- Enum.filter(references, &(&1.name == name)),
         {:ok, declared} <- Referencing.declared(resource, action, reference, given) do
      %{
        input
        | editor: if(declared.several?, do: :references, else: :reference),
          reference: declared
      }
    else
      _not_declared_or_unusable -> input
    end
  end

  def referring(input, _resource, _action, _references, _given), do: input

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
      editor: file(kind, type) || control(cell_type, type, constraints),
      fields: fields(cell_type, type, constraints),
      members: members(cell_type, type, constraints),
      reference: nil,
      required?: required?,
      sensitive?: AshDataTable.Resource.Exposing.sensitive?(field),
      default: if(computed?(field), do: nil, else: field.default)
    }
  end

  # An argument that takes a file is given by uploading one. Ash stores no
  # file, so only an argument is ever of that type.
  defp file(:argument, type), do: if(file?(type), do: :file)
  defp file(_attribute, _type), do: nil

  @doc "Whether a type is `Ash.Type.File`, a NewType taken as what it is made of."
  @spec file?(Ash.Type.t()) :: boolean
  def file?({:array, _type}), do: false

  def file?(type) do
    type = Ash.Type.get_type(type)

    cond do
      type == Ash.Type.File -> true
      is_atom(type) and Ash.Type.NewType.new_type?(type) -> file?(type.subtype_of())
      true -> false
    end
  end

  @doc """
  The control a table has for a value of a type, where a person gives one
  in a form: that of a cell of that type (a group of fields for a map cell,
  the kind and its value for a union), or a plain field for a value that is
  written as one line of text. Nil for the rest: the arrays of anything
  without a cell type, and a map cell or a union with an input a person
  cannot give.
  """
  @spec control(CellType.t(), Ash.Type.t(), keyword) :: Editing.editor() | :plain | nil
  def control(:other, {:array, _type}, _constraints), do: nil

  def control(:other, type, constraints) do
    if Ash.Type.storage_type(type, constraints) in @plain, do: :plain
  end

  def control(cell_type, type, constraints), do: Editing.editor(cell_type, type, constraints)

  # The fields of an input that is a map cell, or an array of them.
  defp fields(cell_type, type, constraints) when cell_type in [:map, {:array, :map}] do
    case AshDataTable.Resource.Embedding.of(type, constraints) do
      %{fields: fields} -> fields
      nil -> nil
    end
  end

  defp fields(_cell_type, _type, _constraints), do: nil

  # The kinds of an input that is a union.
  defp members(:union, type, constraints) do
    case AshDataTable.Resource.Embedding.of(type, constraints) do
      %{members: members} -> members
      nil -> nil
    end
  end

  defp members(_cell_type, _type, _constraints), do: nil

  @doc """
  The required inputs of an action that a table has no field for. An action
  with one cannot be run from a table.
  """
  @spec unusable(Ash.Resource.t() | Spark.Dsl.t(), struct, atom | nil, [struct], [atom]) ::
          [input]
  def unusable(resource, action, record_argument \\ nil, references \\ [], page \\ []) do
    for %{editor: nil, required?: true} = input <-
          inputs(resource, action, record_argument, references, page),
        do: input
  end

  @doc """
  Whether using an action opens the action panel first. It does when the
  person has something to give: an attribute the action accepts, or an
  argument that hands the records they choose to a relationship, which is
  what such an action is for, as is an argument that takes a file; or an
  argument it does not run without. An
  action without inputs, or with other optional arguments only, runs
  straight away: those keep their defaults. `inputs` are the ones a table
  has a field for.
  """
  @spec panel?([input]) :: boolean
  def panel?(inputs) do
    Enum.any?(inputs, fn input ->
      # an argument with a default runs with it
      input.kind == :attribute or not is_nil(input.reference) or input.editor == :file or
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
  columns besides, for which `AshDataTable.Resource.Editing` says the same.

  `columns` are the fields of the table's columns, each with its column as
  written in the block (nil for a column of the default set).
  """
  @spec unloadable_after_action(Ash.Resource.t(), Table.t(), [{struct, struct | nil}]) :: [atom]
  def unloadable_after_action(resource, table, columns) do
    loaded =
      for {%struct{name: name}, _declared} <- columns,
          struct in [
            Ash.Resource.Calculation,
            Ash.Resource.Aggregate,
            Ash.Resource.Relationships.BelongsTo
          ],
          do: name

    acting? =
      record_actions?(resource, table) or not is_nil(table.create_action)

    if acting? and is_nil(Info.primary_action(resource, :read)) and
         Editing.unloadable_after_save(resource, table, columns) == [],
       do: loaded,
       else: []
  end

  @doc """
  The primary read action of a resource whose table changes records, when
  that action is private; nil when nothing is wrong.

  Ash loads what a create, an update or a destroy action returns through
  the primary read action (ash 3.36.1: `Ash.Actions.Create`, `Update` and
  `Destroy` name it themselves), and asks its policies and field policies
  what of the result the person may have. No option of a call says
  otherwise, so a table that runs such an action runs the primary read
  action with it, whichever read action its block names. A table that only
  reads runs none of this.

  The table changes records when it has an editable column, a row action
  or a create action.
  """
  @spec private_result_read(Ash.Resource.t(), Table.t()) :: atom | nil
  def private_result_read(resource, table) do
    with %{public?: false, name: name} <- Info.primary_action(resource, :read),
         true <- changes?(resource, table) do
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
  the primary read action, without arguments (`private_result_read/2`), so
  a row could never be shown again after one.
  """
  @spec unanswered_result_read(Ash.Resource.t(), Table.t()) :: {atom, atom} | nil
  def unanswered_result_read(resource, table) do
    with %{name: name, arguments: arguments} <- Info.primary_action(resource, :read),
         %{name: argument} <-
           Enum.find(arguments, &(&1.allow_nil? == false and is_nil(&1.default))),
         true <- changes?(resource, table),
         true <- Enum.any?(columns(resource, table), fn {field, _declared} -> loaded?(field) end) do
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
  defp columns(resource, table) do
    case table.columns do
      [] ->
        Enum.map(Info.public_attributes(resource), &{&1, nil})

      declared ->
        for column <- declared, field = Info.field(resource, column.name), do: {field, column}
    end
  end

  defp changes?(resource, table) do
    columns = columns(resource, table)

    record_actions?(resource, table) or
      not is_nil(table.create_action) or
      Enum.any?(columns, fn {field, declared} ->
        Editing.update_action(resource, table, field, declared) != :none
      end)
  end

  # Whether the block names an action that returns a record, which the row
  # is then shown from: an update or a destroy action. A generic action
  # returns no row: the table reads again after it.
  defp record_actions?(resource, table) do
    Enum.any?(table.actions, fn %{name: name} ->
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

  def message({:page_argument_not_found, name, argument}),
    do:
      "The action `#{name}` says `page_argument :#{argument}`, and has no argument named " <>
        "`#{argument}`. A page argument is an argument of the action that the page fills."

  def message({:page_argument_not_public, name, argument}),
    do:
      "The action `#{name}` says `page_argument :#{argument}`, and its argument `#{argument}` " <>
        "is not public. A page gives a private argument through `private_arguments`, without " <>
        "a declaration; `page_argument` is for a public one that the panel is not to ask for."

  def message({:page_argument_is_record_argument, name, argument}),
    do:
      "The action `#{name}` says `page_argument :#{argument}`, and `#{argument}` is its " <>
        "`record_argument`, which the table gives the row's primary key. It cannot be both."

  def message({:page_argument_twice, name, argument}),
    do: "The action `#{name}` says `page_argument :#{argument}` more than once."

  def message(reason) when elem(reason, 0) in @undeclarable,
    do: Referencing.undeclarable_message(reason)

  def message({:no_field, what, name, %{name: input, sensitive?: true, type: {type, _}}}),
    do:
      "The #{what} action `#{name}` cannot be run from a table: its input `#{input}` is " <>
        "required and declared `sensitive?: true`, and has the type #{inspect(type)}. The " <>
        "action panel hides what is typed for a sensitive input, which it can do for text " <>
        "and for a number only."

  def message({:no_field, what, name, %{name: input, type: {type, _constraints}}}),
    do:
      "The #{what} action `#{name}` cannot be run from a table: its input `#{input}` is " <>
        "required, and a table has no field for its type (#{inspect(type)}). The action panel " <>
        "has fields for text, numbers, booleans, dates, datetimes, choices, arrays of those, " <>
        "values written as one line of text, such as a key, for embedded resources and " <>
        "maps whose every field is one of these, for unions whose every kind is, and for " <>
        "an argument that takes one file."

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
        AshDataTable.Resource.Reading.private_action() <>
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
