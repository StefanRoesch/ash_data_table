defmodule DemoWeb.Tables.ReferenceCellStatesTest do
  @moduledoc """
  What a reference cell shows when the related record's label is not the
  person's to see, and what it never shows.

  The tables are of resources that exist for the tests only
  (`test/support/reference_tables.ex`), mounted at `/support/dockets`: a
  docket shows the clerk it is with by the clerk's name. A person sees the
  names of the clerks of their own office only, and nobody reads any clerk
  while `Demo.Support.Gate` is closed, which a test does while the page is
  open, as a policy can turn that looks at more than the actor.
  """
  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Support.Desk.{Clerk, Docket}
  alias Demo.Support.Gate

  setup %{conn: conn} do
    Gate.open()

    [ada, grace] =
      for {name, office} <- [{"Wilhelmina", "north"}, {"Bartholomew", "south"}] do
        Clerk |> Ash.Changeset.for_create(:create, %{name: name, office: office}) |> Ash.create!()
      end

    [north, south, free] =
      for {title, clerk} <- [{"Docket one", ada}, {"Docket two", grace}, {"Docket three", nil}] do
        Docket
        |> Ash.Changeset.for_create(:create, %{title: title, clerk_id: clerk && clerk.id})
        |> Ash.create!()
      end

    on_exit(fn ->
      Gate.open()
      Demo.Support.Ets.stop([Clerk, Docket])
    end)

    %{conn: conn, north: north, south: south, free: free}
  end

  defp as(conn, reader),
    do: Phoenix.ConnTest.init_test_session(conn, %{"assigns" => %{reader: reader}})

  # What a cell holds for a screen reader alone.
  defp hidden_text(html, id, key, field),
    do: text(html, "#{cell(id, key, field)} > span.sr-only")

  test "a label the person may see is shown; one hidden from them is the cell of a hidden field",
       %{conn: conn, north: north, south: south, free: free} do
    {:ok, _view, html} = conn |> as(%{office: "north"}) |> live("/support/dockets")

    assert headers(html, "docket") == ["Title", "Clerk"]

    assert text(html, cell("docket", north.id, "clerk")) == "Wilhelmina"
    assert hidden_text(html, "docket", north.id, "clerk") == nil

    # there is a clerk, whom they may read, whose name they may not see
    assert text(html, cell("docket", south.id, "clerk")) == "Not available"
    assert hidden_text(html, "docket", south.id, "clerk") == "Not available"
    refute html =~ "Bartholomew"

    # and there is none
    assert text(html, cell("docket", free.id, "clerk")) == ""
    assert hidden_text(html, "docket", free.id, "clerk") == nil
  end

  test "a label the person can never see has no column", %{conn: conn, north: north} do
    # nobody is of no office
    {:ok, _view, html} = live(conn, "/support/dockets")

    assert headers(html, "docket") == ["Title"]

    assert Enum.sort(column(html, "docket", "title")) ==
             ["Docket one", "Docket three", "Docket two"]

    assert attribute(html, cell("docket", north.id, "clerk"), "id") == []
    refute html =~ "Wilhelmina"
    refute html =~ "Bartholomew"
  end

  test "a destination the person may not read has no column, and the rest of the table is there",
       %{conn: conn} do
    Gate.close()

    {:ok, _view, html} = conn |> as(%{office: "north"}) |> live("/support/dockets")

    assert headers(html, "docket") == ["Title"]
    assert length(column(html, "docket", "title")) == 3
    refute html =~ "Wilhelmina"
  end

  test "a destination that is refused while the page is open is not shown when a row is saved",
       %{conn: conn, north: north} do
    {:ok, view, html} = conn |> as(%{office: "north"}) |> live("/support/dockets")
    assert text(html, cell("docket", north.id, "clerk")) == "Wilhelmina"

    Gate.close()
    html = save(view, "docket", north.id, "title", "Docket one, again")

    assert text(html, cell("docket", north.id, "title")) == "Docket one, again"
    assert hidden_text(html, "docket", north.id, "clerk") == "Not available"
    refute text(html, cell("docket", north.id, "clerk")) =~ "Wilhelmina"
  end
end
