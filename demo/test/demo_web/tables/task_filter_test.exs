defmodule DemoWeb.Tables.TaskFilterTest do
  @moduledoc """
  Filtering the mounted table of `Demo.Tracker.Task` at `/tasks`: the filter
  row under the header, as a person meets and operates it.
  """
  use DemoWeb.ModeCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator

  describe "the filter row" do
    setup %{conn: conn} do
      world = world(tasks: 0)
      {:ok, _view, html} = conn |> log_in(world.admin) |> live("/tasks")
      %{html: html}
    end

    test "offers text an operator menu and a text input", %{html: html} do
      assert filter_controls(html, "task", "title") == %{
               operators: ["contains", "equals", "starts with"],
               input: "text",
               choices: nil
             }
    end

    test "offers a number its operators and a number input, with is empty only when it can be nil",
         %{html: html} do
      assert filter_controls(html, "task", "progress") == %{
               operators: [
                 "equals",
                 "greater than",
                 "less than",
                 "at least",
                 "at most",
                 "between"
               ],
               input: "number",
               choices: nil
             }

      assert filter_controls(html, "task", "estimate_hours").operators ==
               [
                 "equals",
                 "greater than",
                 "less than",
                 "at least",
                 "at most",
                 "between",
                 "is empty"
               ]
    end

    test "offers a date and a datetime their operators and native inputs", %{html: html} do
      assert filter_controls(html, "task", "due_on") == %{
               operators: ["on", "before", "after", "between", "is empty"],
               input: "date",
               choices: nil
             }

      assert filter_controls(html, "task", "completed_at") == %{
               operators: ["before", "after", "between", "is empty"],
               input: "datetime-local",
               choices: nil
             }

      assert filter_controls(html, "task", "inserted_at").operators ==
               ["before", "after", "between"]
    end

    test "offers a boolean a choice of any, yes and no", %{html: html} do
      assert filter_controls(html, "task", "billable?") == %{
               operators: nil,
               input: nil,
               choices: ["Any", "Yes", "No"]
             }
    end

    test "offers an enum a choice of any and its values by their labels", %{html: html} do
      assert filter_controls(html, "task", "status") == %{
               operators: ["is", "is any of", "is none of"],
               input: nil,
               choices: [
                 "Any",
                 "Backlog",
                 "To do",
                 "In progress",
                 "In review",
                 "Done",
                 "Archived"
               ]
             }
    end

    test "offers a calculation and an aggregate the filter of their type", %{html: html} do
      assert filter_controls(html, "task", "overdue?").choices == ["Any", "Yes", "No"]

      assert filter_controls(html, "task", "comment_count") == %{
               operators: [
                 "equals",
                 "greater than",
                 "less than",
                 "at least",
                 "at most",
                 "between"
               ],
               input: "number",
               choices: nil
             }
    end

    test "has an empty cell for a column declared `filterable? false` and for one the resource cannot filter",
         %{html: html} do
      for field <- ["description", "headline"] do
        assert filter_controls(html, "task", field) == %{operators: nil, input: nil, choices: nil}
        assert attribute(html, "#task-filter-#{field}", "role") == ["gridcell"]
      end
    end

    test "is the second row of the grid, with a cell under every header", %{html: html} do
      assert attribute(html, "#task-head [role=row]", "aria-rowindex") == ["1", "2"]

      assert attribute(html, "#task-filter-row [role=gridcell]", "aria-colindex") ==
               attribute(html, "#task-head-row [role=columnheader]", "aria-colindex")
    end

    test "names every control for people who cannot see where it is", %{html: html} do
      assert attribute(html, "#task-filter-title input", "aria-label") == ["Filter Title"]
      assert attribute(html, "#task-filter-title select", "aria-label") == ["How to filter Title"]

      assert attribute(html, "#task-filter-status select", "aria-label") ==
               ["How to filter State", "Filter State"]
    end
  end

  # Tasks of the world's first organization, one per keyword list of fields,
  # each created a day after the one before it, so the last one is the newest
  # and comes first.
  defp tasks(world, tasks) do
    [project | _] = world.projects

    for {fields, index} <- Enum.with_index(tasks) do
      Generator.generate(
        Generator.task(
          [
            organization_id: world.organization.id,
            project_id: project.id,
            reporter_id: world.admin.id,
            inserted_at: DateTime.add(~U[2026-01-01 12:00:00.000000Z], index, :day)
          ] ++ fields
        )
      )
    end
  end

  defp titles(html), do: column(html, "task", "title")

  describe "a text filter" do
    setup %{conn: conn} do
      world = world(tasks: 0)

      tasks(world, [
        [title: "report", external_ref: nil],
        [title: "Write the report", external_ref: "EXT-1"],
        [title: "Repair the door", external_ref: nil],
        [title: "Report on doors", external_ref: "EXT-2"],
        [title: "No Report", external_ref: "EXT-3"]
      ])

      {:ok, view, html} = conn |> log_in(world.admin) |> live("/tasks")
      %{view: view, html: html}
    end

    test "shows the rows that contain what was typed, once the input is left",
         %{view: view, html: html} do
      assert titles(html) == [
               "No Report",
               "Report on doors",
               "Repair the door",
               "Write the report",
               "report"
             ]

      html = filter(view, "task", "title", v: "report")

      assert titles(html) == ["Write the report", "report"]
    end

    test "applies on Enter as it does on leaving the input", %{view: view} do
      view
      |> form("#task-filters", %{"filter" => %{"title" => %{"v" => "door"}}})
      |> render_submit()

      assert titles(render_async(view)) == ["Report on doors", "Repair the door"]
    end

    test "with equals shows the rows whose text is exactly that", %{view: view} do
      assert titles(filter(view, "task", "title", o: "equals", v: "report")) == ["report"]
    end

    test "with starts with shows the rows that begin with it", %{view: view} do
      assert titles(filter(view, "task", "title", o: "starts_with", v: "Rep")) ==
               ["Report on doors", "Repair the door"]
    end

    test "with is empty shows the rows without a value, and needs none typed", %{view: view} do
      html = filter(view, "task", "external_ref", o: "is_empty")

      assert titles(html) == ["Repair the door", "report"]
      assert filter_controls(html, "task", "external_ref").input == nil
    end

    test "does not apply an operator that was picked while no value is typed", %{view: view} do
      assert titles(filter(view, "task", "title", o: "equals", v: "")) ==
               ["No Report", "Report on doors", "Repair the door", "Write the report", "report"]
    end
  end

  describe "a number filter" do
    setup %{conn: conn} do
      world = world(tasks: 0)

      tasks(world, [
        [title: "Ten", progress: 10, estimate_hours: Decimal.new("2.5"), status: :todo],
        [title: "Fifty", progress: 50, estimate_hours: nil, status: :todo],
        [title: "Also fifty", progress: 50, estimate_hours: Decimal.new("8"), status: :todo],
        [title: "Ninety", progress: 90, estimate_hours: Decimal.new("40"), status: :todo]
      ])

      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")
      %{view: view}
    end

    test "equals is what applies when a number is simply typed", %{view: view} do
      assert titles(filter(view, "task", "progress", v: "50")) == ["Also fifty", "Fifty"]
    end

    test "greater than leaves the number itself out, at least keeps it", %{view: view} do
      assert titles(filter(view, "task", "progress", o: "greater_than", v: "50")) == ["Ninety"]

      assert titles(filter(view, "task", "progress", o: "at_least", v: "50")) ==
               ["Ninety", "Also fifty", "Fifty"]
    end

    test "less than leaves the number itself out, at most keeps it", %{view: view} do
      assert titles(filter(view, "task", "progress", o: "less_than", v: "50")) == ["Ten"]

      assert titles(filter(view, "task", "progress", o: "at_most", v: "50")) ==
               ["Also fifty", "Fifty", "Ten"]
    end

    test "takes a number with decimals for a decimal column", %{view: view} do
      assert titles(filter(view, "task", "estimate_hours", o: "at_most", v: "2.5")) == ["Ten"]
    end

    test "is empty shows the rows without a number", %{view: view} do
      assert titles(filter(view, "task", "estimate_hours", o: "is_empty")) == ["Fifty"]
    end
  end

  describe "a date and a datetime filter" do
    setup %{conn: conn} do
      world = world(tasks: 0)

      tasks(world, [
        [title: "First", due_on: ~D[2026-03-01], completed_at: ~U[2026-03-10 09:00:00Z]],
        [title: "Mid", due_on: ~D[2026-03-15], completed_at: ~U[2026-03-10 09:00:01Z]],
        [title: "Last", due_on: ~D[2026-03-31], completed_at: ~U[2026-03-10 09:00:02Z]],
        [title: "Open end", due_on: nil, completed_at: nil]
      ])

      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")
      %{view: view}
    end

    test "on is what applies when a date is simply picked", %{view: view} do
      assert titles(filter(view, "task", "due_on", v: "2026-03-15")) == ["Mid"]
    end

    test "before and after a date leave the day itself out", %{view: view} do
      assert titles(filter(view, "task", "due_on", o: "before", v: "2026-03-15")) == ["First"]
      assert titles(filter(view, "task", "due_on", o: "after", v: "2026-03-15")) == ["Last"]
    end

    test "is empty shows the rows without a date", %{view: view} do
      assert titles(filter(view, "task", "due_on", o: "is_empty")) == ["Open end"]
    end

    test "before is what applies when a datetime is simply picked, to the second",
         %{view: view} do
      assert titles(filter(view, "task", "completed_at", v: "2026-03-10T09:00:01")) == ["First"]
    end

    test "after a datetime leaves the moment itself out", %{view: view} do
      assert titles(filter(view, "task", "completed_at", o: "after", v: "2026-03-10T09:00:01")) ==
               ["Last"]
    end

    test "a datetime picked to the minute means that minute's start", %{view: view} do
      assert titles(filter(view, "task", "completed_at", o: "after", v: "2026-03-10T09:00")) ==
               ["Last", "Mid"]
    end

    test "is empty shows the rows without a datetime", %{view: view} do
      assert titles(filter(view, "task", "completed_at", o: "is_empty")) == ["Open end"]
    end
  end

  describe "a choice" do
    setup %{conn: conn} do
      world = world(tasks: 0)
      late = Date.add(Date.utc_today(), -3)
      soon = Date.add(Date.utc_today(), 3)

      [quiet, _busy, chatty] =
        tasks(world, [
          [title: "Quiet", billable?: true, status: :todo, priority: :low, due_on: soon],
          [title: "Busy", billable?: false, status: :in_review, priority: :urgent, due_on: late],
          [title: "Chatty", billable?: true, status: :done, priority: :low, due_on: late]
        ])

      comment = [organization_id: world.organization.id, author_id: world.admin.id]
      Generator.generate(Generator.comment([task_id: quiet.id] ++ comment))
      Generator.generate_many(Generator.comment([task_id: chatty.id] ++ comment), 3)

      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")
      %{view: view}
    end

    test "of yes or no filters a boolean, and any shows all again", %{view: view} do
      assert titles(filter(view, "task", "billable?", o: "yes")) == ["Chatty", "Quiet"]
      assert titles(filter(view, "task", "billable?", o: "no")) == ["Busy"]
      assert titles(filter(view, "task", "billable?", o: "")) == ["Chatty", "Busy", "Quiet"]
    end

    test "of a value filters an enum, and any shows all again", %{view: view} do
      assert titles(filter(view, "task", "status", v: "in_review")) == ["Busy"]
      assert titles(filter(view, "task", "status", v: "")) == ["Chatty", "Busy", "Quiet"]
    end

    test "combines with the other filters: a row has to match all of them", %{view: view} do
      assert titles(filter(view, "task", "priority", v: "low")) == ["Chatty", "Quiet"]
      assert titles(filter(view, "task", "status", v: "done")) == ["Chatty"]
      assert titles(filter(view, "task", "billable?", o: "no")) == []
      assert titles(filter(view, "task", "priority", v: "")) == []
      assert titles(filter(view, "task", "status", v: "")) == ["Busy"]
    end

    test "filters a calculation", %{view: view} do
      # done is not open, so only the late task still in review is overdue
      assert titles(filter(view, "task", "overdue?", o: "yes")) == ["Busy"]
      assert titles(filter(view, "task", "overdue?", o: "no")) == ["Chatty", "Quiet"]
    end

    test "filters an aggregate", %{view: view} do
      assert titles(filter(view, "task", "comment_count", o: "at_least", v: "1")) ==
               ["Chatty", "Quiet"]

      assert titles(filter(view, "task", "comment_count", o: "equals", v: "0")) == ["Busy"]
    end
  end

  describe "a filter with paging and sorting" do
    setup %{conn: conn} do
      world = world(tasks: 0)

      # the odd ones are billable: 30 of 60
      tasks(
        world,
        for n <- 1..60 do
          [title: "Task " <> String.pad_leading("#{n}", 2, "0"), billable?: rem(n, 2) == 1]
        end
      )

      %{conn: log_in(conn, world.admin)}
    end

    defp numbered(range), do: for(n <- range, do: "Task " <> String.pad_leading("#{n}", 2, "0"))

    test "returns to the first page, and the range and the total follow", %{conn: conn} do
      {:ok, view, html} = live(conn, "/tasks?task[page]=3")

      assert text(html, "#task-range") == "51–60 of 60"

      html = filter(view, "task", "billable?", o: "yes")

      assert titles(html) == numbered(59..11//-2)
      assert text(html, "#task-range") == "1–25 of 30"
      assert attribute(html, "#task-pagination [aria-current=page]", "id") == ["task-page-1"]

      assert attribute(html, "#task-pagination button", "id") ==
               ["task-previous", "task-page-1", "task-page-2", "task-next"]

      # 30 tasks, the two header rows and the footer row of the summaries
      assert attribute(html, "#task-table", "aria-rowcount") == ["33"]
    end

    test "stays while paging", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/tasks")
      filter(view, "task", "billable?", o: "yes")

      view |> element("#task-next") |> render_click()
      html = render_async(view)

      assert titles(html) == numbered(9..1//-2)
      assert text(html, "#task-range") == "26–30 of 30"
    end

    test "combines with the sort, whichever was chosen first", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/tasks")

      view |> element("#task-head-title") |> render_click()
      render_async(view)
      html = filter(view, "task", "billable?", o: "no")

      assert titles(html) == numbered(2..50//2)
      assert attribute(html, "#task-head-title", "aria-sort") == ["ascending"]

      view |> element("#task-head-title") |> render_click()
      html = render_async(view)

      assert titles(html) == numbered(60..12//-2)
      assert filter_controls(html, "task", "billable?").choices == ["Any", "Yes", "No"]

      assert attribute(html, "[id='task-filter-billable?-value'] option[selected]", "value") ==
               ["no"]
    end
  end

  describe "clearing" do
    setup %{conn: conn} do
      world = world(tasks: 0)

      tasks(world, [
        [title: "Paint the fence", billable?: true],
        [title: "Paint the door", billable?: false],
        [title: "Oil the door", billable?: true]
      ])

      {:ok, view, html} = conn |> log_in(world.admin) |> live("/tasks")
      %{view: view, html: html}
    end

    test "is not offered while no filter is set", %{html: html} do
      assert attribute(html, "#task-clear-filters", "id") == []
      assert attribute(html, "#task-filter-row button", "id") == []
    end

    test "a filter with a value has a clear button, which removes that filter alone",
         %{view: view} do
      filter(view, "task", "title", v: "Paint")
      html = filter(view, "task", "billable?", o: "yes")

      assert titles(html) == ["Paint the fence"]

      assert attribute(html, "#task-filter-row button", "id") ==
               ["task-filter-title-clear", "task-filter-billable?-clear"]

      assert attribute(html, "#task-filter-title-clear", "aria-label") ==
               ["Clear the Title filter"]

      view |> element("#task-filter-title-clear") |> render_click()
      html = render_async(view)

      assert titles(html) == ["Oil the door", "Paint the fence"]
      assert attribute(html, "#task-filter-title-value", "value") == []
      assert attribute(html, "#task-filter-row button", "id") == ["task-filter-billable?-clear"]
    end

    test "Clear filters appears while a filter is set and removes them all", %{view: view} do
      filter(view, "task", "title", v: "door")
      html = filter(view, "task", "billable?", o: "no")

      assert titles(html) == ["Paint the door"]
      assert text(html, "#task-clear-filters") == "Clear filters"

      view |> element("#task-clear-filters") |> render_click()
      html = render_async(view)

      assert titles(html) == ["Oil the door", "Paint the door", "Paint the fence"]
      assert attribute(html, "#task-clear-filters", "id") == []
      assert attribute(html, "#task-filter-row button", "id") == []
      assert attribute(html, "#task-filter-title-value", "value") == []
      assert attribute(html, "[id='task-filter-billable?-value'] option[selected]", "value") == []
    end
  end

  describe "announcing the result" do
    setup %{conn: conn} do
      world = world(tasks: 0)

      tasks(world, [
        [title: "Paint the fence"],
        [title: "Paint the door"],
        [title: "Oil the door"]
      ])

      {:ok, view, html} = conn |> log_in(world.admin) |> live("/tasks")
      %{view: view, html: html}
    end

    test "has a live region that says nothing until a filter changes", %{html: html} do
      assert attribute(html, "#task-status", "aria-live") == ["polite"]
      assert attribute(html, "#task-status", "role") == ["status"]
      assert text(html, "#task-status") == ""
    end

    test "says how many records match after each filter change", %{view: view} do
      assert text(filter(view, "task", "title", v: "Paint"), "#task-status") == "2 results"
      assert text(filter(view, "task", "title", v: "fence"), "#task-status") == "1 result"
      assert text(filter(view, "task", "title", v: "roof"), "#task-status") == "0 results"

      view |> element("#task-clear-filters") |> render_click()

      assert text(render_async(view), "#task-status") == "3 results"
    end

    test "changes its content even when the count stays the same, so that it is read out again",
         %{view: view} do
      first = filter(view, "task", "title", v: "Paint")
      second = filter(view, "task", "title", v: "door")

      assert text(first, "#task-status") == "2 results"
      assert text(second, "#task-status") == "2 results"

      [first] =
        first |> LazyHTML.from_fragment() |> LazyHTML.query("#task-status") |> Enum.to_list()

      [second] =
        second |> LazyHTML.from_fragment() |> LazyHTML.query("#task-status") |> Enum.to_list()

      assert LazyHTML.text(first) != LazyHTML.text(second)
    end
  end

  describe "the URL" do
    setup %{conn: conn} do
      world = world(tasks: 0)

      tasks(world, [
        [title: "Paint the fence", progress: 20, billable?: true, status: :todo, due_on: nil],
        [
          title: "Paint the door",
          progress: 50,
          billable?: false,
          status: :in_review,
          due_on: nil
        ],
        [
          title: "Oil the door",
          progress: 80,
          billable?: true,
          status: :in_review,
          due_on: ~D[2026-05-01]
        ]
      ])

      %{conn: log_in(conn, world.admin)}
    end

    test "holds each filter under the table's id, compactly", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/tasks")

      # the default operator: the value alone
      filter(view, "task", "title", v: "Paint")
      assert_patch(view, "/tasks?task[f][title]=Paint")

      # another operator: named
      filter(view, "task", "progress", o: "at_least", v: "50")
      assert_patch(view, "/tasks?task[f][progress][at_least]=50&task[f][title]=Paint")

      view |> element("#task-clear-filters") |> render_click()
      assert_patch(view, "/tasks")

      # an operator without a value
      filter(view, "task", "due_on", o: "is_empty")
      assert_patch(view, "/tasks?task[f][due_on][is_empty]=")

      # choices
      filter(view, "task", "due_on", o: "on")
      filter(view, "task", "billable?", o: "yes")
      assert_patch(view, "/tasks?task[f][billable%3F]=yes")

      filter(view, "task", "status", v: "in_review")
      assert_patch(view, "/tasks?task[f][billable%3F]=yes&task[f][status]=in_review")
    end

    test "opened afresh, the URL a person reached by filtering shows the same rows and filters",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, "/tasks")

      filter(view, "task", "title", v: "door")
      assert_patch(view)
      filter(view, "task", "progress", o: "at_least", v: "50")
      assert_patch(view)
      filter(view, "task", "status", v: "in_review")
      assert_patch(view)
      filter(view, "task", "billable?", o: "yes")
      assert_patch(view)
      reached = filter(view, "task", "due_on", o: "after", v: "2026-04-30")
      url = assert_patch(view)

      {:ok, _view, opened} = live(conn, url)

      assert url ==
               "/tasks?task[f][billable%3F]=yes&task[f][due_on][after]=2026-04-30" <>
                 "&task[f][progress][at_least]=50&task[f][status]=in_review&task[f][title]=door"

      assert titles(opened) == ["Oil the door"]
      assert titles(opened) == titles(reached)

      assert attribute(opened, "#task-filter-title-value", "value") == ["door"]

      assert attribute(opened, "#task-filter-title-operator option[selected]", "value") ==
               ["contains"]

      assert attribute(opened, "#task-filter-progress-value", "value") == ["50"]

      assert attribute(opened, "#task-filter-progress-operator option[selected]", "value") ==
               ["at_least"]

      assert attribute(opened, "#task-filter-status-value option[selected]", "value") ==
               ["in_review"]

      assert attribute(opened, "[id='task-filter-billable?-value'] option[selected]", "value") ==
               ["yes"]

      assert attribute(opened, "#task-filter-due_on-value", "value") == ["2026-04-30"]

      assert attribute(opened, "#task-filter-due_on-operator option[selected]", "value") == [
               "after"
             ]

      assert text(opened, "#task-clear-filters") == "Clear filters"
      assert text(opened, "#task-range") == "1–1 of 1"
    end

    test "a filter without a value is opened afresh too", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/tasks?task[f][due_on][is_empty]=")

      assert titles(html) == ["Paint the door", "Paint the fence"]

      assert attribute(html, "#task-filter-due_on-operator option[selected]", "value") == [
               "is_empty"
             ]

      assert filter_controls(html, "task", "due_on").input == nil
    end

    test "filter parameters that mean nothing to the table are ignored", %{conn: conn} do
      for query <- [
            "task[f]=title",
            "task[f][]=title",
            "task[f][no_such_column]=x",
            "task[f][internal_note]=x",
            "task[f][description]=x",
            "task[f][headline]=x",
            "task[f][title]=",
            "task[f][title][no_such_operator]=x",
            "task[f][title][at_least]=x",
            "task[f][title][contains][]=x",
            "task[f][title][contains]=a&task[f][title][equals]=b",
            "task[f][progress][is_empty]=",
            "task[f][billable%3F]=maybe",
            "task[f][billable%3F][is_empty]=",
            "task[f][status]=no_such_status",
            "task[f][progress]=abc",
            "task[f][progress][at_least]=1.5",
            "task[f][estimate_hours]=1,5",
            "task[f][due_on]=2026-02-31",
            "task[f][due_on][before]=soon",
            "task[f][completed_at]=10 o'clock",
            "task[f][comment_count]=many",
            "task[f][status][contains]=todo"
          ] do
        {:ok, _view, html} = live(conn, "/tasks?" <> query)

        assert titles(html) == ["Oil the door", "Paint the door", "Paint the fence"], query
        assert attribute(html, "#task-clear-filters", "id") == [], query
        assert text(html, "#task-error") == nil, query
      end
    end

    test "a filter that means something is kept beside one that does not", %{conn: conn} do
      {:ok, _view, html} =
        live(conn, "/tasks?task[f][title]=door&task[f][nope]=1&task[sort]=nope")

      assert titles(html) == ["Oil the door", "Paint the door"]
    end

    test "parameters of the page that are not the table's are kept", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/tasks?utm=mail&other[f][title]=1&task[sort]=title")

      filter(view, "task", "title", v: "door")
      assert_patch(view, "/tasks?other[f][title]=1&task[f][title]=door&task[sort]=title&utm=mail")

      view |> element("#task-filter-title-clear") |> render_click()
      assert_patch(view, "/tasks?other[f][title]=1&task[sort]=title&utm=mail")
    end
  end

  describe "a value that is not one" do
    setup %{conn: conn} do
      world = world(tasks: 0)
      tasks(world, [[title: "Ten", progress: 10], [title: "Fifty", progress: 50]])

      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")
      %{view: view}
    end

    test "is not applied, and its filter says so", %{view: view} do
      # a number input lets a number with decimals through; the column holds whole numbers
      html = filter(view, "task", "progress", v: "1.5")

      assert titles(html) == ["Fifty", "Ten"]
      assert text(html, "#task-error") == nil
      assert attribute(html, "#task-filter-progress-value", "value") == ["1.5"]
      assert attribute(html, "#task-filter-progress-value", "aria-invalid") == ["true"]

      assert attribute(html, "#task-filter-progress-value", "aria-describedby") ==
               ["task-filter-progress-error"]

      assert text(html, "#task-filter-progress-error") == "Not a valid value"
      assert attribute(html, "#task-clear-filters", "id") == []
    end

    test "takes the place of the filter that applied before", %{view: view} do
      assert titles(filter(view, "task", "progress", v: "50")) == ["Fifty"]

      html = filter(view, "task", "progress", v: "half")

      assert titles(html) == ["Fifty", "Ten"]
      assert attribute(html, "#task-filter-progress-value", "aria-invalid") == ["true"]
      assert_patch(view, "/tasks")
    end

    test "is forgotten once a value that is one is typed", %{view: view} do
      filter(view, "task", "progress", v: "1.5")
      html = filter(view, "task", "progress", v: "10")

      assert titles(html) == ["Ten"]
      assert attribute(html, "#task-filter-progress-value", "aria-invalid") == []
      assert text(html, "#task-filter-progress-error") == nil
    end

    test "does not stop the other filters", %{view: view} do
      filter(view, "task", "progress", v: "1.5")
      html = filter(view, "task", "title", v: "Fif")

      assert titles(html) == ["Fifty"]
      assert attribute(html, "#task-filter-progress-value", "aria-invalid") == ["true"]
    end

    test "is not a date or a datetime either", %{view: view} do
      html = filter(view, "task", "due_on", v: "2026-02-31")
      assert titles(html) == ["Fifty", "Ten"]
      assert text(html, "#task-filter-due_on-error") == "Not a valid value"

      html = filter(view, "task", "completed_at", v: "yesterday")
      assert titles(html) == ["Fifty", "Ten"]
      assert text(html, "#task-filter-completed_at-error") == "Not a valid value"
    end
  end

  describe "who is reading" do
    setup do
      world = world(tasks: 0, other_tasks: 0)

      tasks(world, [
        [title: "Acme plan", external_ref: "EXT-SECRET-1", assignee_id: nil],
        [title: "Acme report", external_ref: nil, assignee_id: nil]
      ])

      [project] = Enum.take(Ash.read!(Demo.Tracker.Project, as(world.outsider)), 1)

      Generator.generate(
        Generator.task(
          organization_id: world.other_organization.id,
          project_id: project.id,
          reporter_id: world.outsider.id,
          title: "Globex plan",
          external_ref: "EXT-SECRET-2"
        )
      )

      %{world: world}
    end

    test "a filter never shows the tasks of another organization", %{conn: conn, world: world} do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")
      html = filter(view, "task", "title", v: "plan")

      assert titles(html) == ["Acme plan"]
      assert text(html, "#task-status") == "1 result"

      {:ok, view, _html} = conn |> log_in(world.outsider) |> live("/tasks")
      html = filter(view, "task", "title", v: "plan")

      assert titles(html) == ["Globex plan"]
      assert text(html, "#task-status") == "1 result"
    end

    test "nobody finds nothing, whatever the filter", %{conn: conn, world: world} do
      {:ok, _view, html} = conn |> log_in(world.nobody) |> live("/tasks?task[f][title]=plan")

      assert titles(html) == []
      assert text(html, "#task-empty") == "No records"
    end

    test "a field the reader can never see has no filter to search it through",
         %{conn: conn, world: world} do
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")
      assert titles(filter(view, "task", "external_ref", v: "SECRET")) == ["Acme plan"]

      {:ok, _view, html} = conn |> log_in(world.member) |> live("/tasks")

      assert attribute(html, "#task-filter-external_ref", "id") == []
      assert attribute(html, "[name^='filter[external_ref]']", "name") == []
      refute html =~ "EXT-SECRET"
    end
  end
end
