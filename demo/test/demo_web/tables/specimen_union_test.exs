defmodule DemoWeb.Tables.SpecimenUnionTest do
  @moduledoc """
  A union in the mounted table of `Demo.KitchenSink.Specimen` at
  `/specimens`: "A union" is a number, a text, a shade or an address. The
  cell shows the value it holds, and it is edited in the side panel, the
  kind first. On Postgres.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator
  alias Demo.KitchenSink.Address
  alias Demo.KitchenSink.Specimen

  setup %{conn: conn} do
    Generator.reseed(1)

    specimen =
      Generator.generate(
        Generator.specimen(label: "Shown", a_union: %Ash.Union{type: :number, value: 12})
      )

    %{conn: conn, specimen: specimen}
  end

  defp union(value), do: Generator.generate(Generator.specimen(label: "Other", a_union: value))
  defp shown(html, specimen), do: text(html, cell("specimen", specimen.id, "a_union"))
  defp stored(specimen), do: Ash.get!(Specimen, specimen.id, authorize?: false).a_union
  defp field(html, name), do: Enum.find(panel(html, "specimen").fields, &(&1.name == name))
  defp names(html), do: Enum.map(panel(html, "specimen").fields, & &1.name)

  # What the union's field sends: the kind that is chosen, the kind its
  # value was given for, and the value.
  defp sent(kind, of \\ nil, value),
    do: %{"_union_type" => kind, "_of" => of || kind, "_union_value" => value}

  defp change(view, sent) do
    view
    |> element("[id='specimen-panel-form']")
    |> render_change(%{"panel" => %{"a_union" => sent}})
  end

  defp submit(view, sent), do: send_panel(view, "specimen", %{"panel" => %{"a_union" => sent}})

  describe "the cell" do
    test "shows the value the union holds, as a cell of its kind's type shows it", %{
      conn: conn,
      specimen: number
    } do
      text = union(%Ash.Union{type: :text, value: "urgent"})
      shade = union(%Ash.Union{type: :shade, value: :dark})

      address =
        union(%Ash.Union{
          type: :address,
          value: %Address{street: "Unionsweg 5", city: "Köln", primary?: true}
        })

      none = union(nil)

      {:ok, _view, html} = live(conn, "/specimens")

      assert shown(html, number) == "12"
      assert shown(html, text) == "urgent"
      assert shown(html, shade) == "Dark"
      assert shown(html, address) == "Street: Unionsweg 5, City: Köln, Primary?: Yes"
      assert shown(html, none) == ""
    end

    test "is editable, with nothing to open in the cell, and neither sorted nor filtered by", %{
      conn: conn,
      specimen: specimen
    } do
      {:ok, _view, html} = live(conn, "/specimens")

      assert attribute(html, cell("specimen", specimen.id, "a_union"), "aria-readonly") == []
      assert attribute(html, "[id='specimen-editor-a_union']", "data-editor") == ["union"]
      assert text(html, "[id='specimen-editor-a_union']") == ""

      assert attribute(html, "[id='specimen-head-a_union']", "aria-sort") == []

      assert filter_controls(html, "specimen", "a_union") ==
               %{operators: nil, input: nil, choices: nil}
    end
  end

  describe "the side panel" do
    test "opens with the kind and that kind's value, under the column's label", %{
      conn: conn,
      specimen: specimen
    } do
      {:ok, view, _html} = live(conn, "/specimens")
      html = edit(view, "specimen", specimen.id, "a_union")

      # a specimen is called by its key: its table names no `label_field`
      assert %{heading: heading, submit: "Save"} = panel(html, "specimen")
      assert heading == "A union: #{specimen.id}"
      assert names(html) == ["a_union", "a_union._union_type", "a_union._union_value"]

      assert %{label: "A union", control: "union", value: "number", required?: false} =
               field(html, "a_union")

      assert %{label: "Kind", control: "select", value: "number"} =
               field(html, "a_union._union_type")

      assert %{label: "Number", control: "number", value: "12"} =
               field(html, "a_union._union_value")

      # the kinds, in words, and none: the attribute may be empty
      assert html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("[id='specimen-panel-f-a_union-kind'] option")
             |> Enum.map(&String.trim(LazyHTML.text(&1))) == [
               "",
               "Number",
               "Text",
               "Shade",
               "Address"
             ]
    end

    test "a kind made of fields has those fields, each with the control of its type", %{
      conn: conn
    } do
      specimen =
        union(%Ash.Union{type: :address, value: %Address{street: "Unionsweg 5", city: "Köln"}})

      {:ok, view, _html} = live(conn, "/specimens")
      html = edit(view, "specimen", specimen.id, "a_union")

      assert names(html) == [
               "a_union",
               "a_union._union_type",
               "a_union._union_value.street",
               "a_union._union_value.city",
               "a_union._union_value.postcode",
               "a_union._union_value.primary?"
             ]

      assert %{label: "Street", control: "textarea", value: "Unionsweg 5", required?: true} =
               field(html, "a_union._union_value.street")

      assert %{control: "checkbox", value: "false"} = field(html, "a_union._union_value.primary?")
    end

    test "without a value there is the choice of the kind and nothing else", %{conn: conn} do
      specimen = union(nil)

      {:ok, view, _html} = live(conn, "/specimens")
      html = edit(view, "specimen", specimen.id, "a_union")

      assert names(html) == ["a_union", "a_union._union_type"]
      assert %{value: ""} = field(html, "a_union._union_type")
    end

    test "choosing another kind puts that kind's fields in place of the others, empty", %{
      conn: conn,
      specimen: specimen
    } do
      {:ok, view, _html} = live(conn, "/specimens")
      edit(view, "specimen", specimen.id, "a_union")

      # the browser sends the number that is still in the page
      html = change(view, sent("text", "number", "12"))

      assert %{label: "Text", control: "textarea", value: ""} =
               field(html, "a_union._union_value")

      assert field(html, "a_union").errors == []

      html = change(view, sent("shade", "text", "anything"))
      assert %{label: "Shade", control: "select", value: ""} = field(html, "a_union._union_value")

      html = change(view, sent("address", "shade", "dark"))

      assert %{control: "textarea", value: ""} = field(html, "a_union._union_value.street")
      refute field(html, "a_union._union_value")

      html = change(view, sent("", "address", %{"_present" => "", "street" => "x"}))
      assert names(html) == ["a_union", "a_union._union_type"]

      # nothing was saved
      assert stored(specimen) == %Ash.Union{type: :number, value: 12}
    end
  end

  describe "Save" do
    test "saves the kind's value through the column's update action, and the cell shows it", %{
      conn: conn,
      specimen: specimen
    } do
      {:ok, view, _html} = live(conn, "/specimens")
      edit(view, "specimen", specimen.id, "a_union")

      html = submit(view, sent("number", "40"))

      assert panel(html, "specimen") == nil
      assert shown(html, specimen) == "40"
      assert stored(specimen) == %Ash.Union{type: :number, value: 40}
    end

    test "saves another kind in place of the one the record held", %{
      conn: conn,
      specimen: specimen
    } do
      {:ok, view, _html} = live(conn, "/specimens")
      edit(view, "specimen", specimen.id, "a_union")
      change(view, sent("shade", "number", "12"))

      html = submit(view, sent("shade", "medium"))

      assert shown(html, specimen) == "Medium"
      assert stored(specimen) == %Ash.Union{type: :shade, value: :medium}

      edit(view, "specimen", specimen.id, "a_union")
      change(view, sent("address", "shade", "medium"))

      html =
        submit(
          view,
          sent("address", %{
            "_present" => "",
            "street" => "Kai 1",
            "city" => "Kiel",
            "postcode" => "",
            "primary?" => "true"
          })
        )

      assert shown(html, specimen) == "Street: Kai 1, City: Kiel, Primary?: Yes"

      assert %Ash.Union{
               type: :address,
               value: %Address{street: "Kai 1", city: "Kiel", primary?: true}
             } =
               stored(specimen)
    end

    test "a value that was typed for another kind is never saved as this one's", %{
      conn: conn,
      specimen: specimen
    } do
      {:ok, view, _html} = live(conn, "/specimens")
      edit(view, "specimen", specimen.id, "a_union")

      # "Text" is chosen and the panel is sent at once, with the number
      html = submit(view, sent("text", "number", "12"))

      assert shown(html, specimen) == ""
      assert stored(specimen) == %Ash.Union{type: :text, value: nil}
    end

    test "no kind takes the value away", %{conn: conn, specimen: specimen} do
      {:ok, view, _html} = live(conn, "/specimens")
      edit(view, "specimen", specimen.id, "a_union")

      html = submit(view, sent("", "number", "12"))

      assert panel(html, "specimen") == nil
      assert shown(html, specimen) == ""
      # Ash keeps the kind of a value that was taken away
      assert stored(specimen) in [nil, %Ash.Union{type: :number, value: nil}]

      # and the panel opens without a kind again
      html = edit(view, "specimen", specimen.id, "a_union")
      assert %{value: ""} = field(html, "a_union._union_type")
    end

    test "what the record holds already calls nothing", %{conn: conn, specimen: specimen} do
      {:ok, view, _html} = live(conn, "/specimens")
      edit(view, "specimen", specimen.id, "a_union")
      before = Ash.get!(Specimen, specimen.id, authorize?: false).updated_at

      html = submit(view, sent("number", "12"))

      assert panel(html, "specimen") == nil
      assert Ash.get!(Specimen, specimen.id, authorize?: false).updated_at == before
    end

    test "what the action says of a value is shown at the value's field, and the panel stays", %{
      conn: conn,
      specimen: specimen
    } do
      {:ok, view, _html} = live(conn, "/specimens")
      edit(view, "specimen", specimen.id, "a_union")

      html = submit(view, sent("number", "-3"))

      assert %{errors: ["must be greater than or equal to 0"], value: "-3"} =
               field(html, "a_union._union_value")

      assert field(html, "a_union").errors == []

      assert attribute(html, "[id='specimen-panel-f-a_union-value']", "aria-invalid") == ["true"]

      assert announcement(html, "specimen") ==
               "A union was not saved: A union: must be greater than or equal to 0"

      assert stored(specimen) == %Ash.Union{type: :number, value: 12}

      # and goes when the value is put right
      html = submit(view, sent("number", "3"))
      assert panel(html, "specimen") == nil
      assert shown(html, specimen) == "3"
    end

    test "what it says of a field of a kind made of fields is shown at that field", %{
      conn: conn,
      specimen: specimen
    } do
      {:ok, view, _html} = live(conn, "/specimens")
      edit(view, "specimen", specimen.id, "a_union")
      change(view, sent("address", "number", "12"))

      html =
        submit(
          view,
          sent("address", %{"_present" => "", "street" => "", "city" => "Kiel", "postcode" => ""})
        )

      assert %{errors: ["is required"]} = field(html, "a_union._union_value.street")
      assert %{errors: [], value: "Kiel"} = field(html, "a_union._union_value.city")

      assert announcement(html, "specimen") ==
               "A union was not saved: A union Street: is required"

      assert stored(specimen) == %Ash.Union{type: :number, value: 12}
    end

    test "errors are shown as a person types, at the field they have been in", %{
      conn: conn,
      specimen: specimen
    } do
      {:ok, view, _html} = live(conn, "/specimens")
      edit(view, "specimen", specimen.id, "a_union")

      html = change(view, sent("number", "-1"))

      assert %{errors: ["must be greater than or equal to 0"]} =
               field(html, "a_union._union_value")
    end
  end
end
