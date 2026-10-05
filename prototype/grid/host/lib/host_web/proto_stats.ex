defmodule HostWeb.ProtoStats do
  @moduledoc """
  THROWAWAY PROTOTYPE (#11). Records, per LiveView process, how long the last
  event took on the server, and serves that plus the process memory as JSON.
  Kept out of the LiveView's own diffs so it does not distort the diff sizes.
  """
  use HostWeb, :controller

  @table :proto_stats

  def attach do
    :ets.new(@table, [:named_table, :public, :set])

    :telemetry.attach_many(
      "proto-stats",
      [
        [:phoenix, :live_view, :handle_event, :stop],
        [:phoenix, :live_component, :handle_event, :stop],
        [:phoenix, :live_view, :handle_params, :stop],
        [:phoenix, :live_view, :render, :stop],
        [:ash_table_proto, :refetch],
        [:ash_table_proto, :save]
      ],
      &__MODULE__.handle/4,
      nil
    )
  end

  # Runs in the LiveView process.
  def handle([:ash_table_proto, kind], %{us: us}, _meta, _) do
    put(%{:"#{kind}_us" => us})
  end

  def handle([:phoenix, _, :render, :stop], %{duration: duration}, _meta, _) do
    put(%{render_us: us(duration)})
  end

  def handle([:phoenix, _, kind, :stop], %{duration: duration}, meta, _) do
    put(%{event: meta[:event] || to_string(kind), handle_us: us(duration)})
  end

  defp us(native), do: System.convert_time_unit(native, :native, :microsecond)

  defp put(map) do
    old =
      case :ets.lookup(@table, self()) do
        [{_, old}] -> old
        [] -> %{}
      end

    :ets.insert(@table, {self(), Map.merge(old, map)})
  end

  def pid_param(pid), do: pid |> :erlang.pid_to_list() |> to_string()

  defp pid!(%{"pid" => pid}), do: pid |> String.to_charlist() |> :erlang.list_to_pid()

  # GET /prototype/grid/stats?pid=<0.1.0>[&gc=1]
  def stats(conn, params) do
    pid = pid!(params)
    before = memory(pid)
    if params["gc"], do: :erlang.garbage_collect(pid)

    last =
      case :ets.lookup(@table, pid) do
        [{_, last}] -> last
        [] -> %{}
      end

    json(conn, %{
      memory: before.memory,
      total_heap: before.total_heap,
      after_gc: if(params["gc"], do: memory(pid)),
      last: last
    })
  end

  # `memory`: the whole process in bytes as the allocator sees it (heap blocks,
  # stack, mailbox). It moves in large steps because heap blocks do.
  # `live`: words actually in use on the heaps (exact right after a full GC),
  # plus `binary`: the off-heap binaries (strings over 64 bytes) it references.
  defp memory(pid) do
    case :erlang.process_info(pid, [:memory, :total_heap_size, :garbage_collection_info, :binary]) do
      :undefined ->
        %{memory: nil, total_heap: nil, live: nil, binary: nil}

      info ->
        word = :erlang.system_info(:wordsize)
        gc = info[:garbage_collection_info]
        binary = info[:binary] |> Enum.uniq_by(&elem(&1, 0)) |> Enum.map(&elem(&1, 1)) |> Enum.sum()

        %{
          memory: info[:memory],
          total_heap: info[:total_heap_size] * word,
          live: (gc[:heap_size] + gc[:old_heap_size]) * word,
          binary: binary
        }
    end
  end

  # GET /prototype/grid/reset : back to the seed data (measurement runs start equal)
  def reset(conn, _params) do
    Ash.DataLayer.Ets.stop(Host.Work.Task)
    Ash.DataLayer.Ets.stop(Host.Work.Comment)
    Host.Seeds.run()
    json(conn, %{ok: true})
  end

  # GET /prototype/grid/poke?pid=..&index=3&col=assignee&value=x
  # Makes the server change a row without any input from the page.
  def poke(conn, %{"index" => index, "col" => col, "value" => value} = params) do
    send(pid!(params), {:poke, %{"index" => String.to_integer(index), "col" => col, "value" => value}})
    json(conn, %{ok: true})
  end
end
