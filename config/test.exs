import Config

# Only the test suite needs domains: it generates `Ash.Info.Manifest` to check
# our own cell type classification against it (ADR 0001).
config :ash_data_table, ash_domains: [AshDataTable.Test.Domain]

config :logger, level: :warning

# The zones other than UTC that the tests show and convert datetimes in.
config :elixir, :time_zone_database, Tz.TimeZoneDatabase
