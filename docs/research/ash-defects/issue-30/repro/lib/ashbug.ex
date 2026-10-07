defmodule Ashbug.Repo do
  use AshPostgres.Repo, otp_app: :ashbug
  def installed_extensions, do: ["ash-functions"]
  def min_pg_version, do: %Version{major: 16, minor: 0, patch: 0}
end

defmodule Ashbug.Application do
  use Application
  def start(_, _), do: Supervisor.start_link([Ashbug.Repo], strategy: :one_for_one)
end
