defmodule AshTable do
  @moduledoc """
  Presents an Ash resource to people as a table in Phoenix LiveView.

  A resource gets a table by listing the extension `AshTable.Resource`, and
  optionally describing the table in a `table do … end` block. The table
  reaches a page in one of two ways:

    * mounted as a page of its own, with one line in the router: see
      `AshTable.Router.ash_table/3`;
    * placed in an existing LiveView with `table/1`.

  The table offers only what the resource offers. Sorting, filtering and
  pagination run on the server through the read action; page size and default
  sort live on that action, and a person gives its arguments in a line of
  inputs above the rows. A cell is edited in place through the update
  action its column names, with the cell's value as the only input, and the
  table shows what the action returns. A row has buttons for the update and
  destroy actions the block declares, and the table a button for its create
  action; an action with inputs asks for them in the action panel. A row
  expands into the tables of its related records, each the table of its own
  resource, and a column can show a related record by its label: see
  `AshTable.Resource`.

  ## Configuration

  All of it is optional, and read while the application runs:

      config :ash_table,
        layout: {MyAppWeb.Layouts, :app},
        gettext_backend: MyAppWeb.Gettext,
        translate_error: {MyAppWeb.CoreComponents, :translate_error}

    * `:layout` - the function component a mounted table is rendered in:
      see `AshTable.Live.Page`. Without it, mounted tables are rendered bare.
    * `:gettext_backend` - the Gettext backend that translates the table's
      own texts and the labels of the resource: see `AshTable.Gettext`.
      Without it, they are in English.
    * `:translate_error` - `{module, function}` naming a function that takes
      `{message, variables}` and returns the text to show, as the
      `translate_error/1` of a Phoenix application's core components does.
      The messages of the resource's actions are given to it: those of a
      failed save, of a row action or a create that failed, and those of a
      read that failed with an error the action returned. Without it, a message is shown as the resource wrote it, with
      its variables filled in.

  `mix ash_table.install` sets all three for a new Phoenix application.
  """
  use Phoenix.Component

  @doc """
  Renders the table of a resource inside a LiveView.

      <AshTable.table id="tasks" resource={MyApp.Tracker.Task} scope={@current_scope} />

  The table reads through the resource's read action, saves through its
  update actions, and runs the row actions and the create action its block
  declares. Pass who is reading as `scope` (an `Ash.Scope`), or as
  `actor` and `tenant`; with none of them nobody is logged in. The assign
  names of `AshTable.Domain` are for mounted tables and play no part here.

  Authorization is on, unless the resource's domain says `authorize? false`
  (see `AshTable.Domain`) or the table is given `authorize?` itself, which
  wins over the domain either way.

  What the person may not see or do is left out as on a mounted table (see
  `AshTable.Live.Page`), with one difference: a table in a page of the host's
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
  (`tasks[of][project][tasks]=KEY`): see `AshTable.Live.Page`.

  The arguments of the table's read action, and those its columns ask for
  (see "Arguments" in `AshTable.Resource`), are kept with the sort and the
  filters: by the table itself, or in the `url`. A default of an asked
  argument that is a function is given `assigns`.

  A nested table links to its full view wherever the host's router mounts
  the destination's table with `AshTable.Router.ash_table/3`, also from a
  table placed here.

  ## The line of the table's name

  Above its grid the table has one line: its name at one end, and at the
  other the create button, when the resource's `table` block names a
  `create_action` that the person may run. The name is `label`.

  A table cannot know the outline of the page it is placed in, so by default
  the name is text that is no heading. `heading` says otherwise:

      <AshTable.table id="tasks" resource={MyApp.Tracker.Task} heading={2} scope={@current_scope} />

    * `true` (the default) - the name as text;
    * a number from 1 to 6 - the name as a heading of that level;
    * `false` - no name, for a page that names the table itself. The line
      then holds the create button alone, and is left out when there is
      none.

  The element of the name has the id of the table followed by `-name`, for a
  page that labels a region by it (`aria-labelledby="tasks-name"`). A table
  whose read is refused outright renders nothing, this line included.
  """
  attr :id, :string,
    required: true,
    doc: "Unique on the page. It prefixes every DOM id of the table and names its URL parameters."

  attr :resource, :atom,
    required: true,
    doc: "An Ash resource that lists the extension `AshTable.Resource`."

  attr :scope, :any, default: nil, doc: "An `Ash.Scope` carrying actor and tenant."
  attr :actor, :any, default: nil, doc: "The actor, used when no `scope` is given."
  attr :tenant, :any, default: nil, doc: "The tenant, used when no `scope` is given."

  attr :authorize?, :boolean,
    default: nil,
    doc:
      "Whether reads and saves are authorized. Defaults to the `authorize?` of the resource's domain (see `AshTable.Domain`), which is `true` unless the domain says otherwise."

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
      "How the table's name is shown on the line above it, with the create button at the other end. `true` shows it as text that is no heading, since a table cannot know the outline of the page it is in; a number from 1 to 6 makes it a heading of that level; `false` leaves it out, for a page that names the table itself."

  attr :assigns, :map,
    default: %{},
    doc:
      "What a default of an asked argument is given when it is a function (`ask :currency, default: &MyApp.Defaults.currency/1`): the assigns of the page that it looks at, such as `%{current_user: @current_user}`. A mounted table gives such a function the assigns of its socket."

  def table(assigns) do
    assigns = assign_new(assigns, :grid_label, fn -> assigns.label || label(assigns.resource) end)

    if assigns.heading not in [true, false, 1, 2, 3, 4, 5, 6] do
      raise ArgumentError,
            "the `heading` of <AshTable.table> is `true`, `false` or a heading level from 1 to 6, " <>
              "got: #{inspect(assigns.heading)}"
    end

    ~H"""
    <.live_component
      module={AshTable.Live.TableComponent}
      id={@id}
      resource={@resource}
      scope={@scope}
      actor={@actor}
      tenant={@tenant}
      authorize?={@authorize?}
      url={@url}
      label={@grid_label}
      heading={@heading}
      mounted?={false}
      page_assigns={@assigns}
    />
    """
  end

  @doc """
  The name of a resource's table for people: its `plural_name` when the
  resource has one, else its short name, humanised. It is translated like a
  column label (see `AshTable.Gettext`).
  """
  @spec label(Ash.Resource.t()) :: String.t()
  def label(resource) do
    (Ash.Resource.Info.plural_name(resource) || Ash.Resource.Info.short_name(resource))
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
    |> AshTable.Text.label()
  end
end
