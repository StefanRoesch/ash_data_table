defmodule DemoWeb.E2E.DataController do
  @moduledoc """
  What the browser tests need to do to the data without a table: start from
  the standard seed again, and delete a task behind an open table's back.

  It is compiled and routed in the e2e environment only (`e2e/server`, and
  `config :demo, e2e_routes: true`), whose database is `demo_e2e`.
  """
  use DemoWeb, :controller

  @doc "Empties the database and fills it with the standard seed."
  def seed(conn, _params) do
    json(conn, Map.take(run_seed(), [:profile, :tasks, :comments, :milliseconds]))
  end

  @doc "Deletes a task straight in the data layer, as another person's destroy would."
  def delete_task(conn, %{"id" => id}) do
    {:ok, uuid} = Ecto.UUID.dump(id)
    %{num_rows: deleted} = Demo.Repo.query!("DELETE FROM tasks WHERE id = $1", [uuid])
    json(conn, %{deleted: deleted})
  end

  # In a process of its own, as `mix run priv/repo/seeds.exs` has one:
  # `Ash.Generator` keeps its sequences in the process that generates, and
  # looks for them in that process's ancestors, which it cannot do from a
  # request process (it takes the endpoint's registered name for a pid).
  defp run_seed do
    {pid, ref} = spawn_monitor(fn -> exit({:seeded, Demo.Seeds.run(:standard)}) end)

    receive do
      {:DOWN, ^ref, :process, ^pid, {:seeded, summary}} -> summary
      {:DOWN, ^ref, :process, ^pid, reason} -> raise "seeding failed: #{inspect(reason)}"
    end
  end
end
