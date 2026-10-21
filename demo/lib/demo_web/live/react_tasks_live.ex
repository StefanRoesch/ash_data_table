defmodule DemoWeb.ReactTasksLive do
  @moduledoc """
  The tasks drawn with the demo's React kit (`DemoWeb.ReactKit`): the table
  of /tasks attached to this LiveView (`AshDataTable.attach/4`), its parts
  React islands drawn with shadcn/ui through live_react, in the browser
  only: the grid, the heading line (with "Columns" and the argument line),
  what a table limited to related records says, the messages in place of
  the rows, the line above the grid (the selection line), the live region
  (the status), the pagination, the question, the action panel and the
  picker. Its sort, filters and page are in the URL, as on /tasks. The
  front page links to it, and so does /tasks (`DemoWeb.Layouts.tasks/1`);
  its link back keeps the URL's query, so the sort and filters carry over.
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

  # the table patches the URL: LiveView calls this on every patch. Both
  # tables have the id "task", so /tasks reads the same query.
  @impl true
  def handle_params(_params, url, socket) do
    heex =
      case URI.parse(url).query do
        nil -> ~p"/tasks"
        query -> ~p"/tasks" <> "?" <> query
      end

    {:noreply, assign(socket, heex: heex)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} time_zone={@time_zone}>
      <:same_table>
        <.link navigate={@heex} class="link">{gettext("The same table in HEEx")}</.link>
      </:same_table>
      <AshDataTable.attached table={@table} streams={@streams} uploads={assigns[:uploads]} />
    </Layouts.app>
    """
  end
end
