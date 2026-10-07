defmodule Phx.MixProject do
  use Mix.Project

  def project do
    [app: :phx, version: "0.1.0", elixir: "~> 1.17", deps: deps(), listeners: [Phoenix.CodeReloader]]
  end

  def application, do: [mod: {Phx.Application, []}, extra_applications: [:logger]]

  defp deps do
    [{:ash, "3.34.4"}, {:simple_sat, "~> 0.1"}, {:phoenix, "~> 1.8"}, {:bandit, "~> 1.5"}, {:jason, "~> 1.4"}]
  end
end
