defmodule AshTableProto.MixProject do
  use Mix.Project

  # THROWAWAY PROTOTYPE for ticket #11. Never promoted to production.
  def project do
    [
      app: :ash_table_proto,
      version: "0.0.0",
      elixir: "~> 1.15",
      # REQUIRED (verified): without this line the hook file is still extracted
      # but no index.js manifest is written, and the host bundle fails with
      # `Could not resolve "phoenix-colocated/ash_table_proto"`. With it, the
      # manifest is written whenever this project is compiled, also as a
      # dependency of the host (into the HOST build directory).
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      deps: deps()
    ]
  end

  def application, do: [extra_applications: [:logger]]

  defp deps do
    [
      {:phoenix_live_view, "~> 1.2"},
      {:ash, "~> 3.34"},
      {:ash_phoenix, "~> 2.3"}
    ]
  end
end
