defmodule Repro.MixProject do
  use Mix.Project

  def project do
    [app: :repro, version: "0.1.0", elixir: "~> 1.17", deps: deps(),
     lockfile: System.get_env("REPRO_LOCK", "mix.lock"),
     deps_path: System.get_env("REPRO_DEPS", "deps"),
     build_path: System.get_env("REPRO_BUILD", "_build")]
  end

  def application, do: [extra_applications: [:logger]]

  defp deps do
    case System.get_env("ASH_SOURCE", "3.34.4") do
      "main" -> [{:ash, github: "ash-project/ash", branch: "main"}, {:simple_sat, "~> 0.1"}]
      v -> [{:ash, v}, {:simple_sat, "~> 0.1"}]
    end
  end
end
