import Config
config :bug, ecto_repos: [Bug.Repo], ash_domains: [Pg.Domain, Ets.Domain]
config :bug, Bug.Repo, username: "ash_table", password: "ash_table", hostname: "127.0.0.1", port: 5477,
  database: "ashbug_35", pool_size: 5, log: false
config :logger, level: :warning
demo_flags = [
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
  many_to_many_destroy_destination_on_match?: true
]
# ASH_FLAGS=demo: all of the colleague's demo flags. ASH_ONLY=a,b: only those of them. Neither: Ash's defaults.
flags =
  cond do
    System.get_env("ASH_FLAGS") == "demo" -> demo_flags
    only = System.get_env("ASH_ONLY") -> Keyword.take(demo_flags, Enum.map(String.split(only, ","), &String.to_atom/1))
    true -> []
  end
# ash 3.34 requires this one to be set; :mixed keeps the previous behaviour
config :ash, Keyword.put_new(flags, :default_string_length_count, :mixed)
