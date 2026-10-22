defmodule DemoWeb.SameTableLinkTest do
  # /tasks and /react/tasks link to each other above the table
  # (`DemoWeb.Layouts.tasks/1`, `DemoWeb.ReactTasksLive`); each link keeps
  # the URL's query, so the sort and filters carry over both ways.
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage, only: [text: 2]

  setup do
    %{world: world(tasks: 3)}
  end

  test "/tasks links to /react/tasks, which links back", %{conn: conn, world: world} do
    conn = log_in(conn, world.member)
    {:ok, view, _html} = live(conn, "/tasks")

    assert has_element?(view, "#same-table a[href='/react/tasks']", "The same table in React")

    {:ok, react, _html} =
      view |> element("#same-table a") |> render_click() |> follow_redirect(conn, "/react/tasks")

    assert has_element?(react, "#same-table a[href='/tasks']", "The same table in HEEx")

    {:ok, _view, _html} =
      react |> element("#same-table a") |> render_click() |> follow_redirect(conn, "/tasks")
  end

  test "the link back keeps the sort and filters", %{conn: conn, world: world} do
    {:ok, view, _html} =
      conn |> log_in(world.member) |> live("/react/tasks?task[sort]=-title&task[f][title]=Task")

    assert {:error, {:live_redirect, %{to: to}}} =
             view |> element("#same-table a") |> render_click()

    assert %URI{path: "/tasks", query: query} = URI.parse(to)
    assert %{"task[sort]" => "-title", "task[f][title]" => "Task"} = URI.decode_query(query)
  end

  test "the link back keeps the sort and filters after a patch", %{conn: conn, world: world} do
    {:ok, react, _html} =
      conn |> log_in(world.member) |> live("/react/tasks?task[sort]=-title&task[f][title]=Task")

    render_patch(react, "/react/tasks?task[sort]=title")
    assert linked(react, "/tasks") == %{"task[sort]" => "title"}
  end

  test "the link to React keeps the sort and filters, also after a patch", %{
    conn: conn,
    world: world
  } do
    {:ok, view, _html} =
      conn |> log_in(world.member) |> live("/tasks?task[sort]=-title&task[f][title]=Task")

    assert %{"task[sort]" => "-title", "task[f][title]" => "Task"} = linked(view, "/react/tasks")

    render_patch(view, "/tasks?task[sort]=title")
    assert linked(view, "/react/tasks") == %{"task[sort]" => "title"}

    assert {:error, {:live_redirect, %{to: to}}} =
             view |> element("#same-table a") |> render_click()

    assert %URI{path: "/react/tasks", query: query} = URI.parse(to)
    assert URI.decode_query(query) == %{"task[sort]" => "title"}
  end

  test "without a query, neither link has one", %{conn: conn, world: world} do
    conn = log_in(conn, world.member)

    {:ok, view, _html} = live(conn, "/tasks")
    assert has_element?(view, "#same-table a[href='/react/tasks']")

    {:ok, react, _html} = live(conn, "/react/tasks")
    assert has_element?(react, "#same-table a[href='/tasks']")
  end

  # the query of the link above the table, which leads to `path`
  defp linked(view, path) do
    [href] =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#same-table a")
      |> LazyHTML.attribute("href")

    assert %URI{path: ^path, query: query} = URI.parse(href)
    URI.decode_query(query || "")
  end

  test "in German", %{conn: conn, world: world} do
    conn = conn |> log_in(world.member) |> in_locale("de")

    {:ok, _view, html} = live(conn, "/tasks")
    assert text(html, "#same-table a") == "Dieselbe Tabelle in React"

    {:ok, _view, html} = live(conn, "/react/tasks")
    assert text(html, "#same-table a") == "Dieselbe Tabelle in HEEx"
  end
end
