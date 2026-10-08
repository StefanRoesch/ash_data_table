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

  Reads, saves, row actions and creates are authorized, unless the domain
  says `authorize? false`.
  The table follows the person who mounted the page: a host that changes who
  is logged in mounts the page again, as a login or logout does.

  ## What a person may not see or do

  The table has no rules of its own; it asks Ash and shows the answer.

    * **Records** the person may not see are not there: Ash filters them out.
    * **A field the person can never see** has no column for them, and a URL
      that sorts or filters by it is ignored.
    * **A field hidden on some records only** keeps its column. Its hidden
      cells are empty, announced as "Not available", and cannot be edited.
      A column's component (`AshTable.Component`) is not called for such a
      cell, and is never given the record.
    * **An update action the person can never run** leaves its columns
      read-only for them; if that is every one, the table offers no editing.
      An action that depends on the record leaves cells looking editable, and
      a refusal is shown on the cell when it is saved.
    * **A row action the person can never run** has no button for them; if
      that is every one, the table has no actions column. An action that
      depends on the record keeps its button on every row, and a refusal is
      shown when it runs: on the row's actions cell, or above the fields of
      the action panel, as "You are not allowed to do this."
    * **A create action the person can never run** leaves the table without
      its create button.
    * **An input of a field the person can never see** is no field of an
      action panel for them, in a row action or in a create; one hidden from
      them on a record is left out of that record's panel. A value sent for
      such a field all the same is not given to the action. As for a cell,
      this protects the table only: the action itself accepts the field from
      anyone its policy allows.
    * **A read refused outright** makes the page answer as if it did not
      exist: `AshTable.NotFoundError` is raised, which Phoenix renders as 404.
      That holds for a request, for a live navigation to the page (LiveView
      tells the browser to ask for the page afresh) and for a read that is
      refused while the page is open (the browser is redirected to the same
      URL). With `on_forbidden :message` in the resource's `table` block the
      page stays and says "You are not allowed to see these records."

    * **A related record the person may not read** is an empty reference
      cell, as no related record is; a label hidden from them is "Not
      available". **A destination they can never read** has no column for
      its reference cell.

    * **A relationship whose destination the person can never read** has no
      line under an expanded row. In a nested table everything above holds
      for its own resource. A record created in a nested table is joined to
      the row above by the table, from that row as it is read again for the
      person, never by what the form sends. The row a nested table belongs to is read again,
      as the person, each time the nested table reads: when that row is gone
      or no longer theirs, the nested table says "This record is no longer
      available." A nested table whose read is refused says "You are not
      allowed to see these records." when its resource's block says
      `on_forbidden :message`, and "These records are not available."
      otherwise.

  Ash is asked what a person can never see or do each time the table reads:
  when the page is opened and at every change of sort, filter or page. It
  costs no query.

  Before a cell is saved, before a row action runs and before its panel
  opens, the record is read again by its primary key, as the person. An
  event that names a row that is not on the person's page, or an action the
  table does not offer them, runs nothing.

  ## The heading

  The first line of the page is the table's: its name as the page's `h1`,
  and at the other end the create button, when the resource's `table` block
  names a `create_action` that the person may run. The name is the
  resource's `plural_name`, or its short name, in words (`AshTable.label/1`),
  and is the page title too.

  ## When a read fails

  A read that fails without being refused shows a message in place of the
  rows: the message of an error the read action returned on purpose (Ash's
  "invalid" class), or "The records could not be loaded." for anything else,
  which is logged. A field is named only when the person has a column for it.

  ## Layout

  A LiveView mounted by the router is rendered in the root layout only. Since
  Phoenix 1.8 the app layout is a function component that each page calls
  itself, so this page has to be told which one to call:

      config :ash_table, layout: {MyAppWeb.Layouts, :app}

  The component is called with the table as its inner block and with these
  assigns:

    * `flash`;
    * `current_scope`, nil when the socket has none;
    * `current_user` and `current_tenant`, each when the socket has it;
    * the assigns the resource's domain names as `scope_assign`,
      `actor_assign` and `tenant_assign` (`AshTable.Domain`), under those
      names, each when the socket has it. With the default names these are
      the ones above.

  So a host whose domain says `actor_assign :current_account` has a layout
  that is given `current_account`. A single table can be given another
  layout, or none, in the router: `ash_table "/tasks", Task, layout: false`.
  The configuration is read when the page is rendered. With neither set the
  page is rendered bare.

  ## URL

  Sort, filters and page are kept in the URL, under the table's id:
  `/tasks?task[sort]=-title&task[f][title]=report&task[page]=2`.

  Which rows are expanded, and the sort, filters and page of the tables
  nested in them, are not in the URL. A new read of the table (a change of
  its sort, filters or page) closes what was open in it.

  ## Limited to the records related to one record

  One more parameter of the table, `of`, limits it to the records related to
  one record: `/comments?comment[of][task][comments]=KEY` is the comments of
  one task. It is the short name of the parent's resource, the name of its
  relationship, and the parent's primary key (by attribute where it has
  several: `task[of][task_label][task][task_id]=…`). This is the full view
  of a nested table, which the link in a nested table's last row leads to
  when the router mounts the destination's table. Sort, filters and page
  work beside it, and it stays in the URL through them.

  The page then reads as a nested table does: the parent is read again by
  its key, as the person, on every read, with the relationship as a load.
  Above the grid it says what it shows: the parent, called by its resource's
  `label_field` or by the first column of its table that the person sees on
  it, and the relationship; with a control that takes the limit away. Where
  the nested table would offer create, its button is on this line, and a
  record created there is created under that parent.

  Nothing in the parameter is trusted. The parent's resource is looked up by
  its short name, as text, among the resources of the application's domains
  (`config :my_app, ash_domains: […]`, for the app of the endpoint) and of
  the table's own domain, and counts only when its table offers this person
  that relationship to this table's resource. Anything else is no limit: the
  page shows the table as if nothing had been asked. A parent that is gone or
  not the person's to read shows "This record is no longer available." and
  names no record; a destination whose read is refused is the page's own
  refusal, as above.
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
        <%!-- the page's heading is the first line of the table: its name, and
        its create button at the other end --%>
        <.live_component
          module={AshTable.Live.TableComponent}
          id={@table.id}
          resource={@table.resource}
          url={@url}
          label={@page_title}
          heading={1}
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

  # What the layout is told: the flash, and who is asking under the names the
  # socket has them: those the resource's domain gives them, and the
  # conventional ones. An assign the socket does not have is not passed,
  # except `current_scope`, which the layout of a new Phoenix app expects.
  defp layout_assigns(assigns) do
    names = assigns.table.resource |> AshTable.Domain.Info.assign_names() |> Map.values()

    assigns
    |> Map.take([:flash, :current_user | names])
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
