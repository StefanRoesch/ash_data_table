defmodule DemoWeb.Tables.FullViewTest do
  @moduledoc """
  The full view of a nested table: the page of the destination's own table,
  limited to the records related to one record by the table's parameter
  `of`, which names that record and the relationship:
  `/comments?comment[of][task][comments]=ID` shows the comments of one task.

  The page reads as a nested table reads: the record is read again, as the
  person, on every read, with the related records as its load.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator
  alias Demo.Tracker.Task

  @moment ~U[2026-01-01 12:00:00.000000Z]

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
  defp comments(world, task, bodies) do
    for {body, index} <- Enum.with_index(bodies) do
      Generator.generate(
        Generator.comment(
          organization_id: task.organization_id,
          task_id: task.id,
          author_id: world.admin.id,
          body: body,
          inserted_at: DateTime.add(@moment, index, :minute)
        )
      )
    end
  end

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

  # The path of a table's page limited to the records related to a record.
  defp of(path, table, parent, relationship, key),
    do: "#{path}?#{table}[of][#{parent}][#{relationship}]=#{key}"

  defp heading(html, id), do: text(html, "##{id}-related-heading")

  # The parameters of the URL a patch went to.
  defp patched(view) do
    uri = view |> assert_patch() |> URI.parse()
    {uri.path, Plug.Conn.Query.decode(uri.query || "")}
  end

  # A table that is not limited: no heading, no way back.
  defp plain(html, id) do
    assert attribute(html, "##{id}-related", "id") == []
    assert attribute(html, "##{id}-related-clear", "id") == []
    html
  end

  describe "the records" do
    setup %{conn: conn} do
      world = world(tasks: 0, other_tasks: 0)
      task = task(world, "Write the report")
      other = task(world, "Another task")
      comments(world, task, ["First", "Second", "Third"])
      comments(world, other, ["Of the other task"])

      %{world: world, task: task, other: other, conn: log_in(conn, world.admin)}
    end

    test "of a has-many are those of the one record, as their own page shows them",
         %{conn: conn, task: task, other: other} do
      {:ok, _view, html} = live(conn, of("/comments", "comment", "task", "comments", task.id))

      assert headers(html, "comment") == ["ID", "Body", "Inserted at", "Task ID", "Author ID"]
      assert column(html, "comment", "body") == ["Third", "Second", "First"]
      assert text(html, "#comment-range") == "3 records"

      {:ok, _view, html} = live(conn, of("/comments", "comment", "task", "comments", other.id))
      assert column(html, "comment", "body") == ["Of the other task"]

      # and without the limit, all of them
      {:ok, _view, html} = live(conn, "/comments")
      assert length(column(html, "comment", "body")) == 4
    end

    test "of a many-to-many are those joined to the one record", %{
      conn: conn,
      world: world,
      task: task,
      other: other
    } do
      labels(world, task, ["urgent", "backend"])
      labels(world, other, ["frontend"])

      {:ok, _view, html} = live(conn, of("/labels", "label", "task", "labels", task.id))

      assert column(html, "label", "name") == ["backend", "urgent"]
      assert heading(html, "label") == "Write the report: Labels"
    end

    test "of a belongs-to is the one record it points at, with no sort, no filter and no pages",
         %{conn: conn, world: world, task: task} do
      [project | _] = world.projects

      {:ok, _view, html} = live(conn, of("/projects", "project", "task", "project", task.id))

      assert column(html, "project", "name") == [project.name]
      assert heading(html, "project") == "Write the report: Project"
      assert attribute(html, "#project-head-row th[aria-sort]", "id") == []
      assert attribute(html, "#project-filter-row :is(input, select)", "id") == []
      assert attribute(html, "#project-pagination", "id") == []
    end

    test "of a has-one that picks one of many is the one its own sort puts first", %{
      conn: conn,
      task: task
    } do
      {:ok, _view, html} =
        live(conn, of("/comments", "comment", "task", "latest_comment", task.id))

      assert column(html, "comment", "body") == ["Third"]
      assert heading(html, "comment") == "Write the report: Newest comment"

      {:ok, _view, html} =
        live(conn, of("/comments", "comment", "task", "first_comment", task.id))

      assert column(html, "comment", "body") == ["First"]

      # a sort or a filter in the URL does not change which one it is
      {:ok, _view, html} =
        live(
          conn,
          of("/comments", "comment", "task", "first_comment", task.id) <>
            "&comment[sort]=-inserted_at&comment[f][body]=Third"
        )

      assert column(html, "comment", "body") == ["First"]
    end

    test "of a record whose key has several attributes", %{conn: conn, world: world, task: task} do
      [label] = labels(world, task, ["urgent"])

      {:ok, _view, html} =
        live(
          conn,
          "/tasks?task[of][task_label][task][task_id]=#{task.id}&task[of][task_label][task][label_id]=#{label.id}"
        )

      assert column(html, "task", "title") == ["Write the report"]
    end
  end

  describe "the heading" do
    setup %{conn: conn} do
      world = world(tasks: 0, other_tasks: 0)
      task = task(world, "Write the report")
      comments(world, task, ["First"])

      %{world: world, task: task, conn: log_in(conn, world.admin)}
    end

    test "says whose records these are: the record by its label, and the relationship as its line is labelled",
         %{conn: conn, world: world, task: task} do
      {:ok, _view, html} = live(conn, of("/comments", "comment", "task", "comments", task.id))

      assert heading(html, "comment") == "Write the report: Comments"
      assert attribute(html, "#comment-related-heading", "id") == ["comment-related-heading"]
      # above the grid, and no part of it
      assert attribute(html, "#comment-table #comment-related", "id") == []

      [project | _] = world.projects
      {:ok, _view, html} = live(conn, of("/tasks", "task", "project", "tasks", project.id))
      assert heading(html, "task") == "#{project.name}: Tasks"
    end

    test "links the record to the page of its own table", %{conn: conn, task: task} do
      {:ok, _view, html} = live(conn, of("/comments", "comment", "task", "comments", task.id))

      assert text(html, "a#comment-related-parent") == "Write the report"
      assert attribute(html, "#comment-related-parent", "href") == ["/tasks"]
    end

    test "follows the record when the page is read again", %{conn: conn, task: task} do
      {:ok, view, _html} = live(conn, of("/comments", "comment", "task", "comments", task.id))

      task
      |> Ash.Changeset.for_update(:update, %{title: "Write the summary"})
      |> Ash.update!(authorize?: false)

      view |> element("#comment-head-body") |> render_click()
      assert heading(render_async(view), "comment") == "Write the summary: Comments"
    end

    test "is beside the page's own heading, and the grid keeps its name", %{
      conn: conn,
      task: task
    } do
      {:ok, _view, html} = live(conn, of("/comments", "comment", "task", "comments", task.id))

      # the page's heading is the first line of the table
      assert text(html, "#comment-page h1") == "Comments"
      assert attribute(html, "#comment-page h1", "id") == ["comment-name"]
      assert attribute(html, "#comment-table", "aria-label") == ["Comments"]
    end
  end

  describe "the way back to all records" do
    setup %{conn: conn} do
      world = world(tasks: 0, other_tasks: 0)
      task = task(world, "Write the report")
      other = task(world, "Another task")
      comments(world, task, ["First", "Second"])
      comments(world, other, ["Of the other task"])

      %{world: world, task: task, conn: log_in(conn, world.admin)}
    end

    test "is a control above the grid that takes the limit out of the URL", %{
      conn: conn,
      task: task
    } do
      {:ok, view, html} = live(conn, of("/comments", "comment", "task", "comments", task.id))

      assert text(html, "#comment-related-clear") == "Show all records"
      assert attribute(html, "#comment-related-clear", "href") == ["/comments"]

      view |> element("#comment-related-clear") |> render_click()

      assert patched(view) == {"/comments", %{}}
      html = plain(render_async(view), "comment")
      assert length(column(html, "comment", "body")) == 3
    end

    test "takes with it the sort, the filters and the page that were chosen under the limit",
         %{conn: conn, task: task} do
      {:ok, view, html} =
        live(
          conn,
          of("/comments", "comment", "task", "comments", task.id) <>
            "&comment[sort]=body&comment[f][body]=Second"
        )

      assert column(html, "comment", "body") == ["Second"]
      assert attribute(html, "#comment-related-clear", "href") == ["/comments"]

      view |> element("#comment-related-clear") |> render_click()

      assert patched(view) == {"/comments", %{}}
      assert length(column(render_async(view), "comment", "body")) == 3
    end
  end

  describe "sort, filters and pages under the limit" do
    setup %{conn: conn} do
      world = world(tasks: 0, other_tasks: 0)

      project =
        Generator.generate(
          Generator.project(organization_id: world.organization.id, name: "Aardvark")
        )

      for n <- 1..30 do
        task(world, "Task #{String.pad_leading("#{n}", 2, "0")}",
          project_id: project.id,
          progress: n,
          inserted_at: DateTime.add(@moment, n, :minute)
        )
      end

      # and one of another project, which is never among them
      task(world, "Task 99 of another project", progress: 99)

      %{
        world: world,
        project: project,
        path: of("/tasks", "task", "project", "tasks", project.id),
        limit: %{"of" => %{"project" => %{"tasks" => project.id}}},
        conn: log_in(conn, world.admin)
      }
    end

    test "work as on any page, and the limit stays in the URL through each of them",
         %{conn: conn, path: path, limit: limit} do
      {:ok, view, html} = live(conn, path)

      assert text(html, "#task-range") == "1–25 of 30"
      assert hd(column(html, "task", "title")) == "Task 30"

      # a sort
      view |> element("#task-head-title") |> render_click()
      assert patched(view) == {"/tasks", %{"task" => Map.put(limit, "sort", "title")}}
      html = render_async(view)
      assert hd(column(html, "task", "title")) == "Task 01"
      assert heading(html, "task") == "Aardvark: Tasks"

      # a page
      view |> element("#task-next") |> render_click()

      assert patched(view) ==
               {"/tasks", %{"task" => Map.merge(limit, %{"sort" => "title", "page" => "2"})}}

      html = render_async(view)
      assert column(html, "task", "title") == Enum.map(26..30, &"Task #{&1}")
      assert text(html, "#task-range") == "26–30 of 30"

      # a filter, which starts at the first page again
      filter(view, "task", "progress", o: "at_least", v: "29")

      assert patched(view) ==
               {"/tasks",
                %{
                  "task" =>
                    Map.merge(limit, %{
                      "sort" => "title",
                      "f" => %{"progress" => %{"at_least" => "29"}}
                    })
                }}

      html = render(view)
      assert column(html, "task", "title") == ["Task 29", "Task 30"]
      assert text(html, "#task-range") == "1–2 of 2"

      # clearing the filters leaves the limit and the sort
      view |> element("#task-clear-filters") |> render_click()
      assert patched(view) == {"/tasks", %{"task" => Map.put(limit, "sort", "title")}}
      assert text(render_async(view), "#task-range") == "1–25 of 30"
    end

    test "are read from a URL that is opened afresh, as a shared link is", %{
      conn: conn,
      path: path
    } do
      {:ok, _view, html} =
        live(conn, path <> "&task[sort]=-title&task[f][progress][at_most]=28&task[page]=2")

      assert column(html, "task", "title") == ["Task 03", "Task 02", "Task 01"]
      assert text(html, "#task-range") == "26–28 of 28"
      assert heading(html, "task") == "Aardvark: Tasks"
      assert attribute(html, "#task-head-title", "aria-sort") == ["descending"]
    end

    test "the first response of the server holds the limited rows already", %{
      conn: conn,
      path: path
    } do
      html = conn |> get(path) |> html_response(200)

      assert text(html, "#task-range") == "1–25 of 30"
      assert heading(html, "task") == "Aardvark: Tasks"
      refute html =~ "Task 99 of another project"
    end
  end

  describe "a limit that names nothing the table has" do
    setup %{conn: conn} do
      world = world(tasks: 0, other_tasks: 0)
      task = task(world, "Write the report")
      other = task(world, "Another task")
      comments(world, task, ["First", "Second"])
      comments(world, other, ["Of the other task"])
      [label] = labels(world, task, ["urgent"])

      %{world: world, task: task, label: label, conn: log_in(conn, world.admin)}
    end

    test "is ignored: the page shows the table as if nothing had been asked", %{
      conn: conn,
      task: task,
      label: label
    } do
      id = task.id

      for query <- [
            # a resource the application does not have, and names of modules
            "comment[of][nothing][comments]=#{id}",
            "comment[of][Elixir.Demo.Tracker.Task][comments]=#{id}",
            "comment[of][Demo.Tracker.Task][comments]=#{id}",
            "comment[of][Task][comments]=#{id}",
            "comment[of][String][to_atom]=#{id}",
            # a resource with no relationship to comments
            "comment[of][label][tasks]=#{label.id}",
            "comment[of][project][comments]=#{id}",
            # a relationship of the task to something else
            "comment[of][task][labels]=#{id}",
            "comment[of][task][project]=#{id}",
            # no relationship, a private one, an attribute
            "comment[of][task][nothing]=#{id}",
            "comment[of][task][organization]=#{id}",
            "comment[of][task][title]=#{id}",
            # shapes the table never writes
            "comment[of]=#{id}",
            "comment[of][task]=#{id}",
            "comment[of][task][comments][id]=#{id}",
            "comment[of][task][comments][]=#{id}",
            "comment[of][task][comments]=",
            "comment[of][task][comments]=not-a-key",
            "comment[of][task][comments]=#{id}&comment[of][task][latest_comment]=#{id}",
            "comment[of][task][comments]=#{id}&comment[of][project][tasks]=#{id}",
            # the parameter of another table
            "task[of][task][comments]=#{id}"
          ] do
        {:ok, _view, html} = live(conn, "/comments?" <> query)

        html = plain(html, "comment")
        assert length(column(html, "comment", "body")) == 3, query
        assert text(html, "#comment-error") == nil, query
        refute html =~ "Write the report", query
      end
    end

    test "a private relationship is not one to reach a table through", %{conn: conn, task: task} do
      # `Task.task_labels` is the task's own, not public, relationship to its labels' join
      {:ok, _view, html} = live(conn, "/task_labels?task_label[of][task][task_labels]=#{task.id}")

      plain(html, "task_label")
      assert length(column(html, "task_label", "note")) == 1
    end

    test "a relationship of a table whose rows never expand is not one either", %{
      conn: conn,
      world: world
    } do
      # people have `max_depth 0`: no row of theirs ever opens their assigned tasks
      {:ok, _view, html} =
        live(conn, "/tasks?task[of][user][assigned_tasks]=#{world.admin.id}")

      plain(html, "task")
      assert length(column(html, "task", "title")) == 2
    end

    test "is dropped from the URL by the next change of the table", %{conn: conn, task: task} do
      {:ok, view, _html} = live(conn, "/comments?comment[of][nothing][comments]=#{task.id}")

      view |> element("#comment-head-body") |> render_click()

      assert patched(view) == {"/comments", %{"comment" => %{"sort" => "body"}}}
    end
  end

  describe "a record that is not the person's to read" do
    setup %{conn: conn} do
      world = world(tasks: 0, other_tasks: 0)
      task = task(world, "Write the secret report")
      comments(world, task, ["A secret comment"])

      %{
        world: world,
        task: task,
        path: of("/comments", "comment", "task", "comments", task.id),
        conn: conn
      }
    end

    # No record is named, nothing of it or of its related records is shown,
    # and "No records" is not said: nothing is known about them.
    defp nothing_told(html) do
      assert text(html, "#comment-error") == "This record is no longer available."
      assert column(html, "comment", "body") == []
      assert text(html, "#comment-empty") == nil
      assert heading(html, "comment") == "Comments"
      assert attribute(html, "#comment-related-parent", "id") == []
      refute html =~ "secret"
      # the way back is there
      assert attribute(html, "#comment-related-clear", "href") == ["/comments"]
      html
    end

    test "that is of another organization gives a person nothing: not its related records, not its name",
         %{conn: conn, world: world, path: path} do
      {:ok, view, html} = conn |> log_in(world.outsider) |> live(path)
      nothing_told(html)

      # nor after a change of the table, which reads again
      view |> element("#comment-head-body") |> render_click()
      nothing_told(render_async(view))

      # nor in the server's first response
      conn |> log_in(world.outsider) |> get(path) |> html_response(200) |> nothing_told()
    end

    test "that does not exist gives the same", %{conn: conn, world: world} do
      missing = of("/comments", "comment", "task", "comments", Ash.UUID.generate())

      for actor <- [world.admin, world.outsider] do
        {:ok, _view, html} = conn |> log_in(actor) |> live(missing)
        nothing_told(html)
      end
    end

    test "that is gone since the page was opened gives the same on the next read", %{
      conn: conn,
      world: world,
      task: task,
      path: path
    } do
      {:ok, view, html} = conn |> log_in(world.admin) |> live(path)
      assert heading(html, "comment") == "Write the secret report: Comments"

      Ash.destroy!(task, authorize?: false)
      view |> element("#comment-head-body") |> render_click()

      nothing_told(render_async(view))
    end

    test "is read as the person on every read: one that stops being theirs stops being shown",
         %{conn: conn, world: world, task: task, path: path} do
      {:ok, view, html} = conn |> log_in(world.member) |> live(path)
      assert column(html, "comment", "body") == ["A secret comment"]

      # moved to the other organization, with its comments left behind
      Demo.Repo.query!("UPDATE tasks SET organization_id = $1 WHERE id = $2", [
        Ecto.UUID.dump!(world.other_organization.id),
        Ecto.UUID.dump!(task.id)
      ])

      view |> element("#comment-head-body") |> render_click()

      nothing_told(render_async(view))
    end

    test "nobody, whose read of the comments is refused, is told that and no more", %{
      conn: conn,
      path: path
    } do
      {:ok, _view, html} = conn |> log_in(nil) |> live(path)

      # the comments' table says `on_forbidden :message`; the limit is not
      # one nobody is offered, so the table is as it is without it
      assert text(html, "#comment-error") == "You are not allowed to see these records."
      assert attribute(html, "#comment-related", "id") == []
      refute html =~ "secret"
    end

    test "nobody, whose read of the record itself is refused, gets the page that does not exist",
         %{conn: conn, world: world} do
      [project | _] = world.projects

      # projects are refused outright when nobody is logged in, tasks are not
      assert_raise AshTable.NotFoundError, fn ->
        conn |> log_in(nil) |> live(of("/tasks", "task", "project", "tasks", project.id))
      end

      assert_error_sent 404, fn ->
        conn |> log_in(nil) |> get(of("/tasks", "task", "project", "tasks", project.id))
      end
    end
  end

  describe "a field of the record that the person may not see" do
    test "is not what the heading calls it by: the next of its columns that they see is",
         %{conn: conn} do
      world = world(tasks: 0, other_tasks: 0)
      task = task(world, "Write the report")
      [label] = labels(world, task, ["urgent"])

      # the join of a task and a label has no label of its own: its first
      # column, the note, is empty here, and its second is the task's key
      {:ok, _view, html} =
        conn
        |> log_in(world.admin)
        |> live(
          "/labels?label[of][task_label][label][task_id]=#{task.id}&label[of][task_label][label][label_id]=#{label.id}"
        )

      assert column(html, "label", "name") == ["urgent"]
      assert heading(html, "label") == "#{task.id}: Label"
    end
  end

  describe "editing and expanding under the limit" do
    setup %{conn: conn} do
      world = world(tasks: 0, other_tasks: 0)
      [project | _] = world.projects
      task = task(world, "Write the report")
      comments(world, task, ["First"])

      %{
        world: world,
        project: project,
        task: task,
        path: of("/tasks", "task", "project", "tasks", project.id),
        conn: log_in(conn, world.admin)
      }
    end

    test "a cell is edited as on any page", %{
      conn: conn,
      task: task,
      path: path,
      project: project
    } do
      {:ok, view, html} = live(conn, path)
      assert "title" in editors(html, "task")

      html = save(view, task.id, "title", "Write the summary")

      assert text(html, cell(task.id, "title")) == "Write the summary"
      assert Ash.get!(Task, task.id, authorize?: false).title == "Write the summary"
      # and the row keeps what its other cells show
      assert text(html, cell(task.id, "project")) == project.name
      assert heading(html, "task") == "#{project.name}: Tasks"

      html = save(view, task.id, "title", "No")
      assert %{shown: "No"} = failure(html, task.id, "title")
    end

    test "a row expands into its nested tables, counted from this page's table", %{
      conn: conn,
      task: task,
      path: path
    } do
      {:ok, view, _html} = live(conn, path)

      html = expand(view, task.id)
      assert "Comments" in lines(html, task.id)

      html = toggle(view, task.id, "comments")
      id = nested(task.id, "comments")
      assert column(html, id, "body") == ["First"]

      # and that nested table has its own link to its own full view
      assert attribute(html, "[id='#{id}-full-view']", "href") ==
               ["/comments?comment[of][task][comments]=#{task.id}"]
    end
  end

  describe "the total under the limit" do
    # 30 tasks whose estimate the member sees (their own) and 30 whose
    # estimate is hidden from them, every estimate 20: a count that ignores
    # the field policies says 60 where the member's rows say 30.
    setup %{conn: conn} do
      world = world(tasks: 0)

      project =
        Generator.generate(
          Generator.project(organization_id: world.organization.id, name: "Aardvark")
        )

      for {owner, kind} <- [{world.member, "Own"}, {world.admin, "Hidden"}], n <- 1..30 do
        task(world, "#{kind} #{String.pad_leading("#{n}", 2, "0")}",
          project_id: project.id,
          assignee_id: owner.id,
          estimate_hours: Decimal.new("20"),
          inserted_at: DateTime.add(@moment, n, :minute)
        )
      end

      %{world: world, path: of("/tasks", "task", "project", "tasks", project.id), conn: conn}
    end

    test "is shown while no filter is set on a column the person sees on some records only",
         %{conn: conn, world: world, path: path} do
      {:ok, view, html} = conn |> log_in(world.member) |> live(path)
      assert text(html, "#task-range") == "1–25 of 60"

      html = filter(view, "task", "title", v: "Own")
      assert text(html, "#task-range") == "1–25 of 30"
    end

    test "is not shown or announced while one is, as in a nested table", %{
      conn: conn,
      world: world,
      path: path
    } do
      {:ok, view, _html} = conn |> log_in(world.member) |> live(path)

      html = filter(view, "task", "estimate_hours", o: "at_least", v: "10")

      # their 30 rows match; the 30 whose estimate they may not see do not,
      # and nothing says how many of those there are
      assert length(column(html, "task", "title")) == 25
      assert text(html, "#task-range") == "1–25"
      assert attribute(html, "#task-table", "aria-rowcount") == ["-1"]
      assert text(html, "#task-status") == "Results updated"
      refute html =~ "of 60"
      refute html =~ "of 30"

      # opened afresh with that filter in the URL
      {:ok, _view, html} =
        conn |> log_in(world.member) |> live(path <> "&task[f][estimate_hours][at_least]=10")

      assert text(html, "#task-range") == "1–25"

      # the admin, who sees every estimate, is told
      {:ok, _view, html} =
        conn |> log_in(world.admin) |> live(path <> "&task[f][estimate_hours][at_least]=10")

      assert text(html, "#task-range") == "1–25 of 60"
    end
  end

  describe "in German" do
    test "the heading, the way back and the link of a nested table are German", %{conn: conn} do
      world = world(tasks: 0, other_tasks: 0)
      task = task(world, "Write the report")
      comments(world, task, ["First"])
      conn = conn |> log_in(world.admin) |> in_locale("de")

      {:ok, _view, html} = live(conn, of("/comments", "comment", "task", "comments", task.id))

      assert heading(html, "comment") == "Write the report: Kommentare"
      assert text(html, "#comment-related-clear") == "Alle Einträge anzeigen"

      {:ok, view, _html} = live(conn, "/tasks")
      expand(view, task.id)
      html = toggle(view, task.id, "comments")
      id = nested(task.id, "comments")

      assert text(html, "[id='#{id}-full-view']") == "In voller Ansicht öffnen"

      assert attribute(html, "[id='#{id}-full-view']", "aria-label") ==
               ["In voller Ansicht öffnen: Kommentare"]
    end
  end
end
