import Config

# The environment the browser tests run the demo in (`demo/e2e`, see the
# demo's README): the demo as it is, compiled once, with nothing that watches
# or reloads, on a database of its own that holds the standard seed. It has
# its own build directory, so it never waits for a dev server's.

# The database is one of the tests' own, as in config/test.exs. `demo_e2e`
# for `e2e/server.sh`; `npm test` names the one it seeds
# (`demo_e2e_template`) and each worker's copy of it (`demo_e2e_0` and up).
#
# Every browser test runs in a database transaction of its own, which is
# rolled back when it ends: Ecto's SQL sandbox, as `Phoenix.Ecto.SQL.Sandbox`
# describes it (`sql_sandbox` below, the plug in the endpoint and
# `DemoWeb.E2E.Sandbox`). A test holds one connection for everything its
# pages start, so a query may wait for another of the same test (the queue
# limits are those of config/test.exs), and a test may hold it for as long as
# its longest timeout (`ownership_timeout`).
config :demo, Demo.Repo,
  username: System.get_env("POSTGRES_USER", "ash_table"),
  password: System.get_env("POSTGRES_PASSWORD", "ash_table"),
  hostname: System.get_env("POSTGRES_HOST", "localhost"),
  port: String.to_integer(System.get_env("POSTGRES_PORT", "5477")),
  database: System.get_env("E2E_DATABASE", "demo_e2e"),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10,
  ownership_timeout: 300_000,
  queue_target: 5_000,
  queue_interval: 10_000

# Ash spawns no tasks, as its testing guide says for transactional tests
# ("Async tests"), and as config/test.exs has it. Otherwise a read with a
# count runs the count in a task of its own, which the read kills
# (`Task.shutdown(task, :brutal_kill)`) when its own query fails first; a
# process killed while it holds the test's one connection ends the test's
# transaction ("client #PID exited", then `DBConnection.OwnershipError` for
# everything after it).
config :ash, :disable_async?, true

# The endpoint has the plug `Phoenix.Ecto.SQL.Sandbox` (with `POST` and
# `DELETE /sandbox`), and the live socket the user agent the plug's metadata
# comes in, which `DemoWeb.E2E.Sandbox` allows each LiveView with.
config :demo, sql_sandbox: true

# The port is set in config/runtime.exs from PORT; demo/e2e/server.sh and
# demo/e2e/support/server.ts set it.
config :demo, DemoWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}],
  check_origin: false,
  secret_key_base:
    "e2eE2Ee2eE2Ek3m5uUu0vV3v6mXl3n2bq8m1q0oJrYt0Qd1mJmM7lV7r8nq2wQyH3c9T0aE2eE2eE2eE2"

# Mounts the routes of `e2e/server` (see the router).
config :demo, e2e_routes: true

# The sandbox's manual mode where the endpoint serves, and every LiveView
# allowed into its test's transaction (`DemoWeb.E2E.Sandbox`),
# and what the page of a browser test sent its LiveViews, heard on the server
# (`e2e/server/recorder.ex`, read by `Sent` in `e2e/support/fixtures.ts`).
config :demo, e2e_children: [DemoWeb.E2E.Sandbox, DemoWeb.E2E.Recorder]

# A warning or an error in the server's output is worth seeing; the rest is noise.
config :logger, level: :warning

# As in dev and test: the checks that find a duplicate id or a bad stream.
config :phoenix_live_view, enable_expensive_runtime_checks: true
