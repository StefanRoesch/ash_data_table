defmodule DemoWeb.Tables.LayoutTest do
  @moduledoc """
  The layout around a mounted table: the app layout named in the config
  (`config :ash_data_table, layout: {DemoWeb.Layouts, :app}`), unless the router
  line says otherwise.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  setup %{conn: conn} do
    world = world(tasks: 2)
    %{conn: log_in(conn, world.admin)}
  end

  test "a mounted table is rendered inside the app layout", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/tasks")

    # the app layout's own container and its flash group
    assert attribute(html, "#app-layout #task-table", "id") == ["task-table"]
    assert attribute(html, "#flash-group", "id") == ["flash-group"]
  end

  test "a table mounted with `layout: false` is rendered bare", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/bare/labels")

    assert headers(html, "label") == ["ID", "Name", "Colour"]
    assert attribute(html, "#flash-group", "id") == []
    assert attribute(html, "#app-layout", "id") == []
  end

  # A bare table brings no landmark of its own, so the page's are the root
  # layout's: its header, and the main landmark every page is rendered in.
  test "the root layout gives every page its main landmark, a bare table's too", %{conn: conn} do
    for path <- ["/tasks", "/bare/labels"] do
      html = conn |> get(path) |> html_response(200)

      assert attribute(html, "main", "id") == ["main"], path
      assert attribute(html, "main h1", "class") != [], path
      assert attribute(html, "main [role=table]", "role") == ["table"], path
    end
  end
end
