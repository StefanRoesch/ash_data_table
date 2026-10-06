defmodule AshTable.Resource.Editing do
  @moduledoc false
  # How a table edits its resource: the update action behind a column and
  # whether that action can serve an inline edit. Shared by the verifiers
  # (which report a mistake) and the table model (which builds on the answer).

  alias Ash.Resource.Info
  alias AshTable.Model.CellType
  alias AshTable.Resource.Info, as: TableInfo

  # The cell types with an editor.
  @editors [:text, :number, :boolean, :date, :datetime, :enum]

  @type reason ::
          {:not_found, atom}
          | {:not_an_update_action, atom, atom}
          | {:not_public, atom}

  @doc "The table-level update action: `:none` when the block names none."
  @spec table_action(Ash.Resource.t()) ::
          {:ok, Ash.Resource.Actions.Update.t()} | :none | {:error, reason}
  def table_action(resource) do
    case TableInfo.table_update_action(resource) do
      {:ok, name} -> action(resource, name)
      :error -> :none
    end
  end

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
  @spec update_action(Ash.Resource.t(), struct, AshTable.Resource.Column.t() | nil) ::
          {:ok, atom} | :none
  def update_action(resource, field, declared) do
    found =
      case declared && declared.update_action do
        false -> :none
        nil -> table_action(resource)
        name -> action(resource, name)
      end

    with {:ok, action} <- found,
         nil <- obstacle(resource, field),
         true <- accepts?(action, field),
         [] <- required_arguments(action) do
      {:ok, action.name}
    else
      _ -> :none
    end
  end

  @typedoc "Why a field's cells can be edited through no action at all."
  @type obstacle :: :not_an_attribute | :not_writable | {:no_editor, Ash.Type.t()}

  @doc """
  What keeps a field's cells from being edited whichever action is behind
  them, or nil when nothing does: only an attribute is edited, it has to be
  writable, and its cell type has to have an editor.
  """
  @spec obstacle(Ash.Resource.t(), struct) :: obstacle | nil
  def obstacle(resource, %Ash.Resource.Attribute{} = attribute) do
    cond do
      not attribute.writable? -> :not_writable
      is_nil(editor(resource, attribute)) -> {:no_editor, attribute.type}
      true -> nil
    end
  end

  def obstacle(_resource, _field), do: :not_an_attribute

  @doc """
  The calculation and aggregate columns that a row could not be shown with
  after a save: those of a table with editable columns whose resource has no
  primary read action, which is what Ash loads them through. Empty when
  nothing is wrong.

  `columns` are the fields of the table's columns, each with its column as
  written in the block (nil for a column of the default set).
  """
  @spec unloadable_after_save(Ash.Resource.t(), [{struct, AshTable.Resource.Column.t() | nil}]) ::
          [atom]
  def unloadable_after_save(resource, columns) do
    loaded =
      for {%struct{name: name}, _declared} <- columns,
          struct in [Ash.Resource.Calculation, Ash.Resource.Aggregate],
          do: name

    editable? =
      Enum.any?(columns, fn {field, declared} ->
        update_action(resource, field, declared) != :none
      end)

    if editable? and is_nil(Info.primary_action(resource, :read)), do: loaded, else: []
  end

  @doc """
  What a field's cells are edited with, by cell type; nil for a type without
  an editor (arrays, maps, embedded resources, keys, times and so on).
  """
  @spec editor(Ash.Resource.t(), struct) :: CellType.t() | nil
  def editor(resource, field) do
    case CellType.of(resource, field) do
      {cell_type, _values} when cell_type in @editors -> cell_type
      _ -> nil
    end
  end

  @doc "Whether the action takes the field as an input: an attribute it accepts."
  @spec accepts?(Ash.Resource.Actions.Update.t(), struct) :: boolean
  def accepts?(action, %Ash.Resource.Attribute{name: name}), do: name in action.accept
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
