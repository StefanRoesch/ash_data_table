import Config
config :agg, ash_domains: [Agg.Ets.Domain, Agg.Pg.Domain], ecto_repos: [Agg.Repo]
config :agg, Agg.Repo,
  hostname: "127.0.0.1", port: 5477, username: "ash_table", password: "ash_table",
  database: "ashbug_33", pool_size: 5, log: (if System.get_env("SQLLOG"), do: :debug, else: false)
config :logger, level: :warning
# required by ash 3.34 to compile at all; the same value the demo uses
config :ash, default_string_length_count: :codepoints

if System.get_env("ASH_FLAGS", "default") == "demo" do
  # verbatim from /home/stefan-roesch/doloops/ash_table/demo/config/config.exs
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
end
