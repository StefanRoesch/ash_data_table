defmodule V32.MixProject do
  use Mix.Project
  @variant System.get_env("V", "hex")
  @flags System.get_env("FLAGS", "0")
  def project do
    [app: :v32, version: "0.1.0", elixir: "~> 1.17", deps: deps(@variant),
     deps_path: "deps_#{@variant}", build_path: "_build_#{@variant}_#{@flags}",
     lockfile: "mix_#{@variant}.lock", consolidate_protocols: false]
  end
  def application, do: [extra_applications: [:logger]]
  defp deps("hex"), do: [{:ash, "== 3.34.4"}, {:ash_postgres, "== 2.14.2"}, {:ash_sql, "== 0.8.1"}, {:simple_sat, "~> 0.1"}]
  defp deps("latest"), do: [{:ash, ">= 3.34.4"}, {:ash_postgres, ">= 2.14.2"}, {:ash_sql, ">= 0.8.1"}, {:simple_sat, "~> 0.1"}]
  defp deps("main"), do: [
    {:ash, github: "ash-project/ash", branch: "main", override: true},
    {:ash_postgres, github: "ash-project/ash_postgres", branch: "main", override: true},
    {:ash_sql, github: "ash-project/ash_sql", branch: "main", override: true},
    {:simple_sat, "~> 0.1"}]
  # ash_sql 0.8.1 copied to ../ash_sql_diag with a diagnostic change
  defp deps("diag"), do: [{:ash, "== 3.34.4"}, {:ash_postgres, "== 2.14.2"}, {:ash_sql, path: "../ash_sql_diag", override: true}, {:simple_sat, "~> 0.1"}]
end
