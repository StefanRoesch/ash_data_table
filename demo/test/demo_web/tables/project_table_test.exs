defmodule DemoWeb.Tables.ProjectTableTest do
  @moduledoc """
  The mounted table of `Demo.Tracker.Project` at `/projects`: a resource that
  lists the extension and has no `table` block.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator

  setup do
    world = world(tasks: 0, projects: 0)

    for name <- ["Website", "Billing", "Mobile app"] do
      Generator.generate(Generator.project(organization_id: world.organization.id, name: name))
    end

    %{world: world}
  end

  test "shows the public attributes in the resource's order, the id among them",
       %{conn: conn, world: world} do
    {:ok, _view, html} = conn |> log_in(world.admin) |> live("/projects")

    assert headers(html, "project") == [
             "ID",
             "Name",
             "Description",
             "Status",
             "Starts on",
             "Budget",
             "Inserted at"
           ]
  end

  test "shows no private attribute, aggregate or foreign key", %{conn: conn, world: world} do
    {:ok, _view, html} = conn |> log_in(world.admin) |> live("/projects")

    for field <- ["updated_at", "organization_id", "task_count", "open_task_count"] do
      assert attribute(html, "#project-head-#{field}", "id") == []
    end
  end

  test "shows the projects in the read action's order, by name", %{conn: conn, world: world} do
    {:ok, _view, html} = conn |> log_in(world.admin) |> live("/projects")

    assert column(html, "project", "name") == ["Billing", "Mobile app", "Website"]
    assert text(html, "#project-range") == "1–3 of 3"
  end

  test "names each row after its record's id", %{conn: conn, world: world} do
    ids = Demo.Tracker.Project |> Ash.read!(as(world.admin)) |> Enum.map(& &1.id)

    {:ok, _view, html} = conn |> log_in(world.admin) |> live("/projects")

    assert attribute(html, "#project-table tbody", "id") == Enum.map(ids, &"project-row-#{&1}")
    assert column(html, "project", "id") == ids
  end

  test "tells nobody, whose read the resource refuses, that it is not allowed",
       %{conn: conn, world: world} do
    {:ok, _view, html} = conn |> log_in(world.nobody) |> live("/projects")

    assert text(html, "#project-error") == "You are not allowed to see these records."
    assert column(html, "project", "name") == []
    assert text(html, "#project-empty") == nil
  end
end
