defmodule AshTable.Test do
  @moduledoc """
  Help for the tests of an application whose tables follow live updates
  (`live? true`: see the guide "Live updates").

  A table hears of a change through a process of its own, which gathers
  what is announced for 100 ms before it hands it to the table.
  `Phoenix.LiveViewTest.render_async/2` does not wait for that. A test
  that changes a record and then looks at a page calls `flush/1` in
  between, in place of sleeping:

      {:ok, view, _html} = live(conn, "/tasks")

      Ash.update!(task, %{title: "Renamed"}, actor: another)

      AshTable.Test.flush(view)
      assert render(view) =~ "Renamed"

  A row whose record is gone, or no longer the person's to read, is not
  taken out of the page until the table's hook has said that no cell of it
  is being edited. A LiveView test has no hook: the test answers for it,
  with the `row` of the event the table pushed.

      assert_push_event(view, "ash_table:leaving", %{table: "task", row: row})
      view |> element("#task-grid") |> render_hook("left", %{"row" => row})
  """

  @doc """
  Hands every table of a LiveView what was announced to it so far, and
  returns when the LiveView has taken it in. `view` is the view of
  `Phoenix.LiveViewTest.live/2`, or the LiveView's process.

  A change made before this is called is announced by then: Ash announces
  it in the process that ran the action, before the action returns. A read
  the table starts for what it heard runs beside the LiveView, as every
  later read of a table does: `Phoenix.LiveViewTest.render_async/2` waits
  for it.
  """
  @spec flush(pid | %{pid: pid}) :: :ok
  def flush(%{pid: pid}), do: flush(pid)

  def flush(view) when is_pid(view) do
    for listener <- AshTable.Listener.of(view), do: AshTable.Listener.flush(listener)

    # the LiveView takes its messages in the order they came: once it has
    # answered this, it has taken in what the listeners sent before
    _ = :sys.get_state(view)
    :ok
  end
end
