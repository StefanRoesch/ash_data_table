defmodule DemoWeb.Tables.FullViewLinkTest do
  @moduledoc """
  The link on a nested table that opens its records in the full view: the
  destination resource's own page, limited to the records related to the
  same row.

  The link is there only when the destination's table is mounted with an
  `ash_data_table` line of the router. In the demo that is so for comments,
  labels, projects, tasks and the labels of tasks, and not for people.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator

  @moment ~U[2026-01-01 12:00:00.000000Z]

  defp task(world, title, overrides) do
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

  # Where the link of the nested table `id` goes, nil when it has none.
  defp full_view(html, id), do: List.first(attribute(html, "[id='#{id}-full-view']", "href"))

  # The path and the query of a link, the query as the parameters it stands for.
  defp parsed(href) do
    uri = URI.parse(href)
    {uri.path, Plug.Conn.Query.decode(uri.query || "")}
  end

  setup %{conn: conn} do
    world = world(tasks: 0)
    task = task(world, "Write the report", assignee_id: world.member.id)
    comment(world, task, "Looks good")
    label = label(world, task, "urgent")

    %{world: world, task: task, label: label, conn: log_in(conn, world.admin)}
  end

  describe "the link on a nested table" do
    test "goes to the destination's mounted page, naming the row and the relationship in the table's own parameters",
         %{conn: conn, task: task} do
      {:ok, view, _html} = live(conn, "/tasks")
      expand(view, task.id)

      html = toggle(view, task.id, "comments")
      id = nested(task.id, "comments")

      assert parsed(full_view(html, id)) ==
               {"/comments", %{"comment" => %{"of" => %{"task" => %{"comments" => task.id}}}}}

      assert text(html, "[id='#{id}-full-view']") == "Open in full view"

      assert attribute(html, "[id='#{id}-full-view']", "aria-label") ==
               ["Open in full view: Comments"]
    end

    test "is there for every kind of relationship whose destination is mounted, and for no other",
         %{conn: conn, task: task} do
      {:ok, view, _html} = live(conn, "/tasks")
      expand(view, task.id)

      for {relationship, expected} <- [
            # has-many
            {"comments", {"/comments", "comment"}},
            # has-one
            {"first_comment", {"/comments", "comment"}},
            {"latest_comment", {"/comments", "comment"}},
            # many-to-many
            {"labels", {"/labels", "label"}},
            # belongs-to
            {"project", {"/projects", "project"}},
            # people have no page of their own
            {"assignee", nil},
            {"reporter", nil}
          ] do
        html = toggle(view, task.id, relationship)
        id = nested(task.id, relationship)

        # the table is there and has been read
        assert attribute(html, "[id='#{id}-table']", "role") == ["grid"]

        case expected do
          {path, table} ->
            assert parsed(full_view(html, id)) ==
                     {path, %{table => %{"of" => %{"task" => %{relationship => task.id}}}}}

          nil ->
            assert full_view(html, id) == nil
            assert attribute(html, "[id='#{id}-view']", "id") == []
        end
      end
    end

    test "is the only cell of the last row of the nested grid, and no tab stop of its own",
         %{conn: conn, task: task} do
      {:ok, view, _html} = live(conn, "/tasks")
      expand(view, task.id)

      html = toggle(view, task.id, "comments")
      id = nested(task.id, "comments")

      assert attribute(html, "[id='#{id}-foot'] > [role=row]:last-child", "id") ==
               ["#{id}-view-row"]

      assert attribute(html, "[id='#{id}-view-row'] > [role=gridcell]", "id") == ["#{id}-view"]
      assert attribute(html, "[id='#{id}-view']", "role") == ["gridcell"]
      assert attribute(html, "[id='#{id}-view']", "tabindex") == ["-1"]
      # as wide as the grid: the comments' boxes and expanders, their five
      # columns and their actions
      assert attribute(html, "[id='#{id}-view']", "colspan") == ["8"]
      assert attribute(html, "[id='#{id}-full-view']", "tabindex") == ["-1"]
      # that it is a live navigation, which does not load the page afresh,
      # the browser shows (`full_view.spec.ts`)
    end

    test "names a row whose key has several attributes by each of them", %{
      conn: conn,
      task: task,
      label: label
    } do
      {:ok, view, _html} = live(conn, "/task_labels")
      key = "#{task.id}-#{label.id}"
      expand(view, "task_label", key)

      html = toggle(view, "task_label", key, "task")

      assert parsed(full_view(html, nested("task_label", key, "task"))) ==
               {"/tasks",
                %{
                  "task" => %{
                    "of" => %{
                      "task_label" => %{
                        "task" => %{"task_id" => task.id, "label_id" => label.id}
                      }
                    }
                  }
                }}
    end

    test "is on a table nested deeper, and names the row that table is under", %{
      conn: conn,
      world: world,
      task: task
    } do
      [project | _] = world.projects
      {:ok, view, _html} = live(conn, "/projects")
      expand(view, "project", project.id)
      toggle(view, "project", project.id, "tasks")
      tasks = nested("project", project.id, "tasks")
      expand(view, tasks, task.id)

      html = toggle(view, tasks, task.id, "comments")

      assert parsed(full_view(html, tasks)) ==
               {"/tasks", %{"task" => %{"of" => %{"project" => %{"tasks" => project.id}}}}}

      assert parsed(full_view(html, nested(tasks, task.id, "comments"))) ==
               {"/comments", %{"comment" => %{"of" => %{"task" => %{"comments" => task.id}}}}}
    end

    test "goes to the first of several pages the router mounts the destination at", %{
      conn: conn,
      task: task
    } do
      # the labels are mounted at /labels and, after it, at /bare/labels
      {:ok, view, _html} = live(conn, "/tasks")
      expand(view, task.id)

      html = toggle(view, task.id, "labels")

      assert {"/labels", _params} = parsed(full_view(html, nested(task.id, "labels")))
    end

    test "is on a nested table of a table that a page of the host's holds", %{
      conn: conn,
      task: task
    } do
      {:ok, view, _html} = live(conn, "/dashboard")
      expand(view, "dashboard-tasks", task.id)

      html = toggle(view, "dashboard-tasks", task.id, "comments")

      assert parsed(full_view(html, nested("dashboard-tasks", task.id, "comments"))) ==
               {"/comments", %{"comment" => %{"of" => %{"task" => %{"comments" => task.id}}}}}
    end

    test "is not on a table of its own, limited or not", %{conn: conn, task: task} do
      for path <- ["/comments", "/comments?comment[of][task][comments]=#{task.id}"] do
        {:ok, _view, html} = live(conn, path)

        assert column(html, "comment", "body") == ["Looks good"]
        assert full_view(html, "comment") == nil
        assert attribute(html, "#comment-foot", "id") == []
      end
    end

    test "is not there while the nested table has nothing to show for its row", %{
      conn: conn,
      task: task
    } do
      {:ok, view, _html} = live(conn, "/tasks")
      expand(view, task.id)
      Ash.destroy!(task, authorize?: false)

      html = toggle(view, task.id, "comments")
      id = nested(task.id, "comments")

      assert text(html, "[id='#{id}-error']") == "This record is no longer available."
      assert full_view(html, id) == nil
    end
  end
end
