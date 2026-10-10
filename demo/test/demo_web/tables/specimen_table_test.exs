defmodule DemoWeb.Tables.SpecimenTableTest do
  @moduledoc """
  The mounted table of `Demo.KitchenSink.Specimen` at `/specimens`: one column
  per built-in Ash type, to see how each type's values are shown.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator
  alias Demo.KitchenSink.Address

  setup %{conn: conn} do
    Generator.reseed(1)

    Generator.generate(
      Generator.specimen(
        label: "Shown",
        a_string: "Plain <text> & more",
        a_ci_string: Ash.CiString.new("MiXed"),
        an_atom: :green,
        an_integer: -42,
        a_float: 0.25,
        a_decimal: Decimal.new("1234.50"),
        a_boolean: true,
        a_date: ~D[2026-03-09],
        a_time: ~T[07:05:00],
        a_utc_datetime: ~U[2026-03-09 14:30:05Z],
        a_utc_datetime_usec: ~U[2026-03-09 14:30:05.123456Z],
        a_naive_datetime: ~N[2026-03-09 14:30:05],
        a_duration_name: :week,
        a_uuid: "11111111-2222-4333-8444-555555555555",
        a_map: %{"colour" => "red"},
        a_module: Enum,
        strings: ["one", "two"],
        integers: [3, 4],
        shades: [:light, :dark],
        an_address: %Address{street: "Hauptstraße 1", city: "Köln", postcode: nil, primary?: true},
        addresses: [
          %Address{street: "Am Hafen 2", city: "Kiel", postcode: "24103", primary?: false},
          %Address{street: "Ring 3", city: "Bonn", postcode: nil, primary?: true}
        ],
        a_typed_map: %{name: "Dana", count: 4},
        a_percentage: 80,
        a_shade: :medium,
        opt_string: nil,
        opt_integer: nil,
        opt_decimal: nil,
        opt_boolean: false,
        opt_date: nil,
        opt_utc_datetime: nil,
        opt_shade: nil
      )
    )

    {:ok, _view, html} = live(conn, "/specimens")
    %{html: html}
  end

  defp shown(html, field) do
    [value] = column(html, "specimen", field)
    value
  end

  test "has a column for every public attribute", %{html: html} do
    assert length(headers(html, "specimen")) == 47
    assert Enum.take(headers(html, "specimen"), 4) == ["ID", "Label", "A string", "A ci string"]
  end

  test "text is shown as it is", %{html: html} do
    assert shown(html, "a_string") == "Plain <text> & more"
    assert shown(html, "a_ci_string") == "MiXed"
  end

  test "numbers are shown plainly", %{html: html} do
    assert shown(html, "an_integer") == "-42"
    assert shown(html, "a_float") == "0.25"
    assert shown(html, "a_decimal") == "1234.50"
    assert shown(html, "a_percentage") == "80"
  end

  test "a boolean is a mark with its meaning in words", %{html: html} do
    assert shown(html, "a_boolean") == "✓Yes"
    assert shown(html, "opt_boolean") == "–No"

    assert attribute(html, "#specimen-table td[id$='-c-a_boolean'] [aria-hidden=true]", "class") ==
             []

    assert text(html, "#specimen-table td[id$='-c-a_boolean'] .sr-only") == "Yes"
  end

  test "dates and datetimes are shown in the format of the native inputs", %{html: html} do
    assert shown(html, "a_date") == "2026-03-09"
    assert shown(html, "a_utc_datetime") == "2026-03-09T14:30:05"
    assert shown(html, "a_utc_datetime_usec") == "2026-03-09T14:30:05"
    assert shown(html, "a_naive_datetime") == "2026-03-09T14:30:05"
  end

  test "an enum is shown by its label", %{html: html} do
    assert shown(html, "a_shade") == "Medium"
    assert shown(html, "an_atom") == "Green"
    assert shown(html, "a_duration_name") == "Week"
  end

  test "nil is empty", %{html: html} do
    for field <- ~w(opt_string opt_integer opt_decimal opt_date opt_utc_datetime opt_shade) do
      assert shown(html, field) == "", field
    end
  end

  test "an array is shown as its values, separated by commas, each as a cell of its type shows it",
       %{html: html} do
    assert shown(html, "strings") == "one, two"
    assert shown(html, "integers") == "3, 4"
    # the labels of an enum's values
    assert shown(html, "shades") == "Light, Dark"
  end

  test "an embedded resource and a map are shown on one line, field by field; an array of them with semicolons between",
       %{html: html} do
    assert shown(html, "an_address") == "Street: Hauptstraße 1, City: Köln, Primary?: Yes"

    assert shown(html, "addresses") ==
             "Street: Am Hafen 2, City: Kiel, Postcode: 24103, Primary?: No; Street: Ring 3, City: Bonn, Primary?: Yes"

    assert shown(html, "a_typed_map") == "Name: Dana, Count: 4"
    # a map that declares no fields: whatever it holds
    assert shown(html, "a_map") == "Colour: red"
  end

  test "every other type is shown as text", %{html: html} do
    assert shown(html, "a_uuid") == "11111111-2222-4333-8444-555555555555"
    assert shown(html, "a_time") == "07:05:00"
    assert shown(html, "a_module") == "Enum"
    # what has no cell of its own is shown as Elixir writes it
    assert shown(html, "a_keyword") =~ "unit"
    assert shown(html, "a_struct") =~ "Demo.KitchenSink.Dimensions"
  end
end
