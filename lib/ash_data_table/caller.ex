defmodule AshDataTable.Caller do
  @moduledoc false
  # Who is asking, and what the page adds to every call to Ash: built from
  # server code only, never from what the browser sends. It holds no
  # assigns of the page (target F8).
  #
  #   * `scope`, or `actor` and `tenant`: who is asking, as the table was
  #     given them.
  #   * `time_zone`: the time zone of the page, in which datetimes are shown,
  #     typed and filtered by (`AshDataTable.Zone`); a nested table and a
  #     picker are in that of the table they are rendered in. UTC until the
  #     table is told another.
  #   * `context`, `private_arguments`, `page_arguments`: what the page adds
  #     to every call to Ash, each a map or a function of the page's assigns
  #     (and of which table asks, for one of two arguments), nil for none;
  #     `before_action`: the page's veto, a function of the
  #     `AshDataTable.Request` (and the assigns), nil for none. The live
  #     layer calls them with the assigns as they are then, in the
  #     LiveView's process (target F8): the caller holds the functions, never
  #     what they return.
  #
  # The 2a functions keep their keyword `opts` (target F7): `reader_opts/1`
  # is that list.

  @typedoc "A map, or a function of the page's assigns (and of which table asks) to one."
  @type page_value :: map | (map -> map) | (map, map -> map) | nil

  @type t :: %__MODULE__{
          scope: term,
          actor: term,
          tenant: term,
          time_zone: String.t(),
          context: page_value,
          private_arguments: page_value,
          page_arguments: page_value,
          before_action:
            (AshDataTable.Request.t() -> term) | (AshDataTable.Request.t(), map -> term) | nil
        }

  defstruct scope: nil,
            actor: nil,
            tenant: nil,
            time_zone: nil,
            context: nil,
            private_arguments: nil,
            page_arguments: nil,
            before_action: nil

  @doc "A caller of these values; the time zone is UTC unless one is given."
  @spec new(keyword) :: t
  def new(values \\ []) do
    struct!(%__MODULE__{time_zone: AshDataTable.Zone.utc()}, values)
  end

  @doc """
  Which person is asking, to tell whether two callers are the same person:
  the actor (the scope's, where the caller has a scope and no actor), as
  its resource and primary key where it is a record of a resource, else as
  it is. Nil where nobody is asking. A person whose role or scope changed
  is the same person.
  """
  @spec who(t) :: term
  def who(%__MODULE__{actor: nil, scope: scope}) when not is_nil(scope) do
    case Ash.Scope.ToOpts.get_actor(scope) do
      {:ok, actor} -> person(actor)
      :error -> nil
    end
  end

  def who(%__MODULE__{actor: actor}), do: person(actor)

  defp person(%resource{} = record) do
    if Ash.Resource.Info.resource?(resource),
      do: {resource, Map.take(record, Ash.Resource.Info.primary_key(resource))},
      else: record
  end

  defp person(actor), do: actor

  @doc """
  Who is asking, as the options the functions of the data layer take:
  `actor`, `scope` and `tenant`. Whether Ash authorizes is each table's
  (`authorize?` of its entry), which `AshDataTable.Live.Core.reader/1` adds.
  """
  @spec reader_opts(t) :: keyword
  def reader_opts(%__MODULE__{} = caller) do
    [
      actor: caller.actor,
      scope: caller.scope,
      tenant: caller.tenant
    ]
  end
end
