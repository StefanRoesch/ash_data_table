import Config
config :v32, ecto_repos: [V32.Repo], ash_domains: [V32.Pg.Domain, V32.Ets.Domain]
config :v32, V32.Repo, username: "ash_table", password: "ash_table", hostname: "127.0.0.1", port: 5477,
  database: "ashbug_32", pool_size: 5, log: false
config :logger, level: :warning
if System.get_env("FLAGS") == "1" do
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
else
  config :ash, default_string_length_count: :mixed
end
