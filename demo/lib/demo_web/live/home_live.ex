defmodule DemoWeb.HomeLive do
  @moduledoc """
  The demo's front page: who you are, and the resources of the demo with what
  you, as that actor, can see of them. The tables themselves are mounted in
  the router by `ash_table`.
  """
  use DemoWeb, :live_view

  @resources [
    {Demo.Tracker.Task,
     "The main specimen: every kind of field, action, policy and field policy."},
    {Demo.Tracker.Project, "Aggregates over tasks. Its read is refused outright for nobody."},
    {Demo.Tracker.Comment, "Keyset pagination only."},
    {Demo.Tracker.Label, "No pagination."},
    {Demo.Tracker.User, "Not multitenant; filtered to your organization by policy."},
    {Demo.Tracker.Organization, "The tenant."},
    {Demo.Tracker.TaskLabel, "The join between tasks and labels."},
    {Demo.KitchenSink.Specimen, "One attribute per built-in Ash type. No tenant, open to anyone."}
  ]

  @impl true
  def mount(_params, _session, socket) do
    %{current_user: actor, current_tenant: tenant} = socket.assigns

    resources =
      for {resource, note} <- @resources do
        %{
          id: resource |> Module.split() |> Enum.join("-") |> String.downcase(),
          name: inspect(resource),
          note: note,
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
      </div>

      <div class="overflow-x-auto">
        <table id="resources" class="table table-zebra">
          <thead>
            <tr>
              <th>Resource</th>
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
