import Config

# The environment the performance scripts measure the demo in (`demo/perf`,
# see the demo's README). It is the demo as production would run it, as far
# as measuring goes: no code reloading, no debug annotations, no runtime
# checks, plugs initialised at compile time, protocols consolidated.
#
# What differs from config/prod.exs: plain HTTP on loopback, assets neither
# minified nor digested (with React's production build all the same, as
# the minified bundle has it: config/config.exs), a fixed secret, no
# `check_origin`, and the routes and modules of `perf/server`, which exist
# in this environment only.

# PERF_DB chooses between the two databases the scripts seed: the large one
# (the default) and the standard one. Neither is the dev database.
config :demo, Demo.Repo,
  username: System.get_env("POSTGRES_USER", "ash_table"),
  password: System.get_env("POSTGRES_PASSWORD", "ash_table"),
  hostname: System.get_env("POSTGRES_HOST", "localhost"),
  port: String.to_integer(System.get_env("POSTGRES_PORT", "5477")),
  database: System.get_env("PERF_DB", "demo_perf"),
  pool_size: 10

# The port is set in config/runtime.exs from PORT; the scripts set it.
config :demo, DemoWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}],
  check_origin: false,
  secret_key_base:
    "pErFpErFpErFk3m5uUu0vV3v6mXl3n2bq8m1q0oJrYt0Qd1mJmM7lV7r8nq2wQyH3c9T0aE2eE2eE2eE"

# Mounts the routes of `perf/server` (see the router), and names its domain.
config :demo,
  perf_routes: true,
  ash_domains: [Demo.Tracker, Demo.KitchenSink, Demo.Perf]

config :logger, level: :warning
