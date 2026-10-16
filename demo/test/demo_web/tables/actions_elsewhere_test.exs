defmodule DemoWeb.Tables.ActionsElsewhereTest do
  @moduledoc """
  Row actions and row create away from `/tasks`: on the full view of a nested
  table, on a page whose create action takes the key of another record, two
  tables deep, in the tables placed in the demo's dashboard, in a table
  whose records have a key of two attributes, and in German.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator
  alias Demo.Tracker.Comment
  alias Demo.Tracker.Project
  alias Demo.Tracker.Task
  alias Demo.Tracker.TaskLabel

  @moment ~U[2026-01-01 12:00:00.000000Z]

  defp task(world, title, overrides \\ []) do
    Generator.generate(
      Generator.task(
        [
          organization_id: world.organization.id,
          project_id: hd(world.projects).id,
          reporter_id: world.admin.id,
          assignee_id: world.member.id,
          title: title,
          progress: 40,
          status: :in_progress,
          inserted_at: @moment
        ] ++ overrides
      )
    )
  end

  defp comment(_world, task, body, author) do
    Generator.generate(
      Generator.comment(
        organization_id: task.organization_id,
        task_id: task.id,
        author_id: author.id,
        body: body,
        inserted_at: @moment
      )
    )
  end

  defp comments do
    Comment
    |> Ash.read!(authorize?: false)
    |> Enum.map(&{&1.body, &1.task_id, &1.author_id})
    |> Enum.sort()
  end

  setup %{conn: conn} do
    world = world(tasks: 0, projects: 1, labels: 0)
    task = task(world, "Write the report")
    other = task(world, "File the report")
    mine = comment(world, task, "Mine", world.member)
    theirs = comment(world, task, "Theirs", world.admin)

    %{conn: log_in(conn, world.member), world: world, task: task, other: other}
    |> Map.merge(%{mine: mine, theirs: theirs})
  end

  describe "the full view of a nested table" do
    setup %{conn: conn, task: task} do
      {:ok, view, html} = live(conn, "/comments?comment[of][task][comments]=#{task.id}")
      %{view: view, html: html}
    end

    test "has the create button on the line that says what it shows, before the way back to all records",
         %{html: html} do
      assert text(html, "#comment-related-heading") == "Write the report: Comments"

      assert attribute(html, "#comment-related > div > *", "id") ==
               ["comment-create", "comment-related-clear"]

      assert text(html, "#comment-create") == "New comment"
      # the line of the page's name has none
      assert attribute(html, "#comment-header button", "id") == []
    end

    test "creates under the record it is limited to, which is no field of the panel",
         %{view: view, world: world, task: task, other: other} do
      assert Enum.map(panel(open_create(view, "comment"), "comment").fields, & &1.name) == [
               "body"
             ]

      html =
        send_panel(view, "comment", %{
          "panel" => %{"body" => "From the full view", "task_id" => other.id}
        })

      assert panel(html, "comment") == nil
      assert hd(column(html, "comment", "body")) == "From the full view"
      assert {"From the full view", task.id, world.member.id} in comments()
    end

    test "runs a row action on a record of it", %{view: view, mine: mine, theirs: theirs} do
      # a member may delete their own comments
      html = act(view, "comment", theirs.id, "destroy")
      assert action_failure(html, "comment", theirs.id) == "You are not allowed to do this."

      html = act(view, "comment", mine.id, "destroy")
      assert column(html, "comment", "body") == ["Theirs"]
      assert Ash.get(Comment, mine.id, authorize?: false, not_found_error?: false) == {:ok, nil}
    end
  end

  describe "a page whose create action takes the key of another record" do
    test "has a field for the key, which is chosen in the picker and which the action checks", %{
      conn: conn,
      world: world,
      task: task
    } do
      {:ok, view, html} = live(conn, "/comments")
      assert text(html, "#comment-header > h1") == "Comments"

      assert [
               %{name: "body", control: "textarea", required?: true},
               # called what the table's column for the key is called
               %{
                 name: "task_id",
                 label: "Task ID",
                 control: "reference",
                 value: "",
                 chosen: nil,
                 required?: true
               }
             ] = panel(open_create(view, "comment"), "comment").fields

      html = run_panel(view, "comment", body: "Loose", task_id: "not a key")

      assert Enum.find(panel(html, "comment").fields, &(&1.name == "task_id")).errors == [
               "is invalid"
             ]

      html = run_panel(view, "comment", body: "Loose", task_id: task.id)
      assert panel(html, "comment") == nil
      assert hd(column(html, "comment", "body")) == "Loose"
      assert {"Loose", task.id, world.member.id} in comments()
    end
  end

  describe "two tables deep" do
    setup %{conn: conn, world: world, task: task} do
      {:ok, view, _html} = live(conn, "/projects")
      [project] = world.projects

      expand(view, "project", project.id)
      toggle(view, "project", project.id, "tasks")
      tasks = nested("project", project.id, "tasks")
      expand(view, tasks, task.id)
      toggle(view, tasks, task.id, "comments")

      %{view: view, project: project, tasks: tasks, comments: nested(tasks, task.id, "comments")}
    end

    test "a row action runs on the record of its own table", %{
      view: view,
      task: task,
      tasks: tasks
    } do
      html = act(view, tasks, task.id, "archive")

      assert text(html, cell(tasks, task.id, "status")) == "Archived"
      assert Ash.get!(Task, task.id, authorize?: false).status == :archived
    end

    test "a panel opens in its own table and runs there", %{view: view, task: task, tasks: tasks} do
      html = act(view, tasks, task.id, "set_progress")
      assert panel(html, tasks).heading == "Set progress: Write the report"
      assert panel(html, "project") == nil

      html = run_panel(view, tasks, progress: "90")
      assert text(html, cell(tasks, task.id, "progress")) == "90"
    end

    test "a destroy takes the row out of its table, with what was open under it",
         %{view: view, mine: mine, tasks: tasks, task: task, comments: comments} do
      html = act(view, comments, mine.id, "destroy")
      assert column(html, comments, "body") == ["Theirs"]

      # and one level up, as an admin may
      {:ok, view, _html} =
        build_conn()
        |> log_in(Ash.get!(Demo.Tracker.User, task.reporter_id, authorize?: false))
        |> live("/projects")

      expand(view, "project", task.project_id)
      toggle(view, "project", task.project_id, "tasks")
      expand(view, tasks, task.id)
      html = toggle(view, tasks, task.id, "comments")
      assert html =~ comments

      html = act(view, tasks, task.id, "destroy")
      refute html =~ comments
      assert column(html, tasks, "title") == ["File the report"]
    end

    test "a record is created under the row of each table",
         %{
           view: view,
           world: world,
           project: project,
           task: task,
           tasks: tasks,
           comments: comments
         } do
      # a comment under the task
      click(view, "[id='#{tasks}-row-#{task.id}-l-comments-create']")

      html = run_panel(view, comments, body: "Deep down")
      assert hd(column(html, comments, "body")) == "Deep down"
      assert {"Deep down", task.id, world.member.id} in comments()

      # a task under the project: `project_id` is no field, and is the project's
      html = click(view, "[id='project-row-#{project.id}-l-tasks-create']")
      assert text(html, "[id='project-row-#{project.id}-l-tasks-create']") == "New task"
      refute "project_id" in Enum.map(panel(html, tasks).fields, & &1.name)

      html = run_panel(view, tasks, title: "Under the project")
      assert hd(column(html, tasks, "title")) == "Under the project"

      assert [%{project_id: project_id, reporter_id: reporter_id}] =
               Task
               |> Ash.read!(authorize?: false, tenant: world.organization.id)
               |> Enum.filter(&(&1.title == "Under the project"))

      assert project_id == project.id
      assert reporter_id == world.member.id
    end
  end

  describe "a table with one input that is a choice" do
    test "shows it with the record's value chosen, and runs with another", %{
      conn: conn,
      world: world
    } do
      [project] = world.projects
      {:ok, view, _html} = live(conn, "/projects")

      html = act(view, "project", project.id, "set_status")

      assert [
               %{
                 name: "status",
                 label: "Status",
                 control: "select",
                 value: value,
                 required?: true
               }
             ] =
               panel(html, "project").fields

      assert value == to_string(project.status)

      html = run_panel(view, "project", status: "on_hold")
      assert panel(html, "project") == nil
      assert text(html, cell("project", project.id, "status")) == "On hold"
      assert Ash.get!(Project, project.id, authorize?: false).status == :on_hold
    end
  end

  describe "the tables placed in the dashboard" do
    test "name themselves on a line with their create button, and run their actions",
         %{conn: conn, world: world, task: task} do
      {:ok, view, html} = live(conn, "/dashboard")

      # the name is a heading of the level the page gave, and names the page's section
      assert text(html, "#dashboard-tasks-header > h2#dashboard-tasks-name") == "Tasks"

      assert attribute(html, "#dashboard-tasks-section", "aria-labelledby") == [
               "dashboard-tasks-name"
             ]

      assert text(html, "#dashboard-tasks-create") == "New task"
      assert text(html, "#dashboard-projects-header > h2") == "Projects"
      # a member may not create projects
      assert text(html, "#dashboard-projects-create") == nil

      html = act(view, "dashboard-tasks", task.id, "archive")
      assert text(html, cell("dashboard-tasks", task.id, "status")) == "Archived"

      html = act(view, "dashboard-tasks", task.id, "set_progress")
      assert panel(html, "dashboard-tasks").heading == "Set progress: Write the report"
      html = run_panel(view, "dashboard-tasks", progress: "60")
      assert text(html, cell("dashboard-tasks", task.id, "progress")) == "60"

      open_create(view, "dashboard-tasks")

      html =
        run_panel(view, "dashboard-tasks",
          title: "From the dashboard",
          project_id: hd(world.projects).id
        )

      assert hd(column(html, "dashboard-tasks", "title")) == "From the dashboard"
      # the other table of the page is as it was
      assert panel(html, "dashboard-projects") == nil
    end
  end

  describe "a table whose records have a key of two attributes" do
    setup %{world: world, task: task, other: other} do
      [red, blue] =
        for name <- ["red", "blue"],
            do:
              Generator.generate(
                Generator.label(organization_id: world.organization.id, name: name)
              )

      for {task, label} <- [{task, red}, {task, blue}, {other, red}] do
        Generator.generate(
          Generator.task_label(
            organization_id: world.organization.id,
            task_id: task.id,
            label_id: label.id
          )
        )
      end

      %{red: red, blue: blue}
    end

    defp links do
      TaskLabel
      |> Ash.read!(authorize?: false, page: [limit: 100])
      |> Map.fetch!(:results)
      |> Enum.map(&{&1.task_id, &1.label_id})
      |> Enum.sort()
    end

    test "runs a row action on the record of the row, and on no other",
         %{conn: conn, task: task, other: other, red: red, blue: blue} do
      {:ok, view, html} = live(conn, "/task_labels")
      key = "#{task.id}-#{red.id}"

      # declared with `confirm false`: no question, and another word on the button
      assert actions(html, "task_label", key) == ["Remove"]
      assert attribute(html, "[id='task_label-row-#{key}-a-destroy']", "data-question") == []

      html = act(view, "task_label", key, "destroy")

      assert links() == Enum.sort([{task.id, blue.id}, {other.id, red.id}])
      assert length(column(html, "task_label", "note")) == 2
    end

    test "creates a record, which is a row with its own key", %{
      conn: conn,
      other: other,
      blue: blue
    } do
      {:ok, view, _html} = live(conn, "/task_labels")

      assert Enum.map(panel(open_create(view, "task_label"), "task_label").fields, & &1.name) ==
               ["task_id", "label_id", "note"]

      html = run_panel(view, "task_label", task_id: other.id, label_id: blue.id, note: "By hand")
      key = "#{other.id}-#{blue.id}"

      assert {other.id, blue.id} in links()
      assert text(html, cell("task_label", key, "note")) == "By hand"

      assert attribute(html, "#task_label-table > [role=rowgroup]:first-of-type", "id") == [
               "task_label-row-#{key}"
             ]

      # and is acted on by that key
      act(view, "task_label", key, "destroy")
      refute {other.id, blue.id} in links()
    end
  end

  describe "in German" do
    test "the table's own words and the resource's are both translated", %{
      conn: conn,
      world: world,
      task: task
    } do
      {:ok, view, html} = conn |> log_in(world.admin) |> in_locale("de") |> live("/tasks")

      assert text(html, "#task-actions-head") == "Aktionen"
      assert text(html, "#task-create") == "Aufgabe anlegen"

      assert actions(html, task.id) == [
               "Archivieren",
               "Neu zuweisen",
               "Fortschritt setzen",
               "Löschen",
               "Labels setzen"
             ]

      assert attribute(html, "[id='task-row-#{task.id}-a-destroy']", "data-question") ==
               ["Diese Aufgabe löschen? Das lässt sich nicht rückgängig machen."]

      html = act(view, task.id, "reassign")

      assert %{heading: "Neu zuweisen: Write the report", submit: "Ausführen"} = panel(html)
      assert Enum.map(panel(html).fields, & &1.label) == ["Zugewiesen an", "Begründung"]
      assert text(html, "#task-panel-cancel") == "Abbrechen"

      html = run_panel(view, reason: "")
      assert announcement(html) =~ "Neu zuweisen fehlgeschlagen: Begründung: "

      cancel_panel(view)
      assert %{heading: "Aufgabe anlegen", submit: "Anlegen"} = panel(open_create(view))
      cancel_panel(view)

      html = act(view, task.id, "archive")
      assert announcement(html) == "Archivieren: erledigt"
    end
  end
end
