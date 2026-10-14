defmodule DemoWeb.Tables.FilterValuesTest do
  @moduledoc """
  The filters that take more than one value, on Postgres: "is any of" and
  "is none of" for a column with a known set of values, and "between" for a
  number, a date and a datetime. At `/tasks`, and at `/specimens` for the
  types `/tasks` does not have.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator
  alias Demo.Tracker.Task

  # Tasks of the world's first organization, the last one the newest, which
  # comes first.
  defp tasks(world, tasks) do
    [project | _] = world.projects

    for {fields, index} <- Enum.with_index(tasks) do
      Generator.generate(
        Generator.task(
          [
            organization_id: world.organization.id,
            project_id: project.id,
            reporter_id: world.admin.id,
            assignee_id: nil,
            inserted_at: DateTime.add(~U[2026-01-01 12:00:00.000000Z], index, :day)
          ] ++ fields
        )
      )
    end
  end

  defp titles(html), do: html |> column("task", "title") |> Enum.sort()

  defp texts(html, selector) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
  end

  # No filter applies: the button that clears them is offered while one does.
  defp refute_filtered(view),
    do: assert(attribute(render(view), "[id$='-clear-filters']", "id") == [])

  # What the row's form is sent, whatever the row offers: a claim.
  defp claim(view, id \\ "task", form) do
    view |> element("##{id}-filters") |> render_change(%{"filter" => form})
    render_async(view, 10_000)
  end

  # Picks the operator, which brings its controls, and then gives it values.
  defp any_of(view, field, values, operator \\ "any_of") do
    filter(view, "task", field, o: operator)
    filter(view, "task", field, o: operator, in: values)
  end

  defp between(view, id \\ "task", field, from, to) do
    filter(view, id, field, o: "between")
    filter(view, id, field, o: "between", from: from, to: to)
  end

  defp ticked(html, field),
    do: attribute(html, "#task-filter-#{field}-values input[checked]", "value")

  setup %{conn: conn} do
    world = world(tasks: 0, other_tasks: 0)

    tasks(world, [
      [
        title: "Alpha",
        status: :todo,
        priority: :low,
        progress: 10,
        estimate_hours: Decimal.new("2"),
        due_on: ~D[2026-03-01],
        completed_at: nil
      ],
      [
        title: "Beta",
        status: :in_progress,
        priority: :high,
        progress: 50,
        estimate_hours: Decimal.new("8.5"),
        due_on: ~D[2026-03-10],
        completed_at: nil
      ],
      [
        title: "Gamma",
        status: :done,
        priority: :low,
        progress: 100,
        estimate_hours: nil,
        due_on: ~D[2026-03-20],
        completed_at: ~U[2026-03-21 10:00:30Z]
      ],
      [
        title: "Delta",
        status: :in_review,
        priority: :urgent,
        progress: 80,
        estimate_hours: Decimal.new("20"),
        due_on: nil,
        completed_at: ~U[2026-03-21 10:01:00Z]
      ]
    ])

    %{world: world, conn: log_in(conn, world.admin)}
  end

  describe "is any of" do
    setup %{conn: conn} do
      {:ok, view, _html} = live(conn, "/tasks")
      %{view: view}
    end

    test "once picked, has a button and a list of the column's values, and filters nothing yet",
         %{view: view} do
      html = filter(view, "task", "status", o: "any_of")

      assert titles(html) == ["Alpha", "Beta", "Delta", "Gamma"]
      refute_filtered(view)

      assert text(html, "#task-filter-status-value") == "Any"
      assert attribute(html, "#task-filter-status-value", "aria-expanded") == ["false"]

      assert attribute(html, "#task-filter-status-value", "aria-controls") ==
               ["task-filter-status-values"]

      assert attribute(html, "#task-filter-status-value", "aria-label") == ["Filter State: Any"]
      assert attribute(html, "#task-filter-status-values", "role") == ["group"]
      assert attribute(html, "#task-filter-status-values", "aria-label") == ["Filter State"]

      assert html |> texts("#task-filter-status-values label") ==
               ["Backlog", "To do", "In progress", "In review", "Done", "Archived"]

      assert attribute(html, "#task-filter-status-values input", "value") ==
               ~w(backlog todo in_progress in_review done archived)

      assert ticked(html, "status") == []
      # nothing to clear, and "Clear filters" is not offered
      assert attribute(html, "#task-filter-status-clear", "id") == []
      assert attribute(html, "#task-clear-filters", "id") == []
      # the single choice is gone: one control for the value
      assert attribute(html, "#task-filter-status select[id$='-value']", "id") == []
    end

    test "shows the rows with one of the chosen values", %{view: view} do
      html = any_of(view, "status", ["todo", "done"])

      assert titles(html) == ["Alpha", "Gamma"]
      assert ticked(html, "status") == ["todo", "done"]
      assert text(html, "#task-filter-status-value") == "2 selected"

      assert attribute(html, "#task-filter-status-value", "aria-label") ==
               ["Filter State: 2 selected"]

      assert attribute(html, "#task-filter-status-value", "title") == ["To do, Done"]
      assert text(html, "#task-status") == "2 results"

      html = filter(view, "task", "status", o: "any_of", in: ["in_review"])
      assert titles(html) == ["Delta"]
      assert text(html, "#task-filter-status-value") == "In review"
    end

    test "with nothing ticked any more is no filter", %{view: view} do
      any_of(view, "status", ["todo"])
      html = filter(view, "task", "status", o: "any_of", in: [])

      assert titles(html) == ["Alpha", "Beta", "Delta", "Gamma"]
      assert text(html, "#task-filter-status-value") == "Any"
      assert_patch(view, "/tasks")
    end

    test "is none of shows the rows with none of them", %{view: view} do
      html = any_of(view, "status", ["todo", "done"], "none_of")

      assert titles(html) == ["Beta", "Delta"]
      assert ticked(html, "status") == ["todo", "done"]
    end

    test "combines with the other filters, a range among them", %{view: view} do
      any_of(view, "status", ["todo", "in_progress", "in_review"])
      any_of(view, "priority", ["low"], "none_of")
      assert titles(render(view)) == ["Beta", "Delta"]

      assert titles(between(view, "progress", "10", "50")) == ["Beta"]
      assert titles(filter(view, "task", "title", v: "zzz")) == []
    end

    test "keeps the chosen value when it follows is, and is keeps it when it is one",
         %{view: view} do
      filter(view, "task", "status", v: "done")

      html = filter(view, "task", "status", o: "any_of")
      assert ticked(html, "status") == ["done"]
      assert titles(html) == ["Gamma"]

      html = filter(view, "task", "status", o: "is")
      assert titles(html) == ["Gamma"]

      assert attribute(html, "#task-filter-status-value option[selected]", "value") == ["done"]
    end

    test "has a clear button, and Clear filters takes it away", %{view: view} do
      html = any_of(view, "status", ["todo", "done"])

      assert attribute(html, "#task-filter-status-clear", "aria-label") ==
               ["Clear the State filter"]

      view |> element("#task-filter-status-clear") |> render_click()
      assert titles(render_async(view, 10_000)) == ["Alpha", "Beta", "Delta", "Gamma"]

      any_of(view, "status", ["todo", "done"])
      between(view, "progress", "10", "")
      view |> element("#task-clear-filters") |> render_click()
      html = render_async(view, 10_000)

      assert titles(html) == ["Alpha", "Beta", "Delta", "Gamma"]
      assert_patch(view, "/tasks")
      # the controls are as on a page opened afresh
      assert filter_controls(html, "task", "progress").input == "number"
      assert attribute(html, "#task-filter-status-values", "id") == []
    end

    test "marks a hidden column as filtered in the list of columns", %{view: view} do
      html = any_of(view, "status", ["todo"])

      assert attribute(html, "#task-column-status", "data-filtered") == [""]
      assert text(html, "#task-column-status-entry [data-flag]") == "(filtered)"
      assert attribute(html, "#task-column-priority", "data-filtered") == []
    end
  end

  describe "between" do
    setup %{conn: conn} do
      {:ok, view, _html} = live(conn, "/tasks")
      %{view: view}
    end

    test "once picked, has two inputs named for what they are, and filters nothing yet",
         %{view: view} do
      html = filter(view, "task", "progress", o: "between")

      assert titles(html) == ["Alpha", "Beta", "Delta", "Gamma"]
      refute_filtered(view)

      assert attribute(html, "#task-filter-progress input", "id") ==
               ["task-filter-progress-value", "task-filter-progress-to"]

      assert attribute(html, "#task-filter-progress input", "type") == ["number", "number"]

      assert attribute(html, "#task-filter-progress input", "aria-label") ==
               ["Filter Progress, from", "Filter Progress, to"]

      assert attribute(html, "#task-filter-progress input", "name") ==
               ["filter[progress][from]", "filter[progress][to]"]

      assert html |> texts("#task-filter-progress span[aria-hidden]") == ["from", "to"]
      assert attribute(html, "#task-filter-progress-clear", "id") == []

      html = filter(view, "task", "due_on", o: "between")
      assert attribute(html, "#task-filter-due_on input", "type") == ["date", "date"]

      html = filter(view, "task", "completed_at", o: "between")

      assert attribute(html, "#task-filter-completed_at input", "type") ==
               ["datetime-local", "datetime-local"]

      assert attribute(html, "#task-filter-completed_at input", "step") == ["1", "1"]
    end

    test "shows the rows in the range, both of its ends among them", %{view: view} do
      html = between(view, "progress", "10", "80")
      assert titles(html) == ["Alpha", "Beta", "Delta"]
      assert attribute(html, "#task-filter-progress input", "value") == ["10", "80"]

      assert titles(filter(view, "task", "progress", o: "between", from: "11", to: "79")) ==
               ["Beta"]
    end

    test "with one end shows everything from it, or up to it", %{view: view} do
      assert titles(between(view, "progress", "50", "")) == ["Beta", "Delta", "Gamma"]

      assert titles(filter(view, "task", "progress", o: "between", from: "", to: "50")) ==
               ["Alpha", "Beta"]
    end

    test "with a first end past the last shows nothing, and marks nothing", %{view: view} do
      html = between(view, "progress", "80", "10")

      assert titles(html) == []
      assert attribute(html, "#task-filter-progress [aria-invalid]", "id") == []
      assert text(html, "#task-status") == "0 results"
    end

    test "takes a number with decimals for a decimal column", %{view: view} do
      assert titles(between(view, "estimate_hours", "2", "8.5")) == ["Alpha", "Beta"]

      assert titles(filter(view, "task", "estimate_hours", o: "between", from: "2.5", to: "8.4")) ==
               []
    end

    test "of dates has both days in it, and no row without a date", %{view: view} do
      assert titles(between(view, "due_on", "2026-03-01", "2026-03-10")) == ["Alpha", "Beta"]

      assert titles(filter(view, "task", "due_on", o: "between", from: "2026-03-02", to: "")) ==
               ["Beta", "Gamma"]
    end

    test "of datetimes has both moments in it, to the second", %{view: view} do
      assert titles(between(view, "completed_at", "2026-03-21T10:00:30", "2026-03-21T10:01:00")) ==
               ["Delta", "Gamma"]

      assert titles(
               filter(view, "task", "completed_at",
                 o: "between",
                 from: "2026-03-21T10:00:31",
                 to: "2026-03-21T10:00:59"
               )
             ) == []

      # an end picked to the minute is that minute's start
      assert titles(
               filter(view, "task", "completed_at",
                 o: "between",
                 from: "",
                 to: "2026-03-21T10:00"
               )
             ) == []
    end

    test "filters an aggregate", %{view: view, world: world} do
      [task | _] = Ash.read!(Task, as(world.admin)) |> Enum.filter(&(&1.title == "Beta"))
      comment = [organization_id: world.organization.id, author_id: world.admin.id]
      Generator.generate_many(Generator.comment([task_id: task.id] ++ comment), 2)

      assert titles(between(view, "comment_count", "1", "2")) == ["Beta"]

      assert titles(filter(view, "task", "comment_count", o: "between", from: "3", to: "")) ==
               []
    end

    test "an end that is not a value of the column is marked, and nothing of the range applies",
         %{view: view} do
      between(view, "progress", "10", "50")
      html = filter(view, "task", "progress", o: "between", from: "10", to: "1.5")

      assert titles(html) == ["Alpha", "Beta", "Delta", "Gamma"]
      assert attribute(html, "#task-filter-progress input", "value") == ["10", "1.5"]

      assert attribute(html, "#task-filter-progress [aria-invalid]", "id") == [
               "task-filter-progress-to"
             ]

      assert attribute(html, "#task-filter-progress-to", "aria-describedby") ==
               ["task-filter-progress-error"]

      assert text(html, "#task-filter-progress-error") == "Not a valid value"
      assert_patch(view, "/tasks")

      html = filter(view, "task", "progress", o: "between", from: "10", to: "50")
      assert titles(html) == ["Alpha", "Beta"]
      assert attribute(html, "#task-filter-progress [aria-invalid]", "id") == []
    end
  end

  describe "the URL" do
    test "holds several values as a list and a range by its ends", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/tasks")

      any_of(view, "status", ["done", "todo"])
      assert_patch(view, "/tasks?task[f][status][any_of][]=todo&task[f][status][any_of][]=done")

      view |> element("#task-clear-filters") |> render_click()
      between(view, "progress", "10", "50")

      assert_patch(
        view,
        "/tasks?task[f][progress][between][from]=10&task[f][progress][between][to]=50"
      )

      filter(view, "task", "progress", o: "between", from: "", to: "50")
      assert_patch(view, "/tasks?task[f][progress][between][to]=50")

      view |> element("#task-clear-filters") |> render_click()
      any_of(view, "priority", ["low"], "none_of")
      assert_patch(view, "/tasks?task[f][priority][none_of][]=low")
    end

    test "opened afresh shows the rows and fills the controls", %{conn: conn} do
      {:ok, _view, html} =
        live(
          conn,
          "/tasks?task[f][status][any_of][]=in_review&task[f][status][any_of][]=todo" <>
            "&task[f][due_on][between][to]=2026-03-10" <>
            "&task[f][progress][between][from]=5&task[f][progress][between][to]=90"
        )

      assert titles(html) == ["Alpha"]

      assert attribute(html, "#task-filter-status-operator option[selected]", "value") ==
               ["any_of"]

      # the values are text in a URL; they are ticked in the column's order
      assert ticked(html, "status") == ["todo", "in_review"]
      assert text(html, "#task-filter-status-value") == "2 selected"
      assert attribute(html, "#task-filter-due_on input", "value") == ["2026-03-10"]
      assert attribute(html, "#task-filter-due_on-to", "value") == ["2026-03-10"]
      assert attribute(html, "#task-filter-progress input", "value") == ["5", "90"]
      assert text(html, "#task-clear-filters") == "Clear filters"
    end

    test "is none of is opened afresh too", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/tasks?task[f][status][none_of][]=todo")

      assert titles(html) == ["Beta", "Delta", "Gamma"]
      assert ticked(html, "status") == ["todo"]
    end

    test "what means nothing to the table is ignored", %{conn: conn} do
      for query <- [
            # a value the column does not have, alone or beside one it has
            "task[f][status][any_of][]=closed",
            "task[f][status][any_of][]=todo&task[f][status][any_of][]=closed",
            "task[f][status][none_of][]=Todo",
            # not a list
            "task[f][status][any_of]=todo",
            "task[f][status][any_of][a]=todo",
            "task[f][status][any_of][][a]=todo",
            # ends that are no values of the type, or no ends
            "task[f][progress][between][from]=abc",
            "task[f][progress][between][from]=1&task[f][progress][between][to]=1.5",
            "task[f][progress][between]=5",
            "task[f][progress][between][]=5",
            "task[f][progress][between][from][]=5",
            "task[f][progress][between][min]=5",
            "task[f][due_on][between][from]=2026-02-31",
            # operators the column does not offer
            "task[f][title][any_of][]=Alpha",
            "task[f][title][between][from]=A",
            "task[f][progress][any_of][]=10",
            "task[f][status][between][from]=todo",
            "task[f][billable%3F][any_of][]=yes",
            # columns without a filter
            "task[f][description][any_of][]=x",
            "task[f][tags][any_of][]=x",
            "task[f][assignee][any_of][]=x",
            "task[f][headline][between][from]=a"
          ] do
        {:ok, _view, html} = live(conn, "/tasks?" <> query)

        assert titles(html) == ["Alpha", "Beta", "Delta", "Gamma"], query
        assert attribute(html, "#task-clear-filters", "id") == [], query
      end
    end

    test "a filter that means something is kept beside one that does not", %{conn: conn} do
      {:ok, _view, html} =
        live(conn, "/tasks?task[f][status][any_of][]=closed&task[f][progress][between][from]=80")

      assert titles(html) == ["Delta", "Gamma"]
    end
  end

  describe "what the row is sent is a claim" do
    setup %{conn: conn} do
      {:ok, view, _html} = live(conn, "/tasks")
      %{view: view}
    end

    test "a value the column does not have is not applied", %{view: view} do
      html = claim(view, %{"status" => %{"o" => "any_of", "in" => ["todo", "closed"]}})
      assert titles(html) == ["Alpha", "Beta", "Delta", "Gamma"]

      html = claim(view, %{"status" => %{"o" => "none_of", "in" => %{"0" => "todo"}}})
      assert titles(html) == ["Alpha", "Beta", "Delta", "Gamma"]
      refute_filtered(view)
    end

    test "an operator the column does not offer is not applied", %{view: view} do
      for form <- [
            %{"title" => %{"o" => "any_of", "in" => ["Alpha"]}},
            %{"title" => %{"o" => "between", "from" => "A", "to" => "B"}},
            %{"progress" => %{"o" => "any_of", "in" => ["10"]}},
            %{"status" => %{"o" => "between", "from" => "todo"}},
            %{"description" => %{"o" => "any_of", "in" => ["x"]}},
            %{"tags" => %{"o" => "any_of", "in" => ["x"]}},
            %{"assignee" => %{"o" => "any_of", "in" => ["x"]}},
            %{"internal_note" => %{"o" => "any_of", "in" => ["x"]}},
            %{"organization_id" => %{"o" => "between", "from" => "0"}}
          ] do
        assert titles(claim(view, form)) == ["Alpha", "Beta", "Delta", "Gamma"], inspect(form)
      end

      refute_filtered(view)
    end
  end

  describe "where there is no filter" do
    test "the columns without one have none of these either", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/tasks")

      for field <- ~w(description headline tags checks recurrence project assignee reporter) do
        assert filter_controls(html, "task", field) == %{operators: nil, input: nil, choices: nil},
               field
      end

      # text and a boolean keep what they had
      assert filter_controls(html, "task", "title").operators ==
               ["contains", "equals", "starts with"]

      assert filter_controls(html, "task", "billable?").operators == nil
    end

    test "a sensitive column has none, and what names it is not applied", %{conn: conn} do
      on_exit(fn -> Demo.Support.Ets.stop(Demo.Support.Secrets.Safe) end)
      Ash.Seed.seed!(Demo.Support.Secrets.Safe, %{name: "main", pin: 48_151_623})
      conn = Phoenix.ConnTest.init_test_session(conn, %{"assigns" => %{reader: %{role: :admin}}})

      {:ok, view, html} =
        live(conn, "/support/safes?safe[f][pin][between][from]=50000000")

      assert column(html, "safe", "name") == ["main"]
      assert attribute(html, "#safe-filter-pin :is(input, select, button)", "id") == []

      html = claim(view, "safe", %{"pin" => %{"o" => "between", "from" => "50000000"}})
      assert column(html, "safe", "name") == ["main"]
    end
  end

  describe "who is reading" do
    test "a column the reader never sees has no filter, and what names it is not applied",
         %{conn: conn, world: world} do
      conn = log_in(conn, world.member)

      {:ok, view, html} = live(conn, "/tasks?task[f][external_ref][any_of][]=x")
      assert titles(html) == ["Alpha", "Beta", "Delta", "Gamma"]
      assert attribute(html, "#task-filter-external_ref", "id") == []

      html = claim(view, %{"external_ref" => %{"o" => "between", "from" => "a"}})
      assert titles(html) == ["Alpha", "Beta", "Delta", "Gamma"]
    end

    test "a range finds only the rows whose value the reader sees, and counts no others",
         %{conn: conn, world: world} do
      tasks(world, [
        [title: "Mine", assignee_id: world.member.id, estimate_hours: Decimal.new("8")]
      ])

      {:ok, view, _html} = conn |> log_in(world.member) |> live("/tasks")

      # Beta has 8.5 hours and Delta 20, which this reader is not shown
      html = between(view, "estimate_hours", "1", "30")
      assert titles(html) == ["Mine"]
      assert text(html, "#task-range") == "1–1 of 1"

      html = filter(view, "task", "estimate_hours", o: "between", from: "20", to: "20")
      assert titles(html) == []
      assert text(html, "#task-status") == "0 results"
    end

    test "nobody finds nothing, whatever the filter", %{conn: conn, world: world} do
      {:ok, _view, html} =
        conn |> log_in(world.nobody) |> live("/tasks?task[f][status][none_of][]=archived")

      assert titles(html) == []
    end

    test "a filter never shows the tasks of another organization", %{conn: conn, world: world} do
      {:ok, _view, html} =
        conn |> log_in(world.outsider) |> live("/tasks?task[f][status][none_of][]=archived")

      assert titles(html) == []
    end
  end

  describe "what others change" do
    test "is spoken of only when it matches these filters", %{conn: conn, world: world} do
      {:ok, view, _html} = conn |> log_in(world.member) |> live("/tasks")
      any_of(view, "status", ["done", "in_review"])
      between(view, "progress", "90", "")

      [project | _] = world.projects

      create = fn title, more ->
        Ash.create!(
          Task,
          Map.merge(%{title: title, project_id: project.id}, more),
          as(world.admin)
        )
      end

      heard = fn ->
        AshDataTable.Test.flush(view)
        text(render_async(view, 10_000), "#task-notice > span") || ""
      end

      # of another state, and of one of these but out of the range
      create.("Elsewhere", %{status: :todo, progress: 95})
      create.("Too little", %{status: :in_review, progress: 20})
      assert heard.() == ""

      create.("Just right", %{status: :in_review, progress: 95})
      assert heard.() == "There are new or changed records."
    end
  end

  describe "the type zoo" do
    setup %{conn: conn} do
      Generator.reseed(1)

      for {label, decimal, moment, usec, naive, shade, atom} <- [
            {"One", "1.25", ~U[2026-03-09 14:30:05Z], ~U[2026-03-09 14:30:05.000000Z],
             ~N[2026-03-09 14:30:05], :light, :red},
            {"Two", "2.50", ~U[2026-03-09 14:30:06Z], ~U[2026-03-09 14:30:05.500000Z],
             ~N[2026-03-09 14:30:06], :medium, :green},
            {"Three", "3.75", ~U[2026-03-09 14:30:07Z], ~U[2026-03-09 14:30:07.000000Z],
             ~N[2026-03-09 14:30:07], :dark, :red}
          ] do
        Generator.generate(
          Generator.specimen(
            label: label,
            a_decimal: Decimal.new(decimal),
            a_utc_datetime: moment,
            a_utc_datetime_usec: usec,
            a_naive_datetime: naive,
            a_shade: shade,
            an_atom: atom
          )
        )
      end

      {:ok, view, _html} = live(conn, "/specimens")
      %{view: view}
    end

    defp labels(html), do: html |> column("specimen", "label") |> Enum.sort()

    test "a decimal range has both ends in it", %{view: view} do
      assert labels(between(view, "specimen", "a_decimal", "1.25", "2.5")) == ["One", "Two"]

      assert_patch(
        view,
        "/specimens?specimen[f][a_decimal][between][from]=1.25&specimen[f][a_decimal][between][to]=2.5"
      )

      assert labels(filter(view, "specimen", "a_decimal", o: "between", from: "1.26", to: "2.49")) ==
               []
    end

    test "a datetime range has both ends in it, with and without microseconds", %{view: view} do
      assert labels(
               between(
                 view,
                 "specimen",
                 "a_utc_datetime",
                 "2026-03-09T14:30:05",
                 "2026-03-09T14:30:06"
               )
             ) == ["One", "Two"]

      view |> element("#specimen-clear-filters") |> render_click()

      # half a second past :05 is after the end that says :05
      assert labels(
               between(
                 view,
                 "specimen",
                 "a_utc_datetime_usec",
                 "2026-03-09T14:30:05",
                 "2026-03-09T14:30:05"
               )
             ) == ["One"]

      view |> element("#specimen-clear-filters") |> render_click()

      assert labels(between(view, "specimen", "a_naive_datetime", "2026-03-09T14:30:06", "")) ==
               ["Three", "Two"]
    end

    test "an Ash.Type.Enum and an atom limited to values take several values", %{view: view} do
      filter(view, "specimen", "a_shade", o: "any_of")

      assert labels(filter(view, "specimen", "a_shade", o: "any_of", in: ["light", "dark"])) ==
               ["One", "Three"]

      view |> element("#specimen-clear-filters") |> render_click()
      filter(view, "specimen", "an_atom", o: "none_of")

      assert labels(filter(view, "specimen", "an_atom", o: "none_of", in: ["red"])) == ["Two"]
      assert_patch(view, "/specimens?specimen[f][an_atom][none_of][]=red")
    end
  end
end
