defmodule DemoWeb.Perf.ProbeController do
  @moduledoc """
  `Demo.Perf.Probe` over HTTP, for the performance scripts. Compiled and
  routed in the perf environment only (`perf/server`, and
  `config :demo, perf_routes: true`).
  """
  use DemoWeb, :controller

  alias Demo.Perf.Probe

  def start(conn, _params) do
    Probe.start()
    json(conn, %{recording: true})
  end

  def events(conn, _params), do: json(conn, Probe.drain())

  def live_views(conn, _params) do
    json(conn, %{live_views: Probe.live_views(), vm: Probe.vm()})
  end

  def versions(conn, _params) do
    version = fn app -> app |> Application.spec(:vsn) |> to_string() end

    json(conn, %{
      elixir: System.version(),
      otp: System.otp_release(),
      erts: to_string(:erlang.system_info(:version)),
      schedulers: System.schedulers_online(),
      mix_env: unquote(to_string(Mix.env())),
      database: Demo.Repo.config()[:database],
      postgres: Demo.Repo.query!("SHOW server_version").rows |> hd() |> hd(),
      tasks: Demo.Repo.query!("SELECT count(*) FROM tasks").rows |> hd() |> hd(),
      packages:
        Map.new(
          ~w(ash_table ash ash_postgres ash_phoenix phoenix phoenix_live_view bandit ecto_sql postgrex)a,
          &{&1, version.(&1)}
        )
    })
  end
end
