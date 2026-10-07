defmodule DemoWeb.HomeLive do
  @moduledoc """
  The demo's front page: who you are, and the resources of the demo with what
  you, as that actor, can see of them, and links to the tables that
  `ash_table` mounts in the router.
  """
  use DemoWeb, :live_view

  # {resource, note, the paths its table is mounted at with what each shows}
  @resources [
    {Demo.Tracker.Task,
     "The main specimen: every kind of field, action, policy and field policy.",
     [
       {"/tasks",
        "declared columns, offset pages, sortable aggregate and calculation; " <>
          "columns and editing differ by who you are. A row expands into seven declared " <>
          "relationships of every kind, three levels deep; a viewer has no line for people. " <>
          "Four row actions (one runs at once, two open the action panel, the delete asks " <>
          "first) and \"New task\", for admins and members; a member's are refused on tasks " <>
          "that are not theirs, and a viewer has none"}
     ]},
    {Demo.Tracker.Project, "Aggregates over tasks. Its read is refused outright for nobody.",
     [
       {"/projects",
        "no column declared: the default columns, edited in place by admins and members; " <>
          "for nobody, a page that does not exist. " <>
          "A row expands into its tasks: the one relationship it offers by default, with " <>
          "\"New task\" on its line. \"Set status\" for admins and members; \"Destroy\" " <>
          "and \"New project\" for admins"}
     ]},
    {Demo.Tracker.Comment, "Keyset pagination only. Its read is refused outright for nobody.",
     [
       {"/comments",
        "keyset pages: next and previous; the body is edited in place by admins and by " <>
          "its author; for nobody, a message (on_forbidden). " <>
          "A row expands into its task and its author. \"Destroy\", which asks first and " <>
          "is refused on a comment that is not yours, and \"New comment\", for admins and " <>
          "members"}
     ]},
    {Demo.Tracker.Label, "No pagination.",
     [
       {"/labels",
        "no pagination: every record, edited in place by admins. A row expands into its " <>
          "tasks. \"Destroy\" and \"New label\" for admins; nobody else has an actions column"},
       {"/bare/labels", "the same, mounted without the app layout"}
     ]},
    {Demo.Tracker.User,
     "Not multitenant; filtered to your organization by policy, and refused outright for a " <>
       "viewer. Its table is mounted nowhere: it is seen nested, under a task or a comment, " <>
       "and its rows never expand (max_depth 0). The demo's one read-only table: it names " <>
       "no update action.", []},
    {Demo.Tracker.Organization, "The tenant.", []},
    {Demo.Tracker.TaskLabel, "The join between tasks and labels.",
     [
       {"/task_labels",
        "a key of two attributes. A row expands into its task and its label, and no " <>
          "further (max_depth 1). \"Remove\" deletes the link at one click (confirm " <>
          "false); \"New task label\" takes the two keys"}
     ]},
    {Demo.KitchenSink.Specimen, "One attribute per built-in Ash type. No tenant, open to anyone.",
     [{"/specimens", "no table block: how every type is shown"}]}
  ]

  @impl true
  def mount(_params, _session, socket) do
    %{current_user: actor, current_tenant: tenant} = socket.assigns

    resources =
      for {resource, note, tables} <- @resources do
        %{
          id: resource |> Module.split() |> Enum.join("-") |> String.downcase(),
          name: inspect(resource),
          note: note,
          tables: tables,
          visible: visible(resource, actor, tenant),
          reads: read_actions(resource),
          fields: length(Ash.Resource.Info.public_attributes(resource))
        }
      end

    {:ok, assign(socket, page_title: "Home", resources: resources)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-2">
        <h1 class="text-2xl font-semibold">ash_table demo</h1>
        <p id="whoami" class="text-base-content/70">
          <span :if={@current_user}>
            You are <strong>{@current_user.name}</strong>
            ({@current_user.email}, {@current_user.role}); the tenant is your organization, <code class="text-xs">{@current_tenant}</code>.
          </span>
          <span :if={!@current_user}>
            You are <strong>nobody</strong>: not logged in, no tenant.
          </span>
          Change it with the switcher at the top right.
        </p>
        <p id="embedded" class="text-base-content/70">
          Every table below is a page of its own. The
          <.link navigate={~p"/dashboard"} class="link">dashboard</.link>
          shows two tables placed in a LiveView of the demo's own.
        </p>
        <p id="nesting" class="text-base-content/70">
          Rows expand: the mark at the start of a row shows one line per relationship, and a
          line opens the table of the related records inside the row, with its own sort,
          filters, pages and editing.
        </p>
        <p id="acting" class="text-base-content/70">
          Rows have buttons: the last column of a table holds the actions its resource
          declares for it, and the button on the line of a table's name creates a record. An
          action with inputs asks for them in a panel first. Which buttons you have depends
          on who you are: a viewer has none.
        </p>
      </div>

      <div class="overflow-x-auto">
        <table id="resources" class="table table-zebra">
          <thead>
            <tr>
              <th>Resource</th>
              <th>Table</th>
              <th>Records you can see</th>
              <th>Public attributes</th>
              <th>Read actions</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={resource <- @resources} id={"resource-#{resource.id}"}>
              <td>
                <div class="font-mono text-sm">{resource.name}</div>
                <div class="text-xs text-base-content/70">{resource.note}</div>
              </td>
              <td>
                <div :for={{path, shows} <- resource.tables} class="text-sm">
                  <.link navigate={path} class="link font-mono">{path}</.link>
                  <div class="text-xs text-base-content/70">{shows}</div>
                </div>
              </td>
              <td data-role="visible">{resource.visible}</td>
              <td>{resource.fields}</td>
              <td>
                <div :for={read <- resource.reads} class="text-xs">
                  <span class="font-mono">{read.name}</span>: {read.pagination}
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </Layouts.app>
    """
  end

  defp visible(resource, actor, tenant) do
    case Ash.count(resource, actor: actor, tenant: tenant) do
      {:ok, count} -> Integer.to_string(count)
      {:error, %Ash.Error.Forbidden{}} -> "not allowed"
      {:error, _} -> "error"
    end
  end

  defp read_actions(resource) do
    for action <- Ash.Resource.Info.actions(resource), action.type == :read do
      %{name: action.name, pagination: describe_pagination(action.pagination)}
    end
  end

  defp describe_pagination(false), do: "no pagination"

  defp describe_pagination(pagination) do
    kinds =
      [pagination.offset? && "offset", pagination.keyset? && "keyset"]
      |> Enum.filter(& &1)
      |> Enum.join(" and ")

    size = if pagination.default_limit, do: ", #{pagination.default_limit} per page", else: ""
    count = if pagination.countable, do: ", countable", else: ""
    kinds <> size <> count
  end
end
