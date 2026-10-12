defmodule DemoWeb.E2E.DataController do
  @moduledoc """
  What the browser tests need to do to the data without a table: start from
  the standard seed again, delete a task behind an open table's back, and
  make the reads of one table fail.

  It is compiled and routed in the e2e environment only (`e2e/server`, and
  `config :demo, e2e_routes: true`), whose databases are the tests' own.
  """
  use DemoWeb, :controller

  # what the table of the comments is called while their reads are to fail
  @away "comments_out_of_reach"

  @doc "Empties the database and fills it with the standard seed."
  def seed(conn, _params) do
    mend_comments()
    json(conn, Map.take(run_seed(), [:profile, :tasks, :comments, :milliseconds]))
  end

  @doc """
  Takes the comments out of the database's reach, so that every read of them
  fails as it would with a database that is down. `mend_comments/2` and
  `seed/2` put them back.
  """
  def break_comments(conn, _params) do
    Demo.Repo.query!("ALTER TABLE IF EXISTS comments RENAME TO #{@away}")
    json(conn, %{comments: "broken"})
  end

  def mend_comments(conn, _params) do
    mend_comments()
    json(conn, %{comments: "mended"})
  end

  defp mend_comments do
    Demo.Repo.query!("ALTER TABLE IF EXISTS #{@away} RENAME TO comments")
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
