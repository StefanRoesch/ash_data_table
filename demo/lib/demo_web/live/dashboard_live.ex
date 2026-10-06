defmodule DemoWeb.DashboardLive do
  @moduledoc """
  A page of the demo's own with two tables placed in it: `AshTable.table/1`
  inside a host LiveView, where the router's `ash_table` gives a table a page
  to itself.

  Each table is given who is asking as attributes, and keeps its sort,
  filters and page itself: nothing of them is in the URL, and neither table
  moves when the other does.
  """
  use DemoWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Dashboard")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-2">
        <h1 class="text-2xl font-semibold">Dashboard</h1>
        <p class="text-base-content/70">
          Two tables embedded in one LiveView with <code class="text-xs">&lt;AshTable.table&gt;</code>.
          Each keeps its own sort, filters and page; neither is in the URL.
        </p>
      </div>

      <section id="dashboard-projects-section" aria-labelledby="dashboard-projects-heading">
        <h2 id="dashboard-projects-heading" class="mb-2 text-lg font-semibold">Projects</h2>
        <AshTable.table
          id="dashboard-projects"
          resource={Demo.Tracker.Project}
          actor={@current_user}
          tenant={@current_tenant}
        />
      </section>

      <section id="dashboard-tasks-section" aria-labelledby="dashboard-tasks-heading">
        <h2 id="dashboard-tasks-heading" class="mb-2 text-lg font-semibold">Tasks</h2>
        <AshTable.table
          id="dashboard-tasks"
          resource={Demo.Tracker.Task}
          actor={@current_user}
          tenant={@current_tenant}
        />
      </section>
    </Layouts.app>
    """
  end
end
