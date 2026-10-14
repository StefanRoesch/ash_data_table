defmodule DemoWeb.Tables.UncheckedTableTest do
  @moduledoc """
  A table that is mounted without authorization
  (`ash_table "/path", Resource, authorize?: false`), and one that is placed
  so (`<AshTable.table authorize?={false}>`).

  The resources are of a domain that authorizes, and their policies and
  field policies allow nobody anything (`test/support/unchecked_tables.ex`):
  whatever a table of them reads, shows or runs here, it does because its
  page was mounted without authorization. Each test is of one way a table
  reaches Ash. The same pages mounted as the domain says answer "not
  found".
  """
  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Support.Closed.{Case, Entry, Keeper, Remark}

  @code "code-7h6g5f4d"

  setup do
    on_exit(fn -> Demo.Support.Ets.stop([Case, Entry, Keeper]) end)

    seed = fn resource, values -> Ash.Seed.seed!(resource, values) end

    ada = seed.(Keeper, %{name: "Ada"})
    bob = seed.(Keeper, %{name: "Bob"})

    first =
      seed.(Case, %{
        title: "Alpha",
        keeper_id: ada.id,
        code: @code,
        remark: %Remark{text: "urgent"}
      })

    second = seed.(Case, %{title: "Beta"})
    for text <- ["one", "two"], do: seed.(Entry, %{text: text, case_id: first.id})
    seed.(Entry, %{text: "other", case_id: second.id})

    %{ada: ada, bob: bob, first: first, second: second}
  end

  defp stored(%Case{id: id}), do: Ash.get!(Case, id, authorize?: false)
  defp cases, do: Case |> Ash.read!(authorize?: false) |> Enum.map(& &1.title) |> Enum.sort()
  defp entries, do: Entry |> Ash.read!(authorize?: false) |> Enum.map(& &1.text) |> Enum.sort()
  defp titles(html, id \\ "case"), do: column(html, id, "title")
  defp full_view(html, id), do: List.first(attribute(html, "[id='#{id}-full-view']", "href"))

  defp open_entries(view, key) do
    expand(view, "case", key)
    toggle(view, "case", key, "entries")
  end

  describe "the resources themselves" do
    test "allow nobody anything: Ash refuses the read, and the page mounted as the domain says is not found",
         %{conn: conn} do
      assert {:error, %Ash.Error.Forbidden{}} = Ash.read(Case, actor: %{role: :admin})
      assert {:error, %Ash.Error.Forbidden{}} = Ash.read(Entry)

      assert_error_sent 404, fn -> get(conn, "/support/closed/cases") end
      assert_error_sent 404, fn -> get(conn, "/support/closed/entries") end
    end
  end

  describe "a page mounted with `authorize?: false`" do
    setup %{conn: conn} do
      {:ok, view, html} = live(conn, "/support/open/cases")
      %{view: view, html: html}
    end

    test "reads its records, as it is first rendered and once it is live", %{
      conn: conn,
      html: html
    } do
      rendered = conn |> get("/support/open/cases") |> html_response(200)

      assert titles(rendered) == ["Alpha", "Beta"]
      assert titles(html) == ["Alpha", "Beta"]
      assert text(html, "#case-range") == "1–2 of 2"
    end

    test "shows every public field, a field policy or not: no column is left out", %{html: html} do
      assert headers(html, "case") == ["Title", "Keeper", "Code", "Remark", "Entry count"]
      refute html =~ "Not available"
    end

    test "shows an aggregate over records nobody may read, and the label of a related record", %{
      html: html,
      first: first,
      second: second
    } do
      assert text(html, cell("case", first.id, "entry_count")) == "2"
      assert text(html, cell("case", second.id, "entry_count")) == "1"
      assert text(html, cell("case", first.id, "keeper")) == "Ada"
      assert text(html, cell("case", first.id, "remark")) == "Text: urgent"
    end

    test "reads again when it is sorted and when it is filtered", %{view: view} do
      view |> element("#case-head-title") |> render_click()
      render_async(view)
      view |> element("#case-head-title") |> render_click()
      assert titles(render_async(view)) == ["Beta", "Alpha"]

      html = filter(view, "case", "title", v: "Alp")
      assert titles(html) == ["Alpha"]
      assert text(html, "#case-range") == "1–1 of 1"
    end

    test "offers everything the table has: editors, row actions, table actions, create, selecting",
         %{html: html, first: first} do
      assert editors(html, "case") == ~w(title keeper code remark)
      assert actions(html, "case", first.id) == ["Close", "Retitle", "Stamp", "Destroy"]
      assert table_actions(html, "case") == ["Count"]
      assert text(html, "#case-create") == "New case"

      assert selection(html, "case").buttons |> Enum.take(-4) ==
               ["Close", "Retitle", "Stamp", "Destroy"]
    end

    test "saves a cell", %{view: view, first: first} do
      html = save(view, "case", first.id, "title", "Alpha one")

      assert_reply view, %{ok: true}
      assert failure(html, "case", first.id, "title") == nil
      assert text(html, cell("case", first.id, "title")) == "Alpha one"
      assert stored(first).title == "Alpha one"
    end

    test "answers with the value of a sensitive cell, which is masked all the same", %{
      view: view,
      html: html,
      first: first
    } do
      assert masked(html, "case", first.id, "code").mask == "••••••"
      refute html =~ @code

      reveal(view, "case", first.id, "code")
      assert_reply view, %{ok: true, value: @code}
    end

    test "opens the picker of a reference cell, which shows the records to choose from, and saves the choice",
         %{view: view, first: first, bob: bob} do
      html = pick(view, "case", first.id, "keeper")
      assert_reply view, %{ok: true}

      assert %{table: table} = picker(html, "case")
      assert column(html, table, "name") == ["Ada", "Bob"]

      html = picked(view, "case", bob.id)

      assert_reply view, %{ok: true}
      assert picker(html, "case") == nil
      assert text(html, cell("case", first.id, "keeper")) == "Bob"
      assert stored(first).keeper_id == bob.id
    end

    test "opens the side panel of a map cell, and saves it", %{view: view, first: first} do
      html = edit(view, "case", first.id, "remark")

      assert_reply view, %{ok: true}
      assert Enum.map(panel(html, "case").fields, & &1.name) == ["remark", "remark.text"]

      html = run_panel(view, "case", remark: %{"_present" => "", "text" => "settled"})

      assert panel(html, "case") == nil
      assert stored(first).remark.text == "settled"
    end

    test "runs a row action that runs at once", %{view: view, first: first} do
      html = act(view, "case", first.id, "close")

      assert_reply view, %{ok: true}
      assert action_failure(html, "case", first.id) == nil
      assert stored(first).closed == true
    end

    test "runs a row action from its panel, whose field of a related record shows what is chosen",
         %{view: view, first: first, bob: bob} do
      html = act(view, "case", first.id, "retitle")

      assert_reply view, %{ok: true, panel: true}
      assert panel(html, "case").heading == "Retitle: Alpha"

      assert %{control: "reference", chosen: "Ada"} =
               Enum.find(panel(html, "case").fields, &(&1.name == "keeper_id"))

      # the picker of the field, and the record that is chosen in it
      html = pick_input(view, "case", "keeper_id")
      assert column(html, picker(html, "case").table, "name") == ["Ada", "Bob"]

      html = picked(view, "case", bob.id)
      assert_reply view, %{ok: true}

      assert %{chosen: "Bob"} = Enum.find(panel(html, "case").fields, &(&1.name == "keeper_id"))

      html = run_panel(view, "case", title: "Alpha two")

      assert panel(html, "case") == nil
      assert %{title: "Alpha two", keeper_id: keeper_id} = stored(first)
      assert keeper_id == bob.id
    end

    test "runs a generic action on a row, and one on the table", %{view: view, first: first} do
      html = act(view, "case", first.id, "stamp")
      assert_reply view, %{ok: true}
      assert result(html, "case") == "Stamp: stamped Alpha"

      html = table_act(view, "case", "count")
      assert result(html, "case") == "Count: 2"
    end

    test "destroys a record", %{view: view, first: first} do
      html = act(view, "case", first.id, "destroy")

      assert_reply view, %{ok: true, removed: true}
      assert titles(html) == ["Beta"]
      assert cases() == ["Beta"]
    end

    test "creates a record", %{view: view} do
      html = open_create(view, "case")
      assert panel(html, "case").heading == "New case"

      html = run_panel(view, "case", title: "Gamma")

      assert panel(html, "case") == nil
      assert "Gamma" in titles(html)
      assert cases() == ["Alpha", "Beta", "Gamma"]
    end

    test "runs an action on the selected rows, and on all that match", %{
      view: view,
      first: first,
      second: second
    } do
      html = run_bulk(view, "case", "close", [first.id])

      assert bulk_result(html, "case") == %{summary: "Close: 1 done.", failures: []}
      assert stored(first).closed
      refute stored(second).closed

      html = run_bulk(view, "case", "close", :all)

      assert bulk_result(html, "case") == %{summary: "Close: 2 done.", failures: []}
      assert stored(second).closed
    end

    test "offers the relationship of its rows, and the nested table reads its records", %{
      view: view,
      first: first,
      second: second
    } do
      html = expand(view, "case", first.id)
      assert lines(html, "case", first.id) == ["Entries"]

      html = toggle(view, "case", first.id, "entries")
      assert column(html, nested("case", first.id, "entries"), "text") == ["one", "two"]

      html = open_entries(view, second.id)
      assert column(html, nested("case", second.id, "entries"), "text") == ["other"]
    end

    test "the nested table is offered everything too, saves a cell, and runs its table action", %{
      view: view,
      first: first
    } do
      html = open_entries(view, first.id)
      id = nested("case", first.id, "entries")

      assert editors(html, id) == ["text"]
      assert line_buttons(html, "case", first.id, "entries") == ["New entry", "Tally"]

      [entry | _] = Entry |> Ash.read!(authorize?: false) |> Enum.filter(&(&1.text == "one"))
      html = save(view, id, entry.id, "text", "one more")

      assert text(html, cell(id, entry.id, "text")) == "one more"
      assert "one more" in entries()

      html = table_act(view, id, "tally", on: "case-row-#{first.id}-l-entries-do-tally")
      assert result(html, id) == "Tally: 3"
    end

    test "a record created in the nested table is joined to its row, which is read for it", %{
      view: view,
      first: first
    } do
      open_entries(view, first.id)
      id = nested("case", first.id, "entries")

      view |> element("[id='case-row-#{first.id}-l-entries-create']") |> render_click()
      html = run_panel(view, id, text: "three")

      assert panel(html, id) == nil
      assert column(html, id, "text") == ["three", "one", "two"]

      assert [%{case_id: case_id}] =
               Entry |> Ash.read!(authorize?: false) |> Enum.filter(&(&1.text == "three"))

      assert case_id == first.id
    end

    test "the nested table links to its full view on a page that is mounted without authorization too",
         %{view: view, first: first} do
      html = open_entries(view, first.id)
      link = full_view(html, nested("case", first.id, "entries"))

      assert link =~ ~r{^/support/open/entries\?}
      refute link =~ "/closed/"
    end

    test "the full view reads the records of the row, and names the row", %{
      conn: conn,
      view: view,
      first: first
    } do
      html = open_entries(view, first.id)
      link = full_view(html, nested("case", first.id, "entries"))

      {:ok, view, html} = live(conn, link)

      assert column(html, "entry", "text") == ["one", "two"]
      assert text(html, "#entry-related-heading") =~ "Alpha"
      # and the way back is to the page of the row's table that is mounted so
      assert attribute(html, "#entry-related-heading a", "href") == ["/support/open/cases"]

      # a record created there is created under that row
      view |> element("#entry-create") |> render_click()
      html = run_panel(view, "entry", text: "three")

      assert column(html, "entry", "text") == ["three", "one", "two"]
    end

    test "the page of the entries by itself reads every entry", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/support/open/entries")

      assert column(html, "entry", "text") == ["one", "other", "two"]
    end
  end

  describe "where a link leads" do
    test "a table without authorization is sent to a page mounted without, and any other never to one" do
      router = DemoWeb.Router

      assert AshTable.Routes.table(router, Entry, :default, false) ==
               %{path: "/support/open/entries", id: "entry"}

      for told <- [nil, true] do
        assert AshTable.Routes.table(router, Entry, :default, told) ==
                 %{path: "/support/closed/entries", id: "entry"}
      end

      # the keepers are mounted without authorization alone: no other table links there
      assert AshTable.Routes.table(router, Keeper, :default, false) ==
               %{path: "/support/open/keepers", id: "keeper"}

      assert AshTable.Routes.table(router, Keeper, :default, nil) == nil
      # nor one of another table of the resource than the one that is mounted
      assert AshTable.Routes.table(router, Keeper, :compact, false) == nil
    end
  end

  describe "the option is the router's alone" do
    test "nothing a browser sends switches authorization off: not the URL, not the session", %{
      conn: conn
    } do
      for query <- ["authorize?=false", "authorize=false", "case[authorize?]=false"] do
        assert_error_sent 404, fn -> get(conn, "/support/closed/cases?" <> query) end
      end

      conn =
        Phoenix.ConnTest.init_test_session(conn, %{
          "authorize?" => false,
          "assigns" => %{authorize?: false, authorize_given: false}
        })

      assert_error_sent 404, fn -> get(conn, "/support/closed/cases") end
    end

    test "is checked when the router is compiled: `true`, `false`, or nothing" do
      assert AshTable.Router.__live_opts__(Case, authorize?: false)[:metadata].ash_table.authorize? ==
               false

      assert AshTable.Router.__live_opts__(Case, authorize?: true)[:metadata].ash_table.authorize? ==
               true

      assert AshTable.Router.__live_opts__(Case, [])[:metadata].ash_table.authorize? == nil

      assert_raise ArgumentError,
                   "the :authorize? of ash_table must be `true` or `false`, got: \"no\"",
                   fn -> AshTable.Router.__live_opts__(Case, authorize?: "no") end
    end
  end

  describe "a table placed with `authorize?={false}`, beside one placed without it" do
    test "the one reads and saves, the other renders nothing", %{conn: conn, first: first} do
      {:ok, view, html} = live(conn, "/support/unchecked")

      assert titles(html, "unchecked") == ["Alpha", "Beta"]
      assert titles(html, "checked") == []
      assert attribute(html, "#checked", "hidden") == [""]

      html = save(view, "unchecked", first.id, "title", "Alpha one")
      assert text(html, cell("unchecked", first.id, "title")) == "Alpha one"

      # an event to the table that authorizes does nothing
      forge(view, "unchecked", "save", %{"row" => first.id, "column" => "title", "value" => "x"})

      assert stored(first).title == "x"
    end

    test "its nested table links to the page that is mounted without authorization", %{
      conn: conn,
      first: first
    } do
      {:ok, view, _html} = live(conn, "/support/unchecked")

      expand(view, "unchecked", first.id)
      html = toggle(view, "unchecked", first.id, "entries")
      id = nested("unchecked", first.id, "entries")

      assert column(html, id, "text") == ["one", "two"]
      assert full_view(html, id) =~ ~r{^/support/open/entries\?}
    end
  end
end
