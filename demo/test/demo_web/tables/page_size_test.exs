defmodule DemoWeb.Tables.PageSizeTest do
  @moduledoc """
  "Rows per page": the menu of a table that declares `page_sizes`.

  The tasks offer 10, 25 and 50 and open with 25, the `default_limit` of
  their read action, by offset. The comments offer 10, 20 and 50 and open
  with 20, by keyset. The projects offer none.
  """
  use DemoWeb.ModeCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator

  defp title(n), do: "Task " <> String.pad_leading("#{n}", 2, "0")
  defp titles(range), do: Enum.map(range, &title/1)

  defp body(n), do: "Comment " <> String.pad_leading("#{n}", 2, "0")
  defp bodies(range), do: Enum.map(range, &body/1)

  # 60 tasks of the world's first project, the last one the newest.
  defp sixty_tasks(world) do
    [project | _] = world.projects

    for n <- 1..60 do
      Generator.generate(
        Generator.task(
          organization_id: world.organization.id,
          project_id: project.id,
          reporter_id: world.admin.id,
          title: title(n),
          inserted_at: DateTime.add(~U[2026-01-01 12:00:00.000000Z], n, :day)
        )
      )
    end
  end

  # 45 comments on a task, the last one the newest.
  defp comments_on(world, task) do
    for n <- 1..45 do
      Generator.generate(
        Generator.comment(
          organization_id: world.organization.id,
          task_id: task.id,
          author_id: world.member.id,
          body: body(n),
          inserted_at: DateTime.add(~U[2026-02-01 08:00:00.000000Z], n, :hour)
        )
      )
    end
  end

  describe "the tasks, by offset" do
    setup %{conn: conn} do
      world = world(tasks: 0)
      sixty_tasks(world)
      %{world: world, conn: log_in(conn, world.admin)}
    end

    test "the menu offers the declared sizes under its label, with the action's own chosen",
         %{conn: conn} do
      {:ok, _view, html} = live(conn, "/tasks")

      assert page_sizes(html, "task") == %{
               label: "Rows per page",
               sizes: ["10", "25", "50"],
               chosen: ["25"]
             }

      # after the buttons, inside the pagination
      assert attribute(html, "#task-pagination > *", "id") |> List.last() ==
               "task-page-size-form"

      assert column(html, "task", "title") == titles(60..36//-1)
    end

    test "choosing a size reads the first page with it, and puts it into the URL", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/tasks")

      html = page_size(view, "task", 50)
      assert_patch(view, "/tasks?task[per]=50")

      assert column(html, "task", "title") == titles(60..11//-1)
      assert text(html, "#task-range") == "1–50 of 60"
      assert page_sizes(html, "task").chosen == ["50"]

      assert attribute(html, "#task-pagination button", "id") ==
               ~w(task-previous task-page-1 task-page-2 task-next)

      html = page_size(view, "task", 10)
      assert_patch(view, "/tasks?task[per]=10")

      assert column(html, "task", "title") == titles(60..51//-1)
      assert text(html, "#task-range") == "1–10 of 60"
      # the rows of all pages are numbered as before: 60, the two header rows
      # and the footer row of the tasks' summaries
      assert attribute(html, "#task-table", "aria-rowcount") == ["63"]
    end

    test "the pages are those of the chosen size", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/tasks?task[per]=10")

      view |> element("#task-next") |> render_click()
      assert_patch(view, "/tasks?task[page]=2&task[per]=10")
      html = render_async(view)

      assert column(html, "task", "title") == titles(50..41//-1)
      assert text(html, "#task-range") == "11–20 of 60"

      view |> element("#task-page-6") |> render_click()
      assert_patch(view, "/tasks?task[page]=6&task[per]=10")
      html = render_async(view)

      assert column(html, "task", "title") == titles(10..1//-1)
      assert text(html, "#task-range") == "51–60 of 60"
      assert attribute(html, "#task-next", "disabled") == [""]
    end

    test "a new size goes back to the first page", %{conn: conn} do
      {:ok, view, html} = live(conn, "/tasks?task[page]=3")
      assert text(html, "#task-range") == "51–60 of 60"

      html = page_size(view, "task", 10)

      assert_patch(view, "/tasks?task[per]=10")
      assert text(html, "#task-range") == "1–10 of 60"
      assert attribute(html, "#task-pagination [aria-current=page]", "id") == ["task-page-1"]
    end

    test "the size the table opens with is left out of the URL", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/tasks?task[per]=10")

      html = page_size(view, "task", 25)

      assert_patch(view, "/tasks")
      assert column(html, "task", "title") == titles(60..36//-1)
      assert page_sizes(html, "task").chosen == ["25"]
    end

    test "the sort, the filters and the arguments stay", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/tasks")

      view |> element("#task-head-title") |> render_click()
      render_async(view)
      filter(view, "task", "title", v: "Task 0")
      argue(view, "task", a: %{"search" => "task"})
      assert_patch(view, "/tasks?task[a][search]=task&task[f][title]=Task+0&task[sort]=title")

      html = page_size(view, "task", 10)

      assert_patch(
        view,
        "/tasks?task[a][search]=task&task[f][title]=Task+0&task[per]=10&task[sort]=title"
      )

      # nine tasks match: the page is not full, and there is one page
      assert column(html, "task", "title") == titles(1..9)
      assert text(html, "#task-range") == "1–9 of 9"

      # and a change of sort or filter keeps the size
      view |> element("#task-head-title") |> render_click()

      assert_patch(
        view,
        "/tasks?task[a][search]=task&task[f][title]=Task+0&task[per]=10&task[sort]=-title"
      )

      render_async(view)

      html = filter(view, "task", "title", v: "Task")

      assert_patch(
        view,
        "/tasks?task[a][search]=task&task[f][title]=Task&task[per]=10&task[sort]=-title"
      )

      assert column(html, "task", "title") == titles(60..51//-1)
    end

    test "is not read out as a change of filters is: it is a change of page", %{conn: conn} do
      {:ok, view, html} = live(conn, "/tasks")
      before = announcement(html)

      assert announcement(page_size(view, "task", 10)) == before
    end

    test "opened afresh, a URL with a size shows that size and that page", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/tasks?task[per]=10&task[page]=2&task[sort]=title")

      assert column(html, "task", "title") == titles(11..20)
      assert text(html, "#task-range") == "11–20 of 60"
      assert page_sizes(html, "task").chosen == ["10"]
      assert attribute(html, "#task-head-title", "aria-sort") == ["ascending"]
    end

    test "a URL from before there were sizes shows what it always did", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/tasks?task[page]=2&task[sort]=title")

      assert column(html, "task", "title") == titles(26..50)
      assert text(html, "#task-range") == "26–50 of 60"
      assert page_sizes(html, "task").chosen == ["25"]
    end

    # The size in a URL is a claim. 100 is what the read action itself would
    # allow (`max_page_size: 100`), and the table does not offer it.
    test "a size in the URL that the table does not offer is ignored: the table opens as declared",
         %{conn: conn} do
      for claim <- ~w(100 60 1000 26 0 -10 all 10.5) ++ ["", "50x"] do
        {:ok, _view, html} = live(conn, "/tasks?task[per]=" <> claim)

        assert length(column(html, "task", "title")) == 25, claim
        assert column(html, "task", "title") == titles(60..36//-1), claim
        assert text(html, "#task-range") == "1–25 of 60", claim
        assert page_sizes(html, "task").chosen == ["25"], claim
      end

      # in whatever shape
      for query <- ["task[per][]=50", "task[per][a]=50"] do
        {:ok, _view, html} = live(conn, "/tasks?" <> query)
        assert length(column(html, "task", "title")) == 25, query
      end

      # and it is not carried on: the next URL the table writes is without it
      {:ok, view, _html} = live(conn, "/tasks?task[per]=100")
      view |> element("#task-next") |> render_click()
      assert_patch(view, "/tasks?task[page]=2")
      assert text(render_async(view), "#task-range") == "26–50 of 60"
    end

    test "a size in an event that the table does not offer is ignored: nothing is read",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, "/tasks?task[page]=2")

      for claim <- ~w(100 60 1000 0 -10 all) ++ [""] do
        html = page_size(view, "task", claim)

        assert length(column(html, "task", "title")) == 25, claim
        assert text(html, "#task-range") == "26–50 of 60", claim
        assert page_sizes(html, "task").chosen == ["25"], claim
      end

      # an event of another shape
      html =
        view
        |> element("#task-page-size-form")
        |> render_change(%{"size" => %{"0" => "50"}})

      assert text(html, "#task-range") == "26–50 of 60"

      # the table has not moved: no URL was written
      refute_patched(view, "/tasks?task[page]=2&task[per]=100")
      view |> element("#task-previous") |> render_click()
      assert_patch(view, "/tasks")
    end

    test "all that match are all there are, whatever the size", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/tasks")

      page_size(view, "task", 10)

      assert %{offered?: true, buttons: ["Select all 60 that match" | _]} =
               selection(select_page(view))

      assert selection(select(view, "task", :all)).selected == "All 60 that match are selected"
    end

    test "in German the menu is labelled in German", %{conn: conn, world: world} do
      {:ok, _view, html} =
        conn |> log_in(world.admin) |> in_locale("de") |> live("/tasks")

      assert page_sizes(html, "task").label == "Zeilen pro Seite"
    end
  end

  describe "a table placed in a page, which keeps its state itself" do
    setup %{conn: conn} do
      world = world(tasks: 0)
      sixty_tasks(world)
      %{world: world, conn: log_in(conn, world.admin)}
    end

    test "choosing a size reads the first page with it, and nothing is in the URL", %{conn: conn} do
      {:ok, view, html} = live(conn, "/dashboard")

      assert page_sizes(html, "dashboard-tasks").chosen == ["25"]
      # the projects declare none
      assert page_sizes(html, "dashboard-projects") == nil

      view |> element("#dashboard-tasks-next") |> render_click()
      render_async(view)
      html = page_size(view, "dashboard-tasks", 50)

      assert text(html, "#dashboard-tasks-range") == "1–50 of 60"
      assert column(html, "dashboard-tasks", "title") == titles(60..11//-1)
      assert page_sizes(html, "dashboard-tasks").chosen == ["50"]

      # a size that is not offered
      html = page_size(view, "dashboard-tasks", 100)
      assert text(html, "#dashboard-tasks-range") == "1–50 of 60"
    end
  end

  describe "the comments, by keyset" do
    setup %{conn: conn} do
      world = world(tasks: 1)
      [task] = world.tasks
      comments_on(world, task)
      %{world: world, task: task, conn: log_in(conn, world.member)}
    end

    test "choosing a size reads from the start with it", %{conn: conn} do
      {:ok, view, html} = live(conn, "/comments")

      assert page_sizes(html, "comment") == %{
               label: "Rows per page",
               sizes: ["10", "20", "50"],
               chosen: ["20"]
             }

      html = page_size(view, "comment", 10)
      assert_patch(view, "/comments?comment[per]=10")

      assert column(html, "comment", "body") == bodies(45..36//-1)
      assert text(html, "#comment-range") == "45 records"

      # the next page is of ten, and keeps the size beside its cursor
      view |> element("#comment-next") |> render_click()
      url = assert_patch(view)
      html = render_async(view)

      assert url =~ "comment[after]="
      assert url =~ "comment[per]=10"
      assert column(html, "comment", "body") == bodies(35..26//-1)

      # opened afresh, that URL shows that page
      {:ok, _view, opened} = live(conn, url)
      assert column(opened, "comment", "body") == bodies(35..26//-1)
      assert page_sizes(opened, "comment").chosen == ["10"]

      # a new size gives the cursor up: a cursor belongs to the size it was made with
      html = page_size(view, "comment", 50)
      assert_patch(view, "/comments?comment[per]=50")

      assert column(html, "comment", "body") == bodies(45..1//-1)
      assert attribute(html, "#comment-previous", "disabled") == [""]
      assert attribute(html, "#comment-next", "disabled") == [""]
    end

    test "a size that the table does not offer is ignored, from the URL and from an event",
         %{conn: conn} do
      {:ok, view, html} = live(conn, "/comments?comment[per]=100")

      assert column(html, "comment", "body") == bodies(45..26//-1)
      assert page_sizes(html, "comment").chosen == ["20"]

      html = page_size(view, "comment", 100)

      assert column(html, "comment", "body") == bodies(45..26//-1)
      assert page_sizes(html, "comment").chosen == ["20"]
    end

    test "nested under a task, the comments have the menu, and keep the choice themselves",
         %{conn: conn, world: world, task: task} do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")

      expand(view, task.id)
      html = toggle(view, task.id, "comments")
      id = nested(task.id, "comments")

      assert page_sizes(html, id) == %{
               label: "Rows per page",
               sizes: ["10", "20", "50"],
               chosen: ["20"]
             }

      # reached through the cell of the row it is in, as the buttons are
      assert attribute(html, "[id='#{id}-page-size']", "tabindex") == ["-1"]
      assert column(html, id, "body") == bodies(45..26//-1)

      html = page_size(view, id, 10)

      assert column(html, id, "body") == bodies(45..36//-1)
      assert page_sizes(html, id).chosen == ["10"]

      click(view, "[id='#{id}-next']")
      html = render_async(view)
      assert column(html, id, "body") == bodies(35..26//-1)

      html = page_size(view, id, 50)
      assert column(html, id, "body") == bodies(45..1//-1)

      # a size that is not offered changes nothing
      html = page_size(view, id, 100)
      assert column(html, id, "body") == bodies(45..1//-1)
      assert page_sizes(html, id).chosen == ["50"]

      # nothing of it is in the URL, and the table around it has not moved
      refute_patched(view, "/tasks?task[per]=50")
      assert page_sizes(html, "task").chosen == ["25"]
    end
  end

  describe "the tasks nested under a project, by offset" do
    test "have the menu of the tasks' table, and the range follows the size", %{conn: conn} do
      world = world(tasks: 0)
      sixty_tasks(world)
      [project | _] = world.projects

      {:ok, view, html} = conn |> log_in(world.admin) |> live("/projects")

      # the projects declare no sizes
      assert page_sizes(html, "project") == nil

      expand(view, "project", project.id)
      html = toggle(view, "project", project.id, "tasks")
      id = nested("project", project.id, "tasks")

      assert page_sizes(html, id).chosen == ["25"]
      assert text(html, "[id='#{id}-range']") == "1–25 of 60"

      html = page_size(view, id, 10)

      assert column(html, id, "title") == titles(60..51//-1)
      assert text(html, "[id='#{id}-range']") == "1–10 of 60"

      html = page_size(view, id, 1000)
      assert text(html, "[id='#{id}-range']") == "1–10 of 60"
    end
  end
end
