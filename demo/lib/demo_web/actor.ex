defmodule DemoWeb.Actor do
  @moduledoc """
  Who you are in the demo. There is no login: the actor switcher in the page
  header stores a user id in the session, and this module turns it into

    * `current_user` - the `Demo.Tracker.User`, or `nil` when nobody is chosen
    * `current_tenant` - that user's organization id, or `nil`

  on the conn (as a plug) and on the socket (as an `on_mount` hook). These are
  the assign names `ash_table` reads by default.
  """
  import Plug.Conn

  alias Demo.Actors

  @doc "Plug: assigns `current_user` and `current_tenant` from the session."
  def init(opts), do: opts

  def call(conn, _opts) do
    user = conn |> get_session(Actors.session_key()) |> Actors.fetch()

    conn
    |> assign(:current_user, user)
    |> assign(:current_tenant, Actors.tenant(user))
  end

  @doc "LiveView hook: assigns `current_user` and `current_tenant` from the session."
  def on_mount(:default, _params, session, socket) do
    socket =
      socket
      |> Phoenix.Component.assign_new(:current_user, fn ->
        session |> Map.get(Actors.session_key()) |> Actors.fetch()
      end)
      |> then(fn socket ->
        Phoenix.Component.assign_new(socket, :current_tenant, fn ->
          Actors.tenant(socket.assigns.current_user)
        end)
      end)

    {:cont, socket}
  end

  @doc "Puts the chosen actor in the session: a user, a user id, or `nil` for nobody."
  def put_actor(conn, nil), do: delete_session(conn, Actors.session_key())
  def put_actor(conn, %Demo.Tracker.User{id: id}), do: put_actor(conn, id)
  def put_actor(conn, id) when is_binary(id), do: put_session(conn, Actors.session_key(), id)
end
