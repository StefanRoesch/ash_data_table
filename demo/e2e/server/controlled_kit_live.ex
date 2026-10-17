defmodule DemoWeb.E2E.ControlledKitLive do
  @moduledoc """
  A page for the browser tests of controlled mode widened (the design note
  of stage 7, D17, test group AB): a table of `AshDataTable.Test.Resource`
  attached with `controlled: [:confirm, :picker]`. The page draws the
  questions (of a column before a save, of a reference cell before a
  choice) and the picker of the owner's cell itself, of the table and of
  the table of parts nested in its row, from `AshDataTable.requests/1`
  (the first one held), and answers with `confirm_request/3`,
  `pick_request/4` and `cancel_request/3`. The records are kept in memory,
  in a tenant of the page's own, made as it mounts. Compiled and routed in
  the e2e environment only.
  """
  use DemoWeb, :live_view

  alias AshDataTable.Test.Resource

  @impl true
  def mount(_params, _session, socket) do
    tenant = "e2e-controlled-#{System.unique_integer([:positive])}"
    if connected?(socket), do: seed(tenant)

    {:ok,
     socket
     |> assign(page_title: "What the page draws", tenant: tenant)
     |> AshDataTable.attach(:table, Resource,
       id: "kit",
       tenant: tenant,
       controlled: [:confirm, :picker]
     )}
  end

  defp seed(tenant) do
    opts = [tenant: tenant, authorize?: false]
    Ash.create!(Resource.Owner, %{name: "Ann"}, opts)
    Ash.create!(Resource.Owner, %{name: "Bob"}, opts)
    anchor = Ash.create!(Resource, %{name: "Anchor", note: "first", owner_id: "Ann"}, opts)
    Ash.create!(Resource.Part, %{title: "Pin", resource_id: anchor.id, owner_id: "Ann"}, opts)
  end

  @impl true
  def handle_event("confirm", _params, socket),
    do: {:noreply, by_request(socket, &AshDataTable.confirm_request(&1, :table, &2))}

  def handle_event("cancel", _params, socket),
    do: {:noreply, by_request(socket, &AshDataTable.cancel_request(&1, :table, &2))}

  def handle_event("pick", %{"key" => key}, socket),
    do: {:noreply, by_request(socket, &AshDataTable.pick_request(&1, :table, &2, key))}

  defp by_request(socket, fun) do
    case List.first(AshDataTable.requests(socket.assigns.table)) do
      %{ref: ref} -> fun.(socket, ref)
      nil -> socket
    end
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        request: List.first(AshDataTable.requests(assigns.table)),
        owners:
          Ash.read!(Resource.Owner, tenant: assigns.tenant, authorize?: false)
          |> Enum.sort_by(& &1.name)
      )

    ~H"""
    <div class="p-4">
      <h1 class="mb-4 text-lg font-semibold">What the page draws</h1>
      <AshDataTable.attached table={@table} streams={@streams} uploads={assigns[:uploads]} />
      <section
        :if={match?(%{kind: :confirm}, @request)}
        id="host-question"
        role="region"
        aria-labelledby="host-question-text"
        class="mt-4 rounded border p-4"
      >
        <p id="host-question-text">{@request.question}</p>
        <button id="host-cancel" type="button" class="btn btn-sm" phx-click="cancel">
          Cancel
        </button>
        <button id="host-confirm" type="button" class="btn btn-sm btn-primary" phx-click="confirm">
          Confirm
        </button>
      </section>
      <section
        :if={match?(%{kind: :picker}, @request)}
        id="host-picker"
        role="region"
        aria-labelledby="host-picker-title"
        class="mt-4 rounded border p-4"
      >
        <h2 id="host-picker-title">{@request.title}</h2>
        <button
          :for={owner <- @owners}
          id={"host-pick-#{owner.name}"}
          type="button"
          class="btn btn-sm"
          phx-click="pick"
          phx-value-key={owner.name}
        >
          {owner.name}
        </button>
        <button id="host-picker-cancel" type="button" class="btn btn-sm" phx-click="cancel">
          Cancel
        </button>
      </section>
    </div>
    """
  end
end
