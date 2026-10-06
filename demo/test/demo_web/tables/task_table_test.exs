defmodule DemoWeb.Tables.TaskTableTest do
  @moduledoc """
  The mounted table of `Demo.Tracker.Task`, as a person meets it at `/tasks`:
  a table with a declared set of columns.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator

  # Tasks of the world's first organization with the titles given, each
  # created a day after the one before it, so the last one is the newest.
  defp tasks_titled(world, titles, overrides \\ []) do
    [project | _] = world.projects

    for {title, index} <- Enum.with_index(titles) do
      Generator.generate(
        Generator.task(
          [
            organization_id: world.organization.id,
            project_id: project.id,
            reporter_id: world.admin.id,
            title: title,
            inserted_at: DateTime.add(~U[2026-01-01 12:00:00.000000Z], index, :day)
          ] ++ overrides
        )
      )
    end
  end

  describe "opening the page" do
    test "shows the declared columns in the declared order, with their labels", %{conn: conn} do
      world = world(tasks: 0)

      {:ok, _view, html} = conn |> log_in(world.admin) |> live("/tasks")

      assert headers(html, "task") == [
               "Title",
               "State",
               "Priority",
               "Progress",
               "Estimate hours",
               "Billable?",
               "Due on",
               "Completed at",
               "Overdue?",
               "Comments",
               "Headline",
               "External ref",
               "Description",
               "Inserted at"
             ]
    end

    test "shows the first page of tasks, newest first as the read action sorts them",
         %{conn: conn} do
      world = world(tasks: 0)
      tasks_titled(world, ["Oldest task", "Middle task", "Newest task"])

      {:ok, _view, html} = conn |> log_in(world.admin) |> live("/tasks")

      assert column(html, "task", "title") == ["Newest task", "Middle task", "Oldest task"]
    end
  end

  describe "sorting" do
    setup %{conn: conn} do
      world = world(tasks: 0)
      # without a due date none of them is overdue
      tasks_titled(world, ["Cherry", "Apple", "Banana"], due_on: nil)
      %{world: world, conn: log_in(conn, world.admin)}
    end

    test "a click on a header sorts ascending, a second descending, a third not at all",
         %{conn: conn} do
      {:ok, view, html} = live(conn, "/tasks")

      assert column(html, "task", "title") == ["Banana", "Apple", "Cherry"]
      assert attribute(html, "#task-head-title", "aria-sort") == ["none"]

      view |> element("#task-head-title") |> render_click()
      assert_patch(view, "/tasks?task[sort]=title")
      html = render_async(view)

      assert column(html, "task", "title") == ["Apple", "Banana", "Cherry"]
      assert attribute(html, "#task-head-title", "aria-sort") == ["ascending"]

      view |> element("#task-head-title") |> render_click()
      assert_patch(view, "/tasks?task[sort]=-title")
      html = render_async(view)

      assert column(html, "task", "title") == ["Cherry", "Banana", "Apple"]
      assert attribute(html, "#task-head-title", "aria-sort") == ["descending"]

      view |> element("#task-head-title") |> render_click()
      assert_patch(view, "/tasks")
      html = render_async(view)

      assert column(html, "task", "title") == ["Banana", "Apple", "Cherry"]
      assert attribute(html, "#task-head-title", "aria-sort") == ["none"]
    end

    test "only one column is sorted at a time", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/tasks")

      view |> element("#task-head-title") |> render_click()
      render_async(view)
      view |> element("#task-head-progress") |> render_click()
      assert_patch(view, "/tasks?task[sort]=progress")
      html = render_async(view)

      assert attribute(html, "#task-head-title", "aria-sort") == ["none"]
      assert attribute(html, "#task-head-progress", "aria-sort") == ["ascending"]
    end

    test "a column declared `sortable? false`, and one the resource cannot sort, offer no sort",
         %{conn: conn} do
      {:ok, _view, html} = live(conn, "/tasks")

      for field <- ["description", "headline"] do
        assert attribute(html, "#task-head-#{field}", "aria-sort") == []
        assert attribute(html, "#task-head-#{field}", "phx-click") == []
      end
    end

    test "an aggregate column sorts by the aggregate", %{conn: conn, world: world} do
      [cherry, apple, _banana] =
        Demo.Tracker.Task |> Ash.read!(as(world.admin)) |> Enum.sort_by(& &1.inserted_at)

      comment = [organization_id: world.organization.id, author_id: world.admin.id]
      Generator.generate_many(Generator.comment([task_id: cherry.id] ++ comment), 2)
      Generator.generate(Generator.comment([task_id: apple.id] ++ comment))

      {:ok, view, _html} = live(conn, "/tasks")
      view |> element("#task-head-comment_count") |> render_click()
      assert_patch(view, "/tasks?task[sort]=comment_count")
      html = render_async(view)

      assert column(html, "task", "title") == ["Banana", "Apple", "Cherry"]
      assert column(html, "task", "comment_count") == ["0", "1", "2"]

      view |> element("#task-head-comment_count") |> render_click()
      html = render_async(view)

      assert column(html, "task", "comment_count") == ["2", "1", "0"]
    end

    test "an expression calculation column sorts by the calculation", %{conn: conn, world: world} do
      tasks_titled(world, ["Late"], due_on: Date.add(Date.utc_today(), -3), status: :todo)

      {:ok, view, _html} = live(conn, "/tasks")
      view |> element("#task-head-overdue\\?") |> render_click()
      render_async(view)
      view |> element("#task-head-overdue\\?") |> render_click()
      assert_patch(view, "/tasks?task[sort]=-overdue%3F")
      html = render_async(view)

      assert column(html, "task", "title") == ["Late", "Banana", "Apple", "Cherry"]
      assert column(html, "task", "overdue?") == ["✓Yes", "–No", "–No", "–No"]
    end
  end

  describe "paging" do
    setup %{conn: conn} do
      world = world(tasks: 0)
      titles = for n <- 1..60, do: "Task " <> String.pad_leading("#{n}", 2, "0")
      tasks_titled(world, titles)
      %{world: world, conn: log_in(conn, world.admin)}
    end

    defp titles(range), do: for(n <- range, do: "Task " <> String.pad_leading("#{n}", 2, "0"))

    test "the first page holds 25 rows and says where it is in the total", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/tasks")

      assert column(html, "task", "title") == titles(60..36//-1)
      assert text(html, "#task-range") == "1–25 of 60"
      # 60 tasks and the two header rows
      assert attribute(html, "#task-table", "aria-rowcount") == ["62"]
      assert attribute(html, "#task-previous", "disabled") == [""]
      assert attribute(html, "#task-next", "disabled") == []
      assert attribute(html, "#task-pagination [aria-current=page]", "id") == ["task-page-1"]
    end

    test "rows are numbered through all pages, the header being row 1 and the filter row 2",
         %{conn: conn} do
      {:ok, view, html} = live(conn, "/tasks")

      assert attribute(html, "#task-head-row", "aria-rowindex") == ["1"]
      assert attribute(html, "#task-filter-row", "aria-rowindex") == ["2"]
      assert attribute(html, "#task-table tbody tr", "aria-rowindex") == Enum.map(3..27, &"#{&1}")

      view |> element("#task-next") |> render_click()
      html = render_async(view)

      assert attribute(html, "#task-table tbody tr", "aria-rowindex") ==
               Enum.map(28..52, &"#{&1}")
    end

    test "next, a page number and previous move through the pages", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/tasks")

      view |> element("#task-next") |> render_click()
      assert_patch(view, "/tasks?task[page]=2")
      html = render_async(view)

      assert column(html, "task", "title") == titles(35..11//-1)
      assert text(html, "#task-range") == "26–50 of 60"

      view |> element("#task-page-3") |> render_click()
      assert_patch(view, "/tasks?task[page]=3")
      html = render_async(view)

      assert column(html, "task", "title") == titles(10..1//-1)
      assert text(html, "#task-range") == "51–60 of 60"
      assert attribute(html, "#task-next", "disabled") == [""]
      assert attribute(html, "#task-pagination [aria-current=page]", "id") == ["task-page-3"]

      view |> element("#task-previous") |> render_click()
      assert_patch(view, "/tasks?task[page]=2")
      html = render_async(view)

      assert column(html, "task", "title") == titles(35..11//-1)

      view |> element("#task-page-1") |> render_click()
      assert_patch(view, "/tasks")
      assert column(render_async(view), "task", "title") == titles(60..36//-1)
    end

    test "sorting returns to the first page and keeps the sort while paging", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/tasks?task[page]=2")

      view |> element("#task-head-title") |> render_click()
      assert_patch(view, "/tasks?task[sort]=title")
      assert column(render_async(view), "task", "title") == titles(1..25)

      view |> element("#task-next") |> render_click()
      assert_patch(view, "/tasks?task[page]=2&task[sort]=title")
      assert column(render_async(view), "task", "title") == titles(26..50)
    end
  end

  describe "the URL" do
    setup %{conn: conn} do
      world = world(tasks: 0)
      titles = for n <- 1..30, do: "Task " <> String.pad_leading("#{n}", 2, "0")
      tasks_titled(world, titles)
      %{world: world, conn: log_in(conn, world.admin)}
    end

    test "opened afresh, the URL a person reached by sorting and paging shows the same rows",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, "/tasks")

      view |> element("#task-head-title") |> render_click()
      assert_patch(view, "/tasks?task[sort]=title")
      render_async(view)
      view |> element("#task-next") |> render_click()
      url = assert_patch(view)
      reached = render_async(view)

      {:ok, _view, opened} = live(conn, url)

      assert url == "/tasks?task[page]=2&task[sort]=title"
      assert column(opened, "task", "title") == titles(26..30)
      assert column(opened, "task", "title") == column(reached, "task", "title")
      assert attribute(opened, "#task-head-title", "aria-sort") == ["ascending"]
      assert text(opened, "#task-range") == "26–30 of 30"
    end

    test "parameters that mean nothing to the table are ignored", %{conn: conn} do
      for query <- [
            "task[sort]=no_such_column",
            "task[sort]=description",
            "task[sort]=internal_note",
            "task[page]=zero",
            "task[page]=-1",
            "task[after]=abc",
            "task=1",
            "task[sort][]=title"
          ] do
        {:ok, _view, html} = live(conn, "/tasks?" <> query)

        assert column(html, "task", "title") == titles(30..6//-1), query
        assert attribute(html, "#task-table [aria-sort]:not([aria-sort=none])", "id") == [], query
      end
    end

    test "a page beyond the last shows no records", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/tasks?task[page]=9")

      assert column(html, "task", "title") == []
      assert text(html, "#task-empty") == "No records"
    end

    test "parameters of the page that are not the table's are kept", %{conn: conn} do
      {:ok, view, html} = live(conn, "/tasks?utm=mail&other[a]=1&task[page]=2")

      assert column(html, "task", "title") == titles(5..1//-1)

      view |> element("#task-head-title") |> render_click()

      assert_patch(view, "/tasks?other[a]=1&task[sort]=title&utm=mail")
    end
  end

  describe "who is reading" do
    setup do
      world = world(tasks: 0, other_tasks: 0)
      tasks_titled(world, ["Acme one", "Acme two"])
      [project] = Enum.take(Ash.read!(Demo.Tracker.Project, as(world.outsider)), 1)

      Generator.generate(
        Generator.task(
          organization_id: world.other_organization.id,
          project_id: project.id,
          reporter_id: world.outsider.id,
          title: "Globex one"
        )
      )

      %{world: world}
    end

    test "the admin and a member see the tasks of their organization only",
         %{conn: conn, world: world} do
      for actor <- [world.admin, world.member, world.viewer] do
        {:ok, _view, html} = conn |> log_in(actor) |> live("/tasks")

        assert column(html, "task", "title") == ["Acme two", "Acme one"]
        assert text(html, "#task-range") == "1–2 of 2"
      end
    end

    test "the outsider sees the tasks of the other organization only",
         %{conn: conn, world: world} do
      {:ok, _view, html} = conn |> log_in(world.outsider) |> live("/tasks")

      assert column(html, "task", "title") == ["Globex one"]
    end

    test "nobody sees no records", %{conn: conn, world: world} do
      {:ok, _view, html} = conn |> log_in(world.nobody) |> live("/tasks")

      assert column(html, "task", "title") == []
      assert text(html, "#task-empty") == "No records"
      assert text(html, "#task-error") == nil
    end

    test "the read runs authorized, as the actor, in the actor's tenant",
         %{conn: conn, world: world} do
      test = self()
      handler = "read-#{inspect(test)}"

      :telemetry.attach(
        handler,
        [:ash, :tracker, :read, :start],
        fn _event, _measurements, metadata, _config -> send(test, {:read, metadata}) end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler) end)

      {:ok, _view, _html} = conn |> log_in(world.member) |> live("/tasks")

      member_id = world.member.id
      tenant = world.organization.id

      assert_receive {:read,
                      %{
                        resource_short_name: :task,
                        action: :read,
                        tenant: ^tenant,
                        actor: %{id: ^member_id},
                        authorize?: true
                      }}
    end
  end

  describe "fields a field policy hides" do
    setup do
      world = world(tasks: 0)
      common = [external_ref: "EXT-SECRET-1", due_on: nil]

      tasks_titled(world, ["Mine"], [assignee_id: world.member.id, estimate_hours: 7.5] ++ common)
      tasks_titled(world, ["Not mine"], [assignee_id: nil, estimate_hours: 9.25] ++ common)

      %{world: world}
    end

    test "an admin sees them", %{conn: conn, world: world} do
      {:ok, _view, html} = conn |> log_in(world.admin) |> live("/tasks")

      assert column(html, "task", "title") == ["Not mine", "Mine"]
      assert column(html, "task", "external_ref") == ["EXT-SECRET-1", "EXT-SECRET-1"]
      assert column(html, "task", "estimate_hours") == ["9.25", "7.5"]
    end

    # What a person can never see has no column for them: see
    # `DemoWeb.Tables.TaskAuthorizationTest`.
    test "a member is not shown a field they can never see", %{conn: conn, world: world} do
      {:ok, _view, html} = conn |> log_in(world.member) |> live("/tasks")

      assert column(html, "task", "title") == ["Not mine", "Mine"]
      refute html =~ "EXT-SECRET-1"
      assert column(html, "task", "external_ref") == []
    end

    test "a member sees a field hidden per record only on their own task",
         %{conn: conn, world: world} do
      {:ok, _view, html} = conn |> log_in(world.member) |> live("/tasks")

      refute html =~ "9.25"
      assert column(html, "task", "estimate_hours") == ["Not available", "7.5"]
    end

    test "the placeholder for a hidden field is text for screen readers only",
         %{conn: conn, world: world} do
      {:ok, _view, html} = conn |> log_in(world.member) |> live("/tasks")

      assert attribute(html, "#task-table td[id$='-c-estimate_hours'] > span", "class") ==
               ["sr-only"]
    end
  end
end
