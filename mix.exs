defmodule AshTable.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/StefanRoesch/ash_table"

  def project do
    [
      app: :ash_table,
      version: @version,
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      # Writes the colocated hook's manifest (`phoenix-colocated/ash_table`),
      # also when this project is compiled as a dependency of a host app.
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      deps: deps(),
      description:
        "An Ash extension that presents a resource to people as a table in Phoenix LiveView.",
      package: package(),
      source_url: @source_url
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ash, "~> 3.34"},
      {:ash_phoenix, "~> 2.3"},
      {:spark, "~> 2.7"},
      {:phoenix, "~> 1.8"},
      {:phoenix_live_view, "~> 1.2"},
      # The solver Ash's policies need. Only the test resources have policies;
      # a host application brings its own.
      {:simple_sat, "~> 0.1", only: :test}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE)
    ]
  end
end
