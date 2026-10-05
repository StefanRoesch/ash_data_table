defmodule DemoWeb.Tables.TaskLabelTableTest do
  @moduledoc """
  The mounted table of `Demo.Tracker.TaskLabel` at `/task_labels`: a resource
  whose primary key is two attributes.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator

  test "names each row after both parts of its key", %{conn: conn} do
    world = world(tasks: 1, labels: 2)
    [task] = world.tasks
    [first, second] = Enum.sort_by(world.labels, & &1.id)

    Demo.Repo.delete_all(Demo.Tracker.TaskLabel)

    for label <- [first, second] do
      Generator.generate(
        Generator.task_label(
          organization_id: world.organization.id,
          task_id: task.id,
          label_id: label.id
        )
      )
    end

    {:ok, _view, html} = conn |> log_in(world.admin) |> live("/task_labels")

    assert headers(html, "task_label") == ["Task ID", "Label ID"]

    assert Enum.sort(attribute(html, "#task_label-table tbody", "id")) == [
             "task_label-row-#{task.id}-#{first.id}",
             "task_label-row-#{task.id}-#{second.id}"
           ]

    assert Enum.sort(attribute(html, "#task_label-table td[id$='-c-label_id']", "id")) == [
             "task_label-row-#{task.id}-#{first.id}-c-label_id",
             "task_label-row-#{task.id}-#{second.id}-c-label_id"
           ]
  end
end
