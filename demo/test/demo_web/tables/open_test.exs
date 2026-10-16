defmodule DemoWeb.Tables.OpenTest do
  @moduledoc """
  "Open" offered by the page (stage 6, group U): a button first in the
  actions cell of every row of the table on the page, which tells the page
  the row's key, whatever `notify` says, and reads and writes nothing.
  `DemoWeb.Support.GivenLive`.
  """
  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Support.Given.{Card, Remark}

  setup %{conn: conn} do
    on_exit(fn -> Demo.Support.Ets.stop([Card, Remark]) end)
    card = Ash.Seed.seed!(Card, %{title: "First"})
    Ash.Seed.seed!(Remark, %{body: "A remark", card_id: card.id})
    %{conn: conn, card: card}
  end

  defp given(conn, session),
    do: live_isolated(conn, DemoWeb.Support.GivenLive, session: Map.put(session, "test", self()))

  defp drained do
    receive do
      {:read, _, _, _} -> drained()
    after
      0 -> :ok
    end
  end

  defp opened do
    receive do
      {:heard, {:ash_data_table, "card", {:row_opened, details}}} -> details
    after
      0 -> nil
    end
  end

  test "a button first in each row's actions cell tells the page the row's key, without notify",
       %{conn: conn, card: card} do
    {:ok, view, html} = given(conn, %{"open" => "Open"})

    assert ["Open" | _] = actions(html, "card", card.id)
    assert attribute(html, "[id='card-row-#{card.id}-a-open']", "data-open") == [""]

    # what the hook sends for it, once the reads of the mount are in
    render(view)
    drained()
    forge(view, "card", "open", %{"row" => card.id})

    assert %{key: key, table: "card", resource: Card} = opened()
    assert key == %{id: card.id}
    # nothing is read for it
    refute_received {:read, _, _, _}
  end

  test "a row that is not on the page, or a page that offers no Open, gets nothing",
       %{conn: conn, card: card} do
    {:ok, view, _html} = given(conn, %{"open" => "Open"})
    forge(view, "card", "open", %{"row" => Ash.UUID.generate()})
    assert opened() == nil

    {:ok, view, html} = given(conn, %{})
    refute "Open" in actions(html, "card", card.id)
    forge(view, "card", "open", %{"row" => card.id})
    assert opened() == nil
  end

  test "a nested table offers none", %{conn: conn, card: card} do
    {:ok, view, _html} = given(conn, %{"open" => "Open"})
    expand(view, "card", card.id)
    html = toggle(view, "card", card.id, "remarks")

    nested = nested("card", card.id, "remarks")

    refute html
           |> AshDataTable.Test.page()
           |> LazyHTML.query("[id^='#{nested}-row-'][data-open]")
           |> Enum.any?()
  end
end
