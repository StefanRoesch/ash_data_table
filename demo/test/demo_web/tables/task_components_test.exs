defmodule DemoWeb.Tables.TaskComponentsTest do
  @moduledoc """
  The components of the table at `/tasks`: the three that are shipped
  (`AshDataTable.Components.Badge` on "State" and "Priority", and
  `AshDataTable.Components.Progress` with `AshDataTable.Components.Slider`, put
  together in `DemoWeb.Cells.Progress`, on "Progress") and the demo's own
  (`DemoWeb.Cells.Hours` on "Estimate hours").
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator
  alias Demo.Tracker.Task

  defp task(world, overrides) do
    [project | _] = world.projects

    Generator.generate(
      Generator.task(
        [
          organization_id: world.organization.id,
          project_id: project.id,
          reporter_id: world.admin.id,
          title: "Write the report",
          status: :in_progress,
          priority: :high,
          progress: 40,
          estimate_hours: Decimal.new("12.5"),
          inserted_at: ~U[2026-01-01 12:00:00.000000Z]
        ] ++ overrides
      )
    )
  end

  defp stored(task), do: Ash.get!(Task, task.id, authorize?: false)

  # the one element matching `selector`, as a tree
  defp tree(html, selector) do
    [node] = html |> seen() |> LazyHTML.query(selector) |> LazyHTML.to_tree()
    node
  end

  setup %{conn: conn} do
    world = world(tasks: 0)
    %{world: world, conn: log_in(conn, world.admin)}
  end

  describe "the badge" do
    test "shows a choice by its label, in a badge", %{conn: conn, world: world} do
      task = task(world, [])
      {:ok, _view, html} = live(conn, "/tasks")

      assert {"td", _, [{"span", badge, ["In progress"]}]} = tree(html, cell(task.id, "status"))
      assert "badge" in String.split(:proplists.get_value("class", badge))

      assert {"td", _, [{"span", _badge, ["High"]}]} = tree(html, cell(task.id, "priority"))
    end
  end

  describe "the progress bar" do
    test "shows a bounded number as a bar, and as the number beside it", %{
      conn: conn,
      world: world
    } do
      task = task(world, [])
      {:ok, _view, html} = live(conn, "/tasks")

      assert {"td", _, [{"span", _, [{"progress", bar, []}, "40"]}]} =
               tree(html, cell(task.id, "progress"))

      bar = Map.new(bar)
      assert bar["value"] == "40"
      assert bar["max"] == "100"
      # the number is said once, by the text: the bar is for the eye
      assert bar["aria-hidden"] == "true"
    end
  end

  # a column's editor template: its attributes, and the one element in it
  defp template(html, field) do
    {"template", attributes, children} = tree(html, "template[id='task-editor-#{field}']")
    [root] = Enum.reject(children, &is_binary/1)
    {Map.new(attributes), root}
  end

  describe "the slider" do
    test "edits a bounded number with a range between the field's minimum and maximum, and shows the number beside it",
         %{conn: conn, world: world} do
      task(world, [])
      {:ok, _view, html} = live(conn, "/tasks")

      assert {%{"data-editor" => "component", "data-commit" => "change"},
              {"span", _, [{"input", range, []}, {"span", number, _}]}} =
               template(html, "progress")

      range = Map.new(range)
      assert range["type"] == "range"
      assert range["min"] == "0"
      assert range["max"] == "100"
      assert range["step"] == "1"
      assert range["aria-label"] == "Progress"

      # the number a person is choosing, which the table keeps up with the
      # range; a screen reader has it from the range itself
      number = Map.new(number)
      assert is_map_key(number, "data-value-text")
      assert number["aria-hidden"] == "true"
    end

    test "saves through the column's update action", %{conn: conn, world: world} do
      task = task(world, status: :todo)
      {:ok, view, _html} = live(conn, "/tasks")

      html = save(view, task.id, "progress", "65")

      # `set_progress` starts a task that is still to do: the column's own action ran
      assert %{progress: 65, status: :in_progress} = stored(task)

      assert {"td", _, [{"span", _, [{"progress", bar, []}, "65"]}]} =
               tree(html, cell(task.id, "progress"))

      assert {"value", "65"} in bar
    end
  end

  describe "the demo's own component, for hours" do
    test "shows the number with its unit, and nothing where there is no estimate", %{
      conn: conn,
      world: world
    } do
      task = task(world, [])
      open = task(world, title: "Not estimated", estimate_hours: nil)
      {:ok, _view, html} = live(conn, "/tasks")

      assert {"td", _, ["12.5 h"]} = tree(html, cell(task.id, "estimate_hours"))
      assert {"td", _, []} = tree(html, cell(open.id, "estimate_hours"))
      # the editor takes the number, not what the cell shows
      assert attribute(html, cell(task.id, "estimate_hours"), "data-value") == ["12.5"]
    end

    test "edits the number in an input that knows the field's minimum, and saves on Enter or on leaving",
         %{conn: conn, world: world} do
      task = task(world, [])
      {:ok, view, html} = live(conn, "/tasks")

      assert {%{"data-editor" => "component", "data-commit" => "enter"},
              {"span", _, [{"input", input, []}, {"span", _, ["h"]}]}} =
               template(html, "estimate_hours")

      input = Map.new(input)
      assert input["type"] == "number"
      assert input["min"] == "0"
      assert input["step"] == "0.5"
      assert input["aria-label"] == "Estimate hours"

      html = save(view, task.id, "estimate_hours", "8")

      assert Decimal.equal?(stored(task).estimate_hours, 8)
      assert {"td", _, ["8 h"]} = tree(html, cell(task.id, "estimate_hours"))
    end

    test "is not asked to show an estimate that is hidden from the person", %{
      conn: conn,
      world: world
    } do
      # a member sees the estimate of the tasks they are assigned to
      own = task(world, title: "Own", assignee_id: world.member.id)
      other = task(world, title: "Other")
      {:ok, _view, html} = conn |> log_in(world.member) |> live("/tasks")

      assert {"td", _, ["12.5 h"]} = tree(html, cell(own.id, "estimate_hours"))

      assert {"td", _, [{"span", [{"class", "sr-only"}], ["Not available"]}]} =
               tree(html, cell(other.id, "estimate_hours"))
    end
  end

  describe "wherever the table of the tasks is shown" do
    # what the cells of a task's row are made of, and which editors the table has
    defp looks(html, id, task) do
      %{
        status: tree(html, cell(id, task.id, "status")),
        progress: tree(html, cell(id, task.id, "progress")),
        estimate: text(html, cell(id, task.id, "estimate_hours")),
        slider: editor(html, id, "progress")
      }
    end

    defp assert_components(looks) do
      assert {"td", _, [{"span", _badge, ["In progress"]}]} = looks.status
      assert {"td", _, [{"span", _, [{"progress", _bar, []}, "40"]}]} = looks.progress
      assert looks.estimate == "12.5 h"
      assert looks.slider == %{control: "range", choices: nil, confirm: nil}
    end

    setup %{world: world} do
      %{task: task(world, []), project: hd(world.projects)}
    end

    test "nested under a project", %{conn: conn, task: task, project: project} do
      {:ok, view, _html} = live(conn, "/projects")
      expand(view, "project", project.id)
      html = toggle(view, "project", project.id, "tasks")
      id = nested("project", project.id, "tasks")

      assert_components(looks(html, id, task))

      # and a save through the slider there runs the column's action
      html = save(view, id, task.id, "progress", "55")
      assert stored(task).progress == 55

      assert {"td", _, [{"span", _, [{"progress", _bar, []}, "55"]}]} =
               tree(html, cell(id, task.id, "progress"))
    end

    test "in the full view of a project's tasks", %{conn: conn, task: task, project: project} do
      {:ok, _view, html} = live(conn, "/tasks?task[of][project][tasks]=#{project.id}")

      assert text(html, "#task-related-heading") =~ "Tasks"
      assert_components(looks(html, "task", task))
    end

    test "placed in a page of the host's", %{conn: conn, task: task} do
      {:ok, _view, html} = live(conn, "/dashboard")

      assert_components(looks(html, "dashboard-tasks", task))
    end

    test "in German, a badge shows the German label and the slider is named in German",
         %{conn: conn, task: task} do
      {:ok, _view, html} = conn |> in_locale("de") |> live("/tasks")

      assert {"td", _, [{"span", _badge, ["In Arbeit"]}]} = tree(html, cell(task.id, "status"))
      assert {"td", _, [{"span", _badge, ["Hoch"]}]} = tree(html, cell(task.id, "priority"))

      assert {_template, {"span", _, [{"input", range, []}, _number]}} =
               template(html, "progress")

      assert {"aria-label", "Fortschritt"} in range
      # the unit of the demo's own component is the same in both languages
      assert text(html, cell(task.id, "estimate_hours")) == "12.5 h"
    end
  end
end
