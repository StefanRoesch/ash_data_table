defmodule AshTable.Live.Page do
  @moduledoc """
  The ready-made LiveView behind `AshTable.Router.ash_table/3`: one resource's
  table as a page of its own.

  It is not used directly. It finds its resource in the metadata of the route
  it was reached through, so one module serves every `ash_table` line of a
  router.

  ## Who is reading

  Actor and tenant come from the socket assigns the host's `on_mount` hooks
  set, by convention:

    * `current_scope`, when it is assigned and not nil, is passed to Ash as
      the scope (it must implement `Ash.Scope.ToOpts`);
    * otherwise `current_user` is the actor and `current_tenant` the tenant.

  Reads are always authorized.

  ## URL

  Sort and page are kept in the URL, under the table's id:
  `/tasks?task[sort]=-title&task[page]=2`.
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
    ~H"""
    <div id={"#{@table.id}-page"}>
      <h1 class="mb-4 text-lg font-semibold">{@page_title}</h1>
      <AshTable.table id={@table.id} resource={@table.resource} url={@url} {reader(assigns)} />
    </div>
    """
  end

  defp reader(assigns) do
    case assigns[:current_scope] do
      nil -> %{actor: assigns[:current_user], tenant: assigns[:current_tenant]}
      scope -> %{scope: scope}
    end
  end

  # `ash_table` puts the table into the route's metadata, which
  # `Phoenix.Router.route_info/4` returns for the URL we were reached by.
  defp route_table!(socket, url) do
    uri = URI.parse(url)

    case Phoenix.Router.route_info(socket.router, "GET", uri.path || "/", uri.host || "") do
      %{ash_table: %{resource: _, id: _} = table} ->
        table

      _other ->
        raise ArgumentError,
              "#{inspect(__MODULE__)} was reached at #{inspect(uri.path)}, which is not a route " <>
                "declared with `ash_table` in #{inspect(socket.router)}. Mount a table with " <>
                "`ash_table \"/path\", MyApp.Resource` from `AshTable.Router`."
    end
  end
end
