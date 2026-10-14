defmodule DemoWeb.Tables.TaskAuthorizationTest do
  @moduledoc """
  What the mounted table of `Demo.Tracker.Task` at `/tasks` shows and lets
  edit, person by person.

  `external_ref` is seen by admins only, whatever the task. `estimate_hours`
  is seen by admins, and by a task's own assignee. An admin may run every
  update action, a viewer none, and a member only on the tasks they are
  assigned to or reported.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator
  alias Demo.Tracker.Task

  @headers [
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
    "Due within 7 days",
    "Due within",
    "External ref",
    "Description",
    "Tags",
    "Checks",
    "Repeats",
    "Inserted at",
    "Project",
    "Assignee",
    "Reported by"
  ]

  # The columns that show a related record, which are left out for a person
  # who can never read its resource: a viewer may not read people, and
  # nobody may not read projects.
  @unreadable %{
    member: [],
    outsider: [],
    viewer: ["Assignee", "Reported by"],
    nobody: ["Project"]
  }

  # One task of the world's first organization, reported by the admin and
  # assigned to nobody. Each is created a day after `day`, so that the tasks
  # of a test are in a known order: the highest day first.
  defp task(world, day, overrides) do
    [project | _] = world.projects

    Generator.generate(
      Generator.task(
        [
          organization_id: world.organization.id,
          project_id: project.id,
          reporter_id: world.admin.id,
          assignee_id: nil,
          description: nil,
          status: :in_progress,
          priority: :medium,
          progress: 40,
          estimate_hours: Decimal.new("12.5"),
          billable?: false,
          due_on: nil,
          completed_at: nil,
          external_ref: nil,
          inserted_at: DateTime.add(~U[2026-01-01 12:00:00.000000Z], day, :day)
        ] ++ overrides
      )
    )
  end

  defp stored(task), do: Ash.get!(Task, task.id, authorize?: false)
  defp titles(html), do: column(html, "task", "title")

  describe "a field the person can never see" do
    setup do
      world = world(tasks: 0, other_tasks: 0)
      task(world, 1, title: "Plan the launch", external_ref: "EXT-SECRET-1")
      %{world: world}
    end

    test "has its column for an admin", %{conn: conn, world: world} do
      {:ok, _view, html} = conn |> log_in(world.admin) |> live("/tasks")

      assert headers(html, "task") == @headers
      assert column(html, "task", "external_ref") == ["EXT-SECRET-1"]
      # the 19 columns, before them the boxes and the expanders, and after
      # them the actions
      assert attribute(html, "#task-table", "aria-colcount") == ["25"]
    end

    for actor <- [:member, :viewer, :outsider] do
      test "has no column for the #{actor}", %{conn: conn, world: world} do
        {:ok, _view, html} = conn |> log_in(world[unquote(actor)]) |> live("/tasks")

        assert headers(html, "task") ==
                 @headers -- ["External ref" | @unreadable[unquote(actor)]]
      end

      test "leaves the columns of the #{actor} numbered without a gap",
           %{conn: conn, world: world} do
        {:ok, _view, html} = conn |> log_in(world[unquote(actor)]) |> live("/tasks")

        # The expanders, the columns that are left (21, and 19 for the viewer),
        # and the actions, which a viewer can never run: and so nothing on
        # several rows either, which is what the boxes before the expanders
        # are for.
        acting = if unquote(actor) == :viewer, do: 0, else: 1

        count =
          acting + 1 + length(@headers -- ["External ref" | @unreadable[unquote(actor)]]) +
            acting

        numbers = Enum.map(1..count, &Integer.to_string/1)

        assert count == if(unquote(actor) == :viewer, do: 20, else: 24)
        assert attribute(html, "#task-table", "aria-colcount") == ["#{count}"]
        assert attribute(html, "#task-head-row th", "aria-colindex") == numbers
        assert attribute(html, "#task-filter-row td", "aria-colindex") == numbers

        assert attribute(html, "#task-head-description", "aria-colindex") ==
                 ["#{15 + acting}"]
      end
    end

    # Nobody is no task's assignee either, so the estimate is never theirs to see.
    test "has no column for nobody, nor has a field only ever seen on one's own tasks",
         %{conn: conn, world: world} do
      {:ok, _view, html} = conn |> log_in(world.nobody) |> live("/tasks")

      assert headers(html, "task") ==
               @headers -- ["External ref", "Estimate hours" | @unreadable.nobody]

      # the expanders, and the 19 columns that are left
      assert attribute(html, "#task-table", "aria-colcount") == ["20"]

      assert attribute(html, "#task-head-row th", "aria-colindex") ==
               Enum.map(1..20, &Integer.to_string/1)

      refute html =~ "estimate_hours"
      refute html =~ "Estimate hours"
    end

    for actor <- [:member, :viewer, :outsider, :nobody] do
      test "is mentioned nowhere in the page of the #{actor}", %{conn: conn, world: world} do
        {:ok, _view, html} = conn |> log_in(world[unquote(actor)]) |> live("/tasks")

        # not its name, in an id, a form field or an event's value; not its label,
        # in a header or the name of a filter or an editor; not its value
        refute html =~ "external_ref"
        refute html =~ "External ref"
        refute html =~ ~r/external/i
        refute html =~ "EXT-SECRET-1"
      end
    end

    test "leaves the cells of a row numbered without a gap", %{conn: conn, world: world} do
      {:ok, _view, html} = conn |> log_in(world.member) |> live("/tasks")

      # the box, the expander, the eighteen columns of a member, the actions
      assert attribute(html, "#task-table tbody td", "aria-colindex") ==
               Enum.map(1..24, &Integer.to_string/1)
    end
  end

  describe "a URL that sorts or filters by a column the person cannot see" do
    setup do
      world = world(tasks: 0, other_tasks: 0)
      task(world, 1, title: "Cherry", external_ref: "EXT-2")
      task(world, 2, title: "Apple", external_ref: "EXT-3")
      task(world, 3, title: "Banana", external_ref: "EXT-1")
      %{world: world}
    end

    test "sorts and filters for an admin, who sees the column", %{conn: conn, world: world} do
      conn = log_in(conn, world.admin)

      {:ok, _view, html} = live(conn, "/tasks?task[sort]=external_ref")
      assert titles(html) == ["Banana", "Cherry", "Apple"]

      {:ok, _view, html} = live(conn, "/tasks?task[f][external_ref]=EXT-2")
      assert titles(html) == ["Cherry"]
    end

    for actor <- [:member, :viewer] do
      test "is ignored for the #{actor}: the rows and their order are those of the plain page",
           %{conn: conn, world: world} do
        conn = log_in(conn, world[unquote(actor)])
        {:ok, _view, plain} = live(conn, "/tasks")

        assert titles(plain) == ["Banana", "Apple", "Cherry"]

        for query <- [
              "task[sort]=external_ref",
              "task[sort]=-external_ref",
              "task[f][external_ref]=EXT-2",
              "task[f][external_ref][equals]=EXT-2",
              "task[f][external_ref][is_empty]=",
              "task[f][external_ref]=EXT-2&task[sort]=external_ref"
            ] do
          {:ok, _view, html} = live(conn, "/tasks?" <> query)

          assert titles(html) == ["Banana", "Apple", "Cherry"], query
          assert text(html, "#task-range") == "1–3 of 3", query

          assert attribute(html, "#task-table [aria-sort]:not([aria-sort=none])", "id") == [],
                 query

          # no filter is shown as set
          assert attribute(html, "#task-clear-filters", "id") == [], query
          refute html =~ "EXT-", query
        end
      end
    end

    test "is dropped from the URL once the person sorts or filters by something else",
         %{conn: conn, world: world} do
      {:ok, view, _html} =
        conn
        |> log_in(world.member)
        |> live("/tasks?task[f][external_ref]=EXT-2&task[sort]=external_ref")

      view |> element("#task-head-title") |> render_click()

      assert_patch(view, "/tasks?task[sort]=title")
      assert titles(render_async(view)) == ["Apple", "Banana", "Cherry"]
    end

    test "cannot be sorted or filtered by through the table's events either",
         %{conn: conn, world: world} do
      {:ok, view, _html} = conn |> log_in(world.member) |> live("/tasks")

      forge(view, "task", "sort", %{"column" => "external_ref"})

      forge(view, "task", "filter", %{
        "filter" => %{"external_ref" => %{"o" => "equals", "v" => "EXT-2"}}
      })

      html = render_async(view)

      assert titles(html) == ["Banana", "Apple", "Cherry"]
      refute_patched(view, "/tasks?task[sort]=external_ref")
      refute html =~ "EXT-"
    end
  end

  describe "a field the person sees on some rows only" do
    setup %{conn: conn} do
      world = world(tasks: 0, other_tasks: 0)
      # the newest first: this is the order of the plain page
      task(world, 5, title: "Mine, 8 hours", assignee_id: world.member.id, estimate_hours: 8)
      task(world, 4, title: "Theirs, 30 hours", estimate_hours: 30)
      task(world, 3, title: "Mine, 20 hours", assignee_id: world.member.id, estimate_hours: 20)
      task(world, 2, title: "Theirs, 5 hours", estimate_hours: 5)
      task(world, 1, title: "Theirs, no estimate", estimate_hours: nil)

      task(world, 0,
        title: "Mine, no estimate",
        assignee_id: world.member.id,
        estimate_hours: nil
      )

      %{world: world, conn: log_in(conn, world.member)}
    end

    test "keeps its column, with a placeholder in the cells that are hidden", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/tasks")

      assert "Estimate hours" in headers(html, "task")

      assert Enum.zip(titles(html), column(html, "task", "estimate_hours")) == [
               {"Mine, 8 hours", "8 h"},
               {"Theirs, 30 hours", "Not available"},
               {"Mine, 20 hours", "20 h"},
               {"Theirs, 5 hours", "Not available"},
               {"Theirs, no estimate", "Not available"},
               {"Mine, no estimate", ""}
             ]

      refute html =~ ">30<"
    end

    test "the placeholder is text for screen readers only", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/tasks")

      assert attribute(html, "#task-table td[id$='-c-estimate_hours'] > span", "class") ==
               ["sr-only", "sr-only", "sr-only"]
    end

    test "a filter by a value finds only rows whose value the person sees", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/tasks")

      # "Theirs, 30 hours" has more than 10 too, and is not found
      html = filter(view, "task", "estimate_hours", o: "greater_than", v: "10")
      assert titles(html) == ["Mine, 20 hours"]
      assert text(html, "#task-range") == "1–1 of 1"

      # nor is a hidden value found by naming it
      html = filter(view, "task", "estimate_hours", o: "equals", v: "30")
      assert titles(html) == []

      html = filter(view, "task", "estimate_hours", o: "less_than", v: "10")
      assert titles(html) == ["Mine, 8 hours"]
    end

    test "is empty finds every row whose value is hidden, whatever it holds", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/tasks")

      html = filter(view, "task", "estimate_hours", o: "is_empty")

      # a hidden value counts as empty: the three hidden rows come back alike,
      # the one that really has no estimate among them
      assert Enum.zip(titles(html), column(html, "task", "estimate_hours")) == [
               {"Theirs, 30 hours", "Not available"},
               {"Theirs, 5 hours", "Not available"},
               {"Theirs, no estimate", "Not available"},
               {"Mine, no estimate", ""}
             ]
    end

    test "a sort orders the rows whose value the person sees, and leaves the hidden ones together",
         %{conn: conn} do
      {:ok, _view, html} = live(conn, "/tasks?task[sort]=estimate_hours")

      # The hidden rows sort as empty ones, in the read action's order among
      # themselves (newest first), not by what they hold: 30, 5, nothing.
      assert titles(html) == [
               "Mine, 8 hours",
               "Mine, 20 hours",
               "Theirs, 30 hours",
               "Theirs, 5 hours",
               "Theirs, no estimate",
               "Mine, no estimate"
             ]

      {:ok, _view, html} = live(conn, "/tasks?task[sort]=-estimate_hours")

      assert titles(html) == [
               "Theirs, 30 hours",
               "Theirs, 5 hours",
               "Theirs, no estimate",
               "Mine, no estimate",
               "Mine, 20 hours",
               "Mine, 8 hours"
             ]
    end
  end

  describe "a person who can never run the table's update actions" do
    setup %{conn: conn} do
      world = world(tasks: 0, other_tasks: 0)
      task = task(world, 1, title: "Write the report", assignee_id: world.viewer.id)
      {:ok, view, html} = conn |> log_in(world.viewer) |> live("/tasks")
      %{world: world, task: task, view: view, html: html}
    end

    test "is offered no editing at all: no cell is marked, and there is no editor",
         %{html: html} do
      assert titles(html) == ["Write the report"]
      assert attribute(html, "#task-table td", "aria-readonly") == []
      assert editors(html, "task") == []
      assert attribute(html, "#task template", "id") == []
      assert attribute(html, "#task dialog", "id") == []
      refute html =~ "Change the state of this task?"
    end

    test "saves nothing by sending the event the table would send", %{view: view, task: task} do
      for {field, value} <- [
            {"title", "The viewer was here"},
            {"status", "done"},
            {"priority", "urgent"},
            {"progress", "90"},
            {"estimate_hours", "1"},
            {"billable?", "true"}
          ] do
        html = save(view, task.id, field, value)

        # the cell is as it was, and says nothing about a save
        assert failure(html, task.id, field) == nil, field
        assert attribute(html, cell(task.id, field), "aria-invalid") == [], field
      end

      assert text(render(view), cell(task.id, "title")) == "Write the report"
      assert text(render(view), "#task-status") == ""

      assert %{
               title: "Write the report",
               status: :in_progress,
               priority: :medium,
               progress: 40,
               billable?: false
             } = stored(task)

      assert Decimal.equal?(stored(task).estimate_hours, Decimal.new("12.5"))
    end
  end

  describe "a person who may run the update actions on some tasks only" do
    setup %{conn: conn} do
      world = world(tasks: 0, other_tasks: 0)
      mine = task(world, 2, title: "My own task", assignee_id: world.member.id)
      theirs = task(world, 1, title: "Somebody else's task")
      {:ok, view, html} = conn |> log_in(world.member) |> live("/tasks")
      %{world: world, mine: mine, theirs: theirs, view: view, html: html}
    end

    test "is offered editing on every task: the table cannot know yet which will be refused",
         %{html: html, mine: mine, theirs: theirs} do
      assert editors(html, "task") ==
               ~w(title status priority progress estimate_hours billable? due_on completed_at description tags checks recurrence project assignee)

      for task <- [mine, theirs], field <- ~w(title status priority progress billable?) do
        assert attribute(html, cell(task.id, field), "aria-readonly") == [], field
      end

      # read-only for everybody
      assert attribute(html, cell(mine.id, "inserted_at"), "aria-readonly") == ["true"]
    end

    test "saves a cell of a task that is theirs", %{view: view, mine: mine} do
      html = save(view, mine.id, "title", "Still my own task")

      assert text(html, cell(mine.id, "title")) == "Still my own task"
      assert failure(html, mine.id, "title") == nil
      assert stored(mine).title == "Still my own task"
    end

    test "is refused on the cell when the task is not theirs, through each of the actions",
         %{view: view, theirs: theirs} do
      for {field, value, shown} <- [
            {"title", "The member was here", "The member was here"},
            {"priority", "urgent", "Urgent"},
            {"progress", "90", "90"}
          ] do
        html = save(view, theirs.id, field, value)

        assert failure(html, theirs.id, field) == %{
                 shown: shown,
                 message: "You are not allowed to change this."
               }
      end

      assert %{title: "Somebody else's task", priority: :medium, progress: 40} = stored(theirs)
    end
  end

  describe "a person who may always run the update actions" do
    test "is offered editing and saves any task", %{conn: conn} do
      world = world(tasks: 0, other_tasks: 0)
      task = task(world, 1, title: "Somebody else's task", assignee_id: world.member.id)
      {:ok, view, html} = conn |> log_in(world.admin) |> live("/tasks")

      assert editors(html, "task") ==
               ~w(title status priority progress estimate_hours billable? due_on completed_at description tags checks recurrence project assignee)

      assert attribute(html, cell(task.id, "title"), "aria-readonly") == []

      html = save(view, task.id, "title", "The admin was here")

      assert text(html, cell(task.id, "title")) == "The admin was here"
      assert stored(task).title == "The admin was here"
    end
  end

  describe "the same table, person by person" do
    test "follows whoever opens it", %{conn: conn} do
      world = world(tasks: 0, other_tasks: 0)
      task(world, 1, title: "Plan the launch", external_ref: "EXT-1")

      seen =
        for actor <- [:admin, :member, :viewer, :outsider, :nobody] do
          {:ok, _view, html} = conn |> log_in(world[actor]) |> live("/tasks")

          {actor,
           %{
             columns: length(headers(html, "task")),
             rows: length(titles(html)),
             editors: length(editors(html, "task"))
           }}
        end

      assert seen == [
               admin: %{columns: 22, rows: 1, editors: 14},
               member: %{columns: 21, rows: 1, editors: 14},
               # may not read people: no assignee, no reporter
               viewer: %{columns: 19, rows: 1, editors: 0},
               # of the other organization: none of these tasks, and a member there
               outsider: %{columns: 21, rows: 0, editors: 14},
               # may not read projects
               nobody: %{columns: 19, rows: 0, editors: 0}
             ]
    end
  end
end
