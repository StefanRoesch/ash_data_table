defmodule DemoWeb.ReactKitTest do
  @moduledoc """
  What the React kit's server side gives its islands (`DemoWeb.ReactKit`,
  `DemoWeb.ReactKit.Props`) goes to JSON (the React kit's note, 13 f): on
  /react/tasks at rest, with a nested table open, sorted, filtered, with a
  row selected, with "No records" in place of the rows and limited to the
  records of one project, every island of the page is read with
  `LiveReact.Test.get_react/2` (by the id the kit gives it), and its props
  are a JSON object of exactly the props the kit gives it, with what that
  state holds. The grid's rows are its stream, which live_react sends
  beside the props: the items, whose JSON `test/item_test.exs` of the
  library checks.

  live_react sends an island's props in full in the test environment
  (`config :live_react, enable_props_diff: false`, config/test.exs, as
  `LiveReact.Test` advises), so that what it reads is all of them in every
  state, not a patch of them; the patches are what the browser suite's
  `react` project runs on.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage, only: [nested: 3]

  alias LiveReact.Test, as: React

  # the islands of a table and their props, by the suffix of their ids
  @props %{
    "heading" => {"AshHeading", {:heading, ~w(table)}},
    "grid" =>
      {"AshGrid",
       ~w(texts skip scrollbar grid table head filters columns row footer editors failure)},
    "selection" => {"AshSelectionLine", {:selection_line, ~w(table)}},
    "status" => {"AshStatus", :status},
    "pagination" => {"AshPagination", :pagination}
  }

  setup %{conn: conn} do
    world = world(tasks: 30)
    %{conn: log_in(conn, world.admin), world: world}
  end

  test "every island's props go to JSON, in every state", %{conn: conn, world: world} do
    {:ok, view, html} = live(conn, "/react/tasks")

    top = islands!(html, "task", Map.keys(@props))

    assert %{"grid" => %{"data-table" => "task"}, "columns" => [_ | _]} = top["grid"]
    assert %{"id" => "task-skip", "href" => "#task-end"} = top["grid"]["skip"]

    assert %{"id" => "task-scrollbar", "hidden" => "", "data-scrollbar" => ""} =
             top["grid"]["scrollbar"]

    refute Map.has_key?(top["grid"]["scrollbar"], "phx-update")

    # the editors, which the island draws into their templates: what the
    # `editor` part is given of a control, a component's by its module, and
    # a template without an editor where the picker edits the cell
    editors = Map.new(top["grid"]["editors"], &{&1["name"], &1})

    assert %{
             "template" => %{"id" => "task-editor-title", "data-editor" => "text"},
             "editor" => "text",
             "counted" => %{"max" => 120},
             "control" => %{"aria-describedby" => "task-editor-title-count"}
           } = editors["title"]

    assert %{
             "editor" => "component",
             "component" => "DemoWeb.Cells.Progress",
             "limits" => %{"min" => "0", "max" => "100", "step" => "1"}
           } = editors["progress"]

    assert %{"editor" => nil, "template" => %{"data-editor" => "reference"}} =
             editors["assignee"]

    # the heading line: "Columns", and the argument line with what the
    # table gives each argument's input
    assert %{
             "element" => %{"id" => "task-header"},
             "shown?" => true,
             "columns" => %{"control" => %{"id" => "task-columns-control"}},
             "argument_line" => %{"form" => %{"id" => "task-arguments"}, "arguments" => inputs}
           } = top["heading"]

    assert %{
             "id" => "task-arg-search",
             "name" => "arguments[a][search]",
             "value" => "",
             "counted" => %{"max" => 60, "unit" => _},
             "count" => %{"element" => %{"data-max" => "60"}}
           } = Enum.find(inputs, &(&1["named"] == "search"))

    task = hd(world.tasks)

    # sent from the grid's sender, which the React kit draws as markup of
    # the LiveView's (its grid is the browser's)
    send = fn event, payload ->
      AshDataTable.Test.send_event(view, "task", event, payload, from: :sender)
      render_async(view, 10_000)
    end

    # a row expanded, its comments open: the nested table's islands are
    # drawn by the table on the page in a portal (which LiveViewTest renders
    # as a template: its target is an island's); its pages are in its grid
    send.("expand", %{"row" => task.id})
    html = send.("toggle", %{"row" => task.id, "relationship" => "comments"})
    comments = nested("task", task.id, "comments")
    inner = islands!(html, comments, ~w(heading grid selection status))
    assert %{"grid" => %{"data-table" => ^comments}} = inner["grid"]
    assert %{"nested?" => true} = inner["heading"]
    islands!(html, "task", Map.keys(@props))

    # sorted
    html = send.("sort", %{"column" => "title"})
    sorted = islands!(html, "task", Map.keys(@props))

    assert %{"mark" => " ▲"} =
             Enum.find(sorted["grid"]["head"]["columns"], &(&1["name"] == "title"))

    # filtered, then no longer
    html = send.("filter", %{"filter" => %{"title" => %{"o" => "contains", "v" => "a"}}})
    filtered = islands!(html, "task", Map.keys(@props))
    assert %{"clear_filters" => %{"id" => _}} = filtered["selection"]

    html = send.("filter", %{"filter" => %{}})

    assert %{"clear_filters" => nil} = islands!(html, "task", Map.keys(@props))["selection"]

    # a row selected
    html = send.("select", %{"rows" => [[task.id, nil]], "all" => false})
    selected = islands!(html, "task", Map.keys(@props))
    assert %{"selection" => %{"selected" => %{"id" => _}}} = selected["selection"]

    # a filter that matches nothing: "No records" in place of the rows, an
    # island of its own
    html =
      send.("filter", %{"filter" => %{"title" => %{"o" => "contains", "v" => "no such task"}}})

    assert %{
             "element" => %{"id" => "task-empty"},
             "kind" => "empty",
             "text" => "No records"
           } = island!(html, "task-empty-island", "AshMessage", :message)
  end

  test "a table limited to the records of one record says so in an island", %{
    conn: conn,
    world: world
  } do
    project = hd(world.projects)

    {:ok, _view, html} = live(conn, "/react/tasks?task[of][project][tasks]=#{project.id}")

    assert %{
             "element" => %{"id" => "task-related"},
             "heading" => %{"id" => "task-related-heading"},
             "record" => %{
               "id" => "task-related-parent",
               "title" => title,
               "path" => "/projects"
             },
             "create" => %{"button" => %{"id" => "task-create"}},
             "clear" => %{"id" => "task-related-clear", "path" => "/react/tasks"}
           } = island!(html, "task-related-island", "AshRelated", :related)

    assert title == project.name
  end

  test "the question, the panel and the picker go to JSON, closed and open", %{
    conn: conn,
    world: world
  } do
    {:ok, view, html} = live(conn, "/react/tasks")
    task = hd(world.tasks)

    # drawn closed, with their places, before anything opens
    assert %{
             "question" => %{"id" => "task-dialog-question"},
             "dialog" => %{"id" => "task-dialog"}
           } = island!(html, "task-dialogs", "AshConfirm", :confirm)

    assert %{
             "open?" => false,
             "place" => %{"id" => "task-panel-place"},
             "fields" => [],
             "frame" => nil
           } = island!(html, "task-panel-island", "AshPanel", :panel)

    assert %{"open?" => false, "place" => %{"id" => "task-picker-place"}, "frame" => nil} =
             island!(html, "task-picker-island", "AshPicker", :picker)

    send = fn event, payload ->
      AshDataTable.Test.send_event(view, "task", event, payload, from: :sender)
      render_async(view, 10_000)
    end

    # the create panel: its form, and a field of each kind it has
    html = send.("create", %{})
    panel = island!(html, "task-panel-island", "AshPanel", :panel)

    assert %{
             "open?" => true,
             "frame" => %{"id" => "task-panel", "data-table" => "task", "role" => "dialog"},
             "form" => %{
               "id" => "task-panel-form",
               "phx-submit" => "ash_data_table:task:panel_submit"
             }
           } = panel

    refute Map.has_key?(panel["frame"], "phx-hook")
    refute Map.has_key?(panel["frame"], "phx-mounted")
    fields = Map.new(panel["fields"], &{&1["element"]["data-field"], &1})

    assert %{"id" => "task-panel-f-title", "editor" => "text", "counted" => %{"max" => 120}} =
             fields["title"]

    assert %{
             "editor" => "reference",
             "reference" => %{"choose" => %{"phx-value-input" => "assignee_id"}}
           } = fields["assignee_id"]

    # the picker of a reference cell, its place for its table
    send.("panel_cancel", %{})
    html = send.("pick", %{"row" => task.id, "column" => "assignee"})

    assert %{
             "open?" => true,
             "frame" => %{"id" => "task-picker", "data-table" => "task"},
             "take" => %{"id" => "task-picker-choose", "data-take" => ""}
           } = island!(html, "task-picker-island", "AshPicker", :picker)
  end

  # The islands `suffixes` of the table `id` in the page, each a JSON
  # object of exactly its props, by suffix.
  defp islands!(html, id, suffixes) do
    Map.new(suffixes, fn suffix ->
      {name, props} = Map.fetch!(@props, suffix)
      {suffix, island!(html, "#{id}-#{suffix}-island", name, props)}
    end)
  end

  # a part given its projection: a prop per key of it, and `more`
  defp island!(html, id, name, part) when is_atom(part), do: island!(html, id, name, {part, []})

  defp island!(html, id, name, {part, more}) when is_atom(part),
    do:
      island!(
        html,
        id,
        name,
        Enum.map(AshDataTable.Kit.Projection.keys(part), &to_string/1) ++ more
      )

  defp island!(html, id, name, props) do
    react = React.get_react(html, id: id)
    assert react.component == name, id
    assert is_map(react.props), id

    assert react.props |> Map.keys() |> Enum.sort() == Enum.sort(props),
           "#{id}: #{inspect(Map.keys(react.props))}"

    react.props
  end
end
