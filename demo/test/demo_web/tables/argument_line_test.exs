defmodule DemoWeb.Tables.ArgumentLineTest do
  @moduledoc """
  The argument line: the inputs above a table's rows in which a person gives
  the arguments of the table's read action and those its calculation columns
  ask for.

  The tables are of resources that exist for the tests only
  (`test/support/argument_tables.ex`), mounted at `/support/stocks`. The
  stock is read through `search`, which takes an argument of every kind the
  line has an input for and requires one of them, `at_least`. Three columns
  show the calculation `amount_in`: one fixes its rate, two ask for it.
  """
  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Support.Asked.{Lot, Shelf, Stock}

  @admin %{role: :admin}

  setup %{conn: conn} do
    [attic, basement] =
      for {name, closed} <- [{"Attic", false}, {"Basement", true}] do
        Ash.create!(Shelf, %{name: name, closed: closed})
      end

    stocks =
      for {name, amount, kind} <- [
            {"apple", 1, :plain},
            {"banana", 5, :fancy},
            {"cherry", 10, :plain},
            {"date", 20, :plain}
          ] do
        Ash.create!(Stock, %{name: name, amount: amount, kind: kind, shelf_id: attic.id},
          authorize?: false
        )
      end

    [apple | _] = stocks

    for {code, size} <- [{"L1", 1}, {"L2", 5}, {"L3", 9}, {"M1", 3}] do
      Ash.create!(Lot, %{code: code, size: size, stock_id: apple.id})
    end

    on_exit(fn -> Demo.Support.Ets.stop([Stock, Lot, Shelf]) end)

    %{
      conn: as(conn, reader: @admin),
      apple: apple,
      stocks: Map.new(stocks, &{&1.name, &1}),
      attic: attic,
      basement: basement
    }
  end

  defp as(conn, assigns),
    do: Phoenix.ConnTest.init_test_session(conn, %{"assigns" => Map.new(assigns)})

  defp argument(html, id \\ "stock", name),
    do: Enum.find(arguments(html, id), &(&1.name == name))

  defp stored!(stock), do: Ash.get!(Stock, stock.id, authorize?: false)

  describe "a read that is on its way when the argument it requires is emptied" do
    setup do
      on_exit(&Demo.Support.Hold.release/0)
    end

    test "is not waited for, and what it brings is not shown: the table asks for the argument, and reports no failure",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, "/support/stocks")
      assert column(argue(view, "stock", a: %{"at_least" => "1"}), "stock", "name") != []

      Demo.Support.Hold.hold()

      # a read starts, and is held back
      html =
        view
        |> form("#stock-arguments", %{"arguments" => %{"a" => %{"at_least" => "5"}}})
        |> render_change()

      assert attribute(html, "#stock-table", "aria-busy") == ["true"]

      # the argument is emptied while it runs
      html =
        view
        |> form("#stock-arguments", %{"arguments" => %{"a" => %{"at_least" => ""}}})
        |> render_change()

      assert text(html, "#stock-fill") == "Fill in At least to see records."
      assert attribute(html, "#stock-table", "aria-busy") == []

      {html, log} =
        ExUnit.CaptureLog.with_log(fn ->
          Demo.Support.Hold.release()
          render_async(view)
        end)

      # the read came back, or was given up: either way nothing of it is shown
      assert text(html, "#stock-fill") == "Fill in At least to see records."
      assert text(html, "#stock-error") == nil
      assert column(html, "stock", "name") == []
      assert attribute(html, "#stock-table", "aria-busy") == []
      refute log =~ "failed"

      # and the table reads again when the argument is given
      assert column(argue(view, "stock", a: %{"at_least" => "5"}), "stock", "name") ==
               ["cherry", "date"]
    end
  end

  describe "the line" do
    setup %{conn: conn} do
      {:ok, view, html} = live(conn, "/support/stocks")
      %{view: view, html: html}
    end

    test "has an input for every public argument of the read action, in the action's order, then what the columns ask for",
         %{html: html} do
      assert Enum.map(arguments(html, "stock"), &{&1.name, &1.label, &1.control}) == [
               {"term", "Search for", "text"},
               {"at_least", "At least", "number"},
               {"kind", "Kind", "select"},
               {"any_kind?", "Any kind?", "checkbox"},
               {"on", "On", "date"},
               {"at", "At", "datetime-local"},
               {"key", "Key", "text"},
               {"names", "Names", "list"},
               {"kinds", "Kinds", "choices"},
               {"amount_asked-rate", "Amount asked: Rate", "number"},
               {"amount_asked-currency", "Amount asked: Currency", "select"},
               {"amount_fn-rate", "Exchange rate", "number"}
             ]

      # a private argument, and one the line has no input for, are not on it
      refute html =~ "stock-arg-secret"
      refute html =~ "stock-arg-where"
      # nor is an argument the block fixes
      refute html =~ "stock-arg-amount_in-rate"
    end

    test "starts each input with its argument's default, and marks what cannot be empty",
         %{html: html} do
      assert Enum.map(arguments(html, "stock"), &{&1.name, &1.value, &1.required?}) == [
               {"term", "", false},
               {"at_least", "", true},
               {"kind", "plain", false},
               {"any_kind?", "false", false},
               {"on", "", false},
               {"at", "", false},
               {"key", "", false},
               {"names", [], false},
               {"kinds", [], false},
               # the default of its `ask`
               {"amount_asked-rate", "3", true},
               # the default the argument has in the resource
               {"amount_asked-currency", "eur", false},
               # a function of the page's assigns, which hold no rate here
               {"amount_fn-rate", "5", true}
             ]
    end

    test "is a form above the grid whose inputs are labelled, ordinary tab stops", %{html: html} do
      # before the grid in the page
      {line, _} = :binary.match(html, ~s(id="stock-arguments"))
      {grid, _} = :binary.match(html, ~s(id="stock-grid"))
      assert line < grid

      assert attribute(html, "#stock-arguments", "phx-change") == [
               "ash_data_table:stock:arguments"
             ]

      assert attribute(html, "#stock-arguments", "phx-submit") == [
               "ash_data_table:stock:arguments"
             ]

      # every control of one value has a label that names it
      for name <- ~w(term at_least kind any_kind? on at key amount_asked-rate) do
        assert attribute(html, "#stock-arguments label[for='stock-arg-#{name}']", "for") ==
                 ["stock-arg-#{name}"]
      end

      # a control of several is a group, named by its label
      for name <- ~w(names kinds) do
        assert attribute(html, "[id='stock-arg-#{name}']", "role") == ["group"]

        assert attribute(html, "[id='stock-arg-#{name}']", "aria-labelledby") ==
                 ["stock-arg-#{name}-label"]
      end

      # none of them is taken out of the tab order
      assert attribute(html, "#stock-arguments input, #stock-arguments select", "tabindex") == []
      # and the line has no button that runs it
      assert attribute(html, "#stock-arguments button[type=submit]", "type") == []
    end

    test "sends what is typed when its input is left, not at every key", %{html: html} do
      for name <- ~w(term at_least on at key amount_asked-rate amount_fn-rate) do
        assert attribute(html, "[id='stock-arg-#{name}']", "phx-debounce") == ["blur"]
      end

      # a choice is applied at once
      for name <- ~w(kind any_kind? amount_asked-currency) do
        assert attribute(html, "[id='stock-arg-#{name}']", "phx-debounce") == []
      end
    end

    test "marks what cannot be empty for the eye too", %{html: html} do
      assert attribute(html, "label[for='stock-arg-at_least'] > span", "aria-hidden") == ["true"]
      assert text(html, "label[for='stock-arg-at_least'] > span[aria-hidden]") == "*"
      assert attribute(html, "label[for='stock-arg-term'] > span", "aria-hidden") == []
      assert attribute(html, "#stock-arg-at_least", "aria-required") == ["true"]
    end
  end

  describe "a table without arguments" do
    test "has no line", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/support/memos")

      assert arguments(html, "memo") == nil
      refute html =~ "data-arguments"
      refute html =~ "memo-fill"
    end
  end

  describe "an argument the read action requires, while it is empty" do
    setup %{conn: conn} do
      {:ok, view, html} = live(conn, "/support/stocks")
      %{view: view, html: html}
    end

    test "is asked for in place of the rows: no error, and not \"No records\"", %{html: html} do
      assert text(html, "#stock-fill") == "Fill in At least to see records."
      assert text(html, "#stock-empty") == nil
      assert text(html, "#stock-error") == nil
      assert column(html, "stock", "name") == []
      # no pages of what was not read
      assert text(html, "#stock-range") == nil
      # the grid is there, with its header and its filters
      assert "Name" in headers(html, "stock")
    end

    test "is read out", %{html: html} do
      assert announcement(html, "stock") == "Fill in At least to see records."
    end

    test "the rows come once it is filled in, and go again when it is emptied", %{view: view} do
      html = argue(view, "stock", a: %{"at_least" => "0"})

      assert column(html, "stock", "name") == ["apple", "cherry"]
      assert text(html, "#stock-fill") == nil
      assert text(html, "#stock-range") == "1–2 of 3"
      assert announcement(html, "stock") == "3 results"

      html = argue(view, "stock", a: %{"at_least" => ""})

      assert text(html, "#stock-fill") == "Fill in At least to see records."
      assert column(html, "stock", "name") == []
      assert text(html, "#stock-empty") == nil
      assert announcement(html, "stock") == "Fill in At least to see records."
    end

    test "something else that is changed meanwhile reads nothing either", %{view: view} do
      html = argue(view, "stock", a: %{"term" => "an"})

      assert text(html, "#stock-fill") == "Fill in At least to see records."
      assert argument(html, "term").value == "an"
      assert column(html, "stock", "name") == []
    end
  end

  describe "what a person gives the read action" do
    setup %{conn: conn} do
      {:ok, view, _html} = live(conn, "/support/stocks?stock[a][at_least]=0")
      %{view: view}
    end

    test "is given to it: text, a number, a choice, a box", %{view: view} do
      html = argue(view, "stock", a: %{"at_least" => "0", "term" => "an"})
      # the kind is "plain" until another is chosen
      assert column(html, "stock", "name") == []

      html = argue(view, "stock", a: %{"at_least" => "0", "term" => "an", "kind" => "fancy"})
      assert column(html, "stock", "name") == ["banana"]

      html = argue(view, "stock", a: %{"at_least" => "6", "term" => "", "any_kind?" => "true"})
      assert column(html, "stock", "name") == ["cherry", "date"]

      assert argument(html, "any_kind?").value == "true"
      assert argument(html, "at_least").value == "6"
    end

    test "a multiple choice gives the values that are ticked", %{view: view} do
      html = argue(view, "stock", a: %{"any_kind?" => "true", "kinds" => ["", "fancy"]})

      assert column(html, "stock", "name") == ["banana"]
      assert argument(html, "kinds").value == ["fancy"]
    end

    test "is announced as a change of the filters is", %{view: view} do
      html = argue(view, "stock", a: %{"at_least" => "6"})
      assert announcement(html, "stock") == "2 results"
    end

    test "starts at the first page again, and leaves the sort and the filters", %{conn: conn} do
      {:ok, view, html} =
        live(
          conn,
          "/support/stocks?stock[a][at_least]=0&stock[a][any_kind%3F]=true&stock[sort]=-name&stock[page]=2"
        )

      assert column(html, "stock", "name") == ["banana", "apple"]

      html = argue(view, "stock", a: %{"at_least" => "5", "any_kind?" => "true"})

      assert column(html, "stock", "name") == ["date", "cherry"]

      assert assert_patch(view) ==
               "/support/stocks?stock[a][any_kind%3F]=true&stock[a][at_least]=5&stock[sort]=-name"
    end

    test "a selection is given up with the arguments it was made under", %{view: view} do
      select(view, "stock", :all)
      argue(view, "stock", a: %{"at_least" => "6"})
      assert_push_event view, "ash_data_table:select", %{table: "stock", all: false, rows: []}
    end

    test "nothing from the outside reaches an argument that is not on the line", %{conn: conn} do
      # `search` returns nothing once its private argument is given
      {:ok, _view, html} =
        live(conn, "/support/stocks?stock[a][at_least]=0&stock[a][secret]=x&stock[a][where][x]=1")

      assert column(html, "stock", "name") == ["apple", "cherry"]
    end
  end

  describe "an argument that is given value by value" do
    setup %{conn: conn} do
      {:ok, view, _html} =
        live(conn, "/support/stocks?stock[a][at_least]=0&stock[a][any_kind%3F]=true")

      %{view: view}
    end

    test "has a row per value, a button that adds one and one each that takes it away",
         %{view: view} do
      html = view |> element("#stock-arg-names-add") |> render_click()

      # an empty row holds no value: nothing is read for it
      assert argument(html, "names").value == [""]
      assert column(html, "stock", "name") == ["apple", "banana"]
      assert_push_event view, "ash_data_table:focus", %{table: "stock", cell: "stock-arg-names-0"}

      assert attribute(html, "#stock-arg-names-0", "aria-label") == ["Names 1"]
      assert attribute(html, "#stock-arg-names-0-remove", "aria-label") == ["Remove Names 1"]
      assert text(html, "#stock-arg-names-add") == "Add value"

      html = argue(view, "stock", a: %{"any_kind?" => "true", "names" => ["", "date"]})
      assert column(html, "stock", "name") == ["date"]

      view |> element("#stock-arg-names-add") |> render_click()

      html =
        argue(view, "stock", a: %{"any_kind?" => "true", "names" => ["", "date", "banana"]})

      assert column(html, "stock", "name") == ["banana", "date"]
      assert argument(html, "names").value == ["date", "banana"]

      view |> element("#stock-arg-names-0-remove") |> render_click()
      html = render_async(view)

      assert column(html, "stock", "name") == ["banana"]
      assert argument(html, "names").value == ["banana"]
      assert_push_event view, "ash_data_table:focus", %{cell: "stock-arg-names-0"}

      view |> element("#stock-arg-names-0-remove") |> render_click()
      html = render_async(view)

      assert column(html, "stock", "name") == ["apple", "banana"]
      assert argument(html, "names").value == []
      assert_push_event view, "ash_data_table:focus", %{cell: "stock-arg-names-add"}
    end

    test "is in the URL as the list of its values", %{conn: conn, view: view} do
      view |> element("#stock-arg-names-add") |> render_click()
      argue(view, "stock", a: %{"any_kind?" => "true", "names" => ["", "date"]})

      path = assert_patch(view)

      assert path ==
               "/support/stocks?stock[a][any_kind%3F]=true&stock[a][at_least]=0&stock[a][names][]=date"

      {:ok, _view, html} = live(conn, path)
      assert column(html, "stock", "name") == ["date"]
      assert argument(html, "names").value == ["date"]
    end

    test "an event that names no such argument, or no such row, changes nothing", %{view: view} do
      before = render(view)

      for {event, params} <- [
            {"argument_add", %{"argument" => "term"}},
            {"argument_add", %{"argument" => "nothing"}},
            {"argument_add", %{}},
            {"argument_remove", %{"argument" => "names", "at" => "0"}},
            {"argument_remove", %{"argument" => "names", "at" => "x"}},
            {"argument_remove", %{"argument" => "kinds", "at" => "0"}}
          ] do
        forge(view, "stock", event, params)
      end

      assert arguments(render(view), "stock") == arguments(before, "stock")
    end
  end

  describe "a value Ash refuses" do
    setup %{conn: conn} do
      {:ok, view, _html} = live(conn, "/support/stocks?stock[a][at_least]=0")
      %{view: view}
    end

    test "is shown at its input with the action's message, and the rows stay", %{view: view} do
      html = argue(view, "stock", a: %{"at_least" => "-1"})

      assert %{value: "-1", errors: ["must be greater than or equal to 0"]} =
               argument(html, "at_least")

      assert attribute(html, "#stock-arg-at_least", "aria-invalid") == ["true"]

      assert attribute(html, "#stock-arg-at_least", "aria-describedby") == [
               "stock-arg-at_least-error"
             ]

      # the rows are those of the argument as it was
      assert column(html, "stock", "name") == ["apple", "cherry"]
      assert text(html, "#stock-error") == nil
      assert text(html, "#stock-fill") == nil
      # and so is the URL
      refute_patched(view)
    end

    test "is read out", %{view: view} do
      html = argue(view, "stock", a: %{"at_least" => "-1"})

      assert announcement(html, "stock") ==
               "At least: must be greater than or equal to 0"
    end

    test "leaves the other inputs' changes in force", %{view: view} do
      html = argue(view, "stock", a: %{"at_least" => "-1", "term" => "ch"})

      assert column(html, "stock", "name") == ["cherry"]
      assert argument(html, "at_least").errors == ["must be greater than or equal to 0"]
      assert assert_patch(view) == "/support/stocks?stock[a][at_least]=0&stock[a][term]=ch"

      # after the read, too
      html = render(view)
      assert argument(html, "at_least").value == "-1"
    end

    test "is taken once it is put right", %{view: view} do
      argue(view, "stock", a: %{"at_least" => "-1"})
      html = argue(view, "stock", a: %{"at_least" => "6"})

      assert %{value: "6", errors: []} = argument(html, "at_least")
      assert attribute(html, "#stock-arg-at_least", "aria-invalid") == []
      assert column(html, "stock", "name") == ["cherry", "date"]
    end

    test "a text that is no value of the type is refused the same way", %{view: view} do
      html = argue(view, "stock", a: %{"at_least" => "0", "key" => "no key"})

      assert %{value: "no key", errors: ["is invalid"]} = argument(html, "key")
      assert column(html, "stock", "name") == ["apple", "cherry"]
    end

    test "in a URL it is not applied, and is shown in its input", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/support/stocks?stock[a][at_least]=0&stock[a][on]=soon")

      assert %{value: "soon", errors: ["is invalid"]} = argument(html, "on")
      assert column(html, "stock", "name") == ["apple", "cherry"]
      assert text(html, "#stock-error") == nil
    end

    test "for the argument the action requires, in a URL: it is asked for", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/support/stocks?stock[a][at_least]=many")

      assert %{value: "many", errors: ["is invalid"]} = argument(html, "at_least")
      assert text(html, "#stock-fill") == "Fill in At least to see records."
      assert text(html, "#stock-error") == nil
    end
  end

  describe "an argument a column asks for" do
    setup %{conn: conn} do
      {:ok, view, html} = live(conn, "/support/stocks?stock[a][at_least]=0")
      %{view: view, html: html}
    end

    test "is its default until the person chooses", %{html: html} do
      # amounts 1 and 10: fixed at 2, asked and 3, asked and 5
      assert column(html, "stock", "amount_in") == ["2", "20"]
      assert column(html, "stock", "amount_asked") == ["3", "30"]
      assert column(html, "stock", "amount_fn") == ["5", "50"]
    end

    test "is what the person chose from then on, for its column alone", %{view: view} do
      html = argue(view, "stock", c: %{"amount_asked" => %{"rate" => "4"}})

      assert column(html, "stock", "amount_in") == ["2", "20"]
      assert column(html, "stock", "amount_asked") == ["4", "40"]
      assert column(html, "stock", "amount_fn") == ["5", "50"]
      assert argument(html, "amount_asked-rate").value == "4"

      assert assert_patch(view) ==
               "/support/stocks?stock[a][at_least]=0&stock[c][amount_asked][rate]=4"
    end

    test "is read from the URL", %{conn: conn} do
      {:ok, _view, html} =
        live(
          conn,
          "/support/stocks?stock[a][at_least]=0&stock[c][amount_asked][rate]=4&stock[c][amount_fn][rate]=9"
        )

      assert column(html, "stock", "amount_asked") == ["4", "40"]
      assert column(html, "stock", "amount_fn") == ["9", "90"]
    end

    test "starts with what the block's function makes of the page's assigns", %{conn: conn} do
      {:ok, _view, html} =
        conn |> as(reader: @admin, rate: 7) |> live("/support/stocks?stock[a][at_least]=0")

      assert argument(html, "amount_fn-rate").value == "7"
      assert column(html, "stock", "amount_fn") == ["7", "70"]
    end

    test "a value its constraints refuse is shown at its input, and the column stays as it was",
         %{view: view} do
      html = argue(view, "stock", c: %{"amount_asked" => %{"rate" => "0"}})

      assert %{value: "0", errors: ["must be greater than or equal to 1"]} =
               argument(html, "amount_asked-rate")

      assert column(html, "stock", "amount_asked") == ["3", "30"]
      assert text(html, "#stock-error") == nil
      refute_patched(view)

      assert announcement(html, "stock") ==
               "Amount asked: Rate: must be greater than or equal to 1"
    end

    test "cannot be emptied where the calculation requires it", %{view: view} do
      html = argue(view, "stock", c: %{"amount_asked" => %{"rate" => ""}})

      assert %{value: "", errors: ["is required"]} = argument(html, "amount_asked-rate")
      assert column(html, "stock", "amount_asked") == ["3", "30"]
    end

    test "nothing from the outside reaches an argument the block fixes", %{conn: conn} do
      {:ok, _view, html} =
        live(conn, "/support/stocks?stock[a][at_least]=0&stock[c][amount_in][rate]=9")

      assert column(html, "stock", "amount_in") == ["2", "20"]
    end

    test "its column is sorted by with it", %{view: view} do
      argue(view, "stock", a: %{"any_kind?" => "true"})
      view |> element("#stock-sort-amount_asked") |> render_click()
      view |> element("#stock-sort-amount_asked") |> render_click()
      html = render_async(view)

      assert column(html, "stock", "name") == ["date", "cherry"]
      assert attribute(html, "#stock-head-amount_asked", "aria-sort") == ["descending"]
    end

    test "its column is filtered by with it", %{view: view} do
      argue(view, "stock", a: %{"any_kind?" => "true"})

      # rate 3: 3, 15, 30, 60
      html = filter(view, "stock", "amount_asked", o: "at_least", v: "30")
      assert column(html, "stock", "name") == ["cherry", "date"]

      argue(view, "stock", a: %{"any_kind?" => "true"}, c: %{"amount_asked" => %{"rate" => "6"}})
      html = render_async(view)
      # rate 6: 6, 30, 60, 120
      assert column(html, "stock", "name") == ["banana", "cherry"]
      assert text(html, "#stock-range") == "1–2 of 3"
    end
  end

  describe "who is asking" do
    test "a person whose read is refused outright is not asked to fill in anything", %{conn: conn} do
      conn = as(conn, %{})

      assert_raise AshDataTable.NotFoundError, fn -> live(conn, "/support/stocks") end
      assert_error_sent 404, fn -> get(conn, "/support/stocks") end
    end

    test "nor is one who can never run the read action, though no read was run", %{conn: conn} do
      conn = as(conn, reader: %{role: :member})

      assert_raise AshDataTable.NotFoundError, fn -> live(conn, "/support/vaults") end

      {:ok, _view, html} = conn |> as(reader: @admin) |> live("/support/vaults")
      assert text(html, "#vault-fill") == "Fill in Code to see records."
    end
  end

  describe "wherever the table runs its read action for a person" do
    setup %{conn: conn} do
      {:ok, view, html} =
        live(conn, "/support/stocks?stock[a][at_least]=5&stock[a][any_kind%3F]=true")

      %{view: view, html: html}
    end

    test "what is loaded onto the page's records is loaded through it", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/support/stocks?stock[a][at_least]=0")

      # an aggregate, read in a step of its own after the page
      assert column(html, "stock", "lot_count") == ["4", "0"]
    end

    test "a cell is saved on the record as the action returns it", %{view: view, stocks: stocks} do
      html = save(view, "stock", stocks["banana"].id, "name", "blueberry")

      assert text(html, cell("stock", stocks["banana"].id, "name")) == "blueberry"
      assert stored!(stocks["banana"]).name == "blueberry"
    end

    test "a row that the arguments leave out after an edit stays until the next read, and is then none of the table's",
         %{view: view, stocks: stocks} do
      banana = stocks["banana"]

      # below what `at_least` asks for
      html = save(view, "stock", banana.id, "amount", "2")

      assert text(html, cell("stock", banana.id, "amount")) == "2"
      assert column(html, "stock", "name") == ["banana", "cherry"]
      assert stored!(banana).amount == 2

      # the table reads its record through the action, which no longer returns it
      html = save(view, "stock", banana.id, "name", "blueberry")

      assert_reply view, %{ok: false, error: "This record is no longer available."}
      assert stored!(banana).name == "banana"

      assert announcement(html, "stock") ==
               "Name was not saved: This record is no longer available."
    end

    test "a row action runs on the record as the action returns it", %{view: view, stocks: stocks} do
      act(view, "stock", stocks["banana"].id, "rename")
      html = run_panel(view, "stock", %{"name" => "blueberry"})

      assert text(html, cell("stock", stocks["banana"].id, "name")) == "blueberry"
    end

    test "an action on every record that matches runs on what the arguments match",
         %{view: view, stocks: stocks} do
      html = run_bulk(view, "stock", "destroy", :all)

      assert bulk_result(html, "stock").summary == "Destroy: 3 done."
      # the one the arguments leave out is still there
      assert [%{name: "apple"}] = Ash.read!(Stock, authorize?: false)
      assert stored!(stocks["apple"])
    end

    test "an action on selected rows does not run on one the arguments leave out",
         %{view: view, stocks: stocks} do
      html = run_bulk(view, "stock", "destroy", [stocks["apple"].id, stocks["banana"].id])

      assert %{summary: "Destroy: 1 done, 1 not done."} = bulk_result(html, "stock")
      assert stored!(stocks["apple"])
    end
  end

  describe "a nested table" do
    setup %{conn: conn, apple: apple} do
      {:ok, view, _html} = live(conn, "/support/stocks?stock[a][at_least]=0")
      expand(view, "stock", apple.id)
      %{view: view}
    end

    test "is read under a row of a table whose read action requires an argument", %{
      view: view,
      apple: apple
    } do
      html = toggle(view, "stock", apple.id, "lots")
      id = nested("stock", apple.id, "lots")

      assert column(html, id, "code") == ["L1", "L2"]
      assert text(html, "[id='#{id}-range']") == "1–2 of 4"
    end

    test "has the argument line of its own read action, whose state is not in the URL", %{
      view: view,
      apple: apple
    } do
      html = toggle(view, "stock", apple.id, "lots")
      id = nested("stock", apple.id, "lots")

      assert [%{name: "code_like", label: "Code like", control: "text", value: ""}] =
               arguments(html, id)

      html = argue(view, id, a: %{"code_like" => "M"})

      assert column(html, id, "code") == ["M1"]
      assert argument(html, id, "code_like").value == "M"
      refute_patched(view)
      # the table around it is as it was
      assert column(html, "stock", "name") == ["apple", "cherry"]
    end

    test "its inputs are ordinary tab stops too", %{view: view, apple: apple} do
      html = toggle(view, "stock", apple.id, "lots")
      id = nested("stock", apple.id, "lots")

      assert attribute(html, "[id='#{id}-arg-code_like']", "tabindex") == []
    end

    test "whose relationship reads through an action that requires an argument asks for it in place of its rows",
         %{view: view, apple: apple} do
      html = toggle(view, "stock", apple.id, "large_lots")
      id = nested("stock", apple.id, "large_lots")

      assert [%{name: "size", label: "Size", required?: true}] = arguments(html, id)
      assert text(html, "[id='#{id}-fill']") == "Fill in Size to see records."
      assert text(html, "[id='#{id}-empty']") == nil
      assert text(html, "[id='#{id}-error']") == nil
      assert text(html, "[id='#{id}-loading']") == nil
      assert column(html, id, "code") == []

      html = argue(view, id, a: %{"size" => "2"})

      # every one of them: Ash cannot page related records through such an action
      assert column(html, id, "code") == ["L2", "L3", "M1"]
      assert text(html, "[id='#{id}-fill']") == nil
      assert text(html, "[id='#{id}-range']") == nil
    end

    test "a cell of it is saved on the record as its own action returns it", %{
      view: view,
      apple: apple
    } do
      toggle(view, "stock", apple.id, "large_lots")
      id = nested("stock", apple.id, "large_lots")
      html = argue(view, id, a: %{"size" => "2"})
      assert column(html, id, "code") == ["L2", "L3", "M1"]

      [lot] = Lot |> Ash.read!() |> Enum.filter(&(&1.code == "L3"))
      html = save(view, id, lot.id, "code", "L9")

      assert text(html, cell(id, lot.id, "code")) == "L9"
    end
  end

  describe "the full view of a nested table" do
    test "is not linked from a table whose read action requires an argument: its URL could not say what the row was read with",
         %{conn: conn, apple: apple} do
      {:ok, view, _html} = live(conn, "/support/stocks?stock[a][at_least]=0")
      expand(view, "stock", apple.id)
      html = toggle(view, "stock", apple.id, "lots")
      id = nested("stock", apple.id, "lots")

      assert column(html, id, "code") == ["L1", "L2"]
      assert attribute(html, "[id='#{id}-full-view']", "id") == []

      # and a URL that names such a row is no limit
      {:ok, _view, html} = live(conn, "/support/lots?lot[of][stock][lots]=#{apple.id}")
      assert text(html, "#lot-related-heading") == nil
      assert length(column(html, "lot", "code")) == 2
    end
  end

  describe "a picker" do
    setup %{conn: conn, stocks: stocks} do
      {:ok, view, _html} = live(conn, "/support/stocks?stock[a][at_least]=0")
      %{view: view, id: "stock-pick-shelf", apple: stocks["apple"]}
    end

    test "has the argument line of the read action it offers its records through", %{
      view: view,
      id: id,
      apple: apple
    } do
      html = pick(view, "stock", apple.id, "shelf")

      assert Enum.map(arguments(html, id), &{&1.name, &1.control, &1.value}) ==
               [{"term", "text", ""}, {"closed_too?", "checkbox", "false"}]

      assert column(html, id, "name") == ["Attic"]

      html = argue(view, id, a: %{"closed_too?" => "true"})
      assert column(html, id, "name") == ["Attic", "Basement"]

      html = argue(view, id, a: %{"closed_too?" => "true", "term" => "Base"})
      assert column(html, id, "name") == ["Basement"]
      # the table it was opened from keeps its URL
      refute_patched(view)
    end

    test "a record is chosen as the picker's table read it: with what its line holds", %{
      view: view,
      id: id,
      apple: apple,
      basement: basement
    } do
      pick(view, "stock", apple.id, "shelf")
      argue(view, id, a: %{"closed_too?" => "true"})
      select(view, id, [basement.id])

      # as the picker's hook sends it: the line's form
      html =
        forge(view, "stock", "picked", %{
          "confirmed" => false,
          "arguments" =>
            "arguments%5Ba%5D%5Bclosed_too%3F%5D=false&arguments%5Ba%5D%5Bclosed_too%3F%5D=true&arguments%5Ba%5D%5Bterm%5D="
        })

      assert_reply view, %{ok: true}
      assert picker(html, "stock") == nil
      assert stored!(apple).shelf_id == basement.id
    end

    test "a record the action does not return for what the line holds is not chosen", %{
      view: view,
      apple: apple,
      attic: attic,
      basement: basement
    } do
      pick(view, "stock", apple.id, "shelf")

      # the line holds its defaults: a closed shelf is not offered, and is
      # not there to be taken
      html = picked(view, "stock", basement.id)

      assert_reply view, %{ok: false}
      assert stored!(apple).shelf_id == attic.id

      # offered once the line asks for it, and taken as the line holds it:
      # with what it holds then, which says closed shelves too, it is
      # found; with defaults, or a form that is none, it is not
      argue(view, "stock-pick-shelf", a: %{"closed_too?" => "true"})
      select(view, "stock-pick-shelf", [basement.id])

      for sent <- ["%zz", "nonsense", "arguments=x"] do
        html = forge(view, "stock", "picked", %{"arguments" => sent})

        assert_reply view, %{ok: false}
        assert picker(html, "stock").error == "This record is no longer available."
      end

      assert stored!(apple).shelf_id == attic.id
    end
  end

  describe "a picker opened from the action panel" do
    setup %{conn: conn, stocks: stocks} do
      {:ok, view, _html} = live(conn, "/support/stocks?stock[a][at_least]=0")
      act(view, "stock", stocks["apple"].id, "move")
      %{view: view, id: "stock-pick-shelf_id", apple: stocks["apple"]}
    end

    # what the picker's hook sends with a choice: the line's form
    @closed_too "arguments%5Ba%5D%5Bclosed_too%3F%5D=true&arguments%5Ba%5D%5Bterm%5D="

    test "a record chosen under the line's arguments is found again under them when the action runs",
         %{view: view, id: id, apple: apple, basement: basement} do
      pick_input(view, "stock", "shelf_id")
      html = argue(view, id, a: %{"closed_too?" => "true"})
      assert column(html, id, "name") == ["Attic", "Basement"]

      select(view, id, [basement.id])
      html = forge(view, "stock", "picked", %{"arguments" => @closed_too})

      assert_reply view, %{ok: true}
      assert [%{name: "shelf_id", chosen: "Basement"}] = panel(html, "stock").fields

      run_panel(view, "stock", %{"shelf_id" => basement.id})

      assert stored!(apple).shelf_id == basement.id
    end

    test "a key that was put into the form, and that the action does not return as it is, runs nothing",
         %{view: view, apple: apple, attic: attic, basement: basement} do
      html = run_panel(view, "stock", %{"shelf_id" => basement.id})

      assert panel(html, "stock").errors == ["Shelf: This record is no longer available."]
      assert stored!(apple).shelf_id == attic.id
    end
  end

  describe "a table placed in a page of the host's" do
    setup %{conn: conn} do
      {:ok, view, html} = conn |> as(reader: @admin, rate: 7) |> live("/support/asked")
      %{view: view, html: html}
    end

    test "keeps what a person gave its arguments itself", %{view: view, html: html} do
      assert text(html, "#held-fill") == "Fill in At least to see records."

      html = argue(view, "held", a: %{"at_least" => "0"})

      assert column(html, "held", "name") == ["apple", "cherry"]
      assert argument(html, "held", "at_least").value == "0"
      refute_patched(view)

      # through a change of its sort
      view |> element("#held-sort-name") |> render_click()
      view |> element("#held-sort-name") |> render_click()
      html = render_async(view)

      assert column(html, "held", "name") == ["date", "cherry"]
      assert argument(html, "held", "at_least").value == "0"
    end

    test "gives a default that is a function the assigns it was given", %{html: html} do
      # `assigns={%{rate: …}}`
      assert argument(html, "held", "amount_fn-rate").value == "7"
      # the table beside it was given none
      assert argument(html, "linked", "amount_fn-rate").value == "5"
    end

    test "keeps them in the page's URL where it is given one, under its id", %{
      conn: conn,
      view: view
    } do
      html = argue(view, "linked", a: %{"at_least" => "6"})

      assert column(html, "linked", "name") == ["cherry", "date"]
      assert assert_patch(view) == "/support/asked?linked[a][at_least]=6"
      # the other table is as it was
      assert text(html, "#held-fill") == "Fill in At least to see records."

      {:ok, _view, html} =
        conn |> as(reader: @admin) |> live("/support/asked?linked[a][at_least]=6")

      assert column(html, "linked", "name") == ["cherry", "date"]
    end
  end
end
