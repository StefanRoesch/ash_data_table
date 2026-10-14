defmodule AshTable.Live.Page do
  @moduledoc """
  The ready-made LiveView behind `AshTable.Router.ash_table/3`: one table of
  a resource as a page of its own. That is the resource's default table,
  or the named table the route names (`table: :compact`).

  It is not used directly. It finds its resource and the table's name in the
  metadata of the route it was reached through, so one module serves every
  `ash_table` line of a router. A route that names a table the resource
  does not have is an error when the page is opened, which lists the tables
  the resource has.

  ## Who is reading

  Actor and tenant come from the socket assigns the host's `on_mount` hooks
  set. Which assigns is said by the resource's domain (`AshTable.Domain`);
  with nothing said there:

    * `current_scope`, when it is assigned and not nil, is passed to Ash as
      the scope (it must implement `Ash.Scope.ToOpts`);
    * otherwise `current_user` is the actor and `current_tenant` the tenant.
      Neither assigned means nobody is logged in.

  Reads, saves, row actions and creates are authorized, unless the domain
  says `authorize? false`, or the route of the page does
  (`ash_table "/admin/tasks", Task, authorize?: false`: see "Without
  authorization" in `AshTable.Router.ash_table/3`). The route wins over the
  domain either way. Nothing a browser sends has a say in it: not the URL,
  not the session, not an event.
  The table follows the person who mounted the page: a host that changes who
  is logged in mounts the page again, as a login or logout does.

  ## Time zone

  Datetimes are shown, typed and filtered by in the time zone of the socket
  assign the resource's domain names as `time_zone_assign` (`time_zone`
  with nothing said there), which the host's `on_mount` hooks set; in UTC
  where it is not assigned or nil. A name that is no time zone, or a zone
  without a time zone database configured, is an `ArgumentError` that names
  the assign. See the guide "Time zones".

  ## What a person may not see or do

  The table has no rules of its own; it asks Ash and shows the answer.

    * **Records** the person may not see are not there: Ash filters them out.
    * **A field the person can never see** has no column for them, and a URL
      that sorts or filters by it is ignored.
    * **A field hidden on some records only** keeps its column. Its hidden
      cells are empty, announced as "Not available", and cannot be edited.
      A column's component (`AshTable.Component`) is not called for such a
      cell, and is never given the record.
    * **A field the resource declares `sensitive?`** has a column whose
      cells show a mask, the same for every value, until the person asks
      for the value of one cell: the record is then read again, as them, and
      a value that is hidden from them on it is not given. `sensitive?` is
      no access rule: whoever may read the field may ask. Such a column is
      neither sorted nor filtered by, and its editor hides what is typed.
    * **An update action the person can never run** leaves its columns
      read-only for them; if that is every one, the table offers no editing.
      An action that depends on the record leaves cells looking editable, and
      a refusal is shown on the cell when it is saved.
    * **A row action the person can never run** has no button for them; if
      that is every one, the table has no actions column. An action that
      depends on the record keeps its button on every row, and a refusal is
      shown when it runs: on the row's actions cell, or above the fields of
      the action panel, as "You are not allowed to do this."
    * **A row action on the rows a person has selected** is the same
      action, run on each record as the person. It is offered where the
      person can ever run it; if that is none, the table has no boxes to
      select rows with. Each selected record is read first, through the
      table's read action and as the person, and the action's policies are
      asked for each by itself: a record they refuse is not changed, is
      counted as not done, and stays selected. An input of a field the
      person sees on some records only is no field of such an action's
      panel.
    * **A create action the person can never run** leaves the table without
      its create button.
    * **A table action the person can never run** has no button for them.
      A generic action is asked about without its arguments: what its
      policy makes of an argument, the key of a row among them, is shown
      as a refusal when the action runs.
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

    * **A related record is chosen from what the person may read.** The
      picker of a reference cell, and of a field of the action panel that
      holds such a key, shows the destination's table as the person may
      read it. The record they choose is read again by its key, as them,
      before the key is saved or the action runs: a key from the browser
      that names no record they may read there changes nothing. A person
      who can never read the destination that way, or can never see the
      key, has no editor for the cell.

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
  table does not offer them, runs nothing. The rows a person has selected
  need not be on the page, as a selection outlives its page: each is read
  by its primary key, as the person, before the action runs on it, and a
  key that names nothing they may read through the table runs nothing.

  ## Live updates

  Where the resource's `table` block says `live? true`, the page follows
  what others change (see "Live updates" in `AshTable.Resource`), unless its
  route says `live?: false`. What is announced is a primary key. The record
  is read again as the person who mounted the page, through the table's
  read action and with its arguments, so everything above holds for a row
  that is updated this way as for one that was read with the page; and the
  page says that there are new or changed records only when at least one of
  them is a record that person would be shown.

  ## Arguments

  The line of inputs above the grid holds the arguments of the table's read
  action, and those its columns ask for. While an argument that the read
  action requires is empty, the action is not run and the page says which
  to fill in. A person who can never run the read action is not asked: Ash
  says so without a read, and they are answered as when the read is refused
  (see above). A default of an asked argument that is a function is given
  the assigns of this page's socket, as the host's `on_mount` hooks set
  them.

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
      the ones above;
    * the assign it names as `time_zone_assign` (`time_zone` by default),
      when the socket has it, so that the layout can say which zone the
      datetimes are in.

  So a host whose domain says `actor_assign :current_account` has a layout
  that is given `current_account`. A single table can be given another
  layout, or none, in the router: `ash_table "/tasks", Task, layout: false`.
  The configuration is read when the page is rendered. With neither set the
  page is rendered bare.

  ## URL

  Sort, filters and page are kept in the URL, under the table's id:
  `/tasks?task[sort]=-title&task[f][title]=report&task[page]=2`. So is what
  the person gave the arguments of the read action
  (`task[a][search]=login`) and those a column asks for
  (`task[c][price_in][currency]=usd`): see "Arguments" in
  `AshTable.Resource`.

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
  when the router mounts the table that is nested: the same table of the
  destination, so a nested table that shows a named table links to a page
  of that named table (`ash_table "/comments/compact", Comment, table:
  :compact`) and to no other. Where the relationship is offered by a named
  table of the parent, the parent is named with that table:
  `comment[of][task_board][comments]=KEY`. Sort, filters and page
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
  that relationship to this table of this table's resource. Anything else is no limit: the
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
          table={@table.table}
          url={@url}
          label={@page_title}
          heading={1}
          authorize?={@table.authorize?}
          live?={@table.live?}
          mounted?={true}
          page_assigns={page_assigns(assigns)}
          time_zone={time_zone(@table.resource, assigns)}
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
    resource = assigns.table.resource
    names = resource |> AshTable.Domain.Info.assign_names() |> Map.values()
    zone = AshTable.Domain.Info.time_zone_assign(resource)

    assigns
    |> Map.take([:flash, :current_user, zone | names])
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

  # The assigns of the page, as a default of an asked argument is given
  # them (`ask :currency, default: &MyApp.Defaults.currency/1`): what the
  # host's `on_mount` hooks have assigned, without what is LiveView's own
  # and this page's.
  defp page_assigns(assigns),
    do: Map.drop(assigns, [:__changed__, :socket, :flash, :live_action, :table, :url, :layout])

  # The zone of the page, from the assign the resource's domain names.
  defp time_zone(resource, assigns) do
    name = AshTable.Domain.Info.time_zone_assign(resource)

    AshTable.Zone.check!(
      assigns[name],
      "The socket assign `#{inspect(name)}` (the `time_zone_assign` of the domain of " <>
        "#{inspect(resource)})"
    )
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
      %{ash_table: %{resource: resource, id: _, layout: _} = table} ->
        # which of the resource's tables the route mounts: its default
        # table where it names none
        table = Map.put_new(table, :table, :default)

        # The router does not look at the resource, so that it does not
        # depend on it at compile time: a table the resource does not have
        # is found here. (A resource without the extension is the table
        # model's to refuse.)
        if AshTable.Resource.Relating.table?(resource) and
             AshTable.Resource.Info.table(resource, table.table) == :error do
          raise ArgumentError,
                "`ash_table` mounts the table `#{inspect(table.table)}` of #{inspect(resource)} " <>
                  "at #{inspect(uri.path)}, but " <>
                  AshTable.Resource.Info.no_table(resource, table.table)
        end

        # what the route says about authorization, and nothing else does:
        # nil where it says nothing, which leaves it to the domain
        # and about live updates: nil leaves it to the resource
        table |> Map.put_new(:authorize?, nil) |> Map.put_new(:live?, nil)

      _other ->
        raise ArgumentError,
              "#{inspect(__MODULE__)} was reached at #{inspect(uri.path)}, which is not a route " <>
                "declared with `ash_table` in #{inspect(socket.router)}. Mount a table with " <>
                "`ash_table \"/path\", MyApp.Resource` from `AshTable.Router`."
    end
  end
end
