defmodule DemoWeb.Tables.PageValuesTest do
  @moduledoc """
  What a page gives a table, through the live
  layer: the page's functions are called with its assigns and told which
  table asks, the table on the page, a nested table and a picker's table
  alike; the veto is asked before a write from the browser, with the
  page's assigns, and only halts. `DemoWeb.Support.GivenLive` and
  `DemoWeb.Support.GivenTagLive` (`test/support/given_tables.ex`).
  """
  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias AshDataTable.Request
  alias Demo.Support.Given.{Card, Remark}

  setup %{conn: conn} do
    on_exit(fn -> Demo.Support.Ets.stop([Card, Remark]) end)
    card = Ash.Seed.seed!(Card, %{title: "First"})
    remark = Ash.Seed.seed!(Remark, %{body: "A remark", card_id: card.id})
    %{conn: conn, card: card, remark: remark}
  end

  defp given(conn, session \\ %{}),
    do: live_isolated(conn, DemoWeb.Support.GivenLive, session: Map.put(session, "test", self()))

  # The reason a LiveView went down with, for a callback that raises.
  defp raised(fun) do
    Process.flag(:trap_exit, true)
    {{%ArgumentError{message: message}, _stack}, _call} = catch_exit(fun.())
    message
  end

  test "the table on the page, a nested table and a picker's table are each given them, told which asks",
       %{conn: conn, card: card, remark: remark} do
    {:ok, view, _html} = given(conn)
    assert_received {:read, Card, %{table: "card", path: ["card"], resource: Card}, "s3"}

    nested = nested("card", card.id, "remarks")
    expand(view, "card", card.id)
    toggle(view, "card", card.id, "remarks")
    assert_received {:read, Remark, %{table: ^nested, path: ["card", ^nested]}, "s3"}

    pick(view, nested, remark.id, "card")
    render_async(view)
    assert_received {:read, Card, %{table: picker, path: ["card", ^nested, picker]}, "s3"}
    assert String.starts_with?(picker, nested <> "-pick-")
  end

  test "a save is asked of the veto, with the page's assigns, and given what the page gives",
       %{conn: conn, card: card} do
    {:ok, view, _html} = given(conn)

    save(view, "card", card.id, "title", "Renamed")
    assert_reply view, %{ok: true}

    assert_received {:asked,
                     %Request{
                       table: "card",
                       path: ["card"],
                       resource: Card,
                       action: :update,
                       type: :update,
                       from: :cell,
                       column: :title,
                       key: key
                     }, true}

    assert key == %{id: card.id}
    assert_received {:write, Card, :update, %{secret: "s3"}, %{table: "card"}}
  end

  test "a row action is given the page's argument, which no private argument replaces",
       %{conn: conn, card: card} do
    {:ok, view, _html} = given(conn)

    html = act(view, "card", card.id, "assign")
    assert_received {:asked, %Request{action: :assign, from: :row}, true}
    assert_received {:write, Card, :assign, %{to: "ann", secret: "s3"}, _ref}
    assert column(html, "card", "assignee") == ["ann"]
  end

  test "a veto that halts writes nothing, and its message is said where the save is",
       %{conn: conn, card: card} do
    {:ok, view, _html} = given(conn, %{"answer" => {:halt, "Not today."}})

    html = save(view, "card", card.id, "title", "Renamed")
    assert_reply view, %{ok: false, error: "Not today."}
    assert announcement(html, "card") =~ "Not today."
    refute_received {:write, _, _, _, _}
    assert Ash.get!(Card, card.id).title == "First"
  end

  test "a veto that answers anything else raises", %{conn: conn, card: card} do
    {:ok, view, _html} = given(conn, %{"answer" => :ok})

    assert raised(fn -> save(view, "card", card.id, "title", "Renamed") end) =~
             "the `before_action` of the table answered :ok"

    assert Ash.get!(Card, card.id).title == "First"
  end

  test "a page argument the page does not give raises when the action runs",
       %{conn: conn, card: card} do
    {:ok, view, _html} = given(conn, %{"page" => %{}})

    assert raised(fn -> act(view, "card", card.id, "assign") end) =~
             "the action `assign` of the table takes its argument `to` from the page"

    assert Ash.get!(Card, card.id).assignee == nil
  end

  test "a function of the page is called once in a callback, for each table that asks",
       %{conn: conn, card: card} do
    {:ok, view, _html} = given(conn, %{"count" => true})
    render(view)
    _mounted = calls()

    # a save, the record read again before it, and what it returned
    save(view, "card", card.id, "title", "Renamed")
    assert_reply view, %{ok: true}
    assert calls() == ["card"]

    # a sort, which reads the page again
    view |> element("[id='card-sort-title']") |> render_click()
    render_async(view)
    assert calls() == ["card"]

    # a row opened, and a nested table in it that reads: each asks once
    nested = nested("card", card.id, "remarks")
    expand(view, "card", card.id)
    _expanded = calls()
    toggle(view, "card", card.id, "remarks")
    assert Enum.frequencies(calls()) == %{nested => 1}
  end

  defp calls(sofar \\ []) do
    receive do
      {:called, table} -> calls([table | sofar])
    after
      0 -> Enum.reverse(sofar)
    end
  end

  test "a function of the page that returns no map raises, naming the option", %{conn: conn} do
    assert_raise ArgumentError, ~r/the `context` function of the table returned :nope/, fn ->
      given(conn, %{"context" => fn _assigns -> :nope end})
    end
  end

  test "attach refuses a page value of another shape", %{conn: conn} do
    {:ok, view, _html} = given(conn)

    assert refused(view, :cards, Card, context: "project 7") =~
             "the `context` of AshDataTable.attach/4 is a map, or a function"

    assert refused(view, :cards, Card, before_action: %{}) =~
             "the `before_action` of AshDataTable.attach/4 is a function of the request"
  end

  # What `AshDataTable.attach/4` raises on the socket of the page, in its
  # process; the page goes on as it was.
  defp refused(view, name, resource, opts) do
    send(
      view.pid,
      {:run,
       fn socket ->
         try do
           {socket, AshDataTable.attach(socket, name, resource, opts)}
         rescue
           error in ArgumentError -> {socket, {:raised, Exception.message(error)}}
         end
       end}
    )

    assert_receive {:ran, {:raised, message}}
    message
  end

  test "the tag gives them too, with its assigns", %{conn: conn, card: card} do
    {:ok, view, _html} =
      live_isolated(conn, DemoWeb.Support.GivenTagLive, session: %{"test" => self()})

    assert_received {:read, Card, %{table: "card", path: ["card"]}, "s3"}

    save(view, "card", card.id, "title", "Renamed")
    assert_received {:asked, %Request{table: "card", from: :cell}, [:answer, :test]}
    assert_received {:write, Card, :update, %{secret: "s3"}, _ref}
  end
end
