defmodule DemoWeb.Tables.ColumnHidingTest do
  @moduledoc """
  What the server renders for a person to hide columns with: the "Columns"
  button above the grid, and the list it opens, with a box for every column
  that can be hidden. Which columns are hidden is the browser's alone
  (`demo/e2e/hiding.spec.ts`): the server renders every box ticked and every
  column as before, and never hears of a hidden column. What it does say is
  which columns the rows are filtered and sorted by, at their boxes.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  setup %{conn: conn} do
    world = world(tasks: 3)
    %{world: world, conn: log_in(conn, world.admin)}
  end

  # The columns the list of the table `id` offers, in order.
  defp listed(html, id) do
    html
    |> attribute("[id='#{id}-columns'] input[type=checkbox]", "id")
    |> Enum.map(&String.replace_prefix(&1, "#{id}-column-", ""))
  end

  defp columns(html, id) do
    html
    |> attribute("[id='#{id}-table'] > thead th[id^='#{id}-head-']", "id")
    |> Enum.map(&String.replace_prefix(&1, "#{id}-head-", ""))
  end

  # What the line of a column in the list reads.
  defp entry(html, id, field) do
    html |> text("[id='#{id}-column-#{field}-entry']") |> String.replace(~r/\s+/, " ")
  end

  defp flags(html, id) do
    for field <- listed(html, id),
        box = "[id='#{id}-column-#{field}']",
        flags =
          Enum.filter(~w(data-filtered data-sorted), &(attribute(html, box, &1) != [])),
        flags != [],
        do: {field, flags}
  end

  describe "the button" do
    test "is a button above the grid that says whether its list is open, and which list that is",
         %{conn: conn} do
      {:ok, _view, html} = live(conn, "/tasks")

      assert text(html, "#task-columns-button") == "Columns"
      assert attribute(html, "#task-columns-button", "type") == ["button"]
      assert attribute(html, "#task-columns-button", "aria-expanded") == ["false"]
      assert attribute(html, "#task-columns-button", "aria-controls") == ["task-columns"]
      # looks as the other buttons of its line do
      assert attribute(html, "#task-columns-button", "class") == ["btn btn-sm"]
      # before the grid, and no part of it
      assert attribute(html, "#task-grid #task-columns-button", "id") == []

      assert attribute(html, "#task > div > #task-columns-control", "id") == [
               "task-columns-control"
             ]
    end

    test "stands beside \"Clear filters\", on the same line", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/tasks")
      html = filter(view, "task", "title", v: "a")

      assert attribute(html, "#task-clear-filters + #task-columns-control", "id") ==
               ["task-columns-control"]
    end

    test "carries the texts the browser puts numbers into", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/tasks")
      data = &List.first(attribute(html, "#task-columns-button", "data-#{&1}"))

      assert data.("text") == "Columns"
      assert data.("text-with") == "Columns ({details})"
      assert data.("text-hidden") == "{n} hidden"
      assert data.("text-filtered") == "{n} filtered"
      assert data.("text-sorted") == "{n} sorted"
      assert data.("say-hidden") == "{column} hidden"
      assert data.("say-shown") == "{column} shown"
    end

    test "has a live region of its own beside it, which the server leaves empty", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/tasks")

      assert attribute(html, "#task-columns-status", "role") == ["status"]
      assert attribute(html, "#task-columns-status", "phx-update") == ["ignore"]
      assert text(html, "#task-columns-status") == ""
    end
  end

  describe "the list" do
    test "is a group of labelled boxes, named, and no menu", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/tasks")

      assert attribute(html, "#task-columns", "role") == ["group"]
      assert attribute(html, "#task-columns", "aria-label") == ["Columns"]
      assert attribute(html, "#task-columns", "popover") == ["manual"]
      assert attribute(html, "#task-columns [role^=menu]", "id") == []

      # every box is in its label, which is its name
      assert attribute(html, "#task-columns > label > input[type=checkbox]", "id") ==
               attribute(html, "#task-columns input", "id")

      assert entry(html, "task", "status") == "State"
      assert entry(html, "task", "billable?") == "Billable?"
    end

    test "has a box for every column but the one of the label, in the columns' order, all ticked",
         %{conn: conn} do
      {:ok, _view, html} = live(conn, "/tasks")

      assert hd(columns(html, "task")) == "title"
      assert listed(html, "task") == tl(columns(html, "task"))
      assert length(listed(html, "task")) > 5

      assert attribute(html, "#task-columns input[type=checkbox]", "checked") ==
               Enum.map(listed(html, "task"), fn _ -> "" end)

      # each names the header of its column
      assert attribute(html, "#task-columns input[type=checkbox]", "data-head") ==
               Enum.map(listed(html, "task"), &"task-head-#{&1}")

      # a column of the label stays: no rule is needed to keep one
      assert attribute(html, "#task-columns", "data-keeps-one") == []
    end

    test "has none for the columns of the boxes, the expanders and the actions", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/tasks")

      for id <- ~w(task-select-head task-expander-head task-actions-head) do
        assert attribute(html, "##{id}", "id") == [id]
      end

      assert length(attribute(html, "#task-columns input", "id")) ==
               length(columns(html, "task")) - 1
    end

    test "in a table without a label every column has a box, and one of them has to stay", %{
      conn: conn
    } do
      {:ok, _view, html} = live(conn, "/comments")

      assert listed(html, "comment") == columns(html, "comment")
      assert attribute(html, "#comment-columns", "data-keeps-one") == [""]
    end

    test "a table with one column has no button: there is nothing to hide", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/support/reports")

      assert length(columns(html, "report")) == 1
      assert attribute(html, "#report-columns-button", "id") == []
      assert attribute(html, "#report-columns", "id") == []
    end
  end

  describe "a column the rows are filtered or sorted by" do
    test "says so at its box, in text, for when it is hidden", %{conn: conn} do
      {:ok, view, html} = live(conn, "/tasks")
      assert flags(html, "task") == []
      assert attribute(html, "#task-columns [data-flag]", "class") == []

      html = filter(view, "task", "status", v: "todo")
      assert flags(html, "task") == [{"status", ["data-filtered"]}]
      assert entry(html, "task", "status") == "State (filtered)"
      assert entry(html, "task", "priority") == "Priority"

      view |> element("#task-head-priority") |> render_click()
      html = render_async(view, 10_000)

      assert flags(html, "task") == [
               {"status", ["data-filtered"]},
               {"priority", ["data-sorted"]}
             ]

      assert entry(html, "task", "priority") == "Priority (sorted)"

      view |> element("#task-head-status") |> render_click()
      html = render_async(view, 10_000)
      assert flags(html, "task") == [{"status", ["data-filtered", "data-sorted"]}]
      assert entry(html, "task", "status") == "State (filtered, sorted)"

      # shown while the box is not ticked, and only then
      assert attribute(html, "#task-column-status-entry > [data-flag]", "class") ==
               ["peer-checked:hidden"]
    end

    test "\"Clear filters\" takes the filter of a column away whether it is shown or not", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, "/tasks")
      html = filter(view, "task", "status", v: "todo")
      assert flags(html, "task") == [{"status", ["data-filtered"]}]

      view |> element("#task-clear-filters") |> render_click()
      html = render_async(view, 10_000)

      assert flags(html, "task") == []
      assert entry(html, "task", "status") == "State"
    end

    test "a filter the table did not take is none", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/tasks")
      html = filter(view, "task", "progress", o: "at_least", v: "many")

      assert flags(html, "task") == []
    end
  end

  describe "every table has its own" do
    test "a nested table", %{conn: conn, world: world} do
      {:ok, view, _html} = live(conn, "/tasks")
      [task | _] = world.tasks

      expand(view, task.id)
      html = toggle(view, task.id, "comments")
      id = nested("task", task.id, "comments")

      assert text(html, "[id='#{id}-columns-button']") == "Columns"
      assert attribute(html, "[id='#{id}-columns-button']", "aria-controls") == ["#{id}-columns"]
      assert attribute(html, "[id='#{id}-columns-button']", "class") == ["btn btn-sm"]
      assert listed(html, id) == columns(html, id)
      # and the table around it has its own still
      assert listed(html, "task") == tl(columns(html, "task"))
    end

    test "the table of a picker", %{conn: conn, world: world} do
      {:ok, view, _html} = live(conn, "/tasks")
      [task | _] = world.tasks

      html = pick(view, task.id, "assignee")
      id = "task-pick-assignee"

      assert text(html, "[id='#{id}-columns-button']") == "Columns"
      assert listed(html, id) != []
      assert listed(html, id) == columns(html, id) -- ["name"]
    end

    test "two tables of one page", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/dashboard")

      for id <- ~w(dashboard-projects dashboard-tasks) do
        assert attribute(html, "##{id}-columns-button", "aria-controls") == ["#{id}-columns"]
        label = if id == "dashboard-projects", do: "name", else: "title"
        assert label in columns(html, id)
        assert listed(html, id) == columns(html, id) -- [label]
      end
    end
  end

  test "a person who does not see a column has no box for it", %{conn: conn, world: world} do
    {:ok, _view, admin} = live(conn, "/projects")
    {:ok, _view, viewer} = conn |> log_in(world.viewer) |> live("/projects")

    assert "budget" in listed(admin, "project")
    refute "budget" in listed(viewer, "project")
    assert listed(viewer, "project") == columns(viewer, "project") -- ["name"]
  end

  test "in German", %{conn: conn} do
    {:ok, view, html} = conn |> in_locale("de") |> live("/tasks")

    assert text(html, "#task-columns-button") == "Spalten"
    assert attribute(html, "#task-columns", "aria-label") == ["Spalten"]
    data = &List.first(attribute(html, "#task-columns-button", "data-#{&1}"))
    assert data.("text-with") == "Spalten ({details})"
    assert data.("text-hidden") == "{n} ausgeblendet"
    assert data.("text-filtered") == "{n} gefiltert"
    assert data.("text-sorted") == "{n} sortiert"
    assert data.("say-hidden") == "{column} ausgeblendet"
    assert data.("say-shown") == "{column} eingeblendet"

    html = filter(view, "task", "status", v: "todo")
    view |> element("#task-head-status") |> render_click()
    html = if html, do: render_async(view, 10_000)
    assert entry(html, "task", "status") =~ "(gefiltert, sortiert)"
  end
end
