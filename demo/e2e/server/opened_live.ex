defmodule DemoWeb.E2E.OpenedLive do
  @moduledoc """
  A page for the browser tests of "Open": the tasks attached
  with `open: "Open"`, and beside them what the page was told last, the
  key of the row opened. It is compiled and routed in the e2e environment
  only.
  """
  use DemoWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Opened", opened: nil)
     |> AshDataTable.attach(:tasks, Demo.Tracker.Task,
       heading: 2,
       actor: socket.assigns.current_user,
       tenant: socket.assigns.current_tenant,
       open: "Open"
     )}
  end

  @impl true
  def handle_info({:ash_data_table, "task", {:row_opened, %{key: %{id: id}}}}, socket),
    do: {:noreply, assign(socket, opened: id)}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 class="text-2xl font-semibold">Opened</h1>
      <p id="opened">{@opened}</p>
      <AshDataTable.attached table={@tasks} streams={@streams} uploads={assigns[:uploads]} />
    </Layouts.app>
    """
  end
end
