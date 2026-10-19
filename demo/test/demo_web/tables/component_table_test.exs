defmodule DemoWeb.Tables.ComponentTableTest do
  @moduledoc """
  What a table does with a column's `component`: where it calls the part that
  shows and the part that edits, what it gives them, and what it never does.

  The table is of a resource that exists for the tests only
  (`Demo.Support.Styled.Gauge` in `test/support/component_tables.ex`), mounted
  at `/support/gauges`; its records are kept in memory. Its components write
  what they were given into the page, and one of them
  (`DemoWeb.Support.Cells.Probe`) raises when it is given a hidden value,
  nothing, a record, or an assign that is not documented. `code` is seen by
  an admin only, `amount` by an admin and by a gauge's owner; a viewer
  changes nothing.
  """
  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Support.Styled.Gauge

  @admin %{id: "ada", name: "ada", role: :admin}
  @member %{id: "max", name: "max", role: :member}
  @viewer %{id: "vera", name: "vera", role: :viewer}

  setup do
    on_exit(fn -> Demo.Support.Ets.stop(Gauge) end)
  end

  defp gauge(attributes \\ %{}) do
    Gauge
    |> Ash.Changeset.for_create(
      :create,
      Map.merge(
        %{
          name: "Boiler",
          level: 4,
          amount: 100,
          state: :busy,
          volume: 7,
          code: "G-1",
          owner: "max"
        },
        attributes
      )
    )
    |> Ash.create!(authorize?: false)
  end

  defp stored(gauge), do: Ash.get!(Gauge, gauge.id, authorize?: false)

  defp open(conn, actor) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{"assigns" => %{current_user: actor}})
    |> live("/support/gauges")
  end

  # the one element matching `selector`, as a tree
  defp tree(html, selector) do
    [node] = html |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> LazyHTML.to_tree()
    node
  end

  describe "a cell of a column whose component shows" do
    test "is the table's own cell, with its id and what it says of itself, around the component's markup",
         %{conn: conn} do
      gauge = gauge()
      {:ok, _view, html} = open(conn, @admin)

      assert {_cell, attributes, [{"span", probe, ["4"]}]} =
               tree(html, cell("gauge", gauge.id, "level"))

      assert {"id", "gauge-row-#{gauge.id}-c-level"} in attributes
      assert {"role", "cell"} in attributes
      # after the boxes of the rows and the first column
      assert {"aria-colindex", "3"} in attributes
      # an editable cell: a Tab stop
      assert {"tabindex", "0"} in attributes
      assert {"data-probe", "level"} in probe
    end

    test "of a value that is hidden from the person is the table's placeholder: the component is not called",
         %{conn: conn} do
      own = gauge(%{name: "Own", owner: "max"})
      other = gauge(%{name: "Other", owner: "ada"})
      {:ok, _view, html} = open(conn, @member)

      # the member's own gauge: the component, with the value
      assert {_cell, _, [{"span", probe, ["100"]}]} = tree(html, cell("gauge", own.id, "amount"))
      assert {"data-probe", "amount"} in probe

      # another's: what a hidden cell of any column is, and nothing of the component
      assert {_cell, attributes,
              [{"span", [{"class", "sr-only"}, {"data-unseen", ""}], ["Not available"]}]} =
               tree(html, cell("gauge", other.id, "amount"))

      refute List.keymember?(attributes, "tabindex", 0)
    end

    test "of a record that has no value is empty, as an empty cell of any column: the component is not called",
         %{conn: conn} do
      gauge = gauge(%{level: nil, state: nil})
      {:ok, _view, html} = open(conn, @admin)

      assert {_cell, _attributes, []} = tree(html, cell("gauge", gauge.id, "level"))
      assert {_cell, _attributes, []} = tree(html, cell("gauge", gauge.id, "state"))
    end

    test "the component is given the value, the text the table would show, and the column: nothing else",
         %{conn: conn} do
      gauge = gauge()
      {:ok, _view, html} = open(conn, @admin)

      assert {_cell, _, [{"span", probe, ["Busy"]}]} =
               tree(html, cell("gauge", gauge.id, "state"))

      assert {"data-given", "column text value"} in probe
      # the value as the record holds it, and the label of that choice as text
      assert {"data-value", ":busy"} in probe

      assert {_cell, _, [{"span", probe, ["100"]}]} =
               tree(html, cell("gauge", gauge.id, "amount"))

      assert {"data-value", "100"} in probe
    end

    test "says what its editor starts with, which is no longer the text it shows", %{conn: conn} do
      gauge = gauge()
      {:ok, _view, html} = open(conn, @admin)

      assert attribute(html, cell("gauge", gauge.id, "level"), "data-value") == ["4"]
      assert attribute(html, cell("gauge", gauge.id, "state"), "data-value") == ["busy"]
      # a column whose component only edits shows the table's own text, which the editor takes
      assert attribute(html, cell("gauge", gauge.id, "volume"), "data-value") == []
    end

    test "is shown by the component for a person who can never edit the column, who has no editor for it",
         %{conn: conn} do
      gauge = gauge()
      {:ok, _view, html} = open(conn, @viewer)

      assert {_cell, attributes, [{"span", probe, ["4"]}]} =
               tree(html, cell("gauge", gauge.id, "level"))

      assert {"data-probe", "level"} in probe
      # nothing of this table is theirs to edit, so no cell says anything about editing
      refute List.keymember?(attributes, "data-value", 0)
      assert editors(html, "gauge") == []
    end
  end

  # a column's editor template: its attributes, and the one element in it
  defp template(html, field) do
    {"template", attributes, children} = tree(html, "template[id='gauge-editor-#{field}']")
    [root] = Enum.reject(children, &is_binary/1)
    {Map.new(attributes), root}
  end

  describe "the editor of a column whose component edits" do
    setup %{conn: conn} do
      gauge = gauge()
      {:ok, view, html} = open(conn, @admin)
      %{gauge: gauge, view: view, html: html}
    end

    test "is the component's, in the column's template, which says when it saves", %{html: html} do
      assert editors(html, "gauge") == ~w(name level amount state volume code)

      assert {%{"data-editor" => "component", "data-commit" => "enter"},
              {"span", probe, [{"input", _, _}]}} = template(html, "level")

      assert {"data-probe-editor", "level"} in probe

      assert {%{"data-editor" => "component", "data-commit" => "change"}, {"span", dial, _}} =
               template(html, "volume")

      assert {"data-dial", "volume"} in dial

      # a column without a component has the editor of its type, which says nothing about when
      assert {attributes, {"textarea", _, _}} = template(html, "name")
      assert attributes["data-editor"] == "text"
      refute is_map_key(attributes, "data-commit")
    end

    test "is given the column, its label, where it is, an empty value and what goes on its control: nothing else",
         %{html: html} do
      {_template, {"span", probe, [{"input", control, []}]}} = template(html, "level")
      probe = Map.new(probe)

      assert probe["data-given"] == "column control label place value"
      assert probe["data-place"] == "grid"
      assert probe["data-label"] == "Rung"
      # what the resource knows about the field
      assert probe["data-type"] == "Ash.Type.Integer"
      assert probe["data-max"] == "10"

      # the template is one for all cells of the column: the table puts the
      # cell's value into the control when it opens the editor
      assert {"value", ""} in control
      # what the table needs on the control: its name for a screen reader,
      # and the mark the table finds it by
      assert {"aria-label", "Rung"} in control
      assert List.keymember?(control, "data-control", 0)
      refute List.keymember?(control, "name", 0)
      refute List.keymember?(control, "id", 0)
    end
  end

  describe "a save through a component's editor" do
    test "runs the column's update action with the cell's value, and the row comes back through the component",
         %{conn: conn} do
      gauge = gauge()
      {:ok, view, _html} = open(conn, @admin)

      html = save(view, "gauge", gauge.id, "level", "7")

      assert %{level: 7, trace: "set_level"} = stored(gauge)
      assert {_cell, _, [{"span", probe, ["7"]}]} = tree(html, cell("gauge", gauge.id, "level"))
      assert {"data-value", "7"} in probe
      assert failure(html, "gauge", gauge.id, "level") == nil
    end

    test "takes the row, the column and the value from the browser, and nothing else", %{
      conn: conn
    } do
      gauge = gauge()
      {:ok, view, _html} = open(conn, @admin)

      forge(view, "gauge", "save", %{
        "row" => to_string(gauge.id),
        "column" => "level",
        "value" => "7",
        # what a component's markup, or a person, might send besides
        "action" => "update",
        "update_action" => "update",
        "name" => "Renamed",
        "amount" => "1",
        "params" => %{"name" => "Renamed", "code" => "X"},
        "cell" => %{"name" => "Renamed", "level" => "9"}
      })

      assert %{level: 7, trace: "set_level", name: "Boiler", amount: 100, code: "G-1"} =
               stored(gauge)
    end

    test "that the resource refuses marks the cell with what was typed and the action's message",
         %{conn: conn} do
      gauge = gauge()
      {:ok, view, _html} = open(conn, @admin)

      html = save(view, "gauge", gauge.id, "level", "11")

      assert stored(gauge).level == 4

      # what was typed is shown as it was typed: it is no value of the field,
      # so the component is not asked to show it
      assert failure(html, "gauge", gauge.id, "level") ==
               %{shown: "11", message: "must be less than or equal to 10"}

      assert attribute(html, cell("gauge", gauge.id, "level") <> " [data-probe]", "data-probe") ==
               []

      assert attribute(html, cell("gauge", gauge.id, "level"), "data-value") == ["11"]
      assert attribute(html, cell("gauge", gauge.id, "level"), "data-saved") == ["4"]
      assert announcement(html, "gauge") == "Rung was not saved: must be less than or equal to 10"

      # given up, the cell is the component's again, with the record's value
      html = discard(view, "gauge", gauge.id, "level")
      assert {_cell, _, [{"span", _probe, ["4"]}]} = tree(html, cell("gauge", gauge.id, "level"))
    end

    test "is refused for a person who can never edit the column", %{conn: conn} do
      gauge = gauge()
      {:ok, view, _html} = open(conn, @viewer)

      html = save(view, "gauge", gauge.id, "level", "7")

      assert stored(gauge).level == 4
      assert {_cell, _, [{"span", _probe, ["4"]}]} = tree(html, cell("gauge", gauge.id, "level"))
    end

    test "is refused for a column the table lets nobody edit, though its component edits and an action would accept the value",
         %{conn: conn} do
      gauge = gauge()
      {:ok, view, html} = open(conn, @admin)

      # the component shows, and the column has no editor
      assert {_cell, attributes, [{"span", _probe, ["max"]}]} =
               tree(html, cell("gauge", gauge.id, "owner"))

      refute List.keymember?(attributes, "tabindex", 0)
      refute "owner" in editors(html, "gauge")

      save(view, "gauge", gauge.id, "owner", "ada")

      assert stored(gauge).owner == "max"
    end

    test "is refused for a cell whose value is hidden from the person", %{conn: conn} do
      gauge = gauge(%{owner: "ada"})
      {:ok, view, _html} = open(conn, @member)

      html = save(view, "gauge", gauge.id, "amount", "1")

      assert stored(gauge).amount == 100

      assert announcement(html, "gauge") ==
               "Amount was not saved: You are not allowed to change this."

      # the cell is as hidden as it was
      assert {_cell, _,
              [{"span", [{"class", "sr-only"}, {"data-unseen", ""}], ["Not available"]}]} =
               tree(html, cell("gauge", gauge.id, "amount"))
    end
  end

  # one field of the open panel: what is in it besides the table's own label
  # and messages
  defp field(html, name) do
    {"div", _, children} = tree(html, "#gauge-panel [data-field='#{name}']")

    for {tag, attributes, inner} <- children,
        tag not in ["label", "div"],
        do: {tag, Map.new(attributes), inner}
  end

  describe "the action panel" do
    test "has the component's editor as the field of an attribute whose column has one, under the table's label",
         %{conn: conn} do
      gauge = gauge()
      {:ok, view, _html} = open(conn, @admin)

      html = act(view, "gauge", gauge.id, "tune")

      assert Enum.map(panel(html, "gauge").fields, &{&1.name, &1.label, &1.control, &1.value}) ==
               [
                 {"level", "Rung", "number", "4"},
                 {"volume", "Volume", "range", "7"},
                 {"name", "Name", "textarea", "Boiler"},
                 {"amount", "Amount", "number", "100"},
                 {"reason", "Reason", "textarea", ""}
               ]

      assert [{"span", probe, [{"input", control, []}]}] = field(html, "level")
      assert probe["data-probe-editor"] == "level"
      assert probe["data-given"] == "column control label place value"
      assert probe["data-place"] == "panel"
      assert probe["data-label"] == "Rung"

      # what the panel needs on the control: the id its label points at and
      # the name its value is sent under
      assert {"id", "gauge-panel-f-level"} in control
      assert {"name", "panel[level]"} in control
      assert {"value", "4"} in control
      assert List.keymember?(control, "data-control", 0)
      # named by the label above it, as every field of the panel
      refute List.keymember?(control, "aria-label", 0)

      assert attribute(html, "#gauge-panel [data-field='level'] > label", "for") == [
               "gauge-panel-f-level"
             ]
    end

    test "runs the action with what the component's control holds", %{conn: conn} do
      gauge = gauge()
      {:ok, view, _html} = open(conn, @admin)
      act(view, "gauge", gauge.id, "tune")

      html = run_panel(view, "gauge", level: "9", volume: "3")

      assert panel(html, "gauge") == nil
      assert %{level: 9, volume: 3, trace: "tune", name: "Boiler"} = stored(gauge)
      assert {_cell, _, [{"span", _probe, ["9"]}]} = tree(html, cell("gauge", gauge.id, "level"))
    end

    test "shows what the action says about the field under the component, and says so on its control",
         %{conn: conn} do
      gauge = gauge()
      {:ok, view, _html} = open(conn, @admin)
      act(view, "gauge", gauge.id, "tune")

      html = run_panel(view, "gauge", level: "11")

      assert stored(gauge).level == 4
      assert [level | _] = panel(html, "gauge").fields
      assert %{name: "level", value: "11", errors: ["must be less than or equal to 10"]} = level

      assert [{"span", _probe, [{"input", control, []}]}] = field(html, "level")
      assert {"aria-invalid", "true"} in control
      assert {"aria-describedby", "gauge-panel-f-level-error"} in control
      assert text(html, "#gauge-panel-f-level-error") == "must be less than or equal to 10"
    end

    test "marks a required field on the component's control, and starts a create with the default",
         %{conn: conn} do
      {:ok, view, _html} = open(conn, @admin)

      html = open_create(view, "gauge")

      assert %{name: "volume", control: "range", value: "5", required?: true} =
               Enum.find(panel(html, "gauge").fields, &(&1.name == "volume"))

      assert %{name: "level", value: "", required?: false} =
               Enum.find(panel(html, "gauge").fields, &(&1.name == "level"))

      html = run_panel(view, "gauge", name: "Kettle", level: "2", volume: "8")

      assert panel(html, "gauge") == nil
      assert [%{name: "Kettle", level: 2, volume: 8}] = Ash.read!(Gauge, authorize?: false)
    end

    test "has no field for an attribute that is hidden from the person on the record, and takes none from the browser",
         %{conn: conn} do
      gauge = gauge(%{owner: "ada"})
      {:ok, view, _html} = open(conn, @member)

      html = act(view, "gauge", gauge.id, "tune")
      assert Enum.map(panel(html, "gauge").fields, & &1.name) == ~w(level volume name reason)

      send_panel(view, "gauge", %{"panel" => %{"level" => "6", "amount" => "1", "code" => "X"}})

      assert %{level: 6, amount: 100, code: "G-1"} = stored(gauge)
    end
  end

  describe "in German" do
    defp open_in_german(conn, actor) do
      conn
      |> Phoenix.ConnTest.init_test_session(%{"assigns" => %{current_user: actor}})
      |> in_locale("de")
      |> live("/support/gauges")
    end

    test "a component is given the column's label and the labels of its choices in German", %{
      conn: conn
    } do
      gauge = gauge(%{state: :done})
      {:ok, _view, html} = open_in_german(conn, @admin)

      assert {_cell, _, [{"span", probe, ["Erledigt"]}]} =
               tree(html, cell("gauge", gauge.id, "state"))

      probe = Map.new(probe)
      assert probe["data-column-label"] == "Status"
      assert probe["data-choices"] == "Idle,Busy,Erledigt"
      # the value is the record's, whatever the language
      assert probe["data-value"] == ":done"

      # the editor is named in German
      assert {_template, {"span", editor, [{"input", control, []}]}} = template(html, "state")
      assert {"data-label", "Status"} in editor
      assert {"aria-label", "Status"} in control
    end

    test "a hidden value is the table's placeholder, in German", %{conn: conn} do
      gauge = gauge(%{owner: "ada"})
      {:ok, _view, html} = open_in_german(conn, @member)

      assert text(html, cell("gauge", gauge.id, "amount")) == "Nicht verfügbar"
    end
  end
end
