defmodule AshDataTable.Resource.Relating do
  @moduledoc false
  # What a row of a table can be expanded into: the relationships it offers,
  # and what can be done with the nested table of each. Shared by the
  # verifiers (which report a mistake) and the table model (which builds on
  # the answer).
  #
  # Only the destination's own declarations are read here, never its table
  # model: two resources that point at each other would otherwise never end.

  alias Ash.Resource.Info
  alias AshDataTable.Resource.Info, as: TableInfo
  alias AshDataTable.Resource.Reading
  alias AshDataTable.Resource.Table

  @type reason ::
          {:not_found, atom}
          | {:not_public, atom}
          | {:no_table, atom, Ash.Resource.t()}
          | {:no_such_table, atom, Ash.Resource.t(), atom}
          | {:declared_twice, atom}
          | private_read
          | {:page_sizes, atom, Ash.Resource.t(), atom, atom, [pos_integer],
             Reading.page_sizes_reason()}

  @typedoc """
  A relationship whose nested table would run a private read action: the
  relationship, the resource the action reads, the action, and whose choice
  the action is. For the related records: the relationship's `:own` or that
  of the destination's `:table`. For what Ash reads on the way to them
  (`passed/1`): that of the join relationship or of the `through` path.
  """
  @type private_read ::
          {:read_action_not_public, atom, Ash.Resource.t(), atom,
           :own | :table | {:join, atom, :own | :primary} | :through}

  @typedoc """
  A read action that Ash runs on the way to related records: of `resource`,
  `action` (nil when the resource has none to run, which is Ash's to
  report), chosen by the `:own` `read_action` of the relationship `by`, or
  the resource's `:primary` one for want of it.
  """
  @type passed :: %{
          resource: Ash.Resource.t(),
          action: Ash.Resource.Actions.Read.t() | nil,
          kind: :join | :through,
          by: atom,
          whose: :own | :primary
        }

  @doc """
  The relationships a row of `table` (an `AshDataTable.Resource.Table` of the
  resource) offers, each with its declaration in the block (nil for one of
  the default set), or what is wrong with the first declared one that cannot
  be offered.

  With no `relationship` in the block: every public relationship whose
  destination has a table, in the order of the resource, except manual
  relationships and those whose nested table would run a private read
  action. Once one is declared: exactly the declared ones, in the declared
  order; one of them that would run a private read action is a mistake.

  A relationship of the default set nests the destination's default table.
  A declared one nests the table of the destination that it names
  (`table`), else the default table too.
  """
  @spec offered(Ash.Resource.t(), Table.t()) ::
          {:ok, [{struct, AshDataTable.Resource.Relationship.t() | nil}]} | {:error, reason}
  def offered(resource, %Table{relationships: declared}) do
    case declared do
      [] ->
        {:ok,
         for relationship <- Info.public_relationships(resource),
             not manual?(relationship),
             table?(relationship.destination),
             not private_read?(relationship) do
           {relationship, nil}
         end}

      declared ->
        with :ok <- declared_once(declared) do
          Enum.reduce_while(declared, {:ok, []}, fn declaration, {:ok, found} ->
            with {:ok, relationship} <- declared(resource, declaration),
                 :ok <- public_read(relationship, nested(declaration)) do
              {:cont, {:ok, found ++ [{relationship, declaration}]}}
            else
              {:error, reason} -> {:halt, {:error, reason}}
            end
          end)
        end
    end
  end

  @doc """
  The relationship a `relationship` of the block names, or what is wrong
  with it: a public relationship of the resource, to a resource that has a
  table, and has the table the declaration names.
  """
  @spec declared(Ash.Resource.t() | Spark.Dsl.t(), AshDataTable.Resource.Relationship.t()) ::
          {:ok, struct} | {:error, reason}
  def declared(resource, %{name: name} = declaration) do
    case Info.relationship(resource, name) do
      nil ->
        {:error, {:not_found, name}}

      %{public?: false} ->
        {:error, {:not_public, name}}

      %{destination: destination} = relationship ->
        cond do
          not table?(destination) ->
            {:error, {:no_table, name, destination}}

          TableInfo.table(destination, nested(declaration)) == :error ->
            {:error, {:no_such_table, name, destination, declaration.table}}

          true ->
            {:ok, relationship}
        end
    end
  end

  @doc """
  The name of the destination's table that a `relationship` of the block
  nests: the one it names, else the default table. Nil stands for a
  relationship of the default set.
  """
  @spec nested(AshDataTable.Resource.Relationship.t() | nil) :: atom
  def nested(%{table: name}) when not is_nil(name), do: name
  def nested(_declaration_or_nil), do: :default

  defp declared_once(declared) do
    names = Enum.map(declared, & &1.name)

    case names -- Enum.uniq(names) do
      [] -> :ok
      [name | _] -> {:error, {:declared_twice, name}}
    end
  end

  @doc "Whether a resource has a table: it lists the extension `AshDataTable.Resource`."
  @spec table?(module) :: boolean
  def table?(resource) do
    match?({:module, _}, Code.ensure_compiled(resource)) and Info.resource?(resource) and
      AshDataTable.Resource in Spark.extensions(resource)
  end

  @doc """
  The read action a nested table of the relationship runs: the relationship's
  own `read_action` when it declares one, which says which records it means,
  else the read action of the destination's table of the name `table`: the
  one that is nested.
  """
  @spec read_action(struct, atom) :: {:ok, Ash.Resource.Actions.Read.t()} | {:error, term}
  def read_action(%{read_action: nil, destination: destination} = relationship, table) do
    case TableInfo.table(destination, table) do
      {:ok, nested} ->
        with {:error, {private, name}} when private in [:not_public, :primary_not_public] <-
               Reading.read_action(destination, nested) do
          {:error, {:read_action_not_public, relationship.name, destination, name, :table}}
        end

      :error ->
        {:error, {:no_such_table, relationship.name, destination, table}}
    end
  end

  def read_action(%{read_action: name, destination: destination} = relationship, _table) do
    case Info.action(destination, name) do
      %{type: :read, public?: false} ->
        {:error, {:read_action_not_public, relationship.name, destination, name, :own}}

      %{type: :read} = action ->
        {:ok, action}

      _other ->
        {:error, {:not_found, name}}
    end
  end

  @doc """
  The read actions Ash runs on the way to the records of a relationship,
  before the one that reads them (ash 3.34.4,
  `Ash.Actions.Read.Relationships`):

    * for a many-to-many, the one of the join resource: the `read_action`
      of the join relationship, else the join resource's primary read
      action. Its policies say which records are related at all;
    * for a relationship `through` a path of others, one for each resource
      in between: its primary read action. (Ash takes the `read_action` of
      the next relationship of the path by name, where the resource has an
      action of that name.)

  None for any other relationship.
  """
  @spec passed(struct) :: [passed]
  def passed(%{type: :many_to_many, through: through, join_relationship: join} = relationship)
      when is_atom(through) do
    name = Map.get(Info.relationship(relationship.source, join) || %{}, :read_action)
    [on_the_way(through, name, :join, join)]
  end

  def passed(%{through: [_ | _] = path, source: source}) do
    [_first | rest] = steps(source, path)
    for step <- rest, do: on_the_way(step.source, step.read_action, :through, step.name)
  end

  def passed(_relationship), do: []

  defp on_the_way(resource, nil, kind, by) do
    action = Info.primary_action(resource, :read)
    %{resource: resource, action: action, kind: kind, by: by, whose: :primary}
  end

  defp on_the_way(resource, name, kind, by) do
    action =
      with %{type: type} when type != :read <- Info.action(resource, name), do: nil

    %{resource: resource, action: action, kind: kind, by: by, whose: :own}
  end

  # The relationships of a `through` path, one after the other, as Ash
  # follows them: a relationship of the path that goes through a path
  # itself is replaced by its own.
  defp steps(resource, path) when is_nil(resource) or path == [], do: []

  defp steps(resource, [name | rest]) do
    case Info.relationship(resource, name) do
      nil ->
        []

      %{through: [_ | _] = path} ->
        nested = steps(resource, path)
        nested ++ steps(Map.get(List.last(nested) || %{}, :destination), rest)

      relationship ->
        [relationship | steps(relationship.destination, rest)]
    end
  end

  @doc """
  What is wrong with a relationship whose nested table would run a private
  read action, or `:ok`: the action that reads the related records, or one
  that Ash runs on the way to them. Anything else that keeps its read action
  from being used is the destination's to report, and the model's to refuse.
  """
  @spec public_read(struct, atom) :: :ok | {:error, private_read}
  def public_read(relationship, table) do
    case read_action(relationship, table) do
      {:error, {:read_action_not_public, _name, _destination, _action, _whose} = reason} ->
        {:error, reason}

      _ok_or_another_matter ->
        Enum.find_value(passed(relationship), :ok, fn
          %{action: %{public?: false} = action} = passed ->
            whose =
              case passed do
                %{kind: :join, by: join, whose: whose} -> {:join, join, whose}
                %{kind: :through} -> :through
              end

            {:error,
             {:read_action_not_public, relationship.name, passed.resource, action.name, whose}}

          _public_or_none ->
            nil
        end)
    end
  end

  @doc """
  What is wrong with the page sizes of the nested table of a relationship
  that has a `read_action` of its own, or `:ok`.

  The table that is nested (`table`, of the destination) says which page
  sizes a person is offered, and its own read action was checked against
  them where that table is declared. Under this relationship it is read
  through another action, which is the authority here: no size may be more
  than its `max_page_size`, and its `default_limit` has to be one of them.

  Nothing is wrong where the nested table has no pages under this
  relationship (`pageable?/2`): it then has no menu either. Nor where the
  relationship has no `read_action` of its own.
  """
  @spec page_sizes(struct, atom) :: :ok | {:error, reason}
  def page_sizes(%{read_action: nil}, _table), do: :ok

  def page_sizes(%{destination: destination} = relationship, table) do
    with {:ok, %Table{page_sizes: [_ | _] = sizes}} <- TableInfo.table(destination, table),
         {:ok, action} <- read_action(relationship, table),
         true <- pageable?(relationship, action),
         {:error, reasons} <- Reading.page_sizes(sizes, action),
         [reason | _] <- Enum.filter(reasons, &of_action?/1) do
      {:error, {:page_sizes, relationship.name, destination, table, action.name, sizes, reason}}
    else
      _nothing_wrong -> :ok
    end
  end

  # What the list itself lacks is the destination's to report.
  defp of_action?({kind, _, _, _}) when kind == :page_size_above_max, do: true
  defp of_action?({:default_limit_not_offered, _, _, _, _}), do: true
  defp of_action?(_of_the_list), do: false

  # of a relationship of the default set, which nests the default table
  defp private_read?(relationship), do: public_read(relationship, :default) != :ok

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
  back in full), through a read action that declares pagination and runs
  without being given an argument.

  A page of related records whose read action requires an argument fails
  (ash 3.34.4: beside the load that is given the arguments, Ash runs the
  action once more without any, and that one's "is required" is the
  answer). Without a page the same load is read with them, so such a
  nested table is shown in full.
  """
  @spec pageable?(struct, Ash.Resource.Actions.Read.t()) :: boolean
  def pageable?(relationship, read_action) do
    arrangeable?(relationship) and not Map.get(relationship, :no_attributes?, false) and
      Reading.supported_strategies(read_action.pagination) != [] and
      not Enum.any?(read_action.arguments, &AshDataTable.Resource.Arguing.needed?/1)
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
      "The destination of `#{name}`, #{inspect(destination)}, has no table: it does not list `AshDataTable.Resource` in its extensions. A row can only be expanded into the table of a resource that has one."

  def message({:no_such_table, name, destination, table}),
    do:
      "`#{name}` is to show the table `#{inspect(table)}` of its destination, but " <>
        TableInfo.no_table(destination, table)

  def message({:declared_twice, name}), do: "`#{name}` is declared more than once."

  def message({:page_sizes, name, destination, table, action, sizes, reason}),
    do:
      "`#{name}` shows #{Table.in_words(table)} of #{inspect(destination)}, which offers the page sizes #{inspect(sizes)}, and reads it through `#{inspect(action)}`, the relationship's own `read_action`. " <>
        Reading.message(reason)

  def message({:read_action_not_public, name, destination, action, :own}),
    do:
      "`#{name}` points to #{inspect(destination)}, whose read action `#{action}`, the relationship's own `read_action`, is not public. " <>
        Reading.private_action() <>
        " Make `#{action}` public, give the relationship a public `read_action`, or do not offer `#{name}` in this table."

  def message({:read_action_not_public, name, destination, action, :table}),
    do:
      "`#{name}` points to #{inspect(destination)}, whose read action `#{action}`, the one behind its table, is not public. " <>
        Reading.private_action() <>
        " Make `#{action}` public, name a public `read_action` in the `table` block of #{inspect(destination)} or on the relationship, or do not offer `#{name}` in this table."

  def message({:read_action_not_public, name, resource, action, {:join, join, :own}}),
    do:
      "`#{name}` is read through the join resource #{inspect(resource)}, whose read action `#{action}`, the `read_action` of the join relationship `#{join}`, is not public. " <>
        Reading.private_action() <>
        " Make `#{action}` public, give `#{join}` a public `read_action`, or do not offer `#{name}` in this table."

  def message({:read_action_not_public, name, resource, action, {:join, join, :primary}}),
    do:
      "`#{name}` is read through the join resource #{inspect(resource)}, whose read action `#{action}`, its primary read action, is not public. " <>
        Reading.private_action() <>
        " Make `#{action}` public, give the join relationship `#{join}` a public `read_action`, or do not offer `#{name}` in this table."

  def message({:read_action_not_public, name, resource, action, :through}),
    do:
      "`#{name}` is read through #{inspect(resource)}, a resource on its `through` path, whose read action `#{action}`, the one Ash reads it through there, is not public. " <>
        Reading.private_action() <>
        " Make `#{action}` public, or do not offer `#{name}` in this table."
end
