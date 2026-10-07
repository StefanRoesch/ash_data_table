defmodule Bug.MixProject do
  use Mix.Project
  @vers System.get_env("VERS", "locked")
  def project do
    [app: :bug, version: "0.1.0", elixir: "~> 1.17", deps: deps(@vers),
     lockfile: "mix.#{@vers}.lock", deps_path: "deps_#{@vers}", build_path: "_build_#{@vers}",
     consolidate_protocols: false]
  end
  def application, do: [extra_applications: [:logger], mod: {Bug.Application, []}]
  defp deps("locked"), do: [{:ash, "== 3.34.4"}, {:ash_sql, "== 0.8.1"}, {:ash_postgres, "== 2.14.2"}, {:picosat_elixir, "~> 0.2"}]
  # COPIES of the locked ash_sql / ash_postgres, for diagnostics and a trial fix only
  defp deps("patched"), do: [{:ash, "== 3.34.4"}, {:ash_sql, path: "../copies/ash_sql", override: true}, {:ash_postgres, path: "../copies/ash_postgres", override: true}, {:picosat_elixir, "~> 0.2"}]
  defp deps("latest"), do: [{:ash, "~> 3.34"}, {:ash_sql, "~> 0.8"}, {:ash_postgres, "~> 2.14"}, {:picosat_elixir, "~> 0.2"}]
  defp deps("main"), do: [
    {:ash, github: "ash-project/ash", branch: "main", override: true},
    {:ash_sql, github: "ash-project/ash_sql", branch: "main", override: true},
    {:ash_postgres, github: "ash-project/ash_postgres", branch: "main", override: true},
    {:picosat_elixir, "~> 0.2"}]
end
