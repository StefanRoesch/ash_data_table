defmodule DemoWeb.Support.ModesLive do
  @moduledoc """
  The table of a router line, placed in a LiveView of a host's own: by the
  tag (`:embedded`) or by `AshDataTable.attach/4` (`:attached`), for the
  tests that run three ways (`DemoWeb.ModeCase`). It finds the
  route of the path it is reached by (`/*path`) as `AshDataTable.Live.Page`
  does (under the `"prefix"` of its live session), and places that table
  with what the page gives it: the same id,
  label, heading 1, reader, time zone, state in the URL, and the same
  layout around it, given its assigns as the page gives them.
  """
  use Phoenix.LiveView

  @impl true
  def mount(%{"path" => path}, session, socket) do
    route = route!(socket, Map.get(session, "prefix", "") <> "/" <> Enum.join(path, "/"))
    label = AshDataTable.label(route.resource)

    # what the tag and the layout are given, made once: the assigns of the
    # host's `on_mount` hooks, as LiveView gives them
    socket =
      assign(socket,
        route: route,
        page_title: label,
        url: nil,
        page_assigns: Map.drop(socket.assigns, [:flash, :live_action]),
        layout_assigns: layout_assigns(route, socket.assigns)
      )

    socket =
      case socket.assigns.live_action do
        :embedded ->
          socket

        :attached ->
          AshDataTable.attach(
            socket,
            :table,
            route.resource,
            [
              id: route.id,
              table: route.table,
              url: true,
              label: label,
              heading: 1,
              authorize?: route.authorize?,
              live?: route.live?,
              time_zone: time_zone(route.resource, socket.assigns)
            ] ++ reader(route.resource, socket.assigns)
          )
      end

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, url, socket), do: {:noreply, assign(socket, url: url)}

  @impl true
  def render(assigns) do
    ~H"""
    <.in_layout layout={layout(@route)} flash={@flash} given={@layout_assigns}>
      <div id={"#{@route.id}-page"}>
        <AshDataTable.table
          :if={@live_action == :embedded}
          id={@route.id}
          resource={@route.resource}
          table={@route.table}
          url={@url}
          label={@page_title}
          heading={1}
          authorize?={@route.authorize?}
          live?={@route.live?}
          time_zone={time_zone(@route.resource, assigns)}
          assigns={@page_assigns}
          {Map.new(reader(@route.resource, assigns))}
        />
        <AshDataTable.attached
          :if={@live_action == :attached}
          table={@table}
          streams={@streams}
          uploads={assigns[:uploads]}
        />
      </div>
    </.in_layout>
    """
  end

  # What the page around a table gives it, as `AshDataTable.Live.Page` does.
  defp layout(%{layout: :default}), do: Application.get_env(:ash_data_table, :layout, false)
  defp layout(%{layout: layout}), do: layout

  defp layout_assigns(%{resource: resource}, assigns) do
    names = resource |> AshDataTable.Domain.Info.assign_names() |> Map.values()
    zone = AshDataTable.Domain.Info.time_zone_assign(resource)

    assigns
    |> Map.take([:current_user, zone | names])
    |> Map.put(:current_scope, assigns[:current_scope])
  end

  # as the page does: given as one attribute, put into the layout's
  # assigns with `assign/2`, called without `layout` and `given`
  defp in_layout(%{layout: {module, function}, given: given} = assigns),
    do: apply(module, function, [assigns |> assign(given) |> Map.drop([:layout, :given])])

  defp in_layout(assigns) do
    ~H"""
    {render_slot(@inner_block)}
    """
  end

  defp time_zone(resource, assigns),
    do: assigns[AshDataTable.Domain.Info.time_zone_assign(resource)]

  defp reader(resource, assigns) do
    case AshDataTable.Domain.Info.reader(resource, assigns) do
      %{scope: scope} -> [scope: scope]
      %{actor: actor, tenant: tenant} -> [actor: actor, tenant: tenant]
    end
  end

  # The route of the router line, as the page reached at the same path on
  # the demo's own host finds it.
  defp route!(socket, path) do
    %{ash_data_table: route} =
      Phoenix.Router.route_info(socket.router, "GET", path, "www.example.com")

    route
    |> Map.put_new(:table, :default)
    |> Map.put_new(:authorize?, nil)
    |> Map.put_new(:live?, nil)
  end
end

defmodule DemoWeb.Support.AttachedDashboardLive do
  @moduledoc """
  The demo's dashboard (`DemoWeb.DashboardLive`) with its two tables
  attached to it (`AshDataTable.attach/4`) in place of the tag: the same
  markup, for the snapshot that runs three ways.
  """
  use DemoWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    %{current_user: actor, current_tenant: tenant, time_zone: zone} = socket.assigns

    {:ok,
     socket
     |> assign(page_title: "Dashboard")
     |> AshDataTable.attach(:projects, Demo.Tracker.Project,
       id: "dashboard-projects",
       heading: 2,
       actor: actor,
       tenant: tenant,
       time_zone: zone
     )
     |> AshDataTable.attach(:tasks, Demo.Tracker.Task,
       id: "dashboard-tasks",
       heading: 2,
       actor: actor,
       tenant: tenant,
       time_zone: zone
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} time_zone={@time_zone}>
      <div class="space-y-2">
        <h1 class="text-2xl font-semibold">Dashboard</h1>
        <p class="text-base-content/70">
          Two tables embedded in one LiveView with <code class="text-xs">&lt;AshDataTable.table&gt;</code>.
          Each keeps its own sort, filters and page; neither is in the URL.
        </p>
      </div>

      <%!-- Each table names itself on the line above it, with its create
      button at the other end: `heading` makes that name a heading of this
      page, and the section is named by it. --%>
      <section id="dashboard-projects-section" aria-labelledby="dashboard-projects-name">
        <AshDataTable.attached table={@projects} streams={@streams} uploads={assigns[:uploads]} />
      </section>

      <section id="dashboard-tasks-section" aria-labelledby="dashboard-tasks-name">
        <AshDataTable.attached table={@tasks} streams={@streams} uploads={assigns[:uploads]} />
      </section>
    </Layouts.app>
    """
  end
end
