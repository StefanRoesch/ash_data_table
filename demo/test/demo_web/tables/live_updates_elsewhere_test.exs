defmodule DemoWeb.Tables.LiveUpdatesElsewhereTest do
  @moduledoc """
  Live updates where the demo's own tables do not have the case, in the
  tables of resources that exist for the tests only
  (`test/support/live_tables.ex`): a record that stops being a person's to
  read, a record they may not read at all, a field a field policy hides, a
  sensitive column, a page mounted without authorization, a page and a
  named table that do not follow, a resource that announces nothing, and
  a picker.

  The demo's own, on Postgres, are in `live_updates_test.exs`.
  """
  use DemoWeb.ModeCase, async: false

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias AshDataTable.Resource.Notifier
  alias Demo.Support.Live.{Bulletin, Pin, Reply, Stamp}

  @notice "There are new or changed records."
  # found nowhere else in a page
  @code "code-7f3a9b1c"
  @draft "draft-4e2d8a6f"

  setup do
    on_exit(fn -> Demo.Support.Ets.stop([Bulletin, Reply, Stamp, Pin]) end)

    %{
      plain: Ash.Seed.seed!(Bulletin, %{title: "Plain", code: @code, draft: @draft}),
      hidden: Ash.Seed.seed!(Bulletin, %{title: "Kept back", hidden?: true})
    }
  end

  defp as(conn, role),
    do: Phoenix.ConnTest.init_test_session(conn, %{"assigns" => %{reader: %{role: role}}})

  # The page once what was announced has reached it. A listener gathers for
  # 100 ms; `AshDataTable.Test.flush/1` has it hand over at once, and the table
  # may read again for what it heard. A row that is to go is asked about
  # first (`ash_data_table:leaving`): `gone` are the keys of the rows the
  # test expects to go, and for each the hook, which these tests do not
  # have, answers that no cell of it is being edited.
  defp heard(view, gone \\ []) do
    AshDataTable.Test.flush(view)
    render_async(view, 10_000)
    Enum.each(gone, &left(view, &1))
    render(view)
  end

  defp left(view, row) do
    assert_push_event(view, "ash_data_table:leaving", %{table: table, row: ^row})
    forge(view, table, "left", %{"row" => row})
  end

  defp titles(html, id \\ "bulletin"), do: column(html, id, "title")
  defp notice(html, id \\ "bulletin"), do: text(html, "[id='#{id}-notice'] > span") || ""

  # How many tables listen to the changes of a resource.
  defp listeners(resource), do: AshDataTable.Test.listening(resource)

  describe "a record the person may not read" do
    setup %{conn: conn} do
      {:ok, reader, html} = conn |> as(:reader) |> live("/support/bulletins")
      assert titles(html) == ["Plain"]
      %{reader: reader}
    end

    test "shows nothing when it is created or changed: no row and no notice",
         %{reader: reader, hidden: hidden} do
      Ash.update!(hidden, %{title: "Kept back, renamed"}, authorize?: false)
      Ash.create!(Bulletin, %{title: "Another secret", hidden?: true}, authorize?: false)

      sent = wire(reader, fn -> AshDataTable.Test.flush(reader) end)
      html = render(reader)

      assert titles(html) == ["Plain"]
      assert notice(html) == ""
      assert text(html, "#bulletin-range") == "1–1 of 1"
      refute sent =~ "Kept back"
      refute sent =~ "Another secret"
      refute sent =~ "new or changed"
    end

    test "is spoken of once it is theirs to read", %{reader: reader, hidden: hidden} do
      Ash.update!(hidden, %{hidden?: false}, authorize?: false)

      html = heard(reader)
      assert titles(html) == ["Plain"]
      assert notice(html) == @notice
    end

    test "goes from the page when it stops being theirs to read",
         %{reader: reader, plain: plain} do
      Ash.create!(Bulletin, %{title: "Stays"}, authorize?: false)
      assert notice(heard(reader)) == @notice
      reader |> element("#bulletin-read-again") |> render_click()
      assert titles(render_async(reader, 10_000)) == ["Plain", "Stays"]

      Ash.update!(plain, %{hidden?: true}, authorize?: false)

      html = heard(reader, [plain.id])
      assert titles(html) == ["Stays"]
      assert text(html, "#bulletin-range") == "1–1 of 1"
      refute html =~ "Plain"
    end

    test "is still an admin's to see", %{conn: conn, hidden: hidden} do
      {:ok, admin, html} = conn |> as(:admin) |> live("/support/bulletins")
      assert titles(html) == ["Kept back", "Plain"]

      Ash.update!(hidden, %{title: "Kept back, renamed"}, authorize?: false)
      assert titles(heard(admin)) == ["Kept back, renamed", "Plain"]
    end
  end

  describe "a field the person may not see" do
    test "stays hidden in a row that is updated", %{conn: conn, plain: plain} do
      {:ok, reader, html} = conn |> as(:reader) |> live("/support/bulletins")
      assert column(html, "bulletin", "draft") == ["Not available"]

      Ash.update!(plain, %{title: "Plain, renamed"}, authorize?: false)

      sent = wire(reader, fn -> AshDataTable.Test.flush(reader) end)
      html = render(reader)

      assert titles(html) == ["Plain, renamed"]
      assert column(html, "bulletin", "draft") == ["Not available"]
      assert attribute(html, cell("bulletin", plain.id, "draft"), "tabindex") == []
      refute html =~ @draft
      refute sent =~ @draft
      assert sent =~ "Plain, renamed"
    end

    test "is shown in a row whose change makes it theirs to see", %{conn: conn, plain: plain} do
      {:ok, reader, _html} = conn |> as(:reader) |> live("/support/bulletins")

      # the draft is everybody's on the bulletin called "shared"
      Ash.update!(plain, %{title: "shared"}, authorize?: false)
      assert column(heard(reader), "bulletin", "draft") == [@draft]
    end

    test "a sensitive value stays masked, and is neither in the page nor in what is sent",
         %{conn: conn, plain: plain} do
      {:ok, admin, html} = conn |> as(:admin) |> live("/support/bulletins")
      assert masked(html, "bulletin", plain.id, "code").mask
      refute html =~ @code

      Ash.update!(plain, %{title: "Plain, renamed", code: "code-new-5d6e"}, authorize?: false)

      sent = wire(admin, fn -> AshDataTable.Test.flush(admin) end)
      html = render(admin)

      assert "Plain, renamed" in titles(html)
      assert masked(html, "bulletin", plain.id, "code").mask

      for text <- [html, sent, kept(admin)], secret <- [@code, "code-new-5d6e"] do
        refute text =~ secret
      end
    end
  end

  describe "a page mounted without authorization" do
    test "reads again without authorization, as it reads its pages",
         %{conn: conn, hidden: hidden, plain: plain} do
      {:ok, open, html} = conn |> as(:reader) |> live("/support/open/bulletins")
      {:ok, closed, _html} = conn |> as(:reader) |> live("/support/bulletins")
      assert titles(html) == ["Kept back", "Plain"]
      assert column(html, "bulletin", "draft") == ["", @draft]

      Ash.update!(hidden, %{title: "Kept back, renamed"}, authorize?: false)
      Ash.update!(plain, %{title: "Plain, renamed"}, authorize?: false)

      html = heard(open)
      assert titles(html) == ["Kept back, renamed", "Plain, renamed"]
      assert column(html, "bulletin", "draft") == ["", @draft]

      # and the page that authorizes, for the same person
      html = heard(closed)
      assert titles(html) == ["Plain, renamed"]
      assert column(html, "bulletin", "draft") == ["Not available"]
    end

    test "speaks of a record that only it shows", %{conn: conn} do
      {:ok, open, _html} = conn |> as(:reader) |> live("/support/open/bulletins")
      {:ok, closed, _html} = conn |> as(:reader) |> live("/support/bulletins")

      Ash.create!(Bulletin, %{title: "Another secret", hidden?: true}, authorize?: false)

      assert notice(heard(open)) == @notice
      assert notice(heard(closed)) == ""
    end
  end

  describe "a table that does not follow" do
    test "is a page that says `live?: false`: it listens to nothing and stays as it was read",
         %{conn: conn, plain: plain} do
      {:ok, still, html} = conn |> as(:admin) |> live("/support/still/bulletins")
      assert listeners(Bulletin) == 0
      assert "Plain" in titles(html)

      # nor do the tables nested in its rows
      expand(still, "bulletin", plain.id)
      toggle(still, "bulletin", plain.id, "replies")
      assert listeners(Reply) == 0

      Ash.update!(plain, %{title: "Plain, renamed"}, authorize?: false)
      assert "Plain" in titles(heard(still))
    end

    test "is a named table that says `live? false`", %{conn: conn, plain: plain} do
      {:ok, quiet, _html} = conn |> as(:admin) |> live("/support/quiet/bulletins")
      assert listeners(Bulletin) == 0

      Ash.update!(plain, %{title: "Plain, renamed"}, authorize?: false)
      assert "Plain" in titles(heard(quiet), "bulletin_quiet")
    end

    test "is refused where it is told to follow a resource that announces nothing",
         %{conn: conn} do
      error =
        assert_raise ArgumentError, fn -> conn |> as(:admin) |> live("/support/stamps") end

      assert error.message =~
               "cannot build the table of Demo.Support.Live.Stamp: it is asked to show live " <>
                 "updates (`live?: true`), but Demo.Support.Live.Stamp announces none: add " <>
                 "`live? true` to its `table` block."
    end
  end

  describe "a table without a tenant" do
    test "listens to the one topic of its resource", %{conn: conn} do
      assert Notifier.topic(Bulletin, nil) == "ash_data_table:Demo.Support.Live.Bulletin"
      # a resource without multitenancy has no other
      assert Notifier.topic(Bulletin, "some-tenant") ==
               "ash_data_table:Demo.Support.Live.Bulletin"

      {:ok, _view, _html} = conn |> as(:admin) |> live("/support/bulletins")
      assert listeners(Bulletin) == 1
    end
  end

  describe "a picker" do
    setup %{conn: conn, plain: plain} do
      reply = Ash.Seed.seed!(Reply, %{body: "A reply", bulletin_id: plain.id})
      {:ok, view, _html} = conn |> as(:admin) |> live("/support/replies")
      %{view: view, reply: reply}
    end

    test "follows the changes of the resource it shows, and stops when it is closed",
         %{view: view, reply: reply, hidden: hidden} do
      assert {listeners(Reply), listeners(Bulletin)} == {1, 0}

      pick(view, "reply", reply.id, "bulletin")
      html = render(view)
      assert titles(html, "reply-pick-bulletin") == ["Kept back", "Plain"]
      assert {listeners(Reply), listeners(Bulletin)} == {1, 1}

      Ash.update!(hidden, %{title: "Kept back, renamed"}, authorize?: false)
      html = heard(view)
      assert titles(html, "reply-pick-bulletin") == ["Kept back, renamed", "Plain"]
      # the row of the record that is chosen now is still marked
      assert length(attribute(html, "[id^='reply-pick-bulletin-row-'][data-current]", "id")) == 1

      cancel_picker(view, "reply")
      assert {listeners(Reply), listeners(Bulletin)} == {1, 0}
    end

    test "holds the row it is open for", %{view: view, reply: reply} do
      pick(view, "reply", reply.id, "bulletin")

      Ash.update!(reply, %{body: "A reply, edited"}, authorize?: false)
      assert column(heard(view), "reply", "body") == ["A reply"]

      html = cancel_picker(view, "reply")
      assert column(html, "reply", "body") == ["A reply, edited"]
    end
  end

  describe "a primary key of two attributes" do
    setup %{conn: conn} do
      first = Ash.Seed.seed!(Pin, %{board: "north", slot: 1, note: "First"})
      second = Ash.Seed.seed!(Pin, %{board: "north", slot: 2, note: "Second"})
      {:ok, view, html} = conn |> as(:admin) |> live("/support/pins")
      assert column(html, "pin", "note") == ["First", "Second"]
      %{view: view, first: first, second: second}
    end

    test "is announced whole", %{first: first} do
      Phoenix.PubSub.subscribe(Demo.PubSub, Notifier.topic(Pin, nil))

      Ash.update!(first, %{note: "First, edited"}, authorize?: false)

      assert_receive {:ash_data_table_changed, _resource, _type, _key, _tenant} = message
      assert message == {:ash_data_table_changed, Pin, :update, %{board: "north", slot: 1}, nil}
    end

    test "names the row that is updated, and the row that goes", %{
      view: view,
      first: first,
      second: second
    } do
      Ash.update!(second, %{note: "Second, edited"}, authorize?: false)
      assert column(heard(view), "pin", "note") == ["First", "Second, edited"]

      Ash.destroy!(first, authorize?: false)
      html = heard(view, ["north-1"])
      assert column(html, "pin", "note") == ["Second, edited"]
      assert column(html, "pin", "slot") == ["2"]

      # one that is no row of the page is spoken of
      Ash.create!(Pin, %{board: "south", slot: 1, note: "New"}, authorize?: false)
      html = heard(view)
      assert column(html, "pin", "note") == ["Second, edited"]
      assert notice(html, "pin") == @notice
    end
  end
end
