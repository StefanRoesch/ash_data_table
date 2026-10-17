defmodule DemoWeb.Tables.SidewaysScrollTest do
  @moduledoc """
  What the server renders for a table to scroll sideways in an area of its
  own: the grid, its scrollbar for the bottom edge of the window, the element
  that keeps a nested table in view, and, in a table that says
  `sticky_label? true`, which header is the label's. Where a table is
  scrolled to, and what stays in view meanwhile, is the browser's alone
  (`demo/e2e/scrolling.spec.ts`).
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  setup %{conn: conn} do
    world = world(tasks: 3)
    %{world: world, conn: log_in(conn, world.admin)}
  end

  test "the grid is the table's scroll area, and no tab stop; its second scrollbar is for the pointer alone",
       %{conn: conn} do
    {:ok, _view, html} = live(conn, "/tasks")

    assert attribute(html, "#task-grid", "tabindex") == ["-1"]
    assert [class] = attribute(html, "#task-grid", "class")
    assert "overflow-x-auto" in String.split(class)
    # the table on a page hands a scroll on to the page; a nested one does not
    refute "overscroll-x-contain" in String.split(class)

    assert attribute(html, "#task-scrollbar[data-scrollbar]", "aria-hidden") == ["true"]
    assert attribute(html, "#task-scrollbar", "tabindex") == ["-1"]
    assert attribute(html, "#task-scrollbar", "hidden") == [""]
    # the hook's, which patches leave alone
    assert attribute(html, "#task-scrollbar", "phx-update") == ["ignore"]
  end

  test "a table that says `sticky_label? true` marks the header of its label column, and no other",
       %{conn: conn} do
    {:ok, _view, html} = live(conn, "/tasks")

    assert attribute(html, "#task-head-row > [role=columnheader][data-label]", "id") == [
             "task-head-title"
           ]
  end

  test "a table that does not say it marks none", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/labels")
    assert attribute(html, "#label-table [role=columnheader]", "role") != []
    assert attribute(html, "#label-table [role=columnheader][data-label]", "id") == []

    {:ok, _view, html} = live(conn, "/comments")
    assert attribute(html, "#comment-table [role=columnheader]", "role") != []
    assert attribute(html, "#comment-table [role=columnheader][data-label]", "id") == []
  end

  test "a nested table is in an element that stays at the left edge, has a scroll area of its own, and says for itself whether its label column stays",
       %{conn: conn, world: world} do
    [task | _] = world.tasks
    {:ok, view, _html} = live(conn, "/tasks")
    expand(view, task.id)
    html = toggle(view, task.id, "comments")
    comments = nested(task.id, "comments")

    cell = "[id='task-row-#{task.id}-n-comments-c']"
    # the two elements around it are marked, and the root's rules of the
    # kit pin the outer one and size the inner one
    assert attribute(
             html,
             "#{cell} > [data-ash-data-table-portal] > [data-ash-data-table-view] > [id='#{comments}']",
             "id"
           ) == [comments]

    assert [root] = attribute(html, "[id='task']", "class")

    assert MapSet.subset?(
             MapSet.new([
               "[&_[data-ash-data-table-portal]]:sticky",
               "[&_[data-ash-data-table-portal]]:left-0",
               "[&_[data-ash-data-table-portal]]:w-0",
               "[&_[data-ash-data-table-view]]:w-[var(--ash-data-table-view)]"
             ]),
             MapSet.new(String.split(root))
           )

    assert [class] = attribute(html, "[id='#{comments}-grid']", "class")
    assert "overflow-x-auto" in String.split(class)
    assert "overscroll-x-contain" in String.split(class)
    assert attribute(html, "[id='#{comments}-scrollbar']", "aria-hidden") == ["true"]
    # the comments say nothing of their label
    assert attribute(html, "[id='#{comments}-table'] [role=columnheader]", "role") != []
    assert attribute(html, "[id='#{comments}-table'] [role=columnheader][data-label]", "id") == []

    # what a line holds stays at the left edge as well
    assert [line] = attribute(html, "[id='task-row-#{task.id}-l-comments-c'] > div", "class")
    assert "sticky" in String.split(line)

    # the tasks of a project are the table of /tasks, which says it
    {:ok, view, _html} = live(conn, "/projects")
    expand(view, "project", task.project_id)
    html = toggle(view, "project", task.project_id, "tasks")
    tasks = nested("project", task.project_id, "tasks")

    assert attribute(html, "[id='#{tasks}-table'] [role=columnheader][data-label]", "id") == [
             "#{tasks}-head-title"
           ]
  end
end
