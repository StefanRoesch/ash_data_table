defmodule AshDataTable.Test.LiveHost do
  @moduledoc """
  A LiveView of the tests' own, for code that works on the socket of a
  LiveView: `run/1` mounts one (`Phoenix.LiveViewTest.live_isolated/3`)
  and runs a function on its socket, in its process. What the function
  raises, a failed assertion too, is raised in the test.

      AshDataTable.Test.LiveHost.run(fn socket -> Registry.take_stream(socket) end)

  Its endpoint is started once, by `test_helper.exs` (`start/0`).
  `AshDataTable.KitCase` runs on it for `AshDataTable.Kit.Default`
  (`test/kit/default_kit_test.exs`).
  """

  defmodule Endpoint do
    @moduledoc false
    use Phoenix.Endpoint, otp_app: :ash_data_table
  end

  defmodule View do
    @moduledoc false
    use Phoenix.LiveView

    @impl true
    def mount(_params, _session, socket), do: {:ok, socket}

    @impl true
    def handle_info({:run, fun, from}, socket) do
      result =
        try do
          {:ok, fun.(socket)}
        rescue
          error -> {:raised, error, __STACKTRACE__}
        end

      send(from, {:ran, result})
      {:noreply, socket}
    end

    @impl true
    def render(assigns), do: ~H""
  end

  import Phoenix.LiveViewTest, only: [live_isolated: 2]

  @endpoint Endpoint

  @doc "Starts the endpoint of the LiveView."
  def start do
    Application.put_env(:ash_data_table, Endpoint,
      secret_key_base: String.duplicate("a", 64),
      live_view: [signing_salt: "ash_data_table_live_host"]
    )

    {:ok, _pid} = Endpoint.start_link()
    :ok
  end

  @doc "Runs `fun` on the socket of a LiveView that is mounted for it, in its process."
  def run(fun) when is_function(fun, 1) do
    {:ok, view, _html} =
      live_isolated(Phoenix.ConnTest.build_conn(), View)

    send(view.pid, {:run, fun, self()})

    receive do
      {:ran, {:ok, value}} -> value
      {:ran, {:raised, error, stacktrace}} -> reraise error, stacktrace
    after
      5_000 -> raise "the LiveView did not answer"
    end
  end
end
