defmodule DemoWeb.Tables.AttachTest do
  @moduledoc """
  Tables attached to a LiveView of the host's (`AshDataTable.attach/4`,
  `DemoWeb.Support.AttachedLive` in `test/support/attached_tables.ex`, at
  `/support/attached`): the bulletins, whose state is in the URL, and the
  scans, beside a stream, an event, a message, an async result and a
  `handle_params/3` of the host's own.

  The table's events, results and batches reach it through hooks of the
  LiveView, which halt what is the table's and let the rest through; one
  for a table that is gone never reaches the host.
  """
  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Support.Bulk.Crate
  alias Demo.Support.Files.Scan
  alias Demo.Support.Live.{Bulletin, Reply}

  setup %{conn: conn} do
    on_exit(fn -> Demo.Support.Ets.stop([Bulletin, Reply, Scan]) end)

    plain = Ash.Seed.seed!(Bulletin, %{title: "Plain"})
    hidden = Ash.Seed.seed!(Bulletin, %{title: "Kept back", hidden?: true})
    Ash.Seed.seed!(Reply, %{body: "A reply", bulletin_id: plain.id})
    scan = Ash.Seed.seed!(Scan, %{title: "Page 1"})

    %{conn: as(conn, :admin), plain: plain, hidden: hidden, scan: scan}
  end

  defp as(conn, role, session \\ %{}),
    do:
      Phoenix.ConnTest.init_test_session(
        conn,
        Map.merge(%{"assigns" => %{reader: %{role: role}}}, session)
      )

  defp titles(html), do: column(html, "bulletin", "title")
  defp heard(html), do: text(html, "#heard")

  # what the LiveView holds between two callbacks
  defp assigns(view), do: Phoenix.LiveView.Debug.socket(view.pid) |> elem(1) |> Map.get(:assigns)

  # The reason a LiveView went down with, for a callback that raises.
  defp raised(fun) do
    Process.flag(:trap_exit, true)
    {{%ArgumentError{message: message}, _stack}, _call} = catch_exit(fun.())
    message
  end

  test "the host's own event, message, async result and handle_params reach it", %{conn: conn} do
    {:ok, view, html} = live(conn, "/support/attached")
    assert titles(html) == ["Kept back", "Plain"]
    assert text(html, "#url") =~ "/support/attached"

    render_click(view, "say", %{"what" => "hello"})
    send(view.pid, {:note, 1})
    render_click(view, "later", %{})
    html = render_async(view)

    assert heard(html) == ~s([event: "hello", info: {:note, 1}, async: :done])

    # and its own stream, named as a table's once was, beside the tables'
    assert text(html, "#own-1") == "First of the host's"
    assert html =~ ~s(id="own-2")
  end

  test "the state is in the URL: sorting patches it, and the table reads it", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/support/attached")

    # ascending, as the read action sorts already, then descending
    view |> element("#bulletin-head-title") |> render_click()
    assert_patch(view, "/support/attached?bulletin[sort]=title")
    view |> element("#bulletin-head-title") |> render_click()
    assert_patch(view, "/support/attached?bulletin[sort]=-title")
    assert titles(render_async(view)) == ["Plain", "Kept back"]

    {:ok, _view, html} = live(conn, "/support/attached?bulletin[sort]=-title")
    assert titles(html) == ["Plain", "Kept back"]
  end

  test "a LiveView without handle_params/3: sorting patches the URL, and the table reads it",
       %{conn: conn} do
    {:ok, view, html} = live(conn, "/support/attached/paramless?bulletin[sort]=-title")
    assert titles(html) == ["Plain", "Kept back"]

    view |> element("#bulletin-head-title") |> render_click()
    assert_patch(view, "/support/attached/paramless")
    assert titles(render_async(view)) == ["Kept back", "Plain"]
    assert Process.alive?(view.pid)
  end

  test "two attached tables have a stream each, named after them, and their own events",
       %{conn: conn, scan: scan} do
    {:ok, view, _html} = live(conn, "/support/attached")

    %{streams: streams} = assigns(view)
    names = streams |> Map.keys() |> Enum.filter(&is_binary/1) |> Enum.sort()
    assert names == ["bulletin:rows", "rows", "scan:rows"]

    html = act(view, "scan", scan.id, "attach")
    assert panel(html, "scan")
    assert panel(html, "bulletin") == nil
    assert assigns(view).uploads |> Map.keys() |> Enum.filter(&is_binary/1) == ["scan-file-file"]
  end

  test "an event for a nested table that is closed is answered, and the page lives",
       %{conn: conn, plain: plain} do
    {:ok, view, _html} = live(conn, "/support/attached")
    expand(view, "bulletin", plain.id)
    toggle(view, "bulletin", plain.id, "replies")
    nested = nested("bulletin", plain.id, "replies")
    assert has?(view, "[id='#{nested}-table']")

    toggle(view, "bulletin", plain.id, "replies")
    refute has?(view, "[id='#{nested}-table']")

    assert render_hook(view, "ash_data_table:#{nested}:expand", %{"row" => "x"}) =~ "Plain"
    assert_reply(view, %{open: false})
    assert heard(render(view)) == "[]"
  end

  test "attached again as another person, the table closes what is open and reads again",
       %{conn: conn, plain: plain} do
    {:ok, view, _html} = live(conn, "/support/attached")
    expand(view, "bulletin", plain.id)
    toggle(view, "bulletin", plain.id, "replies")
    assert AshDataTable.Test.listening(Reply) == 1

    render_click(view, "as", %{"role" => "reader"})
    html = render_async(view)
    assert titles(html) == ["Plain"]
    refute has?(view, "[id='#{nested("bulletin", plain.id, "replies")}-table']")
    assert AshDataTable.Test.listening(Reply) == 0
  end

  test "what may not be attached raises", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/support/attached")
    assert raised(fn -> render_click(view, "swap", %{}) end) =~ "detach it first"

    {:ok, view, _html} = live(conn, "/support/attached")
    assert raised(fn -> render_click(view, "twin", %{}) end) =~ ~s(the id "bulletin")

    {:ok, view, _html} = live(conn, "/support/attached")
    assert raised(fn -> render_click(view, "over", %{}) end) =~ "under the assign :heard"

    {:ok, view, _html} = live(conn, "/support/attached")
    assert raised(fn -> render_click(view, "inside", %{}) end) =~ ~s(and the id "bulletin")
  end

  test "an event of a name no table has is ignored, for a table that is there or not",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, "/support/attached")
    render_hook(view, "ash_data_table:bulletin:nonsense", %{})
    render_hook(view, "ash_data_table:gone:nonsense", %{"row" => "1"})

    html = render(view)
    assert titles(html) == ["Kept back", "Plain"]
    assert heard(html) == "[]"
  end

  test "url: true in a LiveView that is not mounted by the router raises", %{conn: conn} do
    assert_raise ArgumentError, ~r/`url: true`/, fn ->
      live_isolated(conn, DemoWeb.Support.AttachedLive,
        session: %{"assigns" => %{reader: %{role: :admin}}}
      )
    end
  end

  test "detached, the table leaves no listener and no table, and a late batch is dropped",
       %{conn: conn, plain: plain} do
    {:ok, view, _html} = live(conn, "/support/attached")
    expand(view, "bulletin", plain.id)
    toggle(view, "bulletin", plain.id, "replies")
    assert AshDataTable.Test.listening(Bulletin) == 1
    assert AshDataTable.Test.listening(Reply) == 1

    html = render_click(view, "detach", %{})
    refute html =~ ~s(id="bulletin")
    assert assigns(view).bulletins == nil
    assert AshDataTable.Test.listening(Bulletin) == 0
    assert AshDataTable.Test.listening(Reply) == 0

    send(view.pid, {:ash_data_table_heard, "bulletin", [{:update, %{id: plain.id}}]})
    assert heard(render(view)) == "[]"
  end

  test "attached again after detach under the same id, it takes its streams back",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, "/support/attached")
    render_click(view, "detach", %{})
    render_click(view, "again", %{})
    html = render(view)

    assert titles(html) == ["Kept back", "Plain"]
    names = assigns(view).streams |> Map.keys() |> Enum.filter(&is_binary/1) |> Enum.sort()
    assert names == ["bulletin:rows", "rows", "scan:rows"]
  end

  test "a panel that takes a file, drawn without the page's uploads, says what to pass",
       %{conn: conn, scan: scan} do
    conn = as(conn, :admin, %{"uploads" => false})
    {:ok, view, _html} = live(conn, "/support/attached")

    assert raised(fn -> act(view, "scan", scan.id, "attach") end) =~
             "pass `uploads={assigns[:uploads]}` to `AshDataTable.attached`"
  end

  test "with its state in the table, the table reads in mount", %{conn: conn} do
    conn = as(conn, :admin, %{"url" => false})
    {:ok, view, html} = live(conn, "/support/attached")
    assert titles(html) == ["Kept back", "Plain"]

    view |> element("#bulletin-head-title") |> render_click()
    view |> element("#bulletin-head-title") |> render_click()
    assert titles(render_async(view)) == ["Plain", "Kept back"]
    assert text(render(view), "#url") == "http://www.example.com/support/attached"
  end

  describe "a router page whose `on_mount` hook assigns another person while it is open" do
    setup do
      on_exit(fn -> Demo.Support.Ets.stop(Crate) end)
      %{crates: for(n <- 1..2, do: Ash.Seed.seed!(Crate, %{title: "Crate #{n}"}))}
    end

    defp switch(view, assigns), do: send(view.pid, {:switch, assigns})

    # Waits until `count` more messages have reached the mailbox of `pid`,
    # whose receiving is traced (`:erlang.trace/3` with `:receive`).
    defp arrived(pid, count) do
      for _message <- 1..count//1,
          do: assert_receive({:trace, ^pid, :receive, _message}, 5_000)

      :ok
    end

    defp user(conn, user),
      do: Phoenix.ConnTest.init_test_session(conn, %{"assigns" => %{current_user: user}})

    test "the table reads as them, and the layout is given them", %{conn: conn} do
      {:ok, view, html} = live(conn, "/support/switched/bulletins")
      assert titles(html) == ["Kept back", "Plain"]

      switch(view, %{reader: %{role: :reader}})
      # the page attaches its table again in a callback of its own, after
      # the render the hook's change made
      render(view)
      assert titles(render_async(view)) == ["Plain"]
      assert assigns(view).layout_assigns.reader == %{role: :reader}
    end

    test "an event that is waiting when they are assigned runs as them", %{
      conn: conn,
      hidden: hidden
    } do
      {:ok, view, _html} = live(conn, "/support/switched/bulletins")

      # the save waits in the page's mailbox behind what the hook assigns:
      # LiveViewTest asks the page first (a ping) and then sends the event,
      # so the page holds after the ping until both wait. A reader may not
      # read the bulletin kept back, so it is not saved.
      :ok = :sys.suspend(view.pid)
      :erlang.trace(view.pid, true, [:receive])
      saving = Task.async(fn -> save(view, "bulletin", hidden.id, "title", "Changed") end)
      # the ping
      arrived(view.pid, 1)
      send(view.pid, {:hold, self()})
      switch(view, %{reader: %{role: :reader}})
      :ok = :sys.resume(view.pid)
      assert_receive :held
      # the hold, the switch, the resume, and the event after the ping's answer
      arrived(view.pid, 4)
      :erlang.trace(view.pid, false, [:receive])
      send(view.pid, :go)
      Task.await(saving)
      assert_reply(view, %{ok: false})

      assert titles(render_async(view)) == ["Plain"]
      assert Ash.get!(Bulletin, hidden.id, authorize?: false).title == "Kept back"
    end

    test "a run on the selected rows goes on, and says what it came to when the person is the same",
         %{conn: conn, crates: [first | _]} do
      someone = %Demo.Tracker.User{id: Ash.UUID.generate(), role: :admin}
      {:ok, view, _html} = live(user(conn, someone), "/support/switched/crates")

      select(view, "crate", [first.id])

      confirm_bulk(view, "crate", "weigh")
      switch(view, %{current_user: %{someone | role: :member}})

      html = ran(view)
      assert bulk_result(html, "crate") == %{summary: "Weigh: 1 done.", failures: []}
      assert announcement(html, "crate") == "Weigh: 1 done."
    end

    test "a run on the selected rows goes on, and says nothing of it to another person",
         %{conn: conn, crates: [first | _]} do
      someone = %Demo.Tracker.User{id: Ash.UUID.generate(), role: :admin}
      other = %Demo.Tracker.User{id: Ash.UUID.generate(), role: :admin}
      {:ok, view, _html} = live(user(conn, someone), "/support/switched/crates")

      select(view, "crate", [first.id])

      confirm_bulk(view, "crate", "weigh")
      switch(view, %{current_user: other})

      html = ran(view)
      assert bulk_result(html, "crate") == nil
      refute html =~ "Weigh: 1 done."
      refute_push_event view, "ash_data_table:select", %{table: "crate"}

      # it ran all the same
      assert column(html, "crate", "title") == ["Crate 1", "Crate 2"]
    end

    test "a patch to another route of the table attaches it anew, and an answer for the one before is dropped",
         %{conn: conn, crates: [first | _]} do
      {:ok, view, _html} = live(conn, "/support/switched/crates")
      select(view, "crate", [first.id])
      confirm_bulk(view, "crate", "weigh")

      # the run is cancelled as its table is detached; its answer, that it
      # was, comes all the same, to a table of the same id
      render_patch(view, "/support/switched/crates/still")
      html = ran(view)

      assert Process.alive?(view.pid)
      assert bulk_result(html, "crate") == nil
      assert column(html, "crate", "title") == ["Crate 1", "Crate 2"]
    end
  end
end
