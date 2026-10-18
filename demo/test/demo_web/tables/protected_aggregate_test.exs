defmodule DemoWeb.Tables.ProtectedAggregateTest do
  @moduledoc """
  An aggregate column over a field that a field policy protects on the
  related resource, protected by a field policy of its own: the "Assigned
  hours" of a person add up the estimates of their tasks, which an admin
  sees, and so only an admin sees the sum.

  People have no page of their own in the demo: their table is seen under
  the row of a task, on the line of its assignee.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator

  setup %{conn: conn} do
    world = world(tasks: 0, other_tasks: 0)
    [project | _] = world.projects

    [task | _] =
      for hours <- ["3", "4.5"] do
        Generator.generate(
          Generator.task(
            organization_id: world.organization.id,
            project_id: project.id,
            reporter_id: world.admin.id,
            assignee_id: world.member.id,
            estimate_hours: Decimal.new(hours)
          )
        )
      end

    %{world: world, task: task, conn: conn}
  end

  defp assignee(conn, actor, task) do
    {:ok, view, _html} = conn |> log_in(actor) |> live("/tasks")
    expand(view, task.id)
    {toggle(view, task.id, "assignee"), nested(task.id, "assignee")}
  end

  test "is shown to a person its own field policy lets see it", %{
    conn: conn,
    world: world,
    task: task
  } do
    {html, id} = assignee(conn, world.admin, task)

    assert headers(html, id) == ["Name", "Email", "Role", "Assigned hours"]
    assert column(html, id, "assigned_hours") == ["7.5"]
  end

  test "has no column for anybody else, who sees the estimates of their own tasks at most", %{
    conn: conn,
    world: world,
    task: task
  } do
    {html, id} = assignee(conn, world.member, task)

    assert headers(html, id) == ["Name", "Email", "Role"]
    assert column(html, id, "name") == [world.member.name]
    # anywhere in the page but the drawing of an icon, whose path has numbers
    refute Regex.replace(~r{<svg.*?</svg>}s, html, "") =~ "7.5"
  end
end
