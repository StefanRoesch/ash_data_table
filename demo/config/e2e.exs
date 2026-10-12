import Config

# The environment the browser tests run the demo in (`demo/e2e`, see the
# demo's README): the demo as it is, compiled once, with nothing that watches
# or reloads, on a database of its own that the tests seed again and again.
# It has its own build directory, so it never waits for a dev server's.

# The database is one of the tests' own, as in config/test.exs: they empty
# it. `demo_e2e` for `e2e/server.sh`; `npm test` names the one it seeds
# (`demo_e2e_template`) and each worker's copy of it (`demo_e2e_0` and up).
config :demo, Demo.Repo,
  username: System.get_env("POSTGRES_USER", "ash_table"),
  password: System.get_env("POSTGRES_PASSWORD", "ash_table"),
  hostname: System.get_env("POSTGRES_HOST", "localhost"),
  port: String.to_integer(System.get_env("POSTGRES_PORT", "5477")),
  database: System.get_env("E2E_DATABASE", "demo_e2e"),
  pool_size: 10

# The port is set in config/runtime.exs from PORT; demo/e2e/server.sh and
# demo/e2e/support/server.ts set it.
config :demo, DemoWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}],
  check_origin: false,
  secret_key_base:
    "e2eE2Ee2eE2Ek3m5uUu0vV3v6mXl3n2bq8m1q0oJrYt0Qd1mJmM7lV7r8nq2wQyH3c9T0aE2eE2eE2eE2"

# Mounts the routes of `e2e/server`, which seed the database again (see the router).
config :demo, e2e_routes: true

# A warning or an error in the server's output is worth seeing; the rest is noise.
config :logger, level: :warning

# As in dev and test: the checks that find a duplicate id or a bad stream.
config :phoenix_live_view, enable_expensive_runtime_checks: true
