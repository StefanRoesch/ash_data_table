defmodule DemoWeb.Tables.FullViewStatesTest do
  @moduledoc """
  The full view of a nested table where something stands in its way: a
  destination the person may not read, a record whose table has no page, a
  record whose label is hidden from them; and the full view in a table that
  a page of the host's holds.

  The tables are of resources that exist for the tests only
  (`test/support/nested_tables.ex` and `test/support/reference_tables.ex`).
  Whether papers, drafts and clerks may be read is said by
  `Demo.Support.Gate`, which a test closes while a page is open.
  """
  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Support.Desk.{Clerk, Docket}
  alias Demo.Support.Gate
  alias Demo.Support.Shelves.{Binder, Draft, Paper}

  setup do
    Gate.open()

    on_exit(fn ->
      Gate.open()
      Enum.each([Binder, Paper, Draft, Clerk, Docket], &Ash.DataLayer.Ets.stop/1)
    end)
  end

  defp create(resource, attributes),
    do: resource |> Ash.Changeset.for_create(:create, attributes) |> Ash.create!()

  defp as(conn, reader),
    do: Phoenix.ConnTest.init_test_session(conn, %{"assigns" => %{reader: reader}})

  defp heading(html, id), do: text(html, "##{id}-related-heading")

  describe "a destination the person may not read" do
    setup do
      binder = create(Binder, %{title: "Contracts"})

      for resource <- [Paper, Draft],
          do: create(resource, %{title: "Page one", binder_id: binder.id})

      %{
        papers: "/support/papers?paper[of][binder][papers]=#{binder.id}",
        sealed: "/support/papers?paper[of][binder][sealed_papers]=#{binder.id}",
        drafts: "/support/drafts?draft[of][binder][drafts]=#{binder.id}"
      }
    end

    test "is shown while it may be read", %{
      conn: conn,
      papers: papers,
      sealed: sealed,
      drafts: drafts
    } do
      for {path, id, heading} <- [
            {papers, "paper", "Contracts: Papers"},
            {sealed, "paper", "Contracts: Sealed papers"},
            {drafts, "draft", "Contracts: Drafts"}
          ] do
        {:ok, _view, html} = live(conn, path)

        assert column(html, id, "title") == ["Page one"]
        assert heading(html, id) == heading
        assert attribute(html, "##{id}-related-parent", "href") == ["/support/binders"]
      end
    end

    test "says so where its table says `on_forbidden :message`, and names no record", %{
      conn: conn,
      papers: papers,
      sealed: sealed
    } do
      Gate.close()

      for path <- [papers, sealed] do
        {:ok, _view, html} = live(conn, path)

        assert text(html, "#paper-error") == "You are not allowed to see these records."
        assert text(html, "#paper-empty") == nil
        assert column(html, "paper", "title") == []
        refute html =~ "Contracts"
      end
    end

    test "is a page that does not exist where its table says nothing", %{
      conn: conn,
      drafts: drafts
    } do
      Gate.close()

      assert_raise AshTable.NotFoundError, fn -> live(conn, drafts) end
      assert_error_sent 404, fn -> get(conn, drafts) end
    end

    test "that is refused while the page is open stops being shown at the next read", %{
      conn: conn,
      papers: papers,
      sealed: sealed,
      drafts: drafts
    } do
      for path <- [papers, sealed] do
        Gate.open()
        {:ok, view, html} = live(conn, path)
        assert heading(html, "paper") =~ "Contracts"

        Gate.close()
        view |> element("#paper-head-title") |> render_click()
        html = render_async(view, 2000)

        assert text(html, "#paper-error") == "You are not allowed to see these records."
        assert column(html, "paper", "title") == []
        refute html =~ "Contracts"
      end

      Gate.open()
      {:ok, view, _html} = live(conn, drafts)

      Gate.close()
      view |> element("#draft-head-title") |> render_click()

      # the browser is sent to ask for the page afresh, which answers 404
      {path, _flash} = assert_redirect(view, 2000)
      assert_error_sent 404, fn -> get(conn, path) end
    end
  end

  describe "a record whose table has no page of its own" do
    setup %{conn: conn} do
      clerk = create(Clerk, %{name: "Wilhelmina", office: "north"})
      docket = create(Docket, %{title: "Docket one", clerk_id: clerk.id})
      create(Docket, %{title: "Docket two", clerk_id: clerk.id})
      create(Docket, %{title: "Docket of nobody"})

      %{
        conn: conn,
        clerk: clerk,
        docket: docket,
        path: "/support/dockets?docket[of][clerk][dockets]=#{clerk.id}"
      }
    end

    test "is named in the heading without a link", %{conn: conn, path: path} do
      {:ok, _view, html} = conn |> as(%{office: "north"}) |> live(path)

      assert Enum.sort(column(html, "docket", "title")) == ["Docket one", "Docket two"]
      assert heading(html, "docket") == "Wilhelmina: Dockets"
      assert text(html, "span#docket-related-parent") == "Wilhelmina"
      assert attribute(html, "#docket-related a[href]", "id") == ["docket-related-clear"]
    end

    test "is not named for a person from whom everything it could be called by is hidden", %{
      conn: conn,
      path: path
    } do
      # of another office: they read the clerk, and not the clerk's name
      {:ok, _view, html} = conn |> as(%{office: "south"}) |> live(path)

      assert Enum.sort(column(html, "docket", "title")) == ["Docket one", "Docket two"]
      assert heading(html, "docket") == "Dockets"
      assert attribute(html, "#docket-related-parent", "id") == []
      refute html =~ "Wilhelmina"
    end

    test "is where a nested table of its rows links from, two levels down", %{
      conn: conn,
      clerk: clerk,
      docket: docket
    } do
      {:ok, view, _html} = conn |> as(%{office: "north"}) |> live("/support/dockets")

      expand(view, "docket", docket.id)
      html = toggle(view, "docket", docket.id, "clerk")
      clerks = nested("docket", docket.id, "clerk")

      # the clerks have no page: their nested table has no link
      assert column(html, clerks, "name") == ["Wilhelmina"]
      assert attribute(html, "[id='#{clerks}-full-view']", "id") == []

      expand(view, clerks, clerk.id)
      html = toggle(view, clerks, clerk.id, "dockets")

      assert attribute(html, "[id='#{nested(clerks, clerk.id, "dockets")}-full-view']", "href") ==
               ["/support/dockets?docket[of][clerk][dockets]=#{clerk.id}"]
    end
  end

  describe "a table that a page of the host's holds, with its state in that page's URL" do
    setup %{conn: conn} do
      clerk = create(Clerk, %{name: "Wilhelmina", office: "north"})
      create(Docket, %{title: "Docket one", clerk_id: clerk.id})
      create(Docket, %{title: "Docket two", clerk_id: clerk.id})
      create(Docket, %{title: "Docket of nobody"})

      %{conn: as(conn, %{office: "north"}), clerk: clerk}
    end

    test "is limited by its own parameter, keeps the limit through a sort, and gives it up on the way back",
         %{conn: conn, clerk: clerk} do
      {:ok, view, html} = live(conn, "/support/held-dockets?held[of][clerk][dockets]=#{clerk.id}")

      assert Enum.sort(column(html, "held", "title")) == ["Docket one", "Docket two"]
      assert heading(html, "held") == "Wilhelmina: Dockets"

      view |> element("#held-head-title") |> render_click()

      assert assert_patch(view) ==
               "/support/held-dockets?held[of][clerk][dockets]=#{clerk.id}&held[sort]=title"

      assert column(render_async(view, 2000), "held", "title") == ["Docket one", "Docket two"]

      view |> element("#held-related-clear") |> render_click()
      assert assert_patch(view) == "/support/held-dockets"
      assert length(column(render_async(view, 2000), "held", "title")) == 3
    end

    test "is not limited by the parameter of another table", %{conn: conn, clerk: clerk} do
      {:ok, _view, html} =
        live(conn, "/support/held-dockets?docket[of][clerk][dockets]=#{clerk.id}")

      assert length(column(html, "held", "title")) == 3
      assert attribute(html, "#held-related", "id") == []
    end
  end
end
