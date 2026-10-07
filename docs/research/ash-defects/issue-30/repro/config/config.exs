import Config

config :ashbug, ecto_repos: [Ashbug.Repo], ash_domains: [Ashbug.Pg, Ashbug.Ets]

config :ashbug, Ashbug.Repo,
  username: "ash_table", password: "ash_table", hostname: "127.0.0.1", port: 5477,
  database: "ashbug_30", pool_size: 5, log: false

config :logger, level: :warning

# Required by ash 3.34 at compile time; :mixed is "keeps the previous behavior".
config :ash, default_string_length_count: :mixed

# ASHBUG_FLAGS=1 : the colleague's demo flags, copied from demo/config/config.exs
if System.get_env("ASHBUG_FLAGS") == "1" do
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
