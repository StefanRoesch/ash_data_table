defmodule DemoWeb.Tables.NamedTableTest do
  @moduledoc """
  Named tables, as a person meets them in the demo: the board of the tasks
  (`/tasks/board`) and the compact comments (`/comments/compact`), each a
  second table of its resource beside the default one; the compact comments
  nested under a task of the board; and two tables of the comments on one
  page (`/named`).

  Both named tables are declared in a file of their own, as a fragment of
  their resource.
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
          assignee_id: nil,
          title: title,
          status: :in_progress,
          inserted_at:
            DateTime.add(@moment, System.unique_integer([:positive, :monotonic]), :millisecond)
        ] ++ overrides
      )
    )
  end

  defp comment(world, task, body) do
    Generator.generate(
      Generator.comment(
        organization_id: world.organization.id,
        task_id: task.id,
        author_id: world.admin.id,
        body: body
      )
    )
  end

  defp label(world, task, name) do
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

  defp stored!(task), do: Ash.get!(Task, task.id, authorize?: false)

  # Where the link of the nested table `id` goes, nil when it has none.
  defp full_view(html, id), do: List.first(attribute(html, "[id='#{id}-full-view']", "href"))

  defp parsed(href) do
    uri = URI.parse(href)
    {uri.path, Plug.Conn.Query.decode(uri.query || "")}
  end

  @board "task_board"
  @compact "comment_compact"

  setup %{conn: conn} do
    world = world(tasks: 0)
    task = task(world, "Write the report")
    other = task(world, "Plan the launch")
    comment(world, task, "Looks good")
    comment(world, task, "Almost there")
    comment(world, other, "Not yet")
    label(world, task, "urgent")

    %{world: world, task: task, other: other, conn: log_in(conn, world.admin)}
  end

  describe "a named table mounted as a page" do
    test "shows its own columns under its own id, and nothing of the default table", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, "/comments/compact")
      html = render_async(view)

      assert attribute(html, "##{@compact}-table", "role") == ["grid"]
      assert headers(html, @compact) == ["Body", "Author", "Inserted at"]

      assert Enum.sort(column(html, @compact, "body")) == [
               "Almost there",
               "Looks good",
               "Not yet"
             ]

      # the default table of the comments edits, deletes and creates; this
      # one declares none of it, and its rows never expand
      assert editors(html, @compact) == []
      assert attribute(html, "##{@compact}-actions-head", "id") == []
      assert attribute(html, "##{@compact}-create", "id") == []
      assert attribute(html, "##{@compact}-expander-head", "id") == []

      # the page of the default table is as it was
      {:ok, view, _html} = live(conn, "/comments")
      html = render_async(view)
      assert headers(html, "comment") == ["ID", "Body", "Inserted at", "Task ID", "Author ID"]
      assert attribute(html, "#comment-actions-head", "id") == ["comment-actions-head"]
      assert attribute(html, "#comment-create", "id") == ["comment-create"]
    end

    test "keeps its state in the URL under its own id", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/comments/compact")

      view |> element("##{@compact}-head-body") |> render_click()
      assert_patch(view, "/comments/compact?comment_compact[sort]=body")

      assert column(render_async(view), @compact, "body") ==
               ["Almost there", "Looks good", "Not yet"]

      # what is under the id of the default table is not this table's
      {:ok, view, _html} = live(conn, "/comments/compact?comment[sort]=-body")
      html = render_async(view)
      assert attribute(html, "##{@compact}-head-body", "aria-sort") == ["none"]
    end

    test "says what its own `on_forbidden` says to a person whose read is refused", %{
      world: world
    } do
      conn = log_in(build_conn(), world.nobody)
      {:ok, view, _html} = live(conn, "/comments/compact")

      assert text(render_async(view), "##{@compact}-error") ==
               "You are not allowed to see these records."
    end

    test "edits, runs its row action and has its argument line as any table", %{
      conn: conn,
      task: task,
      other: other
    } do
      {:ok, view, _html} = live(conn, "/tasks/board")
      html = render_async(view)

      assert headers(html, @board) == ["Title", "State", "Assignee", "Due on"]
      assert column(html, @board, "title") == ["Plan the launch", "Write the report"]

      # inline editing, through the board's own `update_action`
      save(view, @board, task.id, "title", "Write the long report")
      assert stored!(task).title == "Write the long report"

      # the board declares one row action, and not the default table's four
      assert actions(render(view), @board, task.id) == ["Archive"]
      act(view, @board, other.id, "archive")
      assert stored!(other).status == :archived

      # the read action's argument, kept under the board's id
      argue(view, @board, a: %{"search" => "long"})
      assert_patch(view, "/tasks/board?task_board[a][search]=long")
      assert column(render_async(view), @board, "title") == ["Write the long report"]

      # no create button: the board names no `create_action`
      assert attribute(render(view), "##{@board}-create", "id") == []
    end

    test "is in German where the person reads German", %{conn: conn, task: task} do
      {:ok, view, _html} = conn |> in_locale("de") |> live("/comments/compact")
      assert headers(render_async(view), @compact) == ["Text", "Verfasst von", "Angelegt am"]

      {:ok, view, _html} = conn |> in_locale("de") |> live("/tasks/board")
      html = render_async(view)
      assert headers(html, @board) == ["Titel", "Status", "Zugewiesen an", "Fällig am"]
      assert actions(html, @board, task.id) == ["Archivieren"]

      expand(view, @board, task.id)
      html = toggle(view, @board, task.id, "labels")
      assert headers(html, nested(@board, task.id, "labels")) == ["Name", "Farbe"]
    end

    test "a route that names a table the resource does not have says so when the page is opened",
         %{conn: conn} do
      assert_raise ArgumentError,
                   "`ash_data_table` mounts the table `:compakt` of Demo.Tracker.Comment at \"/support/wrong-table\", but Demo.Tracker.Comment has no table named `:compakt`. Its tables: `:compact`, and the default table.",
                   fn -> live(conn, "/support/wrong-table") end
    end
  end

  describe "a relationship that names a table of its destination" do
    test "nests that table: the compact comments under a task of the board", %{
      conn: conn,
      task: task
    } do
      {:ok, view, _html} = live(conn, "/tasks/board")
      render_async(view)
      html = expand(view, @board, task.id)

      assert lines(html, @board, task.id) == ["Comments", "Labels"]

      html = toggle(view, @board, task.id, "comments")
      id = nested(@board, task.id, "comments")

      assert headers(html, id) == ["Body", "Author", "Inserted at"]
      assert Enum.sort(column(html, id, "body")) == ["Almost there", "Looks good"]
      # the compact table changes nothing: no editor, no actions, and no
      # "New comment" on the line, which the default table has under a task
      assert editors(html, id) == []
      assert attribute(html, "[id='#{id}-actions-head']", "id") == []
      assert line_buttons(html, @board, task.id, "comments") == []
    end

    test "the default table of the tasks still nests the default table of the comments", %{
      conn: conn,
      task: task
    } do
      {:ok, view, _html} = live(conn, "/tasks")
      render_async(view)
      expand(view, task.id)
      html = toggle(view, task.id, "comments")
      id = nested(task.id, "comments")

      assert headers(html, id) == ["ID", "Body", "Inserted at", "Task ID", "Author ID"]
      assert line_buttons(html, task.id, "comments") == ["New comment"]

      assert parsed(full_view(html, id)) ==
               {"/comments", %{"comment" => %{"of" => %{"task" => %{"comments" => task.id}}}}}
    end
  end

  describe "the full view of a nested named table" do
    test "is the page of the same table, and names the table that offers the relationship", %{
      conn: conn,
      task: task
    } do
      {:ok, view, _html} = live(conn, "/tasks/board")
      render_async(view)
      expand(view, @board, task.id)
      html = toggle(view, @board, task.id, "comments")

      href = full_view(html, nested(@board, task.id, "comments"))

      assert parsed(href) ==
               {"/comments/compact",
                %{@compact => %{"of" => %{"task_board" => %{"comments" => task.id}}}}}

      # and that page shows the same table, limited to the same records
      {:ok, view, _html} = live(conn, href)
      html = render_async(view)

      assert headers(html, @compact) == ["Body", "Author", "Inserted at"]
      assert Enum.sort(column(html, @compact, "body")) == ["Almost there", "Looks good"]
      assert text(html, "##{@compact}-related") =~ "Write the report"
      # the parent in the heading leads back to the table that offered the
      # relationship: the board, not the default table of the tasks
      assert [href] = attribute(html, "##{@compact}-related-parent", "href")
      assert String.starts_with?(href, "/tasks/board")
    end

    test "a nested table whose table is mounted nowhere has no link, though another table of its resource is mounted",
         %{conn: conn, task: task} do
      {:ok, view, _html} = live(conn, "/tasks/board")
      render_async(view)
      expand(view, @board, task.id)
      html = toggle(view, @board, task.id, "labels")
      id = nested(@board, task.id, "labels")

      # the short table of the labels
      assert headers(html, id) == ["Name", "Colour"]
      assert column(html, id, "name") == ["urgent"]

      # `/labels` mounts the default table of the labels, which is another
      assert full_view(html, id) == nil
      assert attribute(html, "[id='#{id}-view']", "id") == []
    end

    test "a limit that names another table than the one that offers the relationship is no limit",
         %{conn: conn, task: task} do
      all = ["Almost there", "Looks good", "Not yet"]

      # the default table of the tasks nests the default comments, not these
      {:ok, view, _html} =
        live(conn, "/comments/compact?comment_compact[of][task][comments]=#{task.id}")

      html = render_async(view)
      assert Enum.sort(column(html, @compact, "body")) == all
      assert attribute(html, "##{@compact}-related", "id") == []

      # and the board nests the compact comments, not the default ones
      {:ok, view, _html} = live(conn, "/comments?comment[of][task_board][comments]=#{task.id}")
      html = render_async(view)
      assert Enum.sort(column(html, "comment", "body")) == all
      assert attribute(html, "#comment-related", "id") == []
    end
  end

  describe "the picker, opened from a named table" do
    test "shows the destination's default table, and the choice is saved through the named table's action",
         %{conn: conn, world: world, task: task} do
      {:ok, view, _html} = live(conn, "/tasks/board")
      render_async(view)

      html = pick(view, @board, task.id, "assignee")
      people = "#{@board}-pick-assignee"

      assert %{heading: "Assignee: choose user", table: ^people} = picker(html, @board)
      # the people's default table, the only one they have
      assert headers(render_async(view), people) == ["Name", "Email", "Role", "Assigned hours"]

      picked(view, @board, world.member.id)
      assert stored!(task).assignee_id == world.member.id
    end
  end

  describe "two tables of one resource on one page" do
    test "each has an id of its own without one being written", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/named")
      html = render_async(view)

      assert attribute(html, "#comment-table", "role") == ["grid"]
      assert attribute(html, "##{@compact}-table", "role") == ["grid"]

      assert headers(html, "comment") == ["ID", "Body", "Inserted at", "Task ID", "Author ID"]
      assert headers(html, @compact) == ["Body", "Author", "Inserted at"]

      # each is named on its line, as a heading of the page
      assert text(html, "h2#comment-name") == "Comments"
      assert text(html, "h2##{@compact}-name") == "Comments, compact"

      # no id of the page is there twice
      ids = attribute(html, "[id]", "id")
      assert ids -- Enum.uniq(ids) == []
    end

    test "each keeps its own state in the one URL", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/named")
      render_async(view)

      view |> element("##{@compact}-head-body") |> render_click()
      assert_patch(view, "/named?comment_compact[sort]=body")

      view |> element("#comment-head-body") |> render_click()
      path = assert_patch(view)

      assert parsed(path) ==
               {"/named", %{"comment" => %{"sort" => "body"}, @compact => %{"sort" => "body"}}}

      view |> element("#comment-head-body") |> render_click()
      path = assert_patch(view)

      assert parsed(path) ==
               {"/named", %{"comment" => %{"sort" => "-body"}, @compact => %{"sort" => "body"}}}

      html = render_async(view)
      assert column(html, "comment", "body") == ["Not yet", "Looks good", "Almost there"]
      assert column(html, @compact, "body") == ["Almost there", "Looks good", "Not yet"]

      # and a link with both is read by both
      {:ok, view, _html} =
        live(conn, "/named?comment[sort]=body&comment_compact[sort]=-body")

      html = render_async(view)
      assert column(html, "comment", "body") == ["Almost there", "Looks good", "Not yet"]
      assert column(html, @compact, "body") == ["Not yet", "Looks good", "Almost there"]
    end

    test "each is the table it is: the default one edits, the named one does not", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, "/named")
      html = render_async(view)

      # only the default table has editors
      assert editors(html, "comment") != []
      assert editors(html, @compact) == []
    end
  end
end
