# The demo for one worker of the browser tests (support/server.ts starts it):
#
#     MIX_ENV=e2e PORT=4480 E2E_DATABASE=demo_e2e_0 \
#       mix run --no-compile --no-start --no-halt e2e/server/worker.exs
#
# Makes the worker's database anew as a copy of `demo_e2e_template`, which
# `npm test` has migrated and seeded before any worker starts, and serves the
# demo on PORT. Nothing is compiled here: several of these start at once from
# the one build in `_build/e2e`.

database = System.fetch_env!("E2E_DATABASE")

# what is dropped here is a worker's database and nothing else: `demo_e2e_0`,
# or `demo_e2e_NAME_0` where a working copy has given its tests a name
# (E2E_NAME, support/server.ts)
unless database =~ ~r/\Ademo_e2e(_[a-z]+)?_\d+\z/ do
  raise "E2E_DATABASE must be demo_e2e_<number> or demo_e2e_<name>_<number>, got: #{inspect(database)}"
end

template = String.replace(database, ~r/_\d+\z/, "_template")

# Mix started the logger before it read the configuration; started again, it
# is the one of config/e2e.exs, as under `mix phx.server`.
Application.stop(:logger)
{:ok, _} = Application.ensure_all_started(:postgrex)

{:ok, postgres} =
  Demo.Repo.config()
  |> Keyword.take([:username, :password, :hostname, :port])
  |> Keyword.put(:database, "postgres")
  |> Postgrex.start_link()

# A server that had this database before and is still on its way out is cut off.
Postgrex.query!(postgres, ~s(DROP DATABASE IF EXISTS "#{database}" WITH \(FORCE\)), [])
Postgrex.query!(postgres, ~s(CREATE DATABASE "#{database}" TEMPLATE "#{template}"), [])
GenServer.stop(postgres)

# The server lives as long as the worker that started it: the worker holds
# the other end of its standard input, and when that is closed, however the
# worker ended, the server ends too.
spawn(fn ->
  read = fn read -> if IO.read(:stdio, :line) == :eof, do: System.halt(0), else: read.(read) end
  read.(read)
end)

Application.put_env(:phoenix, :serve_endpoints, true)
{:ok, _} = Application.ensure_all_started(:demo)
