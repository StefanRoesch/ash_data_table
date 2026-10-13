defmodule DemoWeb.NamedLive do
  @moduledoc """
  Two tables of one resource on one page: the default table of the comments
  and their named table `:compact`, each placed with `AshTable.table/1`.

  Neither is given an `id`. The default table's is `comment` and the named
  table's `comment_compact`, so each has its own ids in the page and its own
  parameters in the URL, where both keep their sort, filters and page.
  """
  use DemoWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Named tables")}
  end

  @impl true
  def handle_params(_params, url, socket) do
    {:noreply, assign(socket, url: url)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-2">
        <h1 class="text-2xl font-semibold">Named tables</h1>
        <p id="named-about" class="text-base-content/70">
          A resource can have several tables. Below are two of the comments: their default
          table, and a named one, <code class="text-xs">:compact</code>, with fewer columns and
          nothing to change. Each keeps its sort, filters and page in the URL under an id of its
          own: <code class="text-xs">comment</code> and <code class="text-xs">comment_compact</code>.
        </p>
        <p id="named-mounted" class="text-base-content/70">
          A named table can be a page of its own too: the
          <.link navigate={~p"/comments/compact"} class="link">compact comments</.link>
          and the <.link navigate={~p"/tasks/board"} class="link">board of the tasks</.link>,
          whose rows expand into the compact comments and into a short table of the labels.
        </p>
      </div>

      <section id="named-default-section" aria-labelledby="comment-name">
        <AshTable.table
          resource={Demo.Tracker.Comment}
          label="Comments"
          heading={2}
          url={@url}
          actor={@current_user}
          tenant={@current_tenant}
        />
      </section>

      <section id="named-compact-section" aria-labelledby="comment_compact-name">
        <AshTable.table
          resource={Demo.Tracker.Comment}
          table={:compact}
          label="Comments, compact"
          heading={2}
          url={@url}
          actor={@current_user}
          tenant={@current_tenant}
        />
      </section>
    </Layouts.app>
    """
  end
end
