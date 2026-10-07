import Config
config :bug, ecto_repos: [Bug.Repo], ash_domains: [Bug.Pg.Domain, Bug.Ets.Domain]
config :bug, Bug.Repo,
  username: "ash_table", password: "ash_table", hostname: "127.0.0.1", port: 5477,
  database: "ashbug_31", pool_size: 5, log: false
config :logger, level: :warning
if System.get_env("BUG_FLAGS") == "1" do
  # the colleague's flags, copied from demo/config/config.exs
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
  # Ash's defaults. This one key has no default any more (Ash refuses to compile without it);
  # :mixed "keeps the previous behavior".
  config :ash, default_string_length_count: :mixed
end
