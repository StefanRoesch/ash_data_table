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
  sort live on that action. A cell is edited in place through the update
  action its column names, with the cell's value as the only input, and the
  table shows what the action returns. A row expands into the tables of its
  related records, each the table of its own resource, and a column can show
  a related record by its label: see `AshTable.Resource`.

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
      failed save, and those of a read that failed with an error the action
      returned. Without it, a message is shown as the resource wrote it, with
      its variables filled in.

  `mix ash_table.install` sets all three for a new Phoenix application.
  """
  use Phoenix.Component

  @doc """
  Renders the table of a resource inside a LiveView.

      <AshTable.table id="tasks" resource={MyApp.Tracker.Task} scope={@current_scope} />

  The table reads through the resource's read action, and saves through its
  update actions. Pass who is reading as `scope` (an `Ash.Scope`), or as
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

  A nested table links to its full view wherever the host's router mounts
  the destination's table with `AshTable.Router.ash_table/3`, also from a
  table placed here.
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
    doc: "The accessible name of the grid. Defaults to the humanised name of the resource."

  def table(assigns) do
    assigns = assign_new(assigns, :grid_label, fn -> assigns.label || label(assigns.resource) end)

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
      mounted?={false}
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
