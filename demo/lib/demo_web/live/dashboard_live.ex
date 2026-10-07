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

      <%!-- Each table names itself on the line above it, with its create
      button at the other end: `heading` makes that name a heading of this
      page, and the section is named by it. --%>
      <section id="dashboard-projects-section" aria-labelledby="dashboard-projects-name">
        <AshTable.table
          id="dashboard-projects"
          resource={Demo.Tracker.Project}
          heading={2}
          actor={@current_user}
          tenant={@current_tenant}
        />
      </section>

      <section id="dashboard-tasks-section" aria-labelledby="dashboard-tasks-name">
        <AshTable.table
          id="dashboard-tasks"
          resource={Demo.Tracker.Task}
          heading={2}
          actor={@current_user}
          tenant={@current_tenant}
        />
      </section>
    </Layouts.app>
    """
  end
end
