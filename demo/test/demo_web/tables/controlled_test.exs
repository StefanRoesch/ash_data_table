defmodule DemoWeb.Tables.ControlledTest do
  @moduledoc """
  Controlled mode (stage 6, group V): a table attached with `controlled:`
  holds the question before an action and the action panel as a request,
  which the page draws (`AshDataTable.request/1`) and answers with
  commands; every answer goes through the table's checks, the veto and
  the record read again. `DemoWeb.Support.GivenLive`.
  """
  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Support.Given.{Card, Remark}

  setup %{conn: conn} do
    on_exit(fn -> Demo.Support.Ets.stop([Card, Remark]) end)
    card = Ash.Seed.seed!(Card, %{title: "First"})
    %{conn: conn, card: card}
  end

  defp given(conn, session) do
    session = Map.merge(%{"test" => self(), "controlled" => [:confirm, :panel]}, session)
    live_isolated(conn, DemoWeb.Support.GivenLive, session: session)
  end

  defp run(view, fun) do
    send(view.pid, {:run, fun})
    assert_receive {:ran, told}
    told
  end

  defp request(view), do: run(view, &{&1, AshDataTable.request(&1.assigns.cards)})

  defp answer(view, fun), do: run(view, &{fun.(&1), nil})

  test "a question is held for the page, and Confirm runs the action", %{conn: conn, card: card} do
    {:ok, view, html} = given(conn, %{"notify" => [:requested]})
    # the hook asks nothing: the button has no question
    assert attribute(html, "[id='card-row-#{card.id}-a-destroy']", "data-question") == []

    act(view, "card", card.id, "destroy")
    assert_received {:heard, {:ash_data_table, "card", {:requested, %{ref: ref, kind: :confirm}}}}

    assert %{ref: ^ref, kind: :confirm, action: :destroy, key: key, question: "Delete this card?"} =
             request(view)

    assert key == %{id: card.id}
    assert Ash.read!(Card) != []

    # another ref is no answer
    answer(view, &AshDataTable.confirm_request(&1, :cards, "r0"))
    assert Ash.read!(Card) != []

    answer(view, &AshDataTable.confirm_request(&1, :cards, ref))
    assert Ash.read!(Card) == []
    assert request(view) == nil
  end

  test "a nested table asks its own question: only the table on the page is controlled",
       %{conn: conn, card: card} do
    remark = Ash.Seed.seed!(Remark, %{body: "A remark", card_id: card.id})
    {:ok, view, _html} = given(conn, %{"notify" => [:requested]})
    nested = nested("card", card.id, "remarks")

    expand(view, "card", card.id)
    html = toggle(view, "card", card.id, "remarks")

    # the hook asks before it sends `act`
    assert attribute(html, "[id='#{nested}-row-#{remark.id}-a-destroy']", "data-question") ==
             ["Delete this remark?"]

    act(view, nested, remark.id, "destroy")
    refute_received {:heard, {:ash_data_table, "card", {:requested, _details}}}
    assert request(view) == nil
    assert Ash.read!(Remark) == []
  end

  test "a panel is not drawn: the page has its fields, a sensitive one without its value",
       %{conn: conn} do
    {:ok, view, _html} = given(conn, %{})

    html = open_create(view, "card")
    assert panel(html, "card") == nil

    assert %{kind: :panel, action: :create, key: nil, title: "New card", fields: fields} =
             request(view)

    assert [
             %{name: :title, label: "Title", value: "", required?: false},
             %{name: :code, value: nil},
             %{name: :note},
             %{name: :pin, value: nil}
           ] = fields
  end

  test "an answer the action refuses keeps the request, with what it said at the field",
       %{conn: conn, card: card} do
    {:ok, view, _html} = given(conn, %{})

    act(view, "card", card.id, "rename")
    %{ref: ref, action: :rename, fields: [_title, _reason]} = request(view)

    answer(view, &AshDataTable.validate_request(&1, :cards, ref, %{"title" => "Renamed"}))
    answer(view, &AshDataTable.submit_request(&1, :cards, ref, %{"title" => "Renamed"}))

    assert %{ref: ^ref, fields: [_, %{name: :reason, errors: [_ | _]}]} = request(view)
    assert Ash.get!(Card, card.id).title == "First"

    answer(
      view,
      &AshDataTable.submit_request(&1, :cards, ref, %{"title" => "Renamed", "reason" => "typo"})
    )

    assert request(view) == nil
    assert Ash.get!(Card, card.id).title == "Renamed"
  end

  test "an answer goes through the veto and the record read again", %{conn: conn, card: card} do
    {:ok, view, _html} = given(conn, %{"answer" => {:halt, "Not today."}})

    act(view, "card", card.id, "destroy")
    %{ref: ref} = request(view)
    answer(view, &AshDataTable.confirm_request(&1, :cards, ref))
    assert_received {:asked, %AshDataTable.Request{action: :destroy, from: :row}, true}
    assert Ash.read!(Card) != []

    # gone since the question was held: nothing is destroyed twice, and the page lives
    act(view, "card", card.id, "destroy")
    %{ref: ref} = request(view)
    Ash.destroy!(Ash.get!(Card, card.id), action: :destroy)
    answer(view, &AshDataTable.confirm_request(&1, :cards, ref))
    assert Process.alive?(view.pid)
  end

  test "cancel gives the request up, and nothing runs", %{conn: conn, card: card} do
    {:ok, view, _html} = given(conn, %{})
    act(view, "card", card.id, "rename")
    %{ref: ref} = request(view)

    answer(view, &AshDataTable.cancel_request(&1, :cards, ref))
    assert request(view) == nil
    assert Ash.get!(Card, card.id).title == "First"
  end

  test "attach refuses a panel a page cannot draw, and names its action" do
    assert_raise ArgumentError, ~r/the action `create` has the field `file`/, fn ->
      AshDataTable.attach(%Phoenix.LiveView.Socket{}, :scans, Demo.Support.Files.Scan,
        controlled: [:panel]
      )
    end

    assert_raise ArgumentError, ~r/is a list of `:confirm` and `:panel`/, fn ->
      AshDataTable.attach(%Phoenix.LiveView.Socket{}, :cards, Card, controlled: [:picker])
    end
  end
end
