defmodule DemoWeb.Tables.NestedTableReadsTest do
  @moduledoc """
  What a nested table reads, and when: nothing before its line is opened,
  one read when it is, and nothing of the table around it or of the tables
  beside it.

  Observed through Ash's telemetry of read actions and the repo's telemetry
  of SQL statements, which are sent for every process of the system: so
  these tests do not run beside others.
  """
  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator

  setup %{conn: conn} do
    world = world(tasks: 0)
    [project | _] = world.projects

    [task, other] =
      for title <- ["Write the report", "Another task"] do
        Generator.generate(
          Generator.task(
            organization_id: world.organization.id,
            project_id: project.id,
            reporter_id: world.admin.id,
            title: title
          )
        )
      end

    for task <- [task, other] do
      Generator.generate(
        Generator.comment(
          organization_id: world.organization.id,
          task_id: task.id,
          author_id: world.admin.id,
          body: "A comment"
        )
      )
    end

    test = self()
    handler = "nested-reads-#{System.unique_integer()}"

    :telemetry.attach_many(
      handler,
      [[:ash, :tracker, :read, :stop], [:demo, :repo, :query]],
      fn
        [:ash | _], _measurements, metadata, _config ->
          send(test, {:read, metadata.resource_short_name})

        [:demo | _], _measurements, metadata, _config ->
          # a statement that reads from a subquery has no source
          send(test, {:sql, metadata.source || "(subquery)"})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")
    # the footer summaries of the tasks are asked for beside the rows: a
    # test starts once they are there
    render_async(view, 10_000)
    %{view: view, conn: conn, world: world, project: project, task: task, other: other}
  end

  # Everything that was read since the last call, by kind.
  defp reads(kind) do
    Process.sleep(20)
    collect(kind, [])
  end

  defp collect(kind, found) do
    receive do
      {^kind, what} -> collect(kind, [what | found])
    after
      0 -> Enum.reverse(found)
    end
  end

  defp forget do
    reads(:read)
    reads(:sql)
  end

  # Twice, as every LiveView is rendered twice; and each time the session's
  # actor. With the tasks go the records their reference columns show: the
  # project, the assignee and the reporter of the page's tasks, each read
  # once for the whole page.
  test "opening the page reads the tasks, the labels of their reference columns, and nothing else related" do
    once = [:user, :project, :user, :user, :task]

    assert reads(:read) |> Enum.chunk_every(5) |> Enum.map(&Enum.sort/1) ==
             [Enum.sort(once), Enum.sort(once)]

    assert Enum.uniq(reads(:sql)) -- ["tasks", "users", "projects", "(subquery)"] == []
  end

  test "a page reads the related records of each reference column in one statement, however many rows it has",
       %{view: view, world: world, project: project} do
    people =
      for name <- ["Ada", "Grace", "Linus"] do
        Generator.generate(Generator.user(organization_id: world.organization.id, name: name))
      end

    for {person, index} <- Enum.with_index(people), reporter <- people do
      Generator.generate(
        Generator.task(
          organization_id: world.organization.id,
          project_id: project.id,
          reporter_id: reporter.id,
          assignee_id: person.id,
          title: "Task #{index} of #{reporter.name}"
        )
      )
    end

    forget()

    # a new read of the page: eleven tasks, of four reporters and three assignees
    html = view |> element("#task-head-title") |> render_click()
    render_async(view)

    assert length(column(html, "task", "title")) == 2
    assert length(column(render(view), "task", "title")) == 11

    assert Enum.sort(reads(:read)) == [:project, :task, :user, :user]

    # The page, its count, and the aggregate of the page's tasks, which is
    # read in a statement of its own (the library's internal ticket #35);
    # and one statement per reference column.
    assert Enum.frequencies(reads(:sql)) == %{"tasks" => 3, "projects" => 1, "users" => 2}
  end

  test "expanding a row reads nothing", %{view: view, task: task} do
    forget()
    expand(view, task.id)

    assert reads(:read) == []
    assert reads(:sql) == []
  end

  test "opening a line reads the parent with its related records, once: two statements",
       %{view: view, task: task} do
    expand(view, task.id)
    forget()

    toggle(view, task.id, "comments")

    # the task by its key, as the person, and the comments as its load
    assert Enum.sort(reads(:read)) == [:comment, :task]
    # one for the task with the count, one for the page of its comments
    assert Enum.sort(reads(:sql)) == ["(subquery)", "tasks"]
  end

  test "opening a second line, and a line of another row, reads those alone",
       %{view: view, task: task, other: other} do
    expand(view, task.id)
    expand(view, other.id)
    toggle(view, task.id, "comments")
    forget()

    toggle(view, task.id, "project")
    assert Enum.sort(reads(:read)) == [:project, :task]

    toggle(view, other.id, "comments")
    assert Enum.sort(reads(:read)) == [:comment, :task]

    # closing reads nothing
    toggle(view, task.id, "project")
    expand(view, other.id)
    assert reads(:read) == []
  end

  test "sorting a nested table reads it again, and nothing of the table around it or beside it",
       %{view: view, task: task} do
    expand(view, task.id)
    toggle(view, task.id, "comments")
    toggle(view, task.id, "labels")
    forget()

    click(view, "[id='#{nested(task.id, "comments")}-head-body']")
    render_async(view)

    assert Enum.sort(reads(:read)) == [:comment, :task]
    assert length(reads(:sql)) == 2
  end

  test "a save in a nested table reads and writes that record with what its row shows, and not the table around it",
       %{view: tasks_page, conn: conn, world: world, project: project, task: task} do
    # The page of the tasks that the setup opened is closed first. Tasks are
    # live: it would hear of the save below and read the task again, a
    # moment later, and those reads would be counted here or not.
    GenServer.stop(tasks_page.pid)

    {:ok, view, _html} = conn |> log_in(world.admin) |> live("/projects")
    expand(view, "project", project.id)
    toggle(view, "project", project.id, "tasks")
    id = nested("project", project.id, "tasks")
    # the nested tasks have footer summaries, which are there by now
    render_async(view, 10_000)
    forget()

    html = save(view, id, task.id, "title", "Write the summary")
    # the summaries of the nested tasks are asked for again after the save
    render_async(view, 10_000)

    assert text(html, cell(id, task.id, "title")) == "Write the summary"
    # The task is read again by its key and saved, and shown with the labels
    # of its reference columns: its project, its assignee and its reporter,
    # each by its key. For the footer summaries of the nested tasks, their
    # project is read once more by its key, with the keys of its tasks as
    # its load. The projects' own table, around it, is not read again: that
    # would be a page, and its count.
    assert Enum.sort(reads(:read)) == [:project, :project, :task, :task, :user, :user]
    # with the summaries: the project by its key, the keys of its tasks,
    # and the statement that computes them
    assert Enum.frequencies(reads(:sql)) == %{"tasks" => 5, "users" => 2, "projects" => 2}
  end
end
