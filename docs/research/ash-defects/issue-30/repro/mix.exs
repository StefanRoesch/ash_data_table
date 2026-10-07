defmodule Ashbug.MixProject do
  use Mix.Project

  def project do
    [app: :ashbug, version: "0.1.0", elixir: "~> 1.17", deps: deps(),
     lockfile: System.get_env("ASHBUG_LOCK", "mix.lock")]
  end

  def application, do: [extra_applications: [:logger], mod: {Ashbug.Application, []}]

  defp deps do
    case System.get_env("ASHBUG_ASH", "hex") do
      "hex" ->
        [{:ash, "== 3.34.4"}, {:ash_postgres, "~> 2.14"}, {:simple_sat, "~> 0.1"}]

      "main" ->
        [
          {:ash, github: "ash-project/ash", branch: "main", override: true},
          {:ash_sql, github: "ash-project/ash_sql", branch: "main", override: true},
          {:ash_postgres, github: "ash-project/ash_postgres", branch: "main", override: true},
          {:simple_sat, "~> 0.1"}
        ]
    end
  end
end
