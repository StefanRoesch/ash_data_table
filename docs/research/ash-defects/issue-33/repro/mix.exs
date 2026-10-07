defmodule Agg.MixProject do
  use Mix.Project

  # ASH_SRC = 3.34.4 (default) | main ; ASH_FLAGS = default | demo
  @src System.get_env("ASH_SRC", "3.34.4")
  @flags System.get_env("ASH_FLAGS", "default")

  def project do
    [app: :agg, version: "0.1.0", elixir: "~> 1.17", deps: deps(),
     lockfile: "mix.#{@src}.lock", deps_path: "deps_#{@src}",
     build_path: "_build_#{@src}_#{@flags}"]
  end

  def application, do: [extra_applications: [:logger], mod: {Agg.Application, []}]

  defp deps do
    case @src do
      "main" ->
        [{:ash, github: "ash-project/ash", override: true},
         {:ash_postgres, github: "ash-project/ash_postgres"},
         {:ash_sql, github: "ash-project/ash_sql", override: true},
         {:simple_sat, "~> 0.1"}]
      v -> [{:ash, v}, {:ash_postgres, "2.14.3"}, {:simple_sat, "~> 0.1"}]
    end
  end
end
