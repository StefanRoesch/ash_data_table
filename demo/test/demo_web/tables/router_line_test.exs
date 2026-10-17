defmodule DemoWeb.Tables.RouterLineTest do
  @moduledoc """
  What a route gives its table and hears of it:
  `/support/heard/cards` names `notify`, `open`, `context`,
  `private_arguments`, `page_arguments` and `before_action`, functions as
  `{module, function}`; the host's `on_mount` hook (`DemoWeb.Support.Heard`)
  hears the events and gives the table, `:table`, a command.
  """
  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias AshDataTable.Request
  alias Demo.Support.Given.{Card, Remark}

  setup %{conn: conn} do
    on_exit(fn -> Demo.Support.Ets.stop([Card, Remark]) end)
    card = Ash.Seed.seed!(Card, %{title: "First"})
    conn = Phoenix.ConnTest.init_test_session(conn, %{"test" => self()})
    %{conn: conn, card: card}
  end

  test "the route's functions are called, its events heard, and a command given in the hook",
       %{conn: conn, card: card} do
    {:ok, view, html} = live(conn, "/support/heard/cards")
    assert_received {:read, Card, %{table: "card", path: ["card"]}, "s3"}
    assert_receive {:heard, {:ash_data_table, "card", {:read, %{count: 1}}}}
    assert ["Open" | _] = actions(html, "card", card.id)

    act(view, "card", card.id, "assign")
    assert_received {:asked, %Request{action: :assign, from: :row}, true}
    assert_received {:write, Card, :assign, %{to: "ann", secret: "s3"}, _ref}
    assert_receive {:heard, {:ash_data_table, "card", {:action_ran, %{action: :assign}}}}

    forge(view, "card", "open", %{"row" => card.id})
    assert_receive {:heard, {:ash_data_table, "card", {:row_opened, %{key: key}}}}
    assert key == %{id: card.id}

    send(view.pid, {:run, &AshDataTable.put_state(&1, :table, %{"sort" => "-title"})})
    assert_patch(view, "/support/heard/cards?card[sort]=-title")
  end

  test "an option of another shape is refused where the route is written" do
    assert_raise ArgumentError,
                 ~r/the :context of ash_data_table must be a map, or \{module, function\}/,
                 fn ->
                   AshDataTable.Router.__live_opts__(Card, context: fn _ -> %{} end)
                 end

    assert_raise ArgumentError, ~r/the :notify of ash_data_table names :saved/, fn ->
      AshDataTable.Router.__live_opts__(Card, notify: [:saved])
    end
  end
end
