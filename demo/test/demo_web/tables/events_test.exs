defmodule DemoWeb.Tables.EventsTest do
  @moduledoc """
  What a table tells the page it is on: one message per
  event, `{:ash_data_table, id, {event, details}}`, to the LiveView's own
  process, for the events the page asks for with `notify`, and none
  without it. `DemoWeb.Support.GivenLive` hands every message it hears to
  the test (`{:heard, message}`); `DemoWeb.Support.GivenTagLive` places the
  table with the tag.
  """
  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias AshDataTable.Sensitive.Masked
  alias Demo.Support.Given.{Card, Remark}

  setup %{conn: conn} do
    on_exit(fn -> Demo.Support.Ets.stop([Card, Remark]) end)
    card = Ash.Seed.seed!(Card, %{title: "First", code: "c-1"})
    other = Ash.Seed.seed!(Card, %{title: "Second"})
    remark = Ash.Seed.seed!(Remark, %{body: "A remark", card_id: card.id})
    %{conn: conn, card: card, other: other, remark: remark}
  end

  defp given(conn, session),
    do: live_isolated(conn, DemoWeb.Support.GivenLive, session: Map.put(session, "test", self()))

  # the events the page heard, in their order, and nothing else it heard
  defp events do
    receive do
      {:heard, {:ash_data_table, id, {event, details}}} -> [{id, event, details} | events()]
      {:heard, _other} -> events()
    after
      0 -> []
    end
  end

  defp event(name) do
    case for {id, ^name, details} <- events(), do: {id, details} do
      [one] -> one
      other -> flunk("expected one #{inspect(name)}, heard #{inspect(other)}")
    end
  end

  test "without `notify` the table tells the page nothing", %{conn: conn, card: card} do
    {:ok, view, _html} = given(conn, %{})
    save(view, "card", card.id, "title", "Renamed")
    render_async(view)

    assert events() == []
  end

  test "a read says the state as the URL holds it, how many rows it shows, and how many there are",
       %{conn: conn} do
    {:ok, view, _html} = given(conn, %{"notify" => true})

    assert {"card", %{table: "card", resource: Card, state: %{}, count: 2, total: 2} = details} =
             event(:read)

    refute Map.has_key?(details, :path)

    view |> element("#card-sort-title") |> render_click()
    render_async(view)
    assert {"card", %{state: %{"sort" => "title"}, count: 2}} = event(:read)
  end

  test "a read that fails says so, with what the person reads", %{conn: conn} do
    {:ok, _view, _html} = given(conn, %{"notify" => [:read, :read_failed], "fail" => true})

    assert {"card", %{message: message, forbidden?: false}} = event(:read_failed)
    assert is_binary(message)
  end

  test "a save says the row, the column and the record, its sensitive value masked",
       %{conn: conn, card: card} do
    {:ok, view, _html} = given(conn, %{"notify" => [:row_saved]})

    save(view, "card", card.id, "title", "Renamed")

    assert {"card",
            %{
              table: "card",
              resource: Card,
              action: :update,
              key: key,
              changed: [:title],
              record: %Card{title: "Renamed", code: %Masked{}}
            }} = event(:row_saved)

    assert key == %{id: card.id}
  end

  test "a create says what it was given, without a sensitive input", %{conn: conn} do
    {:ok, view, _html} = given(conn, %{"notify" => [:row_created]})

    open_create(view, "card")

    run_panel(view, "card", %{
      "title" => "Third",
      "code" => "c-3",
      "note" => "hi",
      "pin" => "1234"
    })

    assert {"card",
            %{
              action: :create,
              key: %{id: id},
              arguments: arguments,
              record: %Card{title: "Third", code: %Masked{}}
            }} = event(:row_created)

    # the sensitive attribute and the sensitive argument are left out
    assert arguments == %{title: "Third", note: "hi"}
    assert Ash.get!(Card, id).title == "Third"
  end

  test "row actions, a table action and a destroy", %{conn: conn, card: card, other: other} do
    {:ok, view, _html} = given(conn, %{"notify" => [:action_ran, :row_destroyed]})

    act(view, "card", card.id, "assign")

    assert {"card",
            %{action: :assign, key: key, arguments: %{to: "ann"}, record: %Card{assignee: "ann"}}} =
             event(:action_ran)

    assert key == %{id: card.id}

    act(view, "card", card.id, "rename")
    run_panel(view, "card", %{"title" => "Renamed", "reason" => "typo"})

    assert {"card", %{action: :rename, arguments: %{title: "Renamed", reason: "typo"}}} =
             event(:action_ran)

    table_act(view, "card", "count_cards")

    assert {"card", %{action: :count_cards, key: nil, arguments: %{}, result: 3}} =
             event(:action_ran)

    act(view, "card", other.id, "destroy")
    assert {"card", %{action: :destroy, key: key, arguments: %{}}} = event(:row_destroyed)
    assert key == %{id: other.id}
  end

  test "a run on a selection says on which records it ran", %{
    conn: conn,
    card: card,
    other: other
  } do
    {:ok, view, _html} = given(conn, %{"notify" => [:bulk_ran]})

    run_bulk(view, "card", "assign", [card.id, other.id])

    assert {"card", %{action: :assign, all?: false, arguments: %{to: "ann"}} = details} =
             event(:bulk_ran)

    assert Enum.sort(details.succeeded) == Enum.sort([%{id: card.id}, %{id: other.id}])
    assert details.failed == []
  end

  test "a nested table's events carry its id and path, under the id of the table on the page; a picker's table sends none",
       %{conn: conn, card: card, remark: remark} do
    {:ok, view, _html} = given(conn, %{"notify" => true})
    assert {"card", _read} = event(:read)

    nested = nested("card", card.id, "remarks")
    expand(view, "card", card.id)
    toggle(view, "card", card.id, "remarks")

    assert [
             {"card", :row_expanded, %{table: "card", key: key, relationship: :remarks}},
             {"card", :read, %{table: ^nested, path: ["card", ^nested], count: 1}}
           ] = events()

    assert key == %{id: card.id}

    pick(view, nested, remark.id, "card")
    render_async(view)
    assert events() == []

    toggle(view, "card", card.id, "remarks")
    assert [{"card", :row_collapsed, %{key: ^key, relationship: :remarks}}] = events()
  end

  test "`notify` names events the table has", %{conn: conn} do
    assert_raise ArgumentError,
                 ~r/the `notify` of AshDataTable.attach\/4 names \[:row_changed\]/,
                 fn ->
                   given(conn, %{"notify" => [:row_changed]})
                 end
  end

  test "the tag's page is told, in its own process", %{conn: conn, card: card} do
    {:ok, view, _html} =
      live_isolated(conn, DemoWeb.Support.GivenTagLive, session: %{"test" => self()})

    save(view, "card", card.id, "title", "Renamed")
    render_async(view)

    assert [{"card", :read, _}, {"card", :row_saved, %{key: key}}] = events()
    assert key == %{id: card.id}
  end
end
