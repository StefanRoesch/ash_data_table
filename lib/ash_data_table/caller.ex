defmodule AshDataTable.Caller do
  @moduledoc false
  # Who is asking, and what the page adds to every call to Ash: built from
  # server code only, never from what the browser sends. It holds no
  # assigns of the page (target F8).
  #
  #   * `scope`, or `actor` and `tenant`: who is asking, as the table was
  #     given them.
  #   * `authorize?`: whether Ash authorizes the calls. What the table was
  #     told, else what its resource's domain says.
  #   * `time_zone`: the time zone of the page, in which datetimes are shown,
  #     typed and filtered by (`AshDataTable.Zone`); a nested table and a
  #     picker are in that of the table they are rendered in. UTC until the
  #     table is told another.
  #
  # The 2a functions keep their keyword `opts` (target F7): `reader_opts/1`
  # is that list.

  @type t :: %__MODULE__{
          scope: term,
          actor: term,
          tenant: term,
          authorize?: boolean,
          time_zone: String.t()
        }

  defstruct scope: nil, actor: nil, tenant: nil, authorize?: true, time_zone: nil

  @doc "A caller of these values; the time zone is UTC unless one is given."
  @spec new(keyword) :: t
  def new(values \\ []) do
    struct!(%__MODULE__{time_zone: AshDataTable.Zone.utc()}, values)
  end

  @doc """
  Who is asking, as the options the functions of the data layer take:
  `actor`, `authorize?`, `scope` and `tenant`.
  """
  @spec reader_opts(t) :: keyword
  def reader_opts(%__MODULE__{} = caller) do
    [
      actor: caller.actor,
      authorize?: caller.authorize?,
      scope: caller.scope,
      tenant: caller.tenant
    ]
  end
end
