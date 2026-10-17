defmodule DemoWeb.Tables.TimeZoneTest do
  @moduledoc """
  The time zone of the page: a mounted table in the zone of the socket
  assign its domain names (which the demo's `DemoWeb.Zone` takes from the
  browser, and a test from the LiveView's connect params), a table placed
  with `time_zone`, and none: UTC, as before.

  What is shown, what a typed wall time is stored as, and what a filter
  finds, in Europe/Berlin around both changes of its clocks in 2026:
  2026-03-29 has 23 hours there (02:00 CET is 03:00 CEST), 2026-10-25 has
  25 (03:00 CEST is 02:00 CET). Every instant is fixed.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator
  alias Demo.Tracker.Task

  @berlin "Europe/Berlin"

  defp task(world, title, completed_at) do
    [project | _] = world.projects

    Generator.generate(
      Generator.task(
        organization_id: world.organization.id,
        project_id: project.id,
        reporter_id: world.admin.id,
        title: title,
        status: :done,
        completed_at: completed_at,
        inserted_at: ~U[2026-01-01 12:00:00.000000Z]
      )
    )
  end

  # when the task was completed, as it is stored
  defp stored(task), do: Ash.get!(Task, task.id, authorize?: false).completed_at

  # the zone the browser says it is in, as `assets/js/app.js` sends it
  defp in_zone(conn, zone), do: put_connect_params(conn, %{"time_zone" => zone})

  defp shown(html, id \\ "task", task), do: text(html, cell(id, task.id, "completed_at"))

  setup do
    world = world(tasks: 0, other_tasks: 0)
    %{world: world, task: task(world, "Summer", ~U[2026-07-15 12:00:00Z])}
  end

  describe "a page that gives no zone" do
    test "shows, saves and filters in UTC, as before there were zones", %{
      conn: conn,
      world: world,
      task: task
    } do
      {:ok, view, html} = conn |> log_in(world.admin) |> live("/tasks")

      assert shown(html, task) == "2026-07-15T12:00:00"
      # in UTC the page looks as before: it says no zone
      assert attribute(html, "#time-zone", "id") == []

      save(view, task.id, "completed_at", "2026-07-15T14:00")
      assert stored(task) == ~U[2026-07-15 14:00:00Z]
    end

    test "a zone the browser names that the database does not know is UTC", %{
      conn: conn,
      world: world,
      task: task
    } do
      {:ok, _view, html} =
        conn |> log_in(world.admin) |> in_zone("Mars/Olympus") |> live("/tasks")

      assert shown(html, task) == "2026-07-15T12:00:00"
      # in UTC the page looks as before: it says no zone
      assert attribute(html, "#time-zone", "id") == []
    end
  end

  describe "a mounted table in the zone of its assign" do
    setup %{conn: conn, world: world} do
      {:ok, view, html} = conn |> log_in(world.admin) |> in_zone(@berlin) |> live("/tasks")
      %{view: view, html: html}
    end

    # (its editor holds what the cell shows)
    test "shows a datetime as the clocks there show it", %{html: html, task: task} do
      assert shown(html, task) == "2026-07-15T14:00:00"
      # the page says the zone once; the cells do not
      assert text(html, "#time-zone") == "Times in Europe/Berlin"
    end

    test "saves what is typed as the instant it is there, and shows it back as typed", %{
      view: view,
      task: task
    } do
      html = save(view, task.id, "completed_at", "2026-07-15T16:30")
      assert stored(task) == ~U[2026-07-15 14:30:00Z]
      assert shown(html, task) == "2026-07-15T16:30:00"
      assert failure(html, task.id, "completed_at") == nil

      # in winter the clocks there are an hour ahead of UTC, not two
      save(view, task.id, "completed_at", "2026-01-15T09:00:00")
      assert stored(task) == ~U[2026-01-15 08:00:00Z]
    end

    test "a time that is there twice is the earlier one", %{view: view, task: task} do
      save(view, task.id, "completed_at", "2026-10-25T02:30")
      assert stored(task) == ~U[2026-10-25 00:30:00Z]
    end

    test "a time the clocks skip is not saved, and the cell says why", %{view: view, task: task} do
      html = save(view, task.id, "completed_at", "2026-03-29T02:30")

      assert stored(task) == ~U[2026-07-15 12:00:00Z]

      assert failure(html, task.id, "completed_at") == %{
               shown: "2026-03-29T02:30",
               message: "This time does not exist in Europe/Berlin."
             }
    end

    test "the value the cell holds already saves nothing", %{view: view, task: task} do
      html = save(view, task.id, "completed_at", "2026-07-15T14:00:00")
      assert stored(task) == ~U[2026-07-15 12:00:00Z]
      assert failure(html, task.id, "completed_at") == nil
    end
  end

  describe "a filter in a zone" do
    setup %{conn: conn, world: world} do
      # around the night the clocks go forward: 2026-03-29 is from
      # 2026-03-28T23:00Z to 2026-03-29T22:00Z there
      for {title, at} <- [
            {"Before", ~U[2026-03-28 22:59:59Z]},
            {"First", ~U[2026-03-28 23:00:00Z]},
            {"Gap", ~U[2026-03-29 01:00:00Z]},
            {"Last", ~U[2026-03-29 21:59:59Z]},
            {"After", ~U[2026-03-29 22:00:00Z]}
          ],
          do: task(world, title, at)

      %{conn: log_in(conn, world.admin)}
    end

    defp titles(html), do: html |> column("task", "title") |> Enum.sort()

    defp between(view, from, to) do
      filter(view, "task", "completed_at", o: "between")
      filter(view, "task", "completed_at", o: "between", from: from, to: to)
    end

    test "between the first and the last moment of a day is that day there", %{conn: conn} do
      {:ok, view, _html} = conn |> in_zone(@berlin) |> live("/tasks")
      html = between(view, "2026-03-29T00:00", "2026-03-29T23:59:59")

      assert titles(html) == ["First", "Gap", "Last"]
      # the URL holds what was typed: a link means that wall time wherever it is opened
      assert attribute(html, "#task-filter-completed_at input", "value") ==
               ["2026-03-29T00:00", "2026-03-29T23:59:59"]
    end

    test "the same day in UTC is another one", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/tasks")
      html = between(view, "2026-03-29T00:00", "2026-03-29T23:59:59")

      assert titles(html) == ["After", "Gap", "Last"]
    end

    test "before and after a wall time there", %{conn: conn} do
      {:ok, view, _html} = conn |> in_zone(@berlin) |> live("/tasks")

      assert titles(filter(view, "task", "completed_at", o: "before", v: "2026-03-29T00:00")) ==
               ["Before"]

      assert titles(filter(view, "task", "completed_at", o: "after", v: "2026-03-29T03:00")) ==
               ["After", "Last", "Summer"]
    end
  end

  describe "a mounted table whose domain names another assign" do
    defp booking_page(conn, zone) do
      conn
      |> Phoenix.ConnTest.init_test_session(%{"assigns" => %{zone: zone}})
      |> live("/support/bookings")
    end

    test "is in the zone of that assign", %{conn: conn, task: task} do
      {:ok, _view, html} = booking_page(conn, @berlin)
      assert shown(html, "booking", task) == "2026-07-15T14:00:00"
    end

    test "its action panel shows the time there and saves what is typed as the instant it is",
         %{conn: conn, task: task} do
      {:ok, view, _html} = booking_page(conn, @berlin)

      html = act(view, "booking", task.id, "reschedule")

      assert [%{name: "completed_at", value: "2026-07-15T14:00:00"}] =
               panel(html, "booking").fields

      # what is typed stays as it was typed while the panel is open
      html = type_in_panel(view, "booking", completed_at: "2026-12-24T18:00")
      assert [%{value: "2026-12-24T18:00"}] = panel(html, "booking").fields

      html = run_panel(view, "booking", completed_at: "2026-12-24T18:00")
      assert panel(html, "booking") == nil
      assert stored(task) == ~U[2026-12-24 17:00:00Z]
      assert shown(html, "booking", task) == "2026-12-24T18:00:00"
    end

    test "a time the clocks skip runs nothing, and its field says why", %{conn: conn, task: task} do
      {:ok, view, _html} = booking_page(conn, @berlin)
      act(view, "booking", task.id, "reschedule")

      html = run_panel(view, "booking", completed_at: "2026-03-29T02:15")

      assert [
               %{
                 value: "2026-03-29T02:15",
                 errors: ["This time does not exist in Europe/Berlin."]
               }
             ] =
               panel(html, "booking").fields

      assert stored(task) == ~U[2026-07-15 12:00:00Z]
    end

    test "a name that is no zone is an error that names the assign", %{conn: conn} do
      error = assert_raise ArgumentError, fn -> booking_page(conn, "Mars/Olympus") end

      assert error.message =~
               "The socket assign `:zone` (the `time_zone_assign` of the domain of " <>
                 "Demo.Support.Zones.Booking) is \"Mars/Olympus\""
    end
  end

  describe "a footer summary of a datetime" do
    test "says it in the zone of the page, and again when the zone changes", %{conn: conn} do
      {:ok, view, _html} =
        live_isolated(conn, DemoWeb.Support.ZonedSumLive, session: %{"zone" => "Etc/UTC"})

      # the summary is computed beside the rows
      html = render_async(view)
      assert text(html, "[id='booking_summed-summary-completed_at']") =~ "2026-07-15T12:00:00"

      html = render_hook(view, "zone", %{"zone" => @berlin})
      assert text(html, "[id='booking_summed-summary-completed_at']") =~ "2026-07-15T14:00:00"
    end
  end

  describe "a placed table" do
    test "is in the zone it is given", %{conn: conn, world: world, task: task} do
      {:ok, view, html} = conn |> log_in(world.admin) |> in_zone(@berlin) |> live("/dashboard")

      assert shown(html, "dashboard-tasks", task) == "2026-07-15T14:00:00"

      save(view, "dashboard-tasks", task.id, "completed_at", "2026-07-15T18:00")
      assert stored(task) == ~U[2026-07-15 16:00:00Z]
    end
  end
end
