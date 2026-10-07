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

  # twice, as every LiveView is rendered twice; and each time the session's actor
  test "opening the page reads the tasks and nothing related" do
    assert reads(:read) == [:user, :task, :user, :task]
    assert Enum.uniq(reads(:sql)) -- ["tasks", "users", "(subquery)"] == []
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

    view |> element("[id='#{nested(task.id, "comments")}-head-body']") |> render_click()
    render_async(view, 2000)

    assert Enum.sort(reads(:read)) == [:comment, :task]
    assert length(reads(:sql)) == 2
  end

  test "a save in a nested table reads and writes that record, and not the table around it",
       %{conn: conn, world: world, project: project, task: task} do
    {:ok, view, _html} = conn |> log_in(world.admin) |> live("/projects")
    expand(view, "project", project.id)
    toggle(view, "project", project.id, "tasks")
    id = nested("project", project.id, "tasks")
    forget()

    html = save(view, id, task.id, "title", "Write the summary")

    assert text(html, cell(id, task.id, "title")) == "Write the summary"
    # the task is read again by its key and saved; no project is read
    assert Enum.uniq(reads(:read)) == [:task]
    refute "projects" in reads(:sql)
  end
end
