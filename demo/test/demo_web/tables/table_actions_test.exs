defmodule DemoWeb.Tables.TableActionsTest do
  @moduledoc """
  Table actions, and generic actions that are row actions, in the tables of
  resources that exist for the tests only (`test/support/action_tables.ex`):
  actions that run at once, ask first, open the action panel, return values
  of every kind and fail in every way; on the selected rows; and in a
  nested table.

  The demo's own, on `/labels`, are in `label_actions_test.exs`.

  A button of a table action is used as a click does. What the table's hook
  does is sent as the hook sends it: the `act` event of a row's button, and
  `table_run` once a question was answered with Confirm.
  """
  use DemoWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Support.Generic.{Chore, Rota, Shift}

  setup do
    on_exit(fn ->
      for resource <- [Chore, Rota, Shift], do: Demo.Support.Ets.stop(resource)
    end)
  end

  defp as(conn, role),
    do: Phoenix.ConnTest.init_test_session(conn, %{"assigns" => %{reader: %{role: role}}})

  defp chore(title, done \\ false),
    do: Ash.create!(Chore, %{title: title, done: done}, authorize?: false)

  defp chores, do: Chore |> Ash.read!(authorize?: false) |> Enum.map(& &1.title) |> Enum.sort()

  describe "the buttons of the table actions" do
    setup do
      %{chore: chore("Dishes")}
    end

    test "are on the line of the table's name, after the create button's place, in the declared order",
         %{conn: conn} do
      {:ok, _view, html} = conn |> as(:admin) |> live("/support/chores")

      assert table_actions(html, "chore") ==
               ["Count", "Sweep up", "Greet", "Mood", "Everything", "Audit", "Decline", "Explode"]

      # ordinary buttons of the page, as the create button is
      assert attribute(html, "#chore-do-count", "type") == ["button"]
      assert attribute(html, "#chore-do-count", "class") == ["btn btn-sm"]
      assert attribute(html, "#chore-do-count", "tabindex") == []
      assert attribute(html, "#chore-header #chore-do-count", "id") == ["chore-do-count"]
    end

    test "are those of the actions a person can ever run", %{conn: conn} do
      {:ok, _view, html} = conn |> as(:member) |> live("/support/chores")

      assert table_actions(html, "chore") ==
               ["Count", "Sweep up", "Greet", "Mood", "Everything", "Decline", "Explode"]
    end

    test "a generic action with `record_argument` is a button of every row instead", %{
      conn: conn,
      chore: chore
    } do
      {:ok, _view, html} = conn |> as(:admin) |> live("/support/chores")

      assert actions(html, "chore", chore.id) == ["Finish", "Copy", "Rename", "Stamp"]
      assert attribute(html, "#chore-do-copy", "id") == []
    end

    test "are not offered by a table that could not read, and an event that names one runs nothing",
         %{conn: conn} do
      {:ok, view, html} = conn |> as(:stranger) |> live("/support/chores")

      assert text(html, "#chore-error") != nil
      assert table_actions(html, "chore") == []

      html = confirm_table_action(view, "chore", "sweep")
      assert result(html, "chore") == nil
    end
  end

  describe "a table action without inputs" do
    setup %{conn: conn} do
      chore("Dishes")
      chore("Laundry", true)
      {:ok, view, _html} = conn |> as(:member) |> live("/support/chores")
      %{view: view}
    end

    test "runs when its button is used, and the table says what it returned", %{view: view} do
      html = table_act(view, "chore", "count")

      assert result(html, "chore") == "Count: 2"
      assert announcement(html, "chore") == "Count: 2"
      assert panel(html, "chore") == nil
    end

    test "that returns a value of an enum says it by its label", %{view: view} do
      assert result(table_act(view, "chore", "mood"), "chore") == "Mood: High"
    end

    test "that returns records, or nothing, says that it is done, and the table reads again", %{
      view: view
    } do
      assert result(table_act(view, "chore", "everything"), "chore") == "Everything: done"

      # the action that asks first is not run by its button
      html = table_act(view, "chore", "sweep")

      assert_push_event view, "ash_data_table:ask", %{
        table: "chore",
        action: :sweep,
        question: "Remove every finished chore?"
      }

      # nothing ran: the table still says what came of the action before
      assert result(html, "chore") == "Everything: done"
      assert chores() == ["Dishes", "Laundry"]

      # Confirm runs it
      html = confirm_table_action(view, "chore", "sweep")

      assert result(html, "chore") == "Sweep up: done"
      assert announcement(html, "chore") == "Sweep up: done"
      assert chores() == ["Dishes"]
      # the rows are those of a new read
      assert column(html, "chore", "title") == ["Dishes"]
    end

    test "reads again after it ran: a record that somebody else made is there", %{view: view} do
      chore("Windows")
      html = table_act(view, "chore", "count")

      assert result(html, "chore") == "Count: 3"
      assert column(html, "chore", "title") == ["Dishes", "Laundry", "Windows"]
    end

    test "that fails says what the action said, and what is not of its saying is logged", %{
      view: view
    } do
      html = table_act(view, "chore", "decline")
      assert result(html, "chore") == "Decline failed: not today"
      assert announcement(html, "chore") == "Decline failed: not today"

      log =
        capture_log(fn ->
          html = table_act(view, "chore", "explode")
          assert result(html, "chore") == "Explode failed: This could not be done."
        end)

      assert log =~ "the action `explode` of Demo.Support.Generic.Chore failed"

      # what came of the last one takes the place of what came of the one before
      assert result(table_act(view, "chore", "count"), "chore") == "Count: 2"
    end

    test "is not run by a person who can never run it, whatever their browser sends", %{
      view: view
    } do
      assert render(view) |> attribute("#chore-do-audit", "id") == []

      html = confirm_table_action(view, "chore", "audit")
      assert result(html, "chore") == nil

      # nor is one that no table has, or one of a row
      for name <- ["finish", "copy", "destroy", "read", "nothing"] do
        html = confirm_table_action(view, "chore", name)
        assert result(html, "chore") == nil
      end

      assert chores() == ["Dishes", "Laundry"]
    end
  end

  describe "a table action with inputs" do
    setup %{conn: conn} do
      chore("Dishes")
      {:ok, view, _html} = conn |> as(:member) |> live("/support/chores")
      %{view: view}
    end

    test "opens the action panel with its arguments, and nothing has run", %{view: view} do
      html = table_act(view, "chore", "greet")

      assert %{
               heading: "Greet",
               submit: "Run",
               errors: [],
               fields: [
                 %{name: "to", label: "To", control: "textarea", value: "", required?: true},
                 %{name: "loud", label: "Loud", control: "checkbox", value: "false"}
               ]
             } = panel(html, "chore")

      assert result(html, "chore") == nil
    end

    test "runs with what the fields hold, closes the panel and says what it returned", %{
      view: view
    } do
      table_act(view, "chore", "greet")
      html = run_panel(view, "chore", to: "World", loud: "true")
      html = if panel(html, "chore"), do: flunk("the panel stayed open"), else: ran(view)

      assert result(html, "chore") == "Greet: HELLO WORLD"
      assert announcement(html, "chore") == "Greet: HELLO WORLD"
    end

    test "shows what the action says about a field at the field, and stays open", %{view: view} do
      table_act(view, "chore", "greet")

      # as the person types
      html = type_in_panel(view, "chore", to: "x")

      assert %{fields: [%{name: "to", errors: ["length must be greater than or equal to 2"]} | _]} =
               panel(html, "chore")

      # an error the action returned when it ran
      html = run_panel(view, "chore", to: "nobody")

      assert %{errors: [], fields: [%{name: "to", errors: ["is not at home"]} | _]} =
               panel(html, "chore")

      assert announcement(html, "chore") == "Greet failed: To: is not at home"
      assert result(html, "chore") == nil

      # put right, it runs
      run_panel(view, "chore", to: "World")
      html = ran(view)
      assert panel(html, "chore") == nil
      assert result(html, "chore") == "Greet: Hello World"
    end

    test "is not run without its inputs by the event of an action that asks first", %{view: view} do
      html = confirm_table_action(view, "chore", "greet")

      assert result(html, "chore") == nil
      assert panel(html, "chore") == nil
    end

    test "Cancel closes the panel and runs nothing", %{view: view} do
      table_act(view, "chore", "greet")
      html = cancel_panel(view, "chore")

      assert panel(html, "chore") == nil
      assert result(html, "chore") == nil
    end
  end

  describe "a generic action that is a row action" do
    setup %{conn: conn} do
      dishes = chore("Dishes")
      laundry = chore("Laundry", true)
      {:ok, view, _html} = conn |> as(:member) |> live("/support/chores")
      %{view: view, dishes: dishes, laundry: laundry}
    end

    test "runs on the record of its row, says what came of it, and the table reads again", %{
      view: view,
      dishes: dishes
    } do
      act(view, "chore", dishes.id, "copy")
      assert_reply view, %{ok: true}
      html = ran(view)

      assert chores() == ["Dishes", "Dishes again", "Laundry"]
      assert column(html, "chore", "title") == ["Dishes", "Dishes again", "Laundry"]
      assert result(html, "chore") == "Copy: done"
      assert announcement(html, "chore") == "Copy: done"

      act(view, "chore", dishes.id, "stamp")
      assert result(ran(view), "chore") == "Stamp: stamped Dishes"
    end

    test "that fails marks the actions cell of its row with what the action said", %{
      view: view,
      laundry: laundry
    } do
      html = act(view, "chore", laundry.id, "stamp")
      assert_reply view, %{ok: false}

      assert action_failure(html, "chore", laundry.id) == "is done already"
      assert announcement(html, "chore") == "Stamp failed: is done already"
      assert result(html, "chore") == nil
    end

    test "on a record that is gone runs nothing, and says so", %{view: view, dishes: dishes} do
      Ash.destroy!(dishes, authorize?: false)

      act(view, "chore", dishes.id, "copy")
      assert_reply view, %{ok: false, error: "This record is no longer available."}
      assert chores() == ["Laundry"]
    end

    test "is not run on a row that is none of the page", %{view: view} do
      act(view, "chore", Ash.UUID.generate(), "copy")
      assert_reply view, %{ok: false}
      assert chores() == ["Dishes", "Laundry"]
    end

    test "with other arguments opens the panel for those, headed by the action and the record", %{
      view: view,
      dishes: dishes
    } do
      html = act(view, "chore", dishes.id, "rename")
      assert_reply view, %{ok: true, panel: true}

      assert %{
               heading: "Rename: Dishes",
               submit: "Run",
               fields: [%{name: "title", label: "Title", value: "", required?: true}]
             } = panel(html, "chore")

      # its question is asked when "Run" is used, as that of any row action
      assert attribute(html, "#chore-panel", "data-question") == ["Rename this chore?"]
    end

    test "is given the key of its row, whatever the form sends for that argument", %{
      view: view,
      dishes: dishes,
      laundry: laundry
    } do
      act(view, "chore", dishes.id, "rename")
      send_panel(view, "chore", %{"panel" => %{"title" => "Plates", "chore_id" => laundry.id}})
      html = ran(view)

      assert chores() == ["Laundry", "Plates"]
      assert panel(html, "chore") == nil
      assert result(html, "chore") == "Rename: Plates"
      assert column(html, "chore", "title") == ["Laundry", "Plates"]
    end

    test "shows what the action says at the field of its panel, and stays open", %{
      view: view,
      dishes: dishes,
      laundry: laundry
    } do
      act(view, "chore", dishes.id, "rename")

      html = type_in_panel(view, "chore", title: "ab")

      assert %{fields: [%{errors: ["length must be greater than or equal to 3"]}]} =
               panel(html, "chore")

      cancel_panel(view, "chore")

      act(view, "chore", laundry.id, "rename")
      html = run_panel(view, "chore", title: "Washing")

      assert %{
               heading: "Rename: Laundry",
               fields: [%{errors: ["cannot change once the chore is done"]}]
             } =
               panel(html, "chore")

      assert chores() == ["Dishes", "Laundry"]
    end
  end

  describe "a generic row action on the selected rows" do
    setup %{conn: conn} do
      dishes = chore("Dishes")
      laundry = chore("Laundry", true)
      {:ok, view, html} = conn |> as(:member) |> live("/support/chores")
      %{view: view, html: html, dishes: dishes, laundry: laundry}
    end

    test "is offered on the line above the grid, unless it says `bulk? false`", %{html: html} do
      assert %{buttons: [_select_all, "Clear selection", "Finish", "Copy", "Rename"]} =
               selection(html, "chore")
    end

    test "asks first, and runs once per selected record", %{
      view: view,
      dishes: dishes,
      laundry: laundry
    } do
      bulk(view, "chore", "copy", [dishes.id, laundry.id])
      assert_reply view, %{ask: "Run “Copy” on 2 records?"}

      html = run_bulk(view, "chore", "copy", [dishes.id, laundry.id])

      assert bulk_result(html, "chore") == %{summary: "Copy: 2 done.", failures: []}
      assert chores() == ["Dishes", "Dishes again", "Laundry", "Laundry again"]
    end

    test "asks for its inputs once, and says of how many records the action refused them", %{
      view: view
    } do
      html = bulk(view, "chore", "rename", :all)
      assert_reply view, %{panel: true}

      assert %{heading: "Rename: 2 records", fields: [%{name: "title", value: ""}]} =
               panel(html, "chore")

      # a value the action refuses as such is shown at its field, and nothing runs
      html = run_panel(view, "chore", title: "ab")

      assert %{fields: [%{errors: ["length must be greater than or equal to 3"]}]} =
               panel(html, "chore")

      run_panel(view, "chore", title: "Chore")
      html = ran(view)

      assert panel(html, "chore") == nil

      assert bulk_result(html, "chore") == %{
               summary: "Rename: 1 done, 1 not done.",
               failures: ["Title: cannot change once the chore is done (1)"]
             }

      assert chores() == ["Chore", "Laundry"]
    end

    test "is not run on the selected rows when it says `bulk? false`, nor is a table action", %{
      view: view,
      dishes: dishes
    } do
      for name <- ["stamp", "count", "sweep"] do
        bulk(view, "chore", name, [dishes.id])
        assert_reply view, %{ok: false}
        run_bulk(view, "chore", name, [dishes.id])
      end

      assert chores() == ["Dishes", "Laundry"]
    end
  end

  describe "the table actions of a nested table" do
    setup %{conn: conn} do
      rota = Ash.create!(Rota, %{name: "Week 1"}, authorize?: false)
      other = Ash.create!(Rota, %{name: "Week 2"}, authorize?: false)

      early = Ash.create!(Shift, %{title: "Early", rota_id: rota.id}, authorize?: false)
      Ash.create!(Shift, %{title: "Late", rota_id: other.id}, authorize?: false)

      %{
        conn: conn,
        rota: rota,
        other: other,
        early: early,
        shifts: nested("rota", rota.id, "shifts")
      }
    end

    defp open_shifts(conn, role, rota) do
      {:ok, view, _html} = conn |> as(role) |> live("/support/rotas")
      expand(view, "rota", rota.id)
      toggle(view, "rota", rota.id, "shifts")
      {view, ran(view)}
    end

    test "are buttons on the line that names it, after its create button, for the actions a person can ever run",
         %{conn: conn, rota: rota} do
      {_view, html} = open_shifts(conn, :admin, rota)

      assert line_buttons(html, "rota", rota.id, "shifts") ==
               ["New shift", "Count", "Clear all", "Rename all"]

      # they look as the create button of the line does, and are no tab stops
      button = "[id='rota-row-#{rota.id}-l-shifts-do-count']"

      assert attribute(html, button, "class") ==
               attribute(html, "[id='rota-row-#{rota.id}-l-shifts-create']", "class")

      assert attribute(html, button, "tabindex") == ["-1"]

      # a nested table has no line of its own for them
      assert table_actions(html, nested("rota", rota.id, "shifts")) == []

      {_view, html} = open_shifts(conn, :member, rota)
      assert line_buttons(html, "rota", rota.id, "shifts") == ["New shift", "Count", "Rename all"]
    end

    test "are not on a line that is closed", %{conn: conn, rota: rota, other: other} do
      {view, html} = open_shifts(conn, :admin, rota)
      assert line_buttons(html, "rota", other.id, "shifts") == []

      html = toggle(view, "rota", rota.id, "shifts")
      assert line_buttons(html, "rota", rota.id, "shifts") == []
    end

    test "run on the nested table, which says what came of it and reads again; the action is not given the row above",
         %{conn: conn, rota: rota, shifts: shifts} do
      {view, _html} = open_shifts(conn, :member, rota)

      html = table_act(view, shifts, "count", on: "rota-row-#{rota.id}-l-shifts-do-count")

      # the shifts of every rota: nothing tells the action which rota it is under
      assert result(html, shifts) == "Count: 2"
      assert announcement(html, shifts) == "Count: 2"
      assert column(html, shifts, "title") == ["Early"]
      # the table around it says nothing
      assert result(html, "rota") == nil
    end

    test "open the nested table's own panel, and ask in its own dialog", %{
      conn: conn,
      rota: rota,
      shifts: shifts
    } do
      {view, _html} = open_shifts(conn, :admin, rota)

      html =
        table_act(view, shifts, "rename_all", on: "rota-row-#{rota.id}-l-shifts-do-rename_all")

      assert %{heading: "Rename all", fields: [%{name: "title"}]} = panel(html, shifts)
      assert panel(html, "rota") == nil

      run_panel(view, shifts, title: "Shift")
      html = ran(view)
      assert result(html, shifts) == "Rename all: 2"
      assert column(html, shifts, "title") == ["Shift"]

      table_act(view, shifts, "clear", on: "rota-row-#{rota.id}-l-shifts-do-clear")

      assert_push_event view, "ash_data_table:ask", %{
        table: ^shifts,
        action: :clear,
        question: "Remove every shift, of every rota?"
      }

      # the dialog the question is asked in is the nested table's
      assert render(view) |> attribute("[id='#{shifts}-dialog']", "id") == ["#{shifts}-dialog"]

      html = confirm_table_action(view, shifts, "clear")
      assert result(html, shifts) == "Clear all: done"
      assert column(html, shifts, "title") == []
      assert Ash.read!(Shift, authorize?: false) == []
    end

    test "a generic row action of the nested table is given the key of the nested row", %{
      conn: conn,
      rota: rota,
      early: early,
      shifts: shifts
    } do
      {view, html} = open_shifts(conn, :member, rota)
      assert actions(html, shifts, early.id) == ["Repeat"]

      act(view, shifts, early.id, "repeat")
      html = ran(view)

      assert result(html, shifts) == "Repeat: done"
      assert column(html, shifts, "title") |> Enum.sort() == ["Early", "Early again"]
    end

    test "are on the line of the full view, before the control that shows all records", %{
      conn: conn,
      rota: rota
    } do
      {_view, html} = open_shifts(conn, :admin, rota)
      path = html |> attribute("[id='rota-row-#{rota.id}-t-shifts-full-view']", "href") |> hd()

      {:ok, view, html} = conn |> as(:admin) |> live(path)

      assert html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#shift-related button, #shift-related a")
             |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim())) ==
               ["Week 1", "New shift", "Count", "Clear all", "Rename all", "Show all records"]

      assert result(table_act(view, "shift", "count"), "shift") == "Count: 2"
    end
  end
end
