defmodule AshTable.Domain.Info do
  @moduledoc """
  Introspection for the `table` block of a domain.

  Every function also takes a domain that does not list the extension
  `AshTable.Domain`, and answers with the defaults.
  """
  use Spark.InfoGenerator, extension: AshTable.Domain, sections: [:table]

  @doc """
  Whether the tables of `resource` authorize: the `authorize?` of its domain,
  and `true` for a resource without one.
  """
  @spec authorize?(Ash.Resource.t()) :: boolean
  def authorize?(resource) do
    case Ash.Resource.Info.domain(resource) do
      nil -> true
      domain -> table_authorize?(domain)
    end
  end

  @doc """
  Who is asking for the table of `resource`, read from the assigns of a
  socket: `%{scope: scope}` when the assign its domain names as
  `scope_assign` is there and not nil, else `%{actor: actor, tenant: tenant}`
  from the ones named as `actor_assign` and `tenant_assign`. An assign that
  is not there is nil.
  """
  @spec reader(Ash.Resource.t(), map) :: %{scope: term} | %{actor: term, tenant: term}
  def reader(resource, assigns) do
    %{scope: scope, actor: actor, tenant: tenant} = assign_names(resource)

    case assigns[scope] do
      nil -> %{actor: assigns[actor], tenant: assigns[tenant]}
      scope -> %{scope: scope}
    end
  end

  @doc """
  The names of the socket assigns in which a mounted table of `resource`
  finds who is asking: those its domain names as `scope_assign`,
  `actor_assign` and `tenant_assign`, and the defaults for a resource
  without a domain.
  """
  @spec assign_names(Ash.Resource.t()) :: %{scope: atom, actor: atom, tenant: atom}
  def assign_names(resource) do
    case Ash.Resource.Info.domain(resource) do
      nil ->
        %{scope: :current_scope, actor: :current_user, tenant: :current_tenant}

      domain ->
        %{
          scope: table_scope_assign!(domain),
          actor: table_actor_assign!(domain),
          tenant: table_tenant_assign!(domain)
        }
    end
  end

  @doc """
  The name of the `Phoenix.PubSub` server that carries the live updates of
  `resource`: the `pub_sub` of its domain. Nil where the domain names none,
  and for a resource without a domain.
  """
  @spec pub_sub(Ash.Resource.t()) :: atom | nil
  def pub_sub(resource) do
    with domain when not is_nil(domain) <- Ash.Resource.Info.domain(resource),
         {:ok, pub_sub} <- table_pub_sub(domain) do
      pub_sub
    else
      _none -> nil
    end
  end
end
