defmodule DemoWeb.Tables.EmbeddedTableTest do
  @moduledoc """
  Tables placed in a LiveView of the host's with `<AshDataTable.table … />`.

  The demo's dashboard at `/dashboard` holds two: the projects and the tasks,
  each given the actor and the tenant as attributes. What a domain's
  `authorize?` and a scope do to an embedded table is shown on a page that
  exists for the tests only (`DemoWeb.Support.EmbeddedLive`, at
  `/support/embedded`), with resources whose records are kept in memory.
  """
  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator
  alias Demo.Support.Guarded
  alias Demo.Support.Unguarded

  @projects "dashboard-projects"
  @tasks "dashboard-tasks"

  defp number(n), do: String.pad_leading("#{n}", 2, "0")

  describe "two tables in one page" do
    setup %{conn: conn} do
      world = world(tasks: 0, projects: 0, other_tasks: 3)

      [project | _] =
        for n <- 1..12 do
          Generator.generate(
            Generator.project(
              organization_id: world.organization.id,
              name: "Project #{number(n)}"
            )
          )
        end

      tasks =
        for n <- 1..30 do
          Generator.generate(
            Generator.task(
              organization_id: world.organization.id,
              project_id: project.id,
              reporter_id: world.admin.id,
              title: "Task #{number(n)}",
              inserted_at: DateTime.add(~U[2026-01-01 12:00:00.000000Z], n, :minute)
            )
          )
        end

      %{world: world, tasks: tasks, conn: log_in(conn, world.admin)}
    end

    test "are both there, each under its own id, with the host's page around them",
         %{conn: conn} do
      {:ok, _view, html} = live(conn, "/dashboard")

      assert text(html, "h1") == "Dashboard"
      assert attribute(html, "##{@projects}-table", "aria-label") == ["Projects"]
      assert attribute(html, "##{@tasks}-table", "aria-label") == ["Tasks"]
      assert column(html, @projects, "name") == Enum.map(1..10, &"Project #{number(&1)}")
      assert text(html, "##{@projects}-range") == "1–10 of 12"
      assert text(html, "##{@tasks}-range") == "1–25 of 30"
      # the newest first, as the tasks' read action sorts
      assert hd(column(html, @tasks, "title")) == "Task 30"
    end

    test "sort independently, and without the URL", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/dashboard")

      view |> element("##{@tasks}-sort-title") |> render_click()
      html = render_async(view)

      assert attribute(html, "##{@tasks}-head-title", "aria-sort") == ["ascending"]
      assert Enum.take(column(html, @tasks, "title"), 2) == ["Task 01", "Task 02"]
      assert attribute(html, "##{@projects}-head-name", "aria-sort") == ["none"]
      assert hd(column(html, @projects, "name")) == "Project 01"

      view |> element("##{@projects}-sort-name") |> render_click()
      view |> element("##{@projects}-sort-name") |> render_click()
      html = render_async(view)

      assert attribute(html, "##{@projects}-head-name", "aria-sort") == ["descending"]
      assert hd(column(html, @projects, "name")) == "Project 12"
      assert attribute(html, "##{@tasks}-head-title", "aria-sort") == ["ascending"]
      assert hd(column(html, @tasks, "title")) == "Task 01"

      # nothing of it is in the URL: the page was never patched
      refute_patched(view)
    end

    test "filter independently, each announcing its own result", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/dashboard")

      html = filter(view, @tasks, "title", v: "Task 0")

      assert length(column(html, @tasks, "title")) == 9
      assert text(html, "##{@tasks}-range") == "1–9 of 9"
      assert text(html, "##{@tasks}-status") == "9 results"
      assert text(html, "##{@projects}-range") == "1–10 of 12"
      assert text(html, "##{@projects}-status") == ""

      html = filter(view, @projects, "name", v: "Project 1")

      assert column(html, @projects, "name") == ["Project 10", "Project 11", "Project 12"]
      assert text(html, "##{@projects}-status") == "3 results"
      assert text(html, "##{@tasks}-range") == "1–9 of 9"

      view |> element("##{@tasks}-clear-filters") |> render_click()
      html = render_async(view)

      assert text(html, "##{@tasks}-range") == "1–25 of 30"
      assert column(html, @projects, "name") == ["Project 10", "Project 11", "Project 12"]
    end

    test "page independently", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/dashboard")

      view |> element("##{@projects}-next") |> render_click()
      html = render_async(view)

      assert column(html, @projects, "name") == ["Project 11", "Project 12"]
      assert text(html, "##{@projects}-range") == "11–12 of 12"
      assert text(html, "##{@tasks}-range") == "1–25 of 30"

      view |> element("##{@tasks}-page-2") |> render_click()
      html = render_async(view)

      assert text(html, "##{@tasks}-range") == "26–30 of 30"
      assert List.last(column(html, @tasks, "title")) == "Task 01"
      assert text(html, "##{@projects}-range") == "11–12 of 12"
    end

    test "keep their state themselves: opening the page again starts afresh", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/dashboard")
      view |> element("##{@projects}-next") |> render_click()
      assert text(render_async(view), "##{@projects}-range") == "11–12 of 12"

      {:ok, _view, html} = live(conn, "/dashboard")
      assert text(html, "##{@projects}-range") == "1–10 of 12"
    end

    test "a cell of an embedded table is saved through its column's action",
         %{conn: conn, tasks: tasks} do
      task = List.last(tasks)
      {:ok, view, html} = live(conn, "/dashboard")

      assert "title" in editors(html, @tasks)
      # each table has the editors of its own columns
      assert editors(html, @projects) ==
               ~w(name description status starts_on budget client milestones)

      html = save(view, @tasks, task.id, "title", "Task thirty")

      assert text(html, cell(@tasks, task.id, "title")) == "Task thirty"
      assert Ash.get!(Demo.Tracker.Task, task.id, authorize?: false).title == "Task thirty"

      html = save(view, @tasks, task.id, "title", "ab")

      assert failure(html, @tasks, task.id, "title") == %{
               shown: "ab",
               message: "length must be greater than or equal to 3"
             }

      assert text(html, "##{@tasks}-status") ==
               "Title was not saved: length must be greater than or equal to 3"

      html = discard(view, @tasks, task.id, "title")
      assert text(html, cell(@tasks, task.id, "title")) == "Task thirty"
    end

    test "a read that is refused outright renders nothing of that table, and the page stays",
         %{conn: conn} do
      # nobody: the projects' read is refused, the tasks' finds nothing
      {:ok, _view, html} = conn |> log_in(nil) |> live("/dashboard")

      assert text(html, "h1") == "Dashboard"
      assert attribute(html, "##{@projects}", "hidden") == [""]
      assert text(html, "##{@projects}") == ""
      assert attribute(html, "##{@projects}-table", "id") == []
      assert attribute(html, "##{@projects}-error", "id") == []
      refute html =~ "not allowed"

      assert text(html, "##{@tasks}-empty") == "No records"
      assert attribute(html, "##{@tasks}-table", "id") == ["#{@tasks}-table"]
    end
  end

  test "embedded tables read as the actor, in the tenant, they are given as attributes",
       %{conn: conn} do
    world = world(tasks: 4, other_tasks: 3)

    {:ok, _view, html} = conn |> log_in(world.outsider) |> live("/dashboard")

    assert text(html, "##{@tasks}-range") == "1–3 of 3"
    # what a member can never see is left out here as on the mounted page
    refute "External ref" in headers(html, @tasks)

    {:ok, _view, html} = conn |> log_in(world.admin) |> live("/dashboard")
    assert text(html, "##{@tasks}-range") == "1–4 of 4"
    assert "External ref" in headers(html, @tasks)
  end

  describe "an embedded table and its domain" do
    setup do
      Demo.Support.Gate.open()

      Unguarded.Note
      |> Ash.Changeset.for_create(:create, %{title: "Open to all", secret: "s3cret"})
      |> Ash.create!(authorize?: false)

      for {title, organization} <- [{"Ada at Acme", "acme"}, {"Ada at Globex", "globex"}] do
        Guarded.Note
        |> Ash.Changeset.for_create(:create, %{
          title: title,
          owner: "ada",
          organization: organization
        })
        |> Ash.create!(authorize?: false)
      end

      on_exit(fn ->
        Demo.Support.Ets.stop(Guarded.Note)
        Demo.Support.Ets.stop(Unguarded.Note)
      end)
    end

    test "authorizes as its resource's domain says when it is told nothing: " <>
           "under `authorize? false`, nobody reads and edits everything",
         %{conn: conn} do
      {:ok, view, html} = live(conn, "/support/embedded")

      assert column(html, "open", "title") == ["Open to all"]
      assert column(html, "open", "secret") == ["s3cret"]
      assert editors(html, "open") == ["title", "secret"]

      [%{id: id}] = Ash.read!(Unguarded.Note, authorize?: false)
      html = save(view, "open", id, "secret", "changed by nobody")

      assert text(html, cell("open", id, "secret")) == "changed by nobody"
    end

    test "authorizes when it is told to, whatever its domain says", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/support/embedded")

      # the resource's policies refuse everybody: nothing of the table is there
      assert attribute(html, "#checked", "hidden") == [""]
      assert attribute(html, "#checked-table", "id") == []
      assert text(html, "#after") == "After the tables"
    end

    test "reads as the scope it is given", %{conn: conn} do
      scope = %Demo.Support.Scope{user: %{name: "ada"}, organization: "globex"}

      {:ok, _view, html} =
        conn
        |> Phoenix.ConnTest.init_test_session(%{"assigns" => %{viewer_scope: scope}})
        |> live("/support/embedded")

      assert column(html, "scoped", "title") == ["Ada at Globex"]
    end

    test "with no scope, actor or tenant, nobody is asking", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/support/embedded")

      assert column(html, "scoped", "title") == []
      assert text(html, "#scoped-empty") == "No records"
    end
  end
end
