defmodule DemoWeb.Tables.TaskExportTest do
  @moduledoc """
  "Export CSV" in the line above the grid of `/tasks`: an action on the
  selection (`selection_argument :ids`, `sort_argument :sort`), which runs
  once on every selected task, and returns a file (`Ash.Type.File`), which
  the table pushes to the page for the browser to save
  (`ash_data_table:download`). The export is ash_csv_interchange's
  (`Demo.Tracker.Task.ExportCsv`, `csv_exports`).

  Each selection kind (rows, the whole page, all that match), the table's
  sort, and what a person may not read. The download in a browser is in
  `e2e/export.spec.ts`.
  """
  use DemoWeb.ModeCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage
  import Demo.Records, only: [task_on_day: 3]

  setup do
    # twelve tasks of the world's organization, the first page of ten
    # holds twelve to three: the read action's sort is the newest first
    world = world(tasks: 0)
    tasks = for day <- 1..12, do: task_on_day(world, day, [])
    %{world: world, tasks: tasks}
  end

  # Runs "Export CSV" on what is selected, as the hook does: the action
  # asks nothing and has no panel, so it runs at once. The page once it
  # has run, and the file the table pushed.
  defp export(view) do
    send_event(view, "task", "bulk", %{"action" => "export_csv"})
    assert_reply(view, %{ok: true})
    html = ran(view)

    assert_push_event(view, "ash_data_table:download", %{
      table: "task",
      name: name,
      type: type,
      data: data
    })

    %{html: html, name: name, type: type, rows: rows(Base.decode64!(data))}
  end

  # The CSV, as rows of fields: the header first. No field of these tasks
  # holds a comma, a quote or a line break.
  defp rows(csv), do: csv |> String.split("\r\n", trim: true) |> Enum.map(&String.split(&1, ","))

  defp titles([_header | rows]), do: Enum.map(rows, &Enum.at(&1, 1))

  defp title(day), do: "Task #{String.pad_leading("#{day}", 2, "0")}"

  describe "Export CSV" do
    test "is in the line above the grid, with the actions on the selected rows",
         %{conn: conn, world: world} do
      {:ok, _view, html} = conn |> log_in(world.member) |> live("/tasks")

      assert "Export CSV" in selection(html).buttons
      # the actions after the first two are in the menu "More"
      assert attribute(html, "#task-bulk-more [data-bulk]", "data-bulk") |> List.last() ==
               "export_csv"

      # no row has it: it runs on the selection
      refute html =~ "-a-export_csv"
    end

    test "exports the rows that are selected, and no others, as tasks.csv",
         %{conn: conn, world: world, tasks: tasks} do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")
      [one, _two, three | _rest] = tasks

      select(view, "task", [one.id, three.id])

      assert %{html: html, name: "tasks.csv", type: "text/csv", rows: [header | rows] = all} =
               export(view)

      assert header == [
               "id",
               "title",
               "status",
               "priority",
               "progress",
               "billable",
               "due_on",
               "completed_at",
               "tags",
               "inserted_at"
             ]

      assert Enum.sort(Enum.map(rows, &hd/1)) == Enum.sort([one.id, three.id])
      # in the table's order: the newest first, as the read action sorts
      assert titles(all) == [title(3), title(1)]

      # said above the grid and read out, as a table action's result is
      assert bulk_result(html) == %{summary: "Export CSV: tasks.csv", failures: []}
      assert announcement(html) == "Export CSV: tasks.csv"

      # the rows stay selected: nothing of them changed
      refute_push_event(view, "ash_data_table:select", %{table: "task"})
    end

    test "exports the whole page, and not the tasks of the other pages",
         %{conn: conn, world: world} do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")
      page_size(view, "task", 10)

      html = select_page(view)
      assert length(page_rows(html)) == 10

      assert %{rows: rows} = export(view)
      assert titles(rows) == Enum.map(12..3//-1, &title/1)
    end

    test "exports all that match under the person's filters, read as it runs, with the tasks of every page",
         %{conn: conn, world: world} do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")
      page_size(view, "task", 10)

      # every task: the twelve, on two pages
      select_page(view)
      select(view, "task", :all)
      assert %{rows: rows} = export(view)
      assert titles(rows) == Enum.map(12..1//-1, &title/1)

      # under a filter: those it matches, read when the action runs
      filter(view, "task", "title", v: "Task 1")
      select(view, "task", :all)
      assert %{rows: rows} = export(view)
      assert titles(rows) == [title(12), title(11), title(10)]
    end

    test "keeps the table's sort, which the action is given",
         %{conn: conn, world: world} do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")

      # by title, ascending, then descending
      view |> element("#task-sort-title") |> render_click()
      select(view, "task", :all)
      assert %{rows: rows} = export(view)
      assert titles(rows) == Enum.map(1..12, &title/1)

      view |> element("#task-sort-title") |> render_click()
      select(view, "task", :all)
      assert %{rows: rows} = export(view)
      assert titles(rows) == Enum.map(12..1//-1, &title/1)

      # the rows a person selected, in that order too
      [first, second, third | _rest] = page_rows(render(view))
      select(view, "task", [third, first, second])
      assert %{rows: rows} = export(view)
      assert titles(rows) == [title(12), title(11), title(10)]
    end

    test "exports only what the person may read: a key of another organization's task, or of none, is left out",
         %{conn: conn, world: world, tasks: [one | _rest]} do
      {:ok, view, _html} = conn |> log_in(world.member) |> live("/tasks")
      [outside | _others] = world.other_tasks

      select(view, "task", [one.id, outside.id, Ash.UUID.generate()])
      assert %{rows: [_header | rows]} = export(view)
      assert Enum.map(rows, &hd/1) == [one.id]

      # nothing of it there: the action does not run, and says so
      select(view, "task", [outside.id])
      send_event(view, "task", "bulk", %{"action" => "export_csv"})
      html = ran(view)
      refute_push_event(view, "ash_data_table:download", %{})

      assert bulk_result(html) == %{
               summary: "Export CSV failed: None of the selected records is available any more.",
               failures: []
             }
    end

    test "leaves out the columns a field policy hides from some people",
         %{conn: conn, world: world, tasks: [one | _rest]} do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")

      select(view, "task", [one.id])
      assert %{rows: [header | _rows]} = export(view)
      refute "external_ref" in header
      refute "estimate_hours" in header
    end
  end
end
