defmodule AshTable.Query do
  @moduledoc false
  # Reads one page of a table through its read action. Sorting, filtering and
  # pagination always run on the server; the sort and the filters a person
  # chose are applied with `Ash.Query.sort_input/2` and
  # `Ash.Query.filter_input/2`, the functions for outside input.

  alias AshTable.Model
  alias AshTable.Model.Operator
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
          | {:query, Ash.Query.t()}

  @doc """
  Reads the page `state` points at.

  ## Options

    * `:scope` - an `Ash.Scope`, carrying actor and tenant;
    * `:actor` and `:tenant` - used when no scope is given;
    * `:authorize?` - defaults to `true`;
    * `:query` - a base query to build on in place of the bare resource (for
      a table limited to related records).
  """
  @spec read(Model.t(), State.t(), [option]) :: {:ok, Page.t()} | {:error, Ash.Error.t()}
  def read(%Model{} = model, %State{} = state, opts \\ []) do
    read_opts = reader_opts(opts)

    # The sort a person chose goes in before the action's preparations run,
    # so that a sort of the action itself comes second, as a tie-breaker.
    query =
      (opts[:query] || model.resource)
      |> Ash.Query.new()
      |> sort(state.sort)
      |> filter(state.filters)
      |> Ash.Query.load(Model.loads(model))
      |> Ash.Query.for_read(model.read_action, %{}, read_opts)

    case Ash.read(query, [page: page_opts(model, state)] ++ read_opts) do
      {:ok, result} -> {:ok, page(result, model, state)}
      {:error, error} -> {:error, error}
    end
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

  defp sort(query, nil), do: query
  defp sort(query, {name, direction}), do: Ash.Query.sort_input(query, [{name, direction}])

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

  defp page_opts(%{pagination: %{strategy: :offset} = pagination}, state) do
    [
      limit: pagination.page_size,
      offset: (state.page - 1) * pagination.page_size,
      count: pagination.countable?
    ]
  end

  defp page_opts(%{pagination: %{strategy: :keyset} = pagination}, state) do
    position =
      cond do
        state.after -> [after: state.after]
        state.before -> [before: state.before]
        true -> []
      end

    # Ash counts for a keyset page as it does for an offset one, when the
    # action is countable.
    [limit: pagination.page_size, count: pagination.countable?] ++ position
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
