defmodule DemoWeb.Tables.ValidationDisplayTest do
  @moduledoc """
  What an input says of its limits before anything is saved: the least and
  the most a number takes and its steps, as the resource's constraints say
  them, and whether the action takes the input empty. On the editor of a
  cell (`/specimens`), on a field of the action panel
  (`/support/orders`), on a field inside a map cell (`/tasks`, "Repeats"),
  on the value of a union's kind (`/specimens`), on the argument line
  (`/tasks`), and on each value of an array of numbers (`/support/meters`,
  of a resource in `test/support/limit_tables.ex`).

  They describe and do not judge: nothing of this holds a form back, and
  what Ash says of a value it refuses is shown as before. That is in the
  tests of each of those places, which this slice left as they were; one
  test per place repeats it here beside the limits.
  """
  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Generator
  alias Demo.Support.Plain.Order

  # What the controls of a column's editor say, in the order they stand in:
  # a template's content is not part of the document, so it is read on its
  # own, and the row of a list is in a template inside it.
  defp editor_controls(html, id, field) do
    [{"template", _attributes, children}] =
      html |> query("template[id='#{id}-editor-#{field}']") |> LazyHTML.to_tree()

    content = LazyHTML.from_tree(children)

    row =
      case content |> LazyHTML.query("[data-list] > template") |> LazyHTML.to_tree() do
        [{"template", _attributes, row}] -> LazyHTML.from_tree(row)
        [] -> content
      end

    row |> LazyHTML.query("textarea,select,input") |> Enum.map(&said/1)
  end

  defp controls(html, selector), do: html |> query(selector) |> Enum.map(&said/1)
  defp query(html, selector), do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector)
  defp field(html, id, name), do: Enum.find(panel(html, id).fields, &(&1.name == name))

  # what a control says of its value before anything is typed
  @said ~w(type min max step aria-required required maxlength minlength pattern)

  defp said(control) do
    [{_tag, attributes, _children}] = LazyHTML.to_tree(control)
    for {name, value} <- attributes, name in @said, into: %{}, do: {name, value}
  end

  describe "the editor of a cell" do
    setup %{conn: conn} do
      Generator.reseed(1)
      specimen = Generator.generate(Generator.specimen(label: "Shown", an_integer: 5))
      {:ok, view, html} = live(conn, "/specimens")
      %{view: view, html: html, specimen: specimen}
    end

    test "of a whole number says the least and the most it takes, in steps of one", %{html: html} do
      assert editor_controls(html, "specimen", "an_integer") == [
               %{
                 "type" => "number",
                 "min" => "-1000",
                 "max" => "1000",
                 "step" => "1",
                 "aria-required" => "true"
               }
             ]
    end

    test "of a float and of a decimal says them in any step", %{html: html} do
      assert editor_controls(html, "specimen", "a_float") == [
               %{
                 "type" => "number",
                 "min" => "0.0",
                 "max" => "1.0",
                 "step" => "any",
                 "aria-required" => "true"
               }
             ]

      assert editor_controls(html, "specimen", "a_decimal") == [
               %{
                 "type" => "number",
                 "min" => "0",
                 "max" => "100000",
                 "step" => "any",
                 "aria-required" => "true"
               }
             ]
    end

    test "of a type made of a number says the limits that type gives it", %{html: html} do
      assert editor_controls(html, "specimen", "a_percentage") == [
               %{
                 "type" => "number",
                 "min" => "0",
                 "max" => "100",
                 "step" => "1",
                 "aria-required" => "true"
               }
             ]
    end

    test "of a number without constraints says its step, and nothing of one that may be empty",
         %{html: html} do
      assert editor_controls(html, "specimen", "opt_integer") ==
               [%{"type" => "number", "step" => "1"}]

      assert editor_controls(html, "specimen", "opt_decimal") ==
               [%{"type" => "number", "step" => "any"}]
    end

    test "of an array is the side panel's: its field says the limits of each value on the control of a value",
         %{view: view, html: html, specimen: specimen} do
      assert editor_controls(html, "specimen", "integers") == []

      html = edit(view, "specimen", specimen.id, "integers")

      assert [_row, %{"type" => "number", "min" => "0", "step" => "1"} | _rows] =
               controls(html, "#specimen-panel-f-integers-values input:not([type=hidden])") ++
                 controls(html, "#specimen-panel-f-integers-values > template")

      for control <- controls(html, "#specimen-panel-f-integers-values [data-item] > input"),
          do: assert(control == %{"type" => "number", "min" => "0", "step" => "1"})
    end

    test "of text says that it is required, and nothing of its length or its pattern", %{
      html: html
    } do
      # `a_string` takes 2 to 50 characters
      assert editor_controls(html, "specimen", "a_string") == [%{"aria-required" => "true"}]
      assert editor_controls(html, "specimen", "opt_string") == [%{}]
      # a list of text, each of 20 characters at most, is edited in the side panel
      assert editor_controls(html, "specimen", "strings") == []
    end

    test "of a choice and of a date says that it is required", %{html: html} do
      assert editor_controls(html, "specimen", "a_shade") == [%{"aria-required" => "true"}]
      assert editor_controls(html, "specimen", "opt_shade") == [%{}]

      assert editor_controls(html, "specimen", "a_date") ==
               [%{"type" => "date", "aria-required" => "true"}]
    end

    test "holds nothing back: a number past its limit is the action's to refuse", %{
      view: view,
      specimen: specimen
    } do
      html = save(view, "specimen", specimen.id, "an_integer", "5000")

      assert failure(html, "specimen", specimen.id, "an_integer") == %{
               shown: "5000",
               message: "must be less than or equal to 1000"
             }
    end
  end

  describe "the value of a union's kind" do
    test "says the limits of that kind", %{conn: conn} do
      Generator.reseed(1)

      specimen =
        Generator.generate(
          Generator.specimen(label: "Shown", a_union: %Ash.Union{type: :number, value: 12})
        )

      {:ok, view, _html} = live(conn, "/specimens")
      html = edit(view, "specimen", specimen.id, "a_union")

      assert controls(html, "[id='specimen-panel-f-a_union-value']") ==
               [%{"type" => "number", "min" => "0", "step" => "1"}]
    end
  end

  describe "a field of the action panel" do
    setup do
      on_exit(fn -> Demo.Support.Ets.stop(Order) end)
    end

    setup %{conn: conn} do
      order =
        Order
        |> Ash.Changeset.for_create(:create, %{
          title: "An order",
          note: "Long enough",
          amount: 100,
          code: "C-100",
          owner: "max"
        })
        |> Ash.create!(authorize?: false)

      {:ok, view, _html} =
        conn
        |> Phoenix.ConnTest.init_test_session(%{
          "assigns" => %{current_user: %{id: "max", name: "max", role: :member}}
        })
        |> live("/support/orders")

      %{view: view, order: order}
    end

    test "says the limits of the action's argument", %{view: view, order: order} do
      html = act(view, "order", order.id, "settle")

      assert controls(html, "#order-panel-f-paid") == [
               %{"type" => "number", "min" => "0", "step" => "1", "aria-required" => "true"}
             ]
    end

    test "is in a form the browser does not check, and a number past its limit is the action's to refuse",
         %{view: view, order: order} do
      html = act(view, "order", order.id, "settle")
      assert attribute(html, "#order-panel-form", "novalidate") == [""]

      html = run_panel(view, "order", paid: "-1")

      assert [%{name: "paid", value: "-1", errors: ["must be greater than or equal to 0"]}] =
               panel(html, "order").fields
    end
  end

  describe "an array of numbers, and a number whose bounds exclude their own value" do
    alias Demo.Support.Limits.Meter

    setup do
      on_exit(fn -> Demo.Support.Ets.stop(Meter) end)
    end

    setup %{conn: conn} do
      meter = Ash.Seed.seed!(Meter, %{name: "Main", level: 3, marks: [2, 4]})
      {:ok, view, html} = live(conn, "/support/meters")
      %{view: view, html: html, meter: meter}
    end

    test "in the action panel each value says the limits of a value, and a bound that excludes its own value is not said",
         %{view: view, meter: meter} do
      html = act(view, "meter", meter.id, "tune")

      # the row of a value, which the panel's hook copies for each value
      [{"template", _attributes, row}] =
        html |> query("#meter-panel-f-steps-values > template") |> LazyHTML.to_tree()

      assert row |> LazyHTML.from_tree() |> LazyHTML.query("input") |> Enum.map(&said/1) ==
               [%{"type" => "number", "min" => "0", "max" => "9", "step" => "1"}]

      # and the values a field starts with, which the server renders
      assert controls(html, "#meter-panel-f-marks-values > [data-item] input") ==
               List.duplicate(%{"type" => "number", "min" => "1", "max" => "6", "step" => "1"}, 2)

      assert controls(html, "#meter-panel-f-share") == [%{"type" => "number", "step" => "any"}]
    end

    test "on the argument line each value says the limits of a value, and of two bounds the one that includes its own value is said",
         %{view: view, html: html} do
      assert controls(html, "#meter-arg-over") ==
               [%{"type" => "number", "max" => "2.5", "step" => "any"}]

      html = view |> element("#meter-arg-among-add") |> render_click()

      assert controls(html, "#meter-arg-among input[type=number]") ==
               [%{"type" => "number", "min" => "1", "max" => "5", "step" => "1"}]
    end
  end

  describe "a field inside a map cell, and the argument line" do
    setup %{conn: conn} do
      world = world(tasks: 0, other_tasks: 0, projects: 1)

      task =
        Generator.generate(
          Generator.task(
            organization_id: world.organization.id,
            project_id: hd(world.projects).id,
            reporter_id: world.member.id,
            title: "Send the invoices",
            recurrence: %{every: 2, unit: :week, until: ~D[2027-01-31]}
          )
        )

      {:ok, view, html} = conn |> log_in(world.admin) |> live("/tasks")
      %{view: view, html: html, task: task}
    end

    test "a field inside a map cell says the limits of that field", %{view: view, task: task} do
      html = edit(view, task.id, "recurrence")

      assert controls(html, "#task-panel-f-recurrence-f-every") == [
               %{
                 "type" => "number",
                 "min" => "1",
                 "max" => "365",
                 "step" => "1",
                 "aria-required" => "true"
               }
             ]

      # and is the action's to refuse past them
      html = run_panel(view, recurrence: %{"every" => "0"})

      assert field(html, "task", "recurrence.every").errors ==
               ["must be greater than or equal to 1"]
    end

    test "the editor of a column's component is told that the cell cannot be empty", %{html: html} do
      # the slider says the limits itself, from the constraints it is given
      assert editor_controls(html, "task", "progress") == [
               %{
                 "type" => "range",
                 "min" => "0",
                 "max" => "100",
                 "step" => "1",
                 "aria-required" => "true"
               }
             ]
    end

    test "an input of the argument line says the limits of its argument", %{html: html} do
      assert controls(html, "#task-arguments input[type=number]") == [
               %{"type" => "number", "min" => "0", "step" => "1", "aria-required" => "true"}
             ]

      # text is one line here, and says nothing of itself
      assert controls(html, "#task-arguments input[type=text]") == [%{"type" => "text"}]
    end

    test "the argument line is a form the browser does not check, and a number past its limit is Ash's to refuse",
         %{view: view, html: html} do
      assert attribute(html, "#task-arguments", "novalidate") == [""]

      html = argue(view, "task", c: %{"due_within" => %{"days" => "-1"}})

      assert [_search, %{value: "-1", errors: ["must be greater than or equal to 0"]}] =
               arguments(html, "task")
    end
  end
end
