defmodule DemoWeb.ActorController do
  @moduledoc "The actor switcher's target: stores the chosen user id in the session."
  use DemoWeb, :controller

  alias Demo.Actors

  def update(conn, params) do
    user = Actors.fetch(params["actor"])

    conn
    |> DemoWeb.Actor.put_actor(user)
    |> put_flash(:info, "You are now #{describe(user)}.")
    |> redirect(to: return_to(params["return_to"]))
  end

  defp describe(nil), do: "nobody (not logged in)"
  defp describe(user), do: "#{user.name} (#{user.role})"

  # Only a path on this site.
  defp return_to("/" <> rest = path) do
    if String.starts_with?(rest, ["/", "\\"]), do: ~p"/", else: path
  end

  defp return_to(_), do: ~p"/"
end
