defmodule DemoWeb.Tables.EmbeddedUrlTableTest do
  @moduledoc """
  Tables placed in a LiveView of the host's and given the page's URL
  (`<AshDataTable.table … url={@url} />`): they keep their sort, filters and
  page in that URL, each under its own id.

  The demo's dashboard keeps its tables' state out of the URL, so this page
  exists for the tests only (`DemoWeb.Support.UrlLive`, at `/support/url`),
  with resources whose records are kept in memory: twelve entries, read five
  to a page by offset in the order of their ranks, and twelve tickets, read
  five to a page by keyset.
  """
  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Support.Plain.Entry
  alias Demo.Support.Plain.Ticket

  setup do
    for n <- 1..12 do
      Entry
      |> Ash.Changeset.for_create(:create, %{title: "Entry #{number(n)}", rank: n})
      |> Ash.create!()

      Ticket
      |> Ash.Changeset.for_create(:create, %{title: "Ticket #{number(n)}"})
      |> Ash.create!()
    end

    on_exit(fn ->
      Demo.Support.Ets.stop(Entry)
      Demo.Support.Ets.stop(Ticket)
    end)
  end

  defp number(n), do: String.pad_leading("#{n}", 2, "0")
  defp entries(html), do: column(html, "entries", "title")
  defp tickets(html), do: column(html, "tickets", "title")
  defp named(prefix, range), do: Enum.map(range, &"#{prefix} #{number(&1)}")

  test "the plain address shows each table's first page", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/support/url")

    assert entries(html) == named("Entry", 1..5)
    assert tickets(html) == named("Ticket", 1..5)
    assert text(html, "#entries-range") == "1–5 of 12"
  end

  test "a sort patches the host's URL, and the table shows what the URL says", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/support/url")

    view |> element("#entries-sort-title") |> render_click()
    assert_patch(view, "/support/url?entries[sort]=title")
    assert entries(render_async(view)) == named("Entry", 1..5)

    view |> element("#entries-sort-title") |> render_click()
    assert_patch(view, "/support/url?entries[sort]=-title")
    html = render_async(view)

    assert entries(html) == named("Entry", 12..8//-1)
    assert attribute(html, "#entries-head-title", "aria-sort") == ["descending"]

    view |> element("#entries-sort-title") |> render_click()
    assert_patch(view, "/support/url")
    assert entries(render_async(view)) == named("Entry", 1..5)
  end

  test "a filter patches the host's URL and is announced", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/support/url")

    html = filter(view, "entries", "title", v: "Entry 1")

    assert_patch(view, "/support/url?entries[f][title]=Entry+1")
    assert entries(html) == named("Entry", 10..12)
    assert text(html, "#entries-status") == "3 results"

    view |> element("#entries-clear-filters") |> render_click()
    assert_patch(view, "/support/url")
    assert entries(render_async(view)) == named("Entry", 1..5)
  end

  test "a page change patches the host's URL", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/support/url")

    view |> element("#entries-next") |> render_click()
    assert_patch(view, "/support/url?entries[page]=2")
    html = render_async(view)

    assert entries(html) == named("Entry", 6..10)
    assert text(html, "#entries-range") == "6–10 of 12"

    view |> element("#entries-page-3") |> render_click()
    assert_patch(view, "/support/url?entries[page]=3")
    assert entries(render_async(view)) == named("Entry", 11..12)
  end

  test "opening a URL restores sort, filter and page", %{conn: conn} do
    {:ok, _view, html} =
      live(conn, "/support/url?entries[sort]=-title&entries[page]=2&entries[f][rank][at_least]=3")

    # ranks 3 to 12, the titles downwards, the second five
    assert entries(html) == named("Entry", 7..3//-1)
    assert attribute(html, "#entries-head-title", "aria-sort") == ["descending"]
    assert attribute(html, "#entries-page-2", "aria-current") == ["page"]
    assert attribute(html, "#entries-filter-rank-value", "value") == ["3"]
    assert text(html, "#entries-range") == "6–10 of 10"
  end

  test "the page's own parameters stay when a table patches the URL", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/support/url?tab=overview")

    view |> element("#entries-sort-title") |> render_click()
    assert_patch(view, "/support/url?entries[sort]=title&tab=overview")

    view |> element("#entries-sort-title") |> render_click()
    view |> element("#entries-sort-title") |> render_click()
    assert_patch(view, "/support/url?tab=overview")
  end

  test "two tables share the URL, each under its id, and leave each other's state alone",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, "/support/url")

    view |> element("#tickets-next") |> render_click()
    assert "/support/url?tickets[after]=" <> cursor = assert_patch(view)
    html = render_async(view)

    assert tickets(html) == named("Ticket", 6..10)
    assert entries(html) == named("Entry", 1..5)

    view |> element("#entries-next") |> render_click()
    assert_patch(view, "/support/url?entries[page]=2&tickets[after]=#{cursor}")
    html = render_async(view)

    assert entries(html) == named("Entry", 6..10)
    assert tickets(html) == named("Ticket", 6..10)

    {:ok, _view, html} = live(conn, "/support/url?entries[page]=2&tickets[after]=#{cursor}")

    assert entries(html) == named("Entry", 6..10)
    assert tickets(html) == named("Ticket", 6..10)
  end
end
