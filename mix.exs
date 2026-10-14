defmodule AshDataTable.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/StefanRoesch/ash_data_table"
  @extensions "AshDataTable.Resource,AshDataTable.Domain"

  def project do
    [
      app: :ash_data_table,
      version: @version,
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      # Writes the colocated hook's manifest (`phoenix-colocated/ash_data_table`),
      # also when this project is compiled as a dependency of a host app.
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      # The colocated hooks import the hooks of the package, `assets/js/`.
      # LiveView links `node_modules` beside them to this path of the
      # package, wherever the package is (a path, `deps/`): they import
      # `../node_modules/js/index.js`. The table has no npm dependencies.
      phoenix_live_view: [colocated_assets: [node_modules_path: "assets"]],
      deps: deps(),
      # The template is shipped for hosts to copy into their own backend.
      # Without reference comments its messages count as written by hand
      # there, so the host's `mix gettext.extract` leaves them alone.
      gettext: [write_reference_comments: false],
      description:
        "An Ash extension that presents a resource to people as a table in Phoenix LiveView.",
      package: package(),
      source_url: @source_url,
      aliases: aliases(),
      docs: &docs/0
    ]
  end

  defp aliases do
    [
      # The DSL reference is generated from the extensions before the docs
      # are built, and its links are turned into ones ExDoc resolves.
      docs: ["spark.cheat_sheets", "docs", "spark.replace_doc_links"],
      "spark.cheat_sheets": "spark.cheat_sheets --extensions #{@extensions}",
      "spark.formatter": "spark.formatter --extensions #{@extensions}"
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "main",
      # The tutorial and the topic guides are in reading order. Their code
      # blocks are checked against the repository by
      # `test/documentation_test.exs`.
      extras: [
        "README.md",
        "documentation/tutorials/get-started-with-ash-data-table.md",
        "documentation/topics/columns-and-defaults.md",
        "documentation/topics/reading-sorting-and-pagination.md",
        "documentation/topics/filtering.md",
        "documentation/topics/arguments.md",
        "documentation/topics/state-in-the-url.md",
        "documentation/topics/inline-editing.md",
        "documentation/topics/confirm.md",
        "documentation/topics/choosing-a-related-record.md",
        "documentation/topics/managing-relationships.md",
        "documentation/topics/maps-and-embedded-resources.md",
        "documentation/topics/unions.md",
        "documentation/topics/row-actions-and-create.md",
        "documentation/topics/selecting-rows-and-bulk-actions.md",
        "documentation/topics/table-actions.md",
        "documentation/topics/files.md",
        "documentation/topics/nested-tables.md",
        "documentation/topics/named-tables.md",
        "documentation/topics/live-updates.md",
        "documentation/topics/footer-summaries.md",
        "documentation/topics/custom-components.md",
        "documentation/topics/sensitive-columns.md",
        "documentation/topics/authorization.md",
        "documentation/topics/keyboard-and-accessibility.md",
        "documentation/topics/messages-and-translations.md",
        "documentation/topics/time-zones.md",
        "documentation/topics/layout-and-embedding.md",
        "documentation/topics/mistakes-at-compile-time.md",
        "documentation/dsls/DSL-AshDataTable.Resource.md",
        "documentation/dsls/DSL-AshDataTable.Domain.md",
        "CHANGELOG.md"
      ],
      groups_for_extras: [
        Tutorials: ~r"documentation/tutorials",
        Topics: ~r"documentation/topics",
        "DSL reference": ~r"documentation/dsls",
        "About ash_data_table": ["CHANGELOG.md"]
      ],
      groups_for_modules: [
        Extensions: [AshDataTable.Resource, AshDataTable.Domain],
        "In the page": [
          AshDataTable,
          AshDataTable.Router,
          AshDataTable.Live.Page,
          AshDataTable.NotFoundError
        ],
        Components: [
          AshDataTable.Component,
          AshDataTable.Component.Column,
          AshDataTable.Components.Badge,
          AshDataTable.Components.Image,
          AshDataTable.Components.Progress,
          AshDataTable.Components.Slider
        ],
        "Live updates": [AshDataTable.Resource.Notifier, AshDataTable.Test],
        Translation: [AshDataTable.Gettext],
        Introspection: [
          AshDataTable.Resource.Info,
          AshDataTable.Resource.Table,
          AshDataTable.Resource.Column,
          AshDataTable.Resource.Relationship,
          AshDataTable.Resource.Action,
          AshDataTable.Resource.Reference,
          AshDataTable.Resource.Argument,
          AshDataTable.Resource.Upload,
          AshDataTable.Resource.Ask,
          AshDataTable.Domain.Info
        ]
      ]
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
      {:phoenix_live_view, "~> 1.2 and >= 1.2.10"},
      # Every text of the table goes through Gettext (`AshDataTable.Text`).
      {:gettext, "~> 0.26 or ~> 1.0"},
      # Only `mix ash_data_table.install` needs it; without it the task is a stub.
      {:igniter, "~> 0.6", optional: true},
      {:ex_doc, "~> 0.37", only: [:dev, :test], runtime: false},
      # The solver Ash's policies need. Only the test resources have policies;
      # a host application brings its own.
      {:simple_sat, "~> 0.1", only: :test},
      # A time zone database for the tests of zones other than UTC. A host
      # configures its own (`tz` or `tzdata`); the library needs none.
      {:tz, "~> 0.28", only: :test}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files:
        ~w(lib priv assets/js package.json documentation .formatter.exs mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end
end
