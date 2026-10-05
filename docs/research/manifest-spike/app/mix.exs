defmodule Spike.MixProject do
  use Mix.Project

  def project do
    [
      app: :spike,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Spike.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ash, "~> 3.34"},
      {:picosat_elixir, "~> 0.2"}
    ]
  end
end
