defmodule DemoWeb.Tables.TextCounterTest do
  @moduledoc """
  The counter of a text that has a most it can be long (`max_length`): how
  long the text is now and the most it can be, "12/30", beside the control
  it is typed into. In the editor of a cell (`/labels`, `/tasks`), on a
  field of the action panel, on a field inside a map cell (`/projects`,
  "Client"), on each value of an array of text, and on the argument line
  (`/tasks`, "Search"; `/support/stocks`).

  What is here is what the server renders: the counter as it counts what a
  control holds, in Elixir, as Ash counts. That it follows what is typed
  without the server is the hook's, and in `e2e/counter.spec.ts`. The
  counter describes: nothing here is refused by it, and what Ash says of a
  text that is too long is shown as before.
  """
  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator
  alias Demo.Tracker.Client

  defp query(html, selector), do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector)

  # What is in the `<template>` of a column's editor, which is not part of
  # the document: read on its own. For an array, the row of one value.
  defp editor_content(html, id, field) do
    [{"template", _attributes, children}] =
      html |> query("template[id='#{id}-editor-#{field}']") |> LazyHTML.to_tree()

    content = LazyHTML.from_tree(children)

    case content |> LazyHTML.query("[data-list] > template") |> LazyHTML.to_tree() do
      [{"template", _attributes, row}] -> LazyHTML.from_tree(row)
      [] -> content
    end
  end

  # A counter as it says itself: its text, and what the hook counts by.
  defp counter(found) do
    case LazyHTML.to_tree(found) do
      [] ->
        nil

      [{"span", attributes, _children}] ->
        attributes = Map.new(attributes)

        %{
          text: found |> LazyHTML.text() |> String.trim(),
          id: attributes["id"],
          unit: attributes["data-count"],
          max: attributes["data-max"],
          trim?: is_map_key(attributes, "data-trim"),
          casing: attributes["data-casing"],
          over?: is_map_key(attributes, "data-over"),
          live: attributes["aria-live"],
          role: attributes["role"]
        }
    end
  end

  defp counter(html, selector), do: html |> query(selector) |> counter()
  defp counters(html, selector), do: html |> query(selector) |> Enum.map(&counter/1)

  describe "the editor of a cell" do
    setup %{conn: conn} do
      world = world(tasks: 1, labels: 2)
      conn = log_in(conn, world.admin)
      {:ok, _view, labels} = live(conn, "/labels")
      {:ok, _view, tasks} = live(conn, "/tasks")
      %{labels: labels, tasks: tasks}
    end

    test "of a text with a most has its counter beside the text, which names it as its description",
         %{labels: html} do
      content = editor_content(html, "label", "name")

      assert counter(LazyHTML.query(content, "[data-count]")) == %{
               text: "0/30",
               id: "label-editor-name-count",
               unit: "codepoints",
               max: "30",
               trim?: true,
               casing: nil,
               over?: false,
               # read with the control, and not at every key
               live: nil,
               role: nil
             }

      textarea = LazyHTML.query(content, "textarea")
      assert LazyHTML.attribute(textarea, "aria-describedby") == ["label-editor-name-count"]
      assert LazyHTML.attribute(textarea, "aria-label") == ["Name"]
      # the control of the editor, which is the two of them
      assert LazyHTML.attribute(textarea, "data-control") == [""]
      # and still nothing that would stop the typing
      assert LazyHTML.attribute(textarea, "maxlength") == []
      # one editor, one control: nothing else is typed into
      assert Enum.count(LazyHTML.query(content, "textarea,input,select")) == 1
    end

    test "of a text without a most has none, and is the textarea alone", %{labels: html} do
      content = editor_content(html, "label", "colour")

      assert Enum.count(LazyHTML.query(content, "[data-count]")) == 0
      assert LazyHTML.attribute(LazyHTML.query(content, "textarea"), "aria-describedby") == []
      assert [{"textarea", _attributes, _children}] = LazyHTML.to_tree(content)
    end

    test "of an array of text has one in the row of each value, which the hook names by the row's place",
         %{tasks: html} do
      row = editor_content(html, "task", "tags")

      assert %{text: "0/20", max: "20", unit: "codepoints", id: nil} =
               counter(LazyHTML.query(row, "[data-count]"))

      # the list has the id its rows' counters are named by
      assert attribute(html, "template[id='task-editor-tags']", "id") == ["task-editor-tags"]
    end

    test "of anything that is no text with a most has none", %{tasks: html} do
      for field <- ~w(status due_on estimate_hours checks billable?) do
        assert Enum.count(LazyHTML.query(editor_content(html, "task", field), "[data-count]")) ==
                 0,
               field
      end
    end
  end

  describe "a field of the action panel" do
    setup %{conn: conn} do
      world = world(tasks: 0, other_tasks: 0, projects: 1)

      task =
        Generator.generate(
          Generator.task(
            organization_id: world.organization.id,
            project_id: hd(world.projects).id,
            reporter_id: world.member.id,
            title: "Send the invoices",
            external_ref: "REF-1",
            tags: ["api", "mobile"]
          )
        )

      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")
      %{view: view, task: task, world: world}
    end

    test "counts what it starts with, and names its counter as its description", %{
      view: view,
      task: task
    } do
      html = act(view, task.id, "reassign")

      assert %{text: "0/200", id: "task-panel-f-reason-count", max: "200", over?: false} =
               counter(html, "#task-panel-f-reason-count")

      assert attribute(html, "#task-panel-f-reason", "aria-describedby") ==
               ["task-panel-f-reason-count"]

      assert attribute(html, "#task-panel-f-reason", "maxlength") == []
      # the one counter of the panel: the other field is a choice of a record
      assert length(counters(html, "#task-panel [data-count]")) == 1
    end

    test "counts what is typed as Ash does: trimmed, and in codepoints", %{view: view, task: task} do
      act(view, task.id, "reassign")

      for {typed, count} <- [
            {"No", 2},
            {"  padded  ", 6},
            {"   ", 0},
            {"two\nlines", 9},
            # one family, five codepoints
            {"👨‍👩‍👧", 5},
            {"é", 1}
          ] do
        html = type_in_panel(view, reason: typed)

        assert %{text: text, over?: false} = counter(html, "#task-panel-f-reason-count")
        assert text == "#{count}/200", inspect(typed)
      end
    end

    test "past the most it says so with its number and its mark, and Ash refuses the text", %{
      view: view,
      task: task
    } do
      act(view, task.id, "reassign")
      long = String.duplicate("a", 201)

      html = type_in_panel(view, reason: long)
      assert %{text: "201/200", over?: true} = counter(html, "#task-panel-f-reason-count")

      # the form is not held back: the action is run, and says so itself
      html = run_panel(view, reason: long)

      assert [_assignee, %{name: "reason", errors: ["length must be less than or equal to 200"]}] =
               panel(html).fields

      assert attribute(html, "#task-panel-f-reason", "aria-describedby") ==
               ["task-panel-f-reason-error task-panel-f-reason-count"]

      # exactly the most is not past it
      html = type_in_panel(view, reason: String.duplicate("a", 200))
      assert %{text: "200/200", over?: false} = counter(html, "#task-panel-f-reason-count")
    end

    test "a field of the create panel starts at nothing, and each value of an array of text has its own",
         %{view: view} do
      html = open_create(view)

      assert %{text: "0/120"} = counter(html, "#task-panel-f-title-count")
      assert %{text: "0/40"} = counter(html, "#task-panel-f-external_ref-count")
      # a text without a most has none
      assert counter(html, "#task-panel-f-description-count") == nil

      # an array of text: the row of a value that is added comes from the
      # template, with a counter the hook names
      [{"template", _attributes, row}] =
        html |> query("#task-panel-f-tags-values > template") |> LazyHTML.to_tree()

      assert [%{text: "0/20", id: nil}] =
               row
               |> LazyHTML.from_tree()
               |> LazyHTML.query("[data-count]")
               |> Enum.map(&counter/1)
    end
  end

  describe "a field of an array of text" do
    test "has a counter for each value it starts with, named by the value's place", %{conn: conn} do
      on_exit(fn -> Demo.Support.Ets.stop(Demo.Support.Lists.Roster) end)

      roster =
        Ash.Seed.seed!(Demo.Support.Lists.Roster, %{name: "Night shift", words: ["alpha", "beta"]})

      conn =
        Phoenix.ConnTest.init_test_session(conn, %{
          "assigns" => %{current_user: %{id: "ada", name: "ada", role: :admin}}
        })

      {:ok, view, _html} = live(conn, "/support/rosters")
      html = act(view, "roster", roster.id, "revise")

      assert [
               %{text: "5/12", id: "roster-panel-f-words-values-count-1"},
               %{text: "4/12", id: "roster-panel-f-words-values-count-2"}
             ] = counters(html, "#roster-panel-f-words-values > [data-item] [data-count]")

      assert attribute(
               html,
               "#roster-panel-f-words-values > [data-item] textarea",
               "aria-describedby"
             ) == ["roster-panel-f-words-values-count-1", "roster-panel-f-words-values-count-2"]
    end
  end

  describe "a field inside a map cell" do
    setup %{conn: conn} do
      world = world(tasks: 0, other_tasks: 0, projects: 0)

      project =
        Generator.generate(
          Generator.project(
            organization_id: world.organization.id,
            name: "Website",
            client: %Client{name: "Nordwind GmbH", email: "office@nordwind.test"},
            milestones: [%Demo.Tracker.Milestone{title: "Kick-off"}]
          )
        )

      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/projects")
      %{view: view, project: project}
    end

    test "counts what the value holds, by the constraints of the field", %{
      view: view,
      project: project
    } do
      html = edit(view, "project", project.id, "client")

      assert %{text: "13/60", id: "project-panel-f-client-f-name-count"} =
               counter(html, "#project-panel-f-client-f-name-count")

      assert attribute(html, "#project-panel-f-client-f-name", "aria-describedby") ==
               ["project-panel-f-client-f-name-count"]

      # a field of it without a most has none
      assert counter(html, "#project-panel-f-client-f-email-count") == nil
    end

    test "so does a field of a value of an array of them", %{view: view, project: project} do
      html = edit(view, "project", project.id, "milestones")

      assert [%{text: "8/60"}] = counters(html, "#project-panel [data-count]")
    end
  end

  describe "the argument line" do
    test "counts a text argument beside its input, as its folded and trimmed text is long", %{
      conn: conn
    } do
      world = world(tasks: 1)
      {:ok, view, html} = conn |> log_in(world.admin) |> live("/tasks")

      assert %{text: "0/60", id: "task-arg-search-count", max: "60", trim?: true} =
               counter(html, "#task-arg-search-count")

      assert attribute(html, "#task-arg-search", "aria-describedby") == ["task-arg-search-count"]
      assert attribute(html, "#task-arg-search", "maxlength") == []
      # a number of the line has none
      assert length(counters(html, "#task-arguments [data-count]")) == 1

      html = argue(view, "task", a: %{"search" => "  report "})
      assert %{text: "6/60"} = counter(html, "#task-arg-search-count")

      # it is the argument's from the URL as well
      {:ok, _view, html} = conn |> log_in(world.admin) |> live("/tasks?task[a][search]=invoice")
      assert %{text: "7/60"} = counter(html, "#task-arg-search-count")
    end

    test "past the most it says so, and Ash refuses the argument at its input", %{conn: conn} do
      world = world(tasks: 1)
      {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")

      html = argue(view, "task", a: %{"search" => String.duplicate("x", 61)})

      assert %{text: "61/60", over?: true} = counter(html, "#task-arg-search-count")

      assert [%{errors: ["length must be less than or equal to 60"]} | _] =
               arguments(html, "task")

      assert attribute(html, "#task-arg-search", "aria-describedby") ==
               ["task-arg-search-error task-arg-search-count"]
    end

    test "counts each value of an array of text in its own row", %{conn: conn} do
      on_exit(fn -> Demo.Support.Ets.stop(Demo.Support.Asked.Stock) end)

      conn =
        Phoenix.ConnTest.init_test_session(conn, %{"assigns" => %{reader: %{role: :admin}}})

      {:ok, view, html} = live(conn, "/support/stocks?stock[a][at_least]=0")
      assert counters(html, "#stock-arguments [data-count]") == []

      view |> element("#stock-arg-names-add") |> render_click()
      html = argue(view, "stock", a: %{"names" => ["", "bolt"]})

      assert [%{text: "4/12", id: "stock-arg-names-0-count"}] =
               counters(html, "#stock-arguments [data-count]")

      assert attribute(html, "#stock-arg-names-0", "aria-describedby") ==
               ["stock-arg-names-0-count"]
    end
  end

  describe "what has no counter" do
    test "is a sensitive text: nothing is said of what is typed hidden", %{conn: conn} do
      on_exit(fn -> Demo.Support.Ets.stop(Demo.Support.Secrets.Safe) end)
      safe = Ash.Seed.seed!(Demo.Support.Secrets.Safe, %{name: "main", token: "tok"})

      conn =
        Phoenix.ConnTest.init_test_session(conn, %{"assigns" => %{reader: %{role: :admin}}})

      {:ok, view, html} = live(conn, "/support/safes")
      assert Enum.count(LazyHTML.query(editor_content(html, "safe", "seal"), "[data-count]")) == 0

      html = act(view, "safe", safe.id, "reissue")
      assert attribute(html, "#safe-panel-f-seal", "type") == ["password"]
      assert counters(html, "#safe-panel [data-count]") == []
      assert attribute(html, "#safe-panel-f-seal", "aria-describedby") == []

      # a plain text of the same kind of panel has its own
      cancel_panel(view, "safe")
      html = act(view, "safe", safe.id, "rotate")
      assert %{text: "0/50"} = counter(html, "#safe-panel-f-note-count")
    end
  end
end
