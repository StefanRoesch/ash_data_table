defmodule DemoWeb.Tables.FileTwoTablesTest do
  @moduledoc """
  Two tables of one LiveView whose actions take a file under the same
  argument (`DemoWeb.Support.ScansLive` in `test/support/file_tables.ex`,
  at `/support/two-scans`). Both are live components of one process, and
  LiveView wants the name of an upload to be one of a kind in a process: so
  each table allows its uploads under a name with its own id in it.
  """
  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Support.Files.Scan

  setup %{conn: conn} do
    on_exit(fn -> Demo.Support.Ets.stop(Scan) end)
    scan = Ash.Seed.seed!(Scan, %{title: "Page 1"})
    other = Ash.Seed.seed!(Scan, %{title: "Page 2"})
    {:ok, view, _html} = live(conn, "/support/two-scans")
    %{scan: scan, other: other, view: view}
  end

  defp stored(scan), do: Ash.get!(Scan, scan.id, authorize?: false)

  defp input(view, id, html, file, content) do
    [name] =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[id='#{id}-panel'] input[type=file]")
      |> LazyHTML.attribute("name")

    file_input(view, "[id='#{id}-panel-form']", name, [
      %{name: file, content: content, type: "text/plain"}
    ])
  end

  defp run(view, id),
    do:
      view
      |> element("[id='#{id}-panel-form']")
      |> render_submit(%{"panel" => %{"title" => "Page 1"}})

  test "each table's file input has a name of its own", %{view: view, scan: scan} do
    left = act(view, "left", scan.id, "attach")
    right = act(view, "right", scan.id, "attach")

    names =
      for {id, html} <- [{"left", left}, {"right", right}] do
        html
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("[id='#{id}-panel'] input[type=file]")
        |> LazyHTML.attribute("name")
      end

    assert [[left_name], [right_name]] = names
    assert left_name != right_name
  end

  test "a file is chosen in one table while the other still holds one: both actions run, each with its own file",
       %{view: view, scan: scan, other: other} do
    html = act(view, "left", scan.id, "attach")
    left = input(view, "left", html, "left.txt", "from the left")
    render_upload(left, "left.txt")

    # the left table still holds its file when one is chosen in the right
    html = act(view, "right", other.id, "attach")
    right = input(view, "right", html, "right.txt", "from the right")
    render_upload(right, "right.txt")

    html = run(view, "right")
    assert panel(html, "right") == nil
    assert stored(other).content == "from the right"
    assert stored(other).file_name == "right.txt"

    html = run(view, "left")
    assert panel(html, "left") == nil
    assert stored(scan).content == "from the left"
    assert stored(scan).file_name == "left.txt"
  end

  test "a panel is left with a file chosen, and the other table takes one after it", %{
    view: view,
    scan: scan
  } do
    html = act(view, "left", scan.id, "attach")
    left = input(view, "left", html, "left.txt", "from the left")
    render_upload(left, "left.txt")
    assert panel(cancel_panel(view, "left"), "left") == nil

    html = act(view, "right", scan.id, "attach")
    right = input(view, "right", html, "right.txt", "from the right")
    render_upload(right, "right.txt")

    html = run(view, "right")
    assert panel(html, "right") == nil
    assert stored(scan).content == "from the right"
  end

  test "one table after the other: each action is given its file", %{view: view, scan: scan} do
    html = act(view, "left", scan.id, "attach")
    render_upload(input(view, "left", html, "one.txt", "one"), "one.txt")
    run(view, "left")
    assert stored(scan).content == "one"

    html = act(view, "right", scan.id, "attach")
    render_upload(input(view, "right", html, "two.txt", "two"), "two.txt")
    run(view, "right")
    assert stored(scan).content == "two"
  end
end
