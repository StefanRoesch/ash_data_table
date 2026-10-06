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
  sort live on that action.
  """
  use Phoenix.Component

  @doc """
  Renders the table of a resource inside a LiveView.

      <AshTable.table id="tasks" resource={MyApp.Tracker.Task} scope={@current_scope} />

  The table reads through the resource's read action with authorization on.
  Pass who is reading as `scope` (an `Ash.Scope`), or as `actor` and `tenant`.

  The table keeps its sort, filters and page itself. To keep them in the
  page's URL instead, so that reload, the back button and shared links work,
  pass the current URL as `url` (the second argument of
  `c:Phoenix.LiveView.handle_params/3`, assigned by the LiveView). The table
  then patches the URL, with its parameters under its `id`:
  `?tasks[sort]=-title&tasks[f][title]=report&tasks[page]=2`. Other parameters
  of the page are left as they are.
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
  attr :authorize?, :boolean, default: true, doc: "Whether reads are authorized."

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
    />
    """
  end

  @doc """
  The name of a resource's table for people: its `plural_name` when the
  resource has one, else its short name, humanised.
  """
  @spec label(Ash.Resource.t()) :: String.t()
  def label(resource) do
    (Ash.Resource.Info.plural_name(resource) || Ash.Resource.Info.short_name(resource))
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
