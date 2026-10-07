defmodule AshTable.Resource.Referencing do
  @moduledoc false
  # What a reference cell needs: the label a resource's records are called
  # by, and what a column that names a relationship shows of the related
  # record. Shared by the verifiers (which report a mistake) and the table
  # model (which builds on the answer).
  #
  # Only the destination's own declarations are read here, never its table
  # model, as in `AshTable.Resource.Relating`.

  alias Ash.Resource.Info
  alias AshTable.Resource.Info, as: TableInfo
  alias AshTable.Resource.Relating

  @type label_reason ::
          {:label_not_found, atom}
          | {:label_not_public, atom}
          | {:label_relationship, atom}
          | {:label_not_an_attribute, atom, :calculation | :aggregate}

  @type reason ::
          {:not_belongs_to, atom, atom}
          | {:no_table, atom, Ash.Resource.t()}
          | {:no_label_field, atom, Ash.Resource.t()}
          | {:unusable_label_field, atom, Ash.Resource.t(), label_reason}
          | {:no_read_action, atom, Ash.Resource.t()}

  @typedoc """
  What a reference column shows: the `label` attribute of the record the
  `relationship` points at, read through `read_action` of the destination.
  """
  @type t :: %{
          relationship: struct,
          label: Ash.Resource.Attribute.t(),
          read_action: atom
        }

  @relationships [
    Ash.Resource.Relationships.BelongsTo,
    Ash.Resource.Relationships.HasOne,
    Ash.Resource.Relationships.HasMany,
    Ash.Resource.Relationships.ManyToMany
  ]

  @doc "Whether what a column names is a relationship, and not a field."
  @spec relationship?(struct) :: boolean
  def relationship?(%struct{}), do: struct in @relationships

  @doc """
  The attribute a record of the resource is called by: the `label_field` of
  its `table` block. `:none` when the block names none.
  """
  @spec label_field(Ash.Resource.t() | Spark.Dsl.t()) ::
          {:ok, Ash.Resource.Attribute.t()} | :none | {:error, label_reason}
  def label_field(resource) do
    with {:ok, name} <- TableInfo.table_label_field(resource) do
      cond do
        attribute = Info.attribute(resource, name) ->
          if attribute.public?, do: {:ok, attribute}, else: {:error, {:label_not_public, name}}

        Info.relationship(resource, name) ->
          {:error, {:label_relationship, name}}

        Info.calculation(resource, name) ->
          {:error, {:label_not_an_attribute, name, :calculation}}

        Info.aggregate(resource, name) ->
          {:error, {:label_not_an_attribute, name, :aggregate}}

        true ->
          {:error, {:label_not_found, name}}
      end
    else
      :error -> :none
    end
  end

  @doc """
  What a column shows that names the relationship: the label of the related
  record. Only a belongs-to can be such a column, and only to a resource
  whose table says what its records are called by.

  The related record is read as Ash loads the relationship: through the
  relationship's own `read_action` when it declares one, else through the
  destination's primary read action.
  """
  @spec reference(struct) :: {:ok, t} | {:error, reason}
  def reference(%{name: name, destination: destination} = relationship) do
    cond do
      relationship.type != :belongs_to ->
        {:error, {:not_belongs_to, name, relationship.type}}

      not Relating.table?(destination) ->
        {:error, {:no_table, name, destination}}

      true ->
        with {:ok, label} <- label_of(name, destination),
             {:ok, read_action} <- read_action(relationship) do
          {:ok, %{relationship: relationship, label: label, read_action: read_action}}
        end
    end
  end

  defp label_of(name, destination) do
    case label_field(destination) do
      {:ok, label} -> {:ok, label}
      :none -> {:error, {:no_label_field, name, destination}}
      {:error, reason} -> {:error, {:unusable_label_field, name, destination, reason}}
    end
  end

  defp read_action(%{read_action: nil, name: name, destination: destination}) do
    case Info.primary_action(destination, :read) do
      nil -> {:error, {:no_read_action, name, destination}}
      action -> {:ok, action.name}
    end
  end

  defp read_action(%{read_action: read_action}), do: {:ok, read_action}

  @doc "What is wrong with a `label_field`, or with a column that names a relationship, for a diagnostic."
  @spec message(label_reason | reason) :: String.t()
  def message({:label_not_found, name}), do: "The resource has no attribute named `#{name}`."

  def message({:label_not_public, name}),
    do: "`#{name}` is not public. Only a `public?` attribute can be the label of a record."

  def message({:label_relationship, name}),
    do:
      "`#{name}` is a relationship. The label of a record is one of its own attributes: name an attribute of this resource."

  def message({:label_not_an_attribute, name, kind}),
    do:
      "`#{name}` is #{kind(kind)}. The label of a record has to be an attribute: it is read with the record's key and nothing else."

  def message({:not_belongs_to, name, type}),
    do:
      "`#{name}` is #{kind(type)} relationship. Only a belongs-to relationship can be a column: its cell shows the label of the one related record. Offer this one under the row with `relationship :#{name}`."

  def message({:no_table, name, destination}),
    do:
      "The destination of `#{name}`, #{inspect(destination)}, has no table: it does not list `AshTable.Resource` in its extensions. A column that names a relationship shows the related record's label, which the destination's table declares with `label_field`."

  def message({:no_label_field, name, destination}),
    do:
      "The destination of `#{name}`, #{inspect(destination)}, declares no `label_field`. A column that names a relationship shows the related record's label: add `label_field` to the `table` block of #{inspect(destination)}."

  def message({:unusable_label_field, name, destination, reason}),
    do:
      "The `label_field` of #{inspect(destination)}, the destination of `#{name}`, cannot be used. " <>
        message(reason)

  def message({:no_read_action, name, destination}),
    do:
      "The destination of `#{name}`, #{inspect(destination)}, has no primary read action, and the relationship names no `read_action`. The related record of a column is read as Ash loads the relationship, which needs one of the two."

  defp kind(:calculation), do: "a calculation"
  defp kind(:aggregate), do: "an aggregate"
  defp kind(:has_many), do: "a has-many"
  defp kind(:has_one), do: "a has-one"
  defp kind(:many_to_many), do: "a many-to-many"
  defp kind(type), do: "a #{type}"
end
