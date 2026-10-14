defmodule AshDataTable.Test.Ets do
  @moduledoc """
  Stops the ETS tables of resources, and waits until they are gone.

  `Ash.DataLayer.Ets.stop/1` tells the process that owns a table to stop and
  does not wait for it. A test that starts right after it can still find the
  table, which is gone by the time it writes ("the table identifier does
  not refer to an existing ETS table").
  """

  @doc "Stops the table of each resource, and returns when the tables are gone."
  @spec stop(Ash.Resource.t() | [Ash.Resource.t()]) :: :ok
  def stop(resources) do
    for resource <- List.wrap(resources) do
      table = Ash.DataLayer.Ets.Info.table(resource)

      # the process the table goes with
      owner = if :ets.whereis(table) != :undefined, do: :ets.info(table, :owner)
      reference = if is_pid(owner), do: Process.monitor(owner)

      Ash.DataLayer.Ets.stop(resource)

      if reference do
        receive do
          {:DOWN, ^reference, :process, _pid, _reason} -> :ok
        after
          1_000 -> :ok
        end

        gone(table, 100)
      end
    end

    :ok
  end

  defp gone(_table, 0), do: :ok

  defp gone(table, tries) do
    if :ets.whereis(table) != :undefined do
      Process.sleep(1)
      gone(table, tries - 1)
    end
  end
end
