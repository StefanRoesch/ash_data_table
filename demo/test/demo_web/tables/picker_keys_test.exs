defmodule DemoWeb.Tables.PickerKeysTest do
  @moduledoc """
  The picker where a related record is not named by one UUID, and where what
  a person may read of it changes.

  The tables are of resources that exist for the tests only
  (`test/support/picker_tables.ex`), mounted at `/support/stops`. A stop is
  in a zone, whose primary key is a country and a number and which the stop
  points at by its code; and at a bay, whose key is its number and which
  the relationship reads through an action of its own, the free bays. A zone
  that is closed is read by admins alone, the zone of a stop that is sealed
  is seen by admins alone, and nobody reads any bay while
  `Demo.Support.Gate` is closed. A stop is also at a dock, which belongs to
  a region: its tenant, and nothing else, says whose docks are whose.
  """
  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Support.Gate
  alias Demo.Support.Route.{Bay, Dock, Stop, Zone}

  @zones "stop-pick-zone"
  @bays "stop-pick-bay"

  setup %{conn: conn} do
    Gate.open()

    for {country, number, code, name, closed} <- [
          {"DE", 1, "DE-N", "North", false},
          {"DE", 2, "DE-S", "South", false},
          {"FR", 1, "FR-X", "Closed", true}
        ] do
      Zone
      |> Ash.Changeset.for_create(:create, %{
        country: country,
        number: number,
        code: code,
        name: name,
        closed: closed
      })
      |> Ash.create!()
    end

    for {number, name, free} <- [{1, "Bay one", true}, {2, "Bay two", true}, {3, "Taken", false}] do
      Bay
      |> Ash.Changeset.for_create(:create, %{number: number, name: name, free: free})
      |> Ash.create!()
    end

    [stop, sealed] =
      for {title, sealed} <- [{"First stop", false}, {"Sealed stop", true}] do
        Stop
        |> Ash.Changeset.for_create(:create, %{
          title: title,
          sealed: sealed,
          zone_code: "DE-N",
          bay_number: 1
        })
        |> Ash.create!()
      end

    on_exit(fn ->
      Gate.open()
      Demo.Support.Ets.stop([Zone, Bay, Dock, Stop])
    end)

    %{conn: conn, stop: stop, sealed: sealed}
  end

  defp as(conn, reader),
    do: Phoenix.ConnTest.init_test_session(conn, %{"assigns" => %{reader: reader}})

  defp stored!(stop), do: Ash.get!(Stop, stop.id, authorize?: false)

  describe "a destination with a primary key of two attributes, pointed at by another attribute" do
    setup %{conn: conn} do
      {:ok, view, html} = conn |> as(%{role: :member}) |> live("/support/stops")
      %{view: view, html: html}
    end

    test "shows its label in the cell, and the cell is edited", %{html: html, stop: stop} do
      assert text(html, cell("stop", stop.id, "zone")) == "North"
      assert "zone" in editors(html, "stop")
    end

    test "is chosen from its table, whose rows are named by both parts of their key, and opens on the record the cell points at",
         %{view: view, stop: stop} do
      html = pick(view, "stop", stop.id, "zone")

      assert %{heading: "Zone: choose zone", buttons: ["Cancel", "None", "Choose"]} =
               picker(html, "stop")

      # the closed zone is no record this person may read
      assert Enum.sort(column(html, @zones, "name")) == ["North", "South"]

      # the hook is told the key of such a row on the row itself
      assert attribute(html, "[id='#{@zones}-row-DE-1']", "data-key") == [~s(["DE","1"])]

      # found by the code the stop holds, which is no part of the row's key
      assert current(html, @zones) == ["DE-1"]
    end

    test "a choice saves the destination's attribute that the relationship names: the code",
         %{view: view, stop: stop} do
      pick(view, "stop", stop.id, "zone")

      html = picked(view, "stop", ["DE", "2"])
      assert_reply view, %{ok: true}

      assert picker(html, "stop") == nil
      assert text(html, cell("stop", stop.id, "zone")) == "South"
      assert stored!(stop).zone_code == "DE-S"
    end

    test "the record the cell points at already calls nothing, and \"None\" empties the key",
         %{view: view, stop: stop} do
      pick(view, "stop", stop.id, "zone")
      html = picked(view, "stop", ["DE", "1"])
      assert_reply view, %{ok: true}
      assert text(html, cell("stop", stop.id, "zone")) == "North"

      pick(view, "stop", stop.id, "zone")
      html = picked(view, "stop", nil)
      assert text(html, cell("stop", stop.id, "zone")) == ""
      assert stored!(stop).zone_code == nil
    end

    test "a hand-made choice of a record the person may not read changes nothing, by whatever it is named",
         %{view: view, stop: stop} do
      pick(view, "stop", stop.id, "zone")

      for row <- [
            ["FR", "1"],
            ["FR", 1],
            "FR-X",
            ["DE"],
            ["DE", "1", "x"],
            ["DE", "nine"],
            "DE-1"
          ] do
        html =
          forge(view, "stop", "picked", %{"row" => row, "confirmed" => true})

        assert picker(html, "stop").error == "This record is no longer available.",
               inspect(row)

        refute html =~ "Closed"
      end

      assert stored!(stop).zone_code == "DE-N"
    end

    test "an admin, who reads the closed zone, is offered it and saves it", %{
      conn: conn,
      stop: stop
    } do
      {:ok, view, _html} = conn |> as(%{role: :admin}) |> live("/support/stops")

      html = pick(view, "stop", stop.id, "zone")
      assert Enum.sort(column(html, @zones, "name")) == ["Closed", "North", "South"]

      html = picked(view, "stop", ["FR", "1"])
      assert text(html, cell("stop", stop.id, "zone")) == "Closed"
      assert stored!(stop).zone_code == "FR-X"
    end
  end

  describe "a destination whose key is a number, read through the relationship's own action" do
    setup %{conn: conn} do
      {:ok, view, html} = conn |> as(%{role: :member}) |> live("/support/stops")
      %{view: view, html: html}
    end

    test "offers the records that action returns, which are the ones the cell can show", %{
      view: view,
      stop: stop
    } do
      html = pick(view, "stop", stop.id, "bay")

      assert picker(html, "stop").heading == "Bay: choose bay"
      # the free bays: the relationship's `read_action :free`
      assert Enum.sort(column(html, @bays, "name")) == ["Bay one", "Bay two"]
      assert current(html, @bays) == ["1"]
    end

    test "a choice saves the number, through the column's own action", %{view: view, stop: stop} do
      pick(view, "stop", stop.id, "bay")

      html = picked(view, "stop", "2")
      assert_reply view, %{ok: true}

      assert text(html, cell("stop", stop.id, "bay")) == "Bay two"
      # `rebay` leaves a trace
      assert %{bay_number: 2, rebays: 1} = stored!(stop)
    end

    test "the record the cell points at already runs no action", %{view: view, stop: stop} do
      pick(view, "stop", stop.id, "bay")

      html = picked(view, "stop", "1")
      assert_reply view, %{ok: true}

      assert picker(html, "stop") == nil
      assert text(html, cell("stop", stop.id, "bay")) == "Bay one"
      assert %{bay_number: 1, rebays: 0} = stored!(stop)
    end

    test "a hand-made choice of a record that action does not return changes nothing", %{
      view: view,
      stop: stop
    } do
      pick(view, "stop", stop.id, "bay")

      # bay three is taken: no record of the relationship, though anybody may read it
      for row <- ["3", 3, "three", "99"] do
        html =
          forge(view, "stop", "picked", %{"row" => row, "confirmed" => true})

        assert picker(html, "stop").error == "This record is no longer available."
      end

      assert stored!(stop).bay_number == 1
    end
  end

  describe "a key the person does not see on a record" do
    test "is not theirs to change there: the cell is read-only on that row, and a hand-made event opens nothing and changes nothing",
         %{conn: conn, stop: stop, sealed: sealed} do
      {:ok, view, html} = conn |> as(%{role: :member}) |> live("/support/stops")

      assert attribute(html, cell("stop", stop.id, "zone"), "aria-readonly") == []
      assert attribute(html, cell("stop", sealed.id, "zone"), "aria-readonly") == ["true"]
      # the bay of the same row is theirs to see, and to change
      assert attribute(html, cell("stop", sealed.id, "bay"), "aria-readonly") == []

      html = pick(view, "stop", sealed.id, "zone")
      assert_reply view, %{ok: false}
      assert picker(html, "stop") == nil

      # through the picker of another row's cell
      pick(view, "stop", stop.id, "zone")

      forge(view, "stop", "picked", %{"row" => ["DE", "2"], "for" => sealed.id})

      assert stored!(sealed).zone_code == "DE-N"
    end

    test "that is hidden from them while the picker is open is not changed by the choice: the cell says so",
         %{conn: conn, stop: stop} do
      {:ok, view, _html} = conn |> as(%{role: :member}) |> live("/support/stops")
      pick(view, "stop", stop.id, "zone")

      # sealed behind the table's back
      Ash.Seed.update!(stored!(stop), %{sealed: true})

      html = picked(view, "stop", ["DE", "2"])
      assert_reply view, %{ok: false}

      assert picker(html, "stop") == nil
      assert stored!(stop).zone_code == "DE-N"
      assert attribute(html, cell("stop", stop.id, "zone"), "aria-readonly") == ["true"]

      assert announcement(html, "stop") ==
               "Zone was not saved: You are not allowed to change this."
    end

    test "an admin sees it, and edits it", %{conn: conn, sealed: sealed} do
      {:ok, view, html} = conn |> as(%{role: :admin}) |> live("/support/stops")

      assert attribute(html, cell("stop", sealed.id, "zone"), "aria-readonly") == []

      pick(view, "stop", sealed.id, "zone")
      picked(view, "stop", ["DE", "2"])
      assert stored!(sealed).zone_code == "DE-S"
    end
  end

  describe "a destination that is refused while the page is open" do
    test "opens a picker that says the records are not available, and takes no choice", %{
      conn: conn,
      stop: stop
    } do
      {:ok, view, html} = conn |> as(%{role: :member}) |> live("/support/stops")
      assert "bay" in editors(html, "stop")

      Gate.close()
      html = pick(view, "stop", stop.id, "bay")

      assert picker(html, "stop").heading == "Bay: choose bay"
      assert text(html, "##{@bays}-error") == "These records are not available."
      assert column(html, @bays, "name") == []
      refute html =~ "Bay two"

      html = picked(view, "stop", "2")
      assert_reply view, %{ok: false}
      assert picker(html, "stop").error == "This record is no longer available."
      assert stored!(stop).bay_number == 1
    end

    test "a person who can never read it has no editor for the cell, and no column", %{
      conn: conn
    } do
      Gate.close()
      {:ok, _view, html} = conn |> as(%{role: :member}) |> live("/support/stops")

      assert headers(html, "stop") == ["Title", "Zone", "Dock"]
      assert editors(html, "stop") == ["title", "zone", "dock"]
    end
  end

  describe "in the action panel" do
    setup %{conn: conn} do
      {:ok, view, _html} = conn |> as(%{role: :member}) |> live("/support/stops")
      %{view: view}
    end

    defp field(html, name), do: Enum.find(panel(html, "stop").fields, &(&1.name == name))

    test "the fields hold the keys as they are written, and say what the records are called",
         %{view: view, stop: stop} do
      html = act(view, "stop", stop.id, "reroute")

      assert %{label: "Zone", control: "reference", value: "DE-N", chosen: "North"} =
               field(html, "zone_code")

      assert %{label: "Bay", control: "reference", value: "1", chosen: "Bay one"} =
               field(html, "bay_number")
    end

    test "a choice puts the destination's attribute into the field, for either kind of key",
         %{view: view, stop: stop} do
      act(view, "stop", stop.id, "reroute")

      pick_input(view, "stop", "zone_code")
      html = picked(view, "stop", ["DE", "2"])
      assert %{value: "DE-S", chosen: "South"} = field(html, "zone_code")

      html = pick_input(view, "stop", "bay_number")
      assert current(html, "stop-pick-bay_number") == ["1"]
      html = picked(view, "stop", "2")
      assert %{value: "2", chosen: "Bay two"} = field(html, "bay_number")

      run_panel(view, "stop", [])
      assert %{zone_code: "DE-S", bay_number: 2} = stored!(stop)
    end

    test "a hand-made form with the key of a record the person may not read runs nothing", %{
      view: view,
      stop: stop
    } do
      act(view, "stop", stop.id, "reroute")

      html = run_panel(view, "stop", zone_code: "FR-X")
      assert panel(html, "stop").errors == ["Zone: This record is no longer available."]

      # a bay that the relationship's read action does not return
      html = run_panel(view, "stop", zone_code: "DE-S", bay_number: "3")
      assert panel(html, "stop").errors == ["Bay: This record is no longer available."]

      assert %{zone_code: "DE-N", bay_number: 1} = stored!(stop)
    end

    test "the field of a key the person does not see on the record is no field of their panel",
         %{view: view, sealed: sealed} do
      html = act(view, "stop", sealed.id, "reroute")

      assert Enum.map(panel(html, "stop").fields, & &1.name) == ["bay_number"]
    end
  end

  describe "a destination that is multitenant, where the tenant alone says whose records are whose" do
    setup %{conn: conn} do
      [north, other, south] =
        for {name, region} <- [
              {"North dock", "north"},
              {"Other north dock", "north"},
              {"South dock", "south"}
            ] do
          Dock
          |> Ash.Changeset.for_create(:create, %{name: name, region: region})
          |> Ash.create!()
        end

      conn =
        Phoenix.ConnTest.init_test_session(conn, %{
          "assigns" => %{reader: %{role: :member}, current_tenant: "north"}
        })

      {:ok, view, _html} = live(conn, "/support/stops")
      %{view: view, north: north, other: other, south: south}
    end

    test "the picker offers the records of the person's tenant", %{view: view, stop: stop} do
      html = pick(view, "stop", stop.id, "dock")

      assert Enum.sort(column(html, "stop-pick-dock", "name")) ==
               ["North dock", "Other north dock"]

      refute html =~ "South dock"
    end

    test "a choice of one of them saves", %{view: view, stop: stop, north: north} do
      pick(view, "stop", stop.id, "dock")
      html = picked(view, "stop", north.id)

      assert text(html, cell("stop", stop.id, "dock")) == "North dock"
      assert stored!(stop).dock_id == north.id
    end

    test "a hand-made choice of a record of another tenant changes nothing", %{
      view: view,
      stop: stop,
      south: south
    } do
      pick(view, "stop", stop.id, "dock")

      html = picked(view, "stop", south.id)
      assert_reply view, %{ok: false}

      assert picker(html, "stop").error == "This record is no longer available."
      assert stored!(stop).dock_id == nil
    end

    test "nor does a hand-made form of the action panel with the key of one", %{
      view: view,
      stop: stop,
      north: north,
      south: south
    } do
      act(view, "stop", stop.id, "dock_at")

      html = run_panel(view, "stop", dock_id: south.id)
      assert panel(html, "stop").errors == ["Dock: This record is no longer available."]
      assert stored!(stop).dock_id == nil

      # a hand-made choice in the panel's picker puts nothing into the field
      pick_input(view, "stop", "dock_id")
      html = picked(view, "stop", south.id)
      assert picker(html, "stop").error == "This record is no longer available."
      assert %{value: "", chosen: nil} = field(html, "dock_id")

      cancel_picker(view, "stop")
      html = run_panel(view, "stop", dock_id: north.id)
      assert panel(html, "stop") == nil
      assert stored!(stop).dock_id == north.id
    end
  end
end
