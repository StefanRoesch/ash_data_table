defmodule Bug.MixProject do
  use Mix.Project
  @variant System.get_env("BUG_VARIANT", "hex")
  @flags System.get_env("BUG_FLAGS", "0")
  def project do
    [
      app: :bug,
      version: "0.1.0",
      elixir: "~> 1.17",
      deps: deps(@variant),
      deps_path: "deps_#{@variant}",
      build_path: "_build_#{@variant}_#{@flags}",
      lockfile: "mix_#{@variant}.lock",
      consolidate_protocols: false
    ]
  end
  def application, do: [extra_applications: [:logger]]
  # exactly what the colleague's demo has locked
  defp deps("hex"), do: [{:ash, "== 3.34.4"}, {:ash_postgres, "== 2.14.2"}, {:ash_sql, "== 0.8.1"}, {:simple_sat, "~> 0.1"}]
  # newest on Hex at the time of the run
  defp deps("latest"), do: [{:ash, ">= 3.34.4"}, {:ash_postgres, ">= 2.14.3"}, {:ash_sql, ">= 0.8.1"}, {:simple_sat, "~> 0.1"}]
  # 3.34.4 copied to ../ash_3.34.4_diagnostic with one IO.puts and one env-switched condition in authorize_sort
  defp deps("diag"), do: [{:ash, path: "../ash_3.34.4_diagnostic", override: true}, {:ash_postgres, "== 2.14.2"}, {:ash_sql, "== 0.8.1"}, {:simple_sat, "~> 0.1"}]
  defp deps("main"),
    do: [
      {:ash, github: "ash-project/ash", branch: "main", override: true},
      {:ash_postgres, github: "ash-project/ash_postgres", branch: "main", override: true},
      {:ash_sql, github: "ash-project/ash_sql", branch: "main", override: true},
      {:simple_sat, "~> 0.1"}
    ]
end
