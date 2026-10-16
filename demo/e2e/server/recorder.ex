defmodule DemoWeb.E2E.Recorder do
  @moduledoc """
  What a browser test's page asked of its LiveView: every event it pushed,
  as the server heard it, in order. The browser tests read it to tell what
  was sent and that nothing was (`e2e/support/fixtures.ts`, `Sent`).

  It hears LiveView's own telemetry, which LiveView documents
  (`Phoenix.LiveView.Logger`): `[:phoenix, :live_view, :handle_event,
  :start]` and `[:phoenix, :live_component, :handle_event, :start]`, each
  with the event's name and its params, in the process of the LiveView
  that handles it. Which test a LiveView is of, its session says: a test
  gives its page's session `"e2e_recorder"` (`DemoWeb.E2E.RecorderController`),
  and the LiveView keeps it from its connected `mount` on
  (`[:phoenix, :live_view, :mount, :start]`). Another browser of the same
  test, with a session of its own, is not heard.

  A table's event is kept by its own name and its table's id
  (`ash_data_table:task:save` is `save` of `task`). The events of the table
  `e2e-barrier` are the tests' own (`Sent.flush`), and are not kept.

  Started in the e2e environment only (`config :demo, e2e_children: …`),
  one per server: each worker of the browser tests has a server of its own.
  """
  use GenServer

  @table :demo_e2e_recorded
  @key {__MODULE__, :test}
  @barrier "e2e-barrier"

  @doc false
  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "What the LiveViews of the test `test` heard, in order: `%{event, table, params}` each."
  def heard(test) do
    for {{^test, _order}, entry} <- :ets.match_object(@table, {{test, :_}, :_}), do: entry
  end

  @doc "Forgets what the LiveViews of the test `test` heard so far."
  def forget(test) do
    :ets.match_delete(@table, {{test, :_}, :_})
    :ok
  end

  @impl true
  def init(nil) do
    :ets.new(@table, [:ordered_set, :public, :named_table, write_concurrency: true])

    :telemetry.attach_many(
      __MODULE__,
      [
        [:phoenix, :live_view, :mount, :start],
        [:phoenix, :live_view, :handle_event, :start],
        [:phoenix, :live_component, :handle_event, :start]
      ],
      &__MODULE__.handle/4,
      nil
    )

    {:ok, nil}
  end

  @impl true
  def terminate(_reason, _state), do: :telemetry.detach(__MODULE__)

  @doc false
  def handle([:phoenix, :live_view, :mount, :start], _measurements, metadata, _config) do
    with %{socket: socket, session: %{"e2e_recorder" => test}} <- metadata,
         true <- Phoenix.LiveView.connected?(socket),
         do: Process.put(@key, test)
  end

  def handle([:phoenix, _kind, :handle_event, :start], _measurements, metadata, _config) do
    with test when is_binary(test) <- Process.get(@key),
         {table, event} when table != @barrier <- named(metadata.event) do
      entry = %{event: event, table: table, params: metadata.params}
      :ets.insert(@table, {{test, System.unique_integer([:monotonic])}, entry})
    end
  end

  # `ash_data_table:ID:event`: the table's id and the event's own name; an
  # event of the page's own has no table
  defp named(event) do
    case String.split(event, ":") do
      ["ash_data_table" | [_, _ | _] = rest] ->
        {ids, [plain]} = Enum.split(rest, -1)
        {Enum.join(ids, ":"), plain}

      _page_own ->
        {nil, event}
    end
  end
end
