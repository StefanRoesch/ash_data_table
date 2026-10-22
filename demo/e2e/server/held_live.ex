defmodule DemoWeb.E2E.Held do
  @moduledoc """
  The domain of `DemoWeb.E2E.Held.Essay`, a resource of the browser tests
  alone: the demo's own tables have no column that shows several lines and
  is edited. It keeps its records in memory.
  """
  use Ash.Domain, validate_config_inclusion?: false, extensions: [AshDataTable.Domain]

  resources do
    resource DemoWeb.E2E.Held.Essay
  end
end

defmodule DemoWeb.E2E.Held.Essay do
  @moduledoc "An essay, whose body shows up to three lines and is edited."
  use Ash.Resource,
    domain: DemoWeb.E2E.Held,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource],
    primary_read_warning?: false

  table do
    update_action :update

    column :title

    column :body do
      max_lines 3
    end
  end

  actions do
    defaults [:read, create: [:title, :body]]

    update :update do
      primary? true
      accept [:body]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :body, :string, public?: true
  end
end

defmodule DemoWeb.E2E.HeldLive do
  @moduledoc """
  A page for the browser tests of what a cell shows while its save is on its
  way: the essays, whose every write waits in the table's `before_action`
  (a public option of `AshDataTable.attach/4`) until the test lets it go
  with `POST /e2e/held/release` (`DemoWeb.E2E.HeldController`), the two
  meeting at `DemoWeb.E2E.HeldLatch`. The answer to the save is held that
  long, and nothing else is. Compiled and routed in the e2e environment
  only.
  """
  use DemoWeb, :live_view

  alias DemoWeb.E2E.Held.Essay

  @impl true
  def mount(_params, _session, socket) do
    if Ash.read!(Essay) == [] do
      Ash.create!(Essay, %{title: "Short", body: "One line."})
    end

    {:ok,
     socket
     |> assign(page_title: "Held")
     |> AshDataTable.attach(:essays, Essay, id: "essay", heading: 2, before_action: &hold/1)}
  end

  # Waits until the test lets the write go (`DemoWeb.E2E.HeldLatch`).
  defp hold(_request) do
    :ok = DemoWeb.E2E.HeldLatch.wait()
    :cont
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 class="text-2xl font-semibold">Held</h1>
      <AshDataTable.attached table={@essays} streams={@streams} uploads={assigns[:uploads]} />
    </Layouts.app>
    """
  end
end

defmodule DemoWeb.E2E.HeldController do
  @moduledoc """
  Lets the write that waits on `/e2e/held` go (`DemoWeb.E2E.HeldLive`): once
  one waits, which it does once the save has reached the server.
  """
  use DemoWeb, :controller

  def release(conn, _params) do
    json(conn, %{released: DemoWeb.E2E.HeldLatch.release()})
  end
end

defmodule DemoWeb.E2E.HeldLatch do
  @moduledoc """
  Where a write of `/e2e/held` that waits (`wait/0`) and the test's release
  (`release/0`) meet, whichever comes first: the one that comes first is
  answered as the other comes. Nothing sleeps or polls.

  A write that is never let go goes on after 10 seconds, so that a page
  left open does not hang; a release that finds no write within 5 seconds
  says so (false).
  """
  use GenServer

  @write_waits 10_000
  @release_waits 5_000

  def start_link(_options), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "Waits until the test lets the write go, 10 seconds at most."
  @spec wait() :: :ok
  def wait, do: GenServer.call(__MODULE__, :wait, :infinity)

  @doc "Lets a write go: one that waits, or the next within 5 seconds. Whether one went."
  @spec release() :: boolean
  def release, do: GenServer.call(__MODULE__, :release, :infinity)

  @impl true
  def init(:ok), do: {:ok, %{writes: [], releases: []}}

  @impl true
  def handle_call(:wait, _from, %{releases: [release | rest]} = latch) do
    GenServer.reply(release, true)
    {:reply, :ok, %{latch | releases: rest}}
  end

  def handle_call(:wait, from, latch) do
    Process.send_after(self(), {:given_up, :writes, from, :ok}, @write_waits)
    {:noreply, %{latch | writes: latch.writes ++ [from]}}
  end

  def handle_call(:release, _from, %{writes: [write | rest]} = latch) do
    GenServer.reply(write, :ok)
    {:reply, true, %{latch | writes: rest}}
  end

  def handle_call(:release, from, latch) do
    Process.send_after(self(), {:given_up, :releases, from, false}, @release_waits)
    {:noreply, %{latch | releases: latch.releases ++ [from]}}
  end

  # one that waited too long is answered, if it still waits
  @impl true
  def handle_info({:given_up, kind, from, answer}, latch) do
    waiting = Map.fetch!(latch, kind)

    if from in waiting do
      GenServer.reply(from, answer)
      {:noreply, Map.put(latch, kind, List.delete(waiting, from))}
    else
      {:noreply, latch}
    end
  end
end
