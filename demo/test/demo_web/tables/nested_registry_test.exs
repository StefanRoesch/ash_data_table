defmodule DemoWeb.Tables.NestedRegistryTest do
  @moduledoc """
  What the one component of a page holds while nested tables are open, as
  real events and reads go through it (stage 5): after each, every nested
  table is drawn into a line that its parent's row holds on the page, and
  the table on the page is the one `table.entry` names.

  A portal whose cell is gone makes the browser throw; the browser suite
  catches that as a console error. Here it is checked after every step of
  one walk through the page: opening, sorting, filtering, paging, live
  updates and closing.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator
  alias Demo.Tracker.Comment

  @moment ~U[2026-01-01 12:00:00.000000Z]

  defp task(world, title, minute) do
    [project | _] = world.projects

    Generator.generate(
      Generator.task(
        organization_id: world.organization.id,
        project_id: project.id,
        reporter_id: world.admin.id,
        title: title,
        inserted_at: DateTime.add(@moment, minute, :minute)
      )
    )
  end

  defp comment(world, task, body, minute) do
    Generator.generate(
      Generator.comment(
        organization_id: world.organization.id,
        task_id: task.id,
        author_id: world.admin.id,
        body: body,
        inserted_at: DateTime.add(@moment, minute, :minute)
      )
    )
  end

  # The `AshDataTable.Table` the page holds between two callbacks
  # (`Phoenix.LiveView.Debug`): it is attached to the page, under `table`.
  defp table(view) do
    {:ok, %{assigns: %{table: %AshDataTable.Table{} = table}}} =
      Phoenix.LiveView.Debug.socket(view.pid)

    table
  end

  # By the id of each element on the page as a person sees it, the table
  # it is drawn in: the nearest root of a table (`.ash-data-table`) around it.
  defp drawn_in(html) do
    html |> AshDataTable.Test.page() |> LazyHTML.to_tree() |> drawn_in(nil, %{})
  end

  defp drawn_in(nodes, around, found) when is_list(nodes),
    do: Enum.reduce(nodes, found, &drawn_in(&1, around, &2))

  defp drawn_in({_tag, attributes, children}, around, found) do
    id = :proplists.get_value("id", attributes, nil)
    class = :proplists.get_value("class", attributes, "")
    found = if id, do: Map.put(found, id, around), else: found
    root? = id && "ash-data-table" in String.split(class)
    drawn_in(children, if(root?, do: id, else: around), found)
  end

  defp drawn_in(_text, _around, found), do: found

  # The two promises of the registry, after a callback: the table on the
  # page is `table.entry`, and each nested table's cell is a line of a row
  # of the table it is in, on the page now; the table of a picker belongs
  # to a table whose picker is open.
  defp holds!(view) do
    html = render(view)
    %{entry: top, entries: entries} = table(view)
    assert top.id == "task"

    where = drawn_in(html)

    for {id, entry} <- entries do
      assert List.last(entry.path) == id
      parent = Enum.at(entry.path, -2)
      assert parent == "task" or Map.has_key?(entries, parent)

      if entry.target do
        assert Map.fetch(where, entry.target) == {:ok, parent},
               "the cell of #{id}, #{entry.target}, is not a line of #{parent} on the page"

        assert Map.fetch(where, id) == {:ok, parent}
      else
        holder = if parent == "task", do: top, else: entries[parent]
        assert holder.picker, "#{id} is a picker's table, and #{parent} has no picker open"
      end
    end

    Map.keys(entries) |> Enum.sort()
  end

  defp heard(view) do
    AshDataTable.Test.flush(view)
    render_async(view, 10_000)
    left(view)
    render_async(view, 10_000)
  end

  defp left(view) do
    {ref, _topic, _proxy} = view.proxy

    receive do
      {^ref, {:push_event, "ash_data_table:leaving", %{table: table, row: row}}} ->
        forge(view, table, "left", %{"row" => row})
        left(view)
    after
      0 -> :ok
    end
  end

  test "every nested table stays drawn into a line of its parent, and the table on the page stays the entry, through every kind of callback",
       %{conn: conn} do
    world = world(tasks: 0)
    others = for minute <- 1..11, do: task(world, "Task #{minute}", minute)
    task = task(world, "With comments", 20)
    first = comment(world, task, "First comment", 1)
    second = comment(world, task, "Second comment", 2)
    {:ok, view, _html} = conn |> log_in(world.admin) |> live("/tasks")

    comments = nested(task.id, "comments")
    deep = nested(comments, first.id, "task")
    assert holds!(view) == []

    # opening, two levels down
    expand(view, task.id)
    assert holds!(view) == []
    toggle(view, task.id, "comments")
    render_async(view, 10_000)
    assert holds!(view) == [comments]
    expand(view, comments, first.id)
    toggle(view, comments, first.id, "task")
    render_async(view, 10_000)
    assert holds!(view) == [comments, deep]

    # sorting the nested table reads it again: what was open in it closes
    click(view, "[id='#{comments}-head-body']")
    render_async(view, 10_000)
    assert holds!(view) == [comments]
    assert column(render(view), comments, "body") == ["First comment", "Second comment"]

    # filtering it, with the deeper table open again
    expand(view, comments, first.id)
    toggle(view, comments, first.id, "task")
    render_async(view, 10_000)
    assert holds!(view) == [comments, deep]
    filter(view, comments, "body", v: "Second")
    assert holds!(view) == [comments]
    assert column(render(view), comments, "body") == ["Second comment"]
    filter(view, comments, "body", v: "")
    assert holds!(view) == [comments]

    # live updates: a comment changed, a comment gone with a table open under it
    expand(view, comments, first.id)
    toggle(view, comments, first.id, "task")
    render_async(view, 10_000)
    Ash.update!(second, %{body: "Second comment, edited"}, as(world.admin))
    heard(view)
    assert holds!(view) == [comments, deep]
    Ash.destroy!(first, as(world.admin))
    heard(view)
    assert holds!(view) == [comments]
    Ash.create!(Comment, %{body: "Third comment", task_id: task.id}, as(world.admin))
    heard(view)
    assert holds!(view) == [comments]

    # sorting the table on the page closes everything under its rows
    click(view, "[id='task-head-title']")
    render_async(view, 10_000)
    assert holds!(view) == []

    # a page change takes the rows away with their tables
    click(view, "[id='task-head-title']")
    click(view, "[id='task-head-title']")
    render_async(view, 10_000)
    expand(view, task.id)
    toggle(view, task.id, "comments")
    render_async(view, 10_000)
    assert holds!(view) == [comments]
    page_size(view, "task", 10)
    assert holds!(view) == []
    click(view, "[id='task-next']")
    render_async(view, 10_000)
    assert holds!(view) == []
    assert length(column(render(view), "task", "title")) == length(others) + 1 - 10

    # and closing a line, and the row, by hand
    click(view, "[id='task-previous']")
    render_async(view, 10_000)
    expand(view, task.id)
    toggle(view, task.id, "comments")
    render_async(view, 10_000)
    assert holds!(view) == [comments]
    toggle(view, task.id, "comments")
    assert holds!(view) == []
    toggle(view, task.id, "comments")
    render_async(view, 10_000)
    assert holds!(view) == [comments]
    expand(view, task.id)
    assert holds!(view) == []
  end
end
