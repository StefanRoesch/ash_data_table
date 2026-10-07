defmodule Agg.Repo do
  use AshPostgres.Repo, otp_app: :agg
  def installed_extensions, do: ["ash-functions"]
  def min_pg_version, do: %Version{major: 16, minor: 0, patch: 0}
end

defmodule Agg.Application do
  use Application
  def start(_, _), do: Supervisor.start_link([Agg.Repo], strategy: :one_for_one)
end

# Custom aggregate: joins the values with "," in ascending order.
defmodule Agg.Joined do
  use Ash.Resource.Aggregate.CustomAggregate
  use AshPostgres.CustomAggregate
  require Ecto.Query

  @impl AshPostgres.CustomAggregate
  def dynamic(_opts, binding) do
    Ecto.Query.dynamic([], fragment("string_agg(?::text, ',' ORDER BY ?)", field(as(^binding), :secret), field(as(^binding), :secret)))
  end
end
