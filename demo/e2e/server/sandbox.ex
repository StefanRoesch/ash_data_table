defmodule DemoWeb.E2E.Sandbox do
  @moduledoc """
  The browser tests' database transactions, as `Phoenix.Ecto.SQL.Sandbox`
  describes them: each test starts one with `POST /sandbox` (the plug in the
  endpoint), its browser sends what that answered as its user agent, and
  every request and LiveView with that user agent works in the test's
  transaction until `DELETE /sandbox` rolls it back
  (`e2e/support/server.ts`).

  Two things, in the e2e environment only:

    * the child of the application (`config :demo, e2e_children: …`) that
      puts the sandbox into its manual mode where the endpoint serves, so
      that a process nobody allowed fails at its first query instead of
      writing outside every test. Where it does not serve, as in
      `mix run priv/repo/seeds.exs`, the sandbox stays in its automatic
      mode, which commits.
    * the `on_mount` hook of every live session (see the router), first:
      it allows the LiveView's process into the transaction its user agent
      names. What the LiveView starts with `start_async` (the tables' reads,
      summaries and runs) is allowed through it (`$callers`), and the
      listener of live updates and Ash's notifiers do not reach the
      database. A disconnected mount runs in the request, which the plug
      allowed.

  The hook allows with the decoded metadata (`decode_metadata/1`), not with
  the text: `allow/2` given the text makes the process trap exits, which is
  for a request process; a LiveView that traps exits would be handed the
  exit of every task it started as a message.
  """
  import Phoenix.LiveView

  alias Phoenix.Ecto.SQL.Sandbox

  @doc false
  def child_spec(_opts), do: %{id: __MODULE__, start: {__MODULE__, :start_link, []}}

  @doc false
  def start_link do
    if Phoenix.Endpoint.server?(:demo, DemoWeb.Endpoint) do
      :ok = Ecto.Adapters.SQL.Sandbox.mode(Demo.Repo, :manual)
    end

    :ignore
  end

  @doc false
  def on_mount(:default, _params, _session, socket) do
    if connected?(socket) do
      socket
      |> get_connect_info(:user_agent)
      |> Sandbox.decode_metadata()
      |> Sandbox.allow(Ecto.Adapters.SQL.Sandbox)
    end

    {:cont, socket}
  end
end
