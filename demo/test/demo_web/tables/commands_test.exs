defmodule DemoWeb.Tables.CommandsTest do
  @moduledoc """
  What a host tells an attached table (stage 6, group T): read again, take
  a state, clear the selection, give the selected records, and what it may
  read of the table (`AshDataTable.status/1`). The test hands the host's
  LiveView a function to run in its process (`{:run, fun}`):
  `DemoWeb.Support.GivenLive`, and `DemoWeb.Support.AttachedLive` for a
  table whose state is in the URL.
  """
  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias AshDataTable.Sensitive.Masked
  alias Demo.Support.Given.{Card, Remark}
  alias Demo.Support.Live.Bulletin

  setup %{conn: conn} do
    on_exit(fn -> Demo.Support.Ets.stop([Card, Remark, Bulletin]) end)
    card = Ash.Seed.seed!(Card, %{title: "First", code: "c-1"})
    other = Ash.Seed.seed!(Card, %{title: "Second"})
    %{conn: conn, card: card, other: other}
  end

  defp given(conn, session \\ %{}),
    do: live_isolated(conn, DemoWeb.Support.GivenLive, session: Map.put(session, "test", self()))

  # runs `fun` in the LiveView, and gives back what it told
  defp run(view, fun) do
    send(view.pid, {:run, fun})
    assert_receive {:ran, told}
    told
  end

  defp reads do
    receive do
      {:read, Card, %{table: "card"}, _secret} -> 1 + reads()
    after
      0 -> 0
    end
  end

  # what the LiveView went down with, for a command that raises
  defp raised(view, fun) do
    Process.flag(:trap_exit, true)
    ref = Process.monitor(view.pid)
    send(view.pid, {:run, fun})
    assert_receive {:DOWN, ^ref, :process, _pid, {%ArgumentError{message: message}, _stack}}
    message
  end

  test "refresh reads the table once more", %{conn: conn} do
    {:ok, view, _html} = given(conn)
    # the reads of the mount, the static one and the connected one
    assert reads() > 0

    run(view, &{AshDataTable.refresh(&1, :cards), nil})
    render_async(view)
    assert reads() == 1
  end

  test "put_state takes what the table allows, and reads", %{conn: conn} do
    {:ok, view, _html} = given(conn)

    run(view, fn socket ->
      socket =
        AshDataTable.put_state(socket, :cards, %{
          "sort" => "-title",
          "f" => %{"nothing" => %{"v" => "x"}},
          "page" => "7"
        })

      {socket, nil}
    end)

    html = render_async(view)
    assert column(html, "card", "title") == ["Second", "First"]

    assert %{state: %{"sort" => "-title"} = state, count: 2} =
             run(view, &{&1, AshDataTable.status(&1.assigns.cards)})

    refute Map.has_key?(state, "f")
  end

  test "put_state with the state in the URL patches it", %{conn: conn} do
    Ash.Seed.seed!(Bulletin, %{title: "Plain"})

    conn =
      Phoenix.ConnTest.init_test_session(conn, %{"assigns" => %{reader: %{role: :admin}}})

    {:ok, view, _html} = live(conn, "/support/attached")
    send(view.pid, {:run, &AshDataTable.put_state(&1, :bulletins, %{"sort" => "-title"})})
    assert_patch(view, "/support/attached?bulletin[sort]=-title")
  end

  test "clear_selection takes every row out, and tells the hook", %{conn: conn, card: card} do
    {:ok, view, _html} = given(conn)
    select(view, "card", [card.id])

    run(view, &{AshDataTable.clear_selection(&1, :cards), nil})
    assert_push_event view, "ash_data_table:select", %{table: "card", all: false, rows: []}
    assert %{selected: [], all?: false} = run(view, &{&1, AshDataTable.status(&1.assigns.cards)})
  end

  test "selected_records reads the selection again as the person, its sensitive values masked",
       %{conn: conn, card: card, other: other} do
    {:ok, view, _html} = given(conn)

    select(view, "card", [card.id, Ash.UUID.generate()])
    assert {:ok, [%Card{title: "First", code: %Masked{}}]} = selected(view)

    select(view, "card", :all)
    assert {:ok, records} = selected(view)
    assert Enum.sort(Enum.map(records, & &1.id)) == Enum.sort([card.id, other.id])

    assert %{selected: [], all?: true} = run(view, &{&1, AshDataTable.status(&1.assigns.cards)})
  end

  defp selected(view), do: run(view, &{&1, AshDataTable.selected_records(&1, :cards)})

  test "status says what a host may read of the table", %{conn: conn, card: card} do
    {:ok, view, _html} = given(conn)
    select(view, "card", [card.id])

    assert run(view, &{&1, AshDataTable.status(&1.assigns.cards)}) == %{
             id: "card",
             state: %{},
             count: 2,
             total: 2,
             loading?: false,
             error: nil,
             selected: [%{id: card.id}],
             all?: false
           }

    assert AshDataTable.status(nil) == nil
  end

  test "a command for a name no table is attached under raises: the tag takes none",
       %{conn: conn} do
    {:ok, view, _html} =
      live_isolated(conn, DemoWeb.Support.GivenTagLive, session: %{"test" => self()})

    assert raised(view, &{AshDataTable.refresh(&1, :card), nil}) =~
             "AshDataTable.refresh/2: no table is attached under the assign :card"
  end
end
