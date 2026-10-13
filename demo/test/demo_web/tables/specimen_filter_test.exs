defmodule DemoWeb.Tables.SpecimenFilterTest do
  @moduledoc """
  Filtering the mounted table of `Demo.KitchenSink.Specimen` at `/specimens`:
  a table without a block, so every column has the filter its type gets by
  default.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator

  setup %{conn: conn} do
    Generator.reseed(1)

    for fields <- [
          [
            label: "A lower",
            a_string: "alpha one",
            a_ci_string: Ash.CiString.new("alpha one"),
            opt_string: nil,
            a_float: 0.25,
            a_percentage: 10,
            a_utc_datetime_usec: ~U[2026-03-09 14:30:05.000000Z],
            a_naive_datetime: ~N[2026-03-09 14:30:05],
            opt_utc_datetime: nil,
            an_atom: :red
          ],
          [
            label: "B upper",
            a_string: "ALPHA two",
            a_ci_string: Ash.CiString.new("ALPHA two"),
            opt_string: "given",
            a_float: 0.5,
            a_percentage: 50,
            a_utc_datetime_usec: ~U[2026-03-09 14:30:05.500000Z],
            a_naive_datetime: ~N[2026-03-09 14:30:06],
            opt_utc_datetime: ~U[2026-03-09 14:30:05Z],
            an_atom: :green
          ],
          [
            label: "C mixed",
            a_string: "Beta Alpha",
            a_ci_string: Ash.CiString.new("Beta Alpha"),
            opt_string: "given",
            a_float: 0.75,
            a_percentage: 90,
            a_utc_datetime_usec: ~U[2026-03-09 14:30:07.000000Z],
            a_naive_datetime: ~N[2026-03-09 14:30:07],
            opt_utc_datetime: ~U[2026-03-09 14:30:07Z],
            an_atom: :red
          ]
        ] do
      Generator.generate(Generator.specimen(fields))
    end

    {:ok, view, html} = live(conn, "/specimens")
    %{view: view, html: html}
  end

  defp labels(html), do: column(html, "specimen", "label")

  describe "the filter each type gets by default" do
    test "text, whether it tells upper from lower case or not", %{html: html} do
      for field <- ["a_string", "a_ci_string"] do
        assert filter_controls(html, "specimen", field) == %{
                 operators: ["contains", "equals", "starts with"],
                 input: "text",
                 choices: nil
               }
      end

      assert filter_controls(html, "specimen", "opt_string").operators ==
               ["contains", "equals", "starts with", "is empty"]
    end

    test "numbers, a NewType of one among them", %{html: html} do
      for field <- ["an_integer", "a_float", "a_decimal", "a_percentage"] do
        assert filter_controls(html, "specimen", field) == %{
                 operators: [
                   "equals",
                   "greater than",
                   "less than",
                   "at least",
                   "at most",
                   "between"
                 ],
                 input: "number",
                 choices: nil
               }
      end

      assert "is empty" in filter_controls(html, "specimen", "opt_integer").operators
    end

    test "a boolean, a date and every kind of datetime", %{html: html} do
      assert filter_controls(html, "specimen", "a_boolean").choices == ["Any", "Yes", "No"]
      assert filter_controls(html, "specimen", "opt_boolean").choices == ["Any", "Yes", "No"]
      assert filter_controls(html, "specimen", "a_date").input == "date"

      assert filter_controls(html, "specimen", "a_date").operators ==
               ["on", "before", "after", "between"]

      for field <- ~w(a_utc_datetime a_utc_datetime_usec a_datetime a_naive_datetime) do
        assert filter_controls(html, "specimen", field) == %{
                 operators: ["before", "after", "between"],
                 input: "datetime-local",
                 choices: nil
               }
      end

      assert filter_controls(html, "specimen", "opt_utc_datetime").operators ==
               ["before", "after", "between", "is empty"]
    end

    test "enums: an Ash.Type.Enum, an atom limited to values, a built-in one", %{html: html} do
      assert filter_controls(html, "specimen", "a_shade").choices ==
               ["Any", "Light", "Medium", "Dark"]

      assert filter_controls(html, "specimen", "an_atom").choices ==
               ["Any", "Red", "Green", "Blue"]

      assert "Week" in filter_controls(html, "specimen", "a_duration_name").choices
    end

    test "none for the types shown as read-only text", %{html: html} do
      for field <- ~w(id a_uuid a_time a_duration a_binary a_map a_typed_map a_term a_module
                      a_date_range strings integers shades an_address addresses a_union) do
        assert filter_controls(html, "specimen", field) ==
                 %{operators: nil, input: nil, choices: nil},
               field
      end
    end
  end

  describe "text matches as the resource defines" do
    test "a :string tells upper from lower case", %{view: view} do
      assert labels(filter(view, "specimen", "a_string", v: "alpha")) == ["A lower"]
      assert labels(filter(view, "specimen", "a_string", v: "Alpha")) == ["C mixed"]
      assert labels(filter(view, "specimen", "a_string", o: "equals", v: "alpha two")) == []

      assert labels(filter(view, "specimen", "a_string", o: "starts_with", v: "ALPHA")) ==
               ["B upper"]
    end

    test "a :ci_string does not", %{view: view} do
      assert labels(filter(view, "specimen", "a_ci_string", v: "alpha")) ==
               ["A lower", "B upper", "C mixed"]

      assert labels(filter(view, "specimen", "a_ci_string", o: "equals", v: "alpha two")) ==
               ["B upper"]

      assert labels(filter(view, "specimen", "a_ci_string", o: "starts_with", v: "ALPHA")) ==
               ["A lower", "B upper"]
    end

    test "is empty finds the rows without text", %{view: view} do
      assert labels(filter(view, "specimen", "opt_string", o: "is_empty")) == ["A lower"]
    end
  end

  describe "other types" do
    test "a float and a NewType of a number compare as numbers", %{view: view} do
      assert labels(filter(view, "specimen", "a_float", o: "at_least", v: "0.5")) ==
               ["B upper", "C mixed"]

      view |> element("#specimen-clear-filters") |> render_click()

      assert labels(filter(view, "specimen", "a_percentage", o: "less_than", v: "50")) ==
               ["A lower"]
    end

    test "a datetime with microseconds and a naive one compare to the second", %{view: view} do
      assert labels(filter(view, "specimen", "a_utc_datetime_usec", v: "2026-03-09T14:30:06")) ==
               ["A lower", "B upper"]

      view |> element("#specimen-clear-filters") |> render_click()

      assert labels(
               filter(view, "specimen", "a_naive_datetime", o: "after", v: "2026-03-09T14:30:06")
             ) == ["C mixed"]

      view |> element("#specimen-clear-filters") |> render_click()

      assert labels(filter(view, "specimen", "opt_utc_datetime", o: "is_empty")) == ["A lower"]
    end

    test "an atom limited to values is a choice", %{view: view} do
      assert labels(filter(view, "specimen", "an_atom", v: "red")) == ["A lower", "C mixed"]
      assert_patch(view, "/specimens?specimen[f][an_atom]=red")
    end
  end
end
