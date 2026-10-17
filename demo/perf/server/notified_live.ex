defmodule DemoWeb.Perf.NotifiedLive do
  @moduledoc """
  The tasks of /tasks attached to a LiveView of the host's with what a
  page gives a table and hears of it: every event (`notify:
  true`), a `context` function, and a veto that lets everything through.
  For the performance scripts, in the perf environment only.
  """
  use DemoWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Notified", heard: 0)
     |> AshDataTable.attach(:tasks, Demo.Tracker.Task,
       heading: 2,
       actor: socket.assigns.current_user,
       tenant: socket.assigns[:current_tenant],
       notify: true,
       context: fn assigns, ref ->
         %{shared: %{page: "notified", table: ref.table, heard: assigns.heard}}
       end,
       before_action: fn _request, _assigns -> :cont end
     )}
  end

  # every event is heard, and counted
  @impl true
  def handle_info({:ash_data_table, _id, _event}, socket),
    do: {:noreply, assign(socket, heard: socket.assigns.heard + 1)}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <AshDataTable.attached table={@tasks} streams={@streams} uploads={assigns[:uploads]} />
    </Layouts.app>
    """
  end
end
