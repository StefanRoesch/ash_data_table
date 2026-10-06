defmodule AshTable.Live.Page do
  @moduledoc """
  The ready-made LiveView behind `AshTable.Router.ash_table/3`: one resource's
  table as a page of its own.

  It is not used directly. It finds its resource in the metadata of the route
  it was reached through, so one module serves every `ash_table` line of a
  router.

  ## Who is reading

  Actor and tenant come from the socket assigns the host's `on_mount` hooks
  set. Which assigns is said by the resource's domain (`AshTable.Domain`);
  with nothing said there:

    * `current_scope`, when it is assigned and not nil, is passed to Ash as
      the scope (it must implement `Ash.Scope.ToOpts`);
    * otherwise `current_user` is the actor and `current_tenant` the tenant.
      Neither assigned means nobody is logged in.

  Reads and saves are authorized, unless the domain says `authorize? false`.
  The table follows the person who mounted the page: a host that changes who
  is logged in mounts the page again, as a login or logout does.

  ## What a person may not see or do

  The table has no rules of its own; it asks Ash and shows the answer.

    * **Records** the person may not see are not there: Ash filters them out.
    * **A field the person can never see** has no column for them, and a URL
      that sorts or filters by it is ignored.
    * **A field hidden on some records only** keeps its column. Its hidden
      cells are empty, announced as "Not available", and cannot be edited.
    * **An update action the person can never run** leaves its columns
      read-only for them; if that is every one, the table offers no editing.
      An action that depends on the record leaves cells looking editable, and
      a refusal is shown on the cell when it is saved.
    * **A read refused outright** makes the page answer as if it did not
      exist: `AshTable.NotFoundError` is raised, which Phoenix renders as 404.
      That holds for a request, for a live navigation to the page (LiveView
      tells the browser to ask for the page afresh) and for a read that is
      refused while the page is open (the browser is redirected to the same
      URL). With `on_forbidden :message` in the resource's `table` block the
      page stays and says "You are not allowed to see these records."

  Ash is asked what a person can never see or do each time the table reads:
  when the page is opened and at every change of sort, filter or page. It
  costs no query.

  ## Layout

  A LiveView mounted by the router is rendered in the root layout only. Since
  Phoenix 1.8 the app layout is a function component that each page calls
  itself, so this page has to be told which one to call:

      config :ash_table, layout: {MyAppWeb.Layouts, :app}

  The component is called with the table as its inner block and with the
  assigns `flash`, `current_scope` (nil when the socket has none) and, when
  the socket has it, `current_user`. A single table can be given another
  layout, or none, in the router: `ash_table "/tasks", Task, layout: false`.
  The configuration is read when the page is rendered. With neither set the
  page is rendered bare.

  ## URL

  Sort, filters and page are kept in the URL, under the table's id:
  `/tasks?task[sort]=-title&task[f][title]=report&task[page]=2`.
  """
  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, table: nil, url: nil)}
  end

  @impl true
  def handle_params(_params, url, socket) do
    table = route_table!(socket, url)

    {:noreply, assign(socket, table: table, url: url, page_title: AshTable.label(table.resource))}
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :layout, layout(assigns.table))

    ~H"""
    <.in_layout layout={@layout} {layout_assigns(assigns)}>
      <div id={"#{@table.id}-page"}>
        <h1 class="mb-4 text-lg font-semibold">{@page_title}</h1>
        <.live_component
          module={AshTable.Live.TableComponent}
          id={@table.id}
          resource={@table.resource}
          url={@url}
          label={@page_title}
          authorize?={nil}
          mounted?={true}
          {reader(@table.resource, assigns)}
        />
      </div>
    </.in_layout>
    """
  end

  # The route's own choice, else the application's, else none.
  defp layout(%{layout: :default}), do: Application.get_env(:ash_table, :layout, false)
  defp layout(%{layout: layout}), do: layout

  defp layout_assigns(assigns) do
    assigns
    |> Map.take([:flash, :current_user])
    |> Map.put(:current_scope, assigns[:current_scope])
  end

  defp in_layout(%{layout: {module, function}} = assigns) do
    apply(module, function, [Map.delete(assigns, :layout)])
  end

  defp in_layout(assigns) do
    ~H"""
    {render_slot(@inner_block)}
    """
  end

  # Who is asking, from the assigns the resource's domain names.
  defp reader(resource, assigns) do
    case AshTable.Domain.Info.reader(resource, assigns) do
      %{scope: scope} -> %{scope: scope, actor: nil, tenant: nil}
      %{actor: actor, tenant: tenant} -> %{scope: nil, actor: actor, tenant: tenant}
    end
  end

  # `ash_table` puts the table into the route's metadata, which
  # `Phoenix.Router.route_info/4` returns for the URL we were reached by.
  defp route_table!(socket, url) do
    uri = URI.parse(url)

    case Phoenix.Router.route_info(socket.router, "GET", uri.path || "/", uri.host || "") do
      %{ash_table: %{resource: _, id: _, layout: _} = table} ->
        table

      _other ->
        raise ArgumentError,
              "#{inspect(__MODULE__)} was reached at #{inspect(uri.path)}, which is not a route " <>
                "declared with `ash_table` in #{inspect(socket.router)}. Mount a table with " <>
                "`ash_table \"/path\", MyApp.Resource` from `AshTable.Router`."
    end
  end
end
