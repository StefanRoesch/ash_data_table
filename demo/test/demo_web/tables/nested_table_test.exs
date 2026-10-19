defmodule DemoWeb.Tables.NestedTableTest do
  @moduledoc """
  Nested tables, as a person meets them in the demo: a row expands into one
  line per relationship, and a line opens the table of the related records.

  Driven by the events the table's hook sends (`expand` with a row's key,
  `toggle` with a row's key and a relationship's name).
  """
  use DemoWeb.ModeCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator

  @moment ~U[2026-01-01 12:00:00.000000Z]

  # A task of the world's first organization, in its first project, reported
  # by the admin.
  defp task(world, title, overrides \\ []) do
    [project | _] = world.projects

    Generator.generate(
      Generator.task(
        [
          organization_id: world.organization.id,
          project_id: project.id,
          reporter_id: world.admin.id,
          title: title,
          inserted_at: @moment
        ] ++ overrides
      )
    )
  end

  # Comments on a task with the bodies given, each written a minute after
  # the one before it, so the last one is the newest.
  defp comments(world, task, bodies, overrides \\ []) do
    for {body, index} <- Enum.with_index(bodies) do
      Generator.generate(
        Generator.comment(
          [
            organization_id: world.organization.id,
            task_id: task.id,
            author_id: world.admin.id,
            body: body,
            inserted_at: DateTime.add(@moment, index, :minute)
          ] ++ overrides
        )
      )
    end
  end

  describe "the expander" do
    test "is the first cell of every row of a table with relationships to offer, after the box of a row that can be selected",
         %{conn: conn} do
      world = world(tasks: 0)
      task = task(world, "Write the report")

      # a viewer has nothing to select a row for
      {:ok, _view, html} = conn |> log_in(world.viewer) |> live("/tasks")

      assert attribute(html, "[id='task-row-#{task.id}-r'] > [role=gridcell]:first-child", "id") ==
               ["task-row-#{task.id}-e"]

      assert text(html, "#task-head-row > [role=columnheader]:first-child") == "Related records"
      assert attribute(html, "#task-expander-head", "aria-colindex") == ["1"]
      assert attribute(html, "#task-head-title", "aria-colindex") == ["2"]

      {:ok, _view, html} = conn |> log_in(world.admin) |> live("/tasks")

      assert attribute(html, "[id='task-row-#{task.id}-r'] > [role=gridcell]", "id")
             |> Enum.take(3) ==
               ["task-row-#{task.id}-s", "task-row-#{task.id}-e", "task-row-#{task.id}-c-title"]

      assert attribute(html, "[id='task-row-#{task.id}-e'] > button", "aria-expanded") == [
               "false"
             ]

      assert attribute(html, "[id='task-row-#{task.id}-e'] > button", "aria-label") == [
               "Related records"
             ]

      # a column of its own: counted, with a header that names it
      assert text(html, "#task-expander-head") == "Related records"

      assert attribute(html, "#task-head-row > [role=columnheader]", "id") |> Enum.take(3) ==
               ["task-select-head", "task-expander-head", "task-head-title"]

      assert attribute(html, "#task-expander-head", "aria-colindex") == ["2"]
      assert attribute(html, "[id='task-row-#{task.id}-e']", "aria-colindex") == ["2"]
      assert attribute(html, "#task-head-title", "aria-colindex") == ["3"]
      assert attribute(html, cell(task.id, "title"), "aria-colindex") == ["3"]
      assert attribute(html, cell(task.id, "inserted_at"), "aria-colindex") == ["21"]
      assert attribute(html, cell(task.id, "reporter"), "aria-colindex") == ["24"]
      # the boxes, the expanders, the 19 columns and the actions
      assert attribute(html, "#task-table", "aria-colcount") == ["25"]
      # and not one of the table's columns
      assert hd(headers(html, "task")) == "Title"
    end

    test "is not there in a table with nothing to offer: no column for it at all", %{conn: conn} do
      Generator.generate(Generator.specimen())

      {:ok, _view, html} = live(conn, "/specimens")

      assert attribute(html, "#specimen-table [data-expander]", "id") == []

      assert attribute(html, "#specimen-head-row > [role=columnheader]:first-child", "id") == [
               "specimen-head-id"
             ]

      assert attribute(html, "#specimen-head-id", "aria-colindex") == ["1"]

      assert attribute(html, "#specimen-table", "aria-colcount") ==
               ["#{length(headers(html, "specimen"))}"]
    end
  end

  describe "an expanded row" do
    setup %{conn: conn} do
      world = world(tasks: 0)
      %{world: world, task: task(world, "Write the report"), conn: log_in(conn, world.admin)}
    end

    test "shows nothing under it until its expander is used", %{conn: conn, task: task} do
      {:ok, _view, html} = live(conn, "/tasks")

      assert lines(html, task.id) == []
      assert attribute(html, "[id='task-row-#{task.id}-x']", "hidden") == [""]
    end

    test "shows one line per declared relationship, in the declared order, with its label",
         %{conn: conn, task: task} do
      {:ok, view, _html} = live(conn, "/tasks")

      html = expand(view, task.id)

      assert lines(html, task.id) ==
               [
                 "Comments",
                 "First comment",
                 "Newest comment",
                 "Labels",
                 "Project",
                 "Assignee",
                 "Reported by"
               ]

      assert attribute(html, "[id='task-row-#{task.id}-x']", "hidden") == []
      # every line is closed: no nested table yet
      assert attribute(
               html,
               "[id='task-row-#{task.id}-x'] [role=gridcell][data-line] > div > button",
               "aria-expanded"
             )
             |> Enum.uniq() == ["false"]

      assert attribute(html, "#task-table[role=grid]", "role") != []
      assert attribute(html, "[id='task-row-#{task.id}-x'] [role=grid]", "id") == []
    end

    test "answers the hook with whether the row is now expanded", %{conn: conn, task: task} do
      {:ok, view, _html} = live(conn, "/tasks")

      expand(view, task.id)
      assert_reply view, %{open: true}

      expand(view, task.id)
      assert_reply view, %{open: false}
    end

    test "closes again with a second use of the expander", %{conn: conn, task: task} do
      {:ok, view, _html} = live(conn, "/tasks")

      expand(view, task.id)
      html = expand(view, task.id)

      assert lines(html, task.id) == []
      assert attribute(html, "[id='task-row-#{task.id}-x']", "hidden") == [""]
    end

    test "offers, where the table declares none, every public relationship whose destination has a table",
         %{conn: conn, world: world, task: task} do
      [comment] = comments(world, task, ["Looks good"])
      [project | _] = world.projects
      [label | _] = world.labels

      Generator.generate(
        Generator.task_label(
          organization_id: world.organization.id,
          task_id: task.id,
          label_id: label.id
        )
      )

      for {path, id, key, expected} <- [
            {"/projects", "project", project.id, ["Tasks"]},
            {"/comments", "comment", comment.id, ["Task", "Author"]},
            {"/labels", "label", label.id, ["Tasks"]},
            {"/task_labels", "task_label", "#{task.id}-#{label.id}", ["Task", "Label"]}
          ] do
        {:ok, view, _html} = live(conn, path)

        assert lines(expand(view, id, key), id, key) == expected
      end
    end
  end

  # The labels given, each attached to the task.
  defp labels(world, task, names) do
    for name <- names do
      label =
        Generator.generate(Generator.label(organization_id: world.organization.id, name: name))

      Generator.generate(
        Generator.task_label(
          organization_id: world.organization.id,
          task_id: task.id,
          label_id: label.id
        )
      )

      label
    end
  end

  # No patch of the URL has been asked for.
  defp refute_patched, do: refute_receive({_ref, {:patch, _topic, _to}}, 20)

  describe "a line that is opened" do
    setup %{conn: conn} do
      world = world(tasks: 0)
      task = task(world, "Write the report", assignee_id: world.member.id)
      other = task(world, "Another task", inserted_at: DateTime.add(@moment, -1, :day))
      comments(world, task, ["First", "Second", "Third"])
      comments(world, other, ["Of the other task"])

      %{world: world, task: task, other: other, conn: log_in(conn, world.admin)}
    end

    test "shows the destination's own table under the line: its columns and the related records",
         %{conn: conn, task: task} do
      {:ok, view, _html} = live(conn, "/tasks")
      expand(view, task.id)

      html = toggle(view, task.id, "comments")
      id = nested(task.id, "comments")

      assert headers(html, id) == ["ID", "Body", "Inserted at", "Task ID", "Author ID"]
      # the comments of this task and of no other, newest first as their read action sorts
      assert column(html, id, "body") == ["Third", "Second", "First"]

      assert attribute(html, "[id='task-row-#{task.id}-l-comments-b']", "aria-expanded") == [
               "true"
             ]

      # the other lines stay closed
      assert attribute(html, "[id='task-row-#{task.id}-l-labels-b']", "aria-expanded") == [
               "false"
             ]

      assert attribute(html, "[id='#{nested(task.id, "labels")}']", "id") == []
    end

    test "is a grid of its own in a cell that spans the row, named by its line and its row",
         %{conn: conn, task: task} do
      {:ok, view, _html} = live(conn, "/tasks")
      expand(view, task.id)

      html = toggle(view, task.id, "comments")
      id = nested(task.id, "comments")

      assert attribute(html, "[id='#{id}-table']", "role") == ["grid"]

      assert attribute(html, "[id='#{id}-table']", "aria-labelledby") ==
               ["task-row-#{task.id}-l-comments-b task-row-#{task.id}-c-title"]

      assert attribute(html, "[id='#{id}-table']", "aria-label") == []
      assert text(html, "[id='task-row-#{task.id}-l-comments-b']") =~ "Comments"
      assert text(html, "[id='task-row-#{task.id}-c-title']") == "Write the report"

      # the boxes, the expanders, 19 columns and the actions
      assert attribute(html, "[id='task-row-#{task.id}-n-comments-c']", "colspan") == ["25"]
      assert attribute(html, "[id='task-row-#{task.id}-n-comments-c']", "role") == ["gridcell"]
    end

    test "says that it is loading until its first rows are there", %{conn: conn, task: task} do
      {:ok, view, _html} = live(conn, "/tasks")
      expand(view, task.id)
      id = nested(task.id, "comments")

      html =
        forge(view, "task", "toggle", %{"row" => task.id, "relationship" => "comments"})

      assert text(html, "[id='#{id}-loading']") == "Loading…"
      assert attribute(html, "[id='#{id}-table']", "aria-busy") == ["true"]
      # not "No records": nothing is known yet
      assert text(html, "[id='#{id}-empty']") == nil

      html = render_async(view)

      assert text(html, "[id='#{id}-loading']") == nil
      assert attribute(html, "[id='#{id}-table']", "aria-busy") == []
      assert column(html, id, "body") == ["Third", "Second", "First"]
    end

    test "says \"No records\" when there are none", %{conn: conn, other: other} do
      {:ok, view, _html} = live(conn, "/tasks")
      expand(view, other.id)

      html = toggle(view, other.id, "labels")

      assert text(html, "[id='#{nested(other.id, "labels")}-empty']") == "No records"
    end

    test "of a has-one that picks one of many shows the one its own sort puts first, whatever the action sorts by",
         %{conn: conn, task: task} do
      {:ok, view, _html} = live(conn, "/tasks")
      expand(view, task.id)

      # the comments' read action sorts newest first; this relationship oldest first
      html = toggle(view, task.id, "first_comment")
      assert column(html, nested(task.id, "first_comment"), "body") == ["First"]

      html = toggle(view, task.id, "latest_comment")
      assert column(html, nested(task.id, "latest_comment"), "body") == ["Third"]
    end

    test "of a single related record has no sort, no filter and no pages, and is the same table otherwise",
         %{conn: conn, task: task} do
      {:ok, view, _html} = live(conn, "/tasks")
      expand(view, task.id)

      html = toggle(view, task.id, "latest_comment")
      id = nested(task.id, "latest_comment")

      assert headers(html, id) == ["ID", "Body", "Inserted at", "Task ID", "Author ID"]
      assert attribute(html, "[id='#{id}-head-row'] [role=columnheader]", "role") != []
      assert attribute(html, "[id='#{id}-head-row'] [role=columnheader][aria-sort]", "id") == []
      assert attribute(html, "[id='#{id}-head-row'] [role=columnheader][phx-click]", "id") == []
      assert attribute(html, "[id='#{id}-filter-row'] :is(input, select)", "id") == []
      assert attribute(html, "[id='#{id}-pagination']", "id") == []
      # what the comments' table edits is edited here, as on its own page
      assert editors(html, id) == ["body"]
    end

    test "of a belongs-to shows the one record it points at", %{
      conn: conn,
      world: world,
      task: task
    } do
      [project | _] = world.projects
      {:ok, view, _html} = live(conn, "/tasks")
      expand(view, task.id)

      html = toggle(view, task.id, "project")
      assert column(html, nested(task.id, "project"), "name") == [project.name]

      html = toggle(view, task.id, "assignee")

      assert headers(html, nested(task.id, "assignee")) ==
               ["Name", "Email", "Role", "Assigned hours"]

      assert column(html, nested(task.id, "assignee"), "name") == [world.member.name]

      html = toggle(view, task.id, "reporter")
      assert column(html, nested(task.id, "reporter"), "name") == [world.admin.name]
    end

    test "with no column that filters has no filter row: its header is one row, and its rows count from 2",
         %{conn: conn, world: world, task: task} do
      {:ok, view, _html} = live(conn, "/tasks")
      expand(view, task.id)

      html = toggle(view, task.id, "reporter")
      id = nested(task.id, "reporter")

      assert attribute(html, "[id='#{id}-head'] > [role=row]", "id") == ["#{id}-head-row"]
      assert attribute(html, "[id='#{id}-filter-row']", "id") == []
      assert attribute(html, "[id='#{id}-filters']", "id") == []

      assert attribute(
               html,
               "[id='#{id}-table'] > [role=rowgroup]:not([id$='-head']) > [role=row]",
               "aria-rowindex"
             ) ==
               ["2"]

      assert attribute(html, "[id='#{id}-table']", "aria-rowcount") == ["2"]
      assert column(html, id, "name") == [world.admin.name]

      # a table where some columns filter keeps it, and counts both rows
      html = toggle(view, task.id, "comments")
      comments = nested(task.id, "comments")
      assert attribute(html, "[id='#{comments}-filter-row']", "id") == ["#{comments}-filter-row"]
      assert attribute(html, "[id='#{comments}-table']", "data-first-row") == ["3"]
    end

    test "of a belongs-to that points at nothing says \"No records\"", %{conn: conn, other: other} do
      {:ok, view, _html} = live(conn, "/tasks")
      expand(view, other.id)

      html = toggle(view, other.id, "assignee")

      assert column(html, nested(other.id, "assignee"), "name") == []
      assert text(html, "[id='#{nested(other.id, "assignee")}-empty']") == "No records"
    end

    test "of a many-to-many shows the records joined to the row, in full where the destination has no pages",
         %{conn: conn, world: world, task: task, other: other} do
      labels(world, task, ["urgent", "backend", "api"])
      labels(world, other, ["frontend"])

      {:ok, view, _html} = live(conn, "/tasks")
      expand(view, task.id)

      html = toggle(view, task.id, "labels")
      id = nested(task.id, "labels")

      # by name, as the labels' read action sorts
      assert column(html, id, "name") == ["api", "backend", "urgent"]
      assert attribute(html, "[id='#{id}-pagination']", "id") == []
      # sorting and filtering are there
      assert attribute(html, "[id='#{id}-head-name']", "aria-sort") == ["none"]
      assert filter_controls(html, id, "name").input == "text"
    end

    test "is closed again with a second use of the line, and is gone with what it showed",
         %{conn: conn, task: task} do
      {:ok, view, _html} = live(conn, "/tasks")
      expand(view, task.id)
      toggle(view, task.id, "comments")

      html = toggle(view, task.id, "comments")

      assert attribute(html, "[id='#{nested(task.id, "comments")}']", "id") == []

      assert attribute(html, "[id='task-row-#{task.id}-l-comments-b']", "aria-expanded") == [
               "false"
             ]

      refute html =~ "Third"
      # the lines are still there
      assert length(lines(html, task.id)) == 7
    end

    test "several lines of one row, and lines of several rows, are open side by side",
         %{conn: conn, task: task, other: other} do
      {:ok, view, _html} = live(conn, "/tasks")
      expand(view, task.id)
      expand(view, other.id)
      toggle(view, task.id, "comments")
      toggle(view, task.id, "project")
      html = toggle(view, other.id, "comments")

      assert column(html, nested(task.id, "comments"), "body") == ["Third", "Second", "First"]
      assert length(column(html, nested(task.id, "project"), "name")) == 1
      assert column(html, nested(other.id, "comments"), "body") == ["Of the other task"]
    end

    test "closing the row closes everything under it, and opening it again starts with closed lines",
         %{conn: conn, task: task} do
      {:ok, view, _html} = live(conn, "/tasks")
      expand(view, task.id)
      toggle(view, task.id, "comments")

      html = expand(view, task.id)
      assert lines(html, task.id) == []
      refute html =~ "Third"

      html = expand(view, task.id)
      assert length(lines(html, task.id)) == 7
      assert attribute(html, "[id='#{nested(task.id, "comments")}']", "id") == []
    end
  end

  describe "a nested table's own sort, filters and pages" do
    setup %{conn: conn} do
      world = world(tasks: 0)
      task = task(world, "Write the report")
      other = task(world, "Another task", inserted_at: DateTime.add(@moment, -1, :day))
      %{world: world, task: task, other: other, conn: log_in(conn, world.admin)}
    end

    test "a click on its header sorts it, and neither the URL nor the table around it",
         %{conn: conn, world: world, task: task} do
      comments(world, task, ["Banana", "Apple", "Cherry"])
      {:ok, view, _html} = live(conn, "/tasks")
      expand(view, task.id)
      toggle(view, task.id, "comments")
      id = nested(task.id, "comments")

      click(view, "[id='#{id}-head-body']")
      html = render_async(view)

      assert column(html, id, "body") == ["Apple", "Banana", "Cherry"]
      assert attribute(html, "[id='#{id}-head-body']", "aria-sort") == ["ascending"]
      refute_patched()
      # the table around it is as it was: its rows, its sort, and the line still open
      assert column(html, "task", "title") == ["Write the report", "Another task"]
      assert attribute(html, "#task-head-title", "aria-sort") == ["none"]

      click(view, "[id='#{id}-head-body']")
      html = render_async(view)

      assert column(html, id, "body") == ["Cherry", "Banana", "Apple"]
    end

    test "its filter row filters it, announces the result, and leaves the URL alone",
         %{conn: conn, world: world, task: task} do
      comments(world, task, ["Banana", "Apple", "Cherry"])
      {:ok, view, _html} = live(conn, "/tasks")
      expand(view, task.id)
      toggle(view, task.id, "comments")
      id = nested(task.id, "comments")

      html = filter(view, id, "body", v: "an")

      assert column(html, id, "body") == ["Banana"]
      assert text(html, "[id='#{id}-status']") == "1 result"
      assert attribute(html, "[id='#{id}-clear-filters']", "tabindex") == ["-1"]
      refute_patched()
      assert column(html, "task", "title") == ["Write the report", "Another task"]
      assert attribute(html, "#task-clear-filters", "id") == []

      click(view, "[id='#{id}-clear-filters']")
      html = render_async(view)

      assert column(html, id, "body") == ["Cherry", "Apple", "Banana"]
    end

    test "keyset pages: next and previous, in the last row of its grid", %{
      conn: conn,
      world: world,
      task: task
    } do
      comments(world, task, for(n <- 1..45, do: "Comment #{String.pad_leading("#{n}", 2, "0")}"))
      {:ok, view, _html} = live(conn, "/tasks")
      expand(view, task.id)
      html = toggle(view, task.id, "comments")
      id = nested(task.id, "comments")

      numbered = fn range ->
        for n <- range, do: "Comment #{String.pad_leading("#{n}", 2, "0")}"
      end

      # 20 to a page, as the comments' read action says, newest first
      assert column(html, id, "body") == numbered.(45..26//-1)
      assert text(html, "[id='#{id}-range']") == "45 records"
      assert attribute(html, "[id='#{id}-previous']", "disabled") == [""]
      assert attribute(html, "[id='#{id}-next']", "disabled") == []
      # the controls are in the grid, and no tab stops
      assert attribute(
               html,
               "[id='#{id}-foot'] [id='#{id}-pager'] [id='#{id}-pagination']",
               "role"
             ) == ["group"]

      assert attribute(html, "[id='#{id}-pagination'] button", "tabindex") == ["-1", "-1"]

      click(view, "[id='#{id}-next']")
      html = render_async(view)
      assert column(html, id, "body") == numbered.(25..6//-1)
      refute_patched()

      click(view, "[id='#{id}-next']")
      html = render_async(view)
      assert column(html, id, "body") == numbered.(5..1//-1)
      assert attribute(html, "[id='#{id}-next']", "disabled") == [""]

      click(view, "[id='#{id}-previous']")
      html = render_async(view)
      assert column(html, id, "body") == numbered.(25..6//-1)
    end

    test "offset pages: page numbers and the total", %{conn: conn, world: world} do
      project =
        Generator.generate(
          Generator.project(organization_id: world.organization.id, name: "Aardvark")
        )

      for n <- 1..30 do
        task(world, "Task #{String.pad_leading("#{n}", 2, "0")}",
          project_id: project.id,
          inserted_at: DateTime.add(@moment, n, :minute)
        )
      end

      {:ok, view, _html} = live(conn, "/projects")
      expand(view, "project", project.id)
      html = toggle(view, "project", project.id, "tasks")
      id = nested("project", project.id, "tasks")

      assert length(column(html, id, "title")) == 25
      assert hd(column(html, id, "title")) == "Task 30"
      assert text(html, "[id='#{id}-range']") == "1–25 of 30"
      # 30 records, the two header rows and the footer row of the summaries
      assert attribute(html, "[id='#{id}-table']", "aria-rowcount") == ["33"]

      click(view, "[id='#{id}-page-2']")
      html = render_async(view)

      assert column(html, id, "title") == ["Task 05", "Task 04", "Task 03", "Task 02", "Task 01"]
      assert text(html, "[id='#{id}-range']") == "26–30 of 30"
      refute_patched()
      # the projects around it are on their first page still
      assert text(html, "#project-range") =~ "1–"
    end
  end

  describe "editing in a nested table" do
    setup %{conn: conn} do
      world = world(tasks: 0)

      project =
        Generator.generate(
          Generator.project(organization_id: world.organization.id, name: "Aardvark")
        )

      first =
        task(world, "First task",
          project_id: project.id,
          progress: 10,
          status: :in_progress,
          priority: :low
        )

      second =
        task(world, "Second task",
          project_id: project.id,
          inserted_at: DateTime.add(@moment, 1, :minute)
        )

      %{
        world: world,
        project: project,
        first: first,
        second: second,
        id: nested("project", project.id, "tasks"),
        conn: log_in(conn, world.admin)
      }
    end

    defp open_tasks(conn, project) do
      {:ok, view, _html} = live(conn, "/projects")
      expand(view, "project", project.id)
      {view, toggle(view, "project", project.id, "tasks")}
    end

    test "offers the editors of the destination's table", %{conn: conn, project: project, id: id} do
      {_view, html} = open_tasks(conn, project)

      assert editors(html, id) ==
               ~w(title status priority progress estimate_hours billable? due_on completed_at description tags checks recurrence project assignee)

      assert editor(html, id, "status").confirm == "Change the state of this task?"
      # the projects around it have the editors of their own table
      assert editors(html, "project") ==
               ~w(name description status starts_on budget client milestones)
    end

    test "saves the cell of the right record through the destination's own update action",
         %{conn: conn, world: world, project: project, first: first, second: second, id: id} do
      {view, html} = open_tasks(conn, project)
      assert column(html, id, "title") == ["Second task", "First task"]

      html = save(view, id, first.id, "title", "First task, renamed")

      assert column(html, id, "title") == ["Second task", "First task, renamed"]
      assert Ash.get!(Demo.Tracker.Task, first.id, as(world.admin)).title == "First task, renamed"
      assert Ash.get!(Demo.Tracker.Task, second.id, as(world.admin)).title == "Second task"

      # through the column's own action, which leaves its trace
      save(view, id, first.id, "priority", "urgent")

      assert %{priority: :urgent, internal_note: "Reprioritised"} =
               Ash.get!(Demo.Tracker.Task, first.id, authorize?: false)
    end

    test "a save that fails marks the cell of the nested table with the action's message",
         %{conn: conn, project: project, first: first, id: id} do
      {view, _html} = open_tasks(conn, project)

      html = save(view, id, first.id, "title", "ab")

      assert %{shown: "ab", message: "length must be greater than or equal to 3"} =
               failure(html, id, first.id, "title")

      assert text(html, "[id='#{id}-status']") ==
               "Title was not saved: length must be greater than or equal to 3"

      # the table around it says nothing
      assert text(html, "#project-status") == ""

      html = discard(view, id, first.id, "title")
      assert failure(html, id, first.id, "title") == nil
      assert text(html, cell(id, first.id, "title")) == "First task"
    end

    test "a record that no longer matches the nested table's filter stays in place until the next read",
         %{conn: conn, project: project, first: first, id: id} do
      {view, _html} = open_tasks(conn, project)
      html = filter(view, id, "title", v: "First")
      assert column(html, id, "title") == ["First task"]

      html = save(view, id, first.id, "title", "Renamed")

      assert column(html, id, "title") == ["Renamed"]
    end
  end

  describe "editing in the nested tables under a task" do
    setup %{conn: conn} do
      world = world(tasks: 0)

      project =
        Generator.generate(
          Generator.project(organization_id: world.organization.id, name: "Aardvark")
        )

      task = task(world, "Write the report", project_id: project.id)
      other = task(world, "Another task", inserted_at: DateTime.add(@moment, -1, :day))
      [first, second] = comments(world, task, ["First", "Second"])
      [bug, chore] = labels(world, task, ["bug", "chore"])
      [of_other] = comments(world, other, ["Of the other task"])

      %{
        world: world,
        project: project,
        task: task,
        comments: %{first: first, second: second, of_other: of_other},
        labels: %{bug: bug, chore: chore},
        conn: log_in(conn, world.admin)
      }
    end

    defp open_line(conn, task, relationship) do
      {:ok, view, _html} = live(conn, "/tasks")
      expand(view, task.id)
      {view, toggle(view, task.id, relationship), nested(task.id, relationship)}
    end

    test "a comment is edited in place: the right record is saved, and the row stays where it is",
         %{conn: conn, task: task, comments: comments} do
      {view, html, id} = open_line(conn, task, "comments")

      assert editors(html, id) == ["body"]
      assert column(html, id, "body") == ["Second", "First"]
      assert attribute(html, cell(id, comments.first.id, "body"), "aria-readonly") == []

      html = save(view, id, comments.first.id, "body", "First, reworded")

      assert column(html, id, "body") == ["Second", "First, reworded"]
      assert failure(html, id, comments.first.id, "body") == nil
      stored = &Ash.get!(Demo.Tracker.Comment, &1.id, authorize?: false).body
      assert stored.(comments.first) == "First, reworded"
      assert stored.(comments.second) == "Second"
      assert stored.(comments.of_other) == "Of the other task"
      # the task around it is as it was, with its line open
      assert text(html, cell(task.id, "title")) == "Write the report"
    end

    test "a label is edited in place, in a many-to-many", %{
      conn: conn,
      task: task,
      labels: labels
    } do
      {view, html, id} = open_line(conn, task, "labels")

      assert editors(html, id) == ~w(name colour)
      assert column(html, id, "name") == ["bug", "chore"]

      # the labels are sorted by name; the row keeps its place until the next read
      html = save(view, id, labels.bug.id, "name", "zebra")

      assert column(html, id, "name") == ["zebra", "chore"]
      stored = &Ash.get!(Demo.Tracker.Label, &1.id, authorize?: false)
      assert stored.(labels.bug).name == "zebra"
      assert stored.(labels.chore).name == "chore"

      # a value the action refuses marks the cell and saves nothing
      html = save(view, id, labels.chore.id, "colour", "red")
      assert %{shown: "red"} = failure(html, id, labels.chore.id, "colour")
      assert stored.(labels.chore).colour == labels.chore.colour
    end

    test "the project of a task is edited in place, in the one row of a belongs-to",
         %{conn: conn, world: world, task: task, project: project} do
      {view, html, id} = open_line(conn, task, "project")

      assert editors(html, id) == ~w(name description status starts_on budget client milestones)
      assert column(html, id, "name") == ["Aardvark"]

      html = save(view, id, project.id, "name", "Anteater")

      assert column(html, id, "name") == ["Anteater"]
      assert Ash.get!(Demo.Tracker.Project, project.id, authorize?: false).name == "Anteater"

      names =
        for other <- world.projects,
            do: Ash.get!(Demo.Tracker.Project, other.id, authorize?: false).name

      assert names == Enum.map(world.projects, & &1.name)
    end

    test "each person edits what the destination's policies give them",
         %{conn: conn, world: world, task: task, comments: comments, labels: labels} do
      [own] = comments(world, task, ["By the member"], author_id: world.member.id)

      # a member: their own comments and every project, no label
      conn = log_in(conn, world.member)
      {view, html, id} = open_line(conn, task, "comments")
      assert editors(html, id) == ["body"]
      html = save(view, id, own.id, "body", "By the member, reworded")
      assert text(html, cell(id, own.id, "body")) == "By the member, reworded"

      # whose a comment is, is known when it is saved: the cell says so
      html = save(view, id, comments.first.id, "body", "Not mine")

      assert failure(html, id, comments.first.id, "body") == %{
               shown: "Not mine",
               message: "You are not allowed to change this."
             }

      assert Ash.get!(Demo.Tracker.Comment, comments.first.id, authorize?: false).body == "First"

      {_view, html, id} = open_line(conn, task, "project")
      assert editors(html, id) == ~w(name description status starts_on budget client milestones)

      {view, html, id} = open_line(conn, task, "labels")
      assert editors(html, id) == []
      save(view, id, labels.bug.id, "name", "zebra")
      assert Ash.get!(Demo.Tracker.Label, labels.bug.id, authorize?: false).name == "bug"

      # a viewer: nothing
      conn = log_in(conn, world.viewer)

      for relationship <- ~w(comments labels project) do
        {_view, html, id} = open_line(conn, task, relationship)
        assert editors(html, id) == [], relationship

        assert attribute(html, "[id='#{id}-table'] [role=gridcell]", "role") != []

        assert attribute(html, "[id='#{id}-table'] [role=gridcell]", "aria-readonly") == [],
               relationship
      end
    end
  end

  describe "the table around an open nested table" do
    setup %{conn: conn} do
      world = world(tasks: 0)
      task = task(world, "Write the report")
      comments(world, task, ["First", "Second"])
      %{world: world, task: task, conn: log_in(conn, world.admin)}
    end

    test "a row of it that is edited keeps what is open under it", %{conn: conn, task: task} do
      {:ok, view, _html} = live(conn, "/tasks")
      expand(view, task.id)
      toggle(view, task.id, "comments")

      html = save(view, task.id, "title", "Write the summary")

      assert text(html, cell(task.id, "title")) == "Write the summary"
      # the row is sent again, and says that it is expanded
      assert attribute(html, "[id='task-row-#{task.id}-e'] > button", "aria-expanded") == ["true"]
      assert length(lines(html, task.id)) == 7
      assert column(html, nested(task.id, "comments"), "body") == ["Second", "First"]
    end

    test "a new read of it closes what was open", %{conn: conn, task: task} do
      {:ok, view, _html} = live(conn, "/tasks")
      expand(view, task.id)
      toggle(view, task.id, "comments")

      view |> element("#task-head-title") |> render_click()
      html = render_async(view)

      assert lines(html, task.id) == []
      assert attribute(html, "[id='task-row-#{task.id}-x']", "hidden") == [""]

      assert attribute(html, "[id='task-row-#{task.id}-e'] > button", "aria-expanded") == [
               "false"
             ]

      assert attribute(html, "[id='#{nested(task.id, "comments")}']", "id") == []
      refute html =~ "Second"
    end
  end

  describe "how deep rows expand" do
    setup %{conn: conn} do
      world = world(tasks: 0)
      task = task(world, "Write the report", assignee_id: world.member.id)
      [comment] = comments(world, task, ["Looks good"])
      %{world: world, task: task, comment: comment, conn: log_in(conn, world.admin)}
    end

    # Task -> comments -> task -> comments: a cycle, three levels down
    test "nested tables expand again, through a cycle, down to the limit of the table on the page",
         %{conn: conn, task: task, comment: comment} do
      {:ok, view, _html} = live(conn, "/tasks")
      expand(view, task.id)
      toggle(view, task.id, "comments")

      first = nested(task.id, "comments")
      html = expand(view, first, comment.id)
      assert lines(html, first, comment.id) == ["Task", "Author"]

      html = toggle(view, first, comment.id, "task")
      second = nested(first, comment.id, "task")
      assert column(html, second, "title") == ["Write the report"]
      # at depth 2 of 3 there are expanders still
      assert attribute(html, "[id='#{second}-row-#{task.id}-e'] > button", "aria-expanded") == [
               "false"
             ]

      expand(view, second, task.id)
      html = toggle(view, second, task.id, "comments")
      third = nested(second, task.id, "comments")
      assert column(html, third, "body") == ["Looks good"]

      # at the limit: no expander, no column for one, and the columns counted without it
      assert attribute(html, "[id='#{third}-table'] [data-expander]", "id") == []
      assert attribute(html, "[id='#{third}-expander-head']", "id") == []
      # the comments' boxes, their five columns and their actions
      assert attribute(html, "[id='#{third}-table']", "aria-colcount") == ["7"]
      assert attribute(html, "[id='#{third}-head-id']", "aria-colindex") == ["2"]
      # where the same table one level up has it
      assert attribute(html, "[id='#{first}-table']", "aria-colcount") == ["8"]
    end

    test "an event for a table at the limit, which that table never offers, opens nothing",
         %{conn: conn, task: task, comment: comment} do
      {:ok, view, _html} = live(conn, "/tasks")
      expand(view, task.id)
      toggle(view, task.id, "comments")
      first = nested(task.id, "comments")
      expand(view, first, comment.id)
      toggle(view, first, comment.id, "task")
      second = nested(first, comment.id, "task")
      expand(view, second, task.id)
      toggle(view, second, task.id, "comments")
      third = nested(second, task.id, "comments")

      html = expand(view, third, comment.id)
      assert_reply view, %{open: false}
      assert lines(html, third, comment.id) == []

      html = toggle(view, third, comment.id, "task")
      assert attribute(html, "[id='#{nested(third, comment.id, "task")}']", "id") == []
      assert attribute(html, "[id='#{third}-row-#{comment.id}-x']", "id") == []
    end

    test "the rows of a table with `max_depth 0` never expand, wherever it is shown",
         %{conn: conn, task: task} do
      {:ok, view, _html} = live(conn, "/tasks")
      expand(view, task.id)

      # the people have tasks assigned to them and reported by them, and a table that says 0
      html = toggle(view, task.id, "assignee")
      id = nested(task.id, "assignee")

      assert length(column(html, id, "name")) == 1
      assert attribute(html, "[id='#{id}-table'] [data-expander]", "id") == []
      assert attribute(html, "[id='#{id}-table']", "aria-colcount") == ["4"]
    end

    test "a table with `max_depth 1` on the page lets its nested tables expand no further",
         %{conn: conn, world: world, task: task} do
      [label] = labels(world, task, ["urgent"])
      key = "#{task.id}-#{label.id}"

      {:ok, view, _html} = live(conn, "/task_labels")
      expand(view, "task_label", key)
      html = toggle(view, "task_label", key, "task")
      id = nested("task_label", key, "task")

      # the task of a row with a key of two attributes
      assert column(html, id, "title") == ["Write the report"]
      # which on its own page has expanders, and here has none
      assert attribute(html, "[id='#{id}-table'] [data-expander]", "id") == []

      html = expand(view, id, task.id)
      assert_reply view, %{open: false}
      assert lines(html, id, task.id) == []

      html = toggle(view, "task_label", key, "label")
      assert column(html, nested("task_label", key, "label"), "name") == ["urgent"]
    end
  end

  describe "who is asking" do
    setup do
      world = world(tasks: 0)

      project =
        Generator.generate(
          Generator.project(organization_id: world.organization.id, name: "Aardvark")
        )

      own =
        task(world, "The member's own",
          project_id: project.id,
          assignee_id: world.member.id,
          estimate_hours: Decimal.new("8"),
          external_ref: "EXT-1"
        )

      other =
        task(world, "Somebody else's",
          project_id: project.id,
          assignee_id: world.admin.id,
          estimate_hours: Decimal.new("5"),
          external_ref: "EXT-2",
          inserted_at: DateTime.add(@moment, -1, :day)
        )

      comments(world, own, ["On the member's own"])
      %{world: world, project: project, own: own, other: other}
    end

    defp open(conn, path, id, key, relationship) do
      {:ok, view, _html} = live(conn, path)
      expand(view, id, key)
      {view, toggle(view, id, key, relationship)}
    end

    test "the admin sees every line, every column and may edit",
         %{conn: conn, world: world} = context do
      conn = log_in(conn, world.admin)
      {:ok, view, _html} = live(conn, "/tasks")
      assert length(lines(expand(view, context.own.id), context.own.id)) == 7

      {_view, html} = open(conn, "/projects", "project", context.project.id, "tasks")
      id = nested("project", context.project.id, "tasks")

      assert column(html, id, "external_ref") == ["EXT-1", "EXT-2"]
      assert column(html, id, "estimate_hours") == ["8 h", "5 h"]
      assert "title" in editors(html, id)
    end

    test "a line whose destination a person can never read is not there: the viewer and the people",
         %{conn: conn, world: world, own: own} do
      {:ok, view, _html} = conn |> log_in(world.viewer) |> live("/tasks")
      html = expand(view, own.id)

      assert lines(html, own.id) ==
               ["Comments", "First comment", "Newest comment", "Labels", "Project"]

      refute html =~ "Assignee"
      refute html =~ "Reported by"

      # and an event for it opens nothing
      html = toggle(view, own.id, "assignee")
      assert attribute(html, "[id='#{nested(own.id, "assignee")}']", "id") == []
      refute html =~ world.member.name

      # under a comment likewise: its task, not its author
      {:ok, view, _html} = conn |> log_in(world.viewer) |> live("/comments")
      [key] = attribute(render(view), "#comment-table > [role=rowgroup]:not([data-detail])", "id")
      key = String.replace_prefix(key, "comment-row-", "")
      assert lines(expand(view, "comment", key), "comment", key) == ["Task"]
    end

    test "a column the person can never see is not in a nested table, and a field hidden on some records is a placeholder there",
         %{conn: conn, world: world, project: project, own: own, other: other} do
      {_view, html} =
        conn |> log_in(world.member) |> open("/projects", "project", project.id, "tasks")

      id = nested("project", project.id, "tasks")

      assert column(html, id, "title") == ["The member's own", "Somebody else's"]
      refute "External ref" in headers(html, id)
      refute html =~ "EXT-1"
      # the estimate of the member's own task, and "Not available" for the other
      assert column(html, id, "estimate_hours") == ["8 h", "Not available"]
      assert attribute(html, cell(id, other.id, "estimate_hours"), "aria-readonly") == ["true"]
      assert attribute(html, cell(id, own.id, "estimate_hours"), "aria-readonly") == []
      refute html =~ ">5<"
    end

    test "a viewer's nested tables cannot be edited", %{
      conn: conn,
      world: world,
      project: project
    } do
      {view, html} =
        conn |> log_in(world.viewer) |> open("/projects", "project", project.id, "tasks")

      id = nested("project", project.id, "tasks")

      assert column(html, id, "title") == ["The member's own", "Somebody else's"]
      assert editors(html, id) == []
      assert attribute(html, "[id='#{id}-table'] [aria-readonly]", "id") == []

      # and a save that is sent all the same changes nothing
      [first | _] =
        attribute(html, "[id='#{id}-table'] > [role=rowgroup]:not([data-detail])", "id")

      key = String.replace_prefix(first, "#{id}-row-", "")
      save(view, id, key, "title", "Changed by a viewer")
      assert_reply view, %{ok: false}
      assert Ash.get!(Demo.Tracker.Task, key, authorize?: false).title == "The member's own"
    end

    test "a member may edit in a nested table what they may edit on its own page",
         %{conn: conn, world: world, project: project, own: own, other: other} do
      {view, _html} =
        conn |> log_in(world.member) |> open("/projects", "project", project.id, "tasks")

      id = nested("project", project.id, "tasks")

      html = save(view, id, own.id, "title", "Renamed by the member")
      assert text(html, cell(id, own.id, "title")) == "Renamed by the member"

      # reported by the admin, assigned to the admin: not the member's to change
      html = save(view, id, other.id, "title", "Not theirs")

      assert %{message: "You are not allowed to change this."} =
               failure(html, id, other.id, "title")

      assert Ash.get!(Demo.Tracker.Task, other.id, authorize?: false).title == "Somebody else's"
    end

    test "nobody has no rows to expand, and no line for what is refused to them", %{
      conn: conn,
      own: own
    } do
      {:ok, view, html} = live(conn, "/tasks")

      assert column(html, "task", "title") == []
      assert attribute(html, "#task-table [data-expander]", "id") == []

      html = expand(view, own.id)
      assert_reply view, %{open: false}
      assert lines(html, own.id) == []
    end

    test "the outsider sees the related records of their own organization only", %{
      conn: conn,
      world: world
    } do
      [theirs | _] = world.other_tasks

      Generator.generate(
        Generator.comment(
          organization_id: world.other_organization.id,
          task_id: theirs.id,
          author_id: world.outsider.id,
          body: "A comment in the other organization"
        )
      )

      {_view, html} =
        conn |> log_in(world.outsider) |> open("/tasks", "task", theirs.id, "comments")

      assert column(html, nested(theirs.id, "comments"), "body") ==
               ["A comment in the other organization"]

      refute html =~ "On the member's own"
    end

    test "a related record the person may not read is not among the rows, though its parent is theirs",
         %{conn: conn, world: world, own: own} do
      # a comment of the other organization on a task of this one
      Generator.generate(
        Generator.comment(
          organization_id: world.other_organization.id,
          task_id: own.id,
          author_id: world.outsider.id,
          body: "From the other organization"
        )
      )

      {_view, html} = conn |> log_in(world.admin) |> open("/tasks", "task", own.id, "comments")

      assert column(html, nested(own.id, "comments"), "body") == ["On the member's own"]
      assert text(html, "[id='#{nested(own.id, "comments")}-range']") == "1 record"
      refute html =~ "From the other organization"
    end
  end

  describe "an event the table never offered" do
    setup %{conn: conn} do
      world = world(tasks: 0)
      task = task(world, "Write the report")
      comments(world, task, ["Of an Acme task"])
      %{world: world, task: task, conn: conn}
    end

    test "for a row of another organization: the outsider sends the key of an Acme task",
         %{conn: conn, world: world, task: task} do
      {:ok, view, _html} = conn |> log_in(world.outsider) |> live("/tasks")

      html = expand(view, task.id)
      assert_reply view, %{open: false}
      assert lines(html, task.id) == []

      html = toggle(view, task.id, "comments")
      assert attribute(html, "[id='#{nested(task.id, "comments")}']", "id") == []
      refute html =~ "Of an Acme task"
    end

    test "for a row that is not on the page", %{conn: conn, world: world} do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")

      html = expand(view, Ecto.UUID.generate())
      assert_reply view, %{open: false}
      assert attribute(html, "#task-table [role=gridcell]", "role") != []
      assert attribute(html, "#task-table [role=gridcell][data-line]", "id") == []

      # nor without a row at all
      forge(view, "task", "expand", %{})
      assert_reply view, %{open: false}
    end

    test "for a line of a row that is not expanded", %{conn: conn, world: world, task: task} do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")

      html = toggle(view, task.id, "comments")

      assert attribute(html, "[id='#{nested(task.id, "comments")}']", "id") == []
      refute html =~ "Of an Acme task"
    end

    test "for a relationship the table does not offer: private, without a table, undeclared, or none",
         %{conn: conn, world: world, task: task} do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")
      expand(view, task.id)

      # `organization` and `task_labels` are private; neither is declared
      for name <- ["organization", "task_labels", "no_such_relationship", "", nil, %{"a" => "b"}] do
        html =
          forge(view, "task", "toggle", %{"row" => task.id, "relationship" => name})

        assert attribute(html, "#task-table[role=grid]", "role") != []
        assert attribute(html, "[id='task-row-#{task.id}-x'] [role=grid]", "id") == []
      end

      # the page is alive, and a line it does offer opens
      html = toggle(view, task.id, "comments")
      assert column(html, nested(task.id, "comments"), "body") == ["Of an Acme task"]
    end
  end

  describe "the total of a nested table" do
    setup %{conn: conn} do
      world = world(tasks: 0)

      project =
        Generator.generate(
          Generator.project(organization_id: world.organization.id, name: "Aardvark")
        )

      # one task whose estimate the member sees, and three whose estimate they do not
      task(world, "The member's own",
        project_id: project.id,
        assignee_id: world.member.id,
        estimate_hours: Decimal.new("20")
      )

      for n <- 1..3 do
        task(world, "Hidden estimate #{n}",
          project_id: project.id,
          assignee_id: world.admin.id,
          estimate_hours: Decimal.new("20")
        )
      end

      %{world: world, project: project, id: nested("project", project.id, "tasks"), conn: conn}
    end

    test "is shown and announced as on a page of its own while nothing is filtered",
         %{conn: conn, world: world, project: project, id: id} do
      {:ok, view, _html} = conn |> log_in(world.member) |> live("/projects")
      expand(view, "project", project.id)
      html = toggle(view, "project", project.id, "tasks")

      assert text(html, "[id='#{id}-range']") == "1–4 of 4"
      # four tasks, the two header rows and the footer row of the summaries
      assert attribute(html, "[id='#{id}-table']", "aria-rowcount") == ["7"]

      html = filter(view, id, "title", v: "Hidden")
      assert text(html, "[id='#{id}-range']") == "1–3 of 3"
      assert text(html, "[id='#{id}-status']") == "3 results"
    end

    # 4 tasks have an estimate above 10, and the member may know that of one.
    test "counts only the rows the person is shown while a filter is set on a column they see on some records only",
         %{conn: conn, world: world, project: project, id: id} do
      {:ok, view, _html} = conn |> log_in(world.member) |> live("/projects")
      expand(view, "project", project.id)
      toggle(view, "project", project.id, "tasks")

      html = filter(view, id, "estimate_hours", o: "greater_than", v: "10")

      assert column(html, id, "title") == ["The member's own"]
      assert text(html, "[id='#{id}-range']") == "1–1 of 1"
      assert text(html, "[id='#{id}-status']") == "1 result"
      assert attribute(html, "[id='#{id}-table']", "aria-rowcount") == ["4"]
      refute html =~ "of 4"
      refute html =~ "4 results"

      click(view, "[id='#{id}-filter-estimate_hours-clear']")
      html = render_async(view)

      assert text(html, "[id='#{id}-range']") == "1–4 of 4"
      assert text(html, "[id='#{id}-status']") == "4 results"
    end

    test "is shown to a person who sees the column on every record, filter or not",
         %{conn: conn, world: world, project: project, id: id} do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/projects")
      expand(view, "project", project.id)
      toggle(view, "project", project.id, "tasks")

      html = filter(view, id, "estimate_hours", o: "greater_than", v: "10")

      assert text(html, "[id='#{id}-range']") == "1–4 of 4"
      assert text(html, "[id='#{id}-status']") == "4 results"
    end
  end

  describe "a row whose record is gone or no longer the person's to read" do
    setup %{conn: conn} do
      world = world(tasks: 0)
      task = task(world, "Write the report")
      comments(world, task, ["First", "Second"])
      %{world: world, task: task, conn: log_in(conn, world.admin)}
    end

    test "a nested table that is opened under it says so, and not that there are no records",
         %{conn: conn, task: task} do
      {:ok, view, _html} = live(conn, "/tasks")
      expand(view, task.id)

      Demo.Repo.query!("DELETE FROM tasks WHERE id = $1", [Ecto.UUID.dump!(task.id)])
      html = toggle(view, task.id, "comments")
      id = nested(task.id, "comments")

      assert text(html, "[id='#{id}-error']") == "This record is no longer available."
      assert attribute(html, "[id='#{id}-error']", "role") == ["alert"]
      assert text(html, "[id='#{id}-empty']") == nil
      assert column(html, id, "body") == []
    end

    # The comments stay in the reader's organization and would be theirs to
    # read: only the read of the task itself says that they may not have them.
    test "an open nested table that reads again takes its rows away, whoever may read those rows",
         %{conn: conn, world: world, task: task} do
      {:ok, view, _html} = live(conn, "/tasks")
      expand(view, task.id)
      html = toggle(view, task.id, "comments")
      id = nested(task.id, "comments")
      assert column(html, id, "body") == ["Second", "First"]

      # the task moves to the other organization behind the table's back
      Demo.Repo.query!("UPDATE tasks SET organization_id = $1 WHERE id = $2", [
        Ecto.UUID.dump!(world.other_organization.id),
        Ecto.UUID.dump!(task.id)
      ])

      click(view, "[id='#{id}-head-body']")
      html = render_async(view)

      assert text(html, "[id='#{id}-error']") == "This record is no longer available."
      assert column(html, id, "body") == []
      refute html =~ "Second"
      assert text(html, "[id='#{id}-empty']") == nil
    end
  end

  describe "in German" do
    test "the expander, the lines and the texts of a nested table are translated", %{conn: conn} do
      world = world(tasks: 0)
      task = task(world, "Write the report")

      {:ok, view, html} = conn |> log_in(world.admin) |> in_locale("de") |> live("/tasks")

      assert text(html, "#task-expander-head") == "Zugehörige Einträge"

      assert attribute(html, "[id='task-row-#{task.id}-e'] > button", "aria-label") ==
               ["Zugehörige Einträge"]

      html = expand(view, task.id)

      assert lines(html, task.id) ==
               [
                 "Kommentare",
                 "Erster Kommentar",
                 "Neuester Kommentar",
                 "Labels",
                 "Projekt",
                 "Zugewiesen an",
                 "Gemeldet von"
               ]

      html =
        forge(view, "task", "toggle", %{"row" => task.id, "relationship" => "assignee"})

      assert text(html, "[id='#{nested(task.id, "assignee")}-loading']") == "Lädt…"

      html = render_async(view)
      id = nested(task.id, "assignee")
      assert headers(html, id) == ["Name", "E-Mail", "Rolle", "Zugewiesene Stunden"]
      assert text(html, "[id='#{id}-empty']") == "Keine Einträge"

      html = toggle(view, task.id, "comments")

      assert attribute(html, "[id='#{nested(task.id, "comments")}-pagination']", "aria-label") ==
               ["Seiten: Kommentare"]
    end
  end

  describe "tables placed in a page of the host's: /dashboard" do
    test "nest as mounted tables do, each in itself", %{conn: conn} do
      world = world(tasks: 0)
      task = task(world, "Write the report")
      comments(world, task, ["Looks good"])
      [project | _] = world.projects

      {:ok, view, html} = conn |> log_in(world.admin) |> live("/dashboard")

      assert attribute(html, "[id='dashboard-tasks-row-#{task.id}-e'] > button", "aria-expanded") ==
               ["false"]

      html = expand(view, "dashboard-tasks", task.id)
      assert length(lines(html, "dashboard-tasks", task.id)) == 7
      # the other table of the page is as it was
      assert lines(html, "dashboard-projects", project.id) == []

      html = toggle(view, "dashboard-tasks", task.id, "comments")

      assert column(html, nested("dashboard-tasks", task.id, "comments"), "body") == [
               "Looks good"
             ]

      expand(view, "dashboard-projects", project.id)
      html = toggle(view, "dashboard-projects", project.id, "tasks")

      assert column(html, nested("dashboard-projects", project.id, "tasks"), "title") ==
               ["Write the report"]

      refute_patched()
    end
  end
end
