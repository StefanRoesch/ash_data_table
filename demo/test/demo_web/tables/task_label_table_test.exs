defmodule DemoWeb.Tables.TaskLabelTableTest do
  @moduledoc """
  The mounted table of `Demo.Tracker.TaskLabel` at `/task_labels`: a resource
  whose primary key is two attributes. A row is named, found again and saved
  by both parts of its key together.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator
  alias Demo.Tracker.TaskLabel

  # One task with `count` labels, the notes "Note 01", "Note 02", … given in
  # the order of the labels' ids, which is the order the table reads in.
  defp labelled(count) do
    world = world(tasks: 1, labels: count)
    [task] = world.tasks
    labels = Enum.sort_by(world.labels, & &1.id)

    Demo.Repo.delete_all(TaskLabel)

    for {label, index} <- Enum.with_index(labels, 1) do
      Generator.generate(
        Generator.task_label(
          organization_id: world.organization.id,
          task_id: task.id,
          label_id: label.id,
          note: "Note #{String.pad_leading("#{index}", 2, "0")}"
        )
      )
    end

    %{world: world, task: task, labels: labels}
  end

  defp key(task, label), do: "#{task.id}-#{label.id}"

  defp stored(task, label),
    do: Ash.get!(TaskLabel, %{task_id: task.id, label_id: label.id}, authorize?: false)

  test "names each row after both parts of its key", %{conn: conn} do
    %{world: world, task: task, labels: [first, second]} = labelled(2)

    {:ok, _view, html} = conn |> log_in(world.admin) |> live("/task_labels")

    assert headers(html, "task_label") == ["Note", "Task ID", "Label ID"]

    assert attribute(html, "#task_label-table tbody", "id") == [
             "task_label-row-#{task.id}-#{first.id}",
             "task_label-row-#{task.id}-#{second.id}"
           ]

    assert attribute(html, "#task_label-table td[id$='-c-label_id']", "id") == [
             "task_label-row-#{task.id}-#{first.id}-c-label_id",
             "task_label-row-#{task.id}-#{second.id}-c-label_id"
           ]
  end

  test "sorts and filters", %{conn: conn} do
    %{world: world} = labelled(12)
    {:ok, view, html} = conn |> log_in(world.admin) |> live("/task_labels")

    assert hd(column(html, "task_label", "note")) == "Note 01"

    view |> element("#task_label-head-note") |> render_click()
    view |> element("#task_label-head-note") |> render_click()
    assert_patch(view, "/task_labels?task_label[sort]=-note")

    assert Enum.take(column(render_async(view), "task_label", "note"), 2) == [
             "Note 12",
             "Note 11"
           ]

    html = filter(view, "task_label", "note", v: "Note 1")
    assert column(html, "task_label", "note") == ["Note 12", "Note 11", "Note 10"]
    assert text(html, "#task_label-range") == "1–3 of 3"
  end

  test "pages", %{conn: conn} do
    %{world: world, task: task, labels: labels} = labelled(27)
    {:ok, view, html} = conn |> log_in(world.admin) |> live("/task_labels")

    assert text(html, "#task_label-range") == "1–25 of 27"

    view |> element("#task_label-next") |> render_click()
    assert_patch(view, "/task_labels?task_label[page]=2")
    html = render_async(view)

    assert column(html, "task_label", "note") == ["Note 26", "Note 27"]

    assert attribute(html, "#task_label-table tbody", "id") ==
             labels |> Enum.drop(25) |> Enum.map(&"task_label-row-#{key(task, &1)}")
  end

  test "saves a cell of the row with that key, and of no other", %{conn: conn} do
    %{world: world, task: task, labels: [first, second, third]} = labelled(3)
    {:ok, view, html} = conn |> log_in(world.admin) |> live("/task_labels")

    assert editors(html, "task_label") == ["note"]

    html = save(view, "task_label", key(task, second), "note", "Because it is urgent")

    assert column(html, "task_label", "note") == ["Note 01", "Because it is urgent", "Note 03"]
    assert stored(task, first).note == "Note 01"
    assert stored(task, second).note == "Because it is urgent"
    assert stored(task, third).note == "Note 03"

    # emptied: nil is saved
    html = save(view, "task_label", key(task, third), "note", "")
    assert text(html, cell("task_label", key(task, third), "note")) == ""
    assert stored(task, third).note == nil
  end

  test "does not save through a key that is not a row of the page", %{conn: conn} do
    %{world: world, task: task, labels: [first, second]} = labelled(2)
    {:ok, view, _html} = conn |> log_in(world.admin) |> live("/task_labels")

    # the two parts the other way round, and one part alone
    for key <- ["#{first.id}-#{task.id}", "#{task.id}", "#{task.id}-#{task.id}"] do
      html = save(view, "task_label", key, "note", "Smuggled")
      assert column(html, "task_label", "note") == ["Note 01", "Note 02"]
    end

    assert stored(task, first).note == "Note 01"
    assert stored(task, second).note == "Note 02"
  end

  test "a save the action refuses is shown on the cell: a viewer may not change a row",
       %{conn: conn} do
    %{world: world, task: task, labels: [first]} = labelled(1)
    {:ok, view, html} = conn |> log_in(world.viewer) |> live("/task_labels")

    # a viewer can never run the action, so the table offers them no editing
    assert editors(html, "task_label") == []

    save(view, "task_label", key(task, first), "note", "Smuggled")
    assert stored(task, first).note == "Note 01"
  end
end
