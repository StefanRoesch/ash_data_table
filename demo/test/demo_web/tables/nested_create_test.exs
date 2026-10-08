defmodule DemoWeb.Tables.NestedCreateTest do
  @moduledoc """
  Row create in a nested table, and in its full view: the comments of a
  task, under `/tasks` and at `/comments?comment[of][task][comments]=ID`.

  A nested table creates only where it can say what joins the new record to
  its row: in a has-many whose create action accepts the linking field. It
  gives that field itself, from the row it belongs to, and never shows it.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator
  alias Demo.Tracker.Comment

  @moment ~U[2026-01-01 12:00:00.000000Z]

  defp task(world, title, overrides \\ []) do
    [project | _] = world.projects

    Generator.generate(
      Generator.task(
        [
          organization_id: world.organization.id,
          project_id: project.id,
          reporter_id: world.admin.id,
          assignee_id: world.member.id,
          title: title,
          inserted_at: @moment
        ] ++ overrides
      )
    )
  end

  defp comment(world, task, body) do
    Generator.generate(
      Generator.comment(
        organization_id: task.organization_id,
        task_id: task.id,
        author_id: world.admin.id,
        body: body,
        inserted_at: @moment
      )
    )
  end

  # every comment there is, whoever may see it, as {body, task, author}
  defp stored do
    Comment
    |> Ash.read!(authorize?: false)
    |> Enum.map(&{&1.body, &1.task_id, &1.author_id})
    |> Enum.sort()
  end

  # The create button of a line: on the line itself, after its label.
  defp line_create(key, relationship), do: "[id='task-row-#{key}-l-#{relationship}-create']"

  defp open_line(view, key, relationship) do
    expand(view, key)
    toggle(view, key, relationship)
  end

  setup %{conn: conn} do
    world = world(tasks: 0)
    task = task(world, "Write the report")
    other = task(world, "File the report")
    comment(world, task, "First!")

    %{conn: log_in(conn, world.member), world: world, task: task, other: other}
  end

  describe "the create button of a nested table" do
    test "stands on the line of its relationship, after the label, while the line is open",
         %{conn: conn, task: task} do
      {:ok, view, _html} = live(conn, "/tasks")

      html = expand(view, task.id)
      assert lines(html, task.id) |> hd() == "Comments"
      assert text(html, line_create(task.id, "comments")) == nil

      html = toggle(view, task.id, "comments")
      button = line_create(task.id, "comments")

      assert text(html, button) == "New comment"
      # in the line's cell, right after the button that opens the line
      assert attribute(html, "[id='task-row-#{task.id}-l-comments-c'] > button", "id") == [
               "task-row-#{task.id}-l-comments-b",
               "task-row-#{task.id}-l-comments-create"
             ]

      # the line's own button says "Comments" and nothing else
      assert text(html, "[id='task-row-#{task.id}-l-comments-b']") == "Comments"
      # out of the tab order, as everything in the grid
      assert attribute(html, button, "tabindex") == ["-1"]
      # shown once the nested table has read: it says so itself
      assert attribute(html, "[id='#{nested(task.id, "comments")}']", "data-read") == [""]

      html = toggle(view, task.id, "comments")
      assert text(html, button) == nil
    end

    test "is offered for a has-many whose create action takes the linking field, and for nothing else",
         %{conn: conn, task: task} do
      {:ok, view, _html} = live(conn, "/tasks")
      expand(view, task.id)

      # a has-one, a many-to-many and a belongs-to: their resources have a
      # create button on pages of their own, and none here
      for relationship <- ~w(first_comment latest_comment labels project assignee) do
        html = toggle(view, task.id, relationship)
        assert text(html, line_create(task.id, relationship)) == nil, relationship
        assert html =~ nested(task.id, relationship)
      end
    end

    test "is not there for a person who may never create", %{conn: conn, world: world, task: task} do
      {:ok, view, _html} = conn |> log_in(world.viewer) |> live("/tasks")

      html = open_line(view, task.id, "comments")

      assert column(html, nested(task.id, "comments"), "body") == ["First!"]
      assert text(html, line_create(task.id, "comments")) == nil
    end

    test "follows the person asking, who changes while the page is open",
         %{conn: conn, world: world, task: task} do
      conn =
        Phoenix.ConnTest.init_test_session(conn, %{"assigns" => %{actor_id: world.member.id}})

      {:ok, view, _html} = live(conn, "/support/switch")

      comments = nested("tasks", task.id, "comments")
      button = "[id='tasks-row-#{task.id}-l-comments-create']"

      # what is open is closed when the person changes: opened again each time
      open = fn ->
        expand(view, "tasks", task.id)
        toggle(view, "tasks", task.id, "comments")
      end

      become = fn user ->
        view |> element("#become") |> render_click(%{"id" => user.id})
        render_async(view, 2000)
      end

      assert text(open.(), button) == "New comment"

      # a viewer reads the comments and may never write one
      become.(world.viewer)
      html = open.()
      assert column(html, comments, "body") == ["First!"]
      assert text(html, button) == nil

      become.(world.member)
      assert text(open.(), button) == "New comment"
    end
  end

  describe "creating in a nested table" do
    setup %{conn: conn, task: task} do
      {:ok, view, _html} = live(conn, "/tasks")
      open_line(view, task.id, "comments")
      %{view: view, comments: nested(task.id, "comments")}
    end

    defp press(view, key, relationship),
      do: view |> element(line_create(key, relationship)) |> render_click()

    test "opens the panel of that table, without the field that joins the record to the row",
         %{view: view, task: task, comments: comments} do
      html = press(view, task.id, "comments")

      assert panel(html, comments) == %{
               heading: "New comment",
               fields: [
                 %{
                   name: "body",
                   label: "Body",
                   control: "textarea",
                   value: "",
                   required?: true,
                   errors: []
                 }
               ],
               errors: [],
               submit: "Create"
             }

      # the table on the page has no panel of its own for it
      assert panel(html, "task") == nil
      refute html =~ "panel[task_id]"
    end

    test "creates the record under the row, as the person, and shows it first",
         %{view: view, world: world, task: task, comments: comments} do
      press(view, task.id, "comments")

      html = run_panel(view, comments, body: "Second!")

      assert panel(html, comments) == nil
      assert column(html, comments, "body") == ["Second!", "First!"]
      assert announcement(html, comments) == "Comment created"

      assert stored() == [
               {"First!", task.id, world.admin.id},
               {"Second!", task.id, world.member.id}
             ]
    end

    test "does not read the row above again: what it counts stays until the next read",
         %{view: view, task: task, comments: comments} do
      press(view, task.id, "comments")
      html = run_panel(view, comments, body: "Second!")

      assert text(html, cell(task.id, "comment_count")) == "1"

      # the line is still open, and nothing was read again around it
      assert column(html, comments, "body") == ["Second!", "First!"]
    end

    test "takes the row from the table and not from the form: another row's key is not looked at",
         %{view: view, world: world, task: task, other: other, comments: comments} do
      press(view, task.id, "comments")

      send_panel(view, comments, %{
        "panel" => %{"body" => "Smuggled", "task_id" => other.id, "author_id" => world.admin.id},
        "task_id" => other.id,
        "parent_key" => %{"id" => other.id}
      })

      assert stored() == [
               {"First!", task.id, world.admin.id},
               {"Smuggled", task.id, world.member.id}
             ]
    end

    test "reads the row again first, as the person: under a row that is gone nothing is created",
         %{view: view, world: world, task: task, comments: comments} do
      press(view, task.id, "comments")

      # the task moves to the other organization: no longer the member's to read
      Ash.update!(task, %{}, action: :update, authorize?: false)

      Demo.Repo.query!("UPDATE tasks SET organization_id = $1 WHERE id = $2", [
        Ecto.UUID.dump!(world.other_organization.id),
        Ecto.UUID.dump!(task.id)
      ])

      html = run_panel(view, comments, body: "Into the void")

      assert panel(html, comments).errors == ["This record is no longer available."]
      assert stored() == [{"First!", task.id, world.admin.id}]

      # and its button opens nothing any more
      cancel_panel(view, comments)
      assert panel(press(view, task.id, "comments"), comments) == nil
    end

    test "that the action refuses stays open with the error at its field", %{
      view: view,
      task: task,
      comments: comments
    } do
      press(view, task.id, "comments")

      html = run_panel(view, comments, body: "")

      assert [%{name: "body", errors: ["is required"]}] = panel(html, comments).fields
      assert length(stored()) == 1
    end

    test "is gone with its line when the line is closed", %{
      view: view,
      task: task,
      comments: comments
    } do
      assert panel(press(view, task.id, "comments"), comments) != nil

      html = toggle(view, task.id, "comments")

      refute html =~ comments
      assert panel(html, comments) == nil
    end
  end
end
