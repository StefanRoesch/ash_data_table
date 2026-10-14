defmodule DemoWeb.Tables.ReferenceCellTest do
  @moduledoc """
  Reference cells, as a person meets them in the demo: the columns "Project",
  "Assignee" and "Reported by" of `/tasks` each name a belongs-to
  relationship and show the related record's label in place of its key.

  A project is called by its name, and so is a person. People are read by
  the admin and the member, within their organization; a viewer may not read
  people at all.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator

  @moment ~U[2026-01-01 12:00:00.000000Z]

  # A task of the world's first organization, in its first project, reported
  # by the admin and assigned to nobody. Each is created a minute after the
  # one before it, so that the newest comes first.
  defp task(world, title, overrides \\ []) do
    [project | _] = world.projects

    Generator.generate(
      Generator.task(
        [
          organization_id: world.organization.id,
          project_id: project.id,
          reporter_id: world.admin.id,
          assignee_id: nil,
          title: title,
          inserted_at:
            DateTime.add(@moment, System.unique_integer([:positive, :monotonic]), :millisecond)
        ] ++ overrides
      )
    )
  end

  defp person(world, name, overrides \\ []) do
    Generator.generate(
      Generator.user([organization_id: world.organization.id, name: name] ++ overrides)
    )
  end

  describe "a reference cell" do
    setup %{conn: conn} do
      world = world(tasks: 0, other_tasks: 0)
      %{world: world, conn: log_in(conn, world.admin)}
    end

    test "has a column of its own, after the columns of the resource's fields, under the relationship's label",
         %{conn: conn, world: world} do
      task(world, "Write the report")

      {:ok, _view, html} = live(conn, "/tasks")

      assert Enum.take(headers(html, "task"), -4) ==
               ["Inserted at", "Project", "Assignee", "Reported by"]
    end

    test "shows the label of the related record: the `label_field` of its resource's table",
         %{conn: conn, world: world} do
      [project | _] = world.projects
      ada = person(world, "Ada Lovelace")
      task = task(world, "Write the report", assignee_id: ada.id)

      {:ok, _view, html} = live(conn, "/tasks")

      assert text(html, cell(task.id, "project")) == project.name
      assert text(html, cell(task.id, "assignee")) == "Ada Lovelace"
      assert text(html, cell(task.id, "reporter")) == world.admin.name
    end

    test "is empty where there is no related record", %{conn: conn, world: world} do
      task = task(world, "Write the report")

      {:ok, _view, html} = live(conn, "/tasks")

      assert text(html, cell(task.id, "assignee")) == ""
      assert attribute(html, "#{cell(task.id, "assignee")} *", "class") == []
    end

    test "shows each row its own related record, on a page of several", %{
      conn: conn,
      world: world
    } do
      ada = person(world, "Ada Lovelace")
      grace = person(world, "Grace Hopper")
      task(world, "First", assignee_id: ada.id)
      task(world, "Second", assignee_id: grace.id)
      task(world, "Third")
      task(world, "Fourth", assignee_id: ada.id)

      {:ok, _view, html} = live(conn, "/tasks?task[sort]=inserted_at")

      assert column(html, "task", "title") == ["First", "Second", "Third", "Fourth"]

      assert column(html, "task", "assignee") ==
               ["Ada Lovelace", "Grace Hopper", "", "Ada Lovelace"]
    end

    test "is read-only where no update action accepts its key: no editor for its column, and marked as such",
         %{conn: conn, world: world} do
      task = task(world, "Write the report")

      {:ok, _view, html} = live(conn, "/tasks")

      # `update` accepts `project_id` and `assignee_id`, and no action `reporter_id`
      assert "reporter" not in editors(html, "task")
      assert attribute(html, cell(task.id, "reporter"), "aria-readonly") == ["true"]

      for name <- ["project", "assignee"] do
        assert name in editors(html, "task")
        assert attribute(html, cell(task.id, name), "aria-readonly") == []
      end
    end

    test "has no value that is typed: a `save` of it is nothing the table lets anyone send",
         %{conn: conn, world: world} do
      ada = person(world, "Ada Lovelace")
      task = task(world, "Write the report")

      {:ok, view, _html} = live(conn, "/tasks")

      for name <- ["assignee", "reporter", "project"], typed <- ["Somebody", ada.id] do
        html = save(view, task.id, name, typed)
        assert_reply view, %{ok: false}
        assert text(html, cell(task.id, "assignee")) == ""
      end

      assert Ash.get!(Demo.Tracker.Task, task.id, authorize?: false).assignee_id == nil
    end
  end

  describe "a related record the person may not read" do
    setup %{conn: conn} do
      world = world(tasks: 0, other_tasks: 0)
      # a person of another organization: nobody of this one may read them
      stranger = world.outsider
      task = task(world, "Assigned abroad", assignee_id: stranger.id)
      free = task(world, "Assigned to nobody")

      %{world: world, task: task, free: free, stranger: stranger, conn: conn}
    end

    test "looks exactly like no related record: an empty cell, and nothing that says more",
         %{conn: conn, world: world, task: task, free: free, stranger: stranger} do
      for actor <- [world.admin, world.member] do
        {:ok, _view, html} = conn |> log_in(actor) |> live("/tasks")

        refute html =~ stranger.name

        assert [hidden] =
                 html
                 |> LazyHTML.from_fragment()
                 |> LazyHTML.query(cell(task.id, "assignee"))
                 |> LazyHTML.to_tree()

        assert [none] =
                 html
                 |> LazyHTML.from_fragment()
                 |> LazyHTML.query(cell(free.id, "assignee"))
                 |> LazyHTML.to_tree()

        # the same cell but for the row in its id
        assert strip(hidden, task.id) == strip(none, free.id)
        assert text(html, cell(task.id, "assignee")) == ""
      end
    end

    defp strip({tag, attributes, children}, key) do
      {tag,
       for({name, value} <- attributes, do: {name, String.replace(value, to_string(key), "KEY")}),
       children}
    end
  end

  describe "a person who can never read the related resource" do
    setup %{conn: conn} do
      world = world(tasks: 0, other_tasks: 0)
      ada = person(world, "Ada Lovelace")
      task = task(world, "Write the report", assignee_id: ada.id)

      %{world: world, task: task, conn: conn}
    end

    test "has no column for it: the viewer, who may not read people, sees the project alone",
         %{conn: conn, world: world, task: task} do
      [project | _] = world.projects

      {:ok, _view, html} = conn |> log_in(world.viewer) |> live("/tasks")

      assert Enum.take(headers(html, "task"), -2) == ["Inserted at", "Project"]
      assert text(html, cell(task.id, "project")) == project.name
      assert attribute(html, cell(task.id, "assignee"), "id") == []
      assert attribute(html, cell(task.id, "reporter"), "id") == []
      refute html =~ "Ada Lovelace"
      refute html =~ world.admin.name
    end

    test "nor has nobody for the project, whose read is refused when nobody is logged in",
         %{conn: conn} do
      {:ok, _view, html} = conn |> log_in(nil) |> live("/tasks")

      # people are not refused to nobody: they are filtered, to none
      assert Enum.take(headers(html, "task"), -3) == ["Inserted at", "Assignee", "Reported by"]
      assert column(html, "task", "assignee") == []
      refute html =~ "Ada Lovelace"
    end
  end

  describe "sorting and filtering" do
    setup %{conn: conn} do
      world = world(tasks: 0, other_tasks: 0)
      zed = person(world, "Zed")
      amy = person(world, "Amy")
      task(world, "First", assignee_id: zed.id)
      task(world, "Second", assignee_id: amy.id)
      task(world, "Third", assignee_id: zed.id)

      %{conn: log_in(conn, world.admin)}
    end

    test "are not offered for a reference column: no sort on its header, no filter under it",
         %{conn: conn} do
      {:ok, _view, html} = live(conn, "/tasks")

      for name <- ["project", "assignee", "reporter"] do
        assert attribute(html, "#task-head-#{name}", "aria-sort") == []
        assert attribute(html, "#task-head-#{name}", "data-sort") == []
        assert attribute(html, "#task-head-#{name}", "phx-click") == []
        assert filter_controls(html, "task", name) == %{operators: nil, input: nil, choices: nil}
      end
    end

    test "by one are ignored when an event asks for them all the same", %{conn: conn} do
      {:ok, view, html} = live(conn, "/tasks")
      newest_first = column(html, "task", "title")
      assert newest_first == ["Third", "Second", "First"]

      for name <- ["assignee", "assignee.name", "assignee_id"] do
        html = forge(view, "task", "sort", %{"column" => name})

        assert column(html, "task", "title") == newest_first
        assert_patch_none(view)
      end

      html =
        forge(view, "task", "filter", %{
          "filter" => %{"assignee" => %{"o" => "contains", "v" => "Amy"}}
        })

      assert column(html, "task", "title") == newest_first
      assert_patch_none(view)
    end

    test "by one are ignored in a URL", %{conn: conn} do
      for query <- [
            "task[sort]=assignee",
            "task[sort]=-assignee",
            "task[sort]=assignee.name",
            "task[f][assignee]=Amy",
            "task[f][assignee][contains]=Amy",
            "task[f][assignee.name]=Amy",
            "task[f][assignee][name]=Amy"
          ] do
        {:ok, _view, html} = live(conn, "/tasks?" <> query)

        assert column(html, "task", "title") == ["Third", "Second", "First"], query
        assert column(html, "task", "assignee") == ["Zed", "Amy", "Zed"], query
        assert attribute(html, "#task-head-assignee", "aria-sort") == [], query
        assert text(html, "#task-clear-filters") == nil, query
      end
    end

    # nothing was patched: the URL is as it was
    defp assert_patch_none(view) do
      refute_received {_ref, {:patch, _topic, _to}}
      assert render(view) =~ "task-grid"
    end
  end

  describe "after an edit of another cell of the row" do
    setup %{conn: conn} do
      world = world(tasks: 0, other_tasks: 0)
      %{world: world, conn: conn}
    end

    test "the reference cells of the row are as they were", %{conn: conn, world: world} do
      [project | _] = world.projects
      ada = person(world, "Ada Lovelace")
      task = task(world, "Write the report", assignee_id: ada.id)

      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")

      html = save(view, task.id, "title", "Write the summary")

      assert text(html, cell(task.id, "title")) == "Write the summary"
      assert text(html, cell(task.id, "project")) == project.name
      assert text(html, cell(task.id, "assignee")) == "Ada Lovelace"
      assert text(html, cell(task.id, "reporter")) == world.admin.name
    end

    test "and so after an edit that the action refuses, and one that changes nothing",
         %{conn: conn, world: world} do
      ada = person(world, "Ada Lovelace")
      task = task(world, "Write the report", assignee_id: ada.id)

      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")

      html = save(view, task.id, "title", "No")
      assert %{message: _} = failure(html, task.id, "title")
      assert text(html, cell(task.id, "assignee")) == "Ada Lovelace"

      html = save(view, task.id, "priority", to_string(task.priority))
      assert text(html, cell(task.id, "assignee")) == "Ada Lovelace"
    end

    test "a related record the person may not read is still not shown", %{
      conn: conn,
      world: world
    } do
      # reported by the member, who may edit it; assigned to a person of
      # another organization, whom the member may not read
      task =
        task(world, "Assigned abroad",
          reporter_id: world.member.id,
          assignee_id: world.outsider.id
        )

      {:ok, view, _html} = conn |> log_in(world.member) |> live("/tasks")

      html = save(view, task.id, "title", "Still abroad")

      assert text(html, cell(task.id, "title")) == "Still abroad"
      assert text(html, cell(task.id, "assignee")) == ""
      assert text(html, cell(task.id, "reporter")) == world.member.name
      refute html =~ world.outsider.name
    end
  end

  describe "in a nested table" do
    setup %{conn: conn} do
      world = world(tasks: 0, other_tasks: 0)
      [project | _] = world.projects
      ada = person(world, "Ada Lovelace")
      task = task(world, "Write the report", assignee_id: ada.id)
      abroad = task(world, "Assigned abroad", assignee_id: world.outsider.id)

      %{world: world, project: project, task: task, abroad: abroad, conn: conn}
    end

    test "the rows show their reference cells, to each person as on a page of their own",
         %{conn: conn, world: world, project: project, task: task, abroad: abroad} do
      for {actor, headers} <- [
            {world.admin, ["Inserted at", "Project", "Assignee", "Reported by"]},
            {world.member, ["Inserted at", "Project", "Assignee", "Reported by"]},
            {world.viewer, ["Repeats", "Inserted at", "Project"]}
          ] do
        {:ok, view, _html} = conn |> log_in(actor) |> live("/projects")

        expand(view, "project", project.id)
        html = toggle(view, "project", project.id, "tasks")
        id = nested("project", project.id, "tasks")

        assert Enum.take(headers(html, id), -length(headers)) == headers
        assert text(html, cell(id, task.id, "project")) == project.name
        refute html =~ world.outsider.name

        if actor != world.viewer do
          assert text(html, cell(id, task.id, "assignee")) == "Ada Lovelace"
          assert text(html, cell(id, abroad.id, "assignee")) == ""
          assert text(html, cell(id, task.id, "reporter")) == world.admin.name
        end
      end
    end

    test "a row edited in it keeps its reference cells", %{
      conn: conn,
      world: world,
      project: project,
      task: task
    } do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/projects")

      expand(view, "project", project.id)
      toggle(view, "project", project.id, "tasks")
      id = nested("project", project.id, "tasks")

      html = save(view, id, task.id, "title", "Write the summary")

      assert text(html, cell(id, task.id, "title")) == "Write the summary"
      assert text(html, cell(id, task.id, "assignee")) == "Ada Lovelace"
      assert text(html, cell(id, task.id, "project")) == project.name
    end
  end
end
