defmodule DemoWeb.Tables.NestedTableStatesTest do
  @moduledoc """
  What a nested table shows when the person may not read its records, or
  when its read fails: something inside the row in every case, and never
  "No records".

  The tables are of resources that exist for the tests only
  (`test/support/nested_tables.ex`), mounted at `/support/binders`. Whether
  the papers and the drafts of a binder may be read is said by
  `Demo.Support.Gate`, which a test closes while the page is open, as a
  policy can turn that looks at more than the actor; what the read of the
  sheets does is said by `Demo.Support.Switch`.
  """
  use DemoWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Support.Gate
  alias Demo.Support.Shelves.{Binder, Draft, Paper, Sheet, Slip}
  alias Demo.Support.Switch

  setup %{conn: conn} do
    Gate.open()
    Switch.set(:ok)

    binder = Binder |> Ash.Changeset.for_create(:create, %{title: "Contracts"}) |> Ash.create!()

    for resource <- [Paper, Draft, Sheet] do
      resource
      |> Ash.Changeset.for_create(:create, %{title: "Page one", binder_id: binder.id})
      |> Ash.create!()
    end

    on_exit(fn ->
      Gate.open()
      Switch.set(:ok)
      Enum.each([Binder, Paper, Draft, Sheet, Slip], &Ash.DataLayer.Ets.stop/1)
    end)

    {:ok, view, _html} = live(conn, "/support/binders")
    expand(view, "binder", binder.id)

    %{view: view, binder: binder}
  end

  defp open(view, binder, relationship) do
    {toggle(view, "binder", binder.id, relationship), nested("binder", binder.id, relationship)}
  end

  test "while the records may be read, each line opens its table", %{view: view, binder: binder} do
    assert lines(render(view), "binder", binder.id) == [
             "Papers",
             "Sealed papers",
             "Drafts",
             "Sheets",
             "Slips"
           ]

    for relationship <- ~w(papers sealed_papers drafts sheets) do
      {html, id} = open(view, binder, relationship)

      assert column(html, id, "title") == ["Page one"]
      assert text(html, "[id='#{id}-error']") == nil
    end
  end

  describe "a destination the person may not read" do
    # Ash puts the refusal in place of the related records
    test "is said in the row when the destination's table says `on_forbidden :message`",
         %{view: view, binder: binder} do
      Gate.close()
      {html, id} = open(view, binder, "papers")

      assert text(html, "[id='#{id}-error']") == "You are not allowed to see these records."
      assert attribute(html, "[id='#{id}-error']", "role") == ["alert"]
      assert text(html, "[id='#{id}-empty']") == nil
      assert column(html, id, "title") == []
      refute html =~ "Page one"
    end

    # Ash fails the whole read: the relationship says `allow_forbidden_field? false`
    test "is said the same when the refusal comes as an error of the read",
         %{view: view, binder: binder} do
      Gate.close()
      {html, id} = open(view, binder, "sealed_papers")

      assert text(html, "[id='#{id}-error']") == "You are not allowed to see these records."
      assert text(html, "[id='#{id}-empty']") == nil
      refute html =~ "Page one"
    end

    test "is no more than \"not available\" when the destination's table does not say so: never \"No records\"",
         %{view: view, binder: binder} do
      Gate.close()
      {html, id} = open(view, binder, "drafts")

      assert text(html, "[id='#{id}-error']") == "These records are not available."
      assert text(html, "[id='#{id}-empty']") == nil
      refute html =~ "not allowed"
      refute html =~ "Page one"
      # the table around it, and the page, are as they were
      assert column(html, "binder", "title") == ["Contracts"]
    end

    test "takes the rows of an open nested table away at its next read", %{
      view: view,
      binder: binder
    } do
      {html, id} = open(view, binder, "papers")
      assert column(html, id, "title") == ["Page one"]

      Gate.close()
      view |> element("[id='#{id}-head-title']") |> render_click()
      html = render_async(view, 2000)

      assert text(html, "[id='#{id}-error']") == "You are not allowed to see these records."
      assert column(html, id, "title") == []
      refute html =~ "Page one"
    end
  end

  describe "a read that fails" do
    test "shows the message of an error the action returned, inside the row",
         %{view: view, binder: binder} do
      Switch.set(:invalid)
      {html, id} = open(view, binder, "sheets")

      assert text(html, "[id='#{id}-error']") == "is closed until Monday"
      assert text(html, "[id='#{id}-empty']") == nil
      assert column(html, "binder", "title") == ["Contracts"]
    end

    test "says only that the records could not be loaded when it fails underneath, and is logged",
         %{view: view, binder: binder} do
      Switch.set(:unknown)

      {{html, id}, log} = with_log(fn -> open(view, binder, "sheets") end)

      assert text(html, "[id='#{id}-error']") == "The records could not be loaded."
      refute html =~ "vault"
      assert log =~ "the vault at 10.0.0.7 did not answer"
    end

    test "that crashes leaves the page and the table around it standing", %{
      view: view,
      binder: binder
    } do
      Switch.set(:crash)

      {{html, id}, log} = with_log(fn -> open(view, binder, "sheets") end)

      assert text(html, "[id='#{id}-error']") == "The records could not be loaded."
      assert text(html, "[id='#{id}-loading']") == nil
      refute html =~ "vault"
      assert log =~ "the vault at 10.0.0.7 did not answer"
      assert column(html, "binder", "title") == ["Contracts"]

      # and the other lines still open
      Switch.set(:ok)
      {html, id} = open(view, binder, "papers")
      assert column(html, id, "title") == ["Page one"]
    end
  end

  # Ash counts a page of related records with the person's filter as it is
  # written, without the field policies (see `NestedTableGuardTest`). Here
  # for a nested table with keyset pages, whose total stands alone.
  describe "the total of a nested table with keyset pages" do
    setup %{conn: conn, binder: binder} do
      # eight slips whose amount max sees, eight whose amount is hidden from max
      for owner <- ["max", "eve"], n <- 1..8 do
        Slip
        |> Ash.Changeset.for_create(:create, %{
          title: "#{owner} #{n}",
          amount: 20,
          owner: owner,
          binder_id: binder.id
        })
        |> Ash.create!(authorize?: false)
      end

      conn =
        Phoenix.ConnTest.init_test_session(conn, %{
          "assigns" => %{reader: %{name: "max"}}
        })

      {:ok, view, _html} = live(conn, "/support/binders")
      expand(view, "binder", binder.id)
      {html, id} = open(view, binder, "slips")
      %{view: view, html: html, id: id}
    end

    test "is there while nothing is filtered", %{html: html, id: id} do
      assert column(html, id, "title") == ["eve 1", "eve 2", "eve 3", "eve 4", "eve 5"]
      assert column(html, id, "amount") == List.duplicate("Not available", 5)
      assert text(html, "[id='#{id}-range']") == "16 records"
      assert attribute(html, "[id='#{id}-table']", "aria-rowcount") == ["18"]
    end

    for {name, entry} <- [
          {"greater than", %{"o" => "greater_than", "v" => "10"}},
          {"at least", %{"o" => "at_least", "v" => "20"}},
          {"is empty", %{"o" => "is_empty"}}
        ] do
      test "is not shown or announced while the amount is filtered by #{name}: only previous and next",
           %{view: view, id: id} do
        view
        |> element("[id='#{id}-grid']")
        |> render_hook("filter", %{"filter" => %{"amount" => unquote(Macro.escape(entry))}})

        html = render_async(view, 2000)

        assert length(column(html, id, "title")) == 5
        # no "8 records", and not the 16 or the 8 that a count without the policies gives
        assert text(html, "[id='#{id}-range']") == ""
        assert text(html, "[id='#{id}-status']") == "Results updated"
        assert attribute(html, "[id='#{id}-table']", "aria-rowcount") == ["-1"]

        assert attribute(html, "[id='#{id}-pagination'] button", "id") ==
                 ["#{id}-previous", "#{id}-next"]

        assert attribute(html, "[id='#{id}-next']", "disabled") == []

        view |> element("[id='#{id}-next']") |> render_click()
        html = render_async(view, 2000)

        assert length(column(html, id, "title")) == 3
        assert text(html, "[id='#{id}-range']") == ""
        assert attribute(html, "[id='#{id}-next']", "disabled") == [""]
      end
    end

    test "is back when the filter is gone", %{view: view, id: id} do
      view
      |> element("[id='#{id}-grid']")
      |> render_hook("filter", %{"filter" => %{"amount" => %{"o" => "at_least", "v" => "20"}}})

      render_async(view, 2000)
      view |> element("[id='#{id}-clear-filters']") |> render_click()
      html = render_async(view, 2000)

      assert text(html, "[id='#{id}-range']") == "16 records"
      assert text(html, "[id='#{id}-status']") == "16 results"
    end
  end
end
