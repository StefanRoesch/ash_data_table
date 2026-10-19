defmodule DemoWeb.E2E.KitChoice do
  @moduledoc """
  Which kit the tables of a page are drawn with (`DemoWeb.E2E.ChosenKit`):
  a plug of the browser's pipeline in the e2e environment, which keeps the
  header `x-demo-kit` in the session, and a child of the application, which
  starts no process and notes the kit of the session in each LiveView's
  process as it mounts.
  """
  @behaviour Plug

  @kits %{"react" => DemoWeb.ReactKit}

  @doc false
  def child_spec(_opts), do: %{id: __MODULE__, start: {__MODULE__, :start_link, []}}

  @doc false
  def start_link do
    :ok =
      :telemetry.attach(
        __MODULE__,
        [:phoenix, :live_view, :mount, :start],
        &__MODULE__.mounting/4,
        nil
      )

    :ignore
  end

  @doc false
  def mounting(_event, _measurements, %{session: session}, _config) do
    if kit = @kits[session["demo_kit"]], do: Process.put(DemoWeb.E2E.ChosenKit, kit)
  end

  def mounting(_event, _measurements, _metadata, _config), do: :ok

  @impl Plug
  def init(opts), do: opts

  # the kit the browser asks for, kept in the session for the LiveViews of
  # the page, and noted for the disconnected render, which runs in the request
  @impl Plug
  def call(conn, _opts) do
    case Plug.Conn.get_req_header(conn, "x-demo-kit") do
      [name] when is_map_key(@kits, name) ->
        Process.put(DemoWeb.E2E.ChosenKit, @kits[name])
        Plug.Conn.put_session(conn, "demo_kit", name)

      _none ->
        Plug.Conn.delete_session(conn, "demo_kit")
    end
  end
end
