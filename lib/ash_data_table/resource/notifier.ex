defmodule AshDataTable.Resource.Notifier do
  @moduledoc """
  The notifier behind live updates: it announces that a record of a
  resource was created, updated or destroyed, so that the tables that show
  the resource can read the record again.

  It is not listed by hand. A resource whose `table` block says `live? true`
  gets it (see "Live updates" in `AshDataTable.Resource`), and it sends through
  the `Phoenix.PubSub` server that the `table` block of the resource's
  domain names as `pub_sub` (`AshDataTable.Domain`).

  ## What is announced

  One message per changed record, and nothing of the record but its primary
  key:

      {:ash_data_table_changed, resource, action_type, primary_key, tenant}

  `action_type` is `:create`, `:update` or `:destroy`; `primary_key` is a
  map of the primary key's attributes; `tenant` is the tenant of the record,
  nil where it has none. Neither the record, nor what changed, nor who
  changed it is sent: a table that hears of a key reads that record again
  as the person who is looking at it, through its own read action, and
  shows what that read returns. So a message tells nobody anything they may
  not read.

  ## Where it is announced

  On the topic `topic/2` gives for the resource and the record's tenant,
  which is what the tables of that tenant listen to; and on the topic
  without a tenant, which is what a table listens to that reads without
  one. Tenants never share a topic.

  ## What is not announced

  What Ash sends no notification for: a bulk action that is not run with
  `notify?: true`, a write that does not go through an action (`Ash.Seed`,
  the repo), and a generic action, which has no record. An action inside a
  transaction is announced when the transaction is committed, and not at
  all when it is rolled back. A resource without a primary key announces
  nothing.
  """
  use Ash.Notifier

  require Logger

  alias AshDataTable.Resource.Listening

  @typedoc "What a table hears of a changed record."
  @type message ::
          {:ash_data_table_changed, Ash.Resource.t(), :create | :update | :destroy, map, term}

  @impl Ash.Notifier
  def notify(%Ash.Notifier.Notification{
        resource: resource,
        action: %{type: type},
        data: %_{} = record,
        changeset: changeset
      })
      when type in [:create, :update, :destroy] do
    with {:ok, pub_sub} <- Listening.pub_sub(resource),
         [_ | _] = fields <- Ash.Resource.Info.primary_key(resource) do
      tenant = tenant(resource, record, changeset)
      message = {:ash_data_table_changed, resource, type, Map.take(record, fields), tenant}

      for topic <- Enum.uniq([topic(resource, nil), topic(resource, tenant)]) do
        broadcast(pub_sub, origin(changeset), topic, message)
      end
    end

    :ok
  end

  def notify(_notification), do: :ok

  @doc """
  The topic on which the changes of `resource` are announced for `tenant`:
  `"ash_data_table:" <> inspect(resource)`, followed by `":"` and the tenant
  where there is one. `tenant` is a tenant as Ash is given it
  (`Ash.ToTenant`); a resource without multitenancy has the one topic.
  """
  @spec topic(Ash.Resource.t(), term) :: String.t()
  def topic(resource, tenant) do
    base = "ash_data_table:" <> inspect(resource)

    case tenant && Ash.Resource.Info.multitenancy_strategy(resource) do
      none when none in [nil, false] -> base
      _strategy -> base <> ":" <> text(Ash.ToTenant.to_tenant(tenant, resource))
    end
  end

  defp text(tenant) do
    to_string(tenant)
  rescue
    Protocol.UndefinedError -> inspect(tenant)
  end

  # The tenant a record belongs to. Under attribute multitenancy it is read
  # off the record, so that a record written without a tenant (the resource
  # is `global? true`) is still announced to its tenant; else it is the
  # tenant the action ran in.
  defp tenant(resource, record, changeset) do
    case Ash.Resource.Info.multitenancy_strategy(resource) do
      nil ->
        nil

      :attribute ->
        attribute = Ash.Resource.Info.multitenancy_attribute(resource)

        case Map.get(record, attribute) do
          nil ->
            nil

          hidden when is_struct(hidden, Ash.NotLoaded) or is_struct(hidden, Ash.ForbiddenField) ->
            ran_in(changeset)

          value ->
            {module, function, arguments} =
              Ash.Resource.Info.multitenancy_tenant_from_attribute(resource)

            Ash.ToTenant.to_tenant(apply(module, function, [value | arguments]), resource)
        end

      _context ->
        ran_in(changeset)
    end
  end

  defp ran_in(%{to_tenant: tenant}), do: tenant
  defp ran_in(_none), do: nil

  # The listener of the table that ran the action, when a table did: it has
  # shown what the action returned already, and is not told again
  # (`AshDataTable.Query.reader_opts/1`).
  defp origin(%{context: %{ash_data_table_origin: pid}}) when is_pid(pid), do: pid
  defp origin(_changeset), do: nil

  # A write does not fail because nobody can be told of it.
  defp broadcast(pub_sub, origin, topic, message) do
    if origin,
      do: Phoenix.PubSub.broadcast_from(pub_sub, origin, topic, message),
      else: Phoenix.PubSub.broadcast(pub_sub, topic, message)
  rescue
    error in ArgumentError ->
      Logger.warning(
        "ash_data_table: a change of #{inspect(elem(message, 1))} could not be announced through " <>
          "#{inspect(pub_sub)}: #{Exception.message(error)}"
      )
  end
end
