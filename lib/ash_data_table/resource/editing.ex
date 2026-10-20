defmodule AshDataTable.Resource.Editing do
  @moduledoc false
  # How a table edits its resource: the update action behind a column and
  # whether that action can serve an inline edit. Shared by the verifiers
  # (which report a mistake) and the table model (which builds on the answer).

  alias Ash.Resource.Info
  alias AshDataTable.Resource.CellType
  alias AshDataTable.Resource.Embedding
  alias AshDataTable.Resource.Exposing
  alias AshDataTable.Resource.Managing
  alias AshDataTable.Resource.Referencing
  alias AshDataTable.Resource.Table

  # The cell types with an editor.
  @editors [:text, :number, :boolean, :date, :datetime, :enum]

  @type reason ::
          {:not_found, atom}
          | {:not_an_update_action, atom, atom}
          | {:not_public, atom}

  @doc """
  The table-level update action of `table` (an `AshDataTable.Resource.Table`):
  `:none` when its block names none.
  """
  @spec table_action(Ash.Resource.t(), Table.t()) ::
          {:ok, Ash.Resource.Actions.Update.t()} | :none | {:error, reason}
  def table_action(_resource, %Table{update_action: nil}), do: :none
  def table_action(resource, %Table{update_action: name}), do: action(resource, name)

  @doc "The public update action of that name."
  @spec action(Ash.Resource.t(), atom) ::
          {:ok, Ash.Resource.Actions.Update.t()} | {:error, reason}
  def action(resource, name) do
    case Info.action(resource, name) do
      nil -> {:error, {:not_found, name}}
      %{type: :update, public?: false} -> {:error, {:not_public, name}}
      %{type: :update} = action -> {:ok, action}
      %{type: type} -> {:error, {:not_an_update_action, name, type}}
    end
  end

  @doc """
  The update action an inline edit of a column runs, or `:none` for a column
  that can never be edited. `declared` is the column as written in the block,
  or nil for a column of the default set.
  """
  @spec update_action(Ash.Resource.t(), Table.t(), struct, AshDataTable.Resource.Column.t() | nil) ::
          {:ok, atom} | :none
  def update_action(resource, table, field, declared) do
    case edit(resource, table, field, declared) do
      {:ok, name, _written} -> {:ok, name}
      :none -> :none
    end
  end

  @typedoc """
  What an edit of a cell gives its action, as the action's one input:

    * `{:attribute, name}` - the attribute itself, and for a reference cell
      the relationship's foreign key, which the action accepts. `picking`
      is then what the related record is chosen with
      (`AshDataTable.Resource.Referencing.picking/2`);
    * `{:argument, name}` - for a reference cell: an argument of the action
      that hands the key of the chosen record to the relationship
      (`AshDataTable.Resource.Managing`). `managing` is then what the record is
      chosen with (`AshDataTable.Resource.Referencing.managing/1`).
  """
  @type written ::
          {:attribute, atom}
          | {:attribute, atom, Referencing.picking()}
          | {:argument, atom, Referencing.managing()}

  @doc """
  The update action an inline edit of a column runs, with what the edit
  gives it; `:none` for a column that can never be edited. `declared` is as
  for `update_action/4`.
  """
  @spec edit(Ash.Resource.t(), Table.t(), struct, AshDataTable.Resource.Column.t() | nil) ::
          {:ok, atom, written} | :none
  def edit(resource, table, field, declared) do
    with {:ok, action} <- behind(resource, table, declared),
         {:ok, written} <- written(resource, action, field),
         [] <- required_arguments(action) -- given(written) do
      {:ok, action.name, written}
    else
      _ -> :none
    end
  end

  @doc """
  The arguments of its action that an edit gives itself: the one that hands
  the chosen record's key to the relationship. It is no argument the action
  lacks (`required_arguments/1`).
  """
  @spec given(written) :: [atom]
  def given({:argument, name, _managing}), do: [name]
  def given(_attribute), do: []

  @doc """
  The update action behind a column, whether or not it can save an edit of
  it: the column's own `update_action`, else the table's. `:none` where
  neither names one, or the column switches editing off.
  """
  @spec behind(Ash.Resource.t(), Table.t(), AshDataTable.Resource.Column.t() | nil) ::
          {:ok, Ash.Resource.Actions.Update.t()} | :none | {:error, reason}
  def behind(resource, table, declared) do
    case declared && declared.update_action do
      false -> :none
      nil -> table_action(resource, table)
      name -> action(resource, name)
    end
  end

  @typedoc """
  Why an action cannot save an edit of a reference cell:

    * `{:no_picker, reason}` - there is nothing to choose the related
      record with, whichever way the action takes it;
    * `:not_taken` - the action neither accepts the relationship's foreign
      key nor has an argument that hands a key to the relationship;
    * `{:several, argument}` - it has such an argument, which holds a list
      of keys: a cell holds one record;
    * `{:not_related, argument}` - it has such an argument, which does not
      relate the record it names (`on_lookup`);
    * `{:not_keys, argument, reason}` - an argument of it is handed to the
      relationship and holds no key
      (`t:AshDataTable.Resource.Managing.not_keys/0`).
  """
  @type not_written ::
          {:no_picker, Referencing.no_picker()}
          | :not_taken
          | {:several, atom}
          | {:not_related, atom}
          | {:not_keys, atom, Managing.not_keys()}

  @doc """
  What an edit of the field's cell gives the action as its one input, or why
  the action cannot save one.

  An attribute is given as itself, where the action accepts it and nothing
  keeps its cells from being edited (`obstacle/2`).

  A belongs-to relationship, whose cell is a reference cell, is given one of
  two ways, and the first that holds is taken:

    1. as the relationship's foreign key, where the action accepts it and
       the key is a public, writable attribute;
    2. through an argument of the action that a `manage_relationship`
       change hands to the relationship: a public argument that holds one
       key and relates the record it names (`on_lookup`). Where the action
       has several, the first in the action's order.
  """
  @spec written(Ash.Resource.t(), struct, struct) ::
          {:ok, written} | {:error, not_written | obstacle | :not_accepted}
  def written(resource, action, %Ash.Resource.Relationships.BelongsTo{} = relationship) do
    with {:ok, _read_action} <- chosen_from(relationship) do
      key =
        if relationship.source_attribute in action.accept,
          do: Referencing.picking(resource, relationship),
          else: :not_accepted

      case {key, by_argument(resource, action, relationship)} do
        {{:ok, picking}, _argument} -> {:ok, {:attribute, relationship.source_attribute, picking}}
        {_no_key, {:ok, name, managing}} -> {:ok, {:argument, name, managing}}
        # the key the action accepts is what is said of it first
        {{:error, reason}, _argument} -> {:error, {:no_picker, reason}}
        {:not_accepted, {:error, reason}} -> {:error, reason}
      end
    end
  end

  def written(resource, action, field) do
    cond do
      obstacle = obstacle(resource, field) -> {:error, obstacle}
      field.name in action.accept -> {:ok, {:attribute, field.name}}
      true -> {:error, :not_accepted}
    end
  end

  defp chosen_from(relationship) do
    with {:error, reason} <- Referencing.choosing(relationship),
         do: {:error, {:no_picker, reason}}
  end

  # The argument of the action through which a reference cell is edited: the
  # first public one that hands one key to the relationship and relates the
  # record it names. Else what is wrong with the first that is handed to
  # the relationship at all.
  defp by_argument(resource, action, relationship) do
    handed = Managing.handed(resource, action, relationship.name)

    found =
      Enum.find_value(handed, fn
        {name, {:ok, %{several?: false, relates?: true} = managed}} ->
          with {:ok, managing} <- Referencing.managing(managed), do: {:ok, name, managing}

        _another ->
          nil
      end)

    case {found, handed} do
      {{:ok, name, managing}, _handed} -> {:ok, name, managing}
      {{:error, reason}, _handed} -> {:error, {:no_picker, reason}}
      {nil, []} -> {:error, :not_taken}
      {nil, [{name, {:ok, %{several?: true}}} | _]} -> {:error, {:several, name}}
      {nil, [{name, {:ok, %{relates?: false}}} | _]} -> {:error, {:not_related, name}}
      {nil, [{name, {:error, reason}} | _]} -> {:error, {:not_keys, name, reason}}
    end
  end

  @typedoc "Why a field's cells can be edited through no action at all."
  @type obstacle ::
          :not_an_attribute
          | :not_writable
          | {:no_editor, Ash.Type.t()}
          | {:no_fields, Ash.Type.t(), String.t()}
          | {:no_kinds, Ash.Type.t(), String.t()}
          | {:sensitive, Ash.Type.t()}
          | {:no_picker, struct, Referencing.no_picker()}

  @doc """
  What keeps a field's cells from being edited whichever action is behind
  them, or nil when nothing does: an attribute is edited, which has to be
  writable and of a cell type that has an editor (a map cell where a person
  can give every one of its inputs, and a union where they can give every
  kind: `AshDataTable.Resource.Embedding`), and where it is sensitive, of one
  whose editor hides what is typed (`AshDataTable.Resource.Exposing.typed?/1`); and a
  belongs-to
  relationship, whose cell is a reference cell, when a person can choose
  its related record in a picker (`AshDataTable.Resource.Referencing.choosing/1`).
  What an action needs besides to save the choice is said of the action
  (`written/3`).
  """
  @spec obstacle(Ash.Resource.t(), struct) :: obstacle | nil
  def obstacle(resource, %Ash.Resource.Attribute{} = attribute) do
    cond do
      not attribute.writable? ->
        :not_writable

      is_nil(editor(resource, attribute)) ->
        case Embedding.of(attribute.type, attribute.constraints || []) do
          %{members: [_ | _], obstacle: obstacle} when is_binary(obstacle) ->
            {:no_kinds, attribute.type, obstacle}

          %{members: [], obstacle: obstacle} when is_binary(obstacle) ->
            {:no_kinds, attribute.type, obstacle}

          %{obstacle: obstacle} when is_binary(obstacle) ->
            {:no_fields, attribute.type, obstacle}

          _no_map_cell ->
            {:no_editor, attribute.type}
        end

      # what is typed for a sensitive field is hidden, which a table can do
      # for text and for a number alone
      Exposing.sensitive?(attribute) and not Exposing.typed?(editor(resource, attribute)) ->
        {:sensitive, attribute.type}

      true ->
        nil
    end
  end

  def obstacle(_resource, %Ash.Resource.Relationships.BelongsTo{} = relationship) do
    case Referencing.choosing(relationship) do
      {:ok, _read_action} -> nil
      {:error, reason} -> {:no_picker, relationship, reason}
    end
  end

  def obstacle(_resource, _field), do: :not_an_attribute

  @doc """
  The calculation, aggregate and reference columns that a row could not be
  shown with after a save: those of a table with editable columns whose
  resource has no primary read action, which is what Ash loads them through.
  Empty when nothing is wrong.

  `columns` are the fields of the table's columns, each with its column as
  written in the block (nil for a column of the default set).
  """
  @spec unloadable_after_save(Ash.Resource.t(), Table.t(), [
          {struct, AshDataTable.Resource.Column.t() | nil}
        ]) ::
          [atom]
  def unloadable_after_save(resource, table, columns) do
    loaded =
      for {%struct{name: name}, _declared} <- columns,
          struct in [
            Ash.Resource.Calculation,
            Ash.Resource.Aggregate,
            Ash.Resource.Relationships.BelongsTo
          ],
          do: name

    editable? =
      Enum.any?(columns, fn {field, declared} ->
        update_action(resource, table, field, declared) != :none
      end)

    if editable? and is_nil(Info.primary_action(resource, :read)), do: loaded, else: []
  end

  @typedoc """
  What a cell is edited with: the control of its cell type; for an array of
  enum values `:choices`, one checkbox per value of the enum (multiple
  choice); and for any other array `:list`, one control per value, of the
  values' cell type, with a way to add a value and to remove one. A map cell
  is edited as a `:group` of its fields, each with the control of its own
  type, and an array of them as `:groups`, one group per value; both in the
  side panel, never in the cell. A union is edited there as well (`:union`):
  the kind is chosen first, then that kind's value is given.
  """
  @type editor ::
          :text
          | :number
          | :boolean
          | :date
          | :datetime
          | :enum
          | :choices
          | :list
          | :group
          | :groups
          | :union

  @doc """
  What a field's cells are edited with, by cell type; nil for a type without
  an editor (keys, times and so on, the arrays of those, and a map cell or
  a union with an input a person cannot give).
  """
  @spec editor(Ash.Resource.t(), struct) :: editor | nil
  def editor(resource, field) do
    {type, constraints} = CellType.type(resource, field)
    {cell_type, _values} = CellType.classify(type, constraints)
    editor(cell_type, type, constraints)
  end

  @doc """
  The editor of a cell type, for a value of that Ash type; nil for one
  without. A map cell and a union have one when
  `AshDataTable.Resource.Embedding` finds nothing that keeps them from being
  edited.
  """
  @spec editor(CellType.t(), Ash.Type.t() | nil, keyword) :: editor | nil
  def editor(cell_type, type, constraints)
      when cell_type in [:map, {:array, :map}, :union, {:array, :union}] do
    case {Embedding.of(type, constraints), cell_type} do
      {%{obstacle: nil}, :map} -> :group
      {%{obstacle: nil}, :union} -> :union
      {%{obstacle: nil}, {:array, :map}} -> :groups
      _obstacle_or_none -> nil
    end
  end

  def editor(cell_type, _type, _constraints) when cell_type in @editors, do: cell_type
  def editor({:array, :enum}, _type, _constraints), do: :choices
  def editor({:array, item}, _type, _constraints) when item in @editors, do: :list
  def editor(_cell_type, _type, _constraints), do: nil

  @doc """
  Whether the action takes the field as an attribute it accepts: the field
  itself, and for a belongs-to relationship its foreign key.
  """
  @spec accepts?(Ash.Resource.Actions.Update.t(), struct) :: boolean
  def accepts?(action, %Ash.Resource.Attribute{name: name}), do: name in action.accept

  def accepts?(action, %Ash.Resource.Relationships.BelongsTo{source_attribute: name}),
    do: name in action.accept

  def accepts?(_action, _field), do: false

  @doc """
  The arguments the action cannot run without: required, and without a
  default. An inline edit supplies one value, the cell's, so an action with
  such an argument cannot serve one. Attributes the action requires are no
  obstacle: they are already on the record.
  """
  @spec required_arguments(Ash.Resource.Actions.Update.t()) :: [atom]
  def required_arguments(action) do
    for %{allow_nil?: false, default: nil, name: name} <- action.arguments, do: name
  end

  @doc """
  Why a column can never be edited, for a diagnostic: by its obstacle, or
  with nil, when nothing but the lack of an action that saves it stands in
  the way.
  """
  @spec never_edited(obstacle | nil) :: String.t()
  def never_edited(:not_writable), do: "Its attribute is declared `writable?: false`."

  def never_edited({:no_editor, type}),
    do: "It has the type `#{inspect(type)}`, which a table has no editor for."

  def never_edited({:no_fields, type, obstacle}),
    do:
      "It has the type `#{inspect(type)}`, which a table edits field by field, and here it " <>
        "cannot. " <> obstacle

  def never_edited({:no_kinds, type, obstacle}),
    do:
      "It has the type `#{inspect(type)}`, a union, which a table edits kind by kind, and here " <>
        "it cannot. " <> obstacle

  def never_edited({:sensitive, type}),
    do:
      "It is declared `sensitive?: true` and has the type `#{inspect(type)}`. A table hides " <>
        "what is typed for a sensitive field, which it can do for text and for a number only."

  def never_edited({:no_picker, relationship, reason}),
    do: Referencing.no_picker(relationship, reason)

  def never_edited(_other),
    do:
      "A column is edited through an `update_action`, its own or the table's, that accepts its attribute."

  @doc """
  Why an action cannot save an edit of a reference cell, for a diagnostic:
  what `written/3` says of the action `name` and the belongs-to
  `relationship`, but for the lack of a picker, which
  `AshDataTable.Resource.Referencing.no_picker/2` says.
  """
  @spec not_written(atom, struct, not_written) :: String.t()
  def not_written(name, relationship, :not_taken),
    do:
      "The update action `#{name}` does not accept `#{relationship.source_attribute}`, the foreign key of `#{relationship.name}`, and has no argument that a `manage_relationship` change hands to `#{relationship.name}`, so it cannot save an edit of this column."

  def not_written(name, relationship, {:several, argument}),
    do:
      "The update action `#{name}` hands its argument `#{argument}` to `#{relationship.name}` as a list of keys. A cell holds one related record, and an edit of this column gives the action one key: the argument has to hold one key, not a list."

  def not_written(name, relationship, {:not_related, argument}),
    do:
      "The update action `#{name}` hands its argument `#{argument}` to `#{relationship.name}`, and does not relate the record the argument names: its `manage_relationship` change has no `on_lookup` (`type: :append` and `type: :append_and_remove` have one). An edit of this column chooses another record, which the action has to relate."

  def not_written(name, relationship, {:not_keys, argument, reason}),
    do:
      "The update action `#{name}` hands its argument `#{argument}` to `#{relationship.name}`, and the argument does not hold the key of a related record: #{not_keys(relationship, reason)}. A table edits a relationship by choosing an existing record, whose key it gives the action, so it cannot save an edit of this column."

  defp not_keys(relationship, :no_key),
    do:
      "#{inspect(relationship.destination)} has no one attribute to name a record by (its primary key is not one attribute, and the change names no `value_is_key`)"

  defp not_keys(relationship, {:not_a_key, type, key, key_type}),
    do:
      "it is of the type #{inspect(type)}, which is not stored as `#{key}`, the key of #{inspect(relationship.destination)}, is (#{inspect(key_type)})"

  @doc "What is wrong with a named update action, for a diagnostic."
  @spec message(reason) :: String.t()
  def message({:not_found, name}), do: "The resource has no action named `#{name}`."

  def message({:not_an_update_action, name, type}),
    do: "`#{name}` is #{kind(type)} action, not an update action."

  def message({:not_public, name}),
    do: "The update action `#{name}` is not public. Only `public?` actions can be behind a table."

  defp kind(:action), do: "a generic"
  defp kind(type), do: "a #{type}"
end
