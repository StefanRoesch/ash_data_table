defmodule DemoWeb.Tables.ColumnResizeTest do
  @moduledoc """
  What the server renders for a person to change a column's width with: a
  handle at the end of every column's header. The widths themselves are the
  browser's alone (`demo/e2e/resizing.spec.ts`): the server renders the
  handle and never hears of a width.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  setup %{conn: conn} do
    world = world(tasks: 3)
    %{world: world, conn: log_in(conn, world.admin)}
  end

  defp handle(html, id, field) do
    selector = "[id='#{id}-head-#{field}'] > [id='#{id}-resize-#{field}']"

    for name <-
          ~w(role aria-orientation aria-label aria-valuemin aria-valuemax aria-valuenow tabindex data-resize),
        value <- attribute(html, selector, name),
        into: %{},
        do: {name, value}
  end

  test "every column's header ends in a handle, named with the column, that says how narrow and how wide the column can be",
       %{conn: conn} do
    {:ok, _view, html} = live(conn, "/tasks")

    assert handle(html, "task", "title") == %{
             "role" => "separator",
             "aria-orientation" => "vertical",
             "aria-label" => "Resize Title",
             "aria-valuemin" => "48",
             "aria-valuemax" => "1000",
             # no `aria-valuenow`: the width is the browser's to say
             "tabindex" => "-1",
             "data-resize" => ""
           }

    fields =
      html
      |> attribute("#task-head [role=columnheader][id^='task-head-']", "id")
      |> Enum.map(&String.replace_prefix(&1, "task-head-", ""))

    assert length(fields) > 5

    assert attribute(html, "#task-head [role=columnheader] > [data-resize]", "id") ==
             Enum.map(fields, &"task-resize-#{&1}")
  end

  test "the columns before and after the table's columns have none", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/tasks")

    for id <- ~w(task-select-head task-expander-head task-actions-head) do
      assert attribute(html, "##{id}", "id") == [id]
      assert attribute(html, "##{id} [data-resize]", "id") == []
    end

    assert attribute(html, "#task-filter-row [data-resize]", "id") == []
    assert attribute(html, "#task-table > [role=rowgroup]", "role") != []
    assert attribute(html, "#task-table > [role=rowgroup] [data-resize]", "id") == []
  end

  test "a header is called by its column alone, not by its handle as well", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/tasks")

    assert attribute(html, "#task-head-title", "aria-label") == ["Title"]
    assert attribute(html, "[id='task-head-billable?']", "aria-label") == ["Billable?"]
    assert headers(html, "task") |> hd() == "Title"
  end

  test "the handle is the same on a header that sorts and on one that does not", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/tasks")

    assert attribute(html, "#task-head-title", "data-sort") == [""]
    assert attribute(html, "#task-head-tags", "data-sort") == []

    assert handle(html, "task", "tags") == %{
             handle(html, "task", "title")
             | "aria-label" => "Resize Tags"
           }
  end

  test "it is still there after the header was rendered again", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/tasks")

    view |> element("#task-head-title") |> render_click()
    html = render_async(view, 10_000)

    assert attribute(html, "#task-head-title", "aria-sort") == ["ascending"]
    assert handle(html, "task", "title")["aria-label"] == "Resize Title"
  end

  test "a nested table's columns have their handles, under ids of their own", %{
    conn: conn,
    world: world
  } do
    {:ok, view, _html} = live(conn, "/tasks")
    [task | _] = world.tasks

    expand(view, task.id)
    html = toggle(view, task.id, "comments")
    id = nested("task", task.id, "comments")

    assert handle(html, id, "body")["aria-label"] == "Resize Body"
    assert handle(html, "task", "title")["aria-label"] == "Resize Title"
  end

  test "in German", %{conn: conn} do
    {:ok, _view, html} = conn |> in_locale("de") |> live("/tasks")

    assert handle(html, "task", "title")["aria-label"] == "Breite von Titel ändern"
  end
end
