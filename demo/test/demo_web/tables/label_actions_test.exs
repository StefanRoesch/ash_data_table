defmodule DemoWeb.Tables.LabelActionsTest do
  @moduledoc """
  Table actions in the mounted table of `Demo.Tracker.Label` at `/labels`,
  on Postgres and in a tenant: generic actions that count, change and
  delete labels as the person who runs them, one that a role may not run,
  one that takes the key of a row, and the same actions on the line of the
  labels under a task and in their full view.

  Everything else about table actions is in `table_actions_test.exs`.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator
  alias Demo.Tracker.Label

  @moment ~U[2026-01-01 12:00:00.000000Z]

  # The labels of the world's first organization: "bug" and "chore" on a
  # task, "idea" and "later" on none.
  setup do
    world = world(tasks: 0, labels: 0)
    [project | _] = world.projects

    task =
      Generator.generate(
        Generator.task(
          organization_id: world.organization.id,
          project_id: project.id,
          reporter_id: world.admin.id,
          title: "Write the report",
          inserted_at: @moment
        )
      )

    labels =
      for {name, colour} <- [bug: "#aa0000", chore: "#aa0000", idea: "#00aa00", later: "#0000aa"],
          into: %{} do
        label =
          Generator.generate(
            Generator.label(
              organization_id: world.organization.id,
              name: to_string(name),
              colour: colour
            )
          )

        {name, label}
      end

    for name <- [:bug, :chore] do
      Generator.generate(
        Generator.task_label(
          organization_id: world.organization.id,
          task_id: task.id,
          label_id: labels[name].id
        )
      )
    end

    # a label of the other organization, on no task
    Generator.generate(
      Generator.label(
        organization_id: world.other_organization.id,
        name: "theirs",
        colour: "#aa0000"
      )
    )

    %{world: world, task: task, labels: labels}
  end

  defp stored do
    Label
    |> Ash.read!(authorize?: false)
    |> Enum.map(&{&1.name, &1.colour})
    |> Enum.sort()
  end

  describe "the buttons" do
    test "are on the line of the table's name after \"New label\", for the actions each person can ever run",
         %{conn: conn, world: world} do
      {:ok, _view, html} = conn |> log_in(world.admin) |> live("/labels")

      assert text(html, "#label-create") == "New label"
      assert table_actions(html, "label") == ["Count unused", "Recolour", "Remove unused"]

      assert html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#label-header button")
             |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim())) ==
               ["New label", "Count unused", "Recolour", "Remove unused"]

      # counting is everybody's; what changes labels is an admin's
      for actor <- [world.member, world.viewer] do
        {:ok, _view, html} = conn |> log_in(actor) |> live("/labels")
        assert text(html, "#label-create") == nil
        assert table_actions(html, "label") == ["Count unused"]
      end

      {:ok, _view, html} = conn |> log_in(world.nobody) |> live("/labels")
      assert table_actions(html, "label") == []
    end

    test "of the generic action that takes a label's key is in every row, for an admin", %{
      conn: conn,
      world: world,
      labels: labels
    } do
      {:ok, _view, html} = conn |> log_in(world.admin) |> live("/labels")
      assert actions(html, "label", labels.bug.id) == ["Destroy", "Copy"]

      # not on the line of the selected rows: its block says `bulk? false`
      assert %{buttons: [_select_all, "Clear selection", "Destroy"]} = selection(html, "label")

      {:ok, _view, html} = conn |> log_in(world.member) |> live("/labels")
      assert attribute(html, actions_cell("label", labels.bug.id), "id") == []
    end

    test "are in German where the demo translates them", %{conn: conn, world: world} do
      {:ok, view, html} = conn |> log_in(world.admin) |> in_locale("de") |> live("/labels")

      assert table_actions(html, "label") ==
               ["Unbenutzte zählen", "Umfärben", "Unbenutzte entfernen"]

      assert result(table_act(view, "label", "count_unused"), "label") == "Unbenutzte zählen: 2"

      html = table_act(view, "label", "recolour")

      assert %{
               heading: "Umfärben",
               submit: "Ausführen",
               fields: [%{label: "Von"}, %{label: "Nach"}]
             } =
               panel(html, "label")
    end
  end

  describe "\"Count unused\"" do
    test "runs at once, as the person and in their organization, and the table says the number",
         %{conn: conn, world: world} do
      {:ok, view, _html} = conn |> log_in(world.viewer) |> live("/labels")

      html = table_act(view, "label", "count_unused")

      assert result(html, "label") == "Count unused: 2"
      assert announcement(html, "label") == "Count unused: 2"

      # the other organization's person counts the other organization's labels
      {:ok, view, _html} = conn |> log_in(world.outsider) |> live("/labels")
      assert result(table_act(view, "label", "count_unused"), "label") == "Count unused: 1"
    end
  end

  describe "\"Recolour\"" do
    setup %{conn: conn, world: world} do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/labels")
      %{view: view}
    end

    test "opens the action panel with its two arguments", %{view: view} do
      html = table_act(view, "label", "recolour")

      assert %{
               heading: "Recolour",
               submit: "Run",
               fields: [
                 %{name: "from", label: "From", value: "", required?: true},
                 %{name: "to", label: "To", value: "", required?: true}
               ]
             } = panel(html, "label")

      assert stored() |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> length() == 3
    end

    test "shows what the action says of a value at its field", %{view: view} do
      table_act(view, "label", "recolour")
      html = run_panel(view, "label", from: "red", to: "")

      assert %{fields: [%{name: "from", errors: [from]}, %{name: "to", errors: ["is required"]}]} =
               panel(html, "label")

      assert from =~ "must match"
    end

    test "changes the labels of this organization, says how many, and the table shows them", %{
      view: view
    } do
      table_act(view, "label", "recolour")
      run_panel(view, "label", from: "#aa0000", to: "#123456")
      html = ran(view)

      assert panel(html, "label") == nil
      assert result(html, "label") == "Recolour: 2"
      assert column(html, "label", "colour") == ["#123456", "#123456", "#00aa00", "#0000aa"]

      # the other organization's label of that colour is as it was
      assert {"theirs", "#aa0000"} in stored()
    end

    test "is not run by a person who may not, whatever their browser sends", %{
      conn: conn,
      world: world
    } do
      {:ok, view, _html} = conn |> log_in(world.member) |> live("/labels")

      html = table_act(view, "label", "count_unused")
      assert result(html, "label") == "Count unused: 2"

      view |> element("#label-grid") |> render_hook("table_act", %{"action" => "recolour"})
      assert panel(render(view), "label") == nil

      confirm_table_action(view, "label", "remove_unused")
      assert length(stored()) == 5
    end
  end

  describe "\"Remove unused\"" do
    test "asks first, then deletes this organization's unused labels and says that it is done",
         %{conn: conn, world: world} do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/labels")

      table_act(view, "label", "remove_unused")

      assert_push_event view, "ash_table:ask", %{
        table: "label",
        action: :remove_unused,
        question: "Delete every label that no task carries?"
      }

      assert length(stored()) == 5

      html = confirm_table_action(view, "label", "remove_unused")

      assert result(html, "label") == "Remove unused: done"
      assert announcement(html, "label") == "Remove unused: done"
      assert column(html, "label", "name") == ["bug", "chore"]
      assert Enum.map(stored(), &elem(&1, 0)) == ["bug", "chore", "theirs"]
    end
  end

  describe "\"Copy\"" do
    setup %{conn: conn, world: world} do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/labels")
      %{view: view}
    end

    test "opens the panel for the name alone: the label's key is the table's to give", %{
      view: view,
      labels: labels
    } do
      html = act(view, "label", labels.idea.id, "copy")

      assert %{
               heading: "Copy: idea",
               fields: [%{name: "name", label: "Name", value: "", required?: true}]
             } = panel(html, "label")
    end

    test "makes a label of the row's colour, whatever key the form sends, and the table reads again",
         %{view: view, labels: labels} do
      act(view, "label", labels.idea.id, "copy")

      send_panel(view, "label", %{
        "panel" => %{"name" => "idea 2", "label_id" => labels.bug.id}
      })

      html = ran(view)

      assert panel(html, "label") == nil
      assert result(html, "label") == "Copy: done"
      assert {"idea 2", "#00aa00"} in stored()
      assert column(html, "label", "name") == ["bug", "chore", "idea", "idea 2", "later"]
    end

    test "shows at the field what the create inside it says of the name", %{
      view: view,
      labels: labels
    } do
      act(view, "label", labels.idea.id, "copy")
      html = run_panel(view, "label", name: "bug")

      assert %{fields: [%{name: "name", errors: ["has already been taken"]}]} =
               panel(html, "label")

      assert length(stored()) == 5
    end
  end

  describe "under a task" do
    setup %{conn: conn, world: world, task: task} do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")
      expand(view, task.id)
      toggle(view, task.id, "labels")

      %{view: view, html: ran(view), nested: nested(task.id, "labels")}
    end

    test "the labels' table actions are on their line", %{html: html, task: task} do
      assert line_buttons(html, task.id, "labels") ==
               ["Count unused", "Recolour", "Remove unused"]

      # a line whose table has none is as it was
      assert line_buttons(html, task.id, "comments") == []
    end

    test "run on the nested table, in the person's organization, and are not given the task", %{
      view: view,
      task: task,
      nested: nested
    } do
      html =
        table_act(view, nested, "count_unused",
          on: "task-row-#{task.id}-l-labels-do-count_unused"
        )

      # the unused labels of the organization: those of this task are all used
      assert result(html, nested) == "Count unused: 2"
      assert column(html, nested, "name") == ["bug", "chore"]
    end
  end
end
