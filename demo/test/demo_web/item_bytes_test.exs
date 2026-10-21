defmodule DemoWeb.ItemBytesTest do
  @moduledoc """
  The size of the stream's items: the
  first page of `/tasks`, 25 rows and their details, as JSON items of
  `AshDataTable.Item` (what a kit that hands the stream to the browser
  sends) beside the HTML the default kit draws of the same rows. Reported,
  no limit: `MEASURE=1 mix test test/demo_web/item_bytes_test.exs` prints
  the numbers.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    world = world(tasks: 30)
    %{conn: log_in(conn, world.admin)}
  end

  test "a page's items go to JSON, and are measured beside the page's rows in HTML", %{
    conn: conn
  } do
    {:ok, _view, html} = live(conn, "/tasks")
    {:ok, _view, json_page} = live(conn, "/items/tasks")

    rows =
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query("[id='task-table'] > tbody")

    html_bytes = rows |> LazyHTML.to_html() |> byte_size()

    texts =
      json_page
      |> LazyHTML.from_document()
      |> LazyHTML.query("script[data-item]")
      |> Enum.map(&LazyHTML.text/1)

    items = Enum.map(texts, &Jason.decode!/1)
    json = "[" <> Enum.join(texts, ",") <> "]"
    json_bytes = byte_size(json)

    # 25 rows, each with its detail
    assert length(items) == 50
    assert Enum.count(rows) == 50
    assert Enum.all?(items, &is_binary(&1["dom_id"]))

    if System.get_env("MEASURE") == "1" do
      IO.puts(
        "\nM2 /tasks page 1 (#{length(items)} items): JSON #{json_bytes} B, " <>
          "HTML #{html_bytes} B, JSON/HTML #{Float.round(json_bytes / html_bytes, 2)}, " <>
          "gzip JSON #{byte_size(:zlib.gzip(json))} B, " <>
          "gzip HTML #{byte_size(:zlib.gzip(LazyHTML.to_html(rows)))} B"
      )
    end
  end
end
