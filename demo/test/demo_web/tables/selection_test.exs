defmodule DemoWeb.Tables.SelectionTest do
  @moduledoc """
  What is selected, on the server (stage 6, group R): the table holds what
  the hook says a person selected, runs an action on it, and decides when
  it ends or narrows, which it tells the hook (`ash_data_table:select`) and
  the page (`:selection_changed`). `DemoWeb.Support.GivenLive`.
  """
  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Support.Given.{Card, Remark}

  setup %{conn: conn} do
    on_exit(fn -> Demo.Support.Ets.stop([Card, Remark]) end)
    card = Ash.Seed.seed!(Card, %{title: "First"})
    other = Ash.Seed.seed!(Card, %{title: "Second"})
    remark = Ash.Seed.seed!(Remark, %{body: "A remark", card_id: card.id})

    {:ok, view, _html} =
      live_isolated(conn, DemoWeb.Support.GivenLive,
        session: %{"test" => self(), "notify" => [:selection_changed]}
      )

    %{view: view, card: card, other: other, remark: remark}
  end

  defp changed do
    receive do
      {:heard, {:ash_data_table, "card", {:selection_changed, details}}} -> details
    after
      0 -> nil
    end
  end

  test "the table follows what the hook says is selected, and tells the page, once per change",
       %{view: view, card: card, other: other} do
    select(view, "card", [card.id, other.id])
    assert %{selected: selected, all?: false, table: "card"} = changed()
    assert Enum.sort(selected) == Enum.sort([%{id: card.id}, %{id: other.id}])

    # the same again is no change
    select(view, "card", [other.id, card.id, card.id])
    assert changed() == nil

    select(view, "card", :all)
    assert %{selected: [], all?: true} = changed()

    select(view, "card", [])
    assert %{selected: [], all?: false} = changed()
  end

  test "Confirm runs nothing on a selection other than the one its question named", %{
    view: view,
    card: card,
    other: other
  } do
    select(view, "card", [other.id])
    token = bulk_token(view, "card", "assign")

    # the question is open in the page, and the selection changes under it
    select(view, "card", [card.id, other.id])
    html = forge(view, "card", "bulk_run", %{"action" => "assign", "selection" => token})

    said = "Nothing was run: the selection changed after the question was asked."
    assert bulk_result(html, "card") == %{summary: said, failures: []}
    assert announcement(html, "card") == said
    assert attribute(html, "#card-table", "aria-busy") == []
    assert Ash.get!(Card, other.id).assignee == nil
    assert Ash.get!(Card, card.id).assignee == nil

    # a token of nothing selected is not one of what is selected now either
    forge(view, "card", "bulk_run", %{"action" => "assign", "selection" => ""})
    assert Ash.get!(Card, card.id).assignee == nil

    # asked again, it runs on what the question names now
    confirm_bulk(view, "card", "assign")
    ran(view)
    assert Ash.get!(Card, other.id).assignee == "ann"
    assert Ash.get!(Card, card.id).assignee == "ann"
  end

  test "an action runs on what the table holds as selected", %{
    view: view,
    card: card,
    other: other
  } do
    select(view, "card", [other.id])
    confirm_bulk(view, "card", "assign")
    ran(view)

    assert Ash.get!(Card, other.id).assignee == "ann"
    assert Ash.get!(Card, card.id).assignee == nil
  end

  test "a row that goes is selected no longer", %{view: view, card: card, other: other} do
    select(view, "card", [card.id, other.id])
    changed()

    act(view, "card", other.id, "destroy")
    assert_push_event view, "ash_data_table:select", %{table: "card", all: false, rows: rows}
    assert rows == [[card.id, nil]]
    assert %{selected: [%{id: id}]} = changed()
    assert id == card.id
  end

  test "a selection under other filters ends", %{view: view, card: card} do
    select(view, "card", [card.id])
    changed()

    filter(view, "card", "title", v: "First")
    assert_push_event view, "ash_data_table:select", %{table: "card", rows: []}
    assert %{selected: [], all?: false} = changed()
  end

  test "a picker's table holds its own, and tells the page nothing", %{
    view: view,
    card: card,
    remark: remark
  } do
    nested = nested("card", card.id, "remarks")
    expand(view, "card", card.id)
    toggle(view, "card", card.id, "remarks")

    html = pick(view, nested, remark.id, "card")
    select(view, picker_table(html), [card.id])
    assert changed() == nil
  end

  # the id of the table of the open picker: its grid says that it chooses
  defp picker_table(html) do
    [grid] =
      html
      |> AshDataTable.Test.page()
      |> LazyHTML.query("[data-choose][id$='-grid']")
      |> LazyHTML.attribute("id")

    String.replace_suffix(grid, "-grid", "")
  end
end
