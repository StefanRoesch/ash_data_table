defmodule DemoWeb.Kits.DivKitTest do
  @moduledoc """
  The demo's kit of `div`s, whose panel and picker open in the page, passes
  `AshDataTable.KitCase`, and says what it is given in the person's
  language.
  """
  use AshDataTable.KitCase, kit: DemoWeb.DivKit, endpoint: DemoWeb.Endpoint

  import DemoWeb.TablePage, only: [attribute: 3, text: 2]

  test "in German, the kit of divs says the table's texts and its summary in German" do
    {tenant, key, _session} = AshDataTable.KitCase.given(DemoWeb.DivKit, :rows, :inline)
    on_exit(fn -> AshDataTable.KitCase.clean(tenant) end)

    {:ok, view, html} =
      live_isolated(Phoenix.ConnTest.build_conn(), DemoWeb.Support.GermanKitLive,
        session: %{"tenant" => tenant}
      )

    assert text(html, "[id='kit-actions-head']") == "Aktionen"

    assert attribute(html, "[id='kit-select-head'] input", "aria-label") ==
             ["Alle Zeilen dieser Seite auswählen"]

    assert attribute(html, "[id='kit-row-#{key}-s'] input", "aria-label") == ["Zeile auswählen"]

    assert attribute(html, "[id='kit-row-#{key}-e'] button", "aria-label") ==
             ["Zugehörige Einträge"]

    # the sum of the sizes (40 and 3), once it is there
    assert text(render_async(view), "[id='kit-summary-size']") == "Summe 43"
  end
end
