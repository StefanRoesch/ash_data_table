defmodule DemoWeb.ReactKitTest do
  @moduledoc """
  What the React kit's server side gives its islands (`DemoWeb.ReactKit`,
  `DemoWeb.ReactKit.Props`) goes to JSON (the React kit's note, 13 f): on
  /react/tasks, at rest, sorted, filtered, with a row selected and with a
  nested table open, every island's props (`data-props`, as live_react
  writes them: JSON whose quotes are `^`, `LiveReact.Patch.encode_object/1`)
  are JSON objects, and so is every value of their patches.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage, only: [nested: 3]

  @islands ~w(AshHeading AshGrid AshSelectionLine AshStatus AshPagination)

  setup %{conn: conn} do
    world = world(tasks: 30)
    %{conn: log_in(conn, world.admin), world: world}
  end

  test "every island's props go to JSON, and their patches too", %{conn: conn, world: world} do
    {:ok, view, html} = live(conn, "/react/tasks")

    islands = islands(html)
    assert islands |> Enum.map(& &1.name) |> Enum.uniq() |> Enum.sort() == Enum.sort(@islands)

    for island <- islands do
      assert is_map(island.props), "#{island.name} #{island.id}"
    end

    grid = Enum.find(islands, &(&1.name == "AshGrid"))
    assert %{"grid" => %{"data-table" => "task"}, "columns" => [_ | _]} = grid.props

    # the editors, which the island draws into their templates: what the
    # `editor` part is given of a control, a component's by its module, and
    # a template without an editor where the picker edits the cell
    editors = Map.new(grid.props["editors"], &{&1["name"], &1})

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
    heading = Enum.find(islands, &(&1.name == "AshHeading"))

    assert %{
             "heading" => %{"id" => "task-header", "shown" => true},
             "columns" => %{"id" => "task"},
             "arguments" => %{"form" => %{"id" => "task-arguments"}, "inputs" => inputs}
           } = heading.props

    assert %{
             "id" => "task-arg-search",
             "name" => "arguments[a][search]",
             "value" => "",
             "counted" => %{"max" => 60, "unit" => _},
             "count" => %{"data-max" => "60"}
           } = Enum.find(inputs, &(&1["named"] == "search"))

    task = hd(world.tasks)

    # sent from the grid's sender, which the React kit draws as markup of
    # the LiveView's (its grid is the browser's)
    send = &AshDataTable.Test.send_event(view, "task", &1, &2, from: :sender)

    # a row expanded, its comments open: the nested table's islands are
    # drawn by the table on the page in a portal (which LiveViewTest renders
    # as a template: its target is an island's)
    send.("expand", %{"row" => task.id})
    send.("toggle", %{"row" => task.id, "relationship" => "comments"})
    html = render_async(view, 10_000)
    assert html =~ ~s(id="#{nested("task", task.id, "comments")}-grid-island")
    props!(html)

    for page <- [
          send.("sort", %{"column" => "title"}),
          send.("filter", %{"filter" => %{"title" => %{"o" => "contains", "v" => "a"}}}),
          send.("filter", %{"filter" => %{}}),
          send.("select", %{"rows" => [[task.id, nil]], "all" => false})
        ],
        do: props!(page)

    # a filter that matches nothing: "No records", an island of its own
    send.("filter", %{"filter" => %{"title" => %{"o" => "contains", "v" => "no such task"}}})

    assert [%{props: %{"message" => message}}] =
             view |> render_async(10_000) |> islands() |> Enum.filter(&(&1.name == "AshMessage"))

    assert %{"id" => "task-empty", "kind" => "empty", "alert" => false, "text" => "No records"} =
             message
  end

  test "a table limited to the records of one record says so in an island", %{
    conn: conn,
    world: world
  } do
    project = hd(world.projects)

    {:ok, _view, html} = live(conn, "/react/tasks?task[of][project][tasks]=#{project.id}")

    assert [%{props: %{"related" => related}}] =
             html |> islands() |> Enum.filter(&(&1.name == "AshRelated"))

    assert %{
             "id" => "task-related",
             "heading" => %{
               "id" => "task-related-heading",
               "record" => %{
                 "id" => "task-related-parent",
                 "title" => title,
                 "path" => "/projects"
               }
             },
             "create" => %{"attrs" => %{"id" => "task-create"}},
             "clear" => %{"id" => "task-related-clear", "path" => "/react/tasks"}
           } = related

    assert title == project.name
  end

  # Every island's props in the page, its portals too, are JSON objects.
  defp props!(html) do
    for [props] <- Regex.scan(~r/data-props="([^"]*)"/, html, capture: :all_but_first) do
      assert is_map(json!(unescape(props)))
    end
  end

  defp unescape(text),
    do:
      text
      |> String.replace("&amp;", "&")
      |> String.replace("&lt;", "<")
      |> String.replace("&gt;", ">")
      |> String.replace("&#39;", "'")
      |> String.replace("&quot;", "\"")

  # The islands of a page: each element live_react renders, with its name,
  # its props as JSON, and the values of its patches checked on the way.
  defp islands(html) do
    html
    |> LazyHTML.from_document()
    |> LazyHTML.query("[data-name][data-props]")
    |> Enum.map(fn element ->
      [name] = LazyHTML.attribute(element, "data-name")
      [id] = LazyHTML.attribute(element, "id")
      [props] = LazyHTML.attribute(element, "data-props")
      %{name: name, id: id, props: json!(props)}
    end)
  end

  # live_react's encoding of an object (`LiveReact.Patch.encode_object/1`):
  # JSON with `"` as `^`, and `~` and `^` as `~~` and `~^`.
  defp json!(text) do
    text
    |> String.replace(~r/~~|~\^|\^/, fn
      "~~" -> "~"
      "~^" -> "^"
      "^" -> "\""
    end)
    |> Jason.decode!()
  end
end
