defmodule DemoWeb.Tables.LookTest do
  @moduledoc """
  The look of a table (`AshDataTable.Kit`, "The look of a table"): what a
  table is placed with reaches its kit, and every table it shows, nested
  tables and pickers' tables too; the default kit draws the options that
  are on, and nothing of those that are off. How it looks is the
  browser's (the screenshots of the build); what the server renders is
  checked here.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  setup %{conn: conn} do
    world = world(tasks: 3, comments: 3)
    %{world: world, conn: log_in(conn, world.admin)}
  end

  defp classes(html, selector),
    do: html |> attribute(selector, "class") |> Enum.flat_map(&String.split/1)

  @sticky "[&_[role=table]>:has(>[role=row]>[role=columnheader])]:sticky"
  @stripes "[&_[role=table]>:where([role=rowgroup]:nth-child(even_of_[role=rowgroup]:not([data-detail],:has(>[role=row]>[role=columnheader]))))>[role=row]>:is([role=cell],[role=rowheader])]:[background-image:linear-gradient(var(--ash-data-table-stripe),var(--ash-data-table-stripe))]"
  @column_lines "[&_[role=table]>*>[role=row]>:not(:first-child,[colspan])]:border-s"
  @compact "[&_[role=table]>*>[role=row]>:not([colspan])]:py-1"
  @normal "[&_[role=table]>*>[role=row]>:not([colspan])]:py-2"

  test "the default kit draws its default look: no option on", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/tasks")
    root = classes(html, "#task")

    assert @normal in root
    refute @sticky in root
    refute @stripes in root
    refute @column_lines in root
    # nor any `style` in the page: how high a table is, is the host's CSS
    assert attribute(html, "[style]", "style") == []
  end

  test "the options a router line names are drawn, those it does not are not", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/projects/sticky")
    root = classes(html, "#project-sticky")
    assert @sticky in root
    assert "[&_[data-scrollbar]]:hidden!" in root
    refute @stripes in root

    {:ok, _view, html} = live(conn, "/tasks/striped")
    root = classes(html, "#task-striped")
    assert @compact in root
    refute @normal in root
    assert @stripes in root
    assert @column_lines in root
    refute @sticky in root
  end

  test "a number is at the end of its cell: its cells and header say so, other columns' do not",
       %{conn: conn} do
    {:ok, _view, html} = live(conn, "/specimens")
    assert attribute(html, "[id$='-head-an_integer']", "data-number") == [""]
    assert attribute(html, "[id$='-head-a_float']", "data-number") == [""]
    # and no column of another type
    assert attribute(html, "[id$='-head-a_string']", "data-number") == []

    {:ok, _view, html} = live(conn, "/tasks")
    # the estimate is drawn by a component of the demo's, which places it
    assert attribute(html, "#task-head-estimate_hours", "data-number") == []
    assert attribute(html, "#task-head-title", "data-number") == []
  end

  test "the look reaches the kit for every table shown: nested tables at every depth and a picker's table",
       %{conn: conn, world: world} do
    task =
      Enum.find(world.tasks, fn task -> Enum.any?(world.comments, &(&1.task_id == task.id)) end)

    {:ok, view, html} = live(conn, "/look/tasks")

    # the route's options over the kit's own (`column_lines: true`)
    said = "look-compact-false-true-true"
    assert said in classes(html, "#looked")

    expand(view, "looked", task.id)
    html = toggle(view, "looked", task.id, "comments")
    nested = nested("looked", task.id, "comments")
    assert said in classes(html, "[id='#{nested}']")
    # its line says how many records it has, once it has read
    count = Enum.count(world.comments, &(&1.task_id == task.id))

    assert text(html, "[id='looked-row-#{task.id}-l-comments-c']") =~
             ~r/^Comments\s+#{count} records?(\s|$)/

    assert text(html, "[id='looked-row-#{task.id}-l-comments-b']") == "Comments"

    # no `style` in the page, nested tables' none either
    assert attribute(html, "[style]", "style") == []

    [comment | _] = Enum.filter(world.comments, &(&1.task_id == task.id))
    expand(view, nested, comment.id)
    html = toggle(view, nested, comment.id, "task")
    assert said in classes(html, "[id='#{nested(nested, comment.id, "task")}']")

    pick(view, "looked", task.id, "assignee")
    html = render_async(view, 10_000)
    assert said in classes(html, "[id='looked-pick-assignee']")
  end

  describe "which cells can be edited" do
    test "a lock, named \"read-only\", after the heading of a column no row may be edited in; none after an editable one",
         %{conn: conn, world: world} do
      {:ok, _view, html} = live(conn, "/tasks")
      [task | _] = world.tasks

      # `overdue?` is a calculation, `reporter` no update action accepts
      for column <- ["overdue?", "reporter"] do
        assert attribute(html, "[id='task-head-#{column}'] > svg[role=img]", "aria-label") == [
                 "read-only"
               ],
               column
      end

      assert attribute(html, "#task-head-title > svg", "aria-label") == []
      # and its cells are no Tab stops; an editable one is
      assert attribute(html, cell("task", task.id, "reporter"), "tabindex") == []
      assert attribute(html, cell("task", task.id, "title"), "tabindex") == ["0"]
    end

    test "a table that offers the person no editing draws no lock at all", %{
      conn: conn,
      world: world
    } do
      {:ok, _view, html} = conn |> log_in(world.viewer) |> live("/tasks")
      assert attribute(html, "#task-head-row svg[role=img]", "aria-label") == []
    end

    test "the look of an editable and a read-only cell is in the root's rules, once per page", %{
      conn: conn
    } do
      {:ok, _view, html} = live(conn, "/tasks")
      root = classes(html, "#task")

      assert Enum.any?(
               root,
               &(String.contains?(&1, "template[data-editor]") and
                   String.ends_with?(&1, ":cursor-text"))
             )

      # every focus ring of the kit's own in the text colour (#46): none in
      # the primary colour, none dashed
      refute Enum.any?(root, &String.contains?(&1, "outline-dashed"))

      refute Enum.any?(
               root,
               &String.contains?(&1, "outline-[color-mix(in_oklab,var(--color-primary)")
             )

      assert Enum.any?(root, &String.ends_with?(&1, ":focus]:outline-base-content"))
    end
  end
end
