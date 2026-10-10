defmodule AshTable.Resource.Referencing do
  @moduledoc false
  # What a reference cell needs: the label a resource's records are called
  # by, what a column that names a relationship shows of the related
  # record, and what a person chooses another related record with. Shared by
  # the verifiers (which report a mistake) and the table model (which builds
  # on the answer).
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
          | {:read_action_not_public, atom, Ash.Resource.t(), atom, :own | :primary}

  @typedoc """
  What a reference column shows: the `label` attribute of the record the
  `relationship` points at, read through `read_action` of the destination.
  """
  @type t :: %{
          relationship: struct,
          label: Ash.Resource.Attribute.t(),
          read_action: atom
        }

  @typedoc """
  What a person chooses the related record of a belongs-to relationship
  with: the picker, which shows the table of `destination` read through
  `read_action`, and gives the chosen record's `destination_attribute` as
  the value of `source_attribute`, the foreign key. `allow_nil?` says
  whether the key can be empty, which is when "none" can be chosen.
  """
  @type picking :: %{
          relationship: atom,
          destination: Ash.Resource.t(),
          source_attribute: atom,
          destination_attribute: atom,
          read_action: atom,
          allow_nil?: boolean
        }

  @typedoc "Why the related record of a relationship is not chosen in a picker."
  @type no_picker ::
          :filter
          | :no_table
          | :no_read_action
          | :key_not_found
          | :key_not_public
          | :key_not_writable

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
  destination's primary read action. Either has to be `public?`: a table
  runs no private action, and the read action of the destination's table
  does not come into it.
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
      nil ->
        {:error, {:no_read_action, name, destination}}

      %{public?: false} = action ->
        {:error, {:read_action_not_public, name, destination, action.name, :primary}}

      action ->
        {:ok, action.name}
    end
  end

  defp read_action(%{read_action: read_action, name: name, destination: destination}) do
    case Info.action(destination, read_action) do
      %{public?: false} ->
        {:error, {:read_action_not_public, name, destination, read_action, :own}}

      _public_or_ash_reports_it ->
        {:ok, read_action}
    end
  end

  @doc """
  What a person chooses the related record of a belongs-to relationship of
  `resource` with, or why there is nothing to choose it with.

  The records on offer are those of the destination's table: read through
  the relationship's own `read_action` when it declares one, which says
  which records it means and is the action Ash loads the related record
  through, else through the read action of the destination's table. Either
  has to be `public?`.

  There is no picker

    * where the destination has no table, as its table is what is shown;
    * where the relationship has a `filter`: which records it can then hold
      is for Ash's loader to say, with the record the relationship starts
      from, and a table cannot ask it for the candidates;
    * where the foreign key is no public, writable attribute: nothing from
      the outside sets it.
  """
  @spec picking(Ash.Resource.t() | Spark.Dsl.t(), struct) ::
          {:ok, picking} | {:error, no_picker}
  def picking(resource, %Ash.Resource.Relationships.BelongsTo{} = relationship) do
    %{destination: destination, source_attribute: source_attribute} = relationship

    with :ok <- unfiltered(relationship),
         :ok <- has_table(destination),
         {:ok, read_action} <- picker_read_action(relationship),
         {:ok, key} <- key(resource, source_attribute) do
      {:ok,
       %{
         relationship: relationship.name,
         destination: destination,
         source_attribute: source_attribute,
         destination_attribute: relationship.destination_attribute,
         read_action: read_action,
         allow_nil?: key.allow_nil?
       }}
    end
  end

  def picking(_resource, _relationship), do: {:error, :no_table}

  defp unfiltered(%{filter: nil}), do: :ok
  defp unfiltered(_relationship), do: {:error, :filter}

  defp has_table(destination),
    do: if(Relating.table?(destination), do: :ok, else: {:error, :no_table})

  # As a nested table of the relationship reads: `Relating.read_action/1`.
  defp picker_read_action(relationship) do
    case Relating.read_action(relationship) do
      {:ok, action} -> {:ok, action.name}
      {:error, _private_or_none} -> {:error, :no_read_action}
    end
  end

  defp key(resource, name) do
    case Info.attribute(resource, name) do
      nil -> {:error, :key_not_found}
      %{public?: false} -> {:error, :key_not_public}
      %{writable?: false} -> {:error, :key_not_writable}
      attribute -> {:ok, attribute}
    end
  end

  @doc "Why a relationship's related record is never chosen in a picker, for a diagnostic."
  @spec no_picker(struct, no_picker) :: String.t()
  def no_picker(relationship, :filter),
    do:
      "The relationship `#{relationship.name}` has a `filter`, so a table cannot say which records it can hold, and offers none to choose from."

  def no_picker(relationship, :no_table),
    do:
      "The destination of `#{relationship.name}`, #{inspect(relationship.destination)}, has no table to choose a record from."

  def no_picker(relationship, :no_read_action),
    do:
      "The records to choose from would be read through an action of #{inspect(relationship.destination)} that is not a public read action: the relationship's own `read_action`, or the one behind the destination's table. " <>
        AshTable.Resource.Reading.private_action()

  def no_picker(relationship, :key_not_found),
    do:
      "The resource has no attribute `#{relationship.source_attribute}`, the foreign key of `#{relationship.name}`."

  def no_picker(relationship, :key_not_public),
    do:
      "`#{relationship.source_attribute}`, the foreign key of `#{relationship.name}`, is not public (`attribute_public? false`). Only a `public?` attribute is set through a table."

  def no_picker(relationship, :key_not_writable),
    do:
      "`#{relationship.source_attribute}`, the foreign key of `#{relationship.name}`, is declared `attribute_writable? false`, so no action can set it."

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

  def message({:read_action_not_public, name, destination, action, whose}) do
    whose =
      case whose do
        :own -> "the relationship's own `read_action`"
        :primary -> "its primary read action"
      end

    "`#{name}` points to #{inspect(destination)}, whose read action `#{action}`, #{whose}, is not public. " <>
      "The related record of a column is read as Ash loads the relationship. " <>
      AshTable.Resource.Reading.private_action() <>
      " Make `#{action}` public, give the relationship a public `read_action`, or do not show `#{name}` as a column."
  end

  defp kind(:calculation), do: "a calculation"
  defp kind(:aggregate), do: "an aggregate"
  defp kind(:has_many), do: "a has-many"
  defp kind(:has_one), do: "a has-one"
  defp kind(:many_to_many), do: "a many-to-many"
  defp kind(type), do: "a #{type}"
end
