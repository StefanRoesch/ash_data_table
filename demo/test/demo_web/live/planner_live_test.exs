defmodule DemoWeb.PlannerLiveTest do
  @moduledoc """
  The sprint planner (`DemoWeb.PlannerLive`): the card of the selection,
  read back as the person; the feed of the last changes; "Clear selection".
  """
  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator

  setup do
    world = world(tasks: 0)

    %{
      world: world,
      a: task(world, "Fix login", estimate_hours: Decimal.new("3"), billable?: true),
      b: task(world, "Rename the onboarding email", estimate_hours: Decimal.new("4.5")),
      c: task(world, "Plan the retro", estimate_hours: nil, assignee_id: world.member.id)
    }
  end

  defp task(world, title, overrides) do
    [project | _] = world.projects

    Generator.generate(
      Generator.task(
        [
          organization_id: world.organization.id,
          project_id: project.id,
          reporter_id: world.admin.id,
          assignee_id: nil,
          title: title,
          status: :in_progress,
          billable?: false
        ] ++ overrides
      )
    )
  end

  defp planner(conn, actor), do: conn |> log_in(actor) |> live("/tasks/planner")

  # what the card says, once the page has heard what the table told it
  defp card(view) do
    html = render(view)
    {text(html, "#planner-count"), text(html, "#planner-hours"), text(html, "#planner-billable")}
  end

  defp summary(view), do: text(render(view), "#planner-sprint-summary")

  defp feed(view) do
    render(view)
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#planner-feed li")
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
  end

  test "the card counts the selected tasks, their hours and the billable ones",
       %{conn: conn, world: world, a: a, b: b, c: c} do
    {:ok, view, _html} = planner(conn, world.admin)
    assert summary(view) =~ "No tasks selected"
    # the table's name is a heading of the page, and names its section
    assert has_element?(view, "#planner-tasks[aria-labelledby=task-name] h2#task-name", "Tasks")

    select(view, [a.id, b.id, c.id])
    assert card(view) == {"3", "7.5 h", "1"}
  end

  test "a save of a selected row says so, and the card follows it",
       %{conn: conn, world: world, a: a, b: b} do
    {:ok, view, _html} = planner(conn, world.admin)
    select(view, [a.id, b.id])

    save(view, a.id, "estimate_hours", "10")
    render_async(view)

    assert feed(view) == ["Estimate hours of “Fix login” saved"]
    assert card(view) == {"2", "14.5 h", "1"}
  end

  test "a deleted row says so, and leaves the card", %{conn: conn, world: world, a: a, b: b} do
    {:ok, view, _html} = planner(conn, world.admin)
    select(view, [a.id, b.id])

    act(view, a.id, "destroy")
    render_async(view)

    assert feed(view) == ["1 task deleted"]
    assert card(view) == {"1", "4.5 h", "0"}
  end

  test "Clear selection empties the selection and the card", %{conn: conn, world: world, a: a} do
    {:ok, view, _html} = planner(conn, world.admin)
    select(view, [a.id])
    assert card(view) == {"1", "3 h", "1"}

    view |> element("#planner-clear") |> render_click()
    assert_push_event view, "ash_data_table:select", %{table: "task", all: false, rows: []}
    assert summary(view) =~ "No tasks selected"
    assert has_element?(view, "#planner-clear[disabled]")
  end

  test "an estimate the person may not see counts as unknown",
       %{conn: conn, world: world, a: a, b: b, c: c} do
    # the member sees the estimate of their own task only
    {:ok, view, _html} = planner(conn, world.member)

    select(view, [a.id, b.id, c.id])
    assert card(view) == {"3", "0 h + 2 unknown", "1"}
  end

  test "nobody has no rows, and a selection named by the browser reads nothing",
       %{conn: conn, world: world, a: a} do
    {:ok, view, _html} = planner(conn, world.nobody)

    select(view, [a.id])
    assert summary(view) =~ "No tasks selected"
  end

  test "in German", %{conn: conn, world: world, a: a, b: b} do
    {:ok, view, html} = conn |> log_in(world.admin) |> in_locale("de") |> live("/tasks/planner")
    assert text(html, "h1") == "Sprintplanung"

    select(view, [a.id, b.id])
    save(view, b.id, "progress", "50")
    render_async(view)

    assert feed(view) == ["Fortschritt von „Rename the onboarding email“ gespeichert"]
    assert card(view) == {"2", "7.5 Std.", "1"}
  end
end
