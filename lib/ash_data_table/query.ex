defmodule AshDataTable.Query do
  @moduledoc false
  # Reads one page of a table through its read action. Sorting, filtering and
  # pagination always run on the server; the sort and the filters a person
  # chose are applied with `Ash.Query.sort_input/2` and
  # `Ash.Query.filter_input/2`, the functions for outside input.
  #
  # The action is given the arguments the model holds for it
  # (`AshDataTable.Model.supply/2`): what a person typed into the argument line,
  # as they typed it, for Ash to cast. Wherever the table runs its read
  # action for them, it runs it with these: the page and its count, every
  # record that matches, the records of a selection, the record of a row
  # before something is done with it (`get/5`), and what is loaded onto
  # records the action has read. A calculation column is loaded, sorted and
  # filtered by with the arguments its column gives it.
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
  #     statement, where they work but for the sort `AshDataTable.Model` takes
  #     away.
  #
  #   * #32: see `AshDataTable.Resource.Reading.apart/2`. The aggregates it
  #     names are loaded last, in a step that holds nothing else.

  alias AshDataTable.Model
  alias AshDataTable.Model.Argument
  alias AshDataTable.Model.Operator
  alias AshDataTable.Resource.Summarising
  alias AshDataTable.Model.Pagination
  alias AshDataTable.State
  alias AshDataTable.Text
  alias AshDataTable.Zone

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
          | {:origin, pid | nil}

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
             model,
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

  Takes the options of `read/3`, and

    * `:parent_authorize?` - whether the table of the parent authorizes
      (defaults to `true`). The parent is read with authorization when
      either table authorizes;
    * `:parent_arguments` - what the read action of the parent's table is
      given: the `read_arguments` of that table's model. Without them the
      action runs with its defaults.

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
             Keyword.get(opts, :parent_arguments, %{}),
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

    through_parent(via, related, key, read_opts, opts)
  end

  # What a query of related records gives for the record with the primary
  # key `key`: that record is read, as `read_related/4` reads it, with the
  # relationship loaded through the query.
  defp through_parent(via, related, key, read_opts, opts) do
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
             Keyword.get(opts, :parent_arguments, %{}),
             [load: [{via.name, related}]] ++ parent_opts
           ),
         {:ok, result} <- related(Map.get(parent, via.name)) do
      {:ok, result}
    else
      {:ok, nil} -> {:error, :parent_gone}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  The records with the primary keys `keys` as the rows of a page are made
  of them: read as `records/3` reads them (as `related_records/5` does for
  a nested table, whose parent has the primary key `parent`), without the
  person's filters, and with everything the table's columns show loaded
  onto them as onto the records of a page (`load/3`, through the table's
  read action).

  This is how a table follows a change that was announced to it
  (`AshDataTable.Notifier`): a key that names nothing the person may read
  through the table is not among the records, and nothing says why.

  Takes the options of `read_related/4`.
  """
  @spec rows(Model.t(), map | nil, [map], keyword) ::
          {:ok, [Ash.Resource.record()]} | {:error, term}
  def rows(%Model{} = model, parent, keys, opts) do
    read_opts = reader_opts(opts)

    read =
      case model.via do
        nil -> {:ok, records(model, keys, opts)}
        %{} -> related_records(model, %State{}, parent, keys, opts)
      end

    with {:ok, records} <- read do
      load(records, model, [action: model.read_action] ++ read_opts)
    end
  rescue
    error -> {:error, error}
  end

  @doc """
  Whether at least one of the records with the primary keys `keys` is
  among what `state` matches for the person asking: read through the
  table's read action with their filters and its arguments, and for a
  nested table through its parent, in one read that asks for one record.
  A read that fails says no.

  It is what lets a table say that there are new or changed records: only
  a record the person would be shown is spoken of.

  Takes the options of `read_related/4`.
  """
  @spec any?(Model.t(), State.t(), map | nil, [map], keyword) :: boolean
  def any?(%Model{}, %State{}, _parent, [], _opts), do: false

  def any?(%Model{} = model, %State{} = state, parent, keys, opts) do
    read_opts = reader_opts(opts)

    matching =
      model
      |> query(%{state | sort: nil}, [], read_opts)
      |> by_keys(model, keys)
      |> Ash.Query.select(model.primary_key)

    case model.via do
      nil ->
        matching |> stream(model, read_opts) |> Enum.take(1) != []

      %{} = via ->
        match?(
          {:ok, [_ | _]},
          through_parent(via, Ash.Query.limit(matching, 1), parent, read_opts, opts)
        )
    end
  rescue
    _error -> false
  end

  @doc """
  The summaries of the table's columns (`AshDataTable.Model.summarised/1`):
  by column name, `{:ok, value}` or `:unavailable`.

  Each is over every record `state` matches for the person asking, not over
  a page: through the table's read action, with its arguments, the
  person's filters, actor and tenant, as a page is read, and without a
  limit, an offset or a sort. All of them are computed by the data layer in
  one call (`Ash.aggregate/3`).

  A summary never says what the person may not see:

    * every aggregate is asked for with `authorize_fields?: true`, which
      makes Ash count only the records on which the person sees the field,
      and with the table's read action as its own `read_action`: Ash would
      otherwise look at the field policies as the primary read action meets
      them (ash 3.34.4), which need not be the ones the rows are read
      under;

    * a column the person sees on some records only (`partly_hidden?`, in a
      model from `AshDataTable.Model.for_actor/2`) is not asked for at all, and
      is `:unavailable`: a number over the rest would pass for the whole.

  Without authorization (`authorize?: false`) it is computed as the rows
  are read: over everything.

  Also `:unavailable` is every summary of a table that reads through a
  manual action, which the data layer is not asked through, and one of a
  kind the data layer does not compute.

  The records of a nested table are those related to the record with the
  primary key `parent`: their keys are read through that record, as
  `related_records/5` reads them, and the summaries are over the records
  with those keys. So what "related" means stays Ash's loader's to say.

  Takes the options of `read_related/4`. An empty result gives 0 for a
  count and nil for every other kind.
  """
  @spec summaries(Model.t(), State.t(), map | nil, keyword) ::
          {:ok, %{optional(atom) => {:ok, term} | :unavailable}}
          | {:error, :parent_gone | :forbidden | term}
  def summaries(%Model{} = model, %State{} = state, parent, opts) do
    read_opts = reader_opts(opts)
    columns = Model.summarised(model)
    action = Ash.Resource.Info.action(model.resource, model.read_action)

    asked =
      Enum.filter(columns, fn column ->
        not column.partly_hidden? and column.kind == :attribute and not column.sensitive? and
          Summarising.action(action) == :ok and
          Summarising.data_layer(model.resource, column.summary) == :ok
      end)

    unavailable = Map.new(columns, &{&1.name, :unavailable})

    # no sort, and no page: every record that matches
    matching = query(%{model | via: nil}, %{state | sort: nil}, [], read_opts)

    with [_ | _] <- asked,
         {:ok, matching} <- limited(matching, model, parent, read_opts, opts),
         {:ok, values} <- aggregate(matching, asked, model, read_opts) do
      {:ok, Map.merge(unavailable, values)}
    else
      [] -> {:ok, unavailable}
      :none -> {:ok, Map.merge(unavailable, Map.new(asked, &{&1.name, {:ok, nothing(&1)}}))}
      {:error, error} -> {:error, error}
    end
  rescue
    error -> {:error, error}
  end

  # What a summary of no records is.
  defp nothing(%{summary: :count}), do: 0
  defp nothing(_column), do: nil

  # A table of its own summarises what its query matches. A nested one
  # summarises the records with the keys that its parent's relationship
  # gives; `:none` when it gives none, or when a record has no key to be
  # told by.
  defp limited(matching, %Model{via: nil}, _parent, _read_opts, _opts), do: {:ok, matching}
  defp limited(_matching, %Model{primary_key: []}, _parent, _read_opts, _opts), do: :none

  defp limited(matching, %Model{via: via} = model, parent, read_opts, opts) when is_map(parent) do
    related = Ash.Query.select(matching, model.primary_key)

    case through_parent(via, related, parent, read_opts, opts) do
      {:ok, []} ->
        :none

      {:ok, records} ->
        {:ok, by_keys(matching, model, Enum.map(records, &Map.take(&1, model.primary_key)))}

      {:error, error} ->
        {:error, error}
    end
  end

  defp limited(_matching, _model, _parent, _read_opts, _opts), do: {:error, :parent_gone}

  defp aggregate(matching, asked, model, read_opts) do
    aggregates =
      for column <- asked do
        {column.name, column.summary, field: column.field, read_action: model.read_action}
      end

    # the query says who is asking; what marks a table's own writes
    # (`origin/2`) is of no use to a read
    opts = [authorize_fields?: true] ++ Keyword.delete(read_opts, :context)

    with {:ok, values} <- Ash.aggregate(matching, aggregates, opts) do
      {:ok,
       Map.new(asked, fn column ->
         {column.name, {:ok, Map.get(values, column.name, nothing(column)) || nothing(column)}}
       end)}
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
  is shown again after one (`AshDataTable.Record`).

  What is loaded through the table's read action is loaded with the
  arguments that action was read with. The primary read action is given
  none, as Ash gives it none after an action.
  """
  @spec load(result, Model.t(), keyword) :: {:ok, result} | {:error, Ash.Error.t()}
        when result: Ash.Page.page() | [Ash.Resource.record()] | Ash.Resource.record()
  def load(result, %Model{} = model, opts) do
    loaded(
      result,
      [Model.loads(model) ++ Model.aggregates(model), Model.apart(model)],
      model,
      opts
    )
  end

  # Each of `steps` is loaded onto the records in a statement of its own, in
  # that order, as the person.
  defp loaded(result, steps, model, read_opts) do
    Enum.reduce_while(steps, {:ok, result}, fn loads, {:ok, result} ->
      case step(result, loads, model, read_opts) do
        {:ok, result} -> {:cont, {:ok, result}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp step(result, [], _model, _read_opts), do: {:ok, result}
  defp step([], _loads, _model, _read_opts), do: {:ok, []}
  defp step(%{results: []} = page, _loads, _model, _read_opts), do: {:ok, page}

  defp step(%struct{results: records} = page, loads, model, read_opts)
       when struct in [Ash.Page.Offset, Ash.Page.Keyset] do
    with {:ok, records} <- Ash.load(records, through(loads, model, read_opts), read_opts),
         do: {:ok, %{page | results: records}}
  end

  defp step(records, loads, model, read_opts),
    do: Ash.load(records, through(loads, model, read_opts), read_opts)

  # What Ash is asked to load. Through the table's read action, where that
  # takes arguments, it is a query of that action with them: Ash would
  # otherwise run the action without any.
  defp through(loads, %Model{read_action: action, read_arguments: arguments} = model, read_opts) do
    if read_opts[:action] == action and arguments != %{} do
      model.resource
      |> Ash.Query.new()
      |> Ash.Query.load(loads)
      |> Ash.Query.for_read(action, arguments, Keyword.delete(read_opts, :action))
    else
      loads
    end
  end

  @doc """
  Reads one record by its primary key through the read action `action`, as
  `opts` say who is asking: `nil` when it is not there, or not theirs to
  read.

  The action is the one the record's table reads through, which is
  `public?`. Ash would take the primary read action, which nothing says is:
  a table runs no action that it has not looked at.
  """
  @spec get(Ash.Resource.t(), atom, map, map, keyword) ::
          {:ok, Ash.Resource.record() | nil} | {:error, Ash.Error.t()}
  def get(resource, action, key, arguments, opts)
      when is_atom(action) and is_map(key) and arguments == %{} do
    Ash.get(resource, key, [not_found_error?: false, action: action] ++ opts)
  end

  # `Ash.get/3` gives an action no arguments. With them the record is read
  # as it does read it: the one record with that key, through the action.
  def get(resource, action, key, arguments, opts)
      when is_atom(action) and is_map(key) and is_map(arguments) do
    resource
    |> Ash.Query.new()
    |> Ash.Query.do_filter(Map.to_list(key))
    |> Ash.Query.for_read(action, arguments, Keyword.delete(opts, :load))
    |> Ash.read_one([not_found_error?: false] ++ opts)
  end

  @doc """
  What Ash makes of the arguments a model holds
  (`AshDataTable.Model.supply/2`), asked without reading anything, as `opts` say
  who is asking:

    * `missing` - the arguments of the argument line that the read action
      does not run without, and that are empty: in the line's order;
    * `refused` - by the key of an argument of the line, what Ash says of
      the value it holds: a text that is no value of its type, a value its
      constraints do not take.

  The read action's arguments are given to the action
  (`Ash.Query.for_read/4`), and those a column asks for to a load of its
  calculation, which is where Ash casts them. An argument that is no input
  of the line is not looked at: what is wrong with it is said by the read.
  """
  @spec arguments(Model.t(), [option]) :: %{
          missing: [Argument.t()],
          refused: %{optional(Argument.key()) => [String.t()]}
        }
  def arguments(%Model{arguments: []}, _opts), do: %{missing: [], refused: %{}}

  def arguments(%Model{} = model, opts) do
    read = for %{column: nil} = argument <- model.arguments, do: argument

    errors =
      case read do
        [] ->
          []

        _some ->
          model.resource
          |> Ash.Query.for_read(model.read_action, model.read_arguments, reader_opts(opts))
          |> Map.fetch!(:errors)
      end

    required = for %Ash.Error.Query.Required{type: :argument, field: field} <- errors, do: field

    refused =
      for %Ash.Error.Query.InvalidArgument{field: field} = error <- errors,
          Enum.any?(read, &(&1.name == field)) do
        {{nil, field}, said(error)}
      end

    asked =
      for column <- model.columns,
          asks = Enum.filter(model.arguments, &(&1.column == column.name)),
          asks != [],
          refusal <- asked(model.resource, column, asks),
          do: refusal

    %{
      missing: Enum.filter(read, &(&1.name in required)),
      refused: Enum.group_by(refused ++ asked, &elem(&1, 0), &elem(&1, 1))
    }
  end

  # What Ash says of the arguments a column's calculation is loaded with,
  # by asked argument. It names the argument for a value that is none of
  # its type. For one its constraints do not take it does not (ash 3.34.4),
  # so that is put at the asked arguments whose own value their type does
  # not take, and failing that at all of them.
  defp asked(resource, column, asks) do
    errors =
      resource
      |> Ash.Query.new()
      |> Ash.Query.load([{column.field, column.arguments}])
      |> Map.fetch!(:errors)

    for error <- errors, argument <- about(error, asks, column.arguments) do
      {Argument.key(argument), said(error)}
    end
  end

  defp about(%Ash.Error.Query.InvalidCalculationArgument{field: field}, asks, _arguments),
    do: Enum.filter(asks, &(&1.name == field))

  defp about(_error, asks, arguments) do
    case Enum.reject(asks, &value?(&1, Map.get(arguments, &1.name))) do
      [] -> asks
      not_values -> not_values
    end
  end

  defp value?(%Argument{type: {type, constraints}}, value) do
    with {:ok, cast} <- Ash.Type.cast_input(type, value, constraints),
         {:ok, _cast} <- Ash.Type.apply_constraints(type, cast, constraints) do
      true
    else
      _refused -> false
    end
  end

  # The message of an error about an argument, as the host translates the
  # messages of actions.
  defp said(%{message: message} = error) when is_binary(message),
    do: Text.error({message, Map.get(error, :vars) || []})

  defp said(%Ash.Error.Unknown.UnknownError{error: message, value: vars})
       when is_binary(message),
       do: Text.error({message, if(Keyword.keyword?(vars), do: vars, else: [])})

  defp said(_error), do: Text.t(:invalid_filter)

  # The sort a person chose goes in before the action's preparations run, so
  # that a sort of the action itself comes second, as a tie-breaker.
  defp query(model, state, loads, read_opts) do
    model.resource
    |> Ash.Query.new()
    |> sort(known_sort(state.sort, model), model.via)
    |> filter(known(state.filters, model), model.time_zone)
    |> Ash.Query.load(loads)
    |> Ash.Query.for_read(model.read_action, model.read_arguments, read_opts)
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
    |> origin(opts[:origin])
  end

  # A table that follows live updates says of what it runs that it ran it:
  # `origin` is its listener (`AshDataTable.Listener`), which the notifier then
  # leaves out when it announces the change (`AshDataTable.Notifier`). The table
  # has shown what its action returned. It is in the context of that one
  # action, and not shared with the actions it runs in turn: what those
  # change besides is announced to the table like anything else.
  defp origin(reader, nil), do: reader
  defp origin(reader, pid), do: Keyword.put(reader, :context, %{ash_data_table_origin: pid})

  # The two functions below look like a repetition of what `AshDataTable.State`
  # already does, and they are meant to be one: they are the last guard for
  # internal ticket #31, and must stay. Whatever a state holds, and however
  # it came to hold it, nothing but a filter and a sort by one of the
  # table's own columns for this person gets into a query.

  # The filters on columns the table has for this person. The state holds
  # no others (`AshDataTable.State` takes none from the outside, and the table
  # fits a state it kept to the model it has now); this is the same rule once
  # more, where the query is built.
  defp known(filters, model) do
    for {name, filter} <- filters,
        column = Enum.find(model.columns, &(&1.name == name and &1.operators != [])),
        do: {column, filter}
  end

  # Likewise the sort: by a column of the table that sorts, named by the
  # model's own atom. `Ash.Query.sort_input/2` would take the path through a
  # relationship ("assignee.name") from anybody and apply no policy of the
  # related resource to it, so nothing but a column's field ever gets there
  # (internal ticket #31; a reference column, which is named after a
  # relationship, is never `sortable?` for the same reason).
  defp known_sort({name, direction}, model) do
    with %{} = column <- Enum.find(model.columns, &(&1.name == name and &1.sortable?)),
         do: {column, direction}
  end

  defp known_sort(nil, _model), do: nil

  defp sort(query, {%{field: field, arguments: arguments}, direction}, _via)
       when arguments == %{},
       do: Ash.Query.sort_input(query, [{field, direction}])

  # by a calculation as its column computes it: with the column's arguments
  defp sort(query, {%{field: field, arguments: arguments}, direction}, _via),
    do: Ash.Query.sort_input(query, [{field, {arguments, direction}}])

  # While the person has chosen no sort, the relationship's own goes where
  # theirs would: in front of the action's. Ash puts it behind, where an
  # action with a default sort never lets it be seen, and where "the latest
  # comment" of a has-one that picks one of many would be another one.
  defp sort(query, nil, %{sort: sort}) when sort not in [nil, []], do: Ash.Query.sort(query, sort)
  defp sort(query, nil, _via), do: query

  # One filter with the predicates of each column, which Ash combines with
  # AND. The values go in as they were typed: casting them, and what they
  # match, is the resource's.
  #
  # A calculation column that gives arguments is filtered by with them, as
  # the input of its calculation, and in a filter of its own: two columns
  # can show one calculation, and a filter holds a field once.
  #
  # So is a column whose operator leaves out what its predicates match ("is
  # none of"): its filter is those predicates under `not`.
  #
  # A datetime that was typed is a wall time in the page's zone: the filter
  # holds the instant it is (`AshDataTable.Zone.read/3`), and the state, and so
  # the URL, the text as it was typed.
  defp filter(query, [], _zone), do: query

  defp filter(query, filters, zone) do
    filters =
      for {column, {operator, value}} <- filters,
          do: {column, {operator, instants(column, value, zone)}}

    {plain, apart} =
      Enum.split_with(filters, fn {column, {operator, _value}} ->
        column.arguments == %{} and column.field == column.name and
          not Operator.negated?(operator)
      end)

    query =
      case plain do
        [] ->
          query

        plain ->
          Ash.Query.filter_input(
            query,
            Map.new(plain, fn {column, {operator, value}} ->
              {column.field, Map.new(Operator.predicates(operator, value))}
            end)
          )
      end

    Enum.reduce(apart, query, fn {column, {operator, value}}, query ->
      predicates = Map.new(Operator.predicates(operator, value) ++ input(column))
      statement = %{column.field => predicates}

      Ash.Query.filter_input(
        query,
        if(Operator.negated?(operator), do: %{not: statement}, else: statement)
      )
    end)
  end

  defp instants(column, {from, to}, zone),
    do: {Zone.read(column, from, zone), Zone.read(column, to, zone)}

  defp instants(column, value, zone), do: Zone.read(column, value, zone)

  defp input(%{arguments: arguments, field: field, name: name})
       when arguments == %{} and field == name,
       do: []

  defp input(%{arguments: arguments}), do: [{"input", arguments}]

  # How many records a page holds is never what a state says as it stands:
  # a state can come from a URL. `Pagination.size/2` takes a size the table
  # offers, and the read action's own for anything else.
  defp page_opts(%{pagination: %{strategy: :none}}, _state), do: false

  defp page_opts(%{pagination: %{strategy: :offset} = pagination} = model, state) do
    size = Pagination.size(pagination, state.per)
    [limit: size, offset: (state.page - 1) * size, count: count?(model, state)]
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
    [limit: Pagination.size(pagination, state.per), count: count?(model, state)] ++ position
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
    size = Pagination.size(model.pagination, state.per)
    pages = result.count && max(1, ceil(result.count / size))

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
