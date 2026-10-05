import Config

config :ash, default_string_length_count: :codepoints

# Only the test suite needs domains: it generates `Ash.Info.Manifest` to check
# our own cell type classification against it (ADR 0001).
config :ash_table, ash_domains: [AshTable.Test.Domain]

config :logger, level: :warning
