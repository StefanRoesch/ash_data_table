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
  #
  # ## In steps
  #
  # What the columns show besides attributes is not all read in the
  # statement that reads the records. Two defects of the SQL layer stand in
  # the way (ash_sql 0.8.1), each tracked by the library as an internal
  # ticket, and each of these steps can go when it is fixed:
  #
  #   * #35: a statement that selects an aggregate beside a calculation
  #     which Ash adds itself (for a field that a field policy hides on some
  #     records) fails where it is wrapped in a subquery: a page of related
  #     records always is, a list of them through a join resource or of one
  #     of many is, and a page of a table of its own can be. So aggregates
  #     are never selected in the statement that reads the records. They are
  #     loaded onto the records afterwards (`Ash.load/3`, as the person),
  #     and a list or page of related records is read bare, with everything
  #     loaded afterwards. Sorting and filtering by a column stay in the
  #     statement, where they work but for the sort `AshTable.Model` takes
  #     away.
  #
  #   * #32: see `AshTable.Resource.Reading.apart/2`. The aggregates it
  #     names are loaded last, in a step that holds nothing else.

  alias AshTable.Model
  alias AshTable.Model.Operator
  alias AshTable.State

  # how many records are read at a time where records are read to the end
  @batch_size 100

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
    #   * `parent` is, for the records related to one record, that record as
    #     it was read for the person asking; nil for a table of its own.

    @enforce_keys [:records]
    defstruct [:records, :total, :pages, :offset, :previous, :next, :parent]

    @type t :: %__MODULE__{
            records: [Ash.Resource.record()],
            total: non_neg_integer | nil,
            pages: pos_integer | nil,
            offset: non_neg_integer | nil,
            previous: State.t() | nil,
            next: State.t() | nil,
            parent: Ash.Resource.record() | nil
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

    with {:ok, result} <-
           Ash.read(
             query(model, state, Model.loads(model), read_opts),
             [page: page_opts(model, state)] ++ read_opts
           ),
         # internal tickets #35 and #32: see "In steps" above; through the
         # table's read action, which Ash would not take by itself
         {:ok, result} <-
           loaded(
             result,
             [Model.aggregates(model), Model.apart(model)],
             [action: model.read_action] ++ read_opts
           ) do
      {:ok, page(result, model, state)}
    end
  end

  @doc """
  Reads the page `state` points at of a nested table: the records related to
  the record of `model.via.source` with the primary key `key`, through the
  relationship `model.via`.

  The parent record is read again every time, by its primary key, as the
  person asking and through the read action of the table that shows it
  (`via.source_read_action`), with the relationship loaded through the
  nested table's query. A key is all a table keeps of a row, and a key
  proves nothing: only this read says whether the person may see the record
  whose related records they ask for, and it says so as the table that
  shows the record does. Ash's own loader then decides what "related" means, for
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

    # Related records are read bare, and everything the table's columns show
    # besides attributes is loaded onto them afterwards (internal ticket
    # #35: see "In steps" above).
    related =
      case page_opts(model, state) do
        false -> query(model, state, [], read_opts)
        page_opts -> model |> query(state, [], read_opts) |> Ash.Query.page(page_opts)
      end

    parent_opts =
      Keyword.put(
        read_opts,
        :authorize?,
        read_opts[:authorize?] or Keyword.get(opts, :parent_authorize?, true)
      )

    with {:ok, %_{} = parent} <-
           get(
             via.source,
             via.source_read_action,
             key,
             [load: [{via.name, related}]] ++ parent_opts
           ),
         {:ok, result} <- related(Map.get(parent, via.name)),
         {:ok, result} <- load(result, model, [action: model.read_action] ++ read_opts) do
      {:ok, %{page(result, model, state) | parent: parent}}
    else
      {:ok, nil} -> {:error, :parent_gone}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  The primary keys of every record `state` matches: what the table shows
  through all of its pages, as `opts` say who is asking. For an action that
  is run on "all that match".

  They are read through the table's read action, with the person's
  filters, in batches as the action pages (`Ash.stream!/2`), and nothing
  but the keys is kept of them. The sort a person chose says nothing about
  which records match, and is left out.

  For a table of its own. Raises what the read raises.
  """
  @spec matching(Model.t(), State.t(), [option]) :: [map]
  def matching(%Model{via: nil} = model, %State{} = state, opts \\ []) do
    read_opts = reader_opts(opts)

    model
    |> query(%{state | sort: nil}, [], read_opts)
    |> Ash.Query.select(model.primary_key)
    |> stream(model, read_opts)
    |> Enum.map(&Map.take(&1, model.primary_key))
  end

  @doc """
  The records with the primary keys `keys`, as far as they are there and
  `opts` say that the person asking may read them: through the table's read
  action, as a page is read, and so with the same policies and field
  policies. In no particular order; a key that names nothing the person may
  read is not among them, and nothing says which of the two it is.

  For a table of its own. Raises what the read raises.
  """
  @spec records(Model.t(), [map], [option]) :: [Ash.Resource.record()]
  def records(%Model{via: nil}, [], _opts), do: []

  def records(%Model{via: nil} = model, keys, opts) do
    read_opts = reader_opts(opts)

    model
    |> query(%State{}, [], read_opts)
    |> by_keys(model, keys)
    |> stream(model, read_opts)
    |> Enum.to_list()
  end

  @doc """
  The same for a nested table: the records related to the record of
  `model.via.source` with the primary key `key`, through the relationship
  `model.via`. `keys` are the primary keys of the ones that are asked for,
  or `:all` for every one that `state` matches.

  The parent is read as `read_related/4` reads it, with the relationship
  loaded through the nested table's query and without a page: whether a
  record is related to that parent is Ash's loader's to say, and a record
  that is not related is not among them, whoever may read it elsewhere.

  Takes the options of `read_related/4`, and returns its errors.
  """
  @spec related_records(Model.t(), State.t(), map, [map] | :all, keyword) ::
          {:ok, [Ash.Resource.record()]} | {:error, :parent_gone | :forbidden | Ash.Error.t()}
  def related_records(%Model{via: %{}}, _state, _key, [], _opts), do: {:ok, []}

  def related_records(%Model{via: %{} = via} = model, %State{} = state, key, keys, opts)
      when is_map(key) do
    read_opts = reader_opts(opts)

    related =
      case keys do
        :all -> query(model, %{state | sort: nil}, [], read_opts)
        keys -> model |> query(%State{}, [], read_opts) |> by_keys(model, keys)
      end

    parent_opts =
      Keyword.put(
        read_opts,
        :authorize?,
        read_opts[:authorize?] or Keyword.get(opts, :parent_authorize?, true)
      )

    with {:ok, %_{} = parent} <-
           get(
             via.source,
             via.source_read_action,
             key,
             [load: [{via.name, related}]] ++ parent_opts
           ),
         {:ok, result} <- related(Map.get(parent, via.name)) do
      {:ok, result}
    else
      {:ok, nil} -> {:error, :parent_gone}
      {:error, error} -> {:error, error}
    end
  end

  # The records of a query, read to the end in batches: by keyset or by
  # offset as the action pages, and in one read when it does not page. No
  # batch is larger than a page of the action may be.
  defp stream(query, model, read_opts) do
    batch =
      case Ash.Resource.Info.action(model.resource, model.read_action).pagination do
        %{max_page_size: max} when is_integer(max) -> min(max, @batch_size)
        _none -> @batch_size
      end

    Ash.stream!(query, [allow_stream_with: :full_read, batch_size: batch] ++ read_opts)
  end

  # Limited to the records with these primary keys: one of them, whichever.
  defp by_keys(query, %Model{primary_key: [field]}, keys),
    do: Ash.Query.do_filter(query, [{field, [in: Enum.map(keys, &Map.fetch!(&1, field))]}])

  defp by_keys(query, %Model{primary_key: fields}, keys),
    do: Ash.Query.do_filter(query, or: Enum.map(keys, &Map.to_list(Map.take(&1, fields))))

  # What Ash put at the relationship: the records, as a page, a list, one
  # record or none; or its refusal.
  defp related(%Ash.ForbiddenField{}), do: {:error, :forbidden}
  defp related(%Ash.NotLoaded{}), do: {:error, :forbidden}
  defp related(nil), do: {:ok, []}

  defp related(%struct{} = page) when struct in [Ash.Page.Offset, Ash.Page.Keyset],
    do: {:ok, page}

  defp related(%_{} = record), do: {:ok, [record]}
  defp related(records) when is_list(records), do: {:ok, records}

  @doc """
  Puts onto records everything the table's columns show besides attributes,
  as `opts` say who is asking: the calculations and the related records'
  labels with the aggregates, and last the aggregates that are read apart
  (internal ticket #32). Takes what a read gave: a page, a list, or one
  record.

  `opts` may name the read action to load through, with `:action`. Records
  that the table has read are loaded onto through the table's read action:
  the policies and field policies that say what the person may have of
  what is loaded are then those of the action that read the records. Without
  `:action` Ash loads through the primary read action, as it does itself
  for what a create, an update or a destroy action returns: the way a row
  is shown again after one (`AshTable.Record`).
  """
  @spec load(result, Model.t(), keyword) :: {:ok, result} | {:error, Ash.Error.t()}
        when result: Ash.Page.page() | [Ash.Resource.record()] | Ash.Resource.record()
  def load(result, %Model{} = model, opts) do
    loaded(result, [Model.loads(model) ++ Model.aggregates(model), Model.apart(model)], opts)
  end

  # Each of `steps` is loaded onto the records in a statement of its own, in
  # that order, as the person.
  defp loaded(result, steps, read_opts) do
    Enum.reduce_while(steps, {:ok, result}, fn loads, {:ok, result} ->
      case step(result, loads, read_opts) do
        {:ok, result} -> {:cont, {:ok, result}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp step(result, [], _read_opts), do: {:ok, result}
  defp step([], _loads, _read_opts), do: {:ok, []}
  defp step(%{results: []} = page, _loads, _read_opts), do: {:ok, page}

  defp step(%struct{results: records} = page, loads, read_opts)
       when struct in [Ash.Page.Offset, Ash.Page.Keyset] do
    with {:ok, records} <- Ash.load(records, loads, read_opts),
         do: {:ok, %{page | results: records}}
  end

  defp step(records, loads, read_opts), do: Ash.load(records, loads, read_opts)

  @doc """
  Reads one record by its primary key through the read action `action`, as
  `opts` say who is asking: `nil` when it is not there, or not theirs to
  read.

  The action is the one the record's table reads through, which is
  `public?`. Ash would take the primary read action, which nothing says is:
  a table runs no action that it has not looked at.
  """
  @spec get(Ash.Resource.t(), atom, map, keyword) ::
          {:ok, Ash.Resource.record() | nil} | {:error, Ash.Error.t()}
  def get(resource, action, key, opts) when is_atom(action) and is_map(key) do
    Ash.get(resource, key, [not_found_error?: false, action: action] ++ opts)
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

  # The two functions below look like a repetition of what `AshTable.State`
  # already does, and they are meant to be one: they are the last guard for
  # internal ticket #31, and must stay. Whatever a state holds, and however
  # it came to hold it, nothing but a filter and a sort by one of the
  # table's own columns for this person gets into a query.

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
  # related resource to it, so nothing but a column's name ever gets there
  # (internal ticket #31; a reference column, which is named after a
  # relationship, is never `sortable?` for the same reason).
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
  # its own counts through the read itself, which applies them. Internal
  # ticket #30: this goes when Ash applies field policies to that count.
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
