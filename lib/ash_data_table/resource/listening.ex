defmodule AshDataTable.Resource.Listening do
  @moduledoc false
  # Live updates as a declaration says them: whether a resource announces
  # its changes, whether a table of it follows them, and through which
  # `Phoenix.PubSub` server. Shared by the domain's verifier, which reports
  # a domain that names no server, and by the table model, which builds on
  # the answer.

  alias AshDataTable.Resource.Info
  alias AshDataTable.Resource.Table

  @type reason ::
          {:no_pub_sub, Ash.Resource.t(), module | nil}
          | {:not_announced, Ash.Resource.t()}

  @doc "Whether the resource announces its changes: its `table` block says `live? true`."
  @spec announces?(module) :: boolean
  def announces?(resource) do
    # a module that is no resource of ours does not
    Spark.Dsl.is?(resource, Ash.Resource) and
      AshDataTable.Resource in Spark.extensions(resource) and
      Info.table_live?(resource)
  end

  @doc """
  Whether a table of the resource follows live updates: the resource
  announces them, and the table does not say `live? false`.
  """
  @spec follows?(Ash.Resource.t(), Table.t()) :: boolean
  def follows?(resource, %Table{live?: live?}), do: Info.table_live?(resource) and live? != false

  @doc """
  The `Phoenix.PubSub` server the resource announces through: the `pub_sub`
  of its domain.
  """
  @spec pub_sub(Ash.Resource.t()) :: {:ok, atom} | {:error, reason}
  def pub_sub(resource) do
    case AshDataTable.Domain.Info.pub_sub(resource) do
      nil -> {:error, {:no_pub_sub, resource, Ash.Resource.Info.domain(resource)}}
      pub_sub -> {:ok, pub_sub}
    end
  end

  @doc "What is wrong, for whoever wrote the declaration."
  @spec message(reason) :: String.t()
  def message({:no_pub_sub, resource, nil}),
    do:
      "#{inspect(resource)} says `live? true`, but it has no domain to name a `pub_sub`. " <>
        "Live updates are sent through a Phoenix.PubSub server, which the `table` block of " <>
        "the resource's domain names (`AshDataTable.Domain`)."

  def message({:no_pub_sub, resource, domain}),
    do:
      "#{inspect(resource)} says `live? true`, but the `table` block of #{inspect(domain)} " <>
        "names no `pub_sub`. Live updates are sent through a Phoenix.PubSub server: add " <>
        "`pub_sub MyApp.PubSub` to the `table` block of #{inspect(domain)} " <>
        "(with `extensions: [AshDataTable.Domain]`)."

  def message({:not_announced, resource}),
    do:
      "it is asked to show live updates (`live?: true`), but #{inspect(resource)} announces " <>
        "none: add `live? true` to its `table` block."
end
