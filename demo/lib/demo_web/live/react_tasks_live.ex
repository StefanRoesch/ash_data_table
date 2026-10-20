defmodule DemoWeb.ReactTasksLive do
  @moduledoc """
  The tasks drawn with the demo's React kit (`DemoWeb.ReactKit`): the table
  of /tasks attached to this LiveView (`AshDataTable.attach/4`), its parts
  React islands drawn with shadcn/ui through live_react, in the browser
  only: the grid, the heading line (with "Columns" and the argument line),
  what a table limited to related records says, the messages in place of
  the rows, the line above the grid (the selection line), the live region
  (the status) and the pagination; the panel, the picker and the question
  are still the default kit's (R3). Its sort, filters and page are in the
  URL, as on /tasks.
  """
  use DemoWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Tasks (React)")
     |> AshDataTable.attach(:table, Demo.Tracker.Task,
       kit: DemoWeb.ReactKit,
       heading: 1,
       url: true,
       actor: socket.assigns.current_user,
       tenant: socket.assigns.current_tenant,
       time_zone: socket.assigns.time_zone
     )}
  end

  # the table patches the URL: LiveView calls this on every patch
  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} time_zone={@time_zone}>
      <AshDataTable.attached table={@table} streams={@streams} uploads={assigns[:uploads]} />
    </Layouts.app>
    """
  end
end
