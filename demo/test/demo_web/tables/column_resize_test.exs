defmodule DemoWeb.Tables.ColumnResizeTest do
  @moduledoc """
  What the server renders for a person to change a column's width with: a
  handle at the end of every column's header, for the pointer, and a width
  field per column in the list of "Columns" with "Reset widths", for the
  keyboard. The widths themselves are the browser's alone
  (`demo/e2e/resizing.spec.ts`): the server renders the handle and the
  fields and never hears of a width.
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

    for name <- ~w(role aria-hidden aria-label tabindex data-resize),
        value <- attribute(html, selector, name),
        into: %{},
        do: {name, value}
  end

  defp width_field(html, id, field) do
    selector = "[id='#{id}-columns'] [id='#{id}-column-#{field}-width']"

    for name <- ~w(type min max aria-label data-width value tabindex),
        value <- attribute(html, selector, name),
        into: %{},
        do: {name, value}
  end

  test "every column's header ends in a handle, for the pointer alone", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/tasks")

    # no role, no name, no Tab stop: the keyboard has the width fields
    assert handle(html, "task", "title") == %{"aria-hidden" => "true", "data-resize" => ""}

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

    assert handle(html, "task", "tags") == handle(html, "task", "title")
  end

  test "it is still there after the header was rendered again", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/tasks")

    view |> element("#task-sort-title") |> render_click()
    html = render_async(view, 10_000)

    assert attribute(html, "#task-head-title", "aria-sort") == ["ascending"]
    assert handle(html, "task", "title")["data-resize"] == ""
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

    assert handle(html, id, "body")["data-resize"] == ""
    assert width_field(html, id, "body")["data-width"] == "#{id}-head-body"
  end

  test "the list of Columns has a width field beside each box, named with the column, from 48 to 1000 pixels",
       %{conn: conn} do
    {:ok, _view, html} = live(conn, "/tasks")

    # no value: the width is the browser's to say, and the hook fills it in
    assert width_field(html, "task", "status") == %{
             "type" => "number",
             "min" => "48",
             "max" => "1000",
             "aria-label" => "Width of State",
             "data-width" => "task-head-status"
           }

    # the label column first, which has no box: it cannot be hidden
    boxes = attribute(html, "#task-columns input[type=checkbox]", "data-head")
    refute "task-head-title" in boxes

    assert attribute(html, "#task-columns input[type=number]", "data-width") ==
             ["task-head-title" | boxes]

    assert width_field(html, "task", "title")["aria-label"] == "Width of Title"
    assert text(html, "#task-column-title-entry") == "Title"

    assert attribute(html, "#task-columns > button[data-reset-widths]", "id") == [
             "task-reset-widths"
           ]

    assert text(html, "#task-reset-widths") == "Reset widths"
  end

  test "in German", %{conn: conn} do
    {:ok, _view, html} = conn |> in_locale("de") |> live("/tasks")

    assert width_field(html, "task", "status")["aria-label"] == "Breite von Status"
    assert text(html, "#task-reset-widths") == "Breiten zurücksetzen"
  end
end
