defmodule DemoWeb.E2E.DataController do
  @moduledoc """
  What the browser tests need to do to the data without a table: delete a
  task behind an open table's back, and make the reads of one table fail.
  Each in the transaction of the test that asks (`DemoWeb.E2E.Sandbox`),
  which ends with the test: none outlives it.

  It is compiled and routed in the e2e environment only (`e2e/server`, and
  `config :demo, e2e_routes: true`), whose databases are the tests' own.
  """
  use DemoWeb, :controller

  # what the table of the comments is called while their reads are to fail
  @away "comments_out_of_reach"

  @doc """
  Takes the comments out of the database's reach, so that every read of them
  fails as it would with a database that is down. `mend_comments/2`, and
  the end of the test's transaction, put them back.
  """
  def break_comments(conn, _params) do
    Demo.Repo.query!("ALTER TABLE IF EXISTS comments RENAME TO #{@away}")
    json(conn, %{comments: "broken"})
  end

  def mend_comments(conn, _params) do
    Demo.Repo.query!("ALTER TABLE IF EXISTS #{@away} RENAME TO comments")
    json(conn, %{comments: "mended"})
  end

  @doc "Deletes a task straight in the data layer, as another person's destroy would."
  def delete_task(conn, %{"id" => id}) do
    {:ok, uuid} = Ecto.UUID.dump(id)
    %{num_rows: deleted} = Demo.Repo.query!("DELETE FROM tasks WHERE id = $1", [uuid])
    json(conn, %{deleted: deleted})
  end
end
