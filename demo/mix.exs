defmodule Demo.MixProject do
  use Mix.Project

  def project do
    [
      app: :demo,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      consolidate_protocols: Mix.env() != :dev
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Demo.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  # What the browser tests and the performance scripts need of the server.
  defp elixirc_paths(:e2e), do: ["lib", "e2e/server"]
  defp elixirc_paths(:perf), do: ["lib", "perf/server", "test/support/modes_tables.ex"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:sourceror, "~> 1.8", only: [:dev, :test]},
      {:ash_data_table, path: ".."},
      {:ash_phoenix, "~> 2.0"},
      {:ash_postgres, "~> 2.14 and >= 2.14.5"},
      {:ash_sql, "~> 0.8 and >= 0.8.2"},
      {:ash, "~> 3.36 and >= 3.36.1"},
      {:picosat_elixir, "~> 0.2"},
      {:phoenix, "~> 1.8.5"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      # An MCP endpoint into the running demo for coding agents, at /tidewave/mcp.
      {:tidewave, "~> 0.9", only: :dev},
      {:phoenix_live_view, "~> 1.2.0"},
      {:lazy_html, ">= 0.1.0", only: [:test, :e2e]},
      # LiveReact.Test.get_react/2 reads an island with it (react_kit_test.exs)
      {:floki, ">= 0.30.0", only: :test},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      # The time zone database the tables convert datetimes with: the demo
      # shows them in the zone of the person's browser (`DemoWeb.Zone`).
      # `ash_data_table` brings none; a host configures its own.
      {:tz, "~> 0.28"},
      {:bandit, "~> 1.5"},
      # React islands in LiveView, for the React kit (stage 8 of the
      # refactor): SSR off (config/config.exs), so no Node at runtime. Its JS
      # is bundled by the Hex esbuild from deps/, as phoenix_live_view's is.
      {:live_react, "~> 2.0"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ash.setup", "assets.setup", "assets.build", "run priv/repo/seeds.exs"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ash.setup --quiet", "test"],
      # npm only for the React islands' packages (assets/package.json), with
      # Node 20 or later. `npm install`, not `npm ci`: it installs what
      # package-lock.json pins as well, but changes node_modules only where
      # it differs from the lockfile, while `npm ci` deletes node_modules
      # every time, which breaks a running dev server's esbuild watcher
      # (the browser tests' global setup runs this alias).
      "assets.setup": [
        "tailwind.install --if-missing",
        "esbuild.install --if-missing",
        "cmd --cd assets npm install --no-audit --no-fund"
      ],
      "assets.build": ["compile", "tailwind demo", "esbuild demo"],
      "assets.deploy": [
        "tailwind demo --minify",
        "esbuild demo --minify",
        "phx.digest"
      ],
      precommit: [
        "compile --force --warnings-as-errors",
        "deps.unlock --unused",
        "format",
        "test"
      ]
    ]
  end
end
