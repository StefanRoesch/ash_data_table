defmodule AshTable.Model do
  @moduledoc """
  The table model: everything a table is rendered from.

  It is built at runtime from `Ash.Resource.Info` and the resource's `table`
  block (see ADR 0001). Building is cheap and the result is not cached.

    * `resource` and its `primary_key`;
    * `read_action`, the name of the read action behind the table;
    * `pagination`, an `AshTable.Model.Pagination`;
    * `columns`, the ordered list of `AshTable.Model.Column`.

  ## Columns

  With no `column` in the block, the columns are the resource's public
  attributes in the order `Ash.Resource.Info.public_attributes/1` returns
  them. Once one `column` is declared, the columns are exactly the declared
  ones in the declared order. Calculations and aggregates appear only when
  named.

  ## Editing

  A column is editable in principle when it is an attribute, the attribute is
  writable, its cell type has an editor, and an update action can save it:
  the column's own `update_action`, else the table's, which accepts the
  attribute and has no required argument without a default. The column then
  carries that action, its editor and the question of its `confirm`. With no
  `update_action` at either level nothing is editable.
  """

  alias Ash.Resource.Info
  alias AshTable.Model.CellType
  alias AshTable.Model.Column
  alias AshTable.Model.Operator
  alias AshTable.Model.Pagination
  alias AshTable.Resource.Editing
  alias AshTable.Resource.Info, as: TableInfo
  alias AshTable.Resource.Reading

  @enforce_keys [:resource, :primary_key, :read_action, :pagination, :columns]
  defstruct [:resource, :primary_key, :read_action, :pagination, :columns]

  @type t :: %__MODULE__{
          resource: Ash.Resource.t(),
          primary_key: [atom],
          read_action: atom,
          pagination: Pagination.t(),
          columns: [Column.t()]
        }

  @default_page_size 25

  @doc """
  Builds the table model of a resource.

  The resource must list the extension `AshTable.Resource`. There are no
  options yet; the argument is reserved for what later slices need (the actor,
  for the columns a person may see).

  Raises `ArgumentError` for a resource without the extension, and for a
  `table` block with a mistake the compile-time checks report.
  """
  @spec build(Ash.Resource.t(), keyword) :: t
  def build(resource, _opts \\ []) do
    ensure_table!(resource)

    read_action = read_action!(resource)
    pagination = pagination(resource, read_action)

    columns =
      case TableInfo.table(resource) do
        [] ->
          Enum.map(Info.public_attributes(resource), &column(resource, &1, nil, pagination))

        declared ->
          Enum.map(declared, &column(resource, field!(resource, &1.name), &1, pagination))
      end

    %__MODULE__{
      resource: resource,
      primary_key: Info.primary_key(resource),
      read_action: read_action.name,
      pagination: pagination,
      columns: columns
    }
  end

  @doc """
  The fields of the table's columns that are not on a record unless asked
  for: its calculations and aggregates.
  """
  @spec loads(t) :: [atom]
  def loads(%__MODULE__{columns: columns}) do
    for %{kind: kind, name: name} <- columns, kind in [:calculation, :aggregate], do: name
  end

  @doc """
  What a field of the resource is called in this table: the label of its
  column, or its humanised name when the table has no column for it.
  """
  @spec field_label(t, atom) :: String.t()
  def field_label(%__MODULE__{columns: columns}, name) when is_atom(name) do
    case Enum.find(columns, &(&1.name == name)) do
      nil -> humanize(name)
      column -> column.label
    end
  end

  defp ensure_table!(resource) do
    if not (Ash.Resource.Info.resource?(resource) and
              AshTable.Resource in Spark.extensions(resource)) do
      raise ArgumentError,
            "#{inspect(resource)} does not list `AshTable.Resource` in its extensions, so it has no table. " <>
              "Add `extensions: [AshTable.Resource]` to its `use Ash.Resource`."
    end
  end

  # The verifiers report the mistakes below when the resource is compiled.
  # They are raised here for a resource that was compiled despite them.

  defp read_action!(resource) do
    case Reading.read_action(resource) do
      {:ok, action} ->
        action

      {:error, reason} ->
        raise ArgumentError,
              "cannot build the table of #{inspect(resource)}: " <>
                "no usable read action (#{inspect(reason)})"
    end
  end

  defp pagination(resource, read_action) do
    case Reading.strategy(resource, read_action) do
      {:ok, :none} ->
        %Pagination{strategy: :none, page_size: nil, countable?: false}

      {:ok, strategy} ->
        %{default_limit: default_limit, max_page_size: max_page_size, countable: countable} =
          read_action.pagination

        %Pagination{
          strategy: strategy,
          page_size: min(default_limit || @default_page_size, max_page_size),
          countable?: countable in [true, :by_default]
        }

      {:error, {:unsupported, strategy}} ->
        raise ArgumentError,
              "cannot build the table of #{inspect(resource)}: its read action " <>
                "`#{read_action.name}` does not support #{strategy} pagination"
    end
  end

  defp field!(resource, name) do
    Info.public_attribute(resource, name) ||
      Info.public_calculation(resource, name) ||
      Info.public_aggregate(resource, name) ||
      raise ArgumentError,
            "cannot build the table of #{inspect(resource)}: it declares the column `#{name}`, " <>
              "but the resource has no public attribute, calculation or aggregate of that name"
  end

  # `declared` is the column as written in the block, or nil for a column of
  # the default set.
  defp column(resource, field, declared, pagination) do
    {type, constraints} = CellType.type(resource, field)
    {cell_type, values} = CellType.classify(type, constraints)

    update_action =
      case Editing.update_action(resource, field, declared) do
        {:ok, name} -> name
        :none -> nil
      end

    %Column{
      editable?: not is_nil(update_action),
      update_action: update_action,
      editor: update_action && cell_type,
      confirm: update_action && declared && declared.confirm,
      name: field.name,
      kind: kind(field),
      label: (declared && declared.label) || humanize(field.name),
      type: {type, constraints},
      cell_type: cell_type,
      values: values,
      # the block can only switch sorting off
      sortable?:
        Reading.sortable?(resource, field.name, pagination.strategy) and
          not match?(%{sortable?: false}, declared),
      # and filtering likewise
      operators:
        if(match?(%{filterable?: false}, declared),
          do: [],
          else: Operator.available(resource, field)
        )
    }
  end

  defp kind(%Ash.Resource.Attribute{}), do: :attribute
  defp kind(%Ash.Resource.Calculation{}), do: :calculation
  defp kind(%Ash.Resource.Aggregate{}), do: :aggregate

  defp humanize(name) do
    name
    |> to_string()
    |> String.split("_", trim: true)
    |> Enum.with_index()
    |> Enum.map_join(" ", fn
      {"id", _index} -> "ID"
      {word, 0} -> String.capitalize(word)
      {word, _index} -> word
    end)
  end
end
