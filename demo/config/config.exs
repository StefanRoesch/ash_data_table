# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# These enable behaviors that will become the default in the next major
# version of Ash. Setting them now opts your application into the new
# behavior and ensures a seamless upgrade. See the backwards compatibility
# guide for an explanation of each setting:
# https://hexdocs.pm/ash/backwards-compatibility-config.html
config :ash,
  allow_forbidden_field_for_relationships_by_default: true,
  include_embedded_source_by_default?: false,
  show_keysets_for_all_actions?: false,
  default_page_type: :keyset,
  policies: [no_filter_static_forbidden_reads?: false],
  keep_read_action_loads_when_loading?: false,
  default_actions_require_atomic?: true,
  read_action_after_action_hooks_in_order?: true,
  bulk_actions_default_to_errors?: true,
  transaction_rollback_on_error?: true,
  redact_sensitive_values_in_errors?: true,
  default_string_length_count: :codepoints,
  infer_generic_action_reactors?: false,
  many_to_many_destroy_destination_on_match?: true,
  known_types: [AshPostgres.Timestamptz, AshPostgres.TimestamptzUsec]

# A time zone database, for the zones other than UTC that the tables show
# datetimes in (`DemoWeb.Zone`, `time_zone` of `AshDataTable.table/1`).
config :elixir, :time_zone_database, Tz.TimeZoneDatabase

config :spark,
  formatter: [
    remove_parens?: true,
    "Ash.Resource": [
      section_order: [
        :postgres,
        :resource,
        :code_interface,
        :actions,
        :policies,
        :pub_sub,
        :preparations,
        :changes,
        :validations,
        :multitenancy,
        :attributes,
        :relationships,
        :calculations,
        :aggregates,
        :identities
      ]
    ],
    "Ash.Domain": [section_order: [:resources, :policies, :authorization, :domain, :execution]]
  ]

config :demo,
  ecto_repos: [Demo.Repo],
  ash_domains: [Demo.Tracker, Demo.KitchenSink],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

config :demo, Demo.Repo, types: Demo.PostgrexTypes

# The CSV exports of the resources (`csv_exports`, ash_csv_interchange): the
# app that owns them, and the domains they are found in. `/tasks` exports
# the selected tasks with one (`Demo.Tracker.Task`, `:export_csv`).
config :ash_csv_interchange, otp_app: :demo
config :demo, AshCsvInterchange, domains: [Demo.Tracker]

# The layout the tables mounted by `ash_data_table` in the router are rendered in.
# The tables' own texts are translated by the demo's Gettext backend (the
# domain `ash_data_table`, in `priv/gettext/*/LC_MESSAGES/ash_data_table.po`), and the
# messages of the resources' actions by the function that translates the
# errors of the demo's own forms (the domain `errors`).
config :ash_data_table,
  layout: {DemoWeb.Layouts, :app},
  gettext_backend: DemoWeb.Gettext,
  translate_error: {DemoWeb.CoreComponents, :translate_error}

# Configure the endpoint
config :demo, DemoWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: DemoWeb.ErrorHTML, json: DemoWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Demo.PubSub,
  live_view: [signing_salt: "hIygmEPg"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  demo: [
    # Unminified, esbuild bundles React's development build (it sets
    # `process.env.NODE_ENV` from `--minify`): StrictMode and React's
    # checks, which dev and e2e want. The perf environment measures the
    # demo as production runs it (`assets.deploy`, minified): React's
    # production build, unminified.
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=. --jsx=automatic) ++
        if(config_env() == :perf,
          do: [~s(--define:process.env.NODE_ENV="production")],
          else: []
        ),
    cd: Path.expand("../assets", __DIR__),
    # deps/ (phoenix, phoenix_live_view, live_react), the colocated hooks of
    # the build, and assets/node_modules (npm: react, the shadcn sources'
    # packages), which live_react's files in deps/ import react from
    env: %{
      "NODE_PATH" => [
        Path.expand("../deps", __DIR__),
        Mix.Project.build_path(),
        Path.expand("../assets/node_modules", __DIR__)
      ]
    }
  ]

# The React islands (assets/islands) render in the browser only: no server
# rendering, so no Node at runtime.
config :live_react, ssr: false

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  demo: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
