defmodule DemoWeb.Tables.ImageTableTest do
  @moduledoc """
  `AshTable.Components.Image` in a table: a text column that holds where a
  picture is. The table is of a resource that exists for the tests only
  (`test/support/component_tables.ex`), mounted at `/support/portraits`.
  """
  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Support.Styled.Portrait

  setup do
    on_exit(fn -> Demo.Support.Ets.stop(Portrait) end)

    portrait = fn name, picture ->
      Ash.create!(Portrait, %{name: name, picture: picture}, authorize?: false)
    end

    %{
      ada: portrait.("Ada", "/images/logo.svg"),
      bob: portrait.("Bob", "https://example.com/bob.png"),
      eve: portrait.("Eve", "javascript:alert(1)"),
      nil: portrait.("Nil", nil)
    }
  end

  defp picture(portrait), do: "#{cell("portrait", portrait.id, "picture")} > img"

  test "a cell shows the picture at the place its value names, named by the column, and nothing else",
       %{conn: conn, ada: ada, bob: bob} do
    {:ok, _view, html} = live(conn, "/support/portraits")

    for {portrait, source} <- [{ada, "/images/logo.svg"}, {bob, "https://example.com/bob.png"}] do
      assert attribute(html, picture(portrait), "src") == [source]
      assert attribute(html, picture(portrait), "alt") == ["Picture"]
      assert attribute(html, picture(portrait), "loading") == ["lazy"]
      assert text(html, cell("portrait", portrait.id, "picture")) == ""
    end
  end

  test "a value that is no place of a picture is shown as text, and a record without one has an empty cell",
       %{conn: conn, eve: eve, nil: none} do
    {:ok, _view, html} = live(conn, "/support/portraits")

    assert attribute(html, picture(eve), "src") == []
    assert text(html, cell("portrait", eve.id, "picture")) == "javascript:alert(1)"
    assert attribute(html, "[src^='javascript']", "src") == []

    assert attribute(html, picture(none), "src") == []
    assert text(html, cell("portrait", none.id, "picture")) == ""
  end

  test "the column is edited as text: the place is typed, and the cell shows the new picture", %{
    conn: conn,
    ada: ada
  } do
    {:ok, view, html} = live(conn, "/support/portraits")

    assert editor(html, "portrait", "picture").control == "textarea"
    # the editor starts with the place, not with the picture
    assert attribute(html, cell("portrait", ada.id, "picture"), "data-value") ==
             ["/images/logo.svg"]

    html = save(view, "portrait", ada.id, "picture", "/images/other.png")

    assert attribute(html, picture(ada), "src") == ["/images/other.png"]
    assert Ash.get!(Portrait, ada.id, authorize?: false).picture == "/images/other.png"
  end
end
