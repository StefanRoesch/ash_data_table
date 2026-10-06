defmodule DemoWeb.Tables.LabelTableTest do
  @moduledoc """
  The mounted table of `Demo.Tracker.Label` at `/labels`: a read action
  without pagination, so the table shows every record.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  test "shows every record, sorted as the read action sorts, with no pagination",
       %{conn: conn} do
    world = world(tasks: 0, labels: 30)

    {:ok, _view, html} = conn |> log_in(world.admin) |> live("/labels")

    assert headers(html, "label") == ["ID", "Name", "Colour"]
    assert column(html, "label", "name") == world.labels |> Enum.map(& &1.name) |> Enum.sort()
    assert length(column(html, "label", "name")) == 30
    # 30 labels and the two header rows
    assert attribute(html, "#label-table", "aria-rowcount") == ["32"]
    assert attribute(html, "#label-pagination", "id") == []
  end
end
