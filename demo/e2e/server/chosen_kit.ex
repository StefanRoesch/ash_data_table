defmodule DemoWeb.E2E.ChosenKit do
  @moduledoc """
  The kit of the browser tests' tables (`config :ash_data_table, kit: …` in
  config/e2e.exs): `AshDataTable.Kit.Default`, or the demo's React kit
  (`DemoWeb.ReactKit`) for a page the browser asked for it, by request (the
  React kit's note, section 7, 3; Q15). The Playwright project `react`
  sends the header `x-demo-kit: react` with every request; the plug
  `DemoWeb.E2E.KitChoice` keeps it in the session, and as a LiveView of that session mounts
  (LiveView's documented telemetry `[:phoenix, :live_view, :mount,
  :start]`, in the LiveView's process, before its `on_mount` hooks, as
  `DemoWeb.E2E.Sandbox` hears it), the kit is noted in its process. Every
  part, `class`, `presentation` and `look` is then that kit's. A table
  placed with a kit of its own keeps it.
  """
  use AshDataTable.Kit, contract: 6

  for part <- AshDataTable.Kit.parts() do
    def unquote(part)(assigns), do: chosen().unquote(part)(assigns)
  end

  def class(part, state), do: chosen().class(part, state)
  def presentation(thing), do: chosen().presentation(thing)
  def look(option), do: chosen().look(option)

  defp chosen, do: Process.get(__MODULE__, AshDataTable.Kit.Default)
end
