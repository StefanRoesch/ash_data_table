defmodule DemoWeb.Tables.ReferenceActionTest do
  @moduledoc """
  Arguments of generic actions whose records are chosen in the picker,
  because the `action` of the table block says which resource they refer
  to (`reference`), on Postgres and in a tenant:

    * "Merge" at `/labels`, a table action with one key and a list of
      keys, both of labels;
    * "Assign open tasks" at `/projects`, a generic action in every row,
      which the table gives the row's key and which takes the key of a
      person besides; also on the selected rows.

  Everything else about the picker of an action's field is in
  `picker_panel_test.exs` and `task_labels_action_test.exs`.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator
  alias Demo.Tracker.Label
  alias Demo.Tracker.Task

  @moment ~U[2026-01-01 12:00:00.000000Z]

  setup do
    world = world(tasks: 0, labels: 0)
    %{world: world}
  end

  defp label(world, name, organization \\ nil) do
    Generator.generate(
      Generator.label(
        organization_id: (organization || world.organization).id,
        name: name,
        colour: "#aa0000"
      )
    )
  end

  defp task(world, project, title, overrides \\ []) do
    Generator.generate(
      Generator.task(
        [
          organization_id: world.organization.id,
          project_id: project.id,
          reporter_id: world.admin.id,
          assignee_id: nil,
          status: :todo,
          title: title,
          inserted_at: @moment
        ] ++ overrides
      )
    )
  end

  defp carry(world, task, labels) do
    for label <- labels do
      Generator.generate(
        Generator.task_label(
          organization_id: world.organization.id,
          task_id: task.id,
          label_id: label.id
        )
      )
    end
  end

  defp labels_of(task) do
    Task
    |> Ash.get!(task.id, authorize?: false, load: :labels)
    |> Map.fetch!(:labels)
    |> Enum.map(& &1.name)
    |> Enum.sort()
  end

  defp label_names(world) do
    Label
    |> Ash.read!(authorize?: false, tenant: world.organization.id)
    |> Enum.map(& &1.name)
    |> Enum.sort()
  end

  defp assignee_of(task), do: Ash.get!(Task, task.id, authorize?: false).assignee_id
  defp field(html, id, name), do: Enum.find(panel(html, id).fields, &(&1.name == name))

  describe "\"Merge\" at /labels: a table action with a key and a list of keys" do
    setup %{conn: conn, world: world} do
      [project | _] = world.projects
      labels = for name <- ~w(bug defect fault idea), into: %{}, do: {name, label(world, name)}
      theirs = label(world, "theirs", world.other_organization)

      one = task(world, project, "One")
      two = task(world, project, "Two")
      carry(world, one, [labels["bug"], labels["defect"]])
      carry(world, two, [labels["fault"], labels["idea"]])

      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/labels")
      %{view: view, labels: labels, theirs: theirs, one: one, two: two}
    end

    test "opens the panel with a field per argument: what is chosen, and a button that opens the picker",
         %{view: view} do
      html = table_act(view, "label", "merge")

      assert %{
               heading: "Merge",
               fields: [
                 %{name: "into", label: "Into", control: "reference", value: "", chosen: nil},
                 %{name: "labels", label: "Labels", control: "references", value: [], chosen: []}
               ]
             } = panel(html, "label")

      # no key is typed: neither field has a text input a person sees
      assert attribute(html, "#label-panel-f-into input:not([hidden])", "name") == []
      assert text(html, "#label-panel-f-into-choose") == "Choose"
      assert text(html, "#label-panel-f-labels-choose") == "Choose"
    end

    test "the picker of the one key is the labels' own table, in which one row is chosen", %{
      view: view,
      labels: labels
    } do
      table_act(view, "label", "merge")
      html = pick_input(view, "label", "into")

      assert %{
               heading: "Into: choose label",
               table: "label-pick-into",
               # the argument cannot be empty: no "None"
               buttons: ["Cancel", "Choose"]
             } = picker(html, "label")

      html = render_async(view)
      # the labels of this organization, and not the other's
      assert column(html, "label-pick-into", "name") == ~w(bug defect fault idea)
      assert attribute(html, "#label-pick-into-grid", "data-select") == ["single"]
      # a table to choose from: nothing in it is edited, run or created
      assert editors(html, "label-pick-into") == []
      assert table_actions(html, "label-pick-into") == []

      html = picked(view, "label", labels["bug"].id)
      assert picker(html, "label") == nil
      bug = labels["bug"].id
      assert %{value: ^bug, chosen: "bug"} = field(html, "label", "into")
    end

    test "the picker of the list of keys takes any number of rows", %{view: view, labels: labels} do
      table_act(view, "label", "merge")
      html = pick_input(view, "label", "labels")

      assert %{heading: "Labels: choose label", table: "label-pick-labels"} =
               picker(html, "label")

      html = render_async(view)
      assert attribute(html, "#label-pick-labels-grid", "data-select") == ["multi"]

      html = picked_rows(view, "label", [labels["defect"].id, labels["fault"].id])
      assert picker(html, "label") == nil

      assert %{value: value, chosen: ["defect", "fault"]} = field(html, "label", "labels")
      assert value == [labels["defect"].id, labels["fault"].id]
    end

    test "runs with what was chosen, as the person, and the table says what it returned", %{
      view: view,
      world: world,
      labels: labels,
      one: one,
      two: two
    } do
      table_act(view, "label", "merge")
      pick_input(view, "label", "into")
      picked(view, "label", labels["bug"].id)
      pick_input(view, "label", "labels")
      picked_rows(view, "label", [labels["defect"].id, labels["fault"].id])

      run_panel(view, "label", %{})
      html = ran(view)

      assert panel(html, "label") == nil
      assert result(html, "label") == "Merge: 2"
      assert label_names(world) == ~w(bug idea)
      assert column(html, "label", "name") == ~w(bug idea)
      # the task that carried both has the one once; the other got it
      assert labels_of(one) == ~w(bug)
      assert labels_of(two) == ~w(bug idea)
    end

    test "a key the form sends that names no label this person could choose runs nothing", %{
      view: view,
      world: world,
      labels: labels,
      theirs: theirs
    } do
      table_act(view, "label", "merge")

      for sent <- [
            %{"into" => theirs.id, "labels" => ["", labels["defect"].id]},
            %{"into" => labels["bug"].id, "labels" => ["", theirs.id]},
            %{"into" => Ash.UUID.generate(), "labels" => ["", labels["defect"].id]}
          ] do
        html = send_panel(view, "label", %{"panel" => sent})

        assert %{errors: [_not_available]} = panel(html, "label")
        assert label_names(world) == ~w(bug defect fault idea)
      end
    end

    test "what the action says of an argument is shown at its field", %{view: view, world: world} do
      table_act(view, "label", "merge")
      html = run_panel(view, "label", %{})

      assert %{errors: ["is required"]} = field(html, "label", "into")
      assert label_names(world) == ~w(bug defect fault idea)
    end

    test "speaks German where the demo translates it", %{conn: conn, world: world} do
      {:ok, view, _html} = conn |> log_in(world.admin) |> in_locale("de") |> live("/labels")
      html = table_act(view, "label", "merge")

      assert %{
               heading: "Zusammenführen",
               fields: [%{label: "In"}, %{label: "Labels"}]
             } = panel(html, "label")

      assert text(html, "#label-panel-f-into-choose") == "Auswählen"
      html = pick_input(view, "label", "into")
      assert %{heading: "In: Label auswählen"} = picker(html, "label")
    end
  end

  describe "\"Assign open tasks\" at /projects: a generic action in every row" do
    setup %{conn: conn, world: world} do
      [project, other | _] = world.projects

      tasks = %{
        open: task(world, project, "Open"),
        taken: task(world, project, "Taken", assignee_id: world.member.id),
        done: task(world, project, "Done", status: :done),
        elsewhere: task(world, other, "Elsewhere")
      }

      {:ok, view, html} = conn |> log_in(world.admin) |> live("/projects")
      %{view: view, html: html, project: project, other: other, tasks: tasks}
    end

    test "has its button in every row, for an admin only", %{
      conn: conn,
      html: html,
      world: world,
      project: project
    } do
      assert "Assign open tasks" in actions(html, "project", project.id)

      {:ok, _view, html} = conn |> log_in(world.member) |> live("/projects")
      refute "Assign open tasks" in actions(html, "project", project.id)
    end

    test "asks for the person and not for the project: the row gives that", %{
      view: view,
      project: project
    } do
      html = act(view, "project", project.id, "assign_open_tasks")

      assert %{
               heading: "Assign open tasks: " <> _name,
               fields: [
                 %{name: "assignee", label: "Assignee", control: "reference", required?: true}
               ]
             } = panel(html, "project")

      html = pick_input(view, "project", "assignee")

      assert %{heading: "Assignee: choose user", table: "project-pick-assignee"} =
               picker(html, "project")
    end

    test "runs on the row's project with the person who was chosen", %{
      view: view,
      world: world,
      project: project,
      tasks: tasks
    } do
      act(view, "project", project.id, "assign_open_tasks")
      pick_input(view, "project", "assignee")
      html = picked(view, "project", world.viewer.id)
      assert field(html, "project", "assignee").chosen == world.viewer.name

      run_panel(view, "project", %{})
      html = ran(view)

      assert panel(html, "project") == nil
      assert result(html, "project") == "Assign open tasks: 1"
      assert assignee_of(tasks.open) == world.viewer.id
      # a task somebody has, one that is done, and one of another project stay
      assert assignee_of(tasks.taken) == world.member.id
      assert assignee_of(tasks.done) == nil
      assert assignee_of(tasks.elsewhere) == nil
    end

    test "a key for the row that the form sends is not taken, nor one of a person of another organization",
         %{view: view, world: world, project: project, other: other, tasks: tasks} do
      act(view, "project", project.id, "assign_open_tasks")

      html =
        send_panel(view, "project", %{
          "panel" => %{"assignee" => world.outsider.id, "project_id" => other.id}
        })

      assert %{errors: [_not_available]} = panel(html, "project")
      assert assignee_of(tasks.open) == nil

      send_panel(view, "project", %{
        "panel" => %{"assignee" => world.viewer.id, "project_id" => other.id}
      })

      ran(view)
      assert assignee_of(tasks.open) == world.viewer.id
      assert assignee_of(tasks.elsewhere) == nil
    end

    test "runs on the selected rows, with the person chosen once for all of them", %{
      view: view,
      world: world,
      project: project,
      other: other,
      tasks: tasks
    } do
      html = bulk(view, "project", "assign_open_tasks", [project.id, other.id])

      assert %{
               heading: "Assign open tasks: 2 records",
               fields: [%{name: "assignee", control: "reference"}]
             } = panel(html, "project")

      pick_input(view, "project", "assignee")
      picked(view, "project", world.member.id)
      run_panel(view, "project", %{})
      html = ran(view)

      assert %{summary: "Assign open tasks: 2 done.", failures: []} = bulk_result(html, "project")
      assert assignee_of(tasks.open) == world.member.id
      assert assignee_of(tasks.elsewhere) == world.member.id
    end
  end
end
