defmodule DemoWeb.Tables.CommentTableTest do
  @moduledoc """
  The mounted table of `Demo.Tracker.Comment` at `/comments`: a read action
  that paginates by keyset only, 20 at a time, newest first, and counts.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator

  setup %{conn: conn} do
    world = world(tasks: 1)
    [task] = world.tasks

    for n <- 1..45 do
      Generator.generate(
        Generator.comment(
          organization_id: world.organization.id,
          task_id: task.id,
          author_id: world.member.id,
          body: body(n),
          inserted_at: DateTime.add(~U[2026-02-01 08:00:00.000000Z], n, :hour)
        )
      )
    end

    %{world: world, conn: log_in(conn, world.member)}
  end

  defp body(n), do: "Comment " <> String.pad_leading("#{n}", 2, "0")
  defp bodies(range), do: Enum.map(range, &body/1)

  test "shows the first 20, with next and previous only, and how many there are",
       %{conn: conn} do
    {:ok, _view, html} = live(conn, "/comments")

    assert headers(html, "comment") == ["ID", "Body", "Inserted at", "Task ID", "Author ID"]
    assert column(html, "comment", "body") == bodies(45..26//-1)
    assert attribute(html, "#comment-previous", "disabled") == [""]
    assert attribute(html, "#comment-next", "disabled") == []

    assert attribute(html, "#comment-pagination button", "id") == [
             "comment-previous",
             "comment-next"
           ]

    # the total alone: where a page lies among the others is not known
    assert text(html, "#comment-range") == "45 records"
  end

  test "tells assistive technology how many rows there are, the two header rows counted",
       %{conn: conn} do
    {:ok, _view, html} = live(conn, "/comments")

    assert attribute(html, "#comment-table", "aria-rowcount") == ["47"]
  end

  test "numbers the rows of every page from the top of that page", %{conn: conn} do
    {:ok, view, html} = live(conn, "/comments")

    assert attribute(html, "#comment-table [role=rowgroup] [role=row]", "aria-rowindex") ==
             Enum.map(3..22, &"#{&1}")

    view |> element("#comment-next") |> render_click()
    assert_patch(view)
    html = render_async(view)

    # which rows of the 45 these are is not known under keyset pagination
    assert attribute(html, "#comment-table [role=rowgroup] [role=row]", "aria-rowindex") ==
             Enum.map(3..22, &"#{&1}")

    assert text(html, "#comment-range") == "45 records"
  end

  test "next and previous move through the pages", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/comments")

    view |> element("#comment-next") |> render_click()
    assert "/comments?comment[after]=" <> _cursor = assert_patch(view)
    assert column(render_async(view), "comment", "body") == bodies(25..6//-1)

    view |> element("#comment-next") |> render_click()
    assert_patch(view)
    html = render_async(view)

    assert column(html, "comment", "body") == bodies(5..1//-1)
    assert attribute(html, "#comment-next", "disabled") == [""]

    view |> element("#comment-previous") |> render_click()
    assert "/comments?comment[before]=" <> _cursor = assert_patch(view)
    assert column(render_async(view), "comment", "body") == bodies(25..6//-1)

    view |> element("#comment-previous") |> render_click()
    assert_patch(view)
    html = render_async(view)

    assert column(html, "comment", "body") == bodies(45..26//-1)
    assert attribute(html, "#comment-previous", "disabled") == [""]
  end

  test "a page's URL opens that page afresh", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/comments")

    view |> element("#comment-next") |> render_click()
    url = assert_patch(view)

    {:ok, _view, html} = live(conn, url)

    assert column(html, "comment", "body") == bodies(25..6//-1)
  end

  test "sorts by an attribute, and pages in that order", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/comments")

    view |> element("#comment-sort-body") |> render_click()
    assert_patch(view, "/comments?comment[sort]=body")
    assert column(render_async(view), "comment", "body") == bodies(1..20)

    view |> element("#comment-next") |> render_click()
    assert_patch(view)
    assert column(render_async(view), "comment", "body") == bodies(21..40)
  end

  @tag :capture_log
  test "a cursor that is not one shows that the records could not be loaded", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/comments?comment[after]=nonsense")

    assert text(html, "#comment-error") == "The records could not be loaded."
  end

  test "a filter narrows the rows and says how many there are now", %{conn: conn} do
    {:ok, view, html} = live(conn, "/comments")

    assert text(html, "#comment-status") == ""

    html = filter(view, "comment", "body", v: "Comment 3")

    assert column(html, "comment", "body") == bodies(39..30//-1)
    assert text(html, "#comment-status") == "10 results"
    assert text(html, "#comment-range") == "10 records"
    assert attribute(html, "#comment-table", "aria-rowcount") == ["12"]

    html = filter(view, "comment", "body", v: "Comment 45")

    assert text(html, "#comment-status") == "1 result"
    assert text(html, "#comment-range") == "1 record"
  end

  test "says how many there are in the language of the person", %{conn: conn} do
    {:ok, view, html} = conn |> in_locale("de") |> live("/comments")

    assert text(html, "#comment-range") == "45 Einträge"
    assert text(filter(view, "comment", "body", v: "Comment 45"), "#comment-range") == "1 Eintrag"
  end

  describe "for nobody, whose read the resource refuses outright" do
    # The table of comments is declared with `on_forbidden :message`.
    test "the page says that it is not allowed, in place of the rows", %{world: world} do
      conn = log_in(build_conn(), world.nobody)

      assert html_response(get(conn, "/comments"), 200) =~
               "You are not allowed to see these records."

      {:ok, _view, html} = live(conn, "/comments")

      assert text(html, "#comment-error") == "You are not allowed to see these records."
      assert attribute(html, "#comment-error", "role") == ["alert"]
      assert column(html, "comment", "body") == []
    end

    test "that is not \"no records\", and offers no way through the pages",
         %{world: world} do
      {:ok, _view, html} = build_conn() |> log_in(world.nobody) |> live("/comments")

      assert text(html, "#comment-empty") == nil
      refute html =~ "No records"
      assert attribute(html, "#comment-pagination", "id") == []
    end

    test "the headers are still those anyone would see", %{world: world} do
      {:ok, _view, html} = build_conn() |> log_in(world.nobody) |> live("/comments")

      assert headers(html, "comment") == ["ID", "Body", "Inserted at", "Task ID", "Author ID"]
    end
  end
end
