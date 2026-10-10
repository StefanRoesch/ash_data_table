defmodule AshTable.Resource.Reading do
  @moduledoc false
  # How a table reads its resource: the read action behind it, the pagination
  # strategy and what that strategy leaves sortable. Shared by the verifiers
  # (which report a mistake) and the table model (which builds on the answer).

  alias Ash.Resource.Info
  alias AshTable.Resource.Info, as: TableInfo
  alias AshTable.Resource.Relating

  @type strategy :: :offset | :keyset | :none

  @type reason ::
          :no_primary_read_action
          | {:not_found, atom}
          | {:not_a_read_action, atom, atom}
          | {:not_public, atom}
          | {:primary_not_public, atom}
          | private_read

  @doc """
  The read action behind the table: the one named in the block, else the
  primary read action. Either has to be `public?`: a table runs no private
  action, however it came by it.
  """
  @spec read_action(Ash.Resource.t()) :: {:ok, Ash.Resource.Actions.Read.t()} | {:error, reason}
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
          %{public?: false, name: name} -> {:error, {:primary_not_public, name}}
          action -> {:ok, action}
        end
    end
  end

  @doc """
  Why a table runs no private action, for a diagnostic. Ash itself runs one
  for whoever its policies allow, and the policy its documentation gives for
  a private action allows everybody
  (`bypass private_action?() do authorize_if always() end`): what keeps such
  an action from a person is that no interface runs it.
  """
  @spec private_action() :: String.t()
  def private_action,
    do:
      "A table only runs `public?` actions: a private action is not meant for interfaces, and may be exempt from policies."

  @doc "What is wrong with the read action behind the table, for a diagnostic."
  @spec message(reason) :: String.t()
  def message({:not_found, name}), do: "The resource has no action named `#{name}`."

  def message({:not_a_read_action, name, type}),
    do: "`#{name}` is #{kind(type)} action, not a read action."

  def message({:not_public, name}),
    do: "The read action `#{name}` is not public. Only `public?` actions can be behind a table."

  def message({:primary_not_public, name}),
    do:
      "The primary read action `#{name}` is not public, and the table names no `read_action`, so it would read through it. " <>
        private_action() <>
        " Make `#{name}` public, or name a public read action with `read_action`."

  def message({:column_read_not_public, name, kind, read}) do
    %{resource: resource, action: action, how: how, from: from} = read

    {whose, remedy} =
      case how do
        :own ->
          {"the aggregate's own `read_action`", "give the aggregate a public `read_action`, "}

        {:relationship, _relationship, :primary, true} ->
          {"its primary read action", "give the aggregate a public `read_action`, "}

        {:relationship, relationship, :primary, false} ->
          {"its primary read action",
           "give the relationship `#{relationship}` a public `read_action`, "}

        {:relationship, relationship, :own, _last?} ->
          {"the `read_action` of the relationship `#{relationship}`",
           "give the relationship a public `read_action`, "}

        {:join, relationship, join, :own} ->
          {"the `read_action` of `#{join}`, the join relationship of `#{relationship}`",
           "give `#{join}` a public `read_action`, "}

        {:join, relationship, join, :primary} ->
          {"its primary read action, as the join resource of `#{relationship}`",
           "give the join relationship `#{join}` a public `read_action`, "}

        {:through, relationship} ->
          {"the action Ash reads it through on the `through` path of `#{relationship}`", ""}
      end

    reads =
      if is_nil(from) or (kind == :aggregate and from == name),
        do: "The aggregate `#{name}` reads",
        else: "The #{kind} `#{name}` is computed from the aggregate `#{from}`: it reads"

    "#{reads} #{inspect(resource)} through `#{action}`, #{whose}, which is not public. " <>
      private_action() <>
      " Make `#{action}` public, #{remedy}or do not show `#{name}` as a column."
  end

  def message(:no_primary_read_action),
    do:
      "The resource has no primary read action. Name the read action behind the table with `read_action`."

  defp kind(:action), do: "a generic"
  defp kind(:update), do: "an update"
  defp kind(type), do: "a #{type}"

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

  @typedoc """
  A read action that Ash runs to compute a column, and that is private: of
  `resource`, named `action`. `how` says whose choice it is: the
  aggregate's `:own` `read_action`, that of a `{:relationship, name, whose,
  last?}` of the aggregate's path (its `:own`, or the `:primary` one of its
  destination for want of one; `last?` for the relationship the aggregate
  is over), or one Ash runs on the way through that relationship
  (`AshTable.Resource.Relating.passed/1`). `from` is nil for the aggregate
  that is the column, else the name of the aggregate the column is computed
  from.
  """
  @type private_read ::
          {:column_read_not_public, atom, :aggregate | :calculation,
           %{
             resource: Ash.Resource.t(),
             action: atom,
             how:
               :own
               | {:relationship, atom | nil, :own | :primary, boolean}
               | {:join, atom, atom, :own | :primary}
               | {:through, atom},
             from: atom | String.t() | nil
           }}

  @doc """
  What is wrong with an aggregate or a calculation column that Ash computes
  through a private read action, or nil.

  An aggregate is read through actions of the resources on its path, as
  Ash applies their policies to it (ash 3.34.4, observed on Postgres): for
  each relationship of the path its own `read_action`, else the primary
  read action of its destination, and what Ash runs on the way through it
  (`AshTable.Resource.Relating.passed/1`); for the last relationship, the
  aggregate's own `read_action` besides, which stands in for the primary
  one. Each has to be `public?` for the aggregate to be a column.

  A calculation is looked into as far as it is an expression: the
  aggregates it holds, by name or written out (`count(comments)`), are read
  in the same way, and so are those of an expression calculation it
  references, and those an aggregate is taken over (its `field`) or filtered
  by. What a calculation references otherwise runs no action: Ash applies
  no policy to it (see `AshTable.Resource.Exposing`). A calculation
  computed in Elixir cannot be looked into.
  """
  @spec private_read(Ash.Resource.t(), struct) :: private_read | nil
  def private_read(resource, %struct{name: name} = field)
      when struct in [Ash.Resource.Aggregate, Ash.Resource.Calculation] do
    kind = if struct == Ash.Resource.Aggregate, do: :aggregate, else: :calculation

    Enum.find_value(reads(resource, field, nil, [{resource, name}]), fn
      %{action: %{public?: false, name: action}} = read ->
        {:column_read_not_public, name, kind, %{read | action: action}}

      _public_or_ash_reports_it ->
        nil
    end)
  end

  def private_read(_resource, _field), do: nil

  # The read actions Ash runs to compute a field of `resource`. `from` is
  # the aggregate they are run for, nil for the field itself; `seen` are the
  # fields on the way here.
  defp reads(resource, %Ash.Resource.Aggregate{} = aggregate, from, seen) do
    {related, over} =
      over(resource, aggregate.relationship_path, aggregate.read_action, aggregate, from)

    over ++
      within(related, aggregate.field, seen) ++
      expression(related, aggregate.filter, seen)
  end

  defp reads(
         resource,
         %Ash.Resource.Calculation{calculation: {Ash.Resource.Calculation.Expression, opts}},
         _from,
         seen
       ),
       do: expression(resource, opts[:expr], seen)

  defp reads(_resource, _attribute_or_computed_in_elixir, _from, _seen), do: []

  # A field an aggregate is taken over, when it is computed itself.
  defp within(resource, name, _seen) when is_nil(resource) or is_nil(name), do: []

  defp within(resource, name, seen) do
    if {resource, name} in seen,
      do: [],
      else: reads(resource, Info.field(resource, name), name, [{resource, name} | seen])
  end

  # The aggregates an expression of `resource` holds, with those of the
  # expression calculations it references.
  defp expression(resource, expression, _seen) when is_nil(resource) or expression in [nil, []],
    do: []

  defp expression(resource, expression, seen) do
    with {:ok, expression} <-
           Ash.Filter.hydrate_refs(expression, %{resource: resource, public?: false}) do
      for %{relationship_path: path, attribute: %Ash.Query.Aggregate{} = aggregate} <-
            Ash.Filter.list_refs(expression, false, false, true),
          at = Info.related(resource, path),
          not is_nil(at),
          {related, over} =
            over(
              at,
              aggregate.relationship_path,
              aggregate.read_action,
              aggregate,
              aggregate.name
            ),
          read <- over ++ within(related, aggregate.field, seen) do
        read
      end
    else
      _unreadable -> []
    end
  end

  # The resource an aggregate reads, and the read actions Ash runs for it
  # along its path. An aggregate over a resource that is not related reads
  # that resource alone.
  defp over(resource, path, own, aggregate, from) do
    if Map.get(aggregate, :related?, true) do
      path = List.wrap(path)

      {related, reads} =
        Enum.reduce(Enum.with_index(path, 1), {resource, []}, fn
          {_name, _index}, {nil, reads} ->
            {nil, reads}

          {name, index}, {at, reads} ->
            case Info.relationship(at, name) do
              nil ->
                {nil, reads}

              relationship ->
                last? = index == length(path)

                {relationship.destination,
                 reads ++ step(relationship, if(last?, do: own), last?, from)}
            end
        end)

      {related, reads}
    else
      related = aggregate.resource
      action = if own, do: Info.action(related, own), else: Info.primary_action(related, :read)
      how = if own, do: :own, else: {:relationship, nil, :primary, true}
      {related, [%{resource: related, action: action, how: how, from: from}]}
    end
  end

  # One relationship of an aggregate's path: what Ash runs on the way
  # through it, and the action its destination is read through.
  defp step(%{destination: destination, name: name} = relationship, own, last?, from) do
    passed =
      for passed <- Relating.passed(relationship) do
        how =
          case passed do
            %{kind: :join, by: join, whose: whose} -> {:join, name, join, whose}
            %{kind: :through} -> {:through, name}
          end

        %{resource: passed.resource, action: passed.action, how: how, from: from}
      end

    of_relationship =
      if relationship.read_action,
        do: [
          {Info.action(destination, relationship.read_action), {:relationship, name, :own, last?}}
        ],
        else: []

    of_aggregate =
      if own && own != relationship.read_action,
        do: [{Info.action(destination, own), :own}],
        else: []

    chosen =
      case of_relationship ++ of_aggregate do
        [] -> [{Info.primary_action(destination, :read), {:relationship, name, :primary, last?}}]
        chosen -> chosen
      end

    passed ++
      for(
        {action, how} <- chosen,
        do: %{resource: destination, action: action, how: how, from: from}
      )
  end

  @doc """
  Whether the resource allows sorting by the field under the given
  pagination strategy.

  Never by a value made of fields: an embedded resource or a map.
  `Ash.Resource.Info.sortable?/3` says so for a map, and not for a NewType
  of one, which is a map all the same. It says that an embedded resource
  can be sorted by, and `Ash.Query.sort_input/2`, through which a table
  sorts, refuses one ("is not sortable"); Ash's interface extensions leave
  embedded resources out of what they sort by as well.

  Nor by a union. Ash stores one as a map of its kind and its value, and
  `Ash.Resource.Info.sortable?/3` does not say no; `ash_json_api` and
  `ash_graphql` both leave unions out of what they sort and filter by.
  """
  @spec sortable?(Ash.Resource.t() | Spark.Dsl.t(), atom, strategy) :: boolean
  def sortable?(resource, name, strategy) do
    pagination_type = if strategy == :keyset, do: :keyset, else: :offset

    Info.sortable?(resource, name, pagination_type: pagination_type, include_private?: false) and
      not made_of_fields?(Info.field(resource, name))
  end

  defp made_of_fields?(%{type: type} = field) when not is_nil(type) and not is_tuple(type) do
    constraints = Map.get(field, :constraints) || []

    not is_nil(AshTable.Resource.Embedding.kind(type, constraints)) or
      not is_nil(AshTable.Resource.Embedding.union(type, constraints))
  end

  defp made_of_fields?(_field), do: false

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
