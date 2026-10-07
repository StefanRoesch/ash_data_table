defmodule AshTable.Resource.Reading do
  @moduledoc false
  # How a table reads its resource: the read action behind it, the pagination
  # strategy and what that strategy leaves sortable. Shared by the verifiers
  # (which report a mistake) and the table model (which builds on the answer).

  alias Ash.Resource.Info
  alias AshTable.Resource.Info, as: TableInfo

  @type strategy :: :offset | :keyset | :none

  @doc "The read action behind the table: the one named in the block, else the primary read action."
  @spec read_action(Ash.Resource.t()) ::
          {:ok, Ash.Resource.Actions.Read.t()}
          | {:error,
             :no_primary_read_action
             | {:not_found, atom}
             | {:not_a_read_action, atom, atom}
             | {:not_public, atom}}
  def read_action(resource) do
    case TableInfo.table_read_action(resource) do
      {:ok, name} ->
        case Info.action(resource, name) do
          nil -> {:error, {:not_found, name}}
          %{type: :read, public?: false} -> {:error, {:not_public, name}}
          %{type: :read} = action -> {:ok, action}
          %{type: type} -> {:error, {:not_a_read_action, name, type}}
        end

      :error ->
        case Info.primary_action(resource, :read) do
          nil -> {:error, :no_primary_read_action}
          action -> {:ok, action}
        end
    end
  end

  @doc "The pagination strategy: the one named in the block, else offset if the action supports it, else keyset."
  @spec strategy(Ash.Resource.t(), Ash.Resource.Actions.Read.t()) ::
          {:ok, strategy} | {:error, {:unsupported, :offset | :keyset}}
  def strategy(resource, %{pagination: pagination}) do
    supported = supported_strategies(pagination)

    case TableInfo.table_paginate_with(resource) do
      {:ok, strategy} ->
        if strategy in supported, do: {:ok, strategy}, else: {:error, {:unsupported, strategy}}

      :error ->
        {:ok, List.first(supported, :none)}
    end
  end

  @doc "The strategies a read action's pagination supports, offset first."
  @spec supported_strategies(term) :: [:offset | :keyset]
  def supported_strategies(%{offset?: offset?, keyset?: keyset?}) do
    if(offset?, do: [:offset], else: []) ++ if keyset?, do: [:keyset], else: []
  end

  def supported_strategies(_none), do: []

  @doc """
  The arguments a field cannot be read without: those of a calculation that
  are required and have no default. A table supplies no arguments, so a
  calculation with one cannot be a column.
  """
  @spec required_arguments(struct) :: [atom]
  def required_arguments(%Ash.Resource.Calculation{arguments: arguments}) do
    for %{allow_nil?: false, default: nil, name: name} <- arguments, do: name
  end

  def required_arguments(_field), do: []

  @doc "Whether the resource allows sorting by the field under the given pagination strategy."
  @spec sortable?(Ash.Resource.t(), atom, strategy) :: boolean
  def sortable?(resource, name, strategy) do
    pagination_type = if strategy == :keyset, do: :keyset, else: :offset
    Info.sortable?(resource, name, pagination_type: pagination_type, include_private?: false)
  end

  @doc """
  The `first` aggregates among `fields` that a table reads apart from the
  rest of a row, each with the calculation among them that makes it so.

  Internal ticket #32, a defect in ash_sql 0.8.1: a `first` aggregate over
  one related record (through belongs-to relationships, or has-one
  relationships on a key of the destination) is read on a plain join when
  it has no `join_filter` and no read action of its own. When the same
  statement joins that relationship another way first, the aggregate's
  value is taken from that join, which carries no policy of the related
  resource: the value of a record the reader may not read comes back. In a
  table, the other join is that of an expression calculation column that
  reaches through the same relationship.

  So such an aggregate is never in a statement with such a calculation: it
  is loaded in a step of its own, and the table does not sort or filter by
  it, which would put it there. `fields` are the fields of the table's
  columns.
  """
  @spec apart(Ash.Resource.t(), [struct]) :: [{atom, atom}]
  def apart(resource, fields) do
    reached =
      for %Ash.Resource.Calculation{
            name: name,
            calculation: {Ash.Resource.Calculation.Expression, opts}
          } <- fields,
          {[_ | _] = path, _field} <- AshTable.Resource.Exposing.references(resource, opts[:expr]),
          do: {name, path}

    for %Ash.Resource.Aggregate{kind: :first, relationship_path: path} = aggregate <- fields,
        aggregate.join_filters in [nil, [], %{}],
        is_nil(aggregate.read_action),
        one_record?(resource, path),
        {calculation, _path} <-
          Enum.take(
            Enum.filter(reached, fn {_name, reached} -> List.starts_with?(reached, path) end),
            1
          ) do
      {aggregate.name, calculation}
    end
  end

  # As ash_sql decides that a path of relationships leads to one record.
  defp one_record?(_resource, []), do: true

  defp one_record?(resource, [name | rest]) do
    case Info.relationship(resource, name) do
      %{type: :belongs_to} = relationship ->
        one_record?(relationship.destination, rest)

      %{type: :has_one, from_many?: false, destination: destination} = relationship ->
        keys = [Info.primary_key(destination) | Enum.map(Info.identities(destination), & &1.keys)]

        [relationship.destination_attribute] in keys and one_record?(destination, rest)

      _other ->
        false
    end
  end
end
