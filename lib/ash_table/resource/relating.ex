defmodule AshTable.Resource.Relating do
  @moduledoc false
  # What a row of a table can be expanded into: the relationships it offers,
  # and what can be done with the nested table of each. Shared by the
  # verifiers (which report a mistake) and the table model (which builds on
  # the answer).
  #
  # Only the destination's own declarations are read here, never its table
  # model: two resources that point at each other would otherwise never end.

  alias Ash.Resource.Info
  alias AshTable.Resource.Info, as: TableInfo
  alias AshTable.Resource.Reading

  @type reason ::
          {:not_found, atom}
          | {:not_public, atom}
          | {:no_table, atom, Ash.Resource.t()}
          | {:declared_twice, atom}

  @doc """
  The relationships a row offers, each with its declaration in the block
  (nil for one of the default set), or what is wrong with the first declared
  one that cannot be offered.

  With no `relationship` in the block: every public relationship whose
  destination has a table, in the order of the resource, except manual
  relationships. Once one is declared: exactly the declared ones, in the
  declared order.
  """
  @spec offered(Ash.Resource.t()) ::
          {:ok, [{struct, AshTable.Resource.Relationship.t() | nil}]} | {:error, reason}
  def offered(resource) do
    case TableInfo.relationships(resource) do
      [] ->
        {:ok,
         for relationship <- Info.public_relationships(resource),
             not manual?(relationship),
             table?(relationship.destination) do
           {relationship, nil}
         end}

      declared ->
        with :ok <- declared_once(declared) do
          Enum.reduce_while(declared, {:ok, []}, fn declaration, {:ok, found} ->
            case declared(resource, declaration.name) do
              {:ok, relationship} -> {:cont, {:ok, found ++ [{relationship, declaration}]}}
              {:error, reason} -> {:halt, {:error, reason}}
            end
          end)
        end
    end
  end

  @doc "The relationship a `relationship` of the block names, or what is wrong with it."
  @spec declared(Ash.Resource.t() | Spark.Dsl.t(), atom) :: {:ok, struct} | {:error, reason}
  def declared(resource, name) do
    case Info.relationship(resource, name) do
      nil ->
        {:error, {:not_found, name}}

      %{public?: false} ->
        {:error, {:not_public, name}}

      %{destination: destination} = relationship ->
        if table?(destination),
          do: {:ok, relationship},
          else: {:error, {:no_table, name, destination}}
    end
  end

  defp declared_once(declared) do
    names = Enum.map(declared, & &1.name)

    case names -- Enum.uniq(names) do
      [] -> :ok
      [name | _] -> {:error, {:declared_twice, name}}
    end
  end

  @doc "Whether a resource has a table: it lists the extension `AshTable.Resource`."
  @spec table?(module) :: boolean
  def table?(resource) do
    match?({:module, _}, Code.ensure_compiled(resource)) and Info.resource?(resource) and
      AshTable.Resource in Spark.extensions(resource)
  end

  @doc """
  The read action a nested table of the relationship runs: the relationship's
  own `read_action` when it declares one, which says which records it means,
  else the read action of the destination's table.
  """
  @spec read_action(struct) :: {:ok, Ash.Resource.Actions.Read.t()} | {:error, term}
  def read_action(%{read_action: nil, destination: destination}),
    do: Reading.read_action(destination)

  def read_action(%{read_action: name, destination: destination}) do
    case Info.action(destination, name) do
      %{type: :read} = action -> {:ok, action}
      _other -> {:error, {:not_found, name}}
    end
  end

  @doc "Whether the relationship is fetched by a module of the resource's own."
  @spec manual?(struct) :: boolean
  def manual?(relationship), do: not is_nil(Map.get(relationship, :manual))

  @doc """
  Whether a person can sort and filter the nested table: not for a single
  related record, where a sort or a filter would change which record it is,
  and not for a manual relationship, whose module may or may not honour them.
  """
  @spec arrangeable?(struct) :: boolean
  def arrangeable?(relationship),
    do: relationship.cardinality == :many and not manual?(relationship)

  @doc """
  Whether Ash can page through the related records: several of them, joined
  by attributes (a manual relationship and one with `no_attributes?` come
  back in full), through a read action that declares pagination.
  """
  @spec pageable?(struct, Ash.Resource.Actions.Read.t()) :: boolean
  def pageable?(relationship, read_action) do
    arrangeable?(relationship) and not Map.get(relationship, :no_attributes?, false) and
      Reading.supported_strategies(read_action.pagination) != []
  end

  @doc """
  What joins a record created in the nested table to the row: the row's
  attribute and the new record's attribute that takes its value. Only a
  has-many joined by attributes has it: a many-to-many is joined by a record
  of another resource, a relationship to one record already has its record,
  and a manual one or one with `no_attributes?` is joined by nothing a table
  could fill in.
  """
  @spec link(struct) :: {atom, atom} | nil
  def link(%{type: :has_many} = relationship) do
    if not manual?(relationship) and not Map.get(relationship, :no_attributes?, false),
      do: {relationship.source_attribute, relationship.destination_attribute}
  end

  def link(_relationship), do: nil

  @doc "What is wrong with a declared relationship, for a diagnostic."
  @spec message(reason) :: String.t()
  def message({:not_found, name}), do: "The resource has no relationship named `#{name}`."

  def message({:not_public, name}),
    do: "`#{name}` is not public. Only `public?` relationships can be offered by a table."

  def message({:no_table, name, destination}),
    do:
      "The destination of `#{name}`, #{inspect(destination)}, has no table: it does not list `AshTable.Resource` in its extensions. A row can only be expanded into the table of a resource that has one."

  def message({:declared_twice, name}), do: "`#{name}` is declared more than once."
end
