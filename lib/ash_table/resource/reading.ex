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

  @doc "Whether the resource allows sorting by the field under the given pagination strategy."
  @spec sortable?(Ash.Resource.t(), atom, strategy) :: boolean
  def sortable?(resource, name, strategy) do
    pagination_type = if strategy == :keyset, do: :keyset, else: :offset
    Info.sortable?(resource, name, pagination_type: pagination_type, include_private?: false)
  end
end
