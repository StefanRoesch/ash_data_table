defmodule DemoWeb.SameTableLinkTest do
  # /tasks and /react/tasks link to each other above the table
  # (`DemoWeb.Layouts.tasks/1`, `DemoWeb.ReactTasksLive`); the link back from
  # React keeps the URL's query, so the sort and filters carry over.
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

  test "in German", %{conn: conn, world: world} do
    conn = conn |> log_in(world.member) |> in_locale("de")

    {:ok, _view, html} = live(conn, "/tasks")
    assert text(html, "#same-table a") == "Dieselbe Tabelle in React"

    {:ok, _view, html} = live(conn, "/react/tasks")
    assert text(html, "#same-table a") == "Dieselbe Tabelle in HEEx"
  end
end
