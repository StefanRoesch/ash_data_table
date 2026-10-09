defmodule DemoWeb.Tables.SpecimenEditTest do
  @moduledoc """
  Inline editing in the mounted table of `Demo.KitchenSink.Specimen` at
  `/specimens`: every type with an editor beside every type without one.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator

  setup %{conn: conn} do
    Generator.reseed(1)

    specimen =
      Generator.generate(
        Generator.specimen(
          label: "Shown",
          a_string: "Plain text",
          a_ci_string: Ash.CiString.new("MiXed"),
          an_atom: :green,
          an_integer: -42,
          a_float: 0.25,
          a_decimal: Decimal.new("1234.50"),
          a_boolean: true,
          a_date: ~D[2026-03-09],
          a_utc_datetime: ~U[2026-03-09 14:30:05Z],
          a_utc_datetime_usec: ~U[2026-03-09 14:30:05.123456Z],
          a_datetime: ~U[2026-03-09 14:30:05Z],
          a_naive_datetime: ~N[2026-03-09 14:30:05],
          strings: ["one", "two"],
          integers: [3, 4],
          shades: [:light, :dark],
          a_percentage: 80,
          a_shade: :medium,
          opt_string: "Something",
          opt_integer: 7,
          opt_decimal: Decimal.new("1.5"),
          opt_boolean: false,
          opt_date: ~D[2026-03-10],
          opt_utc_datetime: ~U[2026-03-10 08:00:00Z],
          opt_shade: :dark,
          inserted_at: ~U[2026-03-01 08:00:00.000000Z],
          updated_at: ~U[2026-03-01 09:00:00.000000Z]
        )
      )

    {:ok, view, html} = live(conn, "/specimens")
    %{conn: conn, view: view, html: html, specimen: specimen}
  end

  defp shown(html, specimen, field), do: text(html, cell("specimen", specimen.id, field))
  defp html(view), do: render(view)

  @editable ~w(label a_string a_ci_string an_atom an_integer a_float a_decimal a_boolean a_date
               a_utc_datetime a_utc_datetime_usec a_datetime a_naive_datetime a_duration_name
               strings integers shades a_percentage a_shade opt_string opt_integer opt_decimal
               opt_boolean opt_date opt_utc_datetime opt_shade)

  # an array of embedded resources among them: its values have no editor
  @read_only ~w(id a_time a_time_usec a_duration a_uuid a_uuid_v7 a_binary a_url_encoded_binary
                a_map a_typed_map a_keyword a_tuple a_struct a_term a_module a_date_range
                an_address addresses a_union inserted_at updated_at)

  describe "what can be edited" do
    test "the types with an editor have one; the others, and what the action does not accept, are read-only",
         %{html: html, specimen: specimen} do
      assert editors(html, "specimen") == @editable

      for field <- @editable do
        assert attribute(html, cell("specimen", specimen.id, field), "aria-readonly") == [], field
      end

      for field <- @read_only do
        assert attribute(html, cell("specimen", specimen.id, field), "aria-readonly") == ["true"],
               field
      end
    end
  end

  describe "saving" do
    @saves [
      {"a_string", "Other text", "Other text"},
      {"a_ci_string", "lower", "lower"},
      {"an_atom", "blue", "Blue"},
      {"an_integer", "17", "17"},
      {"a_float", "0.75", "0.75"},
      {"a_decimal", "99.90", "99.90"},
      {"a_boolean", "false", "–No"},
      {"a_date", "2027-01-31", "2027-01-31"},
      {"a_utc_datetime", "2027-01-31T23:59:58", "2027-01-31T23:59:58"},
      {"a_utc_datetime_usec", "2027-01-31T23:59:58", "2027-01-31T23:59:58"},
      {"a_datetime", "2027-01-31T23:59:58", "2027-01-31T23:59:58"},
      {"a_naive_datetime", "2027-01-31T23:59:58", "2027-01-31T23:59:58"},
      {"a_duration_name", "month", "Month"},
      {"a_percentage", "55", "55"},
      {"a_shade", "light", "Light"},
      {"opt_boolean", "true", "✓Yes"},
      {"opt_shade", "medium", "Medium"}
    ]

    for {field, typed, shown} <- @saves do
      test "#{field} shows the new value in the row and when the page is reopened",
           %{conn: conn, view: view, specimen: specimen} do
        html = save(view, "specimen", specimen.id, unquote(field), unquote(typed))
        assert shown(html, specimen, unquote(field)) == unquote(shown)

        {:ok, _view, html} = live(conn, "/specimens")
        assert shown(html, specimen, unquote(field)) == unquote(shown)
      end
    end

    test "an array of text and one of numbers are saved value by value", %{
      conn: conn,
      view: view,
      specimen: specimen
    } do
      assert editor(html(view), "specimen", "strings").control == {"list", "textarea"}
      assert editor(html(view), "specimen", "integers").control == {"list", "number"}

      html = save(view, "specimen", specimen.id, "strings", ["three", "one", "four"])
      assert shown(html, specimen, "strings") == "three, one, four"

      html = save(view, "specimen", specimen.id, "integers", ["10", "0"])
      assert shown(html, specimen, "integers") == "10, 0"

      assert %{strings: ["three", "one", "four"], integers: [10, 0]} =
               Ash.get!(Demo.KitchenSink.Specimen, specimen.id)

      {:ok, _view, html} = live(conn, "/specimens")
      assert shown(html, specimen, "strings") == "three, one, four"
      assert shown(html, specimen, "integers") == "10, 0"
    end

    test "an array of enum values is saved as multiple choice", %{
      conn: conn,
      view: view,
      specimen: specimen
    } do
      assert editor(html(view), "specimen", "shades") == %{
               control: "choices",
               choices: ["Light", "Medium", "Dark"],
               confirm: nil
             }

      html = save(view, "specimen", specimen.id, "shades", ["medium", "dark"])
      assert shown(html, specimen, "shades") == "Medium, Dark"
      assert Ash.get!(Demo.KitchenSink.Specimen, specimen.id).shades == [:medium, :dark]

      # nothing ticked: the empty array
      html = save(view, "specimen", specimen.id, "shades", [])
      assert shown(html, specimen, "shades") == ""
      assert failure(html, "specimen", specimen.id, "shades") == nil

      {:ok, _view, html} = live(conn, "/specimens")
      assert shown(html, specimen, "shades") == ""
    end

    test "an array the action refuses is shown as it was typed, with the action's message",
         %{view: view, specimen: specimen} do
      # `integers` has to have a value, and its values may not be negative
      html = save(view, "specimen", specimen.id, "integers", [])

      assert failure(html, "specimen", specimen.id, "integers") == %{
               shown: "",
               message: "must have 1 or more items"
             }

      html = save(view, "specimen", specimen.id, "integers", ["5", "-1"])

      assert failure(html, "specimen", specimen.id, "integers") == %{
               shown: "5, -1",
               message: "Integers 2: must be greater than or equal to 0"
             }

      # `strings` takes five values at most
      html = save(view, "specimen", specimen.id, "strings", ~w(a b c d e f))

      assert failure(html, "specimen", specimen.id, "strings") == %{
               shown: "a, b, c, d, e, f",
               message: "must have 5 or fewer items"
             }

      assert %{strings: ["one", "two"], integers: [3, 4]} =
               Ash.get!(Demo.KitchenSink.Specimen, specimen.id)
    end

    test "empty input empties every kind of field that can be empty",
         %{conn: conn, view: view, specimen: specimen} do
      fields = ~w(opt_string opt_integer opt_decimal opt_date opt_utc_datetime opt_shade)

      for field <- fields do
        html = save(view, "specimen", specimen.id, field, "")

        assert shown(html, specimen, field) == "", field
        assert failure(html, "specimen", specimen.id, field) == nil, field
      end

      {:ok, _view, html} = live(conn, "/specimens")
      for field <- fields, do: assert(shown(html, specimen, field) == "", field)
    end

    test "empty input is refused by the action for a field that cannot be empty",
         %{view: view, specimen: specimen} do
      html = save(view, "specimen", specimen.id, "an_integer", "")

      assert failure(html, "specimen", specimen.id, "an_integer") == %{
               shown: "",
               message: "is required"
             }

      html = save(view, "specimen", specimen.id, "an_integer", "5000")

      assert failure(html, "specimen", specimen.id, "an_integer") == %{
               shown: "5000",
               message: "must be less than or equal to 1000"
             }
    end
  end
end
