defmodule AshTable.Query do
  @moduledoc false
  # Reads one page of a table through its read action. Sorting, filtering and
  # pagination always run on the server; the sort and the filters a person
  # chose are applied with `Ash.Query.sort_input/2` and
  # `Ash.Query.filter_input/2`, the functions for outside input.
  #
  # A table of its own and a nested one build the same query and turn what
  # comes back into the same `Page`. They differ in the last step alone: the
  # one reads its query, the other reads the parent record by its key with
  # the query as the load of the relationship.

  alias AshTable.Model
  alias AshTable.Model.Operator
  alias AshTable.Resource.Reading
  alias AshTable.State

  defmodule Page do
    @moduledoc false
    # One page of records and where a person can go from it.
    #
    #   * `total` is the number of records in all pages, when the action
    #     counts; under offset pagination `pages` follows from it.
    #   * `offset` is the number of records before this page (offset
    #     pagination), nil when unknown: under keyset pagination a page does
    #     not know where it lies among the others, even when it has a total.
    #   * `previous` and `next` are the states of the neighbouring pages, nil
    #     where there is none.

    @enforce_keys [:records]
    defstruct [:records, :total, :pages, :offset, :previous, :next]

    @type t :: %__MODULE__{
            records: [Ash.Resource.record()],
            total: non_neg_integer | nil,
            pages: pos_integer | nil,
            offset: non_neg_integer | nil,
            previous: State.t() | nil,
            next: State.t() | nil
          }
  end

  @type option ::
          {:scope, term}
          | {:actor, term}
          | {:tenant, term}
          | {:authorize?, boolean}

  @doc """
  Reads the page `state` points at.

  ## Options

    * `:scope` - an `Ash.Scope`, carrying actor and tenant;
    * `:actor` and `:tenant` - used when no scope is given;
    * `:authorize?` - defaults to `true`.
  """
  @spec read(Model.t(), State.t(), [option]) :: {:ok, Page.t()} | {:error, Ash.Error.t()}
  def read(%Model{via: nil} = model, %State{} = state, opts \\ []) do
    read_opts = reader_opts(opts)

    case Ash.read(
           query(model, state, Model.loads(model), read_opts),
           [page: page_opts(model, state)] ++ read_opts
         ) do
      {:ok, result} -> {:ok, page(result, model, state)}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Reads the page `state` points at of a nested table: the records related to
  the record of `model.via.source` with the primary key `key`, through the
  relationship `model.via`.

  The parent record is read again every time, by its primary key and as the
  person asking, with the relationship loaded through the nested table's
  query. A key is all a table keeps of a row, and a key proves nothing: only
  this read says whether the person may see the record whose related records
  they ask for. Ash's own loader then decides what "related" means, for
  every kind of relationship.

  Takes the options of `read/3`, and `:parent_authorize?`: whether the table
  of the parent authorizes (defaults to `true`). The parent is read with
  authorization when either table authorizes.

  Returns, besides what `read/3` returns:

    * `{:error, :parent_gone}` - the parent record is gone, or no longer the
      person's to read;
    * `{:error, :forbidden}` - the person may not read the destination: Ash
      put an `Ash.ForbiddenField` in place of the related records. (With
      `allow_forbidden_field? false` on the relationship the same refusal is
      an `Ash.Error.Forbidden`.)
  """
  @spec read_related(Model.t(), State.t(), map, keyword) ::
          {:ok, Page.t()} | {:error, :parent_gone | :forbidden | Ash.Error.t()}
  def read_related(%Model{via: %{} = via} = model, %State{} = state, key, opts \\ [])
      when is_map(key) do
    read_opts = reader_opts(opts)

    loads = Model.loads(model)

    # A page of related records is read bare, and what the table's columns
    # show besides attributes is loaded onto its records afterwards: the load
    # of an aggregate inside a paged relationship fails in the data layer for
    # a person whose field policies look at the record (ash 3.34.4,
    # ash_postgres 2.14.2: an `Ecto.QueryError` about map values in a
    # subquery). Sorting and filtering by such a column stay in the query,
    # where they work. What is not paged is read in one go.
    {related, later} =
      case page_opts(model, state) do
        false ->
          {query(model, state, loads, read_opts), []}

        page_opts ->
          {model |> query(state, [], read_opts) |> Ash.Query.page(page_opts), loads}
      end

    parent_opts =
      Keyword.put(
        read_opts,
        :authorize?,
        read_opts[:authorize?] or Keyword.get(opts, :parent_authorize?, true)
      )

    with {:ok, %_{} = parent} <-
           get(via.source, key, [load: [{via.name, related}]] ++ parent_opts),
         {:ok, result} <- related(Map.get(parent, via.name)),
         {:ok, result} <- loaded(result, later, read_opts) do
      {:ok, page(result, model, state)}
    else
      {:ok, nil} -> {:error, :parent_gone}
      {:error, error} -> {:error, error}
    end
  end

  # What Ash put at the relationship: the records, as a page, a list, one
  # record or none; or its refusal.
  defp related(%Ash.ForbiddenField{}), do: {:error, :forbidden}
  defp related(%Ash.NotLoaded{}), do: {:error, :forbidden}
  defp related(nil), do: {:ok, []}

  defp related(%struct{} = page) when struct in [Ash.Page.Offset, Ash.Page.Keyset],
    do: {:ok, page}

  defp related(%_{} = record), do: {:ok, [record]}
  defp related(records) when is_list(records), do: {:ok, records}

  # The records of a page that was read through the person's own read, with
  # the table's calculations and aggregates put onto them, as the person.
  defp loaded(result, [], _read_opts), do: {:ok, result}

  defp loaded(%{results: []} = page, _loads, _read_opts), do: {:ok, page}

  defp loaded(%{results: records} = page, loads, read_opts) do
    with {:ok, records} <- Ash.load(records, loads, read_opts),
         do: {:ok, %{page | results: records}}
  end

  defp loaded(records, _loads, _read_opts) when is_list(records), do: {:ok, records}

  @doc """
  Reads one record by its primary key, as `opts` say who is asking: `nil`
  when it is not there, or not theirs to read.

  Through the primary read action, as `Ash.load/3` and the load of an
  update's result go; through the read action of the resource's table when
  it has none.
  """
  @spec get(Ash.Resource.t(), map, keyword) ::
          {:ok, Ash.Resource.record() | nil} | {:error, Ash.Error.t()}
  def get(resource, key, opts) when is_map(key) do
    action =
      with nil <- Ash.Resource.Info.primary_action(resource, :read),
           {:ok, %{name: name}} <- Reading.read_action(resource) do
        [action: name]
      else
        _primary_or_none -> []
      end

    Ash.get(resource, key, [not_found_error?: false] ++ action ++ opts)
  end

  # The sort a person chose goes in before the action's preparations run, so
  # that a sort of the action itself comes second, as a tie-breaker.
  defp query(model, state, loads, read_opts) do
    model.resource
    |> Ash.Query.new()
    |> sort(known_sort(state.sort, model), model.via)
    |> filter(known(state.filters, model))
    |> Ash.Query.load(loads)
    |> Ash.Query.for_read(model.read_action, %{}, read_opts)
  end

  @doc "Who is asking, as the options of an Ash call: scope, or actor and tenant, and `authorize?`."
  @spec reader_opts([option]) :: keyword
  def reader_opts(opts) do
    context =
      case opts[:scope] do
        nil -> Keyword.take(opts, [:actor, :tenant])
        scope -> [scope: scope]
      end

    context
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Keyword.put(:authorize?, Keyword.get(opts, :authorize?, true))
  end

  # The filters on columns the table has for this person. The state holds
  # no others (`AshTable.State` takes none from the outside, and the table
  # fits a state it kept to the model it has now); this is the same rule once
  # more, where the query is built.
  defp known(filters, model) do
    Map.filter(filters, fn {name, _filter} ->
      Enum.any?(model.columns, &(&1.name == name and &1.operators != []))
    end)
  end

  # Likewise the sort: by a column of the table that sorts, named by the
  # model's own atom. `Ash.Query.sort_input/2` would take the path through a
  # relationship ("assignee.name") from anybody and apply no policy of the
  # related resource to it, so nothing but a column's name ever gets there.
  defp known_sort({name, _direction} = sort, model) do
    if Enum.any?(model.columns, &(&1.name == name and &1.sortable?)), do: sort
  end

  defp known_sort(nil, _model), do: nil

  defp sort(query, {name, direction}, _via),
    do: Ash.Query.sort_input(query, [{name, direction}])

  # While the person has chosen no sort, the relationship's own goes where
  # theirs would: in front of the action's. Ash puts it behind, where an
  # action with a default sort never lets it be seen, and where "the latest
  # comment" of a has-one that picks one of many would be another one.
  defp sort(query, nil, %{sort: sort}) when sort not in [nil, []], do: Ash.Query.sort(query, sort)
  defp sort(query, nil, _via), do: query

  # One filter with a predicate per column, which Ash combines with AND. The
  # values go in as they were typed: casting them, and what they match, is
  # the resource's.
  defp filter(query, filters) when filters == %{}, do: query

  defp filter(query, filters) do
    Ash.Query.filter_input(
      query,
      Map.new(filters, fn {name, {operator, value}} ->
        {name, Map.new([Operator.to_ash(operator, value)])}
      end)
    )
  end

  defp page_opts(%{pagination: %{strategy: :none}}, _state), do: false

  defp page_opts(%{pagination: %{strategy: :offset} = pagination} = model, state) do
    [
      limit: pagination.page_size,
      offset: (state.page - 1) * pagination.page_size,
      count: count?(model, state)
    ]
  end

  defp page_opts(%{pagination: %{strategy: :keyset} = pagination} = model, state) do
    position =
      cond do
        state.after -> [after: state.after]
        state.before -> [before: state.before]
        true -> []
      end

    # Ash counts for a keyset page as it does for an offset one, when the
    # action is countable.
    [limit: pagination.page_size, count: count?(model, state)] ++ position
  end

  # Whether the read asks for the total: when the action counts, and for a
  # nested table only while that gives nothing away. The count of a page of
  # related records is taken with the person's filter as it is written,
  # without the field policies (ash 3.34.4): filtering by a column they see
  # on some records only, they would be told how many records match among
  # those whose value they may not see. So no total is asked for then, and
  # the table shows none, as on an action that does not count. A table of
  # its own counts through the read itself, which applies them.
  defp count?(%{pagination: %{countable?: false}}, _state), do: false
  defp count?(%{via: nil}, _state), do: true

  # Only a filter on a column the person sees on every record leaves the
  # count alone. A filter on anything else, were one ever in the state, would
  # leave no total either: there is none to ask for that is safe.
  defp count?(model, state) do
    Enum.all?(state.filters, fn {name, _filter} ->
      match?(%{partly_hidden?: false}, Enum.find(model.columns, &(&1.name == name)))
    end)
  end

  defp page(records, _model, _state) when is_list(records) do
    %Page{records: records, total: length(records), offset: 0}
  end

  defp page(%Ash.Page.Offset{} = result, model, state) do
    pages = result.count && max(1, ceil(result.count / model.pagination.page_size))

    # From a page beyond the last, back is the last page there is, when the
    # action counts; the pages in between are as empty as this one.
    previous = if pages, do: min(state.page - 1, pages), else: state.page - 1

    %Page{
      records: result.results,
      total: result.count,
      pages: pages,
      offset: result.offset,
      previous: if(state.page > 1, do: State.to_page(state, previous)),
      next: if(result.more?, do: State.to_page(state, state.page + 1))
    }
  end

  defp page(%Ash.Page.Keyset{results: records} = result, _model, state) do
    first = keyset(List.first(records))
    last = keyset(List.last(records))
    start = %{state | page: 1, after: nil, before: nil}

    {previous, next} =
      cond do
        # Read forwards from a cursor: there is something before this page.
        # An empty page has no cursor to go back from, only the start.
        state.after ->
          {if(first, do: %{start | before: first}, else: start),
           more(result, start, :after, last)}

        # Read backwards: `more?` speaks about the records before this page.
        state.before ->
          {more(result, start, :before, first), last && %{start | after: last}}

        true ->
          {nil, more(result, start, :after, last)}
      end

    %Page{records: records, total: result.count, previous: previous, next: next}
  end

  defp more(%{more?: true}, start, direction, cursor) when is_binary(cursor),
    do: Map.put(start, direction, cursor)

  defp more(_result, _start, _direction, _cursor), do: nil

  defp keyset(%{__metadata__: %{keyset: keyset}}), do: keyset
  defp keyset(_none), do: nil
end
