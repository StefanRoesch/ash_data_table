defmodule AshDataTable do
  @moduledoc """
  Presents an Ash resource to people as a table in Phoenix LiveView.

  A resource gets a table by listing the extension `AshDataTable.Resource`, and
  optionally describing the table in a `table do … end` block: its default
  table. It can have further, named tables beside it (`tables do table
  :compact do … end end`). A table reaches a page in one of three ways:

    * mounted as a page of its own, with one line in the router: see
      `AshDataTable.Router.ash_data_table/3`;
    * placed in an existing LiveView with `table/1`;
    * attached to an existing LiveView with `attach/4`, and drawn with
      `attached/1`.

  The table offers only what the resource offers. Sorting, filtering and
  pagination run on the server through the read action; page size and default
  sort live on that action, and a person gives its arguments in a line of
  inputs above the rows. A cell is edited in place through the update
  action its column names, with the cell's value as the only input, and the
  table shows what the action returns. A row has buttons for the update and
  destroy actions the block declares, and the table a button for its create
  action and one for each generic action the block declares; an action with
  inputs asks for them in the action panel. A row
  expands into the tables of its related records, each the table of its own
  resource, and a column can show a related record by its label: see
  `AshDataTable.Resource`.

  ## Configuration

  All of it is optional, and read while the application runs:

      config :ash_data_table,
        layout: {MyAppWeb.Layouts, :app},
        gettext_backend: MyAppWeb.Gettext,
        translate_error: {MyAppWeb.CoreComponents, :translate_error},
        kit: MyAppWeb.TableKit

    * `:layout` - the function component a mounted table is rendered in:
      see `AshDataTable.Live.Page`. Without it, mounted tables are rendered bare.
    * `:gettext_backend` - the Gettext backend that translates the table's
      own texts and the labels of the resource: see `AshDataTable.Gettext`.
      Without it, they are in English.
    * `:translate_error` - `{module, function}` naming a function that takes
      `{message, variables}` and returns the text to show, as the
      `translate_error/1` of a Phoenix application's core components does.
      The messages of the resource's actions are given to it: those of a
      failed save, of a row action or a create that failed, and those of a
      read that failed with an error the action returned. Without it, a message is shown as the resource wrote it, with
      its variables filled in.
    * `:kit` - the module the tables are drawn with: see `AshDataTable.Kit`.
      Without it, `AshDataTable.Kit.Default`. A table is given one of its own
      with `kit`, which wins.

  `mix ash_data_table.install` sets the first three for a new Phoenix application.
  """
  use Phoenix.Component

  alias AshDataTable.Live.Core.Url
  alias AshDataTable.Routes

  # What the page gives the table, as `attach/4` and the tag take it.
  @page [:context, :private_arguments, :page_arguments, :before_action]

  @doc """
  Renders the table of a resource inside a LiveView.

      <AshDataTable.table id="tasks" resource={MyApp.Tracker.Task} scope={@current_scope} />

  That is the resource's default table. `table` places one of its named
  tables (see "Named tables" in `AshDataTable.Resource`):

      <AshDataTable.table resource={MyApp.Tracker.Task} table={:board} scope={@current_scope} />

  The `id` can be left out: it is then the last part of the resource's
  module name, underscored, followed by `_` and the table's name for a
  named table (`task`, `task_board`). So the tables of one resource can
  stand on one page without an id being written; two placements of the
  same table need one each.

  The table reads through the resource's read action, saves through its
  update actions, and runs the row actions and the create action its block
  declares. Pass who is reading as `scope` (an `Ash.Scope`), or as
  `actor` and `tenant`; with none of them nobody is logged in. The assign
  names of `AshDataTable.Domain` are for mounted tables and play no part here.

  Authorization is on, unless the resource's domain says `authorize? false`
  (see `AshDataTable.Domain`) or the table is given `authorize?` itself, which
  wins over the domain either way.

  What the person may not see or do is left out as on a mounted table (see
  `AshDataTable.Live.Page`), with one difference: a table in a page of the host's
  cannot make that page answer "not found". When the read is refused
  outright, it renders nothing at all, unless the resource's `table` block
  says `on_forbidden :message`. What a person can never see or do is asked of
  Ash when the table is first rendered and whenever its attributes change.

  The table keeps its sort, filters and page itself. To keep them in the
  page's URL instead, so that reload, the back button and shared links work,
  pass the current URL as `url` (the second argument of
  `c:Phoenix.LiveView.handle_params/3`, assigned by the LiveView). The table
  then patches the URL, with its parameters under its `id`:
  `?tasks[sort]=-title&tasks[f][title]=report&tasks[page]=2`. Other parameters
  of the page are left as they are. A table with its state in the URL also
  reads the parameter that limits it to the records related to one record
  (`tasks[of][project][tasks]=KEY`): see `AshDataTable.Live.Page`.

  The arguments of the table's read action, and those its columns ask for
  (see "Arguments" in `AshDataTable.Resource`), are kept with the sort and the
  filters: by the table itself, or in the `url`. A default of an asked
  argument that is a function is given `assigns`.

  A nested table links to its full view wherever the host's router mounts
  the table that is nested with `AshDataTable.Router.ash_data_table/3`, also from a
  table placed here.

  ## The line of the table's name

  Above its grid the table has one line: its name at one end, and at the
  other the create button, when the resource's `table` block names a
  `create_action` that the person may run, and the buttons of its table
  actions. The name is `label`.

  A table cannot know the outline of the page it is placed in, so by default
  the name is text that is no heading. `heading` says otherwise:

      <AshDataTable.table id="tasks" resource={MyApp.Tracker.Task} heading={2} scope={@current_scope} />

    * `true` (the default) - the name as text;
    * a number from 1 to 6 - the name as a heading of that level;
    * `false` - no name, for a page that names the table itself. The line
      then holds the buttons alone, and is left out when there are none.

  The element of the name has the id of the table followed by `-name`, for a
  page that labels a region by it (`aria-labelledby="tasks-name"`). A table
  whose read is refused outright renders nothing, this line included.

  ## Time zone

  Datetimes are shown, typed and filtered by in UTC, unless the page gives
  its time zone, usually the person's:

      <AshDataTable.table id="tasks" resource={MyApp.Tracker.Task} time_zone={@time_zone} />

  See the guide "Time zones". A zone other than UTC needs a time zone
  database (`tz` or `tzdata`) configured in the application; a name that is
  no zone, or a zone without a database, is an `ArgumentError` when the
  table is rendered.
  """
  attr :id, :string,
    default: nil,
    doc:
      "Unique on the page. It prefixes every DOM id of the table and names its URL parameters. Defaults to the last part of the resource's module name, underscored (`\"task\"`), and for a named table to that, `_` and the table's name (`\"task_board\"`)."

  attr :resource, :atom,
    required: true,
    doc: "An Ash resource that lists the extension `AshDataTable.Resource`."

  attr :table, :atom,
    default: nil,
    doc:
      "Which of the resource's tables is placed: the name of one of its named tables (a `table` of its `tables` block), such as `:compact`. Left out, or `:default`, it is the resource's default table, the one of its `table` block."

  attr :scope, :any, default: nil, doc: "An `Ash.Scope` carrying actor and tenant."
  attr :actor, :any, default: nil, doc: "The actor, used when no `scope` is given."
  attr :tenant, :any, default: nil, doc: "The tenant, used when no `scope` is given."

  attr :authorize?, :boolean,
    default: nil,
    doc:
      "Whether reads and saves are authorized. Defaults to the `authorize?` of the resource's domain (see `AshDataTable.Domain`), which is `true` unless the domain says otherwise."

  attr :live?, :boolean,
    default: nil,
    doc:
      "Live updates. `false` places the table without them: it does not follow what others change, and neither do the tables nested in its rows and its pickers. `true` says that it has to, and is an error for a resource that announces none. Left out, the table follows them where the resource's `table` block says `live? true`."

  attr :url, :string,
    default: nil,
    doc: "The current URL of the page. When given, sort, filters and page are kept in it."

  attr :label, :string,
    default: nil,
    doc:
      "The table's name: the accessible name of the grid, and the text of the line above it. Defaults to the humanised name of the resource."

  attr :heading, :any,
    default: true,
    doc:
      "How the table's name is shown on the line above it, with the create button and the buttons of the table actions at the other end. `true` shows it as text that is no heading, since a table cannot know the outline of the page it is in; a number from 1 to 6 makes it a heading of that level; `false` leaves it out, for a page that names the table itself."

  attr :time_zone, :string,
    default: nil,
    doc:
      "The time zone of the page, such as `\"Europe/Berlin\"`: a datetime is shown in it, what a person types into a datetime is a time there, and a filter on a datetime means times there. Nil is UTC. A zone other than UTC needs a time zone database (`config :elixir, :time_zone_database, …`). See the guide \"Time zones\"."

  attr :assigns, :map,
    default: %{},
    doc:
      "What a default of an asked argument is given when it is a function (`ask :currency, default: &MyApp.Defaults.currency/1`): the assigns of the page that it looks at, such as `%{current_user: @current_user}`. A mounted table gives such a function the assigns of its socket."

  attr :open, :string,
    default: nil,
    doc:
      "A button with this label in the actions cell of every row, first among its buttons, which tells the page `{:ash_data_table, id, {:row_opened, %{key: key}}}` (`AshDataTable.Event`), whatever `notify` says. Nothing is read or written: what \"open\" means is the page's."

  attr :notify, :any,
    default: nil,
    doc:
      "Which events the page is told, as `{:ash_data_table, id, {event, details}}` messages to its LiveView (`AshDataTable.Event`): `true` for all, or a list of their names. None without it."

  attr :context, :any,
    default: nil,
    doc:
      "What the page adds to the `context` of every call to Ash the table makes, its nested tables and pickers included: a map, or a function of `assigns` (and of which table asks, `%{table: id, path: path, resource: resource}`) that returns one. See \"What the page gives\" in `attach/4`."

  attr :private_arguments, :any,
    default: nil,
    doc:
      "Arguments the page gives the actions the table runs, by name: a map, or a function as for `context`. An action is given those it declares `public?: false`, and no others."

  attr :page_arguments, :any,
    default: nil,
    doc:
      "The values of the arguments an `action` of the table's block says the page fills (`page_argument`), by name: a map, or a function as for `context`."

  attr :before_action, :any,
    default: nil,
    doc:
      "Asked before every write, after the table's checks: a function of the `AshDataTable.Request` (and of `assigns`) that answers `:cont`, or `{:halt, message}`, which stops the write and says the message."

  attr :kit, :atom,
    default: nil,
    doc:
      "The module the table is drawn with (`AshDataTable.Kit`), and the tables it shows. " <>
        "Defaults to `config :ash_data_table, kit: …`, else `AshDataTable.Kit.Default`."

  attr :presentation, :list,
    default: [],
    doc:
      "Whether the action panel, the picker and the question open over the page (`:modal`) " <>
        "or in it (`:inline`): `[panel: :inline, picker: :inline, confirm: :inline]`, over " <>
        "what the kit says. See " <>
        "\"Modal or inline\" in `attach/4`."

  def table(assigns) do
    assigns = assign_new(assigns, :grid_label, fn -> assigns.label || label(assigns.resource) end)
    table = assigns.table || :default

    # (a resource without the extension is the table model's to refuse)
    if AshDataTable.Resource.Relating.table?(assigns.resource) and
         AshDataTable.Resource.Info.table(assigns.resource, table) == :error do
      raise ArgumentError,
            "<AshDataTable.table> was given `table={#{inspect(table)}}`, but " <>
              AshDataTable.Resource.Info.no_table(assigns.resource, table)
    end

    assigns =
      assign(assigns,
        table: table,
        id: assigns.id || AshDataTable.Routes.default_id(assigns.resource, table)
      )

    AshDataTable.Zone.check!(assigns.time_zone, "The `time_zone` of <AshDataTable.table>")

    if assigns.heading not in [true, false, 1, 2, 3, 4, 5, 6] do
      raise ArgumentError,
            "the `heading` of <AshDataTable.table> is `true`, `false` or a heading level from 1 to 6, " <>
              "got: #{inspect(assigns.heading)}"
    end

    page!(Map.take(assigns, @page), "<AshDataTable.table>")
    open!(assigns.open, "<AshDataTable.table>")
    notify!(assigns.notify, "<AshDataTable.table>")

    ~H"""
    <.live_component
      module={AshDataTable.Live.Embedded}
      id={@id}
      resource={@resource}
      table={@table}
      scope={@scope}
      actor={@actor}
      tenant={@tenant}
      authorize?={@authorize?}
      live?={@live?}
      url={@url}
      label={@grid_label}
      heading={@heading}
      mounted?={false}
      page_assigns={@assigns}
      time_zone={@time_zone}
      context={@context}
      private_arguments={@private_arguments}
      page_arguments={@page_arguments}
      before_action={@before_action}
      notify={@notify}
      open={@open}
      kit={@kit}
      presentation={presentation!(@presentation, "<AshDataTable.table>")}
    />
    """
  end

  @doc """
  Attaches a table of a resource to a LiveView, under the assign `name`,
  and reads it. Draw it with `attached/1`:

      def mount(_params, _session, socket) do
        {:ok, AshDataTable.attach(socket, :tasks, MyApp.Tracker.Task, scope: socket.assigns.current_scope)}
      end

      <AshDataTable.attached table={@tasks} streams={@streams} uploads={assigns[:uploads]} />

  The table is the one `table/1` places, without a live component: its
  events, async results and live updates reach it through hooks of the
  LiveView (`Phoenix.LiveView.attach_hook/4`), which halt what is the
  table's and let everything else through to the LiveView's own
  callbacks. The assign holds an `AshDataTable.Table`, which only the table
  changes.

  The options are the attributes of `table/1`: `id`, `table`, `scope`,
  `actor`, `tenant`, `authorize?`, `live?`, `label`, `heading`,
  `time_zone`, `kit` and `presentation`. Besides, `url: true` keeps sort, filters and page in the
  page's URL, under the table's id. That needs a LiveView mounted by the
  router and not inside another; it needs no `handle_params/3` of its own.
  Call `attach/4` in `mount/3`: the table then reads when LiveView first
  hands the LiveView its URL, before the first render. Attached later, it
  reads at the next patch, or at once, with the URL of the last one, where
  a table with `url: true` was attached to the LiveView before.
  A default of an asked argument that is a function is given the
  LiveView's assigns.

  ## "Open"

  `open: "Open"` puts a button with that label in the actions cell of
  every row, first among its buttons. It tells the LiveView
  `{:ash_data_table, id, {:row_opened, %{key: key}}}`, with the row's
  primary key, whatever `notify` says; what it opens is the page's (a
  `push_navigate/2`, a panel of its own). Not in nested tables.

  ## What the page hears

  `notify: true`, or a list of event names, sends the LiveView a message
  `{:ash_data_table, id, {event, details}}` for each event of the table,
  `id` being the table's: see `AshDataTable.Event`. Without it the table
  sends none, so a LiveView whose `handle_info/2` has no clause for them is
  safe.

  ## What the page gives

  Four options add server values to what the table does, for the table and
  every table it shows (nested tables, pickers' tables):

    * `context` - put into the `context` of every call to Ash the table
      makes (reads, writes, summaries), deep-merged with the scope's;
    * `private_arguments` - by name: an action is given those it declares
      `public?: false` (a read through `Ash.Query.set_argument/3`, a write
      as `private_arguments`), and no others;
    * `page_arguments` - by name, the values of the arguments an `action`
      of the table's block says the page fills (`page_argument`), which the
      action panel does not ask for;
    * `before_action` - asked before every write, after the table's own
      checks, with an `AshDataTable.Request`: `:cont` lets it go on,
      `{:halt, message}` stops it and says the message. Anything else
      raises.

  The first three are a map, or a function of the LiveView's assigns, or
  of them and which table asks (`%{table: id, path: path, resource:
  resource}`); `before_action` is a function of the request, or of it and
  the assigns. They are called in the LiveView's process before the reads
  and writes of a callback, once in it for each table that asks. A new
  value of theirs reads nothing again by itself.

  ## Modal or inline

  The action panel and the picker open as the table's kit says
  (`c:AshDataTable.Kit.presentation/1`): over the page, as a modal dialog
  (`AshDataTable.Kit.Default`), or in it, under the table. So does the
  question before an action. `presentation: [panel: :inline, picker:
  :inline, confirm: :inline]` says it for one table, and wins. Over the
  page, the page is inert while it is open, and Escape is Cancel. In the
  page, focus moves into it as it opens and back to what opened it as it
  goes, Escape inside it is Cancel, and nothing else is inert: Tab leaves
  it. What the panel shows and what the table checks are the same either
  way. A question in the page that is asked from a panel or a picker open
  over the page is shown inside it, where it can be answered. One question
  at a time: a question asked while
  another of the table is still open in the page gives the first up, as
  Cancel does.

  ## What the page draws itself

  `controlled: [:confirm, :panel, :picker]` (any of them) has the table
  hold what it would open, for the LiveView to draw:

    * `:confirm` - every question outside a panel: before a row action, a
      table action or an action on the selection, before a cell of a column
      with `confirm` is saved (what was typed is held by the table; the
      cell waits) and before the record chosen for a reference cell is
      saved. A panel's own question (a row action with inputs, the count
      of a selection's panel) is asked with the panel: by the table, or by
      the page with `:panel`;
    * `:panel` - every action panel: of a row action, a table action, a
      create, an action on the selection and a map cell, with its files
      (the page draws `live_file_input/1` of the upload `requests/1`
      names), its groups of fields and unions (`add_group_request/4`,
      `remove_group_request/4`) and the records chosen for a field (their
      keys in the params);
    * `:picker` - the picker of a reference cell, and of a field of a panel
      the table draws (`pick_request/4`).

  It is so for every table the table shows: its nested tables, at every
  depth, hold what they open as the table on the page does (a picker's
  table opens nothing). The table tells the LiveView `:requested` and
  `:request_ended` (with `notify`), `requests/1` says what is held, and the
  LiveView answers with `confirm_request/3`, `validate_request/4`,
  `submit_request/4`, `pick_request/4`, `add_group_request/4`,
  `remove_group_request/4` or `cancel_request/3`, by the request's `ref`;
  each goes the way the person's own answer would, with the table's
  checks, the veto and the record read again. One request at a time per
  table: a new one ends the one before, whose `ref` is answered no more. A
  nested table's request ends when the table closes (its row collapsed).

  A question is no safety check: it guards the person against a mistake,
  not the data against them. With `:confirm` the page shows the question,
  and the table's hook sends nothing that skips it; but the browser can
  still send an event as if it were confirmed (`table_run`, `bulk_run`,
  `picked` with `confirmed`, and with `:panel` `panel_submit`), and it
  runs as it would in the table's own mode, without the question. The
  table's checks, `before_action`, the record read again and Ash's
  policies still decide: what must not run is for them to refuse.

  Names and ids are unique on a page: two tables of one resource need an
  `id` each, and no id may begin with another's and `-row-` or `-pick-`
  (the ids of the tables a table shows). Attaching again under the same
  name tells the table again, which reads anew when who is asking has
  changed (`scope`, `actor`, `tenant`, `authorize?`); another resource,
  table or id under that name raises: detach it first.

  Every event of the table renders the LiveView again, so give the
  LiveView's components named assigns, not `assigns` whole or spread
  attributes, or they render again on every event too.

  The table takes these names on the LiveView: events named
  `ash_data_table:…`, async keys `{:ash_data_table, _, _}` and the message
  `{:ash_data_table_heard, _, _}`. Its hooks halt them; a LiveView keeps
  its own events, async keys and messages to other names.
  """
  @spec attach(Phoenix.LiveView.Socket.t(), atom, Ash.Resource.t(), keyword) ::
          Phoenix.LiveView.Socket.t()
  def attach(socket, name, resource, opts \\ []) when is_atom(name) and is_atom(resource),
    do: attach(socket, name, resource, opts, false)

  @doc false
  # The table of a router line (`AshDataTable.Live.Page`): attached as
  # `attach/4` attaches, and a page of its own, which a refused first read
  # turns into a 404 (`AshDataTable.NotFoundError`).
  @spec attach_mounted(Phoenix.LiveView.Socket.t(), atom, Ash.Resource.t(), keyword) ::
          Phoenix.LiveView.Socket.t()
  def attach_mounted(socket, name, resource, opts),
    do: attach(socket, name, resource, opts, true)

  defp attach(socket, name, resource, opts, mounted?) do
    opts =
      Keyword.validate!(
        opts,
        [:id, :table, :scope, :actor, :tenant, :authorize?, :live?, :label, :time_zone] ++
          [:notify, :open, :kit, :presentation] ++
          @page ++ [heading: true, url: false, controlled: []]
      )

    page!(Map.new(Keyword.take(opts, @page)), "AshDataTable.attach/4")
    notify!(opts[:notify], "AshDataTable.attach/4")

    table = opts[:table] || :default

    if AshDataTable.Resource.Relating.table?(resource) and
         AshDataTable.Resource.Info.table(resource, table) == :error do
      raise ArgumentError,
            "AshDataTable.attach/4 was given `table: #{inspect(table)}`, but " <>
              AshDataTable.Resource.Info.no_table(resource, table)
    end

    if opts[:heading] not in [true, false, 1, 2, 3, 4, 5, 6] do
      raise ArgumentError,
            "the `heading` of AshDataTable.attach/4 is `true`, `false` or a heading level " <>
              "from 1 to 6, got: #{inspect(opts[:heading])}"
    end

    given = %{
      id: opts[:id] || Routes.default_id(resource, table),
      resource: resource,
      table: table,
      scope: opts[:scope],
      actor: opts[:actor],
      tenant: opts[:tenant],
      authorize?: opts[:authorize?],
      live?: opts[:live?],
      url: nil,
      label: opts[:label] || label(resource),
      heading: opts[:heading],
      mounted?: mounted?,
      # a default of an asked argument is given the LiveView's assigns as
      # they are when it is called (`AshDataTable.Live.Core.page_assigns/1`)
      page_assigns: :socket,
      time_zone:
        AshDataTable.Zone.check!(opts[:time_zone], "The `time_zone` of AshDataTable.attach/4"),
      select: nil,
      context: opts[:context],
      private_arguments: opts[:private_arguments],
      page_arguments: opts[:page_arguments],
      before_action: opts[:before_action],
      notify: opts[:notify],
      open: open!(opts[:open], "AshDataTable.attach/4"),
      controlled: controlled!(opts[:controlled]),
      kit: kit!(opts[:kit], "AshDataTable.attach/4"),
      presentation: presentation!(opts[:presentation] || [], "AshDataTable.attach/4")
    }

    AshDataTable.Live.Hooks.attach(socket, name, given, opts[:url] == true)
  end

  # What the host draws itself (controlled mode): the questions, the action
  # panels and the picker of the table on the page.
  defp controlled!(kinds) do
    if not (is_list(kinds) and Enum.all?(kinds, &(&1 in [:confirm, :panel, :picker]))) do
      raise ArgumentError,
            "the `controlled` of AshDataTable.attach/4 is a list of `:confirm`, `:panel` and " <>
              "`:picker`, got: #{inspect(kinds, limit: 5)}"
    end

    Enum.uniq(kinds)
  end

  # The kit a table is drawn with: the one it is given, else the one of the
  # configuration, else the default. Checked as a kit unless it is `held`,
  # the kit the table has already: the tag is given its kit on every render,
  # and checks it only when another is named (`AshDataTable.Live.Embedded`).
  @doc false
  def kit!(given, where, held \\ nil) do
    {kit, where} =
      case {given, Application.get_env(:ash_data_table, :kit)} do
        {nil, nil} -> {AshDataTable.Kit.Default, where}
        {nil, configured} -> {configured, "`config :ash_data_table`"}
        {given, _configured} -> {given, where}
      end

    if kit == held or kit == AshDataTable.Kit.Default,
      do: kit,
      else: AshDataTable.Kit.check!(kit, where)
  end

  # What opens in the page, or over it, as the table is told: the panel, the
  # picker and the question, each `:modal` or `:inline`.
  defp presentation!(given, where) do
    if not (is_list(given) and
              Enum.all?(
                given,
                &match?(
                  {thing, how}
                  when thing in [:panel, :picker, :confirm] and how in [:modal, :inline],
                  &1
                )
              )) do
      raise ArgumentError,
            "the `presentation` of #{where} is a list of `panel:`, `picker:` and `confirm:`, " <>
              "each `:modal` or `:inline`, got: #{inspect(given, limit: 5)}"
    end

    given
  end

  defp open!(label, _where) when is_nil(label) or is_binary(label), do: label

  defp open!(other, where),
    do:
      raise(
        ArgumentError,
        "the `open` of #{where} is the label of its button, a string, got: #{inspect(other, limit: 5)}"
      )

  defp notify!(notify, _where) when notify in [nil, true], do: :ok

  defp notify!(names, where) when is_list(names) do
    case names -- AshDataTable.Event.names() do
      [] ->
        :ok

      unknown ->
        raise ArgumentError,
              "the `notify` of #{where} names #{inspect(unknown)}, which are no events of a " <>
                "table. They are: #{inspect(AshDataTable.Event.names())}"
    end
  end

  defp notify!(other, where),
    do:
      raise(
        ArgumentError,
        "the `notify` of #{where} is `true` or a list of events, got: #{inspect(other, limit: 5)}"
      )

  defp page!(given, where) do
    for {name, value} <- given, not is_nil(value) do
      fits? =
        case name do
          :before_action -> is_function(value, 1) or is_function(value, 2)
          _value -> is_map(value) or is_function(value, 1) or is_function(value, 2)
        end

      if not fits? do
        raise ArgumentError,
              "the `#{name}` of #{where} is " <>
                if(name == :before_action,
                  do: "a function of the request, or of the request and the page's assigns",
                  else:
                    "a map, or a function of the page's assigns, or of them and which table asks"
                ) <> ", got: #{inspect(value, limit: 5)}"
      end
    end
  end

  @doc """
  Takes the table under the assign `name` off the LiveView: every table it
  shows closes, with what it listens to, reads and uploads, and the assign
  becomes nil. A table of the same id can be attached again.
  """
  @spec detach(Phoenix.LiveView.Socket.t(), atom) :: Phoenix.LiveView.Socket.t()
  def detach(socket, name) when is_atom(name), do: AshDataTable.Live.Hooks.detach(socket, name)

  @doc """
  Reads the table under the assign `name` again, as it is, with its
  summaries: for a page whose values (`context` and the others) or whose
  records changed in a way the table cannot know of. What is open in it
  closes, as on any read.

  The commands (`refresh/2`, `put_state/3`, `clear_selection/2`,
  `selected_records/2`) are for a table attached with `attach/4`, and on
  the router page for its table, `:table`, in an `on_mount` hook; a name
  no table is attached under raises. None writes.
  """
  @spec refresh(Phoenix.LiveView.Socket.t(), atom) :: Phoenix.LiveView.Socket.t()
  def refresh(socket, name) when is_atom(name),
    do: command(socket, name, "AshDataTable.refresh/2", &AshDataTable.Live.Core.Reading.reread/1)

  @doc """
  Gives the table under `name` the state `params` say, as its URL
  parameters hold it under its id: `%{"sort" => "-title", "f" => %{...},
  "a" => %{...}, "page" => "2", "per" => "50"}`. What the table does not
  allow is dropped, as from a URL. With `url: true` the URL is patched, and
  the table reads it from there; else it reads at once.
  """
  @spec put_state(Phoenix.LiveView.Socket.t(), atom, map) :: Phoenix.LiveView.Socket.t()
  def put_state(socket, name, params) when is_atom(name) and is_map(params),
    do: command(socket, name, "AshDataTable.put_state/3", &Url.put_state(&1, params))

  @doc "Takes every row out of the selection of the table under `name`."
  @spec clear_selection(Phoenix.LiveView.Socket.t(), atom) :: Phoenix.LiveView.Socket.t()
  def clear_selection(socket, name) when is_atom(name),
    do:
      command(
        socket,
        name,
        "AshDataTable.clear_selection/2",
        &AshDataTable.Live.Core.Selection.put(&1, {:rows, []}, true)
      )

  @doc """
  The records selected in the table under `name`: the selected rows, or
  with "all that match" every record the filters match, each read again as
  the person through the table's read action, as a page is read, and with
  every `sensitive?` value masked (`%AshDataTable.Sensitive.Masked{}`). A
  key that names nothing the person may read is not among them. The
  selection itself is what the browser said, a claim, until read here.
  `{:error, message}` where the read fails.
  """
  @spec selected_records(Phoenix.LiveView.Socket.t(), atom) ::
          {:ok, [Ash.Resource.record()]} | {:error, String.t()}
  def selected_records(socket, name) when is_atom(name) do
    {:reply, result, _socket} =
      AshDataTable.Live.Hooks.command(
        socket,
        name,
        "AshDataTable.selected_records/2",
        fn socket ->
          {:reply, AshDataTable.Live.Core.Selection.records(socket), socket}
        end
      )

    result
  end

  @doc """
  The requests the tables of a table attached with `controlled:` hold for
  the page to draw: of the table on the page first, then of its nested
  tables, parents before their children; `[]` for none, and for nil. Each
  table holds one at a time. Every request has

    * `ref` - what the answer names (a new request has another);
    * `kind` - `:confirm`, `:panel` or `:picker`;
    * `table`, `path` - the id of the table that holds it, and the ids from
      the table on the page down to it (`[table]` for the table on the
      page);
    * `key` - the primary key of the row it is about, nil for none;
    * `question` - the question to ask before it runs, or nil;
    * `messages` - what its texts are made of, by name, as
      `AshDataTable.Messages` lists them.

  Besides, by kind:

    * `:confirm`, a question: `action`, and for a cell's question `column`
      and `value`, the value the cell is to be given (nil for a sensitive
      column, and for an action's question);
    * `:panel`, an action panel: `action` (nil for the panel of a filter
      for several values, which filters by what is sent and runs nothing),
      `column` (of a cell's panel and a filter's, else nil), `title`,
      `errors` (what is said that is about none of its
      fields) and `fields`, each with `name`, `label`, `type`, `editor`
      (its control), `required?`, `value` (what it holds as its form sends
      it; nil for a sensitive field), `values` (the choices of an enum,
      else nil), `errors`, `messages` and `chosen` (the records a field
      holds that are chosen, each with `key` and `label`); of a value made
      of fields its `fields`, of a union its `kinds`, each described the
      same way; of a file field `upload`, its upload among the LiveView's;
    * `:picker`, the picker of a reference cell or of a field of a panel:
      `column` (the column or field it chooses for), `resource` (what is
      chosen from), `several?`, `allow_none?` (whether no record may be
      chosen), `current` (the key or keys held now), `chosen` (the records
      a field holds, each with `key` and `label`, as far as the table knows
      them), `title` and `errors` (why a key chose nothing). Its `question`
      is the column's, which the page shows with its chooser unless it
      draws the questions too (`pick_request/4`).

  Texts are in words. The page answers with `confirm_request/3`,
  `validate_request/4`, `submit_request/4`, `pick_request/4`,
  `add_group_request/4`, `remove_group_request/4` and `cancel_request/3`,
  by `ref`, whichever table holds it; each goes as the person's own answer
  would, through the table's checks, the veto and the record read again,
  and does nothing for a `ref` no table holds. `:requested`
  (`AshDataTable.Event`) says that one is waiting, `:request_ended` that it
  is held no more: answered, given up, taken over by another, or gone with
  its table (a nested table whose row closed).
  """
  @spec requests(AshDataTable.Table.t() | nil) :: [map]
  def requests(nil), do: []

  def requests(%AshDataTable.Table{} = table),
    do: Enum.map(AshDataTable.Live.Core.Requests.projections(table), &in_words/1)

  # A request as the page shows it: its messages in words, and beside them.
  defp in_words(request) do
    said = &AshDataTable.Text.say/1
    message = &AshDataTable.Messages.of/1
    texts = Map.take(request, [:question, :title, :errors])

    request
    |> Map.merge(%{
      question: request.question && said.(request.question),
      messages:
        Map.new(texts, fn
          {:errors, errors} -> {:errors, Enum.map(errors, message)}
          {name, text} -> {name, message.(text)}
        end)
    })
    |> then(&if(texts[:title], do: %{&1 | title: said.(texts.title)}, else: &1))
    |> then(&if(texts[:errors], do: %{&1 | errors: Enum.map(texts.errors, said)}, else: &1))
    |> fields_in_words(said, message)
    |> chosen_in_words()
  end

  defp fields_in_words(%{fields: fields} = request, said, message) do
    %{
      request
      | fields:
          for field <- fields do
            %{
              field
              | label: said.(field.label),
                errors: Enum.map(field.errors, said),
                values:
                  field.values && for({value, label} <- field.values, do: {value, said.(label)})
            }
            |> Map.put(:messages, %{errors: Enum.map(field.errors, message)})
            |> chosen_in_words()
          end
    }
  end

  defp fields_in_words(request, _said, _message), do: request

  # What the records a picker's field holds are called, in words.
  defp chosen_in_words(%{chosen: chosen} = request) do
    %{
      request
      | chosen:
          for %{label: label} = record <- chosen do
            %{record | label: label_in_words(label)}
          end
    }
  end

  defp chosen_in_words(request), do: request

  defp label_in_words({column, value, zone}), do: AshDataTable.Format.format(column, value, zone)
  defp label_in_words(_none), do: nil

  @doc """
  Answers the question of request `ref` with Confirm: what it asked about
  runs as the person's Confirm would run it (the action, a cell's save,
  a reference cell's choice), through the table's checks, the veto and the
  record read again; refused there, it does not.
  """
  @spec confirm_request(Phoenix.LiveView.Socket.t(), atom, String.t()) ::
          Phoenix.LiveView.Socket.t()
  def confirm_request(socket, name, ref),
    do:
      answer(
        socket,
        name,
        ref,
        [:confirm],
        "AshDataTable.confirm_request/3",
        &AshDataTable.Live.Core.Requests.confirmed/2
      )

  @doc """
  What the page's form of request `ref` holds now, `params` as the panel's
  form sends them (by field name, as typed): the action says what it makes
  of it, as `requests/1` then shows. Nothing runs.
  """
  @spec validate_request(Phoenix.LiveView.Socket.t(), atom, String.t(), map) ::
          Phoenix.LiveView.Socket.t()
  def validate_request(socket, name, ref, params) when is_map(params),
    do:
      answer(socket, name, ref, [:panel], "AshDataTable.validate_request/4", fn socket,
                                                                                _request ->
        AshDataTable.Live.Core.Requests.panel(socket, {:panel_validate, params})
      end)

  @doc """
  Runs the action of request `ref` with `params`, as the panel's Run does:
  done, the request is gone; refused, it stays, with what the action said
  at its fields.
  """
  @spec submit_request(Phoenix.LiveView.Socket.t(), atom, String.t(), map) ::
          Phoenix.LiveView.Socket.t()
  def submit_request(socket, name, ref, params) when is_map(params),
    do:
      answer(socket, name, ref, [:panel], "AshDataTable.submit_request/4", fn socket, _request ->
        AshDataTable.Live.Core.Requests.panel(socket, {:panel_submit, params})
      end)

  @doc """
  Chooses for the picker of request `ref`: a primary key of the record to
  choose (a map of its fields by their names as atoms, or the value of a
  key of one field), a list of them where several are chosen, or nil for
  no record. A map without a field of the primary key raises
  `ArgumentError`. Each key is a claim: the record is read again as the
  person, through the picker's read action, and one that names nothing
  they may read there chooses nothing (the request says why in `errors`).

  A cell's choice then saves as the person's would, after the column's
  question. With `:confirm` that question is a request of its own. Without
  it, the request's `question` is the column's question, and the page must
  show it with its chooser: the choice is the person's answer to it, and
  saves at once. A field's choice is the field's.
  """
  @spec pick_request(Phoenix.LiveView.Socket.t(), atom, String.t(), term) ::
          Phoenix.LiveView.Socket.t()
  def pick_request(socket, name, ref, keys),
    do:
      answer(socket, name, ref, [:picker], "AshDataTable.pick_request/4", fn socket, _request ->
        AshDataTable.Live.Core.Requests.pick(socket, keys)
      end)

  @doc """
  Adds a value to a field made of groups of the panel of request `ref`: a
  value of fields where it has none, one more to a list of them, as the
  panel's own button does. `path` is the field's name, and the way to a
  value inside it, each name an atom as the request's fields have it, or a
  string: `[:place]`, `[:stops]`. Nothing runs; `requests/1` then shows
  the value, empty. A path that names no group of the panel changes
  nothing; one that is no list of names raises `ArgumentError`.
  """
  @spec add_group_request(Phoenix.LiveView.Socket.t(), atom, String.t(), [atom | String.t()]) ::
          Phoenix.LiveView.Socket.t()
  def add_group_request(socket, name, ref, path),
    do:
      answer(socket, name, ref, [:panel], "AshDataTable.add_group_request/4", fn socket,
                                                                                 _request ->
        AshDataTable.Live.Core.Requests.group(socket, :panel_add, path)
      end)

  @doc """
  Takes a value away from a field made of groups of the panel of request
  `ref`, as the panel's own button does: `path` is the field's name and the
  way to the value, `[:place]`, or a value of a list by the key it is
  sent under (as the field's `value` holds it), `[:stops, "1"]`. Nothing
  runs.
  """
  @spec remove_group_request(Phoenix.LiveView.Socket.t(), atom, String.t(), [atom | String.t()]) ::
          Phoenix.LiveView.Socket.t()
  def remove_group_request(socket, name, ref, path),
    do:
      answer(
        socket,
        name,
        ref,
        [:panel],
        "AshDataTable.remove_group_request/4",
        fn socket, _request ->
          AshDataTable.Live.Core.Requests.group(socket, :panel_remove, path)
        end
      )

  @doc "Gives request `ref` up, as Cancel does: nothing runs, and a cell is put back."
  @spec cancel_request(Phoenix.LiveView.Socket.t(), atom, String.t()) ::
          Phoenix.LiveView.Socket.t()
  def cancel_request(socket, name, ref),
    do:
      answer(
        socket,
        name,
        ref,
        :any,
        "AshDataTable.cancel_request/3",
        &AshDataTable.Live.Core.Requests.cancelled/2
      )

  defp answer(socket, name, ref, kinds, where, fun),
    do: command(socket, name, where, &AshDataTable.Live.Core.Requests.answer(&1, ref, kinds, fun))

  @doc """
  What a host may read of an `AshDataTable.Table`, as the assign holds it:

    * `id` - the table's id;
    * `state` - its sort, filters, arguments and page as its URL
      parameters (see `put_state/3`);
    * `count` - the rows shown, `total` - how many there are in all (nil
      where the action does not count);
    * `loading?` - whether it is reading;
    * `error` - what it says in place of its rows, or nil;
    * `selected` - the keys selected (primary keys as maps, claims), and
      `all?` - whether every record that matches is.

  Nil for nil (a table detached).
  """
  @spec status(AshDataTable.Table.t() | nil) :: map | nil
  def status(nil), do: nil

  def status(%AshDataTable.Table{entry: entry}) do
    %{
      id: entry.id,
      state: AshDataTable.State.to_params(entry.state, entry.model),
      count: entry.row_count,
      total: entry.page && entry.page.total,
      loading?: entry.busy? or entry.loading?,
      error: entry.error && AshDataTable.Text.say(entry.error),
      selected:
        for(
          row <- entry.selected,
          key = AshDataTable.Record.key(entry.resource, row),
          do: key
        ),
      all?: entry.all?
    }
  end

  defp command(socket, name, where, fun),
    do:
      AshDataTable.Live.Hooks.command(
        socket,
        name,
        where,
        &AshDataTable.Live.Core.command(&1, fun)
      )

  @doc """
  Draws a table that `attach/4` put on the socket, with its streams and
  uploads:

      <AshDataTable.attached table={@tasks} streams={@streams} uploads={assigns[:uploads]} />

  `uploads` is needed where an action of the table takes a file; LiveView
  has the assign only once an upload is allowed, hence `assigns[:uploads]`.
  The table draws nothing while the assign is nil (after `detach/2`).

  Place it where the table goes, but not inside an item of a stream of the
  page's own: the tables nested in its rows are drawn elsewhere and moved
  into their cells, and LiveView patches a stream item without them.
  """
  attr :table, :any,
    required: true,
    doc: "The `AshDataTable.Table` under the name the table was attached with, or nil."

  attr :streams, :any, required: true, doc: "The page's `@streams`."

  attr :uploads, :any,
    default: nil,
    doc: "The page's uploads, `assigns[:uploads]`: needed where an action takes a file."

  def attached(%{table: nil} = assigns) do
    ~H"""
    """
  end

  def attached(%{table: %{entry: %{gone?: true}}} = assigns) do
    ~H"""
    <div id={@table.entry.id} hidden></div>
    """
  end

  # The five hooks are JS files in the package, under `assets/js/`
  # (`assets/js/index.js`). LiveView writes a colocated hook into
  # `_build/ENV/phoenix-colocated/ash_data_table/`, beside a link named
  # `node_modules` that `mix.exs` points at this package's `assets`
  # (`node_modules_path`): `../node_modules/js/` is `assets/js/` of the
  # package, a path dependency's and a Hex package's alike, and the host
  # sets up nothing for it. Their names are this module's
  # (`AshDataTable.Grid`), which `AshDataTable.Attrs` writes.
  def attached(assigns) do
    ~H"""
    <AshDataTable.Live.Drawing.drawn table={@table} streams={@streams} uploads={@uploads} />
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Pagination">
      // In the package: assets/js/pagination.js
      import {Pagination} from "../node_modules/js/index.js"
      export default Pagination
    </script>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Panel">
      // In the package: assets/js/panel.js
      import {Panel} from "../node_modules/js/index.js"
      export default Panel
    </script>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Picker">
      // In the package: assets/js/picker.js
      import {Picker} from "../node_modules/js/index.js"
      export default Picker
    </script>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Sender">
      // In the package: assets/js/sender.js
      import {Sender} from "../node_modules/js/index.js"
      export default Sender
    </script>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Grid">
      // In the package: assets/js/grid/
      import {Grid} from "../node_modules/js/index.js"
      export default Grid
    </script>
    """
  end

  @doc """
  The name of a resource's table for people: its `plural_name` when the
  resource has one, else its short name, humanised. It is translated like a
  column label (see `AshDataTable.Gettext`).
  """
  @spec label(Ash.Resource.t()) :: String.t()
  def label(resource), do: resource |> AshDataTable.Model.label() |> AshDataTable.Text.label()
end
