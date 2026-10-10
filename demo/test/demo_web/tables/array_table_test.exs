defmodule DemoWeb.Tables.ArrayTableTest do
  @moduledoc """
  What a table does with a column that is an array: how its cells are shown,
  what they are edited with, and what a save sends.

  The table is of a resource that exists for the tests only
  (`Demo.Support.Lists.Roster` in `test/support/array_tables.ex`), mounted at
  `/support/rosters`; its records are kept in memory. It has one array per
  kind of value a table has an editor for. `words` takes at most three values
  of at least two characters, `gaps` takes values that are empty and keeps them, and
  `stages`, which has to have a value, is saved through an action of its own
  that leaves a trace. A viewer changes nothing, and only an admin sees
  `secrets`.

  The arrays of the demo's own tables, on Postgres, are in
  `task_arrays_test.exs` and `specimen_edit_test.exs`.
  """
  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Support.Lists.Roster

  @admin %{id: "ada", name: "ada", role: :admin}
  @member %{id: "max", name: "max", role: :member}
  @viewer %{id: "vera", name: "vera", role: :viewer}

  setup do
    on_exit(fn -> Demo.Support.Ets.stop(Roster) end)
  end

  defp roster(attributes \\ %{}) do
    Ash.Seed.seed!(
      Roster,
      Map.merge(
        %{
          name: "Night shift",
          words: ["alpha", "beta"],
          numbers: [Decimal.new("1.50"), Decimal.new("20")],
          gaps: [1, nil, 3],
          days: [~D[2026-03-09], ~D[2026-12-01]],
          moments: [~U[2026-03-09 14:30:05Z]],
          switches: [true, false],
          stages: [:done, :draft],
          sizes: [:extra_large],
          marks: [700, 900],
          frozen: ["ice"],
          sealed: ["wax"],
          secrets: ["hush"],
          keys: ["11111111-2222-4333-8444-555555555555"],
          grid: [[1, 2], [3]]
        },
        attributes
      )
    )
  end

  defp stored(roster), do: Ash.get!(Roster, roster.id, authorize?: false)

  defp open(conn, actor) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{"assigns" => %{current_user: actor}})
    |> live("/support/rosters")
  end

  defp shown(html, roster, field), do: text(html, cell("roster", roster.id, field))

  defp held(html, roster, field),
    do: attribute(html, cell("roster", roster.id, field), "data-value")

  describe "a cell of an array" do
    test "shows its values as plain text, separated by commas, each as a cell of its type shows it",
         %{conn: conn} do
      roster = roster()
      {:ok, _view, html} = open(conn, @admin)

      assert shown(html, roster, "words") == "alpha, beta"
      assert shown(html, roster, "numbers") == "1.50, 20"
      assert shown(html, roster, "days") == "2026-03-09, 2026-12-01"
      assert shown(html, roster, "moments") == "2026-03-09T14:30:05"
      assert shown(html, roster, "switches") == "Yes, No"
      # the labels of the values of an enum, in the order the record has them
      assert shown(html, roster, "stages") == "Done, Draft"
      assert shown(html, roster, "sizes") == "Extra large"
      # a value that is nil is nothing between its commas
      assert shown(html, roster, "gaps") == "1, , 3"
    end

    test "is text and nothing else: no element of its own in the cell", %{conn: conn} do
      roster = roster()
      {:ok, _view, html} = open(conn, @admin)

      for field <- ~w(words numbers switches stages) do
        assert [{"td", _attributes, [text]}] =
                 html
                 |> LazyHTML.from_fragment()
                 |> LazyHTML.query(cell("roster", roster.id, field))
                 |> LazyHTML.to_tree()

        assert is_binary(text), field
      end
    end

    test "of an empty array and of nil is empty, as every empty cell", %{conn: conn} do
      roster = roster(%{words: [], numbers: nil, stages: nil, switches: []})
      {:ok, _view, html} = open(conn, @admin)

      for field <- ~w(words numbers stages switches) do
        assert [{"td", _attributes, []}] =
                 html
                 |> LazyHTML.from_fragment()
                 |> LazyHTML.query(cell("roster", roster.id, field))
                 |> LazyHTML.to_tree()
      end
    end

    test "of values a table has no cell for, and of arrays, is read-only text as before",
         %{conn: conn} do
      roster = roster()
      {:ok, _view, html} = open(conn, @admin)

      assert shown(html, roster, "keys") == "11111111-2222-4333-8444-555555555555"
      assert shown(html, roster, "grid") == "1, 2, 3"

      for field <- ~w(keys grid) do
        assert attribute(html, cell("roster", roster.id, field), "aria-readonly") == ["true"]
      end
    end

    test "says what its editor starts with: the values, each as its editor writes it",
         %{conn: conn} do
      roster = roster()
      {:ok, _view, html} = open(conn, @admin)

      assert held(html, roster, "words") == [~s(["alpha","beta"])]
      assert held(html, roster, "numbers") == [~s(["1.50","20"])]
      assert held(html, roster, "days") == [~s(["2026-03-09","2026-12-01"])]
      assert held(html, roster, "switches") == [~s(["true","false"])]
      # a choice is its value, not its label
      assert held(html, roster, "stages") == [~s(["done","draft"])]
      assert held(html, roster, "gaps") == [~s(["1","","3"])]
    end

    test "of nil starts its editor with no values, as an empty array does", %{conn: conn} do
      roster = roster(%{words: [], numbers: nil})
      {:ok, _view, html} = open(conn, @admin)

      assert held(html, roster, "words") == ["[]"]
      assert held(html, roster, "numbers") == ["[]"]
    end

    test "is neither sorted nor filtered by", %{conn: conn} do
      roster()
      {:ok, _view, html} = open(conn, @admin)

      for field <- ~w(words numbers switches stages sizes keys) do
        assert attribute(html, "#roster-head-#{field}", "aria-sort") == [], field
        assert attribute(html, "#roster-head-#{field}", "data-sort") == [], field
        assert attribute(html, "#roster-filter-#{field}", "data-filter") == [], field

        assert filter_controls(html, "roster", field) == %{
                 operators: nil,
                 input: nil,
                 choices: nil
               }
      end

      # a column of one value beside them is
      assert attribute(html, "#roster-head-name", "aria-sort") == ["none"]
      assert filter_controls(html, "roster", "name").input == "text"
    end

    test "a sort or a filter by one, asked for by hand, changes nothing", %{conn: conn} do
      roster(%{name: "B", words: ["zz"]})
      roster(%{name: "A", words: ["aa"]})
      {:ok, view, html} = open(conn, @admin)
      names = column(html, "roster", "name")
      assert length(names) == 2

      view |> element("#roster-grid") |> render_hook("sort", %{"column" => "words"})
      assert column(render_async(view, 2000), "roster", "name") == names

      view
      |> element("#roster-filters")
      |> render_change(%{"filter" => %{"words" => %{"o" => "has", "v" => "zz"}}})

      assert column(render_async(view, 2000), "roster", "name") == names
    end
  end

  describe "what an array is edited with" do
    setup %{conn: conn} do
      roster = roster()
      {:ok, view, html} = open(conn, @admin)
      %{roster: roster, view: view, html: html}
    end

    test "an array of enum values with one box per value of the enum, in declared order, with the labels",
         %{html: html} do
      assert editor(html, "roster", "stages") == %{
               control: "choices",
               choices: ["Draft", "In review", "Done"],
               confirm: "Change the stages?"
             }

      # an atom limited to a set of values
      assert editor(html, "roster", "sizes") == %{
               control: "choices",
               choices: ["Small", "Extra large"],
               confirm: nil
             }
    end

    test "any other array with one control per value, of the editor its values have as a cell",
         %{html: html} do
      assert editor(html, "roster", "words").control == {"list", "textarea"}
      assert editor(html, "roster", "numbers").control == {"list", "number"}
      assert editor(html, "roster", "gaps").control == {"list", "number"}
      assert editor(html, "roster", "days").control == {"list", "date"}
      assert editor(html, "roster", "moments").control == {"list", "datetime-local"}
      assert editor(html, "roster", "switches").control == {"list", "checkbox"}
    end

    test "which is a group that the column names, with what its controls are called by their place",
         %{html: html} do
      {"template", attributes, children} = tree(html, "template[id='roster-editor-words']")
      [{"div", group, _rows}] = Enum.reject(children, &is_binary/1)

      assert {"data-editor", "list"} in attributes
      assert {"role", "group"} in group
      assert {"aria-label", "Words"} in group
      assert {"data-value-label", "Words {n}"} in group
      assert {"data-remove-label", "Remove Words {n}"} in group

      {"template", _attributes, children} = tree(html, "template[id='roster-editor-stages']")
      [{"div", group, labels}] = Enum.reject(children, &is_binary/1)

      assert {"role", "group"} in group
      assert {"aria-label", "Stages"} in group

      # each box in the label that names it, with the value it stands for
      assert ["draft", "in_review", "done"] ==
               for(
                 {"label", _, [{"input", box, _} | _]} <- labels,
                 do: :proplists.get_value("value", box)
               )
    end

    test "every column with an editor has its cells open, and no other", %{
      html: html,
      roster: roster
    } do
      editable = ~w(name words numbers gaps days moments switches stages sizes marks secrets)

      assert editors(html, "roster") == editable

      for field <- editable do
        assert attribute(html, cell("roster", roster.id, field), "aria-readonly") == [], field
      end
    end

    test "an array no action accepts, and one switched off in the block, are read-only",
         %{html: html, roster: roster} do
      for field <- ~w(frozen sealed) do
        assert editor(html, "roster", field) == nil
        assert attribute(html, cell("roster", roster.id, field), "aria-readonly") == ["true"]
        assert held(html, roster, field) == []
      end
    end

    test "nothing of it is offered to a person who can never run the action", %{conn: conn} do
      roster = roster(%{name: "Other"})
      {:ok, _view, html} = open(conn, @viewer)

      assert editors(html, "roster") == []
      assert held(html, roster, "words") == []
    end

    test "a column whose component has an editor of its own is edited with the table's all the same",
         %{html: html, roster: roster} do
      # the component shows the cell: it is given the list, and the text the table would show
      assert {"td", _, [{"span", probe, ["700, 900"]}]} =
               tree(html, cell("roster", roster.id, "marks"))

      assert {"data-value", "[700, 900]"} in probe

      # and its editor, which holds one value, is not used
      assert editor(html, "roster", "marks").control == {"list", "number"}
      refute html =~ "data-probe-editor"
      assert held(html, roster, "marks") == [~s(["700","900"])]
    end
  end

  describe "saving an array that is edited value by value" do
    setup %{conn: conn} do
      roster = roster()
      {:ok, view, _html} = open(conn, @admin)
      %{conn: conn, roster: roster, view: view}
    end

    test "sends the values as they were typed, and the action makes of them what it does",
         %{conn: conn, view: view, roster: roster} do
      html = save(view, "roster", roster.id, "words", ["gamma", "alpha", "delta"])

      assert shown(html, roster, "words") == "gamma, alpha, delta"
      assert failure(html, "roster", roster.id, "words") == nil
      assert stored(roster).words == ["gamma", "alpha", "delta"]

      html = save(view, "roster", roster.id, "numbers", ["2.5", "-1"])
      assert shown(html, roster, "numbers") == "2.5, -1"
      assert stored(roster).numbers == [Decimal.new("2.5"), Decimal.new("-1")]

      html = save(view, "roster", roster.id, "days", ["2027-01-31"])
      assert shown(html, roster, "days") == "2027-01-31"
      assert stored(roster).days == [~D[2027-01-31]]

      html =
        save(view, "roster", roster.id, "moments", ["2027-01-31T23:59:58", "2026-01-01T00:00:00"])

      assert shown(html, roster, "moments") == "2027-01-31T23:59:58, 2026-01-01T00:00:00"

      html = save(view, "roster", roster.id, "switches", ["false", "false", "true"])
      assert shown(html, roster, "switches") == "No, No, Yes"
      assert stored(roster).switches == [false, false, true]

      {:ok, _view, html} = open(conn, @admin)
      assert shown(html, roster, "words") == "gamma, alpha, delta"
      assert shown(html, roster, "switches") == "No, No, Yes"
    end

    test "with no values left saves the empty array", %{view: view, roster: roster} do
      html = save(view, "roster", roster.id, "words", [])

      assert shown(html, roster, "words") == ""
      assert failure(html, "roster", roster.id, "words") == nil
      assert stored(roster).words == []
    end

    # `AshPhoenix.Form` leaves out of an array what the array's `empty_values`
    # constraint names, which is the empty text unless the resource says
    # otherwise
    test "leaves out a value that was left empty, as the form of the action does",
         %{view: view, roster: roster} do
      html = save(view, "roster", roster.id, "numbers", ["1", "", "2"])

      assert shown(html, roster, "numbers") == "1, 2"
      assert failure(html, "roster", roster.id, "numbers") == nil
      assert stored(roster).numbers == [Decimal.new("1"), Decimal.new("2")]

      html = save(view, "roster", roster.id, "words", ["", ""])
      assert failure(html, "roster", roster.id, "words") == nil
      assert stored(roster).words == []
    end

    test "keeps it in an array that says an empty text is a value, where the action decides",
         %{view: view, roster: roster} do
      html = save(view, "roster", roster.id, "gaps", ["", "5", ""])

      assert shown(html, roster, "gaps") == ", 5,"
      assert failure(html, "roster", roster.id, "gaps") == nil
      assert stored(roster).gaps == [nil, 5, nil]
    end

    test "that has too many values is refused by the action, which says so on the cell",
         %{view: view, roster: roster} do
      html = save(view, "roster", roster.id, "words", ["aa", "bb", "cc", "dd"])

      assert failure(html, "roster", roster.id, "words") == %{
               shown: "aa, bb, cc, dd",
               message: "must have 3 or fewer items"
             }

      assert stored(roster).words == ["alpha", "beta"]
    end

    test "with a value its type does not take is refused, with the action's message for that value",
         %{view: view, roster: roster} do
      # a constraint of the values
      html = save(view, "roster", roster.id, "words", ["alpha", "b"])

      assert failure(html, "roster", roster.id, "words") == %{
               shown: "alpha, b",
               message: "Words 2: length must be greater than or equal to 2"
             }

      # a value that is no number
      html = save(view, "roster", roster.id, "numbers", ["1", "many"])

      assert failure(html, "roster", roster.id, "numbers") == %{
               shown: "1, many",
               message: "Numbers 2: is invalid"
             }

      assert %{words: ["alpha", "beta"]} = stored(roster)
    end

    test "that failed keeps what was typed for its editor, beside what the record has",
         %{view: view, roster: roster} do
      html = save(view, "roster", roster.id, "words", ["alpha", "b"])
      selector = cell("roster", roster.id, "words")

      assert attribute(html, selector, "data-value") == [~s(["alpha","b"])]
      assert attribute(html, selector, "data-saved") == [~s(["alpha","beta"])]

      assert announcement(html, "roster") ==
               "Words was not saved: Words 2: length must be greater than or equal to 2"

      # given up, as Escape on the cell does: the record's values again
      html = discard(view, "roster", roster.id, "words")
      assert shown(html, roster, "words") == "alpha, beta"
      assert failure(html, "roster", roster.id, "words") == nil
      assert attribute(html, selector, "data-value") == [~s(["alpha","beta"])]
    end
  end

  describe "a save that is refused because of one value" do
    setup %{conn: conn} do
      roster = roster()
      {:ok, view, _html} = open(conn, @admin)
      %{roster: roster, view: view}
    end

    defp invalid(html, roster, field),
      do: attribute(html, cell("roster", roster.id, field), "data-invalid")

    test "says which value: called what its control is called, by the column and its place",
         %{view: view, roster: roster} do
      html = save(view, "roster", roster.id, "words", ["alpha", "beta", "c"])

      assert failure(html, "roster", roster.id, "words").message ==
               "Words 3: length must be greater than or equal to 2"

      # for every type of value: a date that is none, a box that is neither
      for {field, typed, message} <- [
            {"days", ["2026-01-01", "soon"], "Days 2: is invalid"},
            {"switches", ["perhaps", "true"], "Switches 1: is invalid"},
            {"moments", ["2026-01-01T00:00:00", "2026-01-02T00:00:00", "later"],
             "Moments 3: Could not cast input to datetime"}
          ] do
        html = save(view, "roster", roster.id, field, typed)
        assert failure(html, "roster", roster.id, field).message == message
      end
    end

    test "and tells the cell's editor the places of the values, counted from 0",
         %{view: view, roster: roster} do
      html = save(view, "roster", roster.id, "words", ["alpha", "beta", "c"])
      assert invalid(html, roster, "words") == ["[2]"]

      # of values that are none of the type, Ash names the first
      html = save(view, "roster", roster.id, "numbers", ["1", "two", "three"])
      assert invalid(html, roster, "numbers") == ["[1]"]
      assert failure(html, "roster", roster.id, "numbers").message == "Numbers 2: is invalid"

      # the first cell is still marked with its own
      assert invalid(html, roster, "words") == ["[2]"]
    end

    test "says each of several values", %{view: view, roster: roster} do
      html = save(view, "roster", roster.id, "words", ["a", "beta", "c"])

      assert failure(html, "roster", roster.id, "words").message ==
               "Words 1: length must be greater than or equal to 2; " <>
                 "Words 3: length must be greater than or equal to 2"

      assert invalid(html, roster, "words") == ["[0,2]"]
    end

    test "names no value when the action refuses the array as a whole", %{
      view: view,
      roster: roster
    } do
      html = save(view, "roster", roster.id, "words", ["aa", "bb", "cc", "dd"])

      assert failure(html, "roster", roster.id, "words").message == "must have 3 or fewer items"
      assert invalid(html, roster, "words") == []
    end

    test "names no place in a multiple choice, whose boxes have none", %{
      view: view,
      roster: roster
    } do
      html = save(view, "roster", roster.id, "stages", ["done", "nope"])

      assert failure(html, "roster", roster.id, "stages").message == "is invalid"
      assert invalid(html, roster, "stages") == []
    end

    test "is forgotten with the failure: once the edit is given up, and once a save succeeds",
         %{view: view, roster: roster} do
      save(view, "roster", roster.id, "words", ["alpha", "c"])
      html = discard(view, "roster", roster.id, "words")
      assert invalid(html, roster, "words") == []

      save(view, "roster", roster.id, "words", ["alpha", "c"])
      html = save(view, "roster", roster.id, "words", ["alpha", "cc"])
      assert invalid(html, roster, "words") == []
      assert failure(html, "roster", roster.id, "words") == nil
    end
  end

  describe "a value the record has and the enum no longer does" do
    # `Demo.Support.Lists.Earlier` keeps its records in the rosters' table,
    # and still has the size `:medium`. Only an array of atoms limited by
    # `one_of` can hold such a value and be read: an `Ash.Type.Enum` fails
    # the read of a value it does not have.
    setup %{conn: conn} do
      earlier =
        Ash.create!(Demo.Support.Lists.Earlier, %{name: "Old", sizes: [:medium, :small]},
          authorize?: false
        )

      roster = stored(earlier)
      {:ok, view, html} = open(conn, @admin)
      %{roster: roster, view: view, html: html}
    end

    test "is shown as it is, among the labels of the others, and is one of the values the editor starts with",
         %{html: html, roster: roster} do
      assert roster.sizes == [:medium, :small]
      assert shown(html, roster, "sizes") == "medium, Small"
      assert held(html, roster, "sizes") == [~s(["medium","small"])]
      # it has no box: the choices are the enum's
      assert editor(html, "roster", "sizes").choices == ["Small", "Extra large"]
    end

    test "is sent back with what was ticked, and what the action makes of it is shown on the cell",
         %{view: view, roster: roster} do
      # what the editor sends when "Extra large" is ticked: the ticked values
      # in the enum's order, then the value that has no box
      html = save(view, "roster", roster.id, "sizes", ["small", "extra_large", "medium"])

      assert failure(html, "roster", roster.id, "sizes") == %{
               shown: "Small, Extra large, medium",
               message: "atom must be one of small, extra_large, got: medium"
             }

      assert stored(roster).sizes == [:medium, :small]
    end

    test "is a field of the action panel that is sent and not shown: after the boxes, which do not have it",
         %{view: view, roster: roster} do
      html = act(view, "roster", roster.id, "revise")

      assert %{control: "choices", value: ["small"]} = field(html, "sizes")

      assert [{"input", attributes, []}] =
               html
               |> LazyHTML.from_fragment()
               |> LazyHTML.query("#roster-panel-f-sizes > input[type=hidden]")
               |> LazyHTML.to_tree()

      assert {"name", "panel[sizes][]"} in attributes
      assert {"value", "medium"} in attributes

      # the last control of the field: sent after the ticked values
      assert ["text", "checkbox", "checkbox", "hidden"] ==
               attribute(html, "#roster-panel-f-sizes input", "type")

      # it stays through what is typed, which the form sends with it
      html =
        view
        |> element("#roster-panel-form")
        |> render_change(%{
          "panel" => %{"name" => "Old", "sizes" => ["", "small", "extra_large", "medium"]}
        })

      assert %{value: ["small", "extra_large"]} = field(html, "sizes")
      assert attribute(html, "#roster-panel-f-sizes > input[type=hidden]", "value") == ["medium"]
    end

    test "and the panel shows what the action makes of it at the field", %{
      view: view,
      roster: roster
    } do
      act(view, "roster", roster.id, "revise")

      html =
        send_panel(view, "roster", %{
          "panel" => %{
            "name" => "Old",
            "words" => [""],
            "stages" => ["", "done"],
            "switches" => [""],
            "sizes" => ["", "small", "medium"],
            "weights" => ["", "1"]
          }
        })

      assert field(html, "sizes").errors == [
               "atom must be one of small, extra_large, got: medium"
             ]

      assert stored(roster).sizes == [:medium, :small]
    end
  end

  describe "saving a multiple choice" do
    setup %{conn: conn} do
      roster = roster()
      {:ok, view, _html} = open(conn, @admin)
      %{conn: conn, roster: roster, view: view}
    end

    test "sends the values that are ticked, and shows their labels", %{
      conn: conn,
      view: view,
      roster: roster
    } do
      html = save(view, "roster", roster.id, "stages", ["draft", "in_review"])

      assert shown(html, roster, "stages") == "Draft, In review"
      assert failure(html, "roster", roster.id, "stages") == nil
      assert stored(roster).stages == [:draft, :in_review]

      html = save(view, "roster", roster.id, "sizes", ["small", "extra_large"])
      assert shown(html, roster, "sizes") == "Small, Extra large"
      assert stored(roster).sizes == [:small, :extra_large]

      {:ok, _view, html} = open(conn, @admin)
      assert shown(html, roster, "stages") == "Draft, In review"
    end

    test "runs the column's own action", %{view: view, roster: roster} do
      save(view, "roster", roster.id, "stages", ["draft"])
      assert %{stages: [:draft], trace: "restage"} = stored(roster)
    end

    test "with nothing ticked sends the empty array, which this action refuses",
         %{view: view, roster: roster} do
      html = save(view, "roster", roster.id, "stages", [])

      assert failure(html, "roster", roster.id, "stages") == %{
               shown: "",
               message: "must have 1 or more items"
             }

      assert %{stages: [:done, :draft], trace: nil} = stored(roster)

      # and an array without that constraint takes
      html = save(view, "roster", roster.id, "sizes", [])
      assert failure(html, "roster", roster.id, "sizes") == nil
      assert stored(roster).sizes == []
    end

    test "with a value that is none of the enum's is refused by the action", %{
      view: view,
      roster: roster
    } do
      html = save(view, "roster", roster.id, "stages", ["done", "nope"])

      assert failure(html, "roster", roster.id, "stages") == %{
               shown: "Done, nope",
               message: "is invalid"
             }

      assert stored(roster).stages == [:done, :draft]
    end
  end

  describe "a value that is the one the cell already holds" do
    setup %{conn: conn} do
      roster = roster()
      {:ok, view, _html} = open(conn, @admin)
      %{roster: roster, view: view}
    end

    test "runs no action", %{view: view, roster: roster} do
      html = save(view, "roster", roster.id, "stages", ["done", "draft"])

      assert shown(html, roster, "stages") == "Done, Draft"
      assert failure(html, "roster", roster.id, "stages") == nil
      # `restage` leaves its trace whenever it runs
      assert stored(roster).trace == nil

      # the same values in another order are another value
      save(view, "roster", roster.id, "stages", ["draft", "done"])
      assert %{stages: [:draft, :done], trace: "restage"} = stored(roster)
    end

    test "nor for an array without values, whether the record has an empty array or none",
         %{conn: conn} do
      roster = roster(%{name: "Empty", stages: nil})
      {:ok, view, _html} = open(conn, @admin)

      html = save(view, "roster", roster.id, "stages", [])

      assert failure(html, "roster", roster.id, "stages") == nil
      assert %{stages: nil, trace: nil} = stored(roster)
    end

    test "typed again after a failed save runs nothing, and the cell is no longer marked",
         %{view: view, roster: roster} do
      html = save(view, "roster", roster.id, "stages", [])
      assert failure(html, "roster", roster.id, "stages")

      html = save(view, "roster", roster.id, "stages", ["done", "draft"])
      assert failure(html, "roster", roster.id, "stages") == nil
      assert stored(roster).trace == nil
    end
  end

  describe "what the table's editors never send" do
    setup %{conn: conn} do
      roster = roster()
      {:ok, view, _html} = open(conn, @admin)
      %{roster: roster, view: view}
    end

    test "one text for an array, a list for one value, or a list of anything but texts: nothing is saved or shown",
         %{view: view, roster: roster} do
      for {field, value} <- [
            {"words", "gamma"},
            {"words", ["gamma", 1]},
            {"words", [["gamma"]]},
            {"words", %{"0" => "gamma"}},
            {"name", ["Day shift"]}
          ] do
        html = save(view, "roster", roster.id, field, value)

        assert failure(html, "roster", roster.id, field) == nil
        assert shown(html, roster, "words") == "alpha, beta"
        assert shown(html, roster, "name") == "Night shift"
      end

      assert %{words: ["alpha", "beta"], name: "Night shift"} = stored(roster)
    end

    test "an array no action accepts, one switched off, and one a table has no editor for save nothing",
         %{view: view, roster: roster} do
      for field <- ~w(frozen sealed keys) do
        html = save(view, "roster", roster.id, field, ["new"])
        assert failure(html, "roster", roster.id, field) == nil
      end

      assert %{frozen: ["ice"], sealed: ["wax"]} = stored(roster)
    end
  end

  describe "an error that has a path" do
    # Ash says which value of an array an error is about by the value's place
    # as the error's path, and the table shows such an error (see "with a
    # value its type does not take" above). Any other path leads to a record
    # nested in this one, whose field may be called what a column is.
    test "into a nested record is not taken for one about the column of the same name",
         %{conn: conn} do
      roster = roster()
      {:ok, view, _html} = open(conn, @admin)

      html = act(view, "roster", roster.id, "misplace")

      assert action_failure(html, "roster", roster.id) == "This could not be done."
      refute html =~ "is nested"
    end
  end

  describe "an array that is hidden from the person" do
    test "has no column for them, and cannot be saved by sending its name", %{conn: conn} do
      roster = roster()
      {:ok, view, html} = open(conn, @member)

      refute "Secrets" in headers(html, "roster")
      refute html =~ "hush"

      save(view, "roster", roster.id, "secrets", ["loud"])
      assert stored(roster).secrets == ["hush"]
    end
  end

  describe "the field of an array in the action panel" do
    setup %{conn: conn} do
      roster = roster()
      {:ok, view, _html} = open(conn, @admin)
      html = act(view, "roster", roster.id, "revise")
      %{roster: roster, view: view, html: html}
    end

    defp field(html, name), do: Enum.find(panel(html, "roster").fields, &(&1.name == name))

    test "is a multiple choice or a list of the record's values, and is never marked as required",
         %{html: html} do
      assert %{label: "Words", control: "list", value: ["alpha", "beta"], required?: false} =
               field(html, "words")

      # the boxes are in declared order, whatever the order of the record's values
      assert %{label: "Stages", control: "choices", value: ["draft", "done"]} =
               field(html, "stages")

      assert %{control: "list", value: ["true", "false"]} = field(html, "switches")
      # an argument has no record to take its values from
      assert %{label: "Weights", control: "list", value: []} = field(html, "weights")

      # no mark of a required field: an array field always gives a list
      refute html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#roster-panel [data-field=weights] [aria-hidden]")
             |> Enum.any?(&(LazyHTML.text(&1) =~ "*"))
    end

    test "is a group named by its label, whose controls are named by their place or their choice",
         %{html: html} do
      {"div", group, _children} = tree(html, "#roster-panel-f-words")

      assert {"role", "group"} in group
      assert {"aria-labelledby", "roster-panel-f-words-label"} in group
      assert text(html, "#roster-panel-f-words-label") == "Words"

      assert attribute(
               html,
               "#roster-panel-f-words-values > [data-item] > textarea",
               "aria-label"
             ) ==
               ["Words 1", "Words 2"]

      assert attribute(html, "#roster-panel-f-words-values > [data-item] > button", "aria-label") ==
               ["Remove Words 1", "Remove Words 2"]

      assert text(html, "#roster-panel-f-words-values > button[data-add]") == "Add value"

      # the rows are the hook's from here on
      assert attribute(html, "#roster-panel-f-words-values", "phx-update") == ["ignore"]

      assert ["Draft", "In review", "Done"] ==
               html
               |> LazyHTML.from_fragment()
               |> LazyHTML.query("#roster-panel-f-stages > label")
               |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
    end

    # what a browser sends for the field of an array: one entry of the
    # field's own, then one per value
    defp sent(values), do: ["" | values]

    test "runs the action with the values of each array, as they were typed", %{
      view: view,
      roster: roster
    } do
      html =
        send_panel(view, "roster", %{
          "panel" => %{
            "name" => "Day shift",
            "words" => sent(["gamma", "delta"]),
            "stages" => sent(["in_review"]),
            "switches" => sent(["true"]),
            "weights" => sent(["3", "4"])
          }
        })

      assert panel(html, "roster") == nil
      assert shown(html, roster, "words") == "gamma, delta"
      assert shown(html, roster, "stages") == "In review"

      assert %{
               name: "Day shift",
               words: ["gamma", "delta"],
               stages: [:in_review],
               switches: [true],
               trace: "revise"
             } = stored(roster)
    end

    test "sends an array without values as the empty array", %{view: view, roster: roster} do
      html =
        send_panel(view, "roster", %{
          "panel" => %{
            "name" => "Day shift",
            "words" => sent([]),
            "stages" => sent(["done"]),
            "switches" => sent([]),
            "weights" => sent(["1"])
          }
        })

      assert panel(html, "roster") == nil
      assert %{words: [], switches: [], stages: [:done]} = stored(roster)
    end

    test "shows what the action says about an array at its field, and runs nothing",
         %{view: view, roster: roster} do
      html =
        send_panel(view, "roster", %{
          "panel" => %{
            "name" => "Day shift",
            "words" => sent(["aa", "bb", "cc", "dd"]),
            "stages" => sent([]),
            "switches" => sent(["true"]),
            "weights" => sent(["1", "heavy"])
          }
        })

      assert field(html, "words").errors == ["must have 3 or fewer items"]
      assert field(html, "stages").errors == ["must have 1 or more items"]
      # about one value of the array
      assert field(html, "weights").errors == ["Weights 2: is invalid"]
      assert field(html, "name").errors == []

      # the fields keep what was typed
      assert field(html, "stages").value == []

      assert %{name: "Night shift", words: ["alpha", "beta"], trace: nil} = stored(roster)

      assert announcement(html, "roster") =~ "Words: must have 3 or fewer items"
    end

    test "tells the field's rows which values the action refuses, where the errors are shown",
         %{view: view, html: html} do
      places = &attribute(&1, "#roster-panel-f-#{&2}", "data-invalid")
      assert places.(html, "weights") == []

      html =
        send_panel(view, "roster", %{
          "panel" => %{
            "name" => "Day shift",
            "words" => sent(["alpha", "b", "c"]),
            "stages" => sent(["done"]),
            "switches" => sent(["true"]),
            "weights" => sent(["1", "heavy"])
          }
        })

      assert field(html, "words").errors == [
               "Words 2: length must be greater than or equal to 2",
               "Words 3: length must be greater than or equal to 2"
             ]

      assert places.(html, "words") == ["[1,2]"]
      assert places.(html, "weights") == ["[1]"]
      assert places.(html, "switches") == []

      # put right as it is typed
      html =
        view
        |> element("#roster-panel-form")
        |> render_change(%{
          "panel" => %{
            "name" => "Day shift",
            "words" => sent(["alpha", "bb", "c"]),
            "stages" => sent(["done"]),
            "switches" => sent(["true"]),
            "weights" => sent(["1", "2"])
          }
        })

      assert places.(html, "words") == ["[2]"]
      assert places.(html, "weights") == []
    end

    test "says what the action makes of an array while it is typed, and runs nothing",
         %{view: view, roster: roster} do
      html =
        view
        |> element("#roster-panel-form")
        |> render_change(%{
          "panel" => %{
            "name" => "Night shift",
            "words" => sent(["a"]),
            "stages" => sent(["done", "draft"]),
            "switches" => sent(["true", "false"]),
            "weights" => sent([])
          }
        })

      assert field(html, "words").errors == ["Words 1: length must be greater than or equal to 2"]
      assert field(html, "weights").errors == ["must have 1 or more items"]
      assert stored(roster).trace == nil
    end

    test "does not show an error at a field the person has not been in yet", %{view: view} do
      html =
        view
        |> element("#roster-panel-form")
        |> render_change(%{
          "panel" => %{
            "name" => "Day shift",
            "words" => sent(["alpha", "beta"]),
            "_unused_words" => ["", "", ""],
            "stages" => sent(["done", "draft"]),
            "_unused_stages" => ["", "", ""],
            "switches" => sent(["true", "false"]),
            "_unused_switches" => ["", "", ""],
            "weights" => sent([]),
            "_unused_weights" => [""]
          }
        })

      assert field(html, "weights").errors == []
    end

    test "takes nothing that is not the field of an array as a browser sends it",
         %{view: view, roster: roster} do
      # no entry of the field's own: the first value would be taken for it
      html =
        send_panel(view, "roster", %{
          "panel" => %{
            "name" => "Day shift",
            "words" => "gamma",
            "stages" => sent(["done"]),
            "switches" => sent([]),
            "weights" => sent(["1"])
          }
        })

      assert field(html, "words").errors == ["is invalid"]
      assert stored(roster).words == ["alpha", "beta"]
    end
  end

  describe "creating a record with arrays" do
    test "starts their fields empty or with the default, and creates with what was given",
         %{conn: conn} do
      {:ok, view, _html} = open(conn, @admin)
      html = open_create(view, "roster")

      assert %{control: "list", value: []} = field(html, "words")
      assert %{control: "list", value: []} = field(html, "numbers")
      assert %{control: "choices", value: []} = field(html, "stages")

      html =
        send_panel(view, "roster", %{
          "panel" => %{
            "name" => "Weekend",
            "words" => ["", "one-off"],
            "numbers" => ["", "0.5"],
            "switches" => [""],
            "stages" => ["", "draft", "done"],
            "sizes" => [""]
          }
        })

      assert panel(html, "roster") == nil

      assert [
               %{
                 name: "Weekend",
                 words: ["one-off"],
                 stages: [:draft, :done],
                 switches: [],
                 sizes: []
               } = created
             ] =
               Ash.read!(Roster, authorize?: false)

      assert created.numbers == [Decimal.new("0.5")]
      assert shown(html, created, "stages") == "Draft, Done"
    end
  end

  # the one element matching `selector`, as a tree
  defp tree(html, selector) do
    [node] = html |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> LazyHTML.to_tree()
    node
  end
end
