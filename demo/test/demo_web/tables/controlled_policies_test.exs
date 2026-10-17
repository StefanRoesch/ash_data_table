defmodule DemoWeb.Tables.ControlledPoliciesTest do
  @moduledoc """
  Controlled mode against a resource with policies: the
  demo's tasks, whose people of another organization are not the actor's
  to read, and whose viewer edits nothing. What the host answers is a
  claim, checked as the person's own: a key of a person the actor may not
  read chooses nothing, and a save the browser forges for a column the
  actor may not edit is held for nothing. `DemoWeb.Support.ControlledTasksLive`.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Demo.Tracker.Task

  setup %{conn: conn} = context do
    world = world(tasks: 1, other_tasks: 0)
    actor = Map.fetch!(world, Map.get(context, :actor, :admin))

    session = %{
      "actor" => actor.id,
      "test" => self(),
      "controlled" => Map.get(context, :controlled, [:picker, :panel])
    }

    {:ok, view, _html} =
      live_isolated(conn, DemoWeb.Support.ControlledTasksLive, session: session)

    %{view: view, world: world, task: hd(world.tasks)}
  end

  defp run(view, fun) do
    send(view.pid, {:run, fun})
    assert_receive {:ran, told}
    told
  end

  defp requests(view), do: run(view, &{&1, AshDataTable.requests(&1.assigns.tasks)})

  defp answer(view, fun), do: run(view, &{fun.(&1), nil})

  defp assignee(task), do: Ash.get!(Task, task.id, authorize?: false).assignee_id

  test "a forged pick of a person the actor may not read chooses nothing",
       %{view: view, world: world, task: task} do
    before = assignee(task)

    AshDataTable.Test.send_event(view, "task", "pick", %{"row" => task.id, "column" => "assignee"})

    assert_receive {:heard, {:ash_data_table, "task", {:requested, %{ref: ref, kind: :picker}}}}

    # a real person, of another organization
    answer(view, &AshDataTable.pick_request(&1, :tasks, ref, %{id: world.outsider.id}))
    assert assignee(task) == before
    assert [%{ref: ^ref, errors: [_why]}] = requests(view)

    # one of the actor's own organization, whom the task is not assigned to
    other = Enum.find([world.member, world.admin, world.viewer], &(&1.id != before))
    answer(view, &AshDataTable.pick_request(&1, :tasks, ref, %{id: other.id}))
    assert assignee(task) == other.id
    assert requests(view) == []
  end

  @tag actor: :viewer, controlled: [:confirm]
  test "a save forged for a column the actor may not edit is held for nothing",
       %{view: view, task: task} do
    AshDataTable.Test.send_event(view, "task", "save", %{
      "row" => task.id,
      "column" => "status",
      "value" => "done"
    })

    assert_reply view, %{ok: false}
    refute_received {:heard, {:ash_data_table, "task", {:requested, _details}}}
    assert requests(view) == []
  end
end
