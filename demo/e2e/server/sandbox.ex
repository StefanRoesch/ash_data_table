defmodule DemoWeb.E2E.Sandbox do
  @moduledoc """
  The browser tests' database transactions, as `Phoenix.Ecto.SQL.Sandbox`
  describes them: each test starts one with `POST /sandbox` (the plug in the
  endpoint), its browser sends what that answered as its user agent, and
  every request and LiveView with that user agent works in the test's
  transaction until `DELETE /sandbox` rolls it back
  (`e2e/support/server.ts`).

  A child of the application in the e2e environment only
  (`config :demo, e2e_children: …`), which starts no process. Where the
  endpoint serves, it

    * puts the sandbox into its manual mode, so that a process nobody
      allowed fails at its first query instead of writing outside every
      test. Where it does not serve, as in `mix run priv/repo/seeds.exs`,
      the sandbox stays in its automatic mode, which commits.
    * allows every connected LiveView into the transaction its user agent
      names (`connect_info`, see the endpoint), as it mounts: it hears
      LiveView's documented telemetry `[:phoenix, :live_view, :mount,
      :start]`, which is sent in the LiveView's process before its
      `on_mount` hooks run, as `DemoWeb.E2E.Recorder` does. So every live
      session is covered, the router's lines stay as a host writes them,
      and the hooks read in the test's transaction. What the LiveView starts
      with `start_async` (the tables' reads, summaries and runs) is allowed
      through it (`$callers`); the listener of live updates and Ash's
      notifiers do not reach the database. A disconnected mount runs in the
      request, which the plug allowed. (A LiveView nested with
      `live_render/3` has no `connect_info`; the demo has none.)

  It allows with the decoded metadata (`decode_metadata/1`), not with the
  text: `allow/2` given the text makes the process trap exits, which is for
  a request process; a LiveView that traps exits would be handed the exit
  of every task it started as a message.
  """
  alias Phoenix.Ecto.SQL.Sandbox

  @doc false
  def child_spec(_opts), do: %{id: __MODULE__, start: {__MODULE__, :start_link, []}}

  @doc false
  def start_link do
    if Phoenix.Endpoint.server?(:demo, DemoWeb.Endpoint) do
      :ok = Ecto.Adapters.SQL.Sandbox.mode(Demo.Repo, :manual)

      :ok =
        :telemetry.attach(
          __MODULE__,
          [:phoenix, :live_view, :mount, :start],
          &__MODULE__.handle/4,
          nil
        )
    end

    :ignore
  end

  @doc false
  def handle([:phoenix, :live_view, :mount, :start], _measurements, %{socket: socket}, _config) do
    if Phoenix.LiveView.connected?(socket) do
      socket
      |> Phoenix.LiveView.get_connect_info(:user_agent)
      |> Sandbox.decode_metadata()
      |> Sandbox.allow(Ecto.Adapters.SQL.Sandbox)
    end
  end
end
