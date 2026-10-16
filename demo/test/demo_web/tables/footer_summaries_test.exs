defmodule DemoWeb.Tables.FooterSummariesTest do
  @moduledoc """
  Footer summaries in mounted tables, on Postgres: the tasks at `/tasks`
  (the average progress, the sum of the estimates, the latest due date and
  the number of completed tasks), the tasks nested under a project, and
  the efforts of `test/support/summary_tables.ex`, which are the demo's
  tasks under policies that depend on the read action.

  A summary is asked for beside the rows: `render_async/2` waits for both.
  """
  use DemoWeb.ModeCase, async: true

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias AshDataTable.Model
  alias AshDataTable.Query
  alias AshDataTable.State
  alias Demo.Generator
  alias Demo.Support.Sums.Effort
  alias Demo.Tracker.Task

  # One task of the world's first organization, in its first project,
  # reported by the admin and assigned to nobody. Each is created a day
  # after `day`: the highest first.
  defp task(world, day, overrides) do
    [project | _] = world.projects

    Generator.generate(
      Generator.task(
        [
          organization_id: world.organization.id,
          project_id: project.id,
          reporter_id: world.admin.id,
          assignee_id: nil,
          title: "Task #{String.pad_leading("#{day}", 2, "0")}",
          description: nil,
          status: :in_progress,
          priority: :medium,
          progress: 40,
          estimate_hours: Decimal.new("12.5"),
          billable?: false,
          due_on: nil,
          completed_at: nil,
          external_ref: nil,
          internal_note: nil,
          inserted_at: DateTime.add(~U[2026-01-01 12:00:00.000000Z], day, :day)
        ] ++ overrides
      )
    )
  end

  # Three tasks: the member's own, one that is completed, and one without
  # an estimate and a due date.
  defp three(world) do
    [
      task(world, 3,
        progress: 40,
        estimate_hours: Decimal.new("12.5"),
        due_on: ~D[2026-03-01],
        assignee_id: world.member.id
      ),
      task(world, 2,
        progress: 60,
        estimate_hours: Decimal.new("7.5"),
        due_on: ~D[2026-05-01],
        completed_at: ~U[2026-02-01 10:00:00Z]
      ),
      task(world, 1, progress: 80, estimate_hours: nil, due_on: nil)
    ]
  end

  # The page once the rows and the summaries are there.
  defp open_table(conn, actor, path \\ "/tasks") do
    {:ok, view, _html} = conn |> log_in(actor) |> live(path)
    {view, render_async(view, 10_000)}
  end

  # A page of the tests' own tables, which find who is asking in an assign.
  defp open_support(conn, reader, path) do
    conn = Phoenix.ConnTest.init_test_session(conn, %{"assigns" => %{reader: reader}})
    {:ok, view, _html} = live(conn, path)
    {view, render_async(view, 10_000)}
  end

  # What the footer cell under a column says: the kind's name and the
  # number as text; `:unavailable` for the dash; nil for no number (yet).
  # Nil for a table without the cell, `:none` for a cell without a summary.
  defp footer(html, id \\ "task", field) do
    cell = "[id='#{id}-summary-#{field}']"

    cond do
      attribute(html, cell, "id") == [] ->
        nil

      attribute(html, cell, "data-summary") == [] ->
        :none

      attribute(html, cell <> " [data-summary-unavailable]", "data-summary-unavailable") != [] ->
        {text(html, cell <> " [data-summary-kind]"), :unavailable}

      true ->
        {text(html, cell <> " [data-summary-kind]"), text(html, cell <> " [data-summary-value]")}
    end
  end

  defp busy?(html, id \\ "task", field),
    do: attribute(html, "[id='#{id}-summary-#{field}']", "aria-busy") == ["true"]

  describe "the footer row" do
    setup %{conn: conn} do
      world = world(tasks: 0)
      %{world: world, tasks: three(world), conn: conn}
    end

    test "is one more row of the grid after the last record, with a cell under every column",
         %{conn: conn, world: world} do
      {_view, html} = open_table(conn, world.admin)

      assert attribute(html, "#task-table > tfoot", "id") == ["task-foot"]
      assert attribute(html, "#task-foot > tr", "id") == ["task-summaries"]
      assert attribute(html, "#task-summaries", "role") == ["row"]

      # three tasks, the two header rows, and this row: the last of all
      assert attribute(html, "#task-table", "aria-rowcount") == ["6"]
      assert attribute(html, "#task-summaries", "aria-rowindex") == ["6"]

      # a cell for every column of the grid, each a gridcell in its column's place
      assert attribute(html, "#task-summaries > td", "aria-colindex") ==
               attribute(html, "#task-head-row > th", "aria-colindex")

      assert html |> attribute("#task-summaries > td", "role") |> Enum.uniq() == ["gridcell"]
      assert html |> attribute("#task-summaries > td", "tabindex") |> Enum.uniq() == ["-1"]

      for field <- ~w(progress estimate_hours due_on completed_at) do
        assert attribute(html, "#task-summary-#{field}", "aria-colindex") ==
                 attribute(html, "#task-head-#{field}", "aria-colindex")
      end

      assert attribute(html, "#task-summaries > td[data-summary]", "id") == [
               "task-summary-progress",
               "task-summary-estimate_hours",
               "task-summary-due_on",
               "task-summary-completed_at"
             ]

      # under a column without a summary, and under the boxes, the
      # expanders and the actions, the cell is empty
      assert footer(html, "title") == :none
      assert text(html, "#task-summary-title") == ""
      assert text(html, "#task-summaries-select") == ""
      assert text(html, "#task-summaries-expander") == ""
      assert text(html, "#task-summaries-actions") == ""
    end

    test "says the kind before the number, the number as the column's cells show a value",
         %{conn: conn, world: world} do
      {_view, html} = open_table(conn, world.admin)

      assert footer(html, "progress") == {"Average", "60"}
      assert footer(html, "estimate_hours") == {"Sum", "20.0"}
      assert footer(html, "due_on") == {"Max", "2026-05-01"}
      assert footer(html, "completed_at") == {"Count", "1"}

      # read as one text: the name, a space, the number
      assert text(html, "#task-summary-progress") == "Average 60"
    end

    test "is there with the rows, and the numbers come when they are computed",
         %{conn: conn, world: world} do
      {:ok, view, html} = conn |> log_in(world.admin) |> live("/tasks")

      # the rows are there, and the cells of the summaries say that they are busy
      assert length(column(html, "task", "title")) == 3
      assert footer(html, "progress") == {"Average", nil}
      assert busy?(html, "progress")
      # a cell without a summary is never busy
      refute busy?(html, "title")

      html = render_async(view, 10_000)
      assert footer(html, "progress") == {"Average", "60"}
      refute busy?(html, "progress")
    end

    test "speaks the language of the page", %{conn: conn, world: world} do
      conn = conn |> log_in(world.viewer) |> in_locale("de")
      {:ok, view, _html} = live(conn, "/tasks")
      html = render_async(view, 10_000)

      assert footer(html, "progress") == {"Durchschnitt", "60"}
      assert footer(html, "completed_at") == {"Anzahl", "1"}
      assert footer(html, "due_on") == {"Max.", "2026-05-01"}

      assert text(html, "#task-summary-estimate_hours [data-summary-unavailable] .sr-only") ==
               "Nicht verfügbar"
    end

    test "a table without a summary has no footer row, and no footer", %{conn: conn, world: world} do
      {_view, html} = open_table(conn, world.admin, "/labels")

      assert attribute(html, "#label-table", "role") == ["grid"]
      assert attribute(html, "#label-table > tfoot", "id") == []
      assert attribute(html, "[data-summaries]", "id") == []
    end
  end

  describe "what a summary is over" do
    test "every task that matches, not the page", %{conn: conn} do
      world = world(tasks: 0)
      for day <- 1..30, do: task(world, day, progress: day, estimate_hours: Decimal.new(2))

      {view, html} = open_table(conn, world.admin)

      assert length(column(html, "task", "title")) == 25
      assert text(html, "#task-range") == "1–25 of 30"
      # of 1..30, and 30 times 2
      assert footer(html, "progress") == {"Average", "15.5"}
      assert footer(html, "estimate_hours") == {"Sum", "60"}
      assert footer(html, "completed_at") == {"Count", "0"}

      # the same on the second page
      view |> element("#task-next") |> render_click()
      html = render_async(view, 10_000)

      assert length(column(html, "task", "title")) == 5
      assert footer(html, "progress") == {"Average", "15.5"}
      assert footer(html, "estimate_hours") == {"Sum", "60"}
    end

    test "it follows the filters, and the argument of the read action", %{conn: conn} do
      world = world(tasks: 0)
      three(world)
      task(world, 4, title: "Write the report", progress: 10, estimate_hours: Decimal.new(1))

      {view, html} = open_table(conn, world.admin)
      assert footer(html, "estimate_hours") == {"Sum", "21.0"}

      html = filter(view, "task", "progress", o: "at_least", v: "60")
      assert column(html, "task", "title") == ["Task 02", "Task 01"]
      assert footer(html, "progress") == {"Average", "70"}
      assert footer(html, "estimate_hours") == {"Sum", "7.5"}
      assert footer(html, "due_on") == {"Max", "2026-05-01"}

      view |> element("#task-clear-filters") |> render_click()
      render_async(view, 10_000)

      html = argue(view, "task", a: %{"search" => "report"})
      assert column(html, "task", "title") == ["Write the report"]
      assert footer(html, "progress") == {"Average", "10"}
      assert footer(html, "estimate_hours") == {"Sum", "1"}
    end

    test "no record matches: a count of 0, and nothing for every other kind", %{conn: conn} do
      world = world(tasks: 0)
      three(world)

      {view, _html} = open_table(conn, world.admin)
      html = filter(view, "task", "title", v: "no such task")

      assert column(html, "task", "title") == []
      assert text(html, "#task-empty") == "No records"

      assert footer(html, "completed_at") == {"Count", "0"}
      assert footer(html, "progress") == {"Average", ""}
      assert footer(html, "estimate_hours") == {"Sum", ""}
      assert footer(html, "due_on") == {"Max", ""}
    end

    test "a change of the sort asks for nothing again; a filter does", %{conn: conn} do
      world = world(tasks: 0)
      three(world)

      {view, _html} = open_table(conn, world.admin)

      # the page as it is while the rows are on their way
      html = view |> element("#task-head-title") |> render_click()
      refute busy?(html, "progress")
      assert footer(html, "progress") == {"Average", "60"}
      render_async(view, 10_000)

      html =
        view
        |> form("#task-filters", %{"filter" => %{"title" => %{"v" => "Task 01"}}})
        |> render_change()

      # what was shown stays until the new number is there
      assert busy?(html, "progress")
      assert footer(html, "progress") == {"Average", "60"}

      html = render_async(view, 10_000)
      refute busy?(html, "progress")
      assert footer(html, "progress") == {"Average", "80"}
    end
  end

  describe "who is asking" do
    setup %{conn: conn} do
      world = world(tasks: 0, other_tasks: 0)
      %{world: world, tasks: three(world), conn: conn}
    end

    test "a field hidden from the person on some tasks has a dash, not a number over the rest",
         %{conn: conn, world: world} do
      # the member sees the estimate of the one task they are assigned to
      {_view, html} = open_table(conn, world.member)

      assert footer(html, "estimate_hours") == {"Sum", :unavailable}

      assert text(html, "#task-summary-estimate_hours [data-summary-unavailable] [aria-hidden]") ==
               "–"

      assert text(html, "#task-summary-estimate_hours [data-summary-unavailable] .sr-only") ==
               "Not available"

      # the cell holds no number, neither the 12.5 they see nor the 20 there are
      assert text(html, "#task-summary-estimate_hours") == "Sum –Not available"

      # what they see on every task is summed as for anybody
      assert footer(html, "progress") == {"Average", "60"}
      assert footer(html, "due_on") == {"Max", "2026-05-01"}
      assert footer(html, "completed_at") == {"Count", "1"}
    end

    test "Ash itself sums only the values the person may see", %{world: world} do
      # The model as the resource says it, for everybody: the estimate is
      # not marked as hidden in part, so it is asked for, as the member.
      model = Model.build(Task)

      assert {:ok, %{estimate_hours: {:ok, estimate}, progress: {:ok, progress}}} =
               Query.summaries(model, %State{}, nil, as(world.member))

      # their own 12.5, not the 20 of all
      assert Decimal.equal?(estimate, Decimal.new("12.5"))
      assert progress == 60.0

      assert {:ok, %{estimate_hours: {:ok, all}}} =
               Query.summaries(model, %State{}, nil, as(world.admin))

      assert Decimal.equal?(all, Decimal.new("20"))

      # and the model the member meets does not ask at all
      mine = Model.for_actor(model, as(world.member))

      assert {:ok, %{estimate_hours: :unavailable}} =
               Query.summaries(mine, %State{}, nil, as(world.member))
    end

    test "a person of another organization sees the numbers of their own", %{
      conn: conn,
      world: world
    } do
      [project | _] =
        Demo.Tracker.Project
        |> Ash.read!(authorize?: false)
        |> Enum.filter(&(&1.organization_id == world.other_organization.id))

      Generator.generate(
        Generator.task(
          organization_id: world.other_organization.id,
          project_id: project.id,
          reporter_id: world.outsider.id,
          assignee_id: world.outsider.id,
          progress: 7,
          estimate_hours: Decimal.new("99"),
          due_on: ~D[2030-01-01],
          completed_at: nil
        )
      )

      {_view, html} = open_table(conn, world.outsider)

      assert length(column(html, "task", "title")) == 1
      assert footer(html, "progress") == {"Average", "7"}
      assert footer(html, "due_on") == {"Max", "2030-01-01"}
      assert footer(html, "completed_at") == {"Count", "0"}

      # and the admin of the first organization none of theirs
      {_view, html} = open_table(conn, world.admin)
      assert footer(html, "progress") == {"Average", "60"}
      assert footer(html, "estimate_hours") == {"Sum", "20.0"}
      assert footer(html, "due_on") == {"Max", "2026-05-01"}
    end
  end

  describe "after the table has written" do
    setup %{conn: conn} do
      world = world(tasks: 0)
      tasks = three(world)
      {view, html} = open_table(conn, world.admin)
      %{world: world, tasks: tasks, view: view, html: html}
    end

    test "a saved cell: the old number stays, marked busy, until the new one is there",
         %{view: view, tasks: [first | _]} do
      html = save(view, first.id, "estimate_hours", "20")

      # the row is saved, and the summary is on its way
      assert text(html, cell(first.id, "estimate_hours")) =~ "20"
      assert busy?(html, "estimate_hours")
      assert footer(html, "estimate_hours") == {"Sum", "20.0"}

      html = render_async(view, 10_000)
      refute busy?(html, "estimate_hours")
      assert footer(html, "estimate_hours") == {"Sum", "27.5"}
    end

    test "a row action that changes a record, and one that destroys it", %{
      view: view,
      tasks: [first, second, _third]
    } do
      act(view, second.id, "destroy")
      html = render_async(view, 10_000)

      assert length(column(html, "task", "title")) == 2
      assert footer(html, "progress") == {"Average", "60"}
      assert footer(html, "estimate_hours") == {"Sum", "12.5"}
      assert footer(html, "due_on") == {"Max", "2026-03-01"}
      assert footer(html, "completed_at") == {"Count", "0"}
      # one record less, and the footer row is still the last row
      assert attribute(html, "#task-table", "aria-rowcount") == ["5"]
      assert attribute(html, "#task-summaries", "aria-rowindex") == ["5"]

      save(view, first.id, "progress", "100")
      html = render_async(view, 10_000)
      assert footer(html, "progress") == {"Average", "90"}
    end

    test "a created record", %{view: view, world: world} do
      open_create(view)
      run_panel(view, title: "Brand new", progress: "0", project_id: hd(world.projects).id)
      html = render_async(view, 10_000)

      assert hd(column(html, "task", "title")) == "Brand new"
      # of 40, 60, 80 and 0
      assert footer(html, "progress") == {"Average", "45"}
      assert attribute(html, "#task-summaries", "aria-rowindex") == ["7"]
    end

    test "an action on the selected rows", %{view: view, tasks: [first, second, _third]} do
      # the page once the action has run and the table has read again: the
      # summaries are asked for with that read, and waited for with it
      html = run_bulk(view, "destroy", [first.id, second.id])
      refute busy?(html, "progress")

      assert column(html, "task", "title") == ["Task 01"]
      assert footer(html, "progress") == {"Average", "80"}
      assert footer(html, "estimate_hours") == {"Sum", ""}
      assert footer(html, "due_on") == {"Max", ""}
    end

    test "the selection does not change the numbers", %{view: view, tasks: [first | _]} do
      # what a person has selected is the hook's; the server hears of it
      # when a button is used, and the numbers stay those of all that match
      html = bulk(view, "archive", [first.id])
      assert footer(html, "progress") == {"Average", "60"}
      refute busy?(html, "progress")
    end
  end

  describe "live updates" do
    test "what another person changes is summed again, once the table has heard of it", %{
      conn: conn
    } do
      world = world(tasks: 0)
      [first, _second, _third] = three(world)

      {view, html} = open_table(conn, world.admin)
      assert footer(html, "progress") == {"Average", "60"}

      Ash.update!(first, %{progress: 100}, [action: :set_progress] ++ as(world.member))
      AshDataTable.Test.flush(view)
      html = render_async(view, 10_000)

      assert text(html, cell(first.id, "progress")) =~ "100"
      assert footer(html, "progress") == {"Average", "80"}
    end
  end

  describe "a nested table" do
    test "sums the records of its row", %{conn: conn} do
      world = world(tasks: 0)
      [project, other | _] = world.projects
      three(world)
      task(world, 9, project_id: other.id, progress: 0, estimate_hours: Decimal.new("100"))

      {view, html} = open_table(conn, world.admin, "/projects")
      # the table of the projects declares no summary
      assert attribute(html, "#project-table > tfoot", "id") == []

      expand(view, "project", project.id)
      toggle(view, "project", project.id, "tasks")
      html = render_async(view, 10_000)
      id = nested("project", project.id, "tasks")

      assert length(column(html, id, "title")) == 3
      assert attribute(html, "[id='#{id}-foot'] > tr:first-child", "id") == ["#{id}-summaries"]
      assert footer(html, id, "progress") == {"Average", "60"}
      assert footer(html, id, "estimate_hours") == {"Sum", "20.0"}
      assert footer(html, id, "due_on") == {"Max", "2026-05-01"}
      assert footer(html, id, "completed_at") == {"Count", "1"}

      # the other project's one task
      expand(view, "project", other.id)
      toggle(view, "project", other.id, "tasks")
      html = render_async(view, 10_000)
      id = nested("project", other.id, "tasks")

      assert footer(html, id, "progress") == {"Average", "0"}
      assert footer(html, id, "estimate_hours") == {"Sum", "100"}
    end

    test "as the person: a dash for what they see in part", %{conn: conn} do
      world = world(tasks: 0)
      [project | _] = world.projects
      three(world)

      {view, _html} = open_table(conn, world.member, "/projects")
      expand(view, "project", project.id)
      toggle(view, "project", project.id, "tasks")
      html = render_async(view, 10_000)
      id = nested("project", project.id, "tasks")

      assert footer(html, id, "estimate_hours") == {"Sum", :unavailable}
      assert footer(html, id, "progress") == {"Average", "60"}
    end
  end

  describe "a picker" do
    test "shows the summaries of the table it offers records from", %{conn: conn} do
      world = world(tasks: 0)
      three(world)

      # "New comment": its task is chosen from the table of the tasks
      {view, html} = open_table(conn, world.admin, "/comments")
      assert attribute(html, "#comment-table > tfoot", "id") == []

      open_create(view, "comment")
      pick_input(view, "comment", "task_id")
      html = render_async(view, 10_000)
      id = "comment-pick-task_id"

      assert length(column(html, id, "title")) == 3
      assert footer(html, id, "progress") == {"Average", "60"}
      assert footer(html, id, "estimate_hours") == {"Sum", "20.0"}
    end
  end

  describe "field policies that depend on the read action" do
    # Efforts are the demo's tasks. Through `:board`, the default table's
    # read action, a person sees the estimate of their own efforts only and
    # the progress of all; through `:read`, the primary read action, it is
    # the other way round.
    setup %{conn: conn} do
      world = world(tasks: 0, other_tasks: 0)
      three(world)
      task(world, 0, title: "Sealed", progress: 100, estimate_hours: Decimal.new("1000"))
      %{world: world, conn: conn}
    end

    test "a table that reads through another action than the primary one", %{
      conn: conn,
      world: world
    } do
      {_view, html} = open_support(conn, world.member, "/support/efforts")

      # two to a page, of the three the member reads
      assert column(html, "effort", "title") == ["Task 01", "Task 02"]
      assert text(html, "#effort-range") == "1–2 of 3"

      assert footer(html, "effort", "title") == {"Count", "3"}
      # seen on their own effort only, through this action: no number
      assert footer(html, "effort", "estimate_hours") == {"Sum", :unavailable}
      # seen on every effort, through this action
      assert footer(html, "effort", "progress") == {"Max", "80"}
    end

    test "the same resource through its primary read action", %{conn: conn, world: world} do
      {_view, html} = open_support(conn, world.member, "/support/efforts/primary")

      assert footer(html, "effort_primary", "estimate_hours") == {"Sum", "20.0"}
      assert footer(html, "effort_primary", "progress") == {"Average", :unavailable}
    end

    test "Ash is asked about the fields as the table's own read action meets them", %{
      world: world
    } do
      reader = [actor: world.member]

      # through `:board`: the member's own estimate (12.5), not the 20 that
      # the field policies of the primary read action would let through
      assert {:ok, %{title: {:ok, 3}, estimate_hours: {:ok, estimate}, progress: {:ok, 80}}} =
               Query.summaries(Model.build(Effort), %State{}, nil, reader)

      assert Decimal.equal?(estimate, Decimal.new("12.5"))

      # through `:read`: every estimate, and the progress of their own effort
      assert {:ok, %{estimate_hours: {:ok, estimate}, progress: {:ok, progress}}} =
               Query.summaries(Model.build(Effort, table: :primary), %State{}, nil, reader)

      assert Decimal.equal?(estimate, Decimal.new("20"))
      assert progress == 40.0
    end

    test "a page mounted without authorization sums everything, as it reads everything", %{
      conn: conn
    } do
      {_view, html} = open_support(conn, nil, "/support/open/efforts")

      assert text(html, "#effort-range") == "1–2 of 4"
      assert footer(html, "effort", "title") == {"Count", "4"}
      assert footer(html, "effort", "estimate_hours") == {"Sum", "1020.0"}
      assert footer(html, "effort", "progress") == {"Max", "100"}
    end

    test "nobody reads no effort, and is told no number of any", %{conn: conn} do
      {_view, html} = open_support(conn, nil, "/support/efforts")

      assert column(html, "effort", "title") == []
      assert footer(html, "effort", "title") == {"Count", "0"}
      # the estimate is never theirs to see: no column, and so no cell
      assert footer(html, "effort", "estimate_hours") == nil
      assert footer(html, "effort", "progress") == {"Max", ""}
    end
  end

  describe "an argument that the read action requires" do
    setup %{conn: conn} do
      world = world(tasks: 0, other_tasks: 0)
      three(world)
      %{world: world, conn: conn}
    end

    test "while it is empty nothing is read, and there is no footer row", %{
      conn: conn,
      world: world
    } do
      {view, html} = open_support(conn, world.admin, "/support/efforts/above")

      assert text(html, "#effort_above-fill") == "Fill in Least to see records."
      assert attribute(html, "#effort_above-summaries", "id") == []
      assert footer(html, "effort_above", "progress") == nil

      html = argue(view, "effort_above", a: %{"least" => "50"})

      assert column(html, "effort_above", "title") == ["Task 01", "Task 02"]
      # of 60 and 80
      assert footer(html, "effort_above", "progress") == {"Sum", "140"}

      html = argue(view, "effort_above", a: %{"least" => "70"})
      assert footer(html, "effort_above", "progress") == {"Sum", "80"}

      # emptied again: the rows go, and the number with them
      html = argue(view, "effort_above", a: %{"least" => ""})
      assert text(html, "#effort_above-fill") == "Fill in Least to see records."
      assert footer(html, "effort_above", "progress") == nil
    end
  end

  describe "a summary that cannot be computed" do
    test "says so in its cell and in the log, and the rows are as they are", %{conn: conn} do
      world = world(tasks: 0, other_tasks: 0)
      three(world)

      {result, log} =
        with_log(fn -> open_support(conn, world.admin, "/support/efforts/broken") end)

      {_view, html} = result

      assert column(html, "effort_broken", "title") == ["Task 01", "Task 02"]
      assert text(html, "#effort_broken-range") == "1–2 of 3"
      assert attribute(html, "#effort_broken-error", "id") == []

      assert footer(html, "effort_broken", "ghost") == {"Sum", :unavailable}
      refute busy?(html, "effort_broken", "ghost")

      assert log =~
               "ash_data_table: the summaries of the table of Demo.Support.Sums.Effort could not be computed"
    end
  end
end
