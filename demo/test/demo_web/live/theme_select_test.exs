defmodule DemoWeb.ThemeSelectTest do
  # The theme select of the header (`DemoWeb.Layouts.theme_select/1`): it is
  # there beside the toggle, and lists the system's theme, the demo's own
  # two and daisyUI's six, in the person's language. What a choice does is
  # the browser's (`assets/js/page.js`).
  use DemoWeb.ConnCase, async: true

  setup do
    %{world: world(tasks: 0)}
  end

  defp options(html) do
    html
    |> LazyHTML.from_document()
    |> LazyHTML.query("header select#theme-select[data-theme-select] option")
    |> Enum.map(&{hd(LazyHTML.attribute(&1, "value")), LazyHTML.text(&1)})
  end

  test "the header has a theme select, labelled, beside the toggle, with every theme",
       %{conn: conn, world: world} do
    html = conn |> log_in(world.member) |> get(~p"/") |> html_response(200)

    assert options(html) == [
             {"system", "System"},
             {"light", "Light"},
             {"dark", "Dark"},
             {"corporate", "Corporate"},
             {"nord", "Nord"},
             {"cupcake", "Cupcake"},
             {"dracula", "Dracula"},
             {"night", "Night"},
             {"business", "Business"}
           ]

    document = LazyHTML.from_document(html)
    assert LazyHTML.text(LazyHTML.query(document, "header label[for='theme-select']")) == "Theme"
    # the toggle is still there, beside it
    assert Enum.count(LazyHTML.query(document, "header button[data-phx-theme]")) == 3
  end

  test "says its themes in German", %{conn: conn, world: world} do
    conn = conn |> log_in(world.member) |> post(~p"/locale", %{"locale" => "de"})
    html = conn |> recycle() |> get(~p"/") |> html_response(200)

    assert {"night", "Nacht"} in options(html)
    assert {"light", "Hell"} in options(html)

    assert html
           |> LazyHTML.from_document()
           |> LazyHTML.query("label[for='theme-select']")
           |> LazyHTML.text() ==
             "Farbschema"
  end
end
