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
        translate_error: {MyAppWeb.CoreComponents, :translate_error}

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

  `mix ash_data_table.install` sets all three for a new Phoenix application.
  """
  use Phoenix.Component

  alias AshDataTable.Live.Core.Files
  alias AshDataTable.Live.Core.Url
  alias AshDataTable.Live.Registry
  alias AshDataTable.Parts
  alias AshDataTable.Present
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

  # Rows to select with nothing to run on them, one at a time (`:single`) or
  # several (`:multi`): how the table is shown for a person to choose from.
  # Internal; the demo's pages for selection use it.
  attr :select, :atom, default: nil, values: [nil, :single, :multi], doc: false

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
      select={@select}
      context={@context}
      private_arguments={@private_arguments}
      page_arguments={@page_arguments}
      before_action={@before_action}
      notify={@notify}
      open={@open}
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
  `actor`, `tenant`, `authorize?`, `live?`, `label`, `heading` and
  `time_zone`. Besides, `url: true` keeps sort, filters and page in the
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
  the assigns. They are called in the LiveView's process before every read
  and write. A new value of theirs reads nothing again by itself.

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
  def attach(socket, name, resource, opts \\ []) when is_atom(name) and is_atom(resource) do
    opts =
      Keyword.validate!(
        opts,
        [:id, :table, :scope, :actor, :tenant, :authorize?, :live?, :label, :time_zone] ++
          [:notify, :open] ++
          @page ++ [heading: true, url: false, mounted?: false, controlled: []]
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
      mounted?: opts[:mounted?],
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
      controlled: controlled!(opts[:controlled], resource, table)
    }

    AshDataTable.Live.Hooks.attach(socket, name, given, opts[:url] == true)
  end

  # What the host draws itself (controlled mode): the questions before an
  # action and the action panels. A panel the host cannot be handed in this
  # version (a file, a group or a union, records chosen in the picker) is
  # refused here, for every action of the table that would open one.
  defp controlled!(kinds, resource, table) do
    if not (is_list(kinds) and Enum.all?(kinds, &(&1 in [:confirm, :panel]))) do
      raise ArgumentError,
            "the `controlled` of AshDataTable.attach/4 is a list of `:confirm` and `:panel`, " <>
              "got: #{inspect(kinds, limit: 5)}"
    end

    if :panel in kinds do
      model = AshDataTable.Model.build(resource, table: table)

      for action <- [model.create | model.actions ++ model.table_actions],
          action && action.panel?,
          input <- action.inputs,
          input.editor in [:file, :group, :groups, :union, :reference, :references] do
        raise ArgumentError,
              "AshDataTable.attach/4 was given `controlled: [:panel]`, and the panel of the " <>
                "action `#{action.name}` has the field `#{input.name}`, which a page cannot " <>
                "draw in this version: a file, a group of fields or a union, or records " <>
                "chosen in the picker. Leave `:panel` out, and the table draws its panels."
      end
    end

    Enum.uniq(kinds)
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
  The request a table attached with `controlled:` holds for the page to
  draw, or nil:

    * `ref` - what the answer names (a new request has another);
    * `kind` - `:confirm`, a question before an action, or `:panel`, the
      action panel of a row action, a table action, a create or an action
      on the selection;
    * `action`, `key` - the action and its row's primary key (nil for none);
    * `question` - the question to ask before it runs, or nil;
    * `title`, `errors` - of a panel: its title, and what the action said
      that is about none of its fields;
    * `fields` - of a panel, each with `name`, `label`, `type`, `required?`,
      `value` (what it holds as typed; nil for a sensitive field), `values`
      (the choices of an enum, else nil) and `errors`.

  Texts are in words. The page answers with `confirm_request/3`,
  `validate_request/4`, `submit_request/4` and `cancel_request/3`; each
  goes as the person's own answer would, through the table's checks, the
  veto and the record read again, and does nothing for another `ref`.
  `:requested` (`AshDataTable.Event`) says that one is waiting.
  """
  @spec request(AshDataTable.Table.t() | nil) :: map | nil
  def request(nil), do: nil

  def request(%AshDataTable.Table{} = table) do
    case AshDataTable.Live.Core.Requests.projection(table) do
      nil ->
        nil

      request ->
        said = &AshDataTable.Text.say/1

        %{
          request
          | question: request.question && said.(request.question),
            title: request.title && said.(request.title),
            errors: Enum.map(request.errors, said),
            fields:
              for field <- request.fields do
                %{
                  field
                  | label: said.(field.label),
                    errors: Enum.map(field.errors, said),
                    values:
                      field.values &&
                        for({value, label} <- field.values, do: {value, said.(label)})
                }
              end
        }
    end
  end

  @doc "Answers the question of request `ref` with Confirm: the action runs."
  @spec confirm_request(Phoenix.LiveView.Socket.t(), atom, String.t()) ::
          Phoenix.LiveView.Socket.t()
  def confirm_request(socket, name, ref),
    do:
      answer(
        socket,
        name,
        ref,
        :confirm,
        "AshDataTable.confirm_request/3",
        &AshDataTable.Live.Core.Requests.confirmed/2
      )

  @doc """
  What the page's form of request `ref` holds now, `params` as the panel's
  form sends them (by field name, as typed): the action says what it makes
  of it, as `request/1` then shows. Nothing runs.
  """
  @spec validate_request(Phoenix.LiveView.Socket.t(), atom, String.t(), map) ::
          Phoenix.LiveView.Socket.t()
  def validate_request(socket, name, ref, params) when is_map(params),
    do:
      answer(socket, name, ref, :panel, "AshDataTable.validate_request/4", fn socket, _request ->
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
      answer(socket, name, ref, :panel, "AshDataTable.submit_request/4", fn socket, _request ->
        AshDataTable.Live.Core.Requests.panel(socket, {:panel_submit, params})
      end)

  @doc "Gives request `ref` up, as Cancel does: nothing runs."
  @spec cancel_request(Phoenix.LiveView.Socket.t(), atom, String.t()) ::
          Phoenix.LiveView.Socket.t()
  def cancel_request(socket, name, ref) do
    command(socket, name, "AshDataTable.cancel_request/3", fn socket ->
      case AshDataTable.Live.Core.table(socket).entry.request do
        %{ref: ^ref, kind: :panel} -> AshDataTable.Live.Core.Requests.panel(socket, :panel_cancel)
        %{ref: ^ref} -> AshDataTable.Live.Core.put(socket, request: nil)
        _stale -> socket
      end
    end)
  end

  defp answer(socket, name, ref, kind, where, fun),
    do: command(socket, name, where, &AshDataTable.Live.Core.Requests.answer(&1, ref, kind, fun))

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

  # Whether the table's root element is drawn here. A live component draws
  # it itself (its root must be a static tag): `AshDataTable.Live.Embedded`.
  attr :root, :boolean, default: true, doc: false

  def attached(%{table: nil} = assigns) do
    ~H"""
    """
  end

  def attached(%{root: false, table: %{entry: %{gone?: true}}} = assigns) do
    ~H"""
    """
  end

  def attached(%{root: false} = assigns) do
    ~H"""
    <.drawn table={@table} streams={@streams} uploads={@uploads} />
    """
  end

  def attached(%{table: %{entry: %{gone?: true}}} = assigns) do
    ~H"""
    <div id={@table.entry.id} hidden></div>
    """
  end

  def attached(assigns) do
    ~H"""
    <div id={@table.entry.id} class="ash-data-table" data-read={not is_nil(@table.entry.page)}>
      <.drawn table={@table} streams={@streams} uploads={@uploads} />
    </div>
    """
  end

  # ---- the drawing ------------------------------------------------------
  #
  # The table itself: a grid whose rows live in a LiveView stream.
  #
  # The server keeps the table model, the state (sort, filters and position),
  # what the last read said about the pages, the primary keys of the rows of
  # the page and the edits that failed; it does not keep the records. A change
  # of sort, filter or page reads again and resets the stream.
  #
  # Editing a cell is the hook's until the value is saved: it opens the
  # column's editor in the cell and sends one `save` event with the row, the
  # column and the value as typed. The server reads the record again, runs the
  # column's update action and puts the row back into the stream. The value
  # of an array is the list of its values as typed; a cell says it as JSON
  # (`data-value`), which the hook reads and the server never does.
  #
  # Markup contract (spec sections 7.2 and 13):
  #
  #   * the `<table role="grid">` is the stream container; the header is a
  #     child with its own id and every row is one `<tbody>`;
  #   * the header has two rows, the column headers and the filter row, which
  #     are not part of the stream. The controls of the filter row belong to
  #     the form `ID-filters`, which sits outside the table;
  #   * ids are stable and built from names, never from positions:
  #     `ID-head-FIELD` for a header cell, `ID-filter-FIELD` for a filter cell
  #     (its controls end in `-operator`, `-value` and `-clear`; a range has
  #     `-value` and `-to`, and a filter for several values the button
  #     `-value`, the list `-values` and a box `-value-VALUE` for each),
  #     `ID-row-KEY` for a row's `<tbody>` and `ID-row-KEY-c-FIELD` for a cell;
  #   * the header cell of a column ends in the handle that changes the
  #     column's width, `ID-resize-FIELD` (`resizer/1`). The widths are the
  #     hook's and the server never hears of them;
  #   * above the grid, `ID-columns-button` opens the list `ID-columns`, which
  #     has a box per column that a person can hide, `ID-column-FIELD`, in
  #     its label `ID-column-FIELD-entry` (`columns/1`). Which columns are
  #     hidden is the hook's, and the server never hears of it: a hidden
  #     column is rendered as any other;
  #   * `aria-colindex` is computed through `colindex/2`, which counts the
  #     leading columns in when the table has them: the boxes that select a
  #     row, then the expanders; the actions column goes after the last
  #     data column;
  #   * a column's component renders inside the cell, never the cell: the
  #     `<td>`, its id and what it says of itself are the table's. The
  #     component is called for a value that is there and that the person
  #     may see, with that value, its text and the column, and never with
  #     the record (`cell/2`). Its editor is the content of the column's
  #     editor `<template>`, which then says `data-editor="component"` and
  #     when it saves (`data-commit`); the control in it is the element
  #     marked `data-control`;
  #   * the question of a row action is on its button, and on its panel, as
  #     `data-question`. Never as `data-confirm` on anything a person can
  #     click: `phoenix_html`, which a Phoenix application loads, asks the
  #     browser's own `confirm` for every click inside such an element.
  #
  # ## What the tests rely on besides
  #
  # The test helpers (`DemoWeb.TablePage` in `demo/test/support/table_page.ex`
  # and `Table` in `demo/e2e/support/table.ts`) find the parts below by these
  # ids and attributes. They are part of the contract as much as those above:
  # a change of one is a change of the contract, and of the helpers. The
  # sections that follow say what each part is for.
  #
  #   * the root element `ID` (`data-read` once the table has read); in it
  #     the line of the table's name, `ID-header`, with the name `ID-name`,
  #     the create button `ID-create` and the table actions `ID-do-ACTION`
  #     (`data-table-action`);
  #   * `ID-grid`, the grid's hook's element (`data-ash-data-table`, `data-lead`,
  #     `data-select`, `data-choose`, `data-chosen-rows`); in it `ID-table`,
  #     the `<table role="grid">`, which says `aria-busy` while it reads, and
  #     while a table action or an action on the selected rows runs; its
  #     header `ID-head` with the rows `ID-head-row` and `ID-filter-row`, and
  #     `ID-foot`;
  #   * a row: its `<tr>` `ID-row-KEY-r`; the cell with the box
  #     `ID-row-KEY-s` (`data-selector`, the `<input>` its only child); the
  #     expander `ID-row-KEY-e` (`data-expander`, a `button[aria-expanded]`);
  #     the actions cell `ID-row-KEY-a` (`data-actions`) whose buttons are its
  #     children, `ID-row-KEY-a-ACTION` (`data-action`, `data-question`,
  #     `data-destructive`). Its `<tbody>` says `data-key` where rows are
  #     selected and `data-current` in a table to choose from;
  #   * the detail of a row says `data-detail` and `data-row` (the key of its
  #     row); the cell of a line `data-line` (the relationship), with
  #     `ID-row-KEY-l-NAME-c > div > button`s: the one that opens it
  #     (`aria-expanded`), then `ID-row-KEY-l-NAME-create` and the nested
  #     table's actions `ID-row-KEY-l-NAME-do-ACTION`; the cell of a nested
  #     table `data-nested`;
  #   * a failed cell, and a failed actions cell: `aria-invalid` and
  #     `aria-describedby`, which names the message, a child of the cell
  #     (`[popover]`); what the cell shows are its other children;
  #   * a sensitive cell: `button[data-reveal]`, `[data-mask]`,
  #     `[data-masked]`, `[data-secret]`;
  #   * the editor of a column: `template` `ID-editor-FIELD` (`data-editor`,
  #     `data-confirm`), and in the editor of an array `[data-list]` with the
  #     row of a value in a `template` of its own (`button[data-remove]`) and
  #     `button[data-add]`;
  #   * around the rows: `ID-status` (the live region), `ID-error`,
  #     `ID-loading`, `ID-empty`, `ID-fill`, `ID-notice`, `ID-read-again`,
  #     `ID-result` (`[data-summary]`, `[data-failure]`), the question dialog
  #     `ID-dialog` (`ID-dialog-question`), `ID-related-parent`;
  #   * the pages: `ID-pagination`, `ID-range`, `ID-pager`, `ID-previous`,
  #     `ID-next`, `ID-page-N`; the "Rows per page" menu `ID-page-size` in
  #     the form `ID-page-size-form`, which sends it as `size`;
  #   * the filter row: `ID-clear-filters`, `ID-select-head`,
  #     `ID-select-filter`, `ID-expander-head`, `ID-expander-filter`,
  #     `ID-actions-head`, `ID-actions-filter`; a filter's controls are
  #     `select[id$='-operator']` and `select[id$='-value']`;
  #   * the "Columns" list: its button says `data-columns-button`, a hidden
  #     column's entry `data-flag`, and `ID-columns-status` is its live
  #     region;
  #   * the argument line: `form[data-arguments]`, each argument a child
  #     `[data-argument=NAME]` with its `[data-label]` and `[data-error]`s;
  #   * the line of the selection: `ID-selection` (`data-more`,
  #     `data-selected`, `data-all`), each action's button `data-bulk`;
  #   * the action panel `ID-panel` (`data-question`): `ID-panel-title`,
  #     `ID-panel-form`, `ID-panel-errors`, `ID-panel-cancel`,
  #     `ID-panel-submit`. A field says its name in `data-field`; its label
  #     ends in `-label` and holds the word "required" as `.sr-only` where
  #     it is required; its messages are `[data-error]` in a `div` that ends
  #     in `-error`. A value made of fields says `data-group` (its add and
  #     remove buttons `data-add-group`, `data-remove-group`), an array of them
  #     `data-groups` with `data-group-item`s, a union `data-union`, an array
  #     `[data-list] > [data-item]`, a field emptied on purpose
  #     `data-cleared` (its button `ID-panel-f-NAME-clear`, `data-clear-field`).
  #     A field of a related record holds its key in `input[data-key]` and
  #     says what it is called in `ID-panel-f-NAME-chosen` (`data-chosen`),
  #     beside `ID-panel-f-NAME-choose`; one of several records says
  #     `data-references`, with a button per record `ID-panel-f-NAME-r-N`;
  #   * the picker `ID-picker` (`data-question`): `ID-picker-title`,
  #     `ID-picker-error`, the table to choose from `ID-pick-NAME` a direct
  #     child, and the buttons in its last child.
  #
  # ## Events
  #
  # Every event goes to the table it is of: the element it is sent from
  # says so (`phx-target`), and its name too: `ash_data_table:ID:event`,
  # where `ID` is the table's id and `event` one of the names below
  # (target.md Q4). The hooks send theirs with `pushEventTo` on their own
  # element, named so by their transport (`assets/js/transport/`), which
  # takes the id from the element's; the others are sent by the markup
  # (`AshDataTable.Parts.Common.event/2`). An event named for another table,
  # or not named so, is answered as one of another shape. A key of a row is
  # the key in the row's DOM id; a column, action, relationship or input is
  # named as text. The answer, where there is one, goes to the hook alone.
  # Each event is parsed once, as it arrives (`AshDataTable.Intent`): a
  # payload of another shape than the one listed here is answered as one
  # that names nothing the table has (`{ok: false}`, `{open: false}`, `{}`,
  # or no answer).
  #
  # From the grid's hook, on `ID-grid`:
  #
  #   * `expand` `{row}`: answers `{open}`, whether the row is expanded now;
  #   * `toggle` `{row, relationship}`: no answer;
  #   * `save` `{row, column, value}` (`value` a list for an array) and
  #     `clear` `{row, column}`: `{ok: true}`, `{ok: false}`, or
  #     `{ok: false, error}` where the record is gone;
  #   * `discard` `{row, column}`, `dismiss` `{row}`, `left` `{row}`: no
  #     answer;
  #   * `reveal` `{row, column}`: `{ok: true, value}`, `{ok: false}` or
  #     `{ok: false, error}`;
  #   * `act` `{row, action}`: `{ok: true}`, `{ok: true, removed: true}`,
  #     `{ok: true, panel: true}`, `{ok: false}` or `{ok: false, error}`;
  #   * `pick` and `edit` `{row, column}`: `{ok: true}`, `{ok: false}` or
  #     `{ok: false, error}`;
  #   * `select` `{rows}` or `{all: true}`, on every change of what is
  #     selected: no answer;
  #   * `bulk` `{action}`, on what is selected: `{panel: true}`, `{ask}`
  #     (the question to ask first) or `{ok: false}`; `bulk_run`, the
  #     same, once the person has confirmed: no answer;
  #   * `bulk_seen` `{}`, `table_run` `{action}`: no answer.
  #
  # From the panel's hook, on `ID-panel`: `panel_add` and `panel_remove`
  # `{path}`, `panel_unpick` `{input, key}` and `panel_clear` `{input}`,
  # each answered with `{focus}` (the id that gets the focus) or `{}`;
  # `panel_cancel` `{}`, no answer.
  #
  # From the picker's hook, on `ID-picker`: `picked` `{row, confirmed,
  # arguments}` (`row` nil for "None"), or `{rows, arguments}` where several
  # are chosen, `arguments` what the argument line of its table holds, as
  # a query string, or nil: answered `{ok: true}`, `{ok: false}`,
  # `{ok: false, error}` or `{ask}` (the column's question, after which it
  # is sent again with `confirmed: true`); `picker_cancel` `{}`, no answer.
  # The pagination's hook sends nothing.
  #
  # From the markup: `sort` `{column}` (a header's button), `filter` (the
  # form `ID-filters`), `clear_filter` `{column}`, `clear_filters`,
  # `arguments` (the form `ID-arguments`), `argument_add` `{argument}`,
  # `argument_remove` `{argument, at}`, `page` `{to}` (a number, `previous`
  # or `next`), `page_size` `{size}`, `create`, `table_act` `{action}`,
  # `pick_input` `{input}`, `panel_validate` and `panel_submit` (the form
  # `ID-panel-form`), `read_again`.
  #
  # The server tells a grid's hook with `push_event`, each with `table`,
  # the id of the table it is for (every hook of the page hears it, and
  # only that table's acts): `ash_data_table:focus` `{table, cell}` (the id to
  # focus), `ash_data_table:ask` `{table, action, question}` (answered with
  # `table_run`), `ash_data_table:select` `{table, all, rows}` (what is
  # selected, where the server decided it: each row `[key, named]`, as the
  # hook keeps it), `ash_data_table:leaving` `{table, row}` (answered with
  # `left`). A grid's hook tells whoever listens with DOM
  # events on its grid, `ash_data_table:selection` and, where it is told to
  # choose, `ash_data_table:choose`, each with what `selected()` gives:
  # `{table, mode, all, rows}`.
  #
  # ## The argument line
  #
  # A table whose read action takes arguments from a person, or whose
  # columns ask for arguments of their calculations, has a line of inputs
  # above its grid: the form `ID-arguments`, with one control per argument
  # (`ID-arg-NAME` for an argument of the read action, `ID-arg-COLUMN-NAME`
  # for one a column asks for), each with its label, and under it what Ash
  # says of a value it refuses (`…-error`). The controls are ordinary tab
  # stops, in a nested table too.
  #
  # The form sends everything it holds when a control changes or loses the
  # focus, and on Enter, as the filter row does. What a person chose is part
  # of the state (`AshDataTable.State`), and so lives where the sort and the
  # filters live. A value Ash refuses is not taken into the state: it stays
  # in its input, marked, with Ash's message (`refused`), and the rows stay
  # as they are. While an argument the read action requires is empty the
  # action is not run: `ID-fill` says which argument to fill in, in place of
  # the rows.
  #
  # The values of an array that is given value by value are rows the server
  # renders, with a button each that takes the value away and one that adds
  # a row (`argument_remove`, `argument_add`); what the rows hold, the empty
  # ones among them, is kept beside the state (`lines`).
  #
  # ## Selecting rows
  #
  # A table whose rows can be selected has a first column of boxes, before
  # the expanders: `ID-row-KEY-s` in a row, `ID-select-head` in the header
  # with the box that stands for the rows of the page, `ID-select-filter` in
  # the filter row. Rows can be selected where the table has a row action
  # that runs on several rows for this person, and where it is told so
  # (`select`: `:multi` or `:single`), which is how a table is shown for a
  # person to choose from, with nothing to run.
  #
  # Which rows are selected the server holds (`AshDataTable.Live.Core.Selection`),
  # and the hook paints: it is told every change a person makes (`select`),
  # and decides when a selection ends (the filters, the arguments or what
  # the table is limited to changed) or narrows (a row went, a run left
  # the rows it did not run on), which it tells the hook
  # (`ash_data_table:select`). The hook says of each row whether it is
  # selected (`aria-selected`, and the box), tells whoever listens
  # (`ash_data_table:selection` on `ID-grid`, with what `selected()` of the hook
  # gives), and names a row to the server by its primary key: the key in the
  # row's id, or what the row says in `data-key`.
  #
  # Above the grid, `ID-selection` holds the number of selected rows
  # (`ID-selected`, a live region the hook fills) and, in
  # `ID-selection-controls`, `ID-select-all`, `ID-clear-selection` and a
  # button per action on the selected rows (`ID-bulk-ACTION`). Such an
  # action is run by `AshDataTable.Bulk`, beside the process; what it came to
  # is in `ID-result`, and the rows it did not run on stay selected
  # (`ash_data_table:select`).
  #
  # ## Table actions
  #
  # A table action is a button: `ID-do-ACTION`, on the line of the table's
  # name beside the create button, and for a nested table on the line that
  # names it, in the table around it (`…-l-NAME-do-ACTION`). Either sends
  # `table_act` to the table the action is of. An action with inputs opens
  # the action panel; one with a question is asked in the table's dialog,
  # which the hook opens when the server tells it to (`ash_data_table:ask`), and
  # runs when the hook answers `table_run`; any other runs at once.
  #
  # A generic action returns no row. What it came to is said where the
  # outcome of an action on the selected rows is said, in `ID-result`, and
  # read out; then the table reads again. A generic action that is a row
  # action has its button in the actions cell, and is used as the others
  # there are (`act`).
  #
  # ## Choosing a related record
  #
  # A reference cell is edited in the picker: a second panel, `ID-picker`,
  # which holds the table of the destination resource (an entry of this
  # component, drawn in the dialog, under the id `ID-pick-NAME`, told
  # `select: :single` and `choose`) and three buttons, `ID-picker-cancel`, `ID-picker-none` and
  # `ID-picker-choose`. The hook asks for it with one `pick` event, with the
  # row and the column; a field of the action panel that holds such a key
  # asks with its button (`pick_input`). The person selects one row there,
  # which is the hook's as every selection is, and the picker's own hook
  # sends one `picked` event with the row as the grid's hook names it, or
  # nil for no record.
  #
  # What the server keeps is which cell, or which field, the picker is open
  # for (`picker`), as it keeps the panel's action; a new read closes it.
  # The row it is told is a claim: the record is read by it, as the person,
  # before anything is saved (`AshDataTable.Pick`). For a cell the column's
  # action then runs with the foreign key as its one input, and the row is
  # put back; for a field the key goes into the panel's form, with what the
  # record is called beside it.
  #
  # A table that is told `choose` is one to choose from: nothing in it is
  # edited, run, created or expanded (`AshDataTable.Model.build/2`), its grid
  # says so (`data-choose`), and the row of the record that is chosen now
  # says `data-current`, which the hook selects until the person selects
  # another.
  #
  # A field of the action panel that holds the keys of several related
  # records (an argument that the action hands to a relationship) lists
  # what the records are called, each with a button that takes it out again
  # (`ID-panel-f-NAME-r-N`, which the panel's hook sends as `panel_unpick`),
  # and its "Choose" opens the picker for several: the table is told
  # `select: :multi`, its grid says which rows are selected as it opens
  # (`data-chosen-rows`: those of the records the field holds, on whatever
  # page), "Choose" is always to be used, and `picked` carries `rows`, every
  # row that is selected. Which records the field holds is the server's to
  # keep (`refs` of the panel): the rows are rendered from it.
  #
  # ## Map cells
  #
  # A cell whose value is made of fields (an embedded resource, a map, or an
  # array of either) has no editor in the cell either. The hook asks for it
  # with one `edit` event, with the row and the column, and the server
  # opens the action panel for it: the record is read, as the person, and
  # the panel's one input is the column's attribute, shown as a group of
  # the value's fields (`group/1`), or as one group per value of an array
  # (`groups/1`). "Save" runs the column's update action with that one
  # input (`AshDataTable.Edit.put/7`); what the action says about a field is
  # shown at that field, and the panel stays open.
  #
  # What such a field holds is the server's to render, unlike the rows of an
  # array of plain values: a group shows the action's messages at its
  # fields. The panel keeps what the form sent for it last (`groups`), a
  # group is added and taken away by an event (`panel_add`, `panel_remove`,
  # with the way to it), and the values of an array are sent under numbers
  # of their own, which say their order and not their places: nothing in
  # the page changes its name when a value is taken away.
  #
  # ## Unions
  #
  # A cell of a union has no editor in the cell either: the hook asks for
  # the side panel as it does for a map cell (`edit`), and the panel's one
  # input is the column's attribute, shown as a union's field (`union/1`):
  # a group with the choice of the kind (`…-kind`) and, under it, the value
  # of the kind that is chosen: one field of the panel (`…-value`), or the
  # fields of a kind made of fields (`…-f-NAME`). Choosing a kind is a
  # change of the panel's form like any other, and the server renders that
  # kind's fields. The field sends the kind (`_union_type`), the value
  # (`_union_value`), and which kind that value was given for (`_of`), by
  # which a value that was typed for another kind is told and left out
  # (`AshDataTable.Act.kind/2`). What such a field holds is kept with the
  # panel's groups.
  #
  # ## Files
  #
  # An argument that takes a file is a field of the action panel that is an
  # upload of LiveView's (`live_file_input/1`), allowed by this component
  # when a panel with such a field opens, under the name `ID-file-ARGUMENT`.
  # The input's id is LiveView's; its label points at it. The file is sent
  # by LiveView's client when the panel's form is submitted, and the action
  # runs while LiveView holds it (see "Files" among the functions below).
  #
  # ## Sensitive columns
  #
  # A cell of a column whose field is declared `sensitive?` shows a mask,
  # the same for every value, and a button (`data-reveal`); an empty one is
  # empty, as any cell is. The value is not in the page, and not in what the
  # server keeps of a row: a row goes into the stream as
  # `AshDataTable.Present.row/3` gives it, which replaces the record's
  # sensitive values first (`AshDataTable.Sensitive.scrub/2`) and gives a
  # sensitive cell no value at all.
  #
  # The hook asks for the value of one cell with one `reveal` event, with
  # the row and the column, and the server answers with the value as text:
  # the record is read again, as the person, and a value Ash hides from them
  # is not given. The hook puts it into the cell (`data-secret`, a live
  # region) and takes it out again when focus leaves the cell; a patch of
  # the row takes it out by itself. Nothing of it is ever rendered by the
  # server.
  #
  # The editor of such a column is a password input, and starts empty: what
  # the hook sends for it is what was typed, and an editor nothing was typed
  # into saves nothing. A save that failed leaves the cell with its mask and
  # the action's message; what was typed is not kept.
  #
  # ## Nested tables
  #
  # A table whose rows offer relationships, to this person and at this depth,
  # has a column of expanders, the first unless its rows can be selected.
  # The stream then holds two items per record, both `<tbody>`s: the row (`ID-row-KEY`) and, right after it, its
  # detail (`ID-row-KEY-x`), which is empty and hidden until the row is
  # expanded. Expanded, the detail holds one line per relationship
  # (`ID-row-KEY-l-NAME`, with its cell `…-c` and its button `…-b`) and, under
  # an open line, a row (`ID-row-KEY-n-NAME`) whose one cell (`…-c`) spans the
  # table and holds the nested table, under the id `ID-row-KEY-t-NAME`, which
  # prefixes every id in it.
  #
  # Every table the component shows is an entry of its one
  # `AshDataTable.Table` (`AshDataTable.Live.Registry`), with a stream of its
  # own: the table on the page, its nested tables at every depth, the tables
  # of open pickers. A nested table is drawn after the table on the page, at
  # the top of the template, and the browser moves it into its cell
  # (`<.portal>`; its content says which cell it goes into,
  # `data-ash-data-table-portal`, for `AshDataTable.Test.page/1`). Its events name it (`ash_data_table:ID:event`) and reach this
  # component, which finds it by that id. What its row renders decides
  # whether it stays: after every update, event and answer the open lines
  # of the rows on the page are compared with the tables shown, and a table
  # no longer reached is closed with everything under it, its listener,
  # tasks, uploads and stream, in the render that takes its cell away
  # (`AshDataTable.Live.Core.Nesting.reconcile/1`). When who is asking
  # changes, what is open under the rows closes at once.
  #
  # The detail is an item of its own so that opening and closing never needs
  # the record again, which the server does not keep: a toggle puts the
  # detail back into the stream and leaves the row alone, and a save puts the
  # row back and leaves the detail alone. What the server keeps for it is
  # which rows are expanded and which of their lines are open (`open`). A
  # new read forgets both, as it forgets the failed edits.
  #
  # A nested table is given the relationship it is reached through (`via`)
  # and the primary key of the row it belongs to (`parent_key`); it reads
  # through `AshDataTable.Query.read_related/4`, when it is opened and whenever
  # its own sort, filters or page change. Its state is never in the URL.
  # `depth` counts from the table on the page, which is at 0, and
  # `depth_limit` is that table's `max_depth`.
  #
  # ## Live updates
  #
  # A table whose resource announces its changes (`live? true`) follows
  # them, unless it is told not to. It listens through a process of its
  # own (`AshDataTable.Listener`), which hands it what was announced in batches
  # (`update/2`, with `live`): the primary keys of records that were
  # created, updated or destroyed, and nothing else of them
  # (`AshDataTable.Resource.Notifier`). Nothing of an announcement is shown. Each key is
  # read again as the person, through the table's read action
  # (`follow/1`): a row of the page is put back as that read returns it, or
  # taken away when it returns nothing; a record that is no row of the page
  # is never put into it.
  #
  # For those the table has a notice on the line above the grid,
  # `ID-notice`, with the button `ID-read-again` (`read_again`), which is
  # also said through the live region. It is only there when at least one
  # of the records is one this person would be shown, and goes with the
  # next read.
  #
  # Nothing a person is working on changes under them. A row is left as it
  # is while the action panel or the picker is open for it, or a panel or a
  # picker is open in a table under it, at whatever depth: the tables shown
  # say which (`path`), and the rows held back are looked at again after
  # every update, event and answer, in the render that closes what held
  # them. A cell that is being edited is left alone by
  # the hook, as by every patch of its row (`beforeUpdate`): it keeps what
  # was typed, and shows what the server sent once the editor is gone
  # without a save. The server is not told which cell is edited, here as
  # elsewhere.
  #
  # A row whose record the read does not return is not taken away at once,
  # as an editor may be open in it. The hook is asked about that one row
  # (`ash_data_table:leaving`), and answers `left`: at once, or when the editor
  # in the row is gone without a save. A save from it is answered as any
  # save into a record that is gone, and the row then stays.
  #
  # The tables a table renders, nested in a row or in a picker, listen for
  # themselves, each with a listener of its own, whose batches name it
  # (`{:heard, id, batch}`); closing a table stops its listener.
  #
  # ## Scrolling sideways
  #
  # Every table scrolls sideways in an area of its own, its grid `ID-grid`:
  # the table on a page, every nested table, and the table of a picker. The
  # cell of a nested table holds an element that stays at the left edge of
  # the area around it and is as wide as what is seen of that area
  # (`--ash-data-table-view`, which each grid's hook writes on its grid), so a
  # nested table never scrolls with the table around it; so does what a
  # relationship line holds.
  #
  # `ID-scrollbar` is the grid's scrollbar once more: the hook shows it at
  # the bottom edge of the window while the grid's own is below it. It is
  # for the pointer alone (`aria-hidden`, no tab stop).
  #
  # In a table that says `sticky_label? true` the header of the label column
  # says so (`data-label`), and the hook keeps that column in view, with the
  # cells that select and expand a row before it (see "scrolling sideways"
  # in the hook). A table that does not say it has no such header, and
  # nothing of it stays. The server knows nothing of where a table is
  # scrolled to.
  #
  # ## Long text
  #
  # A cell is one line and cuts off what does not fit. The cells of a column
  # that says `max_lines` say how many lines they show (`data-lines`, 2 to
  # 10), and hold their text in a paragraph, their only `<p>`, which wraps,
  # keeps the line breaks of the value and is cut off after that many lines.
  # An empty cell holds nothing, and the cell of a field the person may not
  # see holds what it holds in every column.
  #
  # `ID-whole` is a popover the hook fills with the whole text of a cell
  # that cuts some off, and shows under that cell while it has the focus or
  # the pointer (see "the whole text of a cell" in the hook). The server
  # renders it empty and never writes to it; it is for the eye alone
  # (`aria-hidden`). A sensitive cell has no such text, masked or shown.
  #
  # ## The full view
  #
  # The last row of a nested table's grid holds a link to the page the host's
  # router mounts the destination's table at, when it mounts one
  # (`ID-full-view` in the cell `ID-view`). That page shows the same records:
  # its table's parameter `of` names the row and the relationship
  # (`AshDataTable.Related`).
  #
  # A table with its state in the URL reads that parameter. Limited by it,
  # the table is what a nested table is, read the same way, with `via` and
  # `parent_key` taken from the URL; only that it is not `nested?` in
  # another, and so looks and behaves as a table of its own. Above its grid
  # it says what it shows (`ID-related`: the heading `ID-related-heading`
  # and the control `ID-related-clear`, which takes the limit away).
  #
  # ## Footer summaries
  #
  # A table one of whose columns has a `summary` has one more row after its
  # last record: `ID-summaries`, the first row of the `<tfoot>` `ID-foot`
  # (which a nested table also keeps its pages and its link to the full view
  # in, after it). A table without a summary has no such row, and a table of
  # its own then has no `<tfoot>` at all.
  #
  # The row is a row of the grid like any other: a `gridcell` under every
  # column, with the column's `aria-colindex`, so that a number stands under
  # its column, is hidden and resized with it by the hook's rules, and is
  # reached with the arrow keys. The cell under a column is
  # `ID-summary-FIELD`; under the leading and the actions columns the cells
  # `ID-summaries-select`, `ID-summaries-expander` and `ID-summaries-actions`
  # are empty, as is the cell of a column without a summary. A cell with a
  # summary says its kind in `data-summary`, and holds the kind's name
  # (`[data-summary-kind]`) and after it the number
  # (`[data-summary-value]`), or a dash that is read out as "Not available"
  # (`[data-summary-unavailable]`). The row is the
  # last of all rows: `aria-rowcount` counts it, and its `aria-rowindex` is
  # that count. Arrow Down from the last record reaches it; Page Down and
  # Ctrl+End end at the last record.
  #
  # The numbers are over every record the table matches, not over the page
  # (`AshDataTable.Query.summaries/4`, which also says what is never shown: a
  # number over a field the person sees on some records only). They are
  # asked for beside the read of the rows (a task of its own, under the key
  # `{:ash_data_table, id, {:summary, token}}`), which never waits for them: with every read but one that only sorts, after
  # everything the table writes, and once per batch of live updates
  # (`summarise/1`, from `tidy/1`). Until the answer is there the cells keep
  # what they showed and are `aria-busy`. An answer that fails puts the dash
  # into every cell and is logged; the rows are not touched.

  # The table on the page, and after it, inside its root, the portals of
  # the tables shown in its rows and in theirs: each drawn here, at the top
  # of the template, where it follows its entry, and moved by the browser
  # into the cell of the row it belongs to (`<.portal>`), parents before
  # their children (`AshDataTable.Live.Registry.portals/1`). The two
  # elements around a nested table pin it to the left edge of the scroll
  # area around it and make it as wide as that area: the portal itself
  # takes no part in the layout (`display: contents`). The outer one names
  # the cell (`data-ash-data-table-portal`): what a test reads the page
  # by, as the markup LiveView makes of a portal is LiveView's own.
  attr :table, :any, required: true
  attr :streams, :any, required: true
  attr :uploads, :any, required: true

  defp drawn(assigns) do
    ~H"""
    <.body
      entry={@table.entry}
      options={@table.options}
      time_zone={@table.caller.time_zone}
      rows={rows(@streams, @table.entry)}
      chooser={chooser(@table, @table.entry)}
      chooser_rows={rows(@streams, chooser(@table, @table.entry))}
      myself={@table.options.target}
      uploads={@uploads}
      router={@table.options.router}
    />
    <.portal
      :for={{entry, rows} <- portals(@table, @streams)}
      :key={entry.id}
      id={"#{entry.id}-portal"}
      target={"[id='#{entry.target}']"}
      class="contents"
    >
      <div class="sticky left-0 w-0" data-pin data-ash-data-table-portal={entry.target}>
        <div class="w-[var(--ash-data-table-view)]">
          <div
            :if={!entry.gone?}
            id={entry.id}
            class="ash-data-table"
            data-read={not is_nil(entry.page)}
          >
            <.body
              entry={entry}
              options={%{@table.options | url: nil, heading: false, mounted?: false, controlled: []}}
              time_zone={@table.caller.time_zone}
              rows={rows}
              chooser={chooser(@table, entry)}
              chooser_rows={rows(@streams, chooser(@table, entry))}
              myself={@table.options.target}
              uploads={@uploads}
              router={@table.options.router}
            />
          </div>
          <div :if={entry.gone?} id={entry.id} hidden></div>
        </div>
      </div>
    </.portal>
    """
  end

  # The uploads of the panel's file fields. A function component sees only
  # what it is given, and LiveView's uploads are not the table's to assign
  # (D5): a page that draws a table whose panel takes a file must give them.
  defp files!(entry, nil) do
    if Files.file_inputs(entry.panel) != [] do
      raise ArgumentError,
            "the action panel of the table #{inspect(entry.id)} takes a file, and " <>
              "AshDataTable.attached/1 was given no uploads: pass " <>
              "`uploads={assigns[:uploads]}` to `AshDataTable.attached`."
    end

    Files.panel_files(entry, nil)
  end

  defp files!(entry, uploads), do: Files.panel_files(entry, uploads)

  # The nested tables, parents first, each with the items of its stream:
  # a portal is rendered again only when its table or its stream changed.
  defp portals(table, streams),
    do: for(entry <- Registry.portals(table), do: {entry, streams[entry.stream]})

  # The items of a table's stream, given to its grid whenever the table
  # changes: the grid's comprehension over them is then rendered again, with
  # nothing new in it but what the stream holds, as it was while every
  # table was a component of its own (`Phoenix.LiveViewTest` keeps the rows
  # of a stream where they are only then).
  defp rows(_streams, nil), do: nil

  defp rows(streams, entry), do: streams[entry.stream]

  # The table of the entry's open picker, which is drawn in its dialog.
  defp chooser(_table, %{picker: nil}), do: nil

  defp chooser(table, %{id: id, picker: picker}),
    do: Map.get(table.entries, "#{id}-pick-#{picker.name}")

  # The markup of one table, inside its root element: the table on the
  # page's, a nested table's in its portal, a picker's table in its dialog.
  #
  # The four hooks at the end are JS files in the package, under
  # `assets/js/` (`assets/js/index.js`). LiveView writes a colocated hook
  # into `_build/ENV/phoenix-colocated/ash_data_table/`, beside a link named
  # `node_modules` that `mix.exs` points at this package's `assets`
  # (`node_modules_path`): `../node_modules/js/` is `assets/js/` of the
  # package, a path dependency's and a Hex package's alike, and the host
  # sets up nothing for it.
  attr :entry, :any, required: true
  attr :options, :any, required: true
  attr :chooser, :any, required: true
  attr :chooser_rows, :any, required: true
  attr :time_zone, :any, required: true
  attr :rows, :any, required: true
  attr :myself, :any, required: true
  attr :uploads, :any, required: true
  attr :router, :any, required: true

  defp body(assigns) do
    ~H"""
    <Parts.Heading.heading
      heading={@options.heading}
      id={@entry.id}
      label={@entry.label}
      model={@entry.model}
      myself={@myself}
      nested?={@entry.nested?}
      offered={@entry.offered}
      page={@entry.page}
      related={@entry.related}
    />
    <Parts.Related.related
      :if={@entry.related}
      id={@entry.id}
      via={@entry.related.via}
      title={@entry.related_title}
      parent={
        Routes.table(
          @router,
          @entry.related.via.source,
          @entry.related.via.source_table,
          @entry.authorize_given
        )
      }
      clear={Url.path(@options.url, @entry.id, %{})}
      create={@entry.page && @entry.model.create}
      actions={if @entry.page, do: @entry.offered, else: []}
      target={@myself}
    />
    <Parts.Arguments.argument_line
      id={@entry.id}
      lines={@entry.lines}
      model={@entry.model}
      myself={@myself}
      nested?={@entry.nested?}
      refused={@entry.refused}
      state={@entry.state}
    />
    <Parts.Filter.filter_form
      id={@entry.id}
      myself={@myself}
    />
    <Parts.Selection.selection_line
      bulk={@entry.bulk}
      choose={@entry.choose}
      id={@entry.id}
      model={@entry.model}
      myself={@myself}
      nested?={@entry.nested?}
      notice?={@entry.notice?}
      page={@entry.page}
      row_count={@entry.row_count}
      running={@entry.running}
      selecting={@entry.selecting}
      state={@entry.state}
    />
    <Parts.Messages.status
      announcement={@entry.announcement}
      announcements={@entry.announcements}
      id={@entry.id}
      result={@entry.result}
    />
    <Parts.Grid.grid
      acting?={@entry.acting?}
      open={@entry.open_label}
      asks?={:confirm not in @options.controlled}
      busy?={@entry.busy?}
      choose={@entry.choose}
      creates={@entry.creates}
      editing?={@entry.editing?}
      expandable?={@entry.expandable?}
      full_view={@entry.full_view}
      id={@entry.id}
      label={@entry.label}
      label_column={@entry.label_column}
      labelledby={@entry.labelledby}
      lead={@entry.lead}
      model={@entry.model}
      myself={@myself}
      nested?={@entry.nested?}
      page={@entry.page}
      pending={@entry.pending}
      rejected={@entry.rejected}
      row_count={@entry.row_count}
      rows={@rows}
      running={@entry.running}
      selecting={@entry.selecting}
      state={@entry.state}
      summarised?={@entry.summarised?}
      summary={@entry.summary}
      summing?={@entry.summing?}
      time_zone={@time_zone}
    />
    <Parts.Messages.whole id={@entry.id} />
    <Parts.Messages.dialog
      bulk={@entry.bulk}
      id={@entry.id}
      model={@entry.model}
    />
    <Parts.Panel.panel
      :if={@entry.panel && not match?(%{kind: :panel}, @entry.request)}
      id={@entry.id}
      panel={Present.panel(@entry.panel, Files.files_said(@entry, @uploads))}
      files={files!(@entry, @uploads)}
      target={@myself}
    />
    <%!-- After the panel, and so on top of it when both are open: a picker
      that a field of the panel has opened. --%>
    <Parts.Picker.picker
      :if={@entry.picker}
      id={@entry.id}
      picker={Present.picker(@entry.picker)}
      target={@myself}
    >
      <div
        :if={@chooser && !@chooser.gone?}
        id={@chooser.id}
        class="ash-data-table"
        data-read={not is_nil(@chooser.page)}
      >
        <.body
          entry={@chooser}
          options={%{@options | url: nil, heading: false, mounted?: false, controlled: []}}
          chooser={nil}
          chooser_rows={nil}
          time_zone={@time_zone}
          rows={@chooser_rows}
          myself={@myself}
          uploads={@uploads}
          router={@router}
        />
      </div>
      <div :if={@chooser && @chooser.gone?} id={@chooser.id} hidden></div>
    </Parts.Picker.picker>
    <Parts.Messages.messages
      error={@entry.error}
      fill={@entry.fill}
      id={@entry.id}
      loading?={@entry.loading?}
      nested?={@entry.nested?}
      row_count={@entry.row_count}
    />
    <Parts.Pagination.pagination
      :if={not @entry.nested? and Parts.Pagination.pages?(@entry.page, @entry.model)}
      id={@entry.id}
      nested?={false}
      page={@entry.page}
      model={@entry.model}
      state={@entry.state}
      row_count={@entry.row_count}
      label={@entry.label}
      target={@myself}
    />
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
