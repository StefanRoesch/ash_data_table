defmodule DemoWeb.Tables.TaskArgumentsTest do
  @moduledoc """
  The argument line of the mounted table of `Demo.Tracker.Task` at `/tasks`,
  on Postgres: a read action with an argument that may be left empty (a
  search term), and the calculation `due_within?` as two columns, one that
  fixes its argument and one that asks for it.
  """
  use DemoWeb.ModeCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator

  # Tasks of the world's first organization, one per keyword list of fields,
  # each created a day after the one before it, so the last one is the newest
  # and comes first.
  defp tasks(world, tasks) do
    [project | _] = world.projects

    for {fields, index} <- Enum.with_index(tasks) do
      Generator.generate(
        Generator.task(
          [
            organization_id: world.organization.id,
            project_id: project.id,
            reporter_id: world.admin.id,
            status: :todo,
            inserted_at: DateTime.add(~U[2026-01-01 12:00:00.000000Z], index, :day)
          ] ++ fields
        )
      )
    end
  end

  defp in_days(days), do: Date.add(Date.utc_today(), days)

  setup %{conn: conn} do
    world = world(tasks: 0)

    tasks =
      tasks(world, [
        [title: "Later", description: "nothing", due_on: in_days(200)],
        [title: "Next month", description: "nothing", due_on: in_days(20)],
        [title: "This week", description: "the REPORT is due", due_on: in_days(3)],
        [title: "Write the report", description: nil, due_on: nil]
      ])

    %{world: world, tasks: tasks, conn: log_in(conn, world.admin)}
  end

  defp titles(html), do: column(html, "task", "title")

  describe "the line" do
    test "asks for the search term, and for the days of the column that asks for them", %{
      conn: conn
    } do
      {:ok, _view, html} = live(conn, "/tasks")

      assert arguments(html, "task") == [
               %{
                 name: "search",
                 label: "Search",
                 control: "text",
                 value: "",
                 required?: false,
                 errors: []
               },
               %{
                 name: "due_within-days",
                 label: "Due within: Days",
                 control: "number",
                 value: "30",
                 required?: true,
                 errors: []
               }
             ]

      # nothing is asked for before the rows are shown
      assert text(html, "#task-fill") == nil
      assert titles(html) == ["Write the report", "This week", "Next month", "Later"]
    end
  end

  describe "the search term" do
    test "is given to the read action: in the title or the description, whatever the case", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, "/tasks")

      html = argue(view, "task", a: %{"search" => "report"})

      assert titles(html) == ["Write the report", "This week"]
      assert text(html, "#task-range") == "1–2 of 2"
      assert announcement(html, "task") == "2 results"
      assert assert_patch(view) == "/tasks?task[a][search]=report"
    end

    test "is read from the URL, and shown in its input", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/tasks?task[a][search]=week")

      assert titles(html) == ["This week"]
      assert [%{value: "week"} | _] = arguments(html, "task")
    end

    test "stays through a sort, a filter and a page", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/tasks?task[a][search]=report")

      view |> element("#task-head-title") |> render_click()
      assert assert_patch(view) == "/tasks?task[a][search]=report&task[sort]=title"
      assert titles(render_async(view)) == ["This week", "Write the report"]

      html = filter(view, "task", "title", v: "Write")
      assert titles(html) == ["Write the report"]

      assert assert_patch(view) ==
               "/tasks?task[a][search]=report&task[f][title]=Write&task[sort]=title"
    end

    test "matches nothing: \"No records\", and the line is still there", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/tasks?task[a][search]=zebra")

      assert text(html, "#task-empty") == "No records"
      assert [%{value: "zebra"} | _] = arguments(html, "task")
    end

    test "says which records a cell is saved on: one it no longer returns is no longer available",
         %{conn: conn, tasks: [_later, _month, _week, report]} do
      {:ok, view, _html} = live(conn, "/tasks?task[a][search]=report")

      html = save(view, report.id, "title", "Write the summary")

      # the row is shown from what the action returned, and stays
      assert titles(html) == ["Write the summary", "This week"]

      save(view, report.id, "title", "Write the essay")
      assert_reply view, %{ok: false, error: "This record is no longer available."}
    end
  end

  describe "the calculation that is a column twice" do
    test "is computed for each column with that column's argument", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/tasks")

      assert headers(html, "task") |> Enum.filter(&String.starts_with?(&1, "Due within")) ==
               ["Due within 7 days", "Due within"]

      # newest first: no date, in 3 days, in 20 days, in 200 days
      assert column(html, "task", "due_within?") == ["–No", "✓Yes", "–No", "–No"]
      # the asked one starts with 30 days
      assert column(html, "task", "due_within") == ["–No", "✓Yes", "✓Yes", "–No"]
    end

    test "the asked one follows what the person gives it", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/tasks")

      html = argue(view, "task", c: %{"due_within" => %{"days" => "365"}})

      assert column(html, "task", "due_within?") == ["–No", "✓Yes", "–No", "–No"]
      assert column(html, "task", "due_within") == ["–No", "✓Yes", "✓Yes", "✓Yes"]
      assert assert_patch(view) == "/tasks?task[c][due_within][days]=365"
    end

    test "is put back with its arguments on a row that an action returned", %{
      conn: conn,
      tasks: [later | _]
    } do
      {:ok, view, _html} = live(conn, "/tasks?task[c][due_within][days]=365")

      html = save(view, later.id, "due_on", Date.to_iso8601(in_days(5)))

      assert text(html, cell(later.id, "due_within?")) == "✓Yes"
      assert text(html, cell(later.id, "due_within")) == "✓Yes"

      html = save(view, later.id, "due_on", Date.to_iso8601(in_days(500)))

      assert text(html, cell(later.id, "due_within?")) == "–No"
      assert text(html, cell(later.id, "due_within")) == "–No"
    end

    test "each column is sorted by with its own argument", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/tasks")

      view |> element("#task-head-due_within") |> render_click()
      view |> element("#task-head-due_within") |> render_click()
      html = render_async(view)

      # within 30 days first: two tasks
      assert Enum.take(column(html, "task", "due_within"), 3) == ["✓Yes", "✓Yes", "–No"]
      assert assert_patch(view) == "/tasks?task[sort]=due_within"
      assert assert_patch(view) == "/tasks?task[sort]=-due_within"

      {:ok, _view, html} = live(conn, "/tasks?task[sort]=-due_within%3F")
      # within 7 days first: one task
      assert Enum.take(column(html, "task", "due_within?"), 2) == ["✓Yes", "–No"]
      assert hd(titles(html)) == "This week"
    end

    test "each column is filtered by with its own argument, both at once", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/tasks")

      html = filter(view, "task", "due_within", o: "yes")
      assert titles(html) == ["This week", "Next month"]
      assert text(html, "#task-range") == "1–2 of 2"

      # within 30 days, and not within 7
      html =
        view
        |> form("#task-filters", %{
          "filter" => %{"due_within" => %{"o" => "yes"}, "due_within?" => %{"o" => "no"}}
        })
        |> render_change()
        |> then(fn _ -> render_async(view) end)

      assert titles(html) == ["Next month"]

      # the same filter under another argument
      html = argue(view, "task", c: %{"due_within" => %{"days" => "365"}})
      assert titles(html) == ["Next month", "Later"]
    end

    test "a number its constraint refuses is shown at the input, and the column stays", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, "/tasks")

      html = argue(view, "task", c: %{"due_within" => %{"days" => "-1"}})

      assert [_search, %{value: "-1", errors: ["must be greater than or equal to 0"]}] =
               arguments(html, "task")

      assert column(html, "task", "due_within") == ["–No", "✓Yes", "✓Yes", "–No"]
      assert text(html, "#task-error") == nil
    end
  end

  describe "the tasks elsewhere" do
    test "nested under a project have their line too, which narrows that table alone", %{
      conn: conn,
      world: world
    } do
      [project | _] = world.projects
      {:ok, view, _html} = live(conn, "/projects")

      expand(view, "project", project.id)
      html = toggle(view, "project", project.id, "tasks")
      id = nested("project", project.id, "tasks")

      assert Enum.map(arguments(html, id), & &1.label) == ["Search", "Due within: Days"]
      assert length(column(html, id, "title")) == 4

      html = argue(view, id, a: %{"search" => "week"})
      assert column(html, id, "title") == ["This week"]
      refute_patched(view)
    end

    test "placed in a page of the host's keep what was given, with nothing in the URL", %{
      conn: conn
    } do
      {:ok, view, html} = live(conn, "/dashboard")

      assert Enum.map(arguments(html, "dashboard-tasks"), & &1.label) ==
               ["Search", "Due within: Days"]

      html = argue(view, "dashboard-tasks", a: %{"search" => "week"})
      assert column(html, "dashboard-tasks", "title") == ["This week"]
      refute_patched(view)
    end

    test "to choose one from, in the picker, are searched the same way", %{
      conn: conn,
      tasks: [_later, _month, week, _report]
    } do
      {:ok, view, _html} = live(conn, "/comments")

      open_create(view, "comment")
      html = pick_input(view, "comment", "task_id")
      id = "comment-pick-task_id"

      assert [%{label: "Search"} | _] = arguments(html, id)

      html = argue(view, id, a: %{"search" => "week"})
      assert column(html, id, "title") == ["This week"]

      html = picked(view, "comment", week.id)
      assert_reply view, %{ok: true}
      assert [_body, %{name: "task_id", chosen: "This week"}] = panel(html, "comment").fields
    end
  end

  describe "in German" do
    test "the labels of the line are the host's, as those of the columns are", %{
      conn: conn,
      world: world
    } do
      {:ok, _view, html} = conn |> log_in(world.admin) |> in_locale("de") |> live("/tasks")

      assert Enum.map(arguments(html, "task"), & &1.label) == ["Suche", "Fällig binnen: Tage"]
    end
  end
end
