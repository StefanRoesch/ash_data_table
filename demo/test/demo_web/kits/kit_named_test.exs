defmodule DemoWeb.Kits.KitNamedTest do
  @moduledoc """
  Where a kit is named (the design note of stage 7, D9), and what the kit's
  `cell/1` is given (D10; test group Z): the configuration, the tag,
  `attach/4` and the router line; the tables a table shows, nested and in a
  picker, are drawn with its kit; a cell is the column's component's before
  it is the kit's, and the kit is never given the value of a sensitive cell.
  """
  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AshDataTable.KitCase
  alias AshDataTable.Test.Resource

  @admin %{id: "ada", name: "ada", role: :admin}

  # the page as the browser shows it, nested tables moved into their cells
  defp drawn_by_div_kit?(html, id),
    do:
      html
      |> AshDataTable.Test.page()
      |> LazyHTML.query("[id='#{id}-table'][data-kit='div']")
      |> Enum.count() == 1

  defp as_admin(conn),
    do: Phoenix.ConnTest.init_test_session(conn, %{"assigns" => %{current_user: @admin}})

  test "the router line names the kit", %{conn: conn} do
    {:ok, _view, html} = conn |> as_admin() |> live("/support/kit/memos")
    assert drawn_by_div_kit?(html, "kitmemo")
  end

  test "the tag names the kit", %{conn: conn} do
    {:ok, _view, html} = conn |> as_admin() |> live("/support/kit/tag")
    assert drawn_by_div_kit?(html, "tagged")
  end

  test "the configuration names the kit of every table that is given none", %{conn: conn} do
    Application.put_env(:ash_data_table, :kit, DemoWeb.DivKit)
    on_exit(fn -> Application.delete_env(:ash_data_table, :kit) end)

    {:ok, _view, html} = conn |> as_admin() |> live("/support/memos")
    assert drawn_by_div_kit?(html, "memo")

    Application.put_env(:ash_data_table, :kit, String)

    assert_raise ArgumentError,
                 ~r/`config :ash_data_table` was given `kit: String`, which is no kit/,
                 fn ->
                   AshDataTable.attach(
                     %Phoenix.LiveView.Socket{},
                     :table,
                     Demo.Support.Plain.Memo,
                     []
                   )
                 end
  end

  test "attach names the kit, and a nested table and a picker's table are drawn with it",
       %{conn: conn} do
    {tenant, key, session} = KitCase.given(DemoWeb.DivKit, :rows, :modal)
    on_exit(fn -> KitCase.clean(tenant) end)
    {:ok, view, html} = live_isolated(conn, AshDataTable.KitCase.Live, session: session)
    assert drawn_by_div_kit?(html, "kit")

    AshDataTable.Test.send_event(view, "kit", "expand", %{"row" => key})

    AshDataTable.Test.send_event(view, "kit", "toggle", %{
      "row" => key,
      "relationship" => "parts"
    })

    assert drawn_by_div_kit?(render_async(view), "kit-row-#{key}-t-parts")

    AshDataTable.Test.send_event(view, "kit", "pick", %{"row" => key, "column" => "owner"})
    assert drawn_by_div_kit?(render_async(view), "kit-pick-owner")
  end

  test "a question in the page needs the panel and the picker in the page too" do
    assert_raise ArgumentError, ~r/has the question \(`confirm`\) inline and the panel/, fn ->
      AshDataTable.attach(%Phoenix.LiveView.Socket{}, :table, Demo.Support.Plain.Memo,
        presentation: [confirm: :inline]
      )
    end
  end

  test "a cell is the component's first, else the kit's, which is given no sensitive value",
       %{conn: conn} do
    {tenant, key, session} = KitCase.given(DemoWeb.Support.MarkedKit, :rows, :modal)
    on_exit(fn -> KitCase.clean(tenant) end)
    {:ok, _view, html} = live_isolated(conn, AshDataTable.KitCase.Live, session: session)

    page = LazyHTML.from_document(html)
    cell = &LazyHTML.query(page, "[id='kit-row-#{key}-c-#{&1}'] > [data-kit-cell]")

    assert LazyHTML.attribute(cell.("name"), "data-kit-cell") == ["value"]
    assert LazyHTML.attribute(cell.("name"), "data-given") == ["value"]
    # the column's component draws the size, not the kit
    assert Enum.count(cell.("size")) == 0

    assert page |> LazyHTML.query("[id='kit-row-#{key}-c-size'] progress") |> Enum.count() ==
             1

    # a sensitive cell: the kit is told it is masked, and given nothing
    assert LazyHTML.attribute(cell.("secret"), "data-kit-cell") == ["masked"]
    assert LazyHTML.attribute(cell.("secret"), "data-given") == ["none"]
    refute html =~ Resource.secret()
  end
end
