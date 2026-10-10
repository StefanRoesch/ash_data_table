defmodule AshTable.Router do
  @moduledoc """
  Mounts tables in a Phoenix router.

      import AshTable.Router

      scope "/", MyAppWeb do
        pipe_through :browser

        live_session :default, on_mount: [{MyAppWeb.UserAuth, :mount_current_scope}] do
          ash_table "/tasks", MyApp.Tracker.Task
          ash_table "/projects", MyApp.Tracker.Project
        end
      end
  """

  @doc """
  Mounts the table of `resource` at `path`.

  Expands to a `live` route for `AshTable.Live.Page`. The route sits in
  whichever scope, pipeline and live session surround it, renders in the
  host's layout, and takes actor and tenant from the socket assigns the host's
  `on_mount` hooks set (see `AshTable.Live.Page`).

  The resource is written in full; an alias of the surrounding `scope` is not
  applied to it.

  A mounted table is also where the nested tables of that resource are
  opened in their full view: a nested table links to the first route, in the
  router's order, that mounts its resource at a path without parameters. See
  `AshTable.Live.Page`.

  ## Options

    * `:id` - the table's id, a string. It prefixes the DOM ids of the table
      and names its URL parameters (`?task[sort]=title`). Defaults to the last
      part of the resource's module name, underscored: `"task"` for
      `MyApp.Tracker.Task`. It must be unique among the tables of a page.

    * `:layout` - the layout the page is rendered in: `{module, function}`
      naming a function component, such as `{MyAppWeb.Layouts, :app}`, or
      `false` for none. Defaults to `config :ash_table, layout: …`, and to
      none when that is not set. See `AshTable.Live.Page`.

    * `:authorize?` - `false` mounts the table without authorization: every
      read and every action it runs for this page is given
      `authorize?: false`, as the same option does in `Ash.read/2`. `true`
      authorizes whatever the domain says. Left out, the table authorizes as
      the resource's domain says (`AshTable.Domain`), which is `true` unless
      the domain says otherwise. Written in the router, and taken from
      nowhere else. See "Without authorization" below.

  ## Without authorization

      scope "/admin", MyAppWeb do
        pipe_through [:browser, :require_admin]

        live_session :admin, on_mount: [{MyAppWeb.UserAuth, :require_admin}] do
          ash_table "/tasks", MyApp.Tracker.Task, id: "admin-task", authorize?: false
        end
      end

  > #### `authorize?: false` removes every check {: .warning}
  >
  > A page mounted this way asks Ash nothing: no policy and no field policy
  > is applied. Whoever can open the page reads every record of the
  > resource, sees every public field, and runs every action the table
  > offers, on every record. So do the tables nested in its rows and its
  > pickers.
  >
  > Use it only for a page that your own code already keeps people away
  > from: an admin area behind a pipeline and an `on_mount` hook that let
  > only administrators in. Never for a page that anybody can reach.

  What stays as it is: only `public?` fields are columns and only `public?`
  actions run, the actor and the tenant are still passed on (a change that
  reads `actor` still finds it, and a multitenant resource still needs its
  tenant), and a sensitive column is still masked.

  A nested table links to its full view only on a page that is mounted the
  same way: a table without authorization never sends a person to a page
  that authorizes, where they would see other records, and a table that
  authorizes never links to a page without.
  """
  defmacro ash_table(path, resource, opts \\ []) do
    # As Phoenix does for the modules named in routes: expanding the alias as
    # if inside a function keeps the router from depending on the resource at
    # compile time.
    resource = Macro.expand(resource, %{__CALLER__ | function: {:ash_table, 3}})

    quote bind_quoted: [path: path, resource: resource, opts: opts] do
      live_opts = AshTable.Router.__live_opts__(resource, opts)

      # `alias: false` keeps the surrounding scope's alias off our LiveView.
      scope path, alias: false, as: false do
        Phoenix.LiveView.Router.live("/", AshTable.Live.Page, :table, live_opts)
      end
    end
  end

  @doc false
  def __live_opts__(resource, opts) do
    if not is_atom(resource) do
      raise ArgumentError,
            "ash_table expects a resource module as its second argument, got: #{inspect(resource)}"
    end

    case Keyword.keys(opts) -- [:id, :layout, :authorize?] do
      [] -> :ok
      unknown -> raise ArgumentError, "unknown options for ash_table: #{inspect(unknown)}"
    end

    id = Keyword.get_lazy(opts, :id, fn -> default_id(resource) end)

    if not (is_binary(id) and id =~ ~r/\A[a-z][a-z0-9_-]*\z/) do
      raise ArgumentError,
            "the :id of ash_table must be a string of lower-case letters, digits, `_` and `-` " <>
              "that starts with a letter, got: #{inspect(id)}"
    end

    # `:default` leaves the choice to the application's configuration, which
    # is read when the page is rendered.
    layout = Keyword.get(opts, :layout, :default)

    if not match?({module, function} when is_atom(module) and is_atom(function), layout) and
         layout not in [false, :default] do
      raise ArgumentError,
            "the :layout of ash_table must be {module, function} naming a function component, " <>
              "or false, got: #{inspect(layout)}"
    end

    # nil leaves it to the resource's domain, which is asked when the page
    # is rendered
    authorize? = Keyword.get(opts, :authorize?)

    if authorize? not in [nil, true, false] do
      raise ArgumentError,
            "the :authorize? of ash_table must be `true` or `false`, got: #{inspect(authorize?)}"
    end

    [
      # only used by hosts that still generate route helpers
      as: String.to_atom("ash_table_" <> String.replace(id, "-", "_")),
      metadata: %{
        ash_table: %{resource: resource, id: id, layout: layout, authorize?: authorize?}
      }
    ]
  end

  defp default_id(resource) do
    resource |> Module.split() |> List.last() |> Macro.underscore()
  end
end
