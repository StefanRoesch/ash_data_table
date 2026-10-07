defmodule V32.Repo do
  use AshPostgres.Repo, otp_app: :v32, warn_on_missing_ash_functions?: false
  def installed_extensions, do: []
  def min_pg_version, do: %Version{major: 16, minor: 0, patch: 0}
end
