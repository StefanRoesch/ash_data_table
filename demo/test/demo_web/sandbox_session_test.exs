defmodule DemoWeb.SandboxSessionTest do
  @moduledoc """
  A browser test's database transaction (`e2e/server/sandbox.ex`) and the
  work a table does beside its LiveView: the summaries, the reads after
  the first and the runs on the selected rows of `/tasks`, each in a task
  the LiveView starts (`start_async`), allowed through `$callers` (#66).

  The transaction is started and ended as a browser test does it, with the
  plug `Phoenix.Ecto.SQL.Sandbox` (`POST` and `DELETE /sandbox`). The task
  is held while it holds the test's one connection: a handler of Ash's
  telemetry, which runs in the task, checks the connection out
  (`Demo.Repo.checkout/1`) and waits to be told to go on. Then the
  LiveView ends as it does when the browser leaves the page: its channel
  stops with `{:shutdown, :closed}`. The task finishes its query, and the
  transaction outlives it.
  """
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Demo.Fixtures
  import DemoWeb.TablePage, only: [select_page: 1, confirm_bulk: 3]

  alias Phoenix.Ecto.SQL.Sandbox

  @endpoint DemoWeb.Endpoint

  @handler "sandbox-session-test: held task"

  defp sandbox, do: Sandbox.init(repo: Demo.Repo, at: "/sandbox", timeout: 300_000)

  defp checkout, do: Sandbox.call(Plug.Test.conn(:post, "/sandbox"), sandbox()).resp_body

  defp checkin(metadata) do
    Plug.Test.conn(:delete, "/sandbox")
    |> Plug.Conn.put_req_header("user-agent", metadata)
    |> Sandbox.call(sandbox())
  end

  setup do
    metadata = checkout()
    :ok = metadata |> Sandbox.decode_metadata() |> Sandbox.allow(Ecto.Adapters.SQL.Sandbox)
    Demo.Generator.distinct_ids()
    on_exit(fn -> :telemetry.detach(@handler) end)
    %{metadata: metadata, world: world()}
  end

  # The first of `events` in a process that `held?` names, held in that
  # process while it holds the connection, until it is told `:go`. The test
  # is told which event it holds, and its metadata.
  defp hold(events, held?) do
    test = self()

    :ok =
      :telemetry.attach_many(
        @handler,
        events,
        fn event, _measurements, metadata, _config ->
          if held?.() do
            :telemetry.detach(@handler)

            Demo.Repo.checkout(fn ->
              send(test, {:holding, self(), event, metadata})

              receive do
                :go -> :ok
              end
            end)
          end
        end,
        nil
      )
  end

  # a task of the LiveView `view`'s
  defp task_of?(view), do: view in Process.get(:"$callers", [])

  # The browser leaves while `task` is held: the channel stops as it does
  # when its socket closes, and only then is the task told to go on. The
  # test's transaction is still there, and ends as a test ends it.
  defp leave(view, task, metadata) do
    assert {:dictionary, dictionary} = Process.info(task, :dictionary)
    assert view.pid in Keyword.fetch!(dictionary, :"$callers")

    Process.flag(:trap_exit, true)
    page = Process.monitor(view.pid)
    running = Process.monitor(task)
    Process.exit(view.pid, {:shutdown, :closed})
    assert_receive {:DOWN, ^page, :process, _view, {:shutdown, :closed}}
    send(task, :go)
    # it finishes its query, and ends as a task does that is done
    assert_receive {:DOWN, ^running, :process, ^task, :normal}

    assert %{rows: [[1]]} = Demo.Repo.query!("SELECT 1")
    assert checkin(metadata).status == 200
  end

  test "the page goes while its summaries hold the connection: the transaction outlives them",
       %{metadata: metadata, world: world} do
    # aggregates are asked for by the summaries alone
    hold([[:ash, :tracker, :aggregate, :start]], fn -> true end)
    {:ok, view, _html} = build_conn() |> log_in(world.admin) |> live("/tasks")

    assert_receive {:holding, summaries, [:ash, :tracker, :aggregate, :start],
                    %{resource_short_name: :task}}

    leave(view, summaries, metadata)
  end

  test "the page goes while a read beside it holds the connection: the transaction outlives it",
       %{metadata: metadata, world: world} do
    {:ok, view, _html} = build_conn() |> log_in(world.admin) |> live("/tasks")
    render_async(view)

    hold([[:ash, :tracker, :read, :start]], fn -> task_of?(view.pid) end)
    AshDataTable.Test.send_event(view, "task", "sort", %{"column" => "title"})

    assert_receive {:holding, read, [:ash, :tracker, :read, :start],
                    %{resource_short_name: :task}}

    leave(view, read, metadata)
  end

  test "the page goes while a run on the selected rows holds the connection: the transaction outlives it",
       %{metadata: metadata, world: world} do
    {:ok, view, _html} = build_conn() |> log_in(world.admin) |> live("/tasks")
    render_async(view)
    select_page(view)

    hold([[:ash, :tracker, :bulk_update, :start]], fn -> task_of?(view.pid) end)
    confirm_bulk(view, "task", "archive")

    assert_receive {:holding, run, [:ash, :tracker, :bulk_update, :start],
                    %{resource_short_name: :task, action: :archive}}

    leave(view, run, metadata)
  end
end
