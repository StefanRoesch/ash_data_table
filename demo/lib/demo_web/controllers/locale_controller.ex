defmodule DemoWeb.LocaleController do
  @moduledoc "The language switcher's target: stores the chosen locale in the session."
  use DemoWeb, :controller

  def update(conn, params) do
    conn
    |> DemoWeb.Locale.put_locale(params["locale"])
    |> redirect(to: return_to(params["return_to"]))
  end

  # Only a path on this site.
  defp return_to("/" <> rest = path) do
    if String.starts_with?(rest, ["/", "\\"]), do: ~p"/", else: path
  end

  defp return_to(_), do: ~p"/"
end
