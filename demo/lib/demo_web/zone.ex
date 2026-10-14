defmodule DemoWeb.Zone do
  @moduledoc """
  Which time zone the demo's tables show datetimes in: the zone of the
  person's browser, which `assets/js/app.js` sends with the LiveView's
  connect params (`Intl.DateTimeFormat().resolvedOptions().timeZone`).

  An `on_mount` hook puts it into the socket assign `time_zone`, where a
  mounted table finds it (`time_zone_assign` of `AshDataTable.Domain`), and the
  demo's own pages pass it to the tables they place
  (`<AshDataTable.table time_zone={@time_zone}>`).

  The zone the browser names is a claim: it is taken only when the time zone
  database knows it, else the tables are in UTC. So is the first render,
  before the browser has connected. A real application would rather take
  the zone from the person's settings; this is a convenience of the demo.
  """
  import Phoenix.LiveView, only: [connected?: 1, get_connect_params: 1]

  @utc "Etc/UTC"

  @doc "LiveView hook: assigns the browser's zone as `time_zone`, UTC where it is none."
  def on_mount(:default, _params, _session, socket) do
    zone =
      if connected?(socket),
        do: known(get_connect_params(socket)["time_zone"]),
        else: @utc

    {:cont, Phoenix.Component.assign(socket, time_zone: zone)}
  end

  # A zone the time zone database knows, else UTC.
  defp known(zone) when is_binary(zone) do
    case DateTime.shift_zone(~U[2000-01-01 00:00:00Z], zone) do
      {:ok, _shifted} -> zone
      {:error, _reason} -> @utc
    end
  end

  defp known(_none), do: @utc
end
