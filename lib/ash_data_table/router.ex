defmodule AshDataTable.Router do
  @moduledoc """
  Mounts tables in a Phoenix router.

      import AshDataTable.Router

      scope "/", MyAppWeb do
        pipe_through :browser

        live_session :default, on_mount: [{MyAppWeb.UserAuth, :mount_current_scope}] do
          ash_data_table "/tasks", MyApp.Tracker.Task
          ash_data_table "/projects", MyApp.Tracker.Project
          ash_data_table "/tasks/board", MyApp.Tracker.Task, table: :board
        end
      end
  """

  @doc """
  Mounts a table of `resource` at `path`: its default table, or the named
  table that `table:` names.

  Expands to a `live` route for `AshDataTable.Live.Page`. The route sits in
  whichever scope, pipeline and live session surround it, renders in the
  host's layout, and takes actor and tenant from the socket assigns the host's
  `on_mount` hooks set (see `AshDataTable.Live.Page`).

  The resource is written in full; an alias of the surrounding `scope` is not
  applied to it.

  A mounted table is also where the nested tables of that resource are
  opened in their full view: a nested table links to the first route, in the
  router's order, that mounts the same table of its resource at a path
  without parameters. A nested table that shows a named table links to a
  page of that named table, and has no link when none is mounted. See
  `AshDataTable.Live.Page`.

  ## Options

    * `:table` - the name of the table that is mounted: one of the
      resource's named tables (a `table` of its `tables` block), such as
      `:compact`. Left out, or `:default`, it is the resource's default
      table, the one of its `table` block. The router does not look at the
      resource, so a name the resource has no table for is an error when the
      page is opened, which lists the resource's tables.

    * `:id` - the table's id, a string. It prefixes the DOM ids of the table
      and names its URL parameters (`?task[sort]=title`). Defaults to the last
      part of the resource's module name, underscored: `"task"` for
      `MyApp.Tracker.Task`; for a named table, followed by `_` and the
      table's name: `"task_board"`. It must be unique among the tables of a
      page.

    * `:layout` - the layout the page is rendered in: `{module, function}`
      naming a function component, such as `{MyAppWeb.Layouts, :app}`, or
      `false` for none. Defaults to `config :ash_data_table, layout: …`, and to
      none when that is not set. See `AshDataTable.Live.Page`.

    * `:authorize?` - `false` mounts the table without authorization: every
      read and every action it runs for this page is given
      `authorize?: false`, as the same option does in `Ash.read/2`. `true`
      authorizes whatever the domain says. Left out, the table authorizes as
      the resource's domain says (`AshDataTable.Domain`), which is `true` unless
      the domain says otherwise. Written in the router, and taken from
      nowhere else. See "Without authorization" below.

    * `:notify`, `:open`, `:kit`, `:presentation`, `:look`, `:context`, `:private_arguments`,
      `:page_arguments`, `:before_action` - as the options of
      `AshDataTable.attach/4`, written so that a route can hold them: a
      function as `{module, function}`, called as `function(assigns,
      table_ref)` (`before_action`: `function(request, assigns)`), else a
      literal map. The events reach the host's `on_mount` hooks of the
      `live_session`, which hear them with an `attach_hook/4` on
      `:handle_info` and may give the table, `:table`, commands there. See
      `AshDataTable.Live.Page`.

    * `:live?` - `false` mounts the table without live updates: it does not
      follow what others change, and neither do the tables nested in its
      rows and its pickers. `true` says that it has to follow them, and is
      an error when the page is opened for a resource that announces none.
      Left out, the table follows them where the resource's `table` block
      says `live? true`. See the guide "Live updates".

  ## Without authorization

      scope "/admin", MyAppWeb do
        pipe_through [:browser, :require_admin]

        live_session :admin, on_mount: [{MyAppWeb.UserAuth, :require_admin}] do
          ash_data_table "/tasks", MyApp.Tracker.Task, id: "admin-task", authorize?: false
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
  @page [:notify, :open, :kit, :presentation, :look, :context, :private_arguments] ++
          [:page_arguments, :before_action]

  defmacro ash_data_table(path, resource, opts \\ []) do
    # As Phoenix does for the modules named in routes: expanding the alias as
    # if inside a function keeps the router from depending on the resource at
    # compile time.
    resource = Macro.expand(resource, %{__CALLER__ | function: {:ash_data_table, 3}})

    quote bind_quoted: [path: path, resource: resource, opts: opts] do
      live_opts = AshDataTable.Router.__live_opts__(resource, opts)

      # `alias: false` keeps the surrounding scope's alias off our LiveView.
      scope path, alias: false, as: false do
        Phoenix.LiveView.Router.live("/", AshDataTable.Live.Page, :table, live_opts)
      end
    end
  end

  @doc false
  def __live_opts__(resource, opts) do
    if not is_atom(resource) do
      raise ArgumentError,
            "ash_data_table expects a resource module as its second argument, got: #{inspect(resource)}"
    end

    case Keyword.keys(opts) -- ([:id, :layout, :authorize?, :table, :live?] ++ @page) do
      [] -> :ok
      unknown -> raise ArgumentError, "unknown options for ash_data_table: #{inspect(unknown)}"
    end

    # nil and `:default` both name the default table
    table = Keyword.get(opts, :table) || :default

    if table != :default and not AshDataTable.Resource.Verifiers.VerifyTables.name?(table) do
      raise ArgumentError,
            "the :table of ash_data_table must be the name of a table of the resource, an atom such " <>
              "as `:compact`, or `:default` for its default table, got: #{inspect(opts[:table])}"
    end

    id = Keyword.get_lazy(opts, :id, fn -> AshDataTable.Routes.default_id(resource, table) end)

    if not (is_binary(id) and id =~ ~r/\A[a-z][a-z0-9_-]*\z/) do
      raise ArgumentError,
            "the :id of ash_data_table must be a string of lower-case letters, digits, `_` and `-` " <>
              "that starts with a letter, got: #{inspect(id)}"
    end

    # `:default` leaves the choice to the application's configuration, which
    # is read when the page is rendered.
    layout = Keyword.get(opts, :layout, :default)

    if not match?({module, function} when is_atom(module) and is_atom(function), layout) and
         layout not in [false, :default] do
      raise ArgumentError,
            "the :layout of ash_data_table must be {module, function} naming a function component, " <>
              "or false, got: #{inspect(layout)}"
    end

    # nil leaves it to the resource's domain, which is asked when the page
    # is rendered
    authorize? = Keyword.get(opts, :authorize?)

    if authorize? not in [nil, true, false] do
      raise ArgumentError,
            "the :authorize? of ash_data_table must be `true` or `false`, got: #{inspect(authorize?)}"
    end

    # nil leaves it to the resource, which is asked when the page is rendered
    live? = Keyword.get(opts, :live?)

    if live? not in [nil, true, false] do
      raise ArgumentError,
            "the :live? of ash_data_table must be `true` or `false`, got: #{inspect(live?)}"
    end

    page =
      for name <- @page,
          Keyword.has_key?(opts, name),
          into: %{},
          do: {name, page!(name, opts[name])}

    [
      # only used by hosts that still generate route helpers
      as: String.to_atom("ash_data_table_" <> String.replace(id, "-", "_")),
      metadata: %{
        ash_data_table:
          %{
            resource: resource,
            table: table,
            id: id,
            layout: layout,
            authorize?: authorize?,
            live?: live?
          }
          |> Map.merge(page)
      }
    ]
  end

  # What the page gives its table and hears of it, as a route can
  # hold it: a literal, or `{module, function}` for a function, which the
  # page calls as `attach/4` calls its own.
  defp page!(:notify, notify) when notify == true or is_list(notify) do
    for name <- List.wrap(notify), name != true, name not in AshDataTable.Event.names() do
      raise ArgumentError,
            "the :notify of ash_data_table names #{inspect(name)}, which is no event of a table. " <>
              "They are: #{inspect(AshDataTable.Event.names())}"
    end

    notify
  end

  defp page!(:open, label) when is_binary(label), do: label

  # a module, which `AshDataTable.attach/4` checks: it may not be compiled yet
  defp page!(:kit, kit) when is_atom(kit) and not is_nil(kit), do: kit

  # a list, which `AshDataTable.attach/4` checks
  defp page!(:presentation, presentation) when is_list(presentation), do: presentation

  # the look, checked here as `AshDataTable.attach/4` checks it
  defp page!(:look, look), do: AshDataTable.Kit.look!(look, "ash_data_table")

  defp page!(:before_action, {module, function} = mf) when is_atom(module) and is_atom(function),
    do: mf

  defp page!(name, {module, function} = mf)
       when name in [:context, :private_arguments, :page_arguments] and is_atom(module) and
              is_atom(function),
       do: mf

  defp page!(name, %{} = map) when name in [:context, :private_arguments, :page_arguments],
    do: map

  defp page!(name, value) do
    shape =
      case name do
        :notify -> "`true` or a list of events"
        :open -> "the label of its button, a string"
        :kit -> "a module that uses AshDataTable.Kit"
        :presentation -> "a list such as [panel: :inline]"
        :before_action -> "{module, function}"
        _value -> "a map, or {module, function}"
      end

    raise ArgumentError,
          "the :#{name} of ash_data_table must be #{shape}, got: #{inspect(value)}"
  end
end
