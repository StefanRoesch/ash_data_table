defmodule DemoWeb.E2E.SwitchLive do
  @moduledoc """
  A page for the browser test of what happens to the nested tables when
  who is asking changes while the page is open (stage 5): the tasks, given
  the actor of the actor switcher, until "Become the viewer" gives them the
  viewer. The page is not left. It is compiled and routed in the e2e
  environment only.
  """
  use DemoWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Switching", actor: socket.assigns.current_user)}
  end

  @impl true
  def handle_event("become", _params, socket) do
    {:noreply, assign(socket, actor: Demo.Actors.fetch(Demo.Actors.id(:viewer)))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 class="text-2xl font-semibold">Switching</h1>
      <button id="become" type="button" class="btn" phx-click="become">Become the viewer</button>
      <AshDataTable.table
        id="task"
        resource={Demo.Tracker.Task}
        heading={2}
        actor={@actor}
        tenant={@current_tenant}
      />
    </Layouts.app>
    """
  end
end
