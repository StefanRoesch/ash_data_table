defmodule AshDataTable.Test do
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

      AshDataTable.Test.flush(view)
      assert render(view) =~ "Renamed"

  A row whose record is gone, or no longer the person's to read, is not
  taken out of the page until the table's hook has said that no cell of it
  is being edited. A LiveView test has no hook: the test answers for it,
  with the `row` of the event the table pushed.

      assert_push_event(view, "ash_data_table:leaving", %{table: "task", row: row})
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
    for listener <- AshDataTable.Listener.of(view), do: AshDataTable.Listener.flush(listener)

    # the LiveView takes its messages in the order they came: once it has
    # answered this, it has taken in what the listeners sent before
    _ = :sys.get_state(view)
    :ok
  end

  @doc """
  How many tables listen now to the changes of `resource` for `tenant`
  (nil for a resource without multitenancy), on every page: once each has
  taken in what it was told before. A table that was closed, or whose page
  is gone, is not counted. 0 for a resource whose domain names no
  `pub_sub`.

      assert AshDataTable.Test.listening(MyApp.Tracker.Task, organization.id) == 1
  """
  @spec listening(Ash.Resource.t(), term) :: non_neg_integer
  def listening(resource, tenant \\ nil) do
    case AshDataTable.Resource.Listening.pub_sub(resource) do
      {:ok, pub_sub} ->
        listeners =
          for {pid, _value} <-
                Registry.lookup(pub_sub, AshDataTable.Notifier.topic(resource, tenant)),
              listener?(pid),
              do: pid

        # one that was told to stop has that before it, and is gone once
        # this returns
        for listener <- listeners, do: AshDataTable.Listener.flush(listener)
        Enum.count(listeners, &Process.alive?/1)

      {:error, _reason} ->
        0
    end
  end

  defp listener?(pid) do
    case Process.info(pid, :dictionary) do
      {:dictionary, dictionary} -> List.keymember?(dictionary, AshDataTable.Listener, 0)
      nil -> false
    end
  end
end
