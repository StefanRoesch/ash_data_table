defmodule DemoWeb.Tables.UncountedTableTest do
  @moduledoc """
  A table whose read action pages by keyset and does not count
  (`pagination countable: false`): it has no total to show or to announce.

  The demo's own keyset table, `/comments`, counts, so this table is of a
  resource that exists for the tests only (`Demo.Support.Plain.Ticket`,
  mounted at `/support/tickets`). Its records are kept in memory.
  """
  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Support.Plain.Ticket

  setup do
    for n <- 1..12 do
      Ticket
      |> Ash.Changeset.for_create(:create, %{
        title: "Ticket #{String.pad_leading("#{n}", 2, "0")}"
      })
      |> Ash.create!()
    end

    on_exit(fn -> Demo.Support.Ets.stop(Ticket) end)
  end

  test "shows no total, and does not claim to know how many rows there are", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/support/tickets")

    assert column(html, "ticket", "title") ==
             ["Ticket 01", "Ticket 02", "Ticket 03", "Ticket 04", "Ticket 05"]

    assert text(html, "#ticket-range") == ""
    assert attribute(html, "#ticket-table", "aria-rowcount") == ["-1"]
  end

  test "a filter change says only that the results have changed", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/support/tickets")

    html = filter(view, "ticket", "title", v: "Ticket 1")

    assert column(html, "ticket", "title") == ["Ticket 10", "Ticket 11", "Ticket 12"]
    assert text(html, "#ticket-status") == "Results updated"
    assert text(html, "#ticket-range") == ""
    assert attribute(html, "#ticket-table", "aria-rowcount") == ["-1"]
  end
end
