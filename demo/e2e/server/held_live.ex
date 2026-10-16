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
  with `POST /e2e/held/release` (`DemoWeb.E2E.HeldController`). The answer
  to the save is held that long, and nothing else is. Compiled and routed
  in the e2e environment only.
  """
  use DemoWeb, :live_view

  alias DemoWeb.E2E.Held.Essay

  @doc "The name the LiveView goes by while a write of it waits."
  def waiting, do: __MODULE__.Waiting

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

  # Waits until the test lets the write go; a test that never does lets it
  # go after a while, so that a page left open does not hang.
  defp hold(_request) do
    Process.register(self(), waiting())

    receive do
      :release -> :cont
    after
      10_000 -> :cont
    end
  after
    Process.unregister(waiting())
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
    json(conn, %{released: release(50)})
  end

  defp release(0), do: false

  defp release(tries) do
    case Process.whereis(DemoWeb.E2E.HeldLive.waiting()) do
      nil ->
        Process.sleep(100)
        release(tries - 1)

      pid ->
        send(pid, :release)
        true
    end
  end
end
