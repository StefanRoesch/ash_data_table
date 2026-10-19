defmodule DemoWeb.Tables.LongTextTableTest do
  @moduledoc """
  Columns that show several lines (`max_lines`), in the table of a resource
  that exists for the tests only (`test/support/long_text_tables.ex`), and in
  the demo's compact comments: which cells say how many lines they show, what
  such a cell holds, and that the element the whole text of a cell is shown
  in is rendered empty.

  What a browser makes of it (the lines, the ellipsis, the popover) is in
  `e2e/long_text.spec.ts`.
  """
  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Support.Long.Essay

  @body "A first paragraph.\n\nA second one, <b>with</b> a mark & more.\nAnd a last line."
  # found nowhere else in a page
  @draft "draft-7c1e9a"
  @token "tok-4d2f8b"

  setup do
    on_exit(fn -> Demo.Support.Ets.stop(Essay) end)

    essay =
      Ash.Seed.seed!(Essay, %{
        title: "On tables",
        body: @body,
        tags: ["long", "text"],
        facts: %{"words" => 12},
        draft: @draft,
        token: @token,
        pages: 3
      })

    %{essay: essay, empty: Ash.Seed.seed!(Essay, %{title: "Empty"})}
  end

  defp as(conn, role),
    do: Phoenix.ConnTest.init_test_session(conn, %{"assigns" => %{reader: %{role: role}}})

  defp shown_lines(html, key, field), do: attribute(html, cell("essay", key, field), "data-lines")

  # what a cell holds, as markup
  defp inner(html, key, field) do
    [{_td, _attributes, children}] =
      html |> query(cell("essay", key, field)) |> LazyHTML.to_tree()

    children
  end

  defp query(html, selector), do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector)

  describe "the cells of a column with `max_lines`" do
    setup %{conn: conn} do
      {:ok, view, html} = live(as(conn, :admin), "/support/essays")
      %{view: view, html: html}
    end

    test "say how many lines they show; the cells of the other columns say nothing", %{
      html: html,
      essay: essay
    } do
      assert shown_lines(html, essay.id, "body") == ["3"]
      assert shown_lines(html, essay.id, "tags") == ["2"]
      assert shown_lines(html, essay.id, "facts") == ["2"]
      assert shown_lines(html, essay.id, "draft") == ["2"]

      for field <- ["title", "token", "pages"] do
        assert shown_lines(html, essay.id, field) == [], field
      end
    end

    test "hold their text in one paragraph, as it is: the line breaks kept, the markup escaped",
         %{html: html, essay: essay} do
      assert inner(html, essay.id, "body") == [{"p", [{"data-paragraph", ""}], [@body]}]
      assert inner(html, essay.id, "tags") == [{"p", [{"data-paragraph", ""}], ["long, text"]}]
      assert inner(html, essay.id, "facts") == [{"p", [{"data-paragraph", ""}], ["Words: 12"]}]
      assert inner(html, essay.id, "draft") == [{"p", [{"data-paragraph", ""}], [@draft]}]
      # a column of one line holds its text and nothing around it
      assert inner(html, essay.id, "title") == ["On tables"]
    end

    test "an empty cell is empty, with or without lines", %{html: html, empty: empty} do
      for field <- ["body", "tags", "facts", "draft"] do
        assert inner(html, empty.id, field) == [], field
        assert shown_lines(html, empty.id, field) != [], field
      end
    end

    test "a save that fails shows what was typed in a paragraph, and its message beside it", %{
      view: view,
      essay: essay
    } do
      html = save(view, "essay", essay.id, "body", "Too loud!\nReally.")

      assert %{shown: "Too loud!\nReally.", message: "must not shout"} =
               failure(html, "essay", essay.id, "body")

      assert [
               {"p", [{"data-paragraph", ""}], ["Too loud!\nReally."]},
               {"span", _attributes, ["must not shout"]}
             ] =
               inner(html, essay.id, "body")

      # and a save that goes through shows the new text the same way
      html = save(view, "essay", essay.id, "body", "Quiet.\nNow.")
      assert inner(html, essay.id, "body") == [{"p", [{"data-paragraph", ""}], ["Quiet.\nNow."]}]
    end
  end

  describe "the whole text of a cell" do
    test "is the cell's own, shown in place by the hook: nothing of it is rendered for it, and no sensitive value is in the page",
         %{conn: conn, essay: essay} do
      {:ok, _view, html} = live(as(conn, :admin), "/support/essays")

      # nothing floats: no element is rendered for it, and the grid says
      # what the button the hook puts into a cell says
      assert attribute(html, "#essay-whole", "id") == []
      assert attribute(html, "#essay-grid", "data-show-whole") == ["Show all"]
      assert attribute(html, "#essay-grid", "data-show-less") == ["Show less"]
      assert attribute(html, "#essay-table [data-whole]", "id") == []

      # the sensitive value is nowhere; no cell has a `title`
      refute html =~ @token

      assert attribute(html, cell("essay", essay.id, "token") <> " [data-mask]", "aria-hidden") ==
               ["true"]

      assert attribute(html, "#essay-table :is([role=cell],[role=rowheader])", "role") != []

      assert attribute(html, "#essay-table :is([role=cell],[role=rowheader])[title]", "title") ==
               []
    end

    test "a field the person may not see on a row is not in the page, in a column of several lines either",
         %{conn: conn, essay: essay} do
      closed = Ash.Seed.seed!(Essay, %{title: "Closed", draft: "closed-" <> @draft})
      {:ok, _view, html} = live(as(conn, :reader), "/support/essays")

      refute html =~ "closed-" <> @draft
      # the cell says so to a screen reader, as in every column, and holds no paragraph
      assert [{"span", [{"class", "sr-only"}, {"data-unseen", ""}], [_not_available]}] =
               inner(html, closed.id, "draft")

      assert shown_lines(html, closed.id, "draft") == ["2"]
      # the draft of another essay is theirs to read
      assert inner(html, essay.id, "draft") == [{"p", [{"data-paragraph", ""}], [@draft]}]
    end
  end

  describe "the demo's compact comments" do
    test "show up to three lines of a comment, at /comments/compact and nested under a task of the board",
         %{conn: conn} do
      world = world(tasks: 1)
      [task] = world.tasks

      comment =
        Demo.Generator.generate(
          Demo.Generator.comment(
            organization_id: world.organization.id,
            task_id: task.id,
            author_id: world.admin.id,
            body: "One line.\nAnother."
          )
        )

      conn = log_in(conn, world.admin)
      {:ok, view, _html} = live(conn, "/comments/compact")
      html = render_async(view)

      assert attribute(html, cell("comment_compact", comment.id, "body"), "data-lines") == ["3"]
      assert text(html, cell("comment_compact", comment.id, "body") <> " > p") =~ "One line."
      assert attribute(html, cell("comment_compact", comment.id, "author"), "data-lines") == []

      # the default table of the comments shows one line
      {:ok, view, _html} = live(conn, "/comments")
      html = render_async(view)
      assert attribute(html, cell("comment", comment.id, "body"), "data-lines") == []

      {:ok, view, _html} = live(conn, "/tasks/board")
      render_async(view)
      expand(view, "task_board", task.id)
      toggle(view, "task_board", task.id, "comments")
      html = render_async(view)
      nested = nested("task_board", task.id, "comments")
      assert attribute(html, cell(nested, comment.id, "body"), "data-lines") == ["3"]
      assert attribute(html, "[id='#{nested}-grid']", "data-show-whole") == ["Show all"]
    end
  end
end
