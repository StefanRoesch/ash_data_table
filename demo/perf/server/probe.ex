defmodule Demo.Perf.Probe do
  @moduledoc """
  What the performance scripts ask the server about itself: how long the
  table's callbacks, Ash's actions and the database's queries took, and how
  much memory the processes of the open tables hold.

  It listens to telemetry events that Phoenix, Ash and Ecto emit anyway and
  adds none of its own. It exists in the perf environment only
  (`perf/server`), and nothing is recorded until `start/0` is called.
  """

  @events [
    [:phoenix, :live_view, :handle_params, :stop],
    [:phoenix, :live_view, :handle_event, :stop],
    [:phoenix, :live_view, :render, :stop],
    [:phoenix, :live_component, :handle_event, :stop],
    [:phoenix, :live_component, :update, :stop],
    # an update that Ash runs atomically is the span `:action`
    [:ash, :tracker, :read, :stop],
    [:ash, :tracker, :update, :stop],
    [:ash, :tracker, :action, :stop],
    [:ash, :perf, :read, :stop],
    [:ash, :perf, :update, :stop],
    [:ash, :perf, :action, :stop],
    [:ash, :kitchen_sink, :read, :stop],
    [:ash, :kitchen_sink, :update, :stop],
    [:ash, :kitchen_sink, :action, :stop],
    [:demo, :repo, :query]
  ]

  @doc "Starts recording, forgetting what was recorded before."
  def start do
    stop()
    {:ok, _pid} = Agent.start(fn -> [] end, name: __MODULE__)
    :ok = :telemetry.attach_many(__MODULE__, @events, &__MODULE__.handle/4, nil)
  end

  def stop do
    :telemetry.detach(__MODULE__)
    if pid = Process.whereis(__MODULE__), do: Agent.stop(pid)
    :ok
  end

  @doc "What was recorded since the last call, oldest first, and forgets it."
  def drain do
    Agent.get_and_update(__MODULE__, &{Enum.reverse(&1), []})
  end

  @doc false
  def handle(event, measurements, metadata, _config) do
    entry =
      event
      |> entry(measurements, metadata)
      |> Map.merge(%{at: System.monotonic_time(:microsecond), pid: inspect(self())})

    Agent.cast(__MODULE__, &[entry | &1])
  end

  # A span's stop: `at` is when it ended, `us` how long it took.
  defp entry([:demo, :repo, :query], measurements, metadata) do
    %{
      name: "query",
      us: us(measurements[:total_time]),
      query_us: us(measurements[:query_time]),
      queue_us: us(measurements[:queue_time]),
      decode_us: us(measurements[:decode_time]),
      sql: metadata.query |> to_string() |> String.slice(0, 2000)
    }
  end

  defp entry([:ash, _domain, type, :stop], measurements, metadata) do
    %{name: "ash.#{type}", us: us(measurements.duration), action: to_string(metadata[:action])}
  end

  defp entry([:phoenix, kind, callback, :stop], measurements, metadata) do
    %{name: "#{kind}.#{callback}", us: us(measurements.duration), event: metadata[:event]}
  end

  defp us(nil), do: 0
  defp us(native), do: System.convert_time_unit(native, :native, :microsecond)

  @doc """
  The LiveView processes that are alive, with what each one holds, measured
  after a garbage collection of that process: `memory` is
  `:erlang.process_info(pid, :memory)`, the process's own heap, stack and
  mailbox, which is the heap block the collection left: a step of the
  VM's sequence of heap sizes, often twice what is in use; `live` is the
  part of the heap in use after the collection (the data the process
  holds, in bytes); `binaries` is the size of the binaries outside its heap
  that it refers to, which other processes may refer to as well.
  """
  def live_views do
    for %{pid: pid} <- Phoenix.LiveView.Debug.list_liveviews(), view = view(pid) do
      before = memory(pid)
      :erlang.garbage_collect(pid)

      %{
        pid: inspect(pid),
        view: inspect(view.module),
        url: view.url,
        memory_before_gc: before,
        memory: memory(pid),
        live: live(pid),
        binaries: binaries(pid),
        message_queue_len: info(pid, :message_queue_len)
      }
    end
  end

  @doc "What the whole VM holds, from `:erlang.memory/0`."
  def vm, do: Map.new(:erlang.memory())

  # A LiveView and its socket, as `Phoenix.LiveView.Debug` gives them; nil
  # for one that ended meanwhile.
  defp view(pid) do
    case Phoenix.LiveView.Debug.socket(pid) do
      {:ok, socket} -> %{module: socket.view, url: socket.assigns[:url]}
      {:error, _reason} -> nil
    end
  end

  defp memory(pid), do: info(pid, :memory)

  # the words of the young and the old heap in use, after the collection
  defp live(pid) do
    case info(pid, :garbage_collection_info) do
      gc when is_list(gc) ->
        (gc[:heap_size] + gc[:old_heap_size]) * :erlang.system_info(:wordsize)

      _gone ->
        nil
    end
  end

  defp binaries(pid) do
    case info(pid, :binary) do
      binaries when is_list(binaries) -> binaries |> Enum.map(&elem(&1, 1)) |> Enum.sum()
      _gone -> 0
    end
  end

  defp info(pid, item) do
    case Process.info(pid, item) do
      {^item, value} -> value
      nil -> nil
    end
  end
end
