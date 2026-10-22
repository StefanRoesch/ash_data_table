defmodule DemoWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use DemoWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is invoked from every template of the demo itself. The
  page header (navigation and the actor switcher) and the main landmark are
  in the root layout instead, so that they also surround LiveViews mounted
  by a library.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :time_zone, :string,
    default: nil,
    doc:
      "the zone the tables show datetimes in (`DemoWeb.Zone`), said above the page unless it is UTC"

  slot :inner_block, required: true

  slot :same_table,
    doc: "a link to the same table drawn by the other kit, above the page (`tasks/1`)"

  def app(assigns) do
    ~H"""
    <div id="app-layout" class="px-4 py-8 sm:px-6 lg:px-8">
      <%!-- the whole width of the window: tables have many columns --%>
      <div class="space-y-6">
        <p :if={@same_table != []} id="same-table" class="text-sm">
          {render_slot(@same_table)}
        </p>
        <%!-- A table states no zone in its cells: the page says it once,
        where it is not UTC (in UTC the page looks as it did before). --%>
        <p
          :if={@time_zone not in [nil, "UTC", "Etc/UTC"]}
          id="time-zone"
          class="text-sm text-base-content/70"
        >
          Times in {@time_zone}
        </p>
        {render_slot(@inner_block)}
      </div>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  The layout of /tasks (`ash_data_table "/tasks", Task, layout: …`): the app
  layout with a link to the same table drawn by the React kit
  (`DemoWeb.ReactTasksLive`), which links back. The link keeps the query of
  the page's URL (`current_path`, which the router's page gives its
  layout): both tables have the id "task", so the sort, filters and page
  carry over.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :time_zone, :string, default: nil, doc: "as `app/1` takes it"

  attr :current_path, :string,
    default: nil,
    doc: "the page's path and query, as the router's page gives it"

  slot :inner_block, required: true

  def tasks(assigns) do
    ~H"""
    <.app flash={@flash} time_zone={@time_zone}>
      <:same_table>
        <.link navigate={same_query(~p"/react/tasks", @current_path)} class="link">
          {gettext("The same table in React")}
        </.link>
      </:same_table>
      {render_slot(@inner_block)}
    </.app>
    """
  end

  @doc """
  `path` with the query of `current` (a path with its query, or a URL; nil
  for none): a link to the same table drawn by the other kit, /tasks and
  /react/tasks, whose tables both have the id "task", so that the sort,
  filters and page carry over.
  """
  @spec same_query(String.t(), String.t() | nil) :: String.t()
  def same_query(path, current) do
    case current && URI.parse(current).query do
      nil -> path
      query -> path <> "?" <> query
    end
  end

  @doc """
  The dev-only actor switcher: a form that posts the chosen user id to
  `DemoWeb.ActorController`, which stores it in the session.
  """
  attr :current_user, :any, default: nil
  attr :return_to, :string, default: nil

  def actor_switcher(assigns) do
    assigns =
      assign(assigns,
        actors: Demo.Actors.users(),
        fixed?:
          is_nil(assigns.current_user) or
            assigns.current_user.id in Enum.map(Demo.Actors.users(), & &1.id)
      )

    ~H"""
    <%!-- The root layout is not re-rendered on live navigation, so the form
    takes the current URL when it is submitted (`data-return-to-current`,
    assets/js/page.js). --%>
    <form
      id="actor-switcher"
      action={~p"/actor"}
      method="post"
      class="flex items-center gap-2"
      data-return-to-current
    >
      <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
      <input type="hidden" name="return_to" value={@return_to || "/"} />
      <label for="actor-switcher-select" class="text-sm">Acting as</label>
      <select
        id="actor-switcher-select"
        name="actor"
        class="select select-sm w-auto"
        data-submit-on-change
      >
        <option
          :for={actor <- @actors}
          value={actor.id}
          selected={@current_user && @current_user.id == actor.id}
        >
          {actor.name} · {actor.role} · {actor.organization}
        </option>
        <option :if={!@fixed?} value={@current_user.id} selected>
          {@current_user.name} · {@current_user.role}
        </option>
        <option value="" selected={is_nil(@current_user)}>Nobody · not logged in</option>
      </select>
      <button type="submit" class="btn btn-sm">Switch</button>
    </form>
    """
  end

  @doc """
  The language switcher: a form that posts the chosen locale to
  `DemoWeb.LocaleController`, which stores it in the session. Only the tables,
  the sprint planner and the links between /tasks and /react/tasks are
  translated.
  """
  attr :return_to, :string, default: nil

  def locale_switcher(assigns) do
    assigns =
      assign(assigns, locales: DemoWeb.Locale.locales(), current: DemoWeb.Locale.current())

    ~H"""
    <form
      id="locale-switcher"
      action={~p"/locale"}
      method="post"
      class="flex items-center gap-2"
      data-return-to-current
    >
      <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
      <input type="hidden" name="return_to" value={@return_to || "/"} />
      <label for="locale-switcher-select" class="text-sm">Language</label>
      <select
        id="locale-switcher-select"
        name="locale"
        class="select select-sm w-auto"
        data-submit-on-change
      >
        <option
          :for={{locale, name} <- @locales}
          value={locale}
          lang={locale}
          selected={locale == @current}
        >
          {name}
        </option>
      </select>
    </form>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        type="button"
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        aria-label="Use the system theme"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        type="button"
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        aria-label="Use the light theme"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        type="button"
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        aria-label="Use the dark theme"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
